import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/payment_mode.dart';

void main() {
  group('PaymentMode.copyWith', () {
    test('clears nullable edit fields when callbacks return null', () {
      final mode = _mode(
        type: PaymentModeType.upi,
        accountId: 'account-a',
        lastFourDigits: '1234',
        upiId: 'user',
        bankHandle: 'oksbi',
      );

      final updated = mode.copyWith(
        type: PaymentModeType.atm,
        accountId: () => null,
        lastFourDigits: () => null,
        upiId: () => null,
        bankHandle: () => null,
      );

      expect(updated.type, PaymentModeType.atm);
      expect(updated.accountId, isNull);
      expect(updated.lastFourDigits, isNull);
      expect(updated.upiId, isNull);
      expect(updated.bankHandle, isNull);
    });

    test('preserves nullable fields when callbacks are omitted', () {
      final mode = _mode(
        accountId: 'account-a',
        lastFourDigits: '1234',
        upiId: 'user',
        bankHandle: 'oksbi',
      );

      final updated = mode.copyWith(title: 'Renamed');

      expect(updated.title, 'Renamed');
      expect(updated.accountId, 'account-a');
      expect(updated.lastFourDigits, '1234');
      expect(updated.upiId, 'user');
      expect(updated.bankHandle, 'oksbi');
    });

    test('updates nullable fields when callbacks return values', () {
      final mode = _mode();

      final updated = mode.copyWith(
        accountId: () => 'account-b',
        lastFourDigits: () => '9876',
        upiId: () => 'newuser',
        bankHandle: () => 'okhdfc',
      );

      expect(updated.accountId, 'account-b');
      expect(updated.lastFourDigits, '9876');
      expect(updated.upiId, 'newuser');
      expect(updated.bankHandle, 'okhdfc');
    });
  });

  test('toFirestore includes bank handle for UPI payment modes', () {
    final mode = _mode(
      type: PaymentModeType.upi,
      title: 'UPI user@oksbi',
      upiId: 'user',
      bankHandle: 'oksbi',
    );

    final data = mode.toFirestore();

    expect(data['type'], 'upi');
    expect(data['title'], 'UPI user@oksbi');
    expect(data['upiId'], 'user');
    expect(data['bankHandle'], 'oksbi');
  });
}

PaymentMode _mode({
  PaymentModeType type = PaymentModeType.cash,
  String? accountId,
  String title = 'Cash',
  String? lastFourDigits,
  String? upiId,
  String? bankHandle,
}) {
  return PaymentMode(
    id: 'mode-1',
    userId: 'user-1',
    type: type,
    accountId: accountId,
    title: title,
    lastFourDigits: lastFourDigits,
    upiId: upiId,
    bankHandle: bankHandle,
    createdAt: DateTime.utc(2026),
  );
}
