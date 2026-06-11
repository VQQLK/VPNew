import Foundation

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
        let json: [String: Any] = [
            "log": ["loglevel": "warning"] as [String: Any],
            "outbounds": [[
                "protocol": "vless",
                "settings": [
                    "vnext": [[
                        "address": serverIP,
                        "port": 443,
                        "users": [[
                            "id": uuid,
                            "encryption": "none",
                            "flow": "xtls-rprx-vision"
                        ]] as [[String: Any]]
                    ]] as [[String: Any]]
                ] as [String: Any],
                "streamSettings": [
                    "network": "tcp",
                    "security": "reality",
                    "realitySettings": [
                        "allowInsecure": reality.allowInsecure,
                        "fingerprint": reality.fingerprint,
                        "serverName": reality.serverName,
                        "publicKey": reality.publicKey,
                        "shortId": reality.shortId,
                        "spiderX": reality.spiderX
                    ] as [String: Any]
                ] as [String: Any],
                "tag": "proxy"
            ]] as [[String: Any]]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }
}
