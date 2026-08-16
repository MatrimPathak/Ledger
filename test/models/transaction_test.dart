import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/transaction.dart' as app_model;

void main() {
  group('Transaction', () {
    test('copyWith can clear nullable payment mode and notes', () {
      final createdAt = DateTime(2024, 1, 1, 10);
      final original = app_model.Transaction(
        id: 'tx-1',
        userId: 'user-1',
        title: 'Coffee',
        amount: 250,
        type: app_model.TransactionType.expense,
        date: DateTime(2024, 1, 2),
        categoryId: 'food',
        accountId: 'account-1',
        paymentModeId: 'upi-1',
        notes: 'morning coffee',
        source: app_model.TransactionSource.sms,
        rawSms: 'debited INR 250',
        createdAt: createdAt,
      );

      final updated = original.copyWith(
        title: 'Cafe',
        amount: 300,
        clearPaymentModeId: true,
        clearNotes: true,
      );

      expect(updated.id, original.id);
      expect(updated.userId, original.userId);
      expect(updated.title, 'Cafe');
      expect(updated.amount, 300);
      expect(updated.paymentModeId, isNull);
      expect(updated.notes, isNull);
      expect(updated.source, app_model.TransactionSource.sms);
      expect(updated.rawSms, 'debited INR 250');
      expect(updated.createdAt, createdAt);
    });

    test('toFirestore serializes enums and dates for persistence', () {
      final transaction = app_model.Transaction(
        id: 'tx-1',
        userId: 'user-1',
        title: 'Salary',
        amount: 100000,
        type: app_model.TransactionType.income,
        date: DateTime(2024, 3, 31, 9, 30),
        categoryId: 'salary',
        accountId: 'account-1',
        paymentModeId: null,
        notes: null,
        source: app_model.TransactionSource.manual,
        rawSms: null,
        createdAt: DateTime(2024, 3, 31, 9),
      );

      final data = transaction.toFirestore();

      expect(data['userId'], 'user-1');
      expect(data['type'], 'income');
      expect(data['source'], 'manual');
      expect(data['amount'], 100000);
      expect((data['date'] as Timestamp).toDate(), DateTime(2024, 3, 31, 9, 30));
      expect((data['createdAt'] as Timestamp).toDate(), DateTime(2024, 3, 31, 9));
    });

    test('preserves the existing id when no replacement is provided', () {
      final original = _smsTransaction();

      final copy = original.copyWith(title: 'Updated merchant');

      expect(copy.id, original.id);
      expect(copy.title, 'Updated merchant');
    });

    test('replaces id while preserving SMS transaction metadata', () {
      final original = _smsTransaction();

      final copy = original.copyWith(id: 'firestore-doc-id');

      expect(copy.id, 'firestore-doc-id');
      expect(copy.userId, original.userId);
      expect(copy.title, original.title);
      expect(copy.amount, original.amount);
      expect(copy.type, original.type);
      expect(copy.date, original.date);
      expect(copy.categoryId, original.categoryId);
      expect(copy.accountId, original.accountId);
      expect(copy.paymentModeId, original.paymentModeId);
      expect(copy.notes, original.notes);
      expect(copy.source, app_model.TransactionSource.sms);
      expect(copy.rawSms, original.rawSms);
      expect(copy.createdAt, original.createdAt);
    });

    test('can clear nullable fields without dropping the id', () {
      final original = _smsTransaction();

      final copy = original.copyWith(
        clearPaymentModeId: true,
        clearNotes: true,
      );

      expect(copy.id, original.id);
      expect(copy.paymentModeId, isNull);
      expect(copy.notes, isNull);
    });
  });
}

app_model.Transaction _smsTransaction() {
  final now = DateTime.utc(2026, 5, 27, 7);

  return app_model.Transaction(
    id: 'local-draft-id',
    userId: 'user-1',
    title: 'Coffee Shop',
    amount: 125.50,
    type: app_model.TransactionType.expense,
    date: now,
    categoryId: 'food',
    accountId: 'checking',
    paymentModeId: 'card',
    notes: 'morning coffee',
    source: app_model.TransactionSource.sms,
    rawSms: 'Spent INR 125.50 at Coffee Shop',
    createdAt: now,
  );
}
