import 'package:flutter/services.dart';

/// Bridges a value to the Android-Keystore-backed EncryptedSharedPreferences
/// store (SecurePrefsStore.kt) the background SMS worker reads from — used
/// for exactly two values, the Claude API key and the signed-in uid, which
/// previously mirrored into plaintext SharedPreferences so the worker (no
/// Flutter engine, can't reach flutter_secure_storage) could read them.
///
/// Best-effort: failures are swallowed rather than surfaced, since this is
/// a background convenience mirror, not the source of truth (Dart's own
/// reads continue to use flutter_secure_storage/FirebaseAuth directly).
class SecurePrefsBridge {
  static const _channel =
      MethodChannel('com.matrimpathak.ledger/secure_prefs');

  static Future<void> write(String key, String value) async {
    try {
      await _channel.invokeMethod('write', {'key': key, 'value': value});
    } on MissingPluginException {
      // No channel handler on this platform (e.g. iOS, widget tests).
    } on PlatformException {
      // Background auto-detect degrades gracefully if this mirror write
      // fails — the foreground Dart pipeline is unaffected.
    }
  }
}
