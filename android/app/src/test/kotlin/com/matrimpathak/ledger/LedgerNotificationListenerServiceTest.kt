package com.matrimpathak.ledger

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * JVM unit test (no Android framework dependency) for the pure
 * amount/direction extraction used by LedgerNotificationListenerService.
 * onNotificationPosted itself needs a StatusBarNotification/live service
 * context and isn't unit-testable here — this exercises exactly the two
 * functions that decide what crosses the bridge to Dart.
 */
class LedgerNotificationListenerServiceTest {

    @Test
    fun `extracts amount from common UPI notification phrasings`() {
        assertEquals(250.0, LedgerNotificationListenerService.extractAmount("Paid Rs.250 to Rajesh Kumar"))
        assertEquals(1499.50, LedgerNotificationListenerService.extractAmount("You sent INR 1,499.50 via PhonePe"))
        assertEquals(99.0, LedgerNotificationListenerService.extractAmount("₹99 paid successfully"))
        assertEquals(75.0, LedgerNotificationListenerService.extractAmount("rs 75 debited"))
    }

    @Test
    fun `returns null when no amount is present`() {
        assertNull(LedgerNotificationListenerService.extractAmount("You have a new message"))
        assertNull(LedgerNotificationListenerService.extractAmount(""))
        assertNull(LedgerNotificationListenerService.extractAmount("Hours 250 logged this week"))
    }

    @Test
    fun `does not classify substring keyword matches as a direction`() {
        assertEquals("unknown", LedgerNotificationListenerService.guessEventType("Your talk was presented"))
    }

    @Test
    fun `guesses debit and credit direction from keywords`() {
        assertEquals("debit", LedgerNotificationListenerService.guessEventType("Paid Rs.250 to Rajesh Kumar"))
        assertEquals("debit", LedgerNotificationListenerService.guessEventType("Rs 100 debited from your account"))
        assertEquals("credit", LedgerNotificationListenerService.guessEventType("Rs 500 received from Priya"))
        assertEquals("credit", LedgerNotificationListenerService.guessEventType("Refund of Rs 200 credited"))
        assertEquals("unknown", LedgerNotificationListenerService.guessEventType("Rs 40 - Recharge successful"))
    }
}
