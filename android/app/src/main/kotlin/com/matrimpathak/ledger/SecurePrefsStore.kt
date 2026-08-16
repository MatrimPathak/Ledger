package com.matrimpathak.ledger

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Android-Keystore-backed replacement for the plaintext SharedPreferences
 * mirror the background SMS pipeline previously read the Claude API key
 * and uid from (FlutterSharedPreferences — unencrypted XML on disk). The
 * Dart side writes here via MainActivity's "secure_prefs" MethodChannel
 * whenever the resolved key/uid changes; SmsProcessingWorker (no Flutter
 * engine, can't reach flutter_secure_storage) reads from here instead of
 * plaintext SharedPreferences. Every other auto-detect preference
 * (enabled flag, notification setting, dedup fingerprints) is not
 * sensitive and stays in plain SharedPreferences unchanged.
 *
 * Uses androidx.security:security-crypto 1.1.0. Its APIs (MasterKey,
 * EncryptedSharedPreferences) were deprecated in that same release in
 * favor of hand-rolled Android Keystore + Cipher usage, but remain fully
 * functional — still the pragmatic choice here over reimplementing
 * Keystore key management by hand. Worth revisiting if AndroidX removes
 * these APIs in a future major version.
 */
object SecurePrefsStore {
    private const val FILE_NAME = "ledger_secure_prefs"

    @Volatile
    private var cached: SharedPreferences? = null

    private fun prefs(context: Context): SharedPreferences {
        cached?.let { return it }
        synchronized(this) {
            cached?.let { return it }
            val masterKey = MasterKey.Builder(context.applicationContext)
                .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                .build()
            val prefs = EncryptedSharedPreferences.create(
                context.applicationContext,
                FILE_NAME,
                masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
            cached = prefs
            return prefs
        }
    }

    fun write(context: Context, key: String, value: String) {
        prefs(context).edit().putString(key, value).apply()
    }

    fun read(context: Context, key: String): String? = prefs(context).getString(key, null)

    fun remove(context: Context, key: String) {
        prefs(context).edit().remove(key).apply()
    }
}
