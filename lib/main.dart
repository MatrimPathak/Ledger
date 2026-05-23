import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/constants/app_constants.dart';
import 'firebase_options.dart';
import 'services/notification/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await NotificationService.initialize();

  // Forward API key to SharedPreferences so the background SMS isolate can read it
  final prefs = await SharedPreferences.getInstance();
  final apiKey = dotenv.env['CLAUDE_API_KEY'] ?? AppConstants.claudeApiKeyPlaceholder;
  await prefs.setString(AppConstants.prefKeyClaudeApiKey, apiKey);

  runApp(
    const ProviderScope(
      child: LedgerApp(),
    ),
  );
}
