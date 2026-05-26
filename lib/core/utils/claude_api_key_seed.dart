import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_constants.dart';

Future<void> seedClaudeApiKeyIfNeeded({
  required SharedPreferences prefs,
  required String? envKey,
}) async {
  final existingKey = prefs.getString(AppConstants.prefKeyClaudeApiKey) ?? '';
  if (existingKey.isEmpty ||
      existingKey == AppConstants.claudeApiKeyPlaceholder) {
    await prefs.setString(
      AppConstants.prefKeyClaudeApiKey,
      envKey ?? AppConstants.claudeApiKeyPlaceholder,
    );
  }
}
