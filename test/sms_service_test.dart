import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/services/sms/sms_service.dart';

void main() {
  group('BankSmsFilter', () {
    test('accepts common Indian bank transaction messages', () {
      expect(
        BankSmsFilter.looksLikeBankSms(
          'INR 550.00 debited from A/C XX1234 via UPI Ref 987654.',
        ),
        isTrue,
      );
      expect(
        BankSmsFilter.looksLikeBankSms(
          'Your account is credited by NEFT transfer of Rs. 15000.',
        ),
        isTrue,
      );
    });

    test('rejects non-bank messages before background processing starts', () {
      expect(
        BankSmsFilter.looksLikeBankSms(
          'Your OTP is 123456. Do not share it with anyone.',
        ),
        isFalse,
      );
      expect(
        BankSmsFilter.looksLikeBankSms(
          'Flash sale starts now. Use code SAVE20 at checkout.',
        ),
        isFalse,
      );
    });
  });

  group('resolveBackgroundSmsUid', () {
    test('prefers the foreground Firebase user when available', () {
      final uid = resolveBackgroundSmsUid(
        currentUserUid: 'firebase-user',
        persistedUid: 'persisted-user',
      );

      expect(uid, 'firebase-user');
    });

    test('falls back to the persisted uid in background isolates', () {
      final uid = resolveBackgroundSmsUid(
        currentUserUid: null,
        persistedUid: 'persisted-user',
      );

      expect(uid, 'persisted-user');
    });

    test('treats empty uid values as signed out', () {
      final uid = resolveBackgroundSmsUid(
        currentUserUid: '',
        persistedUid: '',
      );

      expect(uid, isNull);
    });
  });
}
