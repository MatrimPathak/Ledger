import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/features/home/screens/home_screen.dart';
import 'package:ledger/models/account.dart';

void main() {
  group('resolveHomeCurrency', () {
    test('defaults to INR when there are no accounts', () {
      expect(resolveHomeCurrency([], null), 'INR');
    });

    test('uses the selected account currency', () {
      final accounts = [
        _account('checking', currency: 'INR'),
        _account('travel', currency: 'USD'),
      ];

      expect(resolveHomeCurrency(accounts, 'travel'), 'USD');
    });

    test('falls back to the first account currency for a missing account', () {
      final accounts = [
        _account('checking', currency: 'GBP'),
        _account('travel', currency: 'USD'),
      ];

      expect(resolveHomeCurrency(accounts, 'missing'), 'GBP');
    });
  });
}

Account _account(String id, {required String currency}) {
  return Account(
    id: id,
    userId: 'user-1',
    title: id,
    bankName: 'Bank',
    lastSixDigits: '123456',
    balance: 0,
    holderName: 'User',
    currency: currency,
    createdAt: DateTime.utc(2026),
  );
}
