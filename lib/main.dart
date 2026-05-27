import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
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

  final prefs = await SharedPreferences.getInstance();

  // Persist uid so the background SMS isolate can use it without relying
  // on FirebaseAuth.instance.currentUser (which is null in a fresh isolate).
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid != null) {
    await prefs.setString(AppConstants.prefKeyUid, uid);
  }

  // Ensure SharedPreferences always has the best available API key so the
  // background SMS isolate (which cannot read FlutterSecureStorage) can use it.
  // Priority: existing SharedPreferences key → secure storage key → .env key.
  final existingKey = prefs.getString(AppConstants.prefKeyClaudeApiKey) ?? '';
  if (existingKey.isEmpty || existingKey == AppConstants.claudeApiKeyPlaceholder) {
    const storage = FlutterSecureStorage();
    final secureKey = await storage.read(key: AppConstants.prefKeyClaudeApiKey);
    final isValidSecureKey = secureKey != null &&
        secureKey.isNotEmpty &&
        secureKey != AppConstants.claudeApiKeyPlaceholder;
    final seedKey = isValidSecureKey
        ? secureKey
        : (dotenv.env['CLAUDE_API_KEY'] ?? AppConstants.claudeApiKeyPlaceholder);
    await prefs.setString(AppConstants.prefKeyClaudeApiKey, seedKey);
  }

  if (prefs.getBool(AppConstants.prefKeyAutoDetect) == true) {
    SmsService().startListening();
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
