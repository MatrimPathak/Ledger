package com.matrimpathak.ledger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * JVM unit test (no Android framework dependency) for
 * SmsProcessingWorker.redactSensitiveDigits, asserted against the same
 * cases as the Dart counterpart (test/services/ai/claude_service_test.dart's
 * redactSensitiveDigits group) so both interpreters stay in lockstep.
 */
class SmsRedactionTest {

    @Test
    fun `masks a 6+ digit balance figure near a balance keyword`() {
        val body = "Rs.286.00 debited from A/C XX1234. Avl Bal Rs.125430.50"

        val redacted = SmsProcessingWorker.redactSensitiveDigits(body)

        assertFalse(redacted.contains("125430"))
        assertTrue(redacted.contains("A/C XX1234"))
        assertTrue(redacted.contains("Rs.286.00"))
    }

    @Test
    fun `masks a comma-grouped balance figure`() {
        val body = "Available balance is Rs.12,345.67"

        val redacted = SmsProcessingWorker.redactSensitiveDigits(body)

        assertFalse(redacted.contains("12,345"))
    }

    @Test
    fun `leaves short last-4-digit references untouched`() {
        val body = "A/C XX1234 debited by Rs.450.00"

        assertEquals(body, SmsProcessingWorker.redactSensitiveDigits(body))
    }

    @Test
    fun `leaves amounts unrelated to account-balance keywords untouched`() {
        val body = "INR 12000.00 debited from your account for NEFT transfer"

        // "account" is a keyword but no digit run of 6+ immediately follows
        // it within the proximity window — nothing to redact here.
        assertEquals(body, SmsProcessingWorker.redactSensitiveDigits(body))
    }
}
