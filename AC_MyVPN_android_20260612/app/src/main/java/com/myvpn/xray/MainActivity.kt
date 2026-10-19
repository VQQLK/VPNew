package com.myvpn.xray

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Bundle
import android.widget.*
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.material.button.MaterialButton
import org.json.JSONObject
import java.io.File

class MainActivity : AppCompatActivity() {

    private lateinit var btnConnect: MaterialButton
    private lateinit var btnImport:  MaterialButton
    private lateinit var tvStatus:   TextView
    private lateinit var tvIp:       TextView

    private val VPN_REQUEST_CODE    = 1001
    private val IMPORT_REQUEST_CODE = 1002

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        btnConnect = findViewById(R.id.btnConnect)
        btnImport  = findViewById(R.id.btnImport)
        tvStatus   = findViewById(R.id.tvStatus)
        tvIp       = findViewById(R.id.tvIp)

        btnImport.setOnClickListener  { pickConfigFile() }
        btnConnect.setOnClickListener { toggleVpn() }

        updateUi(XrayVpnService.isRunning)
    }

    private fun toggleVpn() {
        if (XrayVpnService.isRunning) {
            stopVpn()
        } else {
            val intent = VpnService.prepare(this)
            if (intent != null) startActivityForResult(intent, VPN_REQUEST_CODE)
            else                startVpn()
        }
    }

    private fun startVpn() {
        val config = File(filesDir, "config.json")
        if (!config.exists()) {
            Toast.makeText(this, "Сначала импортируйте client_config.json", Toast.LENGTH_LONG).show()
            return
        }
        try {
            JSONObject(config.readText())
        } catch (e: Exception) {
            Toast.makeText(this, "Файл конфига повреждён: ${e.message}", Toast.LENGTH_LONG).show()
            return
        }
        val si = Intent(this, XrayVpnService::class.java)
            .putExtra("action", "connect")
            .putExtra("config_path", config.absolutePath)
        ContextCompat.startForegroundService(this, si)
        updateUi(true)
    }

    private fun stopVpn() {
        startService(Intent(this, XrayVpnService::class.java).putExtra("action", "disconnect"))
        updateUi(false)
        tvIp.text = ""
    }

    private fun pickConfigFile() {
        val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
            type = "application/json"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("application/json", "*/*"))
            addCategory(Intent.CATEGORY_OPENABLE)
        }
        startActivityForResult(intent, IMPORT_REQUEST_CODE)
    }

    @Deprecated("Required for VpnService.prepare() — ActivityResult API не поддерживает VpnService")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when {
            requestCode == VPN_REQUEST_CODE && resultCode == Activity.RESULT_OK ->
                startVpn()

            requestCode == IMPORT_REQUEST_CODE && resultCode == Activity.RESULT_OK -> {
                data?.data?.let { uri ->
                    contentResolver.openInputStream(uri)?.use { input ->
                        val content = input.bufferedReader().readText()
                        try {
                            JSONObject(content)
                            File(filesDir, "config.json").writeText(content)
                            Toast.makeText(this, "Конфиг импортирован ✓", Toast.LENGTH_SHORT).show()
                        } catch (e: Exception) {
                            Toast.makeText(this,
                                "Невалидный JSON: ${e.message}", Toast.LENGTH_LONG).show()
                        }
                    }
                }
            }
        }
    }

    private fun updateUi(connected: Boolean) {
        if (connected) {
            btnConnect.text = "Отключить"
            btnConnect.backgroundTintList =
                android.content.res.ColorStateList.valueOf(getColor(R.color.colorDisconnect))
            tvStatus.text = "● VLESS+Reality"
            tvStatus.setTextColor(getColor(R.color.colorConnected))
        } else {
            btnConnect.text = "Подключить"
            btnConnect.backgroundTintList =
                android.content.res.ColorStateList.valueOf(getColor(R.color.colorConnect))
            tvStatus.text = "○ Отключено"
            tvStatus.setTextColor(getColor(R.color.colorDisconnected))
        }
    }

    override fun onResume() {
        super.onResume()
        updateUi(XrayVpnService.isRunning)
    }
}
