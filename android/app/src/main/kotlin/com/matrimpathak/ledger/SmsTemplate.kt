package com.matrimpathak.ledger

/**
 * Kotlin counterpart of lib/models/sms_template.dart — see that file's
 * doc comment for the full design rationale (self-improving parsing
 * tier, why templates are safe to share globally, why the skeleton
 * alone is the single source of truth). Kept field-for-field identical
 * so a template learned by either platform's AI call is usable by both.
 */
data class SmsTemplate(
    val id: String,
    val bank: String,
    val bankCode: String,
    val transactionType: String,
    val direction: String?,
    val paymentMethod: String?,
    val txnCategoryHint: String?,
    val skeleton: String,
    val templateConfidence: Double,
    val matchCount: Int = 0,
) {
    /** See SmsTemplate.senderMatches in local_sms_parser.dart. */
    fun senderMatches(sender: String?): Boolean {
        if (bankCode.isEmpty()) return true
        if (sender.isNullOrEmpty()) return false
        return sender.uppercase().contains(bankCode.uppercase())
    }

    fun tryMatch(body: String): SmsTemplateExtraction? =
        SmsTemplateCompiler.compile(skeleton)?.match(body)
}

data class SmsTemplateExtraction(
    val amount: Double?,
    val referenceNumber: String?,
    val merchantCandidate: String?,
    val accountLastDigits: String?,
)

/**
 * Fixed placeholder vocabulary — kept identical to placeholderPatterns in
 * lib/models/sms_template.dart. Deliberately closed: an unrecognized
 * placeholder type fails the whole template to compile rather than
 * falling back to a guessed pattern, since a wrong regex here would
 * silently corrupt shared, cross-user parsing data.
 */
val placeholderPatterns: Map<String, String> = mapOf(
    "amount" to """[0-9][0-9,]*(?:\.[0-9]{1,2})?""",
    "balance" to """[0-9][0-9,]*(?:\.[0-9]{1,2})?""",
    "refno" to """[A-Za-z0-9]{6,}""",
    "acct_last4" to """[0-9]{4}""",
    "acct_last6" to """[0-9]{4,6}""",
    "card_last4" to """[0-9]{4}""",
    "phone" to """[0-9]{6,12}""",
    "date" to """[0-9]{1,2}[-/][A-Za-z0-9]{2,4}[-/][0-9]{2,4}""",
    "time" to """[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\s*(?:[AaPp][Mm])?""",
    "merchant" to """.{2,40}?""",
    "vpa" to """[A-Za-z0-9.\-_]{2,40}@[A-Za-z0-9.\-_]{2,20}""",
    "bank_name" to """[A-Za-z ]{2,25}""",
)

private val amountTypes = setOf("amount")
private val refTypes = setOf("refno")
private val merchantTypes = setOf("merchant", "vpa")
private val digitTypes = setOf("acct_last4", "acct_last6", "card_last4")
private val placeholderToken = Regex("""\{([a-z0-9_]+)\}""")

/** Kotlin counterpart of SmsTemplateCompiler in lib/models/sms_template.dart. */
class SmsTemplateCompiler private constructor(
    private val regex: Regex,
    private val typesByGroup: List<String>,
) {
    fun match(body: String): SmsTemplateExtraction? {
        val m = regex.find(body) ?: return null

        var amount: Double? = null
        var referenceNumber: String? = null
        var merchantCandidate: String? = null
        var accountLastDigits: String? = null

        for (i in typesByGroup.indices) {
            val type = typesByGroup[i]
            val raw = m.groupValues.getOrNull(i + 1)?.trim()
            if (raw.isNullOrEmpty()) continue

            when {
                amount == null && type in amountTypes ->
                    amount = raw.replace(",", "").toDoubleOrNull()
                referenceNumber == null && type in refTypes ->
                    referenceNumber = raw
                merchantCandidate == null && type in merchantTypes ->
                    merchantCandidate = raw.replace(Regex("""\s+"""), " ")
                accountLastDigits == null && type in digitTypes ->
                    accountLastDigits = raw
            }
        }

        return SmsTemplateExtraction(amount, referenceNumber, merchantCandidate, accountLastDigits)
    }

    companion object {
        /**
         * Returns null (never throws) for a skeleton that doesn't compile
         * to a safe, well-formed matcher — see the Dart counterpart's doc
         * comment for the exact rejection conditions.
         */
        fun compile(skeleton: String): SmsTemplateCompiler? {
            if (skeleton.isEmpty() || skeleton.length > 500) return null
            if (!skeleton.contains("{amount}")) return null

            val buffer = StringBuilder()
            val types = mutableListOf<String>()
            var lastEnd = 0
            var lastWasPlaceholder = false

            for (match in placeholderToken.findAll(skeleton)) {
                val literal = skeleton.substring(lastEnd, match.range.first)
                if (lastWasPlaceholder && literal.isEmpty()) return null
                buffer.append(Regex.escape(literal))

                val type = match.groupValues[1]
                val pattern = placeholderPatterns[type] ?: return null

                buffer.append("(").append(pattern).append(")")
                types.add(type)
                lastEnd = match.range.last + 1
                lastWasPlaceholder = true
            }
            buffer.append(Regex.escape(skeleton.substring(lastEnd)))

            if (types.isEmpty()) return null

            return try {
                SmsTemplateCompiler(Regex(buffer.toString(), RegexOption.IGNORE_CASE), types)
            } catch (_: Exception) {
                null
            }
        }
    }
}
