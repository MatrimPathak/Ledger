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
