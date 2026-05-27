import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static const String appName = 'Ledger';
  static const String defaultCurrency = 'INR';
  static const String currencySymbol = '₹';

  static const String claudeApiKeyPlaceholder = 'YOUR_CLAUDE_API_KEY';
  static String get claudeApiKey =>
      dotenv.env['CLAUDE_API_KEY'] ?? claudeApiKeyPlaceholder;
  static const String claudeApiUrl =
      'https://api.anthropic.com/v1/messages';
  static const String claudeApiVersion = '2023-06-01';
  static const String claudeSmsFastModel = 'claude-haiku-4-5-20251001';
  static const String claudeAnalyticsModel = 'claude-haiku-4-5-20251001';

  static const String prefKeyThemeMode = 'theme_mode';
  static const String prefKeyNotifications = 'notifications_enabled';
  static const String prefKeyAutoDetect = 'auto_detect_enabled';
  static const String prefKeyClaudeApiKey = 'claude_api_key';
  static const String prefKeyOnboardingDone = 'onboarding_done';

  static const int smsConfidenceThreshold = 70; // 0-100

  static const List<String> supportedCurrencies = [
    'INR',
    'USD',
    'EUR',
    'GBP',
    'AED',
    'SGD',
  ];

  static const Map<String, String> currencySymbols = {
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'AED': 'د.إ',
    'SGD': 'S\$',
  };
}
