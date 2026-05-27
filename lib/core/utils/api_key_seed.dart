import '../constants/app_constants.dart';

String? resolveSharedApiKeySeed({
  required String? sharedPreferencesKey,
  required String? secureStorageKey,
  required String? environmentKey,
}) {
  final existingKey = sharedPreferencesKey ?? '';
  if (existingKey.isNotEmpty &&
      existingKey != AppConstants.claudeApiKeyPlaceholder) {
    return null;
  }

  final isValidSecureKey = secureStorageKey != null &&
      secureStorageKey.isNotEmpty &&
      secureStorageKey != AppConstants.claudeApiKeyPlaceholder;
  if (isValidSecureKey) return secureStorageKey;

  return environmentKey ?? AppConstants.claudeApiKeyPlaceholder;
}
