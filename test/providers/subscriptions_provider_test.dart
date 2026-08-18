import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/subscription.dart';
import 'package:ledger/models/transaction.dart' as app_model;
import 'package:ledger/providers/subscriptions_provider.dart';

void main() {
  group('detectSubscriptions', () {
    test('detects a UPI autopay subscription (mandate keyword)', () {
      final now = DateTime(2026, 4, 1);
      final txns = List.generate(
        4,
        (i) => _txn(
          title: 'Spotify',
          amount: 119,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          paymentMethod: app_model.TxnPaymentMethod.upi,
          rawSms: 'Rs 119 debited via UPI autopay mandate for Spotify',
        ),
      );

      final results = detectSubscriptions('user-1', txns);

      expect(results, hasLength(1));
      expect(results.single.kind, SubscriptionKind.subscription);
      expect(results.single.expectedAmount, 119);
      expect(results.single.intervalDays, 30);
    });

    test('detects a UPI subscription via known-merchant allowlist', () {
      final now = DateTime(2026, 1, 5);
      final txns = List.generate(
        3,
        (i) => _txn(
          title: 'NETFLIX.COM',
          amount: 649,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          paymentMethod: app_model.TxnPaymentMethod.upi,
        ),
      );

      final results = detectSubscriptions('user-1', txns);

      expect(results, hasLength(1));
      expect(results.single.kind, SubscriptionKind.subscription);
    });

    test('rent, salary, and electricity are recurring but not subscriptions',
        () {
      final now = DateTime(2026, 1, 1);

      final rent = List.generate(
        4,
        (i) => _txn(
          title: 'Rent - Landlord',
          amount: 25000,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          paymentMethod: app_model.TxnPaymentMethod.bankTransfer,
        ),
      );

      final salary = List.generate(
        4,
        (i) => _txn(
          title: 'Acme Corp Salary',
          amount: 90000,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.income,
        ),
      );

      final electricity = List.generate(
        4,
        (i) => _txn(
          title: 'BESCOM Electricity',
          amount: 1800,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          paymentMethod: app_model.TxnPaymentMethod.upi,
        ),
      );

      final results =
          detectSubscriptions('user-1', [...rent, ...salary, ...electricity]);

      expect(results, hasLength(3));
      final byTitle = {for (final s in results) s.displayName: s.kind};
      expect(byTitle['Rent - Landlord'], SubscriptionKind.recurringBill);
      expect(byTitle['Acme Corp Salary'], SubscriptionKind.recurringIncome);
      // Electricity is paid via UPI but has no mandate keyword and is not on
      // the known-subscription-merchant allowlist, so it stays a bill.
      expect(byTitle['BESCOM Electricity'], SubscriptionKind.recurringBill);
    });

    test('detects a recurring transfer (e.g. a monthly SIP)', () {
      final now = DateTime(2026, 2, 1);
      final txns = List.generate(
        3,
        (i) => _txn(
          title: 'SIP - Mutual Fund',
          amount: 5000,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          txnCategory: app_model.TxnCategory.transfer,
        ),
      );

      final results = detectSubscriptions('user-1', txns);

      expect(results, hasLength(1));
      expect(results.single.kind, SubscriptionKind.recurringTransfer);
    });

    test('requires at least 3 occurrences', () {
      final now = DateTime(2026, 3, 1);
      final txns = List.generate(
        2,
        (i) => _txn(
          title: 'Netflix',
          amount: 649,
          date: now.add(Duration(days: 30 * i)),
          type: app_model.TransactionType.expense,
          paymentMethod: app_model.TxnPaymentMethod.upi,
        ),
      );

      expect(detectSubscriptions('user-1', txns), isEmpty);
    });

    test('rejects an irregular interval', () {
      final now = DateTime(2026, 1, 1);
      final dates = [now, now.add(const Duration(days: 12)), now.add(const Duration(days: 61))];
      final txns = [
        for (final d in dates)
          _txn(
            title: 'Random Merchant',
            amount: 500,
            date: d,
            type: app_model.TransactionType.expense,
          ),
      ];

      expect(detectSubscriptions('user-1', txns), isEmpty);
    });

    test('rejects amounts that vary beyond tolerance', () {
      final now = DateTime(2026, 1, 1);
      final amounts = [100.0, 250.0, 90.0];
      final txns = [
        for (var i = 0; i < amounts.length; i++)
          _txn(
            title: 'Variable Merchant',
            amount: amounts[i],
            date: now.add(Duration(days: 30 * i)),
            type: app_model.TransactionType.expense,
          ),
      ];

      expect(detectSubscriptions('user-1', txns), isEmpty);
    });

    test('excludes rejected transactions and settlement categories', () {
      final now = DateTime(2026, 1, 1);
      final txns = [
        for (var i = 0; i < 4; i++)
          _txn(
            title: 'Card Bill',
            amount: 2000,
            date: now.add(Duration(days: 30 * i)),
            type: app_model.TransactionType.expense,
            txnCategory: app_model.TxnCategory.creditCardPayment,
          ),
        for (var i = 0; i < 4; i++)
          _txn(
            title: 'Rejected Merchant',
            amount: 300,
            date: now.add(Duration(days: 30 * i)),
            type: app_model.TransactionType.expense,
            processingStatus: app_model.TxnProcessingStatus.rejected,
          ),
      ];

      expect(detectSubscriptions('user-1', txns), isEmpty);
    });
  });
}

app_model.Transaction _txn({
  required String title,
  required double amount,
  required DateTime date,
  required app_model.TransactionType type,
  app_model.TxnCategory? txnCategory,
  app_model.TxnPaymentMethod? paymentMethod,
  String? rawSms,
  String? merchantId,
  app_model.TxnProcessingStatus processingStatus =
      app_model.TxnProcessingStatus.confirmed,
}) {
  return app_model.Transaction(
    id: '$title-${date.toIso8601String()}',
    userId: 'user-1',
    title: title,
    amount: amount,
    type: type,
    date: date,
    categoryId: 'general',
    accountId: 'account-1',
    createdAt: date,
    txnCategory: txnCategory,
    paymentMethod: paymentMethod,
    rawSms: rawSms,
    merchantId: merchantId,
    processingStatus: processingStatus,
  );
}
