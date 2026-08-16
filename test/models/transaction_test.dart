import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/payment_mode.dart';
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

  group('Transaction backward compatibility', () {
    test('defaults new fields from a legacy Firestore document', () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .doc('legacy-tx');

      // Simulates a document written before payee/merchant/taxonomy fields
      // existed — none of the new fields are present.
      await docRef.set({
        'userId': 'user-1',
        'title': 'Salary',
        'amount': 50000,
        'type': 'income',
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'categoryId': 'salary',
        'accountId': 'account-1',
        'source': 'manual',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'affectsBalance': true,
      });

      final doc = await docRef.get();
      final transaction = app_model.Transaction.fromFirestore(doc);

      expect(transaction.txnCategory, app_model.TxnCategory.income);
      expect(transaction.paymentMethod, isNull);
      expect(transaction.processingStatus, app_model.TxnProcessingStatus.confirmed);
      expect(transaction.payeeRaw, isNull);
      expect(transaction.merchantId, isNull);
      expect(transaction.aiConfidence, isNull);
      expect(transaction.sourceMessageHash, isNull);
      expect(transaction.linkedTransferTransactionId, isNull);
    });

    test('defaults an expense-type legacy document to TxnCategory.expense',
        () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .doc('legacy-expense');

      await docRef.set({
        'userId': 'user-1',
        'title': 'Groceries',
        'amount': 400,
        'type': 'expense',
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'categoryId': 'groceries',
        'accountId': 'account-1',
        'source': 'manual',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final doc = await docRef.get();
      final transaction = app_model.Transaction.fromFirestore(doc);

      expect(transaction.txnCategory, app_model.TxnCategory.expense);
    });

    test('round-trips every new field through toFirestore/fromFirestore',
        () async {
      final firestore = FakeFirebaseFirestore();
      final now = DateTime.utc(2026, 5, 1, 10);
      final transaction = app_model.Transaction(
        id: '',
        userId: 'user-1',
        title: 'Uber',
        amount: 286,
        type: app_model.TransactionType.expense,
        date: now,
        categoryId: 'transport',
        accountId: 'account-1',
        paymentModeId: 'upi-1',
        createdAt: now,
        payeeRaw: 'Rajesh Kumar',
        merchantId: 'merchant-uber',
        merchantConfidence: 0.94,
        txnCategory: app_model.TxnCategory.expense,
        paymentMethod: app_model.TxnPaymentMethod.upi,
        sourceMessageId: 'sms-123',
        sourceMessageHash: 'hash-abc',
        externalTransactionId: 'UTR123456',
        transactionAt: now,
        processingStatus: app_model.TxnProcessingStatus.aiProcessed,
        aiConfidence: 0.82,
        aiModel: 'claude-haiku-4-5-20251001',
        creditCardAccountId: 'card-1',
        linkedTransferTransactionId: 'tx-linked-1',
      );

      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .doc('tx-full');
      await docRef.set(transaction.toFirestore());
      final roundTripped =
          app_model.Transaction.fromFirestore(await docRef.get());

      expect(roundTripped.payeeRaw, 'Rajesh Kumar');
      expect(roundTripped.merchantId, 'merchant-uber');
      expect(roundTripped.merchantConfidence, 0.94);
      expect(roundTripped.txnCategory, app_model.TxnCategory.expense);
      expect(roundTripped.paymentMethod, app_model.TxnPaymentMethod.upi);
      expect(roundTripped.sourceMessageId, 'sms-123');
      expect(roundTripped.sourceMessageHash, 'hash-abc');
      expect(roundTripped.externalTransactionId, 'UTR123456');
      expect(roundTripped.transactionAt, now);
      expect(roundTripped.processingStatus, app_model.TxnProcessingStatus.aiProcessed);
      expect(roundTripped.aiConfidence, 0.82);
      expect(roundTripped.aiModel, 'claude-haiku-4-5-20251001');
      expect(roundTripped.creditCardAccountId, 'card-1');
      expect(roundTripped.linkedTransferTransactionId, 'tx-linked-1');
    });

    test('rejects an unknown persisted txnCategory by falling back to the legacy type',
        () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .doc('tx-corrupt');

      await docRef.set({
        'userId': 'user-1',
        'title': 'Weird',
        'amount': 10,
        'type': 'expense',
        'txnCategory': 'notARealCategory',
        'date': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
        'categoryId': 'other',
        'accountId': 'account-1',
        'source': 'manual',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final doc = await docRef.get();
      final transaction = app_model.Transaction.fromFirestore(doc);

      expect(transaction.txnCategory, app_model.TxnCategory.expense);
    });
  });

  group('Transaction.resolvePaymentMethod', () {
    test('prefers the explicitly detected payment method', () {
      final transaction = _smsTransaction().copyWith(
        paymentMethod: () => app_model.TxnPaymentMethod.upi,
      );
      final mode = PaymentMode(
        id: 'mode-1',
        userId: 'user-1',
        type: PaymentModeType.creditCard,
        title: 'Card',
        createdAt: DateTime.utc(2026),
      );

      expect(
        transaction.resolvePaymentMethod(mode),
        app_model.TxnPaymentMethod.upi,
      );
    });

    test('falls back to the linked payment mode type when undetected', () {
      final transaction = _smsTransaction();
      final mode = PaymentMode(
        id: 'mode-1',
        userId: 'user-1',
        type: PaymentModeType.creditCard,
        title: 'Card',
        createdAt: DateTime.utc(2026),
      );

      expect(
        transaction.resolvePaymentMethod(mode),
        app_model.TxnPaymentMethod.creditCard,
      );
    });

    test('returns null when neither a detected method nor a mode is available',
        () {
      final transaction = _smsTransaction();

      expect(transaction.resolvePaymentMethod(null), isNull);
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
