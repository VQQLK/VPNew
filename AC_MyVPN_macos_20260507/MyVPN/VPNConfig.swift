import Foundation

/**
 * VPNConfig.swift — конфигурация Reality для macOS VLESS+XTLS-Reality клиента.
 *
 * Изменения по инструкции AC_3:
 * - allowInsecure: false (было true)
 * - fingerprint: "chrome" (было "firefox")
 * - publicKey вместо privateKey
 */
struct RealityConfig {
    var publicKey: String
    var shortId: String
    var serverName: String
    var allowInsecure: Bool = false
    var fingerprint: String = "chrome"
    var spiderX: String = "/"
}

class VPNConfig {
    static func buildClientJSON(uuid: String, serverIP: String, publicKey: String, shortId: String) -> String {
        let reality = RealityConfig(
            publicKey: publicKey,
            shortId: shortId,
            serverName: "www.microsoft.com"
        )
        return """
        {
          "log": { "loglevel": "warning" },
          "outbounds": [{
            "protocol": "vless",
            "settings": {
              "vnext": [{
                "address": "\(serverIP)",
                "port": 443,
                "users": [{
                  "id": "\(uuid)",
                  "encryption": "none",
                  "flow": "xtls-rprx-vision"
                }]
              }]
            },
            "streamSettings": {
              "network": "tcp",
              "security": "reality",
              "realitySettings": {
                "allowInsecure": \(reality.allowInsecure),
                "fingerprint": "\(reality.fingerprint)",
                "serverName": "\(reality.serverName)",
                "publicKey": "\(reality.publicKey)",
                "shortId": "\(reality.shortId)",
                "spiderX": "\(reality.spiderX)"
              }
            },
            "tag": "proxy"
          }]
        }
        """
    }
}
