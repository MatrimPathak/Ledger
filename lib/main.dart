import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/utils/claude_api_key_seed.dart';
import 'firebase_options.dart';
import 'services/notification/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  // Seed SharedPreferences with the .env key only if the user hasn't saved
  // their own key yet — this preserves the user-set key across restarts.
  // SharedPreferences is also read by the background SMS isolate.
  final prefs = await SharedPreferences.getInstance();
  await seedClaudeApiKeyIfNeeded(
    prefs: prefs,
    envKey: dotenv.env['CLAUDE_API_KEY'],
  );

  runApp(
    const ProviderScope(
      child: LedgerApp(),
    ),
  );
}
