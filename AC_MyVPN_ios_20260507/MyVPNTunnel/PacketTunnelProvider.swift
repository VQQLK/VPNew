import NetworkExtension
import LibXray

// ============================================================
//  PacketTunnelProvider — Network Extension (таргет MyVPNTunnel)
//  Bundle ID: com.myvpn.ios.tunnel
//
//  LibXray (Go Mobile binding):
//    SPM: https://github.com/xtls/libxray
//    или xcframework: https://github.com/xtls/libxray/releases
//
//  Entitlements: com.apple.developer.networking.networkextension = ["packet-tunnel"]
//  Info.plist:   NSExtensionPrincipalClass = PacketTunnelProvider
//                NSExtensionPointIdentifier = com.apple.networkextension.packet-tunnel
//
//  Параметры Reality (инструкция AC_3):
//    allowInsecure : false   (не допускаем небезопасные соединения)
//    fingerprint   : "chrome" (имитация TLS fingerprint Chrome)
//    publicKey     : передаётся через providerConfiguration["config"] (JSON)
//                    НИКОГДА не используется privateKey на клиенте
// ============================================================

// Reality-константы, применяемые ко всем клиентским конфигам (AC_3)
private enum RealityDefaults {
    static let allowInsecure: Bool   = false
    static let fingerprint:   String = "chrome"
    static let serverNames: [String] = [
        "www.microsoft.com",
        "www.apple.com",
        "www.cloudflare.com"
    ]
}

class PacketTunnelProvider: NEPacketTunnelProvider {

    private var xrayRunning = false
    private let stateQueue  = DispatchQueue(label: "com.myvpn.tunnel.state")

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // 1. Читаем конфиг
        guard
            let proto  = protocolConfiguration as? NETunnelProviderProtocol,
            let cfg    = proto.providerConfiguration,
            let b64    = cfg["config"] as? String,
            let data   = Data(base64Encoded: b64),
            let json   = String(data: data, encoding: .utf8)
        else {
            completionHandler(makeError("Конфиг не передан или повреждён"))
            return
        }

        // 2. Пишем конфиг во временный файл
        guard let configURL = writeConfigToTemp(json) else {
            completionHandler(makeError("Не удалось записать конфиг"))
            return
        }
        //    и ТОЛЬКО ПОТОМ вызываем setTunnelNetworkSettings.
        //    Это исключает race condition и двойной вызов completionHandler.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            // Bundle.main в Network Extension — это Bundle Extension (не main app).
            // geoip.dat и geosite.dat должны быть в
            // MyVPNTunnel target → Build Phases → Copy Bundle Resources.
            let assetPath = Bundle.main.bundlePath

            // XrayRunLoop блокирует поток до остановки — запускаем в отдельном потоке
            // и используем семафор для ожидания готовности
            let readySemaphore = DispatchSemaphore(value: 0)
            var xrayError: String? = nil

            // Xray сигнализирует о готовности через ~500ms после старта
            // Используем отдельный поток для блокирующего вызова
            DispatchQueue(label: "com.myvpn.xray.run", qos: .userInitiated).async {
                // Сигнализируем через 1 секунду (Xray обычно стартует быстрее)
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    readySemaphore.signal()
                }
                let err = LibXray.XrayRunLoop(
                    datDir:     assetPath,
                    configPath: configURL.path,
                    maxMemory:  62 * 1024 * 1024
                )
                xrayError = err
                // Если XrayRunLoop вернулся с ошибкой до сигнала
                readySemaphore.signal()
            }

            // Ждём готовности (максимум 3 секунды)
            let waitResult = readySemaphore.wait(timeout: .now() + 3.0)

            if waitResult == .timedOut {
                completionHandler(self.makeError("Xray: таймаут запуска"))
                return
            }

            if let err = xrayError, !err.isEmpty {
                completionHandler(self.makeError("Xray: \(err)"))
                return
            }

            self.stateQueue.async { self.xrayRunning = true }

            // 4. Настраиваем TUN только после успешного старта Xray
            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

            settings.ipv4Settings = {
                let s = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
                s.includedRoutes = [NEIPv4Route.default()]
                return s
            }()

            settings.ipv6Settings = {
                let s = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"],
                                       networkPrefixLengths: [64])
                s.includedRoutes = [NEIPv6Route.default()]
                return s
            }()

            settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
            settings.mtu         = NSNumber(value: 1500)

            // completionHandler вызывается ровно один раз — здесь
            self.setTunnelNetworkSettings(settings) { error in
                completionHandler(error)
            }
        }
    }

    override func stopTunnel(
        with reason: NEProviderStopReason,
        completionHandler: @escaping () -> Void
    ) {
        stateQueue.sync {
            if xrayRunning {
                LibXray.XrayStopLoop()
                xrayRunning = false
            }
        }
        completionHandler()
    }

    // ── Helpers ──────────────────────────────────────────────
    private func writeConfigToTemp(_ json: String) -> URL? {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("xray_config.json")
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch { return nil }
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "com.myvpn.ios.tunnel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
