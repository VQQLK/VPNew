import NetworkExtension
import LibXray
import os.log

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

private let logger = Logger(subsystem: "com.myvpn.ios.tunnel", category: "tunnel")

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
    private var configFileURL: URL?

    override func startTunnel(
        options: [String: NSObject]?,
        completionHandler: @escaping (Error?) -> Void
    ) {
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

        guard let configURL = writeConfigToTemp(json) else {
            completionHandler(makeError("Не удалось записать конфиг"))
            return
        }
        configFileURL = configURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let assetPath = Bundle.main.bundlePath
            let readySemaphore = DispatchSemaphore(value: 0)

            // Защищаем xrayError через stateQueue
            var xrayError: String?

            DispatchQueue(label: "com.myvpn.xray.run", qos: .userInitiated).async {
                let err = LibXray.XrayRunLoop(
                    datDir:     assetPath,
                    configPath: configURL.path,
                    maxMemory:  62 * 1024 * 1024
                )
                self.stateQueue.sync {
                    xrayError = err
                }
                readySemaphore.signal()
            }

            let waitResult = readySemaphore.wait(timeout: .now() + 5.0)

            if waitResult == .timedOut {
                self.stateQueue.sync {
                    LibXray.XrayStopLoop()
                }
                self.cleanupConfigFile()
                completionHandler(self.makeError("Xray: таймаут запуска"))
                return
            }

            let finalError: String? = self.stateQueue.sync { xrayError }

            if let err = finalError, !err.isEmpty {
                self.cleanupConfigFile()
                completionHandler(self.makeError("Xray: \(err)"))
                return
            }

            self.stateQueue.async { self.xrayRunning = true }

            let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "127.0.0.1")

            settings.ipv4Settings = {
                let s = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.0.0"])
                s.includedRoutes = [NEIPv4Route.default()]
                return s
            }()

            // IPv6: исключаем маршруты чтобы предотвратить утечку
            settings.ipv6Settings = {
                let s = NEIPv6Settings(addresses: ["fd6e:a81b:704f:1211::1"],
                                       networkPrefixLengths: [64])
                s.includedRoutes = []
                s.excludedRoutes = [NEIPv6Route.default()]
                return s
            }()

            settings.dnsSettings = NEDNSSettings(servers: ["8.8.8.8", "1.1.1.1"])
            settings.mtu         = NSNumber(value: 1400)

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
        cleanupConfigFile()
        completionHandler()
    }

    // ── Helpers ──────────────────────────────────────────────
    private func writeConfigToTemp(_ json: String) -> URL? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.myvpn.ios.tunnel")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create temp dir: \(error.localizedDescription)")
            return nil
        }
        let url = dir.appendingPathComponent("xray_config.json")
        do {
            try json.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            logger.error("Failed to write config: \(error.localizedDescription)")
            return nil
        }
    }

    private func cleanupConfigFile() {
        guard let url = configFileURL else { return }
        try? FileManager.default.removeItem(at: url)
        configFileURL = nil
    }

    private func makeError(_ msg: String) -> NSError {
        NSError(domain: "com.myvpn.ios.tunnel", code: -1,
                userInfo: [NSLocalizedDescriptionKey: msg])
    }
}
