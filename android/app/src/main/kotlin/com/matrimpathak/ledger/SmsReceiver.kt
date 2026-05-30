package com.matrimpathak.ledger

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.workDataOf
import org.json.JSONArray

/**
 * Manifest-registered receiver for SMS_RECEIVED. Runs even when the app is killed.
 * Filters for bank SMS and enqueues a WorkManager expedited job so processing happens
 * without a persistent foreground-service notification on Android 12+.
 *
 * When the app is in the foreground the Dart SMS listener (another_telephony) already
 * handles the same message, so we skip enqueueing to avoid duplicate processing.
 */
class SmsReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
        if (messages.isNullOrEmpty()) return

        val body = messages.joinToString("") { it.messageBody }
        val sender = messages.first().originatingAddress ?: ""
        val timestamp = messages.first().timestampMillis

        if (!looksLikeBankSms(body)) return

        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        if (!prefs.getBoolean("$KEY_PREFIX$KEY_AUTO_DETECT", false)) return

        // Dart's SMS listener handles messages while the app is in the foreground.
        if (isAppInForeground(context)) return

        val fingerprint = buildFingerprint(sender, body, timestamp)
        if (isAlreadyProcessed(fingerprint, prefs)) return

        val request = OneTimeWorkRequestBuilder<SmsProcessingWorker>()
            .setInputData(
                workDataOf(
                    SmsProcessingWorker.KEY_SMS_BODY to body,
                    SmsProcessingWorker.KEY_SMS_TIMESTAMP to timestamp,
                    SmsProcessingWorker.KEY_SMS_FINGERPRINT to fingerprint,
                )
            )
            .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            .build()

        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork("sms_$fingerprint", ExistingWorkPolicy.KEEP, request)
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private fun looksLikeBankSms(body: String): Boolean {
        val lower = body.lowercase()
        val keywords = listOf(
            "debited", "credited", "debit", "credit", "inr", "upi ref", "neft",
            "imps", "rtgs", "a/c", "acct", "transaction", "rs.", "rs ", "balance",
            "bank", "e-mandate", "emandate", "will be deducted", "auto debit", "auto-debit",
        )
        if (keywords.any { lower.contains(it) }) return true
        val patterns = listOf(Regex("""\bnach\b"""), Regex("""\bumn\b"""), Regex("""\bmandate\b"""))
        return patterns.any { it.containsMatchIn(lower) }
    }

    private fun isAppInForeground(context: Context): Boolean {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.runningAppProcesses?.any {
            it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                    && it.processName == context.packageName
        } == true
    }

    private fun buildFingerprint(sender: String, body: String, timestamp: Long): String {
        val snippet = if (body.length > 50) body.substring(0, 50) else body
        return "${sender}_${timestamp}_$snippet"
    }

    private fun isAlreadyProcessed(fingerprint: String, prefs: android.content.SharedPreferences): Boolean {
        val stored = prefs.getString("$KEY_PREFIX$KEY_PROCESSED_IDS", "[]") ?: "[]"
        return try {
            val arr = JSONArray(stored)
            (0 until arr.length()).any { arr.getString(it) == fingerprint }
        } catch (_: Exception) {
            false
        }
    }

    companion object {
        const val FLUTTER_PREFS = "FlutterSharedPreferences"
        const val KEY_PREFIX = "flutter."
        const val KEY_AUTO_DETECT = "auto_detect_enabled"
        const val KEY_PROCESSED_IDS = "processed_sms_ids"
    }
}
