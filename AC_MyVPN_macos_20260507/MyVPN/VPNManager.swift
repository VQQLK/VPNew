import Foundation
import AppKit
import UniformTypeIdentifiers

// ============================================================
//  VPNManager — macOS, Xray-core VLESS+XTLS-Reality
//
//  Запускает xray как фоновый процесс.
//  Xray создаёт SOCKS5 на 127.0.0.1:10808 и HTTP на 10809.
//  После запуска выставляет системный прокси macOS через networksetup.
//
//  Требования:
//    brew install xray          → /opt/homebrew/bin/xray (Apple Silicon)
//                               → /usr/local/bin/xray   (Intel)
//    Или скачать напрямую:
//    https://github.com/XTLS/Xray-core/releases → Xray-macos-arm64-v8a.zip
// ============================================================

@MainActor
class VPNManager: ObservableObject {

    static let shared = VPNManager()

    @Published var isConnected  = false
    @Published var statusText   = "○  Отключено"
    @Published var statusColor  = "#8B949E"
    @Published var publicIP     = ""
    @Published var logText      = ""

    private let appSupportDir: URL
    private var xrayProcess: Process?

    // Ищем xray в стандартных путях Homebrew и прямой установки
    private var xrayPath: String {
        let paths = [
            "/opt/homebrew/bin/xray",    // Homebrew Apple Silicon
            "/usr/local/bin/xray",       // Homebrew Intel
            "/usr/local/sbin/xray",
            Bundle.main.bundlePath + "/Contents/MacOS/xray"  // xray внутри .app
        ]
        return paths.first { FileManager.default.fileExists(atPath: $0) } ?? paths[0]
    }

    private init() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyVPN", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        appSupportDir = dir
    }

    // ── Переключение ─────────────────────────────────────────
    func toggleVPN() {
        isConnected ? Task { await disconnect() } : Task { await connect() }
    }

    // ── Импорт client_config.json ────────────────────────────
    func importConfig() {
        let panel = NSOpenPanel()
        panel.title = "Выберите client_config.json"
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles      = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Валидируем JSON
        do {
            let data = try Data(contentsOf: url)
            _ = try JSONSerialization.jsonObject(with: data)
            let dest = appSupportDir.appendingPathComponent("config.json")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: url, to: dest)
            appendLog("Конфиг импортирован: \(url.lastPathComponent)")
        } catch {
            appendLog("Ошибка: невалидный JSON — \(error.localizedDescription)")
        }
    }

    // ── Подключение ──────────────────────────────────────────
    private func connect() async {
        let configURL = appSupportDir.appendingPathComponent("config.json")
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            appendLog("⚠ Конфиг не найден. Импортируйте client_config.json.")
            return
        }
        guard FileManager.default.fileExists(atPath: xrayPath) else {
            appendLog("⚠ xray не найден. Установите: brew install xray")
            showInstallAlert()
            return
        }

        setStatus("⟳  Подключение…", "#F0E68C")
        appendLog("Запускаем xray [\(xrayPath)]...")

        // Запускаем xray напрямую (не через sudo — xray не требует root на macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: xrayPath)
        process.arguments     = ["run", "-c", configURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

        // Читаем stdout/stderr xray в фоне (не блокируем MainActor)
        pipe.fileHandleForReading.readabilityHandler = { [weak self] fh in
            let data = fh.availableData
            guard !data.isEmpty,
                  let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.appendLog(text)
            }
        }

        do {
            try process.run()
        } catch {
            setStatus("○  Ошибка", "#DA3633")
            appendLog("Не удалось запустить xray: \(error.localizedDescription)")
            return
        }

        xrayProcess = process

        // Ждём 2 сек, проверяем что xray жив
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        guard !process.isTerminated else {
            setStatus("○  Ошибка", "#DA3633")
            appendLog("xray завершился. Проверьте конфиг.")
            xrayProcess = nil
            return
        }

        // Выставляем системный SOCKS5-прокси (не требует root на macOS)
        await setSystemProxy(enable: true)

        isConnected = true
        setStatus("●  VLESS+Reality", "#3FB950")
        appendLog("Xray запущен. SOCKS5: 127.0.0.1:10808")
        await fetchPublicIP()
    }

    // ── Отключение ───────────────────────────────────────────
    private func disconnect() async {
        await setSystemProxy(enable: false)
        // disconnect() помечен async и выполняется на @MainActor —
        // блокировка главного потока недопустима.
        // Переносим terminate + waitUntilExit в Task.detached.
        let processToStop = xrayProcess
        xrayProcess = nil
        if let proc = processToStop {
            await Task.detached(priority: .userInitiated) {
                proc.terminate()
                proc.waitUntilExit()
            }.value
        }

        isConnected = false
        publicIP    = ""
        setStatus("○  Отключено", "#8B949E")
        appendLog("VPN отключён. Системный прокси снят.")
    }

    // ── Системный прокси macOS через networksetup ────────────
    // networksetup не требует sudo для текущего пользователя
    private func setSystemProxy(enable: Bool) async {
        // Определяем активный сетевой интерфейс
        let iface = await getActiveNetworkService()

        await Task.detached(priority: .userInitiated) {
            func run(_ args: [String]) {
                let t = Process()
                t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                t.arguments     = args
                try? t.run(); t.waitUntilExit()
            }

            if enable {
                // Включаем SOCKS5
                run(["-setsocksfirewallproxy",       iface, "127.0.0.1", "10808"])
                run(["-setsocksfirewallproxystate",  iface, "on"])
                // Включаем HTTP прокси
                run(["-setwebproxy",     iface, "127.0.0.1", "10809"])
                run(["-setwebproxystate", iface, "on"])
            } else {
                run(["-setsocksfirewallproxystate", iface, "off"])
                run(["-setwebproxystate",            iface, "off"])
            }
        }.value
    }

    // Определяем активный сетевой сервис (Wi-Fi или Ethernet)
    // русскоязычной macOS. Заменяем на проверку через route get:
    // определяем интерфейс для маршрута по умолчанию, затем находим
    // соответствующий networksetup-сервис по имени интерфейса.
    private func getActiveNetworkService() async -> String {
        return await Task.detached {
            // Шаг 1: получаем имя сетевого интерфейса (например, en0, en1)
            let ifaceTask = Process()
            ifaceTask.executableURL = URL(fileURLWithPath: "/sbin/route")
            ifaceTask.arguments     = ["get", "default"]
            let ifacePipe = Pipe()
            ifaceTask.standardOutput = ifacePipe
            ifaceTask.standardError  = Pipe()
            try? ifaceTask.run(); ifaceTask.waitUntilExit()
            let ifaceOut = String(data: ifacePipe.fileHandleForReading.readDataToEndOfFile(),
                                  encoding: .utf8) ?? ""
            // Извлекаем имя интерфейса из строки "interface: en0"
            var activeIface = "en0"
            for line in ifaceOut.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    activeIface = trimmed.replacingOccurrences(of: "interface:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            // Шаг 2: находим networksetup-сервис по имени интерфейса
            let mapTask = Process()
            mapTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            mapTask.arguments     = ["-listnetworkserviceorder"]
            let mapPipe = Pipe()
            mapTask.standardOutput = mapPipe
            mapTask.standardError  = Pipe()
            try? mapTask.run(); mapTask.waitUntilExit()
            let mapOut = String(data: mapPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""

            // Парсим вывод: ищем строку с Device: <activeIface>
            // Формат: (* 2) Wi-Fi\n(Hardware Port: Wi-Fi, Device: en0)
            var serviceName = "Wi-Fi"
            let sections = mapOut.components(separatedBy: "\n\n")
            for section in sections {
                if section.contains("Device: \(activeIface)") {
                    // Берём первую строку секции как имя сервиса
                    let firstLine = section.components(separatedBy: "\n").first ?? ""
                    // Убираем префикс вида "(* 1) " или "(1) "
                    let cleaned = firstLine
                        .replacingOccurrences(of: #"\(\*?\s*\d+\)\s*"#,
                                              with: "",
                                              options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty { serviceName = cleaned }
                    break
                }
            }
            return serviceName
        }.value
    }

    // ── Публичный IP через SOCKS5-прокси Xray ────────────────
    private func fetchPublicIP() async {
        // После подключения запрашиваем публичный IP
        // URLSession на macOS не поддерживает SOCKS5 через ProxyDictionary нативно,
        // поэтому делаем запрос через shell curl с --proxy socks5
        let result = await Task.detached(priority: .userInitiated) { () -> String in
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            t.arguments     = ["-s", "--proxy", "socks5://127.0.0.1:10808",
                               "--max-time", "6", "https://api.ipify.org"]
            let pipe = Pipe()
            t.standardOutput = pipe
            t.standardError  = Pipe()
            try? t.run(); t.waitUntilExit()
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                          encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }.value

        if !result.isEmpty { publicIP = result }
    }

    // ── Helpers ──────────────────────────────────────────────
    private func setStatus(_ t: String, _ c: String) { statusText = t; statusColor = c }

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        // Ограничиваем длину лога
        let trimmed = msg.count > 200 ? String(msg.prefix(200)) + "…" : msg
        logText += "[\(ts)] \(trimmed)\n"
    }

    private func showInstallAlert() {
        let a = NSAlert()
        a.messageText     = "xray не установлен"
        a.informativeText = "Установите Xray через Homebrew:\n\nbrew install xray\n\nHomebrew: https://brew.sh"
        a.alertStyle      = .warning
        a.addButton(withTitle: "OK")
        a.runModal()
    }
}
