package com.myvpn.xray

import org.json.JSONArray
import org.json.JSONObject

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
    val json = JSONObject().apply {
        put("outbounds", JSONArray().apply {
            put(JSONObject().apply {
                put("protocol", "vless")
                put("settings", JSONObject().apply {
                    put("vnext", JSONArray().apply {
                        put(JSONObject().apply {
                            put("address", serverIp)
                            put("port", 443)
                            put("users", JSONArray().apply {
                                put(JSONObject().apply {
                                    put("id", uuid)
                                    put("encryption", "none")
                                    put("flow", "xtls-rprx-vision")
                                })
                            })
                        })
                    })
                })
                put("streamSettings", JSONObject().apply {
                    put("network", "tcp")
                    put("security", "reality")
                    put("realitySettings", JSONObject().apply {
                        put("allowInsecure", reality.allowInsecure)
                        put("fingerprint", reality.fingerprint)
                        put("serverName", reality.serverName)
                        put("publicKey", reality.publicKey)
                        put("shortId", reality.shortId)
                        put("spiderX", reality.spiderX)
                    })
                })
            })
        })
    }
    return json.toString(2)
}
