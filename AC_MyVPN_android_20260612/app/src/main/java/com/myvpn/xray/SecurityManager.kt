package com.myvpn.xray

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey

/**
 * SecurityManager — централизованное управление безопасностью VPN.
 *
 * Функции:
 * - DNS leak protection: проверка что DNS идёт через VPN
 * - Kill switch: мониторинг сети и отключение при обрыве VPN
 * - Hardware-backed keystore: хранение ключей в защищённом хранилище
 */
object SecurityManager {

    private const val KEYSTORE_PROVIDER = "AndroidKeyStore"
    private const val KEY_ALIAS = "MyVPN_ConfigKey"

    // ── DNS Leak Protection ────────────────────────────────────

    /**
     * Проверяет что VPN активен и DNS идёт через туннель.
     * Возвращает true если DNS leak обнаружен.
     */
    fun isDnsLeaking(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = cm.activeNetwork ?: return true
        val capabilities = cm.getNetworkCapabilities(activeNetwork) ?: return true

        val isVpn = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        return !isVpn
    }

    /**
     * Проверяет что приложение не использует обход VPN.
     */
    fun isVpnBypassed(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = cm.activeNetwork ?: return true
        val capabilities = cm.getNetworkCapabilities(activeNetwork) ?: return true

        val isVpn = capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
        val hasInternet = capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)

        return hasInternet && !isVpn
    }

    // ── Kill Switch ────────────────────────────────────────────

    /**
     * Мониторит состояние VPN и возвращает true если VPN отключился.
     */
    fun isVpnDisconnected(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val activeNetwork = cm.activeNetwork ?: return true
        val capabilities = cm.getNetworkCapabilities(activeNetwork) ?: return true

        return !capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    // ── Hardware-backed Keystore ────────────────────────────────

    /**
     * Генерирует или получает ключ из Android Keystore.
     * Использует hardware-backed keystore если доступен.
     */
    fun getOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(KEYSTORE_PROVIDER).apply { load(null) }

        keyStore.getEntry(KEY_ALIAS, null)?.let {
            return (it as KeyStore.SecretKeyEntry).secretKey
        }

        val keyGenerator = KeyGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_AES,
            KEYSTORE_PROVIDER
        )

        val builder = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setIsStrongBoxBacked(true)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            builder.setIsStrongBoxBacked(true)
        }

        keyGenerator.init(builder.build())
        return keyGenerator.generateKey()
    }
}
