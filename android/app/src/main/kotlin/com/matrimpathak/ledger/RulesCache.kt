package com.matrimpathak.ledger

import android.content.Context
import org.json.JSONObject

/**
 * Process-wide cache for the shared SMS pattern rule set
 * (assets/sms_patterns/bank_patterns.json, bundled into flutter_assets/ by
 * the Flutter build), so SmsReceiver's coarse Layer-1 prefilter and
 * LocalSmsParser's full field extraction both read/parse the file at most
 * once per process rather than on every SMS.
 */
object RulesCache {
    private const val ASSET_PATH = "flutter_assets/assets/sms_patterns/bank_patterns.json"

    @Volatile
    private var cached: JSONObject? = null

    fun get(context: Context): JSONObject {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val json = context.applicationContext.assets.open(ASSET_PATH)
                .bufferedReader(Charsets.UTF_8).use { it.readText() }
            val parsed = JSONObject(json)
            cached = parsed
            return parsed
        }
    }
}
