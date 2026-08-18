package com.matrimpathak.ledger

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Result of running the declarative rule set (assets/sms_patterns/
 * bank_patterns.json, bundled into flutter_assets/) against a single SMS
 * body. Never throws — an SMS that matches nothing still yields a result
 * with low/zero confidence rather than null.
 *
 * Kotlin counterpart of lib/services/sms/local_sms_parser.dart — both
 * interpreters are asserted against the exact same
 * test/fixtures/sms_samples.json so they can't silently drift apart. See
 * the Dart file's doc comment for the full confidence rubric.
 */
data class LocalParseResult(
    val amount: Double?,
    val direction: String?,
    val paymentMethod: String?,
    val txnCategoryHint: String?,
    val referenceNumber: String?,
    val merchantCandidate: String?,
    val accountLastDigits: String?,
    val matchedAccountId: String?,
    val matchedPaymentModeId: String?,
    val matchedRuleId: String,
    val confidence: Double,
) {
    val isHighConfidence: Boolean get() = confidence >= 0.80
    val isMediumConfidence: Boolean get() = confidence >= 0.40 && confidence < 0.80
    val isLowConfidence: Boolean get() = confidence < 0.40
}

class LocalSmsParser(private val rules: JSONObject) {

    constructor(rulesJson: String) : this(JSONObject(rulesJson))

    private val amountRegex = Regex(rules.getString("amountRegex"), RegexOption.IGNORE_CASE)
    private val accountLastDigitsRegex: Regex? =
        rules.optStringOrNull("accountLastDigitsRegex")?.let { Regex(it, RegexOption.IGNORE_CASE) }
    private val ruleList: List<JSONObject> = rules.getJSONArray("rules").let { arr ->
        (0 until arr.length()).map { arr.getJSONObject(it) }
    }

    /**
     * [accounts]/[paymentModes] entries are plain maps mirroring the shape
     * SmsProcessingWorker already fetches from Firestore: each account map
     * has "id" and "lastSixDigits", each payment-mode map has "id" and
     * "lastFourDigits".
     */
    fun parse(
        body: String,
        accounts: List<Map<String, Any?>> = emptyList(),
        paymentModes: List<Map<String, Any?>> = emptyList(),
    ): LocalParseResult {
        val lower = body.lowercase()
        val matchedRule = ruleList.firstOrNull { ruleMatches(it, lower) }

        val amount = extractAmount(body)
        val refNumber = matchedRule?.optStringOrNull("refNumberRegex")?.let { extractGroup(body, it) }
        val merchant = matchedRule?.optStringOrNull("merchantRegex")?.let { extractGroup(body, it) }
        val lastDigits = accountLastDigitsRegex?.let { firstGroup(body, it) }

        val direction = matchedRule?.optStringOrNull("direction") ?: inferDirection(lower)
        val paymentMethod = matchedRule?.optStringOrNull("paymentMethod")
        val txnCategoryHint = matchedRule?.optStringOrNull("txnCategoryHint")

        var matchedAccountId: String? = null
        var matchedPaymentModeId: String? = null
        var instrumentMatch = false
        if (lastDigits != null) {
            for (account in accounts) {
                val digits = account["lastSixDigits"] as? String
                if (digits != null && digitsSuffixMatch(lastDigits, digits)) {
                    matchedAccountId = account["id"] as? String
                    instrumentMatch = true
                    break
                }
            }
            for (mode in paymentModes) {
                val digits = mode["lastFourDigits"] as? String
                if (digits != null && digitsSuffixMatch(lastDigits, digits)) {
                    matchedPaymentModeId = mode["id"] as? String
                    instrumentMatch = true
                    break
                }
            }
        }

        var points = 0
        if (amount != null) points += 30
        if (direction != null) points += 20
        if (!refNumber.isNullOrEmpty()) points += 15
        if (instrumentMatch) points += 20
        if (paymentMethod != null) points += 10
        if (!merchant.isNullOrEmpty()) points += 5

        return LocalParseResult(
            amount = amount,
            direction = direction,
            paymentMethod = paymentMethod,
            txnCategoryHint = txnCategoryHint,
            referenceNumber = refNumber,
            merchantCandidate = merchant,
            accountLastDigits = lastDigits,
            matchedAccountId = matchedAccountId,
            matchedPaymentModeId = matchedPaymentModeId,
            matchedRuleId = matchedRule?.optString("id") ?: "none",
            confidence = points / 100.0,
        )
    }

    private fun ruleMatches(rule: JSONObject, lower: String): Boolean {
        val keywords = rule.optJSONArray("keywords")?.toStringList() ?: emptyList()
        val requireKeywords = rule.optJSONArray("requireKeywords")?.toStringList() ?: emptyList()
        val excludeKeywords = rule.optJSONArray("excludeKeywords")?.toStringList() ?: emptyList()
        if (keywords.isEmpty() || keywords.none { lower.contains(it) }) return false
        if (requireKeywords.isNotEmpty() && requireKeywords.none { lower.contains(it) }) return false
        if (excludeKeywords.any { lower.contains(it) }) return false
        return true
    }

    private fun extractAmount(body: String): Double? {
        val match = amountRegex.find(body) ?: return null
        val raw = match.groupValues.getOrNull(1)?.replace(",", "") ?: return null
        return raw.toDoubleOrNull()
    }

    private fun extractGroup(body: String, pattern: String): String? {
        val regex = Regex(pattern, RegexOption.IGNORE_CASE)
        val match = regex.find(body) ?: return null
        val group = match.groupValues.getOrNull(1)?.trim()
        return if (group.isNullOrEmpty()) null else group
    }

    private fun firstGroup(body: String, regex: Regex): String? {
        val match = regex.find(body) ?: return null
        return match.groupValues.getOrNull(1)?.trim()
    }

    private fun inferDirection(lower: String): String? {
        val debited = lower.contains("debited")
        val credited = lower.contains("credited")
        return when {
            debited && !credited -> "debit"
            credited && !debited -> "credit"
            else -> null
        }
    }

    /**
     * True when [extractedDigits] (last 4-6 digits from the SMS) matches
     * the trailing digits of [knownDigits] (or vice versa, since the SMS
     * and the stored account/payment-mode may record a different number of
     * digits).
     */
    private fun digitsSuffixMatch(extractedDigits: String, knownDigits: String): Boolean {
        if (extractedDigits.isEmpty() || knownDigits.isEmpty()) return false
        val shorter = if (extractedDigits.length <= knownDigits.length) extractedDigits else knownDigits
        val longer = if (extractedDigits.length <= knownDigits.length) knownDigits else extractedDigits
        return longer.endsWith(shorter)
    }

    companion object {
        fun loadFromAssets(context: Context): LocalSmsParser =
            LocalSmsParser(RulesCache.get(context))
    }
}

private fun JSONObject.optStringOrNull(key: String): String? {
    if (!has(key) || isNull(key)) return null
    val value = optString(key)
    return value.ifEmpty { null }
}

private fun JSONArray.toStringList(): List<String> = (0 until length()).map { getString(it) }
