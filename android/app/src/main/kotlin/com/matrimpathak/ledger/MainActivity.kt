package com.matrimpathak.ledger

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.matrimpathak.ledger/secure_prefs"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "write" -> {
                    val key = call.argument<String>("key")
                    val value = call.argument<String>("value")
                    if (key != null && value != null) {
                        SecurePrefsStore.write(applicationContext, key, value)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "key and value are required", null)
                    }
                }
                "remove" -> {
                    val key = call.argument<String>("key")
                    if (key != null) {
                        SecurePrefsStore.remove(applicationContext, key)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGS", "key is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.matrimpathak.ledger/notification_events"
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                NotificationEventBridge.attach(events)
            }

            override fun onCancel(arguments: Any?) {
                NotificationEventBridge.attach(null)
            }
        })

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.matrimpathak.ledger/notification_access"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessGranted" -> {
                    result.success(isNotificationListenerAccessGranted())
                }
                "openSettings" -> {
                    try {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("NO_SETTINGS", "Notification listener settings unavailable", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    // A plain substring check on the enabled-listeners string can false-
    // positive on a different service within the same package (or another
    // package whose flattened component happens to contain this one's name
    // as a substring). Compare the declared component identity instead.
    private fun isNotificationListenerAccessGranted(): Boolean {
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            val target = ComponentName(this, LedgerNotificationListenerService::class.java)
            return nm.isNotificationListenerAccessGranted(target)
        }
        val target = ComponentName(this, LedgerNotificationListenerService::class.java)
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners")
            ?: return false
        return flat.split(":").any { ComponentName.unflattenFromString(it) == target }
    }
}
