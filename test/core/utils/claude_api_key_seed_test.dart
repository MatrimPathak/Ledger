import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/core/utils/claude_api_key_seed.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('seedClaudeApiKeyIfNeeded', () {
    test('preserves an existing user-saved API key', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyClaudeApiKey: 'user-key',
      });
      final prefs = await SharedPreferences.getInstance();

      await seedClaudeApiKeyIfNeeded(
        prefs: prefs,
        envKey: 'env-key',
      );

      expect(
        prefs.getString(AppConstants.prefKeyClaudeApiKey),
        'user-key',
      );
    });

    test('seeds the env key when no key has been saved', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await seedClaudeApiKeyIfNeeded(
        prefs: prefs,
        envKey: 'env-key',
      );

      expect(
        prefs.getString(AppConstants.prefKeyClaudeApiKey),
        'env-key',
      );
    });

    test('replaces the placeholder key with the env key', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyClaudeApiKey: AppConstants.claudeApiKeyPlaceholder,
      });
      final prefs = await SharedPreferences.getInstance();

      await seedClaudeApiKeyIfNeeded(
        prefs: prefs,
        envKey: 'env-key',
      );

      expect(
        prefs.getString(AppConstants.prefKeyClaudeApiKey),
        'env-key',
      );
    });
  });
}
