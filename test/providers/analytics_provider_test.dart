import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/transaction.dart' as app_model;
import 'package:ledger/providers/analytics_provider.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
  group('analyticsInsightsProvider', () {
    test('is kept alive so navigation does not discard cached insights', () {
      expect(
        analyticsInsightsProvider,
        isA<FutureProvider<List<AnalyticsInsight>>>(),
      );
      expect(
        analyticsInsightsProvider,
        isNot(isA<AutoDisposeFutureProvider<List<AnalyticsInsight>>>()),
      );
    });
  });

  group('buildAnalyticsSummary', () {
    test('aggregates income, expenses, categories, and merchants', () {
      final now = DateTime(2026, 5, 1);
      final transactions = [
        _transaction(
          title: 'Coffee Shop',
          amount: 250,
          type: app_model.TransactionType.expense,
          categoryId: 'food',
          date: now,
        ),
        _transaction(
          title: 'Coffee Shop',
          amount: 100,
          type: app_model.TransactionType.expense,
          categoryId: 'food',
          date: now,
        ),
        _transaction(
          title: 'Salary',
          amount: 1000,
          type: app_model.TransactionType.income,
          categoryId: 'salary',
          date: now,
        ),
        _transaction(
          title: 'Cab',
          amount: 125,
          type: app_model.TransactionType.expense,
          categoryId: 'transport',
          date: now,
        ),
      ];

      final summary = buildAnalyticsSummary(transactions);

      expect(summary, hasLength(1));
      final row = summary.single;
      expect(row['period'], 'last_90_days');
      expect(row['totalExpense'], 475);
      expect(row['totalIncome'], 1000);
      expect(row['netSavings'], 525);
      expect(row['savingsRate'], 0.525);
      expect(row['transactionCount'], transactions.length);
      expect(
        row['categoryBreakdown'],
        unorderedEquals([
          {'categoryId': 'food', 'total': 350.0},
          {'categoryId': 'transport', 'total': 125.0},
        ]),
      );
      expect(
        row['topMerchants'],
        containsAll([
          {'name': 'Coffee Shop', 'count': 2},
          {'name': 'Salary', 'count': 1},
          {'name': 'Cab', 'count': 1},
        ]),
      );
    });

    test('keeps savings rate at zero when there is no income', () {
      final now = DateTime(2026, 5, 1);

      final summary = buildAnalyticsSummary([
        _transaction(
          title: 'Groceries',
          amount: 400,
          type: app_model.TransactionType.expense,
          categoryId: 'groceries',
          date: now,
        ),
      ]);

      final row = summary.single;
      expect(row['totalExpense'], 400);
      expect(row['totalIncome'], 0);
      expect(row['netSavings'], -400);
      expect(row['savingsRate'], 0);
      expect(row['categoryBreakdown'], [
        {'categoryId': 'groceries', 'total': 400.0},
      ]);
    });

    test('limits top merchants to the five most frequent entries', () {
      final now = DateTime(2026, 5, 1);
      final transactions = <app_model.Transaction>[
        for (var index = 0; index < 6; index++)
          for (var count = 0; count <= index; count++)
            _transaction(
              title: 'Merchant $index',
              amount: 10,
              type: app_model.TransactionType.expense,
              categoryId: 'shopping',
              date: now,
            ),
      ];

      final topMerchants =
          buildAnalyticsSummary(transactions).single['topMerchants'] as List;

      expect(topMerchants, hasLength(5));
      expect(topMerchants.first, {'name': 'Merchant 5', 'count': 6});
      expect(topMerchants, isNot(contains({'name': 'Merchant 0', 'count': 1})));
    });

    test('excludes transfers, credit-card payments, and adjustments from every aggregate',
        () {
      final now = DateTime(2026, 5, 1);
      final transactions = [
        _transaction(
          title: 'Coffee Shop',
          amount: 250,
          type: app_model.TransactionType.expense,
          categoryId: 'food',
          date: now,
        ),
        _transaction(
          title: 'Card Bill Payment',
          amount: 10000,
          type: app_model.TransactionType.expense,
          categoryId: 'bills',
          date: now,
          txnCategory: app_model.TxnCategory.creditCardPayment,
        ),
        _transaction(
          title: 'Savings Transfer',
          amount: 5000,
          type: app_model.TransactionType.expense,
          categoryId: 'transfer',
          date: now,
          txnCategory: app_model.TxnCategory.transfer,
        ),
        _transaction(
          title: 'Balance Correction',
          amount: 1,
          type: app_model.TransactionType.income,
          categoryId: 'other',
          date: now,
          txnCategory: app_model.TxnCategory.adjustment,
        ),
      ];

      final row = buildAnalyticsSummary(transactions).single;

      expect(row['totalExpense'], 250);
      expect(row['totalIncome'], 0);
      expect(row['transactionCount'], 1);
      expect(row['categoryBreakdown'], [
        {'categoryId': 'food', 'total': 250.0},
      ]);
      expect(
        row['topMerchants'],
        [
          {'name': 'Coffee Shop', 'count': 1}
        ],
      );
    });

    test('still counts a credit-card purchase as ordinary spend', () {
      final now = DateTime(2026, 5, 1);
      final transactions = [
        _transaction(
          title: 'Amazon',
          amount: 1500,
          type: app_model.TransactionType.expense,
          categoryId: 'shopping',
          date: now,
          txnCategory: app_model.TxnCategory.creditCardPurchase,
        ),
      ];

      final row = buildAnalyticsSummary(transactions).single;

      expect(row['totalExpense'], 1500);
      expect(row['transactionCount'], 1);
    });
  });
}

app_model.Transaction _transaction({
  required String title,
  required double amount,
  required app_model.TransactionType type,
  required String categoryId,
  required DateTime date,
  app_model.TxnCategory? txnCategory,
}) {
  return app_model.Transaction(
    id: '$title-$amount-${date.toIso8601String()}',
    userId: 'user-1',
    title: title,
    amount: amount,
    type: type,
    date: date,
    categoryId: categoryId,
    accountId: 'account-1',
    createdAt: date,
    txnCategory: txnCategory,
  );
}
