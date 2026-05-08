import Foundation
import NetworkExtension
import SwiftUI

// ============================================================
//  VPNManager — iOS, Xray VLESS+XTLS-Reality
//  Управляет NETunnelProviderManager → MyVPNTunnel Extension
// ============================================================

@MainActor
class VPNManager: ObservableObject {

    static let shared = VPNManager()

    @Published var isConnected  = false
    @Published var statusText   = "○  Отключено"
    @Published var statusColor  = "#8B949E"
    @Published var publicIP     = ""
    @Published var logText      = ""

    private let tunnelBundleID = "com.myvpn.ios.tunnel"
    private var providerManager: NETunnelProviderManager?
    private let configKey = "myvpn_xray_config"

    private init() {
        Task { await loadManager() }
        // Closure-based addObserver — нет @objc/MainActor конфликта
        NotificationCenter.default.addObserver(
            forName:  .NEVPNStatusDidChange,
            object:   nil,
            queue:    .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handleStatusChange() }
        }
    }

    // ── Загрузка менеджера ───────────────────────────────────
    private func loadManager() async {
        do {
            let managers = try await NETunnelProviderManager.loadAllFromPreferences()
            providerManager = managers.first ?? NETunnelProviderManager()
        } catch {
            appendLog("loadManager: \(error.localizedDescription)")
        }
    }

    // ── Импорт client_config.json ────────────────────────────
    func importConfig(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            appendLog("Нет доступа к файлу.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            // Валидируем JSON
            _ = try JSONSerialization.jsonObject(with: data)
            // Сохраняем как Base64 в UserDefaults
            UserDefaults.standard.set(data.base64EncodedString(), forKey: configKey)
            appendLog("Конфиг импортирован: \(url.lastPathComponent)")
        } catch {
            appendLog("Ошибка: \(error.localizedDescription)")
        }
    }

    // ── Переключение ─────────────────────────────────────────
    func toggleVPN() {
        isConnected ? disconnect() : Task { await connect() }
    }

    // ── Подключение ──────────────────────────────────────────
    private func connect() async {
        guard let configB64 = UserDefaults.standard.string(forKey: configKey) else {
            appendLog("⚠ Сначала импортируйте client_config.json.")
            return
        }

        setStatus("⟳  Подключение…", "#F0E68C")

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = tunnelBundleID
        proto.serverAddress            = "Xray VLESS+Reality"
        // Передаём конфиг в Extension через providerConfiguration
        proto.providerConfiguration    = ["config": configB64]

        let manager = providerManager ?? NETunnelProviderManager()
        manager.protocolConfiguration  = proto
        manager.localizedDescription   = "MyVPN — VLESS+Reality"
        manager.isEnabled              = true

        do {
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
            try manager.connection.startVPNTunnel()
            providerManager = manager
            appendLog("Туннель запущен.")
        } catch {
            setStatus("○  Ошибка", "#DA3633")
            appendLog("Ошибка: \(error.localizedDescription)")
        }
    }

    // ── Отключение ───────────────────────────────────────────
    private func disconnect() {
        providerManager?.connection.stopVPNTunnel()
        appendLog("Останавливаем туннель...")
    }

    // ── Обработчик статуса VPN ───────────────────────────────
    private func handleStatusChange() {
        guard let status = providerManager?.connection.status else { return }
        switch status {
        case .connected:
            isConnected = true
            setStatus("●  VLESS+Reality", "#3FB950")
            Task { await fetchPublicIP() }
        case .connecting:
            setStatus("⟳  Подключение…", "#F0E68C")
        case .disconnecting:
            setStatus("⟳  Отключение…", "#F0E68C")
        case .disconnected, .invalid, .reasserting:
            isConnected = false; publicIP = ""
            setStatus("○  Отключено", "#8B949E")
        @unknown default: break
        }
    }

    // ── Публичный IP ─────────────────────────────────────────
    private func fetchPublicIP() async {
        guard let url = URL(string: "https://api.ipify.org") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            publicIP = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        } catch { publicIP = "" }
    }

    // ── Helpers ──────────────────────────────────────────────
    private func setStatus(_ t: String, _ c: String) { statusText = t; statusColor = c }

    func appendLog(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logText += "[\(ts)] \(msg)\n"
    }
}
