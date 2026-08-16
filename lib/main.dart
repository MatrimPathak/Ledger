import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/utils/api_key_seed.dart';
import 'firebase_options.dart';
import 'services/notification/notification_service.dart';
import 'services/secure/secure_prefs_bridge.dart';
import 'services/sms/sms_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  final prefs = await SharedPreferences.getInstance();

  // Mirror uid into the Keystore-backed native store (not plaintext
  // SharedPreferences) so the background SMS worker — no Flutter engine,
  // can't call FirebaseAuth.instance.currentUser — can use it without ever
  // touching an unencrypted copy on disk.
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    await SecurePrefsBridge.write(AppConstants.prefKeyUid, uid);
  }

  // Resolve the best available API key (secure storage → .env) and mirror
  // it the same way. flutter_secure_storage stays the source of truth for
  // the foreground app; this write only feeds the background worker's
  // otherwise-inaccessible read path. Passing the placeholder as the
  // "existing shared key" always resolves fresh from secure storage/env,
  // since there is no plaintext tier to short-circuit on anymore.
  const storage = FlutterSecureStorage();
  final secureKey = await storage.read(key: AppConstants.prefKeyClaudeApiKey);
  final resolvedKey = resolveSharedApiKeySeed(
        sharedPreferencesKey: AppConstants.claudeApiKeyPlaceholder,
        secureStorageKey: secureKey,
        environmentKey: dotenv.env['CLAUDE_API_KEY'],
      ) ??
      AppConstants.claudeApiKeyPlaceholder;
  final isValidSecureKey = secureKey != null &&
      secureKey.isNotEmpty &&
      secureKey != AppConstants.claudeApiKeyPlaceholder;
  if (resolvedKey != AppConstants.claudeApiKeyPlaceholder) {
    if (!isValidSecureKey) {
      // Seed secure storage from .env on first run so future launches read
      // a stable value straight from it.
      await storage.write(
          key: AppConstants.prefKeyClaudeApiKey, value: resolvedKey);
    }
    await SecurePrefsBridge.write(AppConstants.prefKeyClaudeApiKey, resolvedKey);
  }

  if (prefs.getBool(AppConstants.prefKeyAutoDetect) == true) {
    final smsService = SmsService();
    smsService.startListening();
  }

  runApp(
    const ProviderScope(
      child: LedgerApp(),
    ),
  );
}
