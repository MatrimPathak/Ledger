package com.matrimpathak.ledger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit test for SmsTemplateCompiler, mirroring
 * test/models/sms_template_test.dart so both interpreters are held to
 * the same compiled-matching and rejection behavior.
 */
class SmsTemplateTest {

    // A shape none of assets/sms_patterns/bank_patterns.json's static
    // rules cover — proves the template tier can handle a bank format
    // never hand-coded.
    private val skeleton = "ICICI Bank Acct XX{acct_last4} debited with INR {amount} on " +
        "{date}; info: {merchant} (UPI Ref no {refno})"
    private val body = "ICICI Bank Acct XX7788 debited with INR 1250.50 on 19-Aug-26; " +
        "info: BLINKIT (UPI Ref no 445566778899)"

    @Test
    fun `compiles and extracts every mapped field from a novel shape`() {
        val compiled = SmsTemplateCompiler.compile(skeleton)
        assertNotNull(compiled)

        val result = compiled!!.match(body)
        assertNotNull(result)
        assertEquals(1250.5, result!!.amount!!, 0.001)
        assertEquals("445566778899", result.referenceNumber)
        assertEquals("BLINKIT", result.merchantCandidate)
        assertEquals("7788", result.accountLastDigits)
    }

    @Test
    fun `placeholder types with digits in their name still compile`() {
        // Regression: the token regex must accept digits in the type
        // name, not just letters/underscore — acct_last4 etc. would
        // otherwise be left as literal "{acct_last4}" text, which can
        // never match real SMS content, silently breaking every template
        // using that type.
        for (type in listOf("acct_last4", "acct_last6", "card_last4")) {
            val compiled = SmsTemplateCompiler.compile("Card {$type} charged {amount}")
            assertNotNull("$type should compile", compiled)
            val match = compiled!!.match("Card 1234 charged 500.00")
            assertNotNull("$type should match", match)
            assertEquals("1234", match!!.accountLastDigits)
        }
    }

    @Test
    fun `rejects a skeleton using an unrecognized placeholder type`() {
        assertNull(SmsTemplateCompiler.compile("Paid {amount} to {unknown_type}"))
    }

    @Test
    fun `rejects two placeholders with no literal text between them`() {
        assertNull(SmsTemplateCompiler.compile("{merchant}{amount}"))
    }

    @Test
    fun `rejects a skeleton with no amount placeholder at all`() {
        assertNull(SmsTemplateCompiler.compile("Hello {merchant}, OTP is {refno}"))
    }

    @Test
    fun `a compiled template returns null against unrelated text`() {
        val compiled = SmsTemplateCompiler.compile(skeleton)
        assertNull(compiled!!.match("Some totally unrelated SMS with no structure"))
    }

    private val template = SmsTemplate(
        id = "t1",
        bank = "ICICI Bank",
        bankCode = "ICICIB",
        transactionType = "bank_debit",
        direction = null,
        paymentMethod = null,
        txnCategoryHint = null,
        skeleton = "x {amount}",
        templateConfidence = 0.9,
    )

    @Test
    fun `senderMatches matches when the sender contains the bank code`() {
        assertTrue(template.senderMatches("AD-ICICIB-S"))
        assertTrue(template.senderMatches("VM-ICICIB-T"))
    }

    @Test
    fun `senderMatches does not match a different bank's sender`() {
        assertFalse(template.senderMatches("VM-HDFCBK-T"))
    }

    @Test
    fun `senderMatches does not match a null or empty sender`() {
        assertFalse(template.senderMatches(null))
        assertFalse(template.senderMatches(""))
    }
}
