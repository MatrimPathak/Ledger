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
import 'services/sms/sms_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  // Ensure SharedPreferences always has the best available API key so the
  // background SMS isolate (which cannot read FlutterSecureStorage) can use it.
  // Priority: existing SharedPreferences key → secure storage key → .env key.
  final prefs = await SharedPreferences.getInstance();
  final existingSharedKey = prefs.getString(AppConstants.prefKeyClaudeApiKey);
  String? secureStorageKey;
  if (existingSharedKey == null ||
      existingSharedKey.isEmpty ||
      existingSharedKey == AppConstants.claudeApiKeyPlaceholder) {
    const storage = FlutterSecureStorage();
    secureStorageKey = await storage.read(key: AppConstants.prefKeyClaudeApiKey);
  }
  final seedKey = resolveSharedApiKeySeed(
    sharedPreferencesKey: existingSharedKey,
    secureStorageKey: secureStorageKey,
    environmentKey: dotenv.env['CLAUDE_API_KEY'],
  );
  if (seedKey != null) {
    await prefs.setString(AppConstants.prefKeyClaudeApiKey, seedKey);
  }

  if (prefs.getBool(AppConstants.prefKeyAutoDetect) == true) {
    SmsService().startListening();
  }

  runApp(
    const ProviderScope(
      child: LedgerApp(),
    ),
  );
}
