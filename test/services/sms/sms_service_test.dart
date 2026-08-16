import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/services/sms/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveBackgroundSmsUid', () {
    test('prefers the current Firebase Auth uid when it is available',
        () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: 'stored-uid',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: 'auth-uid',
          prefs: prefs,
        ),
        'auth-uid',
      );
    });

    test('falls back to the stored uid for background isolates', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: 'stored-uid',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: null,
          prefs: prefs,
        ),
        'stored-uid',
      );
    });

    test('returns null when neither uid source is usable', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: '',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: '',
          prefs: prefs,
        ),
        isNull,
      );
    });
  });
}
