import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/features/home/widgets/summary_card.dart';
import 'package:ledger/models/account.dart';

void main() {
  group('resolveSummaryBalance', () {
    test('uses the selected account stored balance and title', () {
      final result = resolveSummaryBalance(
        accounts: [
          _account(
            'checking',
            title: 'Checking',
            balance: 2500,
            currency: 'USD',
          ),
          _account(
            'savings',
            title: 'Savings',
            balance: 4000,
            currency: 'USD',
          ),
        ],
        accountId: 'checking',
        currency: 'USD',
      );

      expect(result.amount, 2500);
      expect(result.label, 'Checking');
      expect(result.display, r'$2,500');
    });

    test('sums all account balances when currencies match', () {
      final result = resolveSummaryBalance(
        accounts: [
          _account('checking', balance: 100, currency: 'USD'),
          _account('savings', balance: 250.5, currency: 'USD'),
        ],
        accountId: null,
        currency: 'USD',
      );

      expect(result.amount, 350.5);
      expect(result.label, 'Total Balance');
      expect(result.display, r'$350.5');
    });

    test('suppresses totals when accounts have multiple currencies', () {
      final result = resolveSummaryBalance(
        accounts: [
          _account('checking', balance: 100, currency: 'USD'),
          _account('savings', balance: 250, currency: 'INR'),
        ],
        accountId: null,
        currency: 'USD',
      );

      expect(result.amount, 0);
      expect(result.label, 'Total Balance');
      expect(result.display, 'Multiple Currencies');
    });

    test('falls back to zero when the selected account no longer exists', () {
      final result = resolveSummaryBalance(
        accounts: [
          _account('checking', balance: 100, currency: 'USD'),
        ],
        accountId: 'missing',
        currency: 'USD',
      );

      expect(result.amount, 0);
      expect(result.label, 'Account Balance');
      expect(result.display, r'$0');
    });
  });
}

Account _account(
  String id, {
  String title = 'Account',
  double balance = 0,
  String currency = 'INR',
}) {
  return Account(
    id: id,
    userId: 'user-1',
    title: title,
    bankName: 'Bank',
    lastSixDigits: '123456',
    balance: balance,
    holderName: 'User',
    currency: currency,
    createdAt: DateTime.utc(2026),
  );
}
