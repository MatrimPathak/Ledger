import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/transaction.dart';

void main() {
  group('Transaction.copyWith', () {
    test('preserves the existing id when no replacement is provided', () {
      final original = _transaction();

      final copy = original.copyWith(title: 'Updated merchant');

      expect(copy.id, original.id);
      expect(copy.title, 'Updated merchant');
    });

    test('replaces id while preserving SMS transaction metadata', () {
      final original = _transaction();

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
      expect(copy.source, TransactionSource.sms);
      expect(copy.rawSms, original.rawSms);
      expect(copy.createdAt, original.createdAt);
    });

    test('can clear nullable fields without dropping the id', () {
      final original = _transaction();

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

Transaction _transaction() {
  final now = DateTime.utc(2026, 5, 27, 7);

  return Transaction(
    id: 'local-draft-id',
    userId: 'user-1',
    title: 'Coffee Shop',
    amount: 125.50,
    type: TransactionType.expense,
    date: now,
    categoryId: 'food',
    accountId: 'checking',
    paymentModeId: 'card',
    notes: 'morning coffee',
    source: TransactionSource.sms,
    rawSms: 'Spent INR 125.50 at Coffee Shop',
    createdAt: now,
  );
}
