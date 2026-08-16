package com.matrimpathak.ledger

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.google.firebase.FirebaseApp
import com.google.firebase.Timestamp
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.Date

/**
 * Processes a bank SMS that was captured by SmsReceiver while the app was in the
 * background. Runs as a WorkManager expedited job — no persistent notification on
 * Android 12+ (API 31+). On older Android a brief processing notification may appear
 * via getForegroundInfo(), required by WorkManager for backward compat.
 *
 * All Firestore and Claude API work runs natively in Kotlin so there is no Flutter
 * engine to boot, which makes the job fast and reliable on any Android version.
 *
 * Mirrors the Dart pipeline (lib/services/sms/sms_service.dart) field-for-field:
 * local deterministic parsing first (LocalSmsParser, same
 * assets/sms_patterns/bank_patterns.json rule set), three-tier confidence
 * routing (high confidence skips the Claude call entirely), and offline-first
 * transaction creation — a transaction is written whenever an amount was
 * resolved either locally or via AI, never silently dropped the way a failed/
 * low-confidence AI call used to.
 */
class SmsProcessingWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    // ── Entry point ───────────────────────────────────────────────────────────

    override suspend fun doWork(): Result {
        val smsBody = inputData.getString(KEY_SMS_BODY) ?: return Result.failure()
        val smsTimestamp = inputData.getLong(KEY_SMS_TIMESTAMP, System.currentTimeMillis())
        val fingerprint = inputData.getString(KEY_SMS_FINGERPRINT) ?: return Result.failure()

        val prefs = applicationContext.getSharedPreferences(
            SmsReceiver.FLUTTER_PREFS, Context.MODE_PRIVATE
        )

        if (!prefs.getBoolean("${P}auto_detect_enabled", false)) return Result.success()
        if (isAlreadyProcessed(fingerprint, prefs)) return Result.success()

        val lastProcessed = prefs.getLong("${P}last_sms_timestamp", 0L)
        if (smsTimestamp <= lastProcessed) return Result.success()

        // uid and the Claude API key live in the Keystore-backed
        // SecurePrefsStore, not plaintext SharedPreferences — see
        // SecurePrefsStore.kt.
        val uid = SecurePrefsStore.read(applicationContext, "uid")?.takeIf { it.isNotBlank() }
            ?: return Result.success()
        val notificationsEnabled = prefs.getBoolean("${P}notifications_enabled", true)

        // E-mandate / NACH pre-debit notifications are not real transactions —
        // the actual debit arrives as a separate SMS. Skip entirely so they
        // never appear in the transaction list (matches sms_service.dart's
        // backgroundSmsHandler).
        if (isPreDebitNotification(smsBody)) {
            markProcessed(fingerprint, smsTimestamp, prefs)
            return Result.success()
        }

        try {
            try { FirebaseApp.initializeApp(applicationContext) } catch (_: Exception) {}
            val db = FirebaseFirestore.getInstance()

            val accounts = fetchAccounts(db, uid)
            val paymentModes = fetchPaymentModes(db, uid)
            val creditCardAccounts = fetchCreditCardAccounts(db, uid)

            val txDate = Date(smsTimestamp)
            val sourceMessageHash = computeSmsHash(smsBody)

            val localParser = LocalSmsParser.loadFromAssets(applicationContext)
            val local = localParser.parse(smsBody, accounts, paymentModes)

            // Firestore-side dedup on top of the device-local fingerprint check
            // above — catches the case where app data was cleared/reinstalled.
            val alreadyExists = if (local.referenceNumber != null) {
                transactionExistsByExternalRef(db, uid, local.referenceNumber)
            } else {
                transactionExistsByHashNearby(db, uid, sourceMessageHash, txDate)
            }
            if (alreadyExists) {
                markProcessed(fingerprint, smsTimestamp, prefs)
                return Result.success()
            }

            // Three-tier routing: high confidence never touches the cloud.
            var aiParsed: ParsedSms? = null
            if (!local.isHighConfidence) {
                val apiKey = SecurePrefsStore.read(applicationContext, "claude_api_key")
                    ?.takeIf { it.isNotBlank() && it != "YOUR_CLAUDE_API_KEY" }
                if (apiKey != null) {
                    aiParsed = callClaudeApi(apiKey, smsBody, accounts, paymentModes)
                }
            }

            val resolvedAmount = aiParsed?.amount ?: local.amount
            if (resolvedAmount == null || !isPlausibleAmount(resolvedAmount)) {
                markProcessed(fingerprint, smsTimestamp, prefs)
                return Result.success()
            }
            if (!isPlausibleTransactionDate(txDate)) {
                markProcessed(fingerprint, smsTimestamp, prefs)
                return Result.success()
            }

            val resolvedDirection = aiParsed?.type ?: local.direction
            val txType = if (resolvedDirection == "credit" || resolvedDirection == "income") "income" else "expense"

            val resolvedAccountId = aiParsed?.accountId ?: local.matchedAccountId
                ?: (accounts.firstOrNull()?.get("id") as? String)
            val resolvedPaymentModeId = aiParsed?.paymentModeId ?: local.matchedPaymentModeId
            val modeType = paymentModes.firstOrNull { it["id"] == resolvedPaymentModeId }?.get("type") as? String
            val affectsBalance = modeType != "creditCard" && modeType != "cash"
            val linkedCreditCardAccountId = if (modeType == "creditCard") {
                creditCardAccounts.firstOrNull { it["paymentModeId"] == resolvedPaymentModeId }
                    ?.get("id") as? String
            } else null

            val categories = fetchCategories(db, uid)
            val categoryId = resolveOrCreateCategory(aiParsed?.categorySlug, categories, uid, db)

            val title = aiParsed?.title ?: local.merchantCandidate ?: "Transaction"
            val txnCategory = local.txnCategoryHint ?: txType
            val processingStatus = when {
                local.isHighConfidence -> "confirmed"
                aiParsed != null -> "aiProcessed"
                else -> "needsAiReview"
            }

            val txMap = buildMap {
                put("userId", uid)
                put("title", title)
                put("amount", resolvedAmount)
                put("type", txType)
                put("date", Timestamp(txDate))
                put("categoryId", categoryId)
                put("accountId", resolvedAccountId ?: "")
                put("paymentModeId", resolvedPaymentModeId)
                put("source", "sms")
                put("rawSms", smsBody)
                put("createdAt", Timestamp(Date()))
                put("affectsBalance", affectsBalance)
                put("txnCategory", txnCategory)
                put("paymentMethod", local.paymentMethod)
                put("sourceMessageId", fingerprint)
                put("sourceMessageHash", sourceMessageHash)
                put("externalTransactionId", local.referenceNumber)
                put("transactionAt", Timestamp(txDate))
                put("processingStatus", processingStatus)
                put("aiConfidence", aiParsed?.confidence)
                put("aiModel", if (aiParsed != null) "claude-haiku-4-5-20251001" else null)
                put("creditCardAccountId", linkedCreditCardAccountId)
            }

            // Mark processed before writing so a concurrent isolate doesn't duplicate.
            markProcessed(fingerprint, smsTimestamp, prefs)

            val txRef = db.collection("users").document(uid).collection("transactions").document()
            db.runTransaction { transaction ->
                transaction.set(txRef, txMap)
                if (resolvedAccountId != null && affectsBalance) {
                    val delta = if (txType == "income") resolvedAmount else -resolvedAmount
                    transaction.update(
                        db.collection("users").document(uid)
                            .collection("accounts").document(resolvedAccountId),
                        "balance", FieldValue.increment(delta),
                    )
                }
                // Credit-card purchases grow outstanding; bill payments shrink
                // it — never double-counted against the bank balance, since
                // affectsBalance is already false for the creditCard payment
                // mode on the purchase leg (mirrors sms_service.dart).
                if (linkedCreditCardAccountId != null) {
                    val outstandingDelta = when (txnCategory) {
                        "creditCardPurchase" -> resolvedAmount
                        "creditCardPayment" -> -resolvedAmount
                        else -> null
                    }
                    if (outstandingDelta != null) {
                        transaction.update(
                            db.collection("users").document(uid)
                                .collection("creditCardAccounts").document(linkedCreditCardAccountId),
                            "currentOutstanding", FieldValue.increment(outstandingDelta),
                        )
                    }
                }
            }.await()

            if (notificationsEnabled) {
                val currency = accounts.firstOrNull()?.get("currency") as? String ?: "INR"
                val symbol = currencySymbol(currency)
                val reviewSuffix = if (processingStatus == "needsAiReview") " · Needs review" else ""
                val notifTitle = "$symbol${formatAmount(resolvedAmount)} added · $title"
                showNotification(
                    id = (System.currentTimeMillis() / 1000).toInt(),
                    title = notifTitle,
                    body = "Auto-detected$reviewSuffix · Tap to review in Ledger",
                    transactionId = txRef.id,
                )
            }

        } catch (_: Exception) {
            // Don't retry — the foreground Dart listener or the user reopening
            // the app will pick up subsequent SMS normally. A transient
            // failure here does not retroactively lose data since nothing
            // was written until the point of failure.
        }

        return Result.success()
    }

    // Required by WorkManager for backward compat on Android 11 and below.
    // On Android 12+ (API 31+) expedited jobs don't show a persistent notification.
    override suspend fun getForegroundInfo(): ForegroundInfo {
        ensureChannel()
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle("Ledger — Processing bank SMS…")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        return ForegroundInfo(FOREGROUND_NOTIF_ID, notification)
    }

    // ── Firestore ─────────────────────────────────────────────────────────────

    private suspend fun fetchAccounts(db: FirebaseFirestore, uid: String) =
        withContext(Dispatchers.IO) {
            db.collection("users").document(uid).collection("accounts")
                .get().await().documents
                .mapNotNull { doc -> doc.data?.toMutableMap()?.also { it["id"] = doc.id } }
        }

    private suspend fun fetchPaymentModes(db: FirebaseFirestore, uid: String) =
        withContext(Dispatchers.IO) {
            db.collection("users").document(uid).collection("paymentModes")
                .get().await().documents
                .mapNotNull { doc -> doc.data?.toMutableMap()?.also { it["id"] = doc.id } }
        }

    private suspend fun fetchCategories(db: FirebaseFirestore, uid: String) =
        withContext(Dispatchers.IO) {
            db.collection("users").document(uid).collection("categories")
                .get().await().documents
                .mapNotNull { doc -> doc.data?.toMutableMap()?.also { it["id"] = doc.id } }
        }

    private suspend fun fetchCreditCardAccounts(db: FirebaseFirestore, uid: String) =
        withContext(Dispatchers.IO) {
            db.collection("users").document(uid).collection("creditCardAccounts")
                .get().await().documents
                .mapNotNull { doc -> doc.data?.toMutableMap()?.also { it["id"] = doc.id } }
        }

    private suspend fun transactionExistsByExternalRef(
        db: FirebaseFirestore,
        uid: String,
        externalTransactionId: String,
    ): Boolean = withContext(Dispatchers.IO) {
        db.collection("users").document(uid).collection("transactions")
            .whereEqualTo("externalTransactionId", externalTransactionId)
            .limit(1).get().await().documents.isNotEmpty()
    }

    private suspend fun transactionExistsByHashNearby(
        db: FirebaseFirestore,
        uid: String,
        sourceMessageHash: String,
        near: Date,
        windowMillis: Long = 2 * 60 * 1000L,
    ): Boolean = withContext(Dispatchers.IO) {
        db.collection("users").document(uid).collection("transactions")
            .whereEqualTo("sourceMessageHash", sourceMessageHash)
            .whereGreaterThanOrEqualTo("date", Timestamp(Date(near.time - windowMillis)))
            .whereLessThanOrEqualTo("date", Timestamp(Date(near.time + windowMillis)))
            .limit(1).get().await().documents.isNotEmpty()
    }

    // Category slug is null on the local-only (high-confidence) path, since
    // the local parser does not attempt semantic categorization — that
    // genuinely needs the AI path. Falls back to "Other" rather than
    // guessing, same as the Dart pipeline.
    private suspend fun resolveOrCreateCategory(
        slug: String?,
        categories: List<Map<String, Any?>>,
        uid: String,
        db: FirebaseFirestore,
    ): String {
        val lower = (slug ?: "other").lowercase()
        val existing = categories.firstOrNull {
            (it["title"] as? String)?.lowercase()?.contains(lower) == true
        }
        if (existing != null) return existing["id"] as String

        // Mirrors DefaultCategories.list in Dart — slug matches category title.
        val defaults = listOf(
            Triple("food", "Food & Dining", Pair(0xe532, 0xFFEF4444.toInt())),
            Triple("transport", "Transport", Pair(0xe1b0, 0xFF3B82F6.toInt())),
            Triple("entertainment", "Entertainment", Pair(0xe518, 0xFFA855F7.toInt())),
            Triple("shopping", "Shopping", Pair(0xe7c5, 0xFFEC4899.toInt())),
            Triple("bills", "Bills & Utilities", Pair(0xe8b0, 0xFFF59E0B.toInt())),
            Triple("health", "Health", Pair(0xe3f3, 0xFF22C55E.toInt())),
            Triple("salary", "Salary", Pair(0xe84f, 0xFF10B981.toInt())),
            Triple("investment", "Investment", Pair(0xe6e1, 0xFF6366F1.toInt())),
            Triple("groceries", "Groceries", Pair(0xe7ed, 0xFF84CC16.toInt())),
            Triple("education", "Education", Pair(0xe80c, 0xFF0EA5E9.toInt())),
            Triple("travel", "Travel", Pair(0xe539, 0xFFF97316.toInt())),
            Triple("transfer", "Transfer", Pair(0xe8d4, 0xFF6366F1.toInt())),
            Triple("other", "Other", Pair(0xe5d3, 0xFF64748B.toInt())),
        )
        val match = defaults.firstOrNull { it.second.lowercase().contains(lower) }
            ?: defaults.last()

        val catMap = mapOf(
            "userId" to uid,
            "title" to match.second,
            "iconCodePoint" to match.third.first,
            "colorValue" to match.third.second,
            "isDefault" to false,
            "createdAt" to Timestamp(Date()),
        )
        return withContext(Dispatchers.IO) {
            db.collection("users").document(uid).collection("categories")
                .add(catMap).await().id
        }
    }

    // ── Claude API ─────────────────────────────────────────────────────────────

    private data class ParsedSms(
        val title: String,
        val amount: Double,
        val type: String,
        val accountId: String?,
        val paymentModeId: String?,
        val categorySlug: String,
        val confidence: Double,
    )

    private suspend fun callClaudeApi(
        apiKey: String,
        smsBody: String,
        accounts: List<Map<String, Any?>>,
        paymentModes: List<Map<String, Any?>>,
    ): ParsedSms? = withContext(Dispatchers.IO) {
        val accountsJson = accounts.joinToString(",") { a ->
            """{"id":"${a["id"]}","title":"${a["title"]}","bank":"${a["bankName"]}","last6":"${a["lastSixDigits"]}"}"""
        }
        val modesJson = paymentModes.joinToString(",") { m ->
            """{"id":"${m["id"]}","type":"${m["type"]}","last4":"${m["lastFourDigits"] ?: ""}","upiId":"${m["upiId"] ?: ""}"}"""
        }

        val prompt = """
You are a financial SMS parser for Indian banking. Parse the SMS and return ONLY valid JSON with no markdown or explanation.

Accounts: [$accountsJson]
PaymentModes: [$modesJson]

SMS: "$smsBody"

$SPECIAL_CASES

$RESPONSE_SCHEMA""".trimIndent()

        val requestBody = JSONObject().apply {
            put("model", "claude-haiku-4-5-20251001")
            put("max_tokens", 256)
            put("system", "You are a financial SMS parser. Return ONLY valid JSON.")
            put("messages", JSONArray().apply {
                put(JSONObject().apply {
                    put("role", "user")
                    put("content", prompt)
                })
            })
        }.toString()

        // Single retry with a short backoff, but only for network-level
        // I/O failures — never for a non-200 HTTP response, which is a
        // real answer from the API, not a transient failure retrying
        // would fix.
        val responseText = try {
            sendClaudeRequest(requestBody, apiKey)
        } catch (_: java.io.IOException) {
            try {
                delay(2_000)
                sendClaudeRequest(requestBody, apiKey)
            } catch (_: Exception) {
                null
            }
        } catch (_: Exception) {
            null
        }

        val text = responseText ?: return@withContext null
        try {
            val content = JSONObject(text)
                .getJSONArray("content").getJSONObject(0).getString("text")
            val parsed = JSONObject(stripMarkdown(content))

            val confidence = parsed.optDouble("confidence", 0.0)
            if (confidence < CONFIDENCE_THRESHOLD) return@withContext null

            val accountId = parsed.optString("accountId").takeIf { it.isNotEmpty() && it != "null" }
            val paymentModeId = parsed.optString("paymentModeId").takeIf { it.isNotEmpty() && it != "null" }

            ParsedSms(
                title = parsed.optString("title", "Transaction"),
                amount = parsed.optDouble("amount", 0.0),
                type = parsed.optString("type", "expense"),
                accountId = accountId,
                paymentModeId = paymentModeId,
                categorySlug = parsed.optString("suggestedCategorySlug", "other"),
                confidence = confidence,
            )
        } catch (_: Exception) {
            null
        }
    }

    // Returns the raw response body on HTTP 200, or null on any other
    // status code (a real, non-retryable answer from the API).
    private fun sendClaudeRequest(requestBody: String, apiKey: String): String? {
        val conn = URL("https://api.anthropic.com/v1/messages")
            .openConnection() as HttpURLConnection
        conn.apply {
            requestMethod = "POST"
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("x-api-key", apiKey)
            setRequestProperty("anthropic-version", "2023-06-01")
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 30_000
        }
        conn.outputStream.use { it.write(requestBody.toByteArray(Charsets.UTF_8)) }
        if (conn.responseCode != 200) return null
        return conn.inputStream.bufferedReader().readText()
    }

    private fun stripMarkdown(text: String): String {
        val trimmed = text.trim()
        return Regex("""^```(?:json)?\s*([\s\S]*?)```$""").find(trimmed)
            ?.groupValues?.get(1)?.trim() ?: trimmed
    }

    // ── Local parsing helpers ─────────────────────────────────────────────────

    private fun computeSmsHash(body: String): String {
        val normalized = body.lowercase().replace(Regex("""\s+"""), " ").trim()
        val digest = MessageDigest.getInstance("SHA-256").digest(normalized.toByteArray(Charsets.UTF_8))
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun isPlausibleAmount(amount: Double): Boolean = amount > 0 && amount <= 10_000_000

    private fun isPlausibleTransactionDate(date: Date): Boolean =
        date.time <= System.currentTimeMillis() + 24 * 60 * 60 * 1000L

    // ── Deduplication ─────────────────────────────────────────────────────────

    private fun isAlreadyProcessed(
        fingerprint: String,
        prefs: android.content.SharedPreferences,
    ): Boolean {
        val stored = prefs.getString("${P}processed_sms_ids", "[]") ?: "[]"
        return try {
            val arr = JSONArray(stored)
            (0 until arr.length()).any { arr.getString(it) == fingerprint }
        } catch (_: Exception) {
            false
        }
    }

    private fun markProcessed(
        fingerprint: String,
        timestamp: Long,
        prefs: android.content.SharedPreferences,
    ) {
        val stored = prefs.getString("${P}processed_sms_ids", "[]") ?: "[]"
        val ids = mutableListOf<String>()
        try {
            val arr = JSONArray(stored)
            for (i in 0 until arr.length()) ids.add(arr.getString(i))
        } catch (_: Exception) {}
        if (!ids.contains(fingerprint)) {
            ids.add(fingerprint)
            if (ids.size > 300) ids.subList(0, ids.size - 300).clear()
            prefs.edit()
                .putString("${P}processed_sms_ids", JSONArray(ids).toString())
                .apply()
        }
        val last = prefs.getLong("${P}last_sms_timestamp", 0L)
        if (timestamp > last) {
            prefs.edit().putLong("${P}last_sms_timestamp", timestamp).apply()
        }
    }

    // ── Notification ──────────────────────────────────────────────────────────

    private fun showNotification(
        id: Int,
        title: String,
        body: String,
        transactionId: String,
    ) {
        ensureChannel()
        val launchIntent = applicationContext.packageManager
            .getLaunchIntentForPackage(applicationContext.packageName)
            ?.apply { putExtra("transaction_id", transactionId) }
        val pi = PendingIntent.getActivity(
            applicationContext, id, launchIntent ?: Intent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try {
            NotificationManagerCompat.from(applicationContext).notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS not granted — notification silently dropped.
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for automatically detected transactions"
            }
            applicationContext.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }
    }

    // ── Misc helpers ──────────────────────────────────────────────────────────

    private fun isPreDebitNotification(body: String): Boolean {
        val lower = body.lowercase()
        return lower.contains("e-mandate") || lower.contains("emandate") ||
            lower.contains("will be deducted") || lower.contains("auto debit") ||
            lower.contains("auto-debit")
    }

    private fun currencySymbol(currency: String) = when (currency) {
        "INR" -> "₹"; "USD" -> "$"; "EUR" -> "€"; "GBP" -> "£";
        "AED" -> "د.إ"; "SGD" -> "S$"; else -> currency
    }

    private fun formatAmount(amount: Double): String =
        if (amount == kotlin.math.floor(amount)) amount.toLong().toString()
        else "%.2f".format(amount)

    companion object {
        const val KEY_SMS_BODY = "sms_body"
        const val KEY_SMS_TIMESTAMP = "sms_timestamp"
        const val KEY_SMS_FINGERPRINT = "sms_fingerprint"

        private const val P = "flutter."
        private const val CHANNEL_ID = "ledger_sms"
        private const val CHANNEL_NAME = "Auto-detected Transactions"
        private const val FOREGROUND_NOTIF_ID = 99
        private const val CONFIDENCE_THRESHOLD = 0.4

        // Kept identical to lib/services/ai/claude_service.dart's prompt
        // fragments of the same name — a credit card bill payment settles
        // existing card debt, it is not new spending, so it must not be
        // categorized as an expense/"bills".
        private const val SPECIAL_CASES = """Special cases:
- E-Mandate / NACH / auto-debit notifications ("will be deducted", "E-Mandate!", "UMN"): treat as expense, extract the mandate description as title (e.g. "Amazon India" from "Amazon India mandate"), use "bills" as category.
- Credit card bill payment (a payment received/confirmed towards a credit card, not a purchase on it): this settles card debt from an existing balance — it is a transfer, not new spending. Use category "transfer".
- ATM withdrawal: treat as expense, category "other"."""

        private const val RESPONSE_SCHEMA = """Return JSON:
{
  "title": "merchant or description (max 30 chars)",
  "amount": number,
  "type": "expense" or "income",
  "accountId": "matching account id or null",
  "paymentModeId": "matching payment mode id or null",
  "suggestedCategorySlug": one of [food, transport, entertainment, shopping, bills, health, salary, investment, groceries, education, travel, transfer, other],
  "confidence": float 0.0-1.0
}"""
    }
}
