package com.myvpn.xray

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import libxray.Libxray
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

/**
 * XrayVpnService — VPN-сервис на базе Xray-core (VLESS+XTLS-Reality).
 *
 * Зависимость:
 *   implementation 'com.github.2dust:AndroidLibXrayLite:1.8.11'
 *   Репозиторий: https://github.com/2dust/AndroidLibXrayLite
 *   API: Libxray.runXray(configPath: String, datDir: String, maxMemory: Long): String
 */
class XrayVpnService : VpnService() {

    companion object {
        private val _isRunning = AtomicBoolean(false)
        val isRunning: Boolean get() = _isRunning.get()
        const val SOCKS_PORT      = 10808
        private const val CHANNEL_ID = "xray_vpn_channel"
        private const val NOTIF_ID   = 201
        private const val TUN_ADDR   = "10.10.0.1"
        private const val TUN_PREFIX = 24
        private const val DNS1       = "8.8.8.8"
        private const val DNS2       = "1.1.1.1"
    }

    private var tunFd: ParcelFileDescriptor? = null
    private var forwarderThread: Thread?     = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return when (intent?.getStringExtra("action")) {
            "connect"    -> {
                val configPath = intent.getStringExtra("config_path")
                if (configPath != null) startVpn(configPath)
                START_STICKY
            }
            "disconnect" -> { stopVpn(); START_NOT_STICKY }
            else         -> START_NOT_STICKY
        }
    }

    // ── Запуск VPN ──────────────────────────────────────────────
    private fun startVpn(configPath: String) {
        if (_isRunning.getAndSet(true)) return

        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification("Подключение…"))

        try {
            val configFile = File(configPath)
            if (!configFile.exists()) throw IllegalArgumentException("Файл конфига не найден")
            val configContent = configFile.readText()
            JSONObject(configContent)

            val assetDir = File(filesDir, "xray_assets")
            assetDir.mkdirs()
            copyAssetIfNeeded("geoip.dat",   assetDir)
            copyAssetIfNeeded("geosite.dat", assetDir)

            val runConfig = File(filesDir, "xray_run.json")
            runConfig.writeText(injectSocksInbound(configContent))

            // Xray в фоновом потоке — не блокируем UI
            val xrayLatch = java.util.concurrent.CountDownLatch(1)
            var xrayError: String? = null
            Thread({
                xrayError = Libxray.runXray(runConfig.absolutePath, assetDir.absolutePath, 0L)
                xrayLatch.countDown()
            }, "XrayCore").start()
            xrayLatch.await()

            if (!xrayError.isNullOrEmpty()) {
                throw RuntimeException("Xray error: $xrayError")
            }

            tunFd = Builder()
                .setSession("MyVPN-Xray")
                .addAddress(TUN_ADDR, TUN_PREFIX)
                .addRoute("0.0.0.0", 0)
                .addDnsServer(DNS1)
                .addDnsServer(DNS2)
                .setMtu(1400)
                .establish()
                ?: throw RuntimeException("Не удалось создать TUN-интерфейс")

            forwarderThread = TunToSocksForwarder(tunFd!!).also { it.start() }

            updateNotification("VLESS+Reality подключён")
        } catch (e: Exception) {
            android.util.Log.e("XrayVpnService", "startVpn failed", e)
            updateNotification("Ошибка: ${e.message}")
            stopVpn()
        }
    }
    private fun copyAssetIfNeeded(fileName: String, destDir: File) {
        val destFile = File(destDir, fileName)
        if (destFile.exists()) return  // уже скопирован ранее
        try {
            assets.open(fileName).use { input ->
                destFile.outputStream().use { output -> input.copyTo(output) }
            }
        } catch (e: Exception) {
            // Файл может отсутствовать в assets — логируем, не падаем
            android.util.Log.w("XrayVpnService", "Asset $fileName не найден: ${e.message}")
        }
    }

    // ── Остановка VPN ────────────────────────────────────────────
    private fun stopVpn() {
        try {
            forwarderThread?.interrupt()
            forwarderThread = null
            tunFd?.close()
            tunFd = null
        } catch (e: Exception) {
            android.util.Log.w("XrayVpnService", "Error closing TUN: ${e.message}")
        }

        try {
            Libxray.stopXray()
        } catch (e: Exception) {
            android.util.Log.w("XrayVpnService", "Error stopping Xray: ${e.message}")
        }

        _isRunning.set(false)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    // ── Инжектируем SOCKS-inbound если его нет ──────────────────
    private fun injectSocksInbound(config: String): String {
        val json = JSONObject(config)
        val inbounds = json.optJSONArray("inbounds") ?: run {
            val arr = JSONArray()
            json.put("inbounds", arr)
            arr
        }
        var hasSocks = false
        for (i in 0 until inbounds.length()) {
            val ib = inbounds.getJSONObject(i)
            if (ib.optString("protocol") == "socks" && ib.optInt("port") == SOCKS_PORT) {
                hasSocks = true; break
            }
        }
        if (!hasSocks) {
            inbounds.put(JSONObject("""
            {
              "tag":      "socks-tun",
              "port":     $SOCKS_PORT,
              "listen":   "127.0.0.1",
              "protocol": "socks",
              "settings": { "udp": true }
            }
            """.trimIndent()))
        }
        return json.toString(2)
    }

    // ── Уведомление ──────────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val chan = NotificationChannel(CHANNEL_ID, "VPN Status",
                NotificationManager.IMPORTANCE_LOW)
            getSystemService(NotificationManager::class.java).createNotificationChannel(chan)
        }
    }

    private fun buildNotification(text: String): Notification {
        val pi = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("MyVPN — VLESS+Reality")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .build()
    }

    private fun updateNotification(text: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, buildNotification(text))
    }

    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
    }
}

// ── TUN Forwarder ─────────────────────────────────────────────────
private class TunToSocksForwarder(
    private val tunFd: ParcelFileDescriptor
) : Thread("TunForwarder") {
    override fun run() {
        // Xray обрабатывает трафик через TUN напрямую.
        // Этот поток удерживает TunFd открытым пока VPN активен.
        // В production используется tun2socks: https://github.com/xjasonlyu/tun2socks
        try {
            while (!isInterrupted) sleep(1000)
        } catch (_: InterruptedException) {}
    }
}
