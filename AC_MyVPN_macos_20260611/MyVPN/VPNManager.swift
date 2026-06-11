import Foundation
import AppKit
import UniformTypeIdentifiers
import os.log

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

private let logger = Logger(subsystem: "com.myvpn.macos", category: "vpn")

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
    private let maxLogLines = 200

    private var xrayPath: String {
        let paths = [
            "/opt/homebrew/bin/xray",
            "/usr/local/bin/xray",
            "/usr/local/sbin/xray",
            Bundle.main.bundlePath + "/Contents/MacOS/xray"
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
        if isConnected {
            Task { await disconnect() }
        } else {
            Task { await connect() }
        }
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: xrayPath)
        process.arguments     = ["run", "-c", configURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError  = pipe

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

        try? await Task.sleep(nanoseconds: 2_000_000_000)

        guard process.isRunning else {
            setStatus("○  Ошибка", "#DA3633")
            appendLog("xray завершился. Проверьте конфиг.")
            xrayProcess = nil
            return
        }

        await setSystemProxy(enable: true)

        isConnected = true
        setStatus("●  VLESS+Reality", "#3FB950")
        appendLog("Xray запущен. SOCKS5: 127.0.0.1:10808")
        await fetchPublicIP()
    }

    // ── Отключение ───────────────────────────────────────────
    private func disconnect() async {
        await setSystemProxy(enable: false)
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
    private func setSystemProxy(enable: Bool) async {
        let iface = await getActiveNetworkService()

        await Task.detached(priority: .userInitiated) {
            func run(_ args: [String]) -> Bool {
                let t = Process()
                t.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                t.arguments     = args
                let errPipe = Pipe()
                t.standardError = errPipe
                do {
                    try t.run()
                    t.waitUntilExit()
                    let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    let errStr = String(data: errData, encoding: .utf8) ?? ""
                    if t.terminationStatus != 0 {
                        logger.error("networksetup \(args.joined(separator: " ")) failed: \(errStr)")
                        return false
                    }
                    return true
                } catch {
                    logger.error("networksetup launch error: \(error.localizedDescription)")
                    return false
                }
            }

            if enable {
                _ = run(["-setsocksfirewallproxy",       iface, "127.0.0.1", "10808"])
                _ = run(["-setsocksfirewallproxystate",  iface, "on"])
                _ = run(["-setwebproxy",                 iface, "127.0.0.1", "10809"])
                _ = run(["-setwebproxystate",            iface, "on"])
            } else {
                _ = run(["-setsocksfirewallproxystate", iface, "off"])
                _ = run(["-setwebproxystate",            iface, "off"])
            }
        }.value
    }

    private func getActiveNetworkService() async -> String {
        return await Task.detached {
            let ifaceTask = Process()
            ifaceTask.executableURL = URL(fileURLWithPath: "/sbin/route")
            ifaceTask.arguments     = ["get", "default"]
            let ifacePipe = Pipe()
            ifaceTask.standardOutput = ifacePipe
            ifaceTask.standardError  = Pipe()
            do { try ifaceTask.run(); ifaceTask.waitUntilExit() } catch { return "Wi-Fi" }
            let ifaceOut = String(data: ifacePipe.fileHandleForReading.readDataToEndOfFile(),
                                  encoding: .utf8) ?? ""
            var activeIface = "en0"
            for line in ifaceOut.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("interface:") {
                    activeIface = trimmed.replacingOccurrences(of: "interface:", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    break
                }
            }

            let mapTask = Process()
            mapTask.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            mapTask.arguments     = ["-listnetworkserviceorder"]
            let mapPipe = Pipe()
            mapTask.standardOutput = mapPipe
            mapTask.standardError  = Pipe()
            do { try mapTask.run(); mapTask.waitUntilExit() } catch { return "Wi-Fi" }
            let mapOut = String(data: mapPipe.fileHandleForReading.readDataToEndOfFile(),
                                encoding: .utf8) ?? ""

            var serviceName = ""
            let sections = mapOut.components(separatedBy: "\n\n")
            for section in sections {
                if section.contains("Device: \(activeIface)") {
                    let firstLine = section.components(separatedBy: "\n").first ?? ""
                    let cleaned = firstLine
                        .replacingOccurrences(of: #"\(\*?\s*\d+\)\s*"#,
                                              with: "",
                                              options: .regularExpression)
                        .trimmingCharacters(in: .whitespaces)
                    if !cleaned.isEmpty { serviceName = cleaned }
                    break
                }
            }

            if serviceName.isEmpty {
                // Fallback: ищем первый сервис с Hardware Port
                for section in sections {
                    if section.contains("Hardware Port:") {
                        let firstLine = section.components(separatedBy: "\n").first ?? ""
                        let cleaned = firstLine
                            .replacingOccurrences(of: #"\(\*?\s*\d+\)\s*"#,
                                                  with: "",
                                                  options: .regularExpression)
                            .trimmingCharacters(in: .whitespaces)
                        if !cleaned.isEmpty { serviceName = cleaned; break }
                    }
                }
            }

            return serviceName.isEmpty ? "Wi-Fi" : serviceName
        }.value
    }

    // ── Публичный IP через SOCKS5-прокси Xray ────────────────
    private func fetchPublicIP() async {
        let result = await Task.detached(priority: .userInitiated) { () -> String in
            let t = Process()
            t.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            t.arguments     = ["-s", "--proxy", "socks5://127.0.0.1:10808",
                               "--max-time", "6", "https://api.ipify.org"]
            let pipe = Pipe()
            t.standardOutput = pipe
            t.standardError  = Pipe()
            do {
                try t.run()
                t.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let str = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                // Валидируем что это IP-адрес
                let parts = str.split(separator: ".")
                guard parts.count == 4, parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return "" }
                return str
            } catch {
                return ""
            }
        }.value

        if !result.isEmpty { publicIP = result }
    }

    // ── Helpers ──────────────────────────────────────────────
    private func setStatus(_ t: String, _ c: String) { statusText = t; statusColor = c }

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let trimmed = msg.count > 200 ? String(msg.prefix(200)) + "…" : msg
        logText += "[\(ts)] \(trimmed)\n"
        let lines = logText.components(separatedBy: "\n")
        if lines.count > maxLogLines {
            logText = lines.suffix(maxLogLines).joined(separator: "\n")
        }
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
