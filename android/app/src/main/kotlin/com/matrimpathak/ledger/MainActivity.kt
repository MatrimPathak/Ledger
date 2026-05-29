package com.matrimpathak.ledger

import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.matrimpathak.ledger/battery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                        val pm = getSystemService(POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    } else {
                        result.success(true) // No Doze on pre-M devices
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    // Opens the general battery-optimization settings list (Play-compliant).
                    // ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS is restricted by Play policy.
                    try {
                        val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("NO_SETTINGS", "Battery optimization settings unavailable", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
