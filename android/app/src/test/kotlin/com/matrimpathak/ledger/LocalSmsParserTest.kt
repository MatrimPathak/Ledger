package com.matrimpathak.ledger

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * JVM unit test (no Android framework dependency) for LocalSmsParser,
 * asserted against the exact same test/fixtures/sms_samples.json fixture
 * file the Dart test (test/services/sms/local_sms_parser_test.dart) uses —
 * this is what catches the two interpreters drifting apart, since both are
 * held to identical expected extraction for identical input.
 *
 * Paths are relative to the Gradle module's working directory
 * (android/app/), hence the "../../" to reach the repo root.
 */
class LocalSmsParserTest {

    private val rules = JSONObject(
        File("../../assets/sms_patterns/bank_patterns.json").readText()
    )
    private val parser = LocalSmsParser(rules)
    private val samples = JSONObject(
        File("../../test/fixtures/sms_samples.json").readText()
    ).getJSONArray("samples")

    @Test
    fun `every fixture sample extracts the expected fields and confidence tier`() {
        for (i in 0 until samples.length()) {
            val sample = samples.getJSONObject(i)
            val id = sample.getString("id")
            val body = sample.getString("body")
            val expected = sample.getJSONObject("expected")

            val result = parser.parse(body)

            assertEquals("[$id] amount", expected.optNullableDouble("amount"), result.amount)
            assertEquals("[$id] direction", expected.optNullableString("direction"), result.direction)
            assertEquals("[$id] paymentMethod", expected.optNullableString("paymentMethod"), result.paymentMethod)
            assertEquals("[$id] txnCategoryHint", expected.optNullableString("txnCategoryHint"), result.txnCategoryHint)
            assertEquals("[$id] referenceNumber", expected.optNullableString("referenceNumber"), result.referenceNumber)
            assertEquals("[$id] merchantCandidate", expected.optNullableString("merchantCandidate"), result.merchantCandidate)
            assertEquals("[$id] accountLastDigits", expected.optNullableString("accountLastDigits"), result.accountLastDigits)
            assertEquals("[$id] matchedRuleId", expected.getString("matchedRuleId"), result.matchedRuleId)

            when (expected.getString("tier")) {
                "high" -> assertTrue("[$id] expected high confidence, got ${result.confidence}", result.isHighConfidence)
                "medium" -> assertTrue("[$id] expected medium confidence, got ${result.confidence}", result.isMediumConfidence)
                "low" -> assertTrue("[$id] expected low confidence, got ${result.confidence}", result.isLowConfidence)
            }
        }
    }

    @Test
    fun `matching a known account last-digits adds the instrument bonus`() {
        val body = "INR 12000.00 debited from your account for NEFT transfer to A/C XX4321. Avl Bal INR 45000.00"
        val without = parser.parse(body)
        val withAccount = parser.parse(
            body,
            accounts = listOf(mapOf("id" to "acc-1", "lastSixDigits" to "564321")),
        )

        assertEquals("acc-1", withAccount.matchedAccountId)
        assertEquals(0.20, withAccount.confidence - without.confidence, 0.001)
    }

    @Test
    fun `matching a known payment mode last-digits adds the instrument bonus`() {
        val body = "Rs.4500.00 spent using your Credit Card XX9988 at a merchant on 12-08-26."
        val without = parser.parse(body)
        val withMode = parser.parse(
            body,
            paymentModes = listOf(mapOf("id" to "mode-1", "lastFourDigits" to "9988")),
        )

        assertEquals("mode-1", withMode.matchedPaymentModeId)
        assertEquals(0.20, withMode.confidence - without.confidence, 0.001)
    }

    // A shape no static rule in bank_patterns.json covers at all — it
    // deliberately avoids every rule-triggering keyword ("debited",
    // "credited", "upi", "credit card", "atm", "refund"), same as the
    // real HDFC "Sent"/"Received" format that motivated this tier.
    private val iciciTemplate = SmsTemplate(
        id = "tpl-icici-debit",
        bank = "ICICI Bank",
        bankCode = "ICICIB",
        transactionType = "bank_debit",
        direction = "debit",
        paymentMethod = "bankTransfer",
        txnCategoryHint = null,
        skeleton = "ICICI Alert: INR {amount} moved from A/C XX{acct_last4} to {merchant} on {date}. Ref {refno}.",
        templateConfidence = 0.92,
    )
    private val iciciBody = "ICICI Alert: INR 1250.50 moved from A/C XX7788 to BLINKIT on 19-Aug-26. Ref 445566778899."

    @Test
    fun `falls back to a matching template when no static rule fits`() {
        val result = parser.parse(iciciBody, sender = "AD-ICICIB-S", templates = listOf(iciciTemplate))

        assertEquals("template", result.matchedRuleId)
        assertEquals("tpl-icici-debit", result.matchedTemplateId)
        assertEquals(1250.5, result.amount!!, 0.001)
        assertEquals("debit", result.direction)
        assertEquals("bankTransfer", result.paymentMethod)
        assertEquals("445566778899", result.referenceNumber)
        assertEquals("BLINKIT", result.merchantCandidate)
        assertEquals("7788", result.accountLastDigits)
        assertTrue(result.isHighConfidence)
    }

    @Test
    fun `a template from a different bank's sender is not tried`() {
        val result = parser.parse(iciciBody, sender = "VM-HDFCBK-T", templates = listOf(iciciTemplate))

        assertEquals("none", result.matchedRuleId)
        assertNull(result.matchedTemplateId)
    }

    @Test
    fun `a static rule match takes priority over a template`() {
        // upi_debit already covers this shape via bank_patterns.json's own
        // rules — the template tier must never be consulted once a static
        // rule fires, so a bad/duplicate learned template can't override
        // hand-verified extraction.
        val body = "Rs.286.00 debited from A/C XX1234 to VPA rajesh@okhdfc on " +
            "15-08-26. UPI Ref No 402312345678. Not you? Call 1800123456"
        val decoy = SmsTemplate(
            id = "decoy",
            bank = "HDFC Bank",
            bankCode = "", // matches any sender, to prove the rule still wins
            transactionType = "other",
            direction = "credit", // deliberately wrong, to prove it's unused
            paymentMethod = null,
            txnCategoryHint = null,
            skeleton = "totally different shape {amount}",
            templateConfidence = 0.9,
        )

        val result = parser.parse(body, templates = listOf(decoy))

        assertEquals("upi_debit", result.matchedRuleId)
        assertNull(result.matchedTemplateId)
        assertEquals("debit", result.direction)
    }

    @Test
    fun `disambiguates between several UPI modes on different accounts by account plus type`() {
        val body = "Sent Rs.500.00\n" +
            "From HDFC Bank A/C *4321\n" +
            "To Test Merchant\n" +
            "On 18-08-26\n" +
            "Ref 999888777666\n" +
            "Not You?\n" +
            "Call 18002586161/SMS BLOCK UPI to 7308080808"

        val accounts = listOf(
            mapOf("id" to "acc-1", "lastSixDigits" to "004321"),
            mapOf("id" to "acc-2", "lastSixDigits" to "009988"),
        )
        val paymentModes = listOf(
            mapOf("id" to "upi-on-acc2", "type" to "upi", "accountId" to "acc-2"),
            mapOf("id" to "upi-on-acc1", "type" to "upi", "accountId" to "acc-1"),
            mapOf("id" to "card-on-acc1", "type" to "debitCard", "accountId" to "acc-1"),
        )

        val result = parser.parse(body, accounts = accounts, paymentModes = paymentModes)

        assertEquals("acc-1", result.matchedAccountId)
        assertEquals("upi-on-acc1", result.matchedPaymentModeId)
    }

    @Test
    fun `an empty string yields zero confidence and no rule match`() {
        val result = parser.parse("")

        assertNull(result.amount)
        assertEquals("none", result.matchedRuleId)
        assertEquals(0.0, result.confidence, 0.0)
        assertTrue(result.isLowConfidence)
    }
}

private fun JSONObject.optNullableDouble(key: String): Double? =
    if (!has(key) || isNull(key)) null else getDouble(key)

private fun JSONObject.optNullableString(key: String): String? =
    if (!has(key) || isNull(key)) null else getString(key)
