import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/utils/payment_mode_filters.dart';
import 'package:ledger/models/payment_mode.dart';

void main() {
  group('paymentModesForTransaction', () {
    test('shows account modes, cash, and global ATM for a selected account', () {
      final modes = [
        _mode('upi-a', PaymentModeType.upi, accountId: 'account-a'),
        _mode('upi-b', PaymentModeType.upi, accountId: 'account-b'),
        _mode('cash', PaymentModeType.cash),
        _mode('atm-global', PaymentModeType.atm),
        _mode('atm-a', PaymentModeType.atm, accountId: 'account-a'),
        _mode('atm-b', PaymentModeType.atm, accountId: 'account-b'),
      ];

      final result = paymentModesForTransaction(
        modes,
        accountId: 'account-a',
      );

      expect(result.map((mode) => mode.id), [
        'upi-a',
        'cash',
        'atm-global',
        'atm-a',
      ]);
    });

    test('shows all modes when no account is selected', () {
      final modes = [
        _mode('upi-a', PaymentModeType.upi, accountId: 'account-a'),
        _mode('cash', PaymentModeType.cash),
      ];

      final result = paymentModesForTransaction(modes, accountId: null);

      expect(result.map((mode) => mode.id), ['upi-a', 'cash']);
    });
  });

  group('paymentModesForAccountPage', () {
    test('shows account modes and cash, but not global ATM', () {
      final modes = [
        _mode('upi-a', PaymentModeType.upi, accountId: 'account-a'),
        _mode('upi-b', PaymentModeType.upi, accountId: 'account-b'),
        _mode('cash', PaymentModeType.cash),
        _mode('atm-global', PaymentModeType.atm),
        _mode('atm-a', PaymentModeType.atm, accountId: 'account-a'),
      ];

      final result = paymentModesForAccountPage(
        modes,
        accountId: 'account-a',
      );

      expect(result.map((mode) => mode.id), ['upi-a', 'cash', 'atm-a']);
    });

    test('shows all modes when no account page is active', () {
      final modes = [
        _mode('upi-a', PaymentModeType.upi, accountId: 'account-a'),
        _mode('atm-global', PaymentModeType.atm),
      ];

      final result = paymentModesForAccountPage(modes, accountId: null);

      expect(result.map((mode) => mode.id), ['upi-a', 'atm-global']);
    });
  });
}

PaymentMode _mode(
  String id,
  PaymentModeType type, {
  String? accountId,
}) {
  return PaymentMode(
    id: id,
    userId: 'user-1',
    type: type,
    accountId: accountId,
    title: id,
    createdAt: DateTime.utc(2026),
  );
}
