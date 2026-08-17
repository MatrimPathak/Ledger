package com.matrimpathak.ledger

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * Extracts only [packageName, postTime, amount, eventTypeGuess] from each
 * posted notification, used solely to correlate a same-moment payment-app
 * notification (e.g. "Paid ₹250 to Rajesh Kumar") against a transaction
 * already created from a bank SMS. The full notification title/text is
 * read only transiently, inside this method, to run the amount/direction
 * regex — it is never stored, logged, or forwarded anywhere. Requires the
 * user to explicitly grant notification-listener access in system
 * settings (Android does not allow this as a normal runtime permission).
 */
class LedgerNotificationListenerService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        try {
            if (sbn.packageName == applicationContext.packageName) return

            val extras = sbn.notification?.extras ?: return
            val title = extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() ?: ""
            val text = extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() ?: ""
            val combined = "$title $text"

            val amount = extractAmount(combined) ?: return // no amount, nothing to correlate
            val eventTypeGuess = guessEventType(combined)

            NotificationEventBridge.emit(
                mapOf(
                    "packageName" to sbn.packageName,
                    "postTime" to sbn.postTime,
                    "amount" to amount,
                    "eventTypeGuess" to eventTypeGuess,
                )
            )
        } catch (_: Exception) {
            // Never let a malformed/unexpected notification crash the listener.
        }
    }

    companion object {
        // Leading \b prevents "rs" from matching as a mid-word substring
        // (e.g. the "rs" inside "hours") — no trailing \b, since "Rs." is a
        // valid prefix and a boundary right after a period is not
        // guaranteed when a space follows it before the digits.
        private val AMOUNT_REGEX =
            Regex("(?:\\b(?:rs\\.?|inr)|₹)\\s*([0-9][0-9,]*(?:\\.[0-9]{1,2})?)", RegexOption.IGNORE_CASE)

        private val DEBIT_KEYWORDS = listOf("paid", "sent", "debited", "spent")
        private val CREDIT_KEYWORDS = listOf("received", "credited", "refund")

        fun extractAmount(text: String): Double? {
            val match = AMOUNT_REGEX.find(text) ?: return null
            val raw = match.groupValues[1].replace(",", "")
            return raw.toDoubleOrNull()
        }

        fun guessEventType(text: String): String {
            val lower = text.lowercase()
            if (DEBIT_KEYWORDS.any { containsWord(lower, it) }) return "debit"
            if (CREDIT_KEYWORDS.any { containsWord(lower, it) }) return "credit"
            return "unknown"
        }

        private fun containsWord(lower: String, word: String): Boolean =
            Regex("\\b${Regex.escape(word)}\\b").containsMatchIn(lower)
    }
}
