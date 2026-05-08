package com.myvpn.xray

/**
 * VpnConfig.kt — конфигурация Reality для VLESS+XTLS-Reality клиента.
 *
 * Патч vpnew-security-full_patch:
 * - allowInsecure: false (не допускаем небезопасные соединения)
 * - fingerprint: "chrome" (имитация Chrome TLS fingerprint)
 * - publicKey вместо privateKey (клиент использует только публичный ключ)
 * - buildRealityConfig и createVlessConfig — top-level функции (не в object)
 */
data class RealityConfig(
    val allowInsecure: Boolean = false,
    val fingerprint: String = "chrome",
    val serverName: String,
    val publicKey: String,
    val shortId: String,
    val spiderX: String = "/"
)

fun buildRealityConfig(
    publicKey: String,
    shortId: String,
    serverName: String
): RealityConfig {
    // uuid и serverAddress не нужны для конфигурации Reality:
    // uuid передаётся в outbound users, serverName — SNI для TLS handshake
    return RealityConfig(
        allowInsecure = false,
        fingerprint = "chrome",
        serverName = serverName,
        publicKey = publicKey,
        shortId = shortId
    )
}

fun createVlessConfig(uuid: String, serverIp: String, publicKey: String, shortId: String): String {
    val reality = buildRealityConfig(publicKey, shortId, "www.microsoft.com")
    return """
        {
          "outbounds": [{
            "protocol": "vless",
            "settings": {
              "vnext": [{
                "address": "$serverIp",
                "port": 443,
                "users": [{
                  "id": "$uuid",
                  "encryption": "none",
                  "flow": "xtls-rprx-vision"
                }]
              }]
            },
            "streamSettings": {
              "network": "tcp",
              "security": "reality",
              "realitySettings": {
                "allowInsecure": ${reality.allowInsecure},
                "fingerprint": "${reality.fingerprint}",
                "serverName": "${reality.serverName}",
                "publicKey": "${reality.publicKey}",
                "shortId": "${reality.shortId}",
                "spiderX": "${reality.spiderX}"
              }
            }
          }]
        }
    """.trimIndent()
}
