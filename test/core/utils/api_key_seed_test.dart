import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/core/utils/api_key_seed.dart';

void main() {
  group('resolveSharedApiKeySeed', () {
    test('preserves an existing SharedPreferences API key', () {
      final seed = resolveSharedApiKeySeed(
        sharedPreferencesKey: 'shared-key',
        secureStorageKey: 'secure-key',
        environmentKey: 'env-key',
      );

      expect(seed, isNull);
    });

    test('uses secure storage when the shared key is missing', () {
      final seed = resolveSharedApiKeySeed(
        sharedPreferencesKey: '',
        secureStorageKey: 'secure-key',
        environmentKey: 'env-key',
      );

      expect(seed, 'secure-key');
    });

    test('falls back to the environment key for placeholder shared keys', () {
      final seed = resolveSharedApiKeySeed(
        sharedPreferencesKey: AppConstants.claudeApiKeyPlaceholder,
        secureStorageKey: AppConstants.claudeApiKeyPlaceholder,
        environmentKey: 'env-key',
      );

      expect(seed, 'env-key');
    });

    test('uses the placeholder when no usable key exists', () {
      final seed = resolveSharedApiKeySeed(
        sharedPreferencesKey: null,
        secureStorageKey: null,
        environmentKey: null,
      );

      expect(seed, AppConstants.claudeApiKeyPlaceholder);
    });
  });
}
