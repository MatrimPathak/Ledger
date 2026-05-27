import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/transaction.dart' as app_model;
import 'package:ledger/services/firebase/firestore_service.dart';

void main() {
  group('FirestoreService.transactionsFromDocs', () {
    test('filters matching account transactions while preserving query order', () {
      final newest = DateTime.utc(2026, 5, 25, 12);
      final middle = DateTime.utc(2026, 5, 24, 12);
      final oldest = DateTime.utc(2026, 5, 23, 12);

      final transactions = FirestoreService.transactionsFromDocs(
        [
          _transactionDoc(
            id: 'newest-checking',
            title: 'Newest checking',
            accountId: 'checking',
            date: newest,
          ),
          _transactionDoc(
            id: 'middle-savings',
            title: 'Middle savings',
            accountId: 'savings',
            date: middle,
          ),
          _transactionDoc(
            id: 'oldest-checking',
            title: 'Oldest checking',
            accountId: 'checking',
            date: oldest,
          ),
        ],
        accountId: 'checking',
      );

      expect(
        transactions.map((transaction) => transaction.id),
        ['newest-checking', 'oldest-checking'],
      );
      expect(
        transactions.map((transaction) => transaction.accountId).toSet(),
        {'checking'},
      );
    });

    test('returns every transaction when no account filter is selected', () {
      final transactions = FirestoreService.transactionsFromDocs([
        _transactionDoc(
          id: 'checking-transaction',
          title: 'Checking transaction',
          accountId: 'checking',
          date: DateTime.utc(2026, 5, 25),
        ),
        _transactionDoc(
          id: 'savings-transaction',
          title: 'Savings transaction',
          accountId: 'savings',
          date: DateTime.utc(2026, 5, 24),
          type: app_model.TransactionType.income,
        ),
      ]);

      expect(
        transactions.map((transaction) => transaction.id),
        ['checking-transaction', 'savings-transaction'],
      );
      expect(
        transactions.map((transaction) => transaction.type),
        [app_model.TransactionType.expense, app_model.TransactionType.income],
      );
    });
  });
}

_TransactionDoc _transactionDoc({
  required String id,
  required String title,
  required String accountId,
  required DateTime date,
  app_model.TransactionType type = app_model.TransactionType.expense,
}) {
  return _TransactionDoc(id, {
    'userId': 'user-1',
    'title': title,
    'amount': 42.5,
    'type': type.name,
    'date': Timestamp.fromDate(date),
    'categoryId': 'category-1',
    'accountId': accountId,
    'paymentModeId': null,
    'notes': null,
    'source': app_model.TransactionSource.manual.name,
    'rawSms': null,
    'createdAt': Timestamp.fromDate(date),
  });
}

class _TransactionDoc implements DocumentSnapshot<Object?> {
  _TransactionDoc(this.id, this._data);

  final Map<String, dynamic> _data;

  @override
  final String id;

  @override
  Object? data() => _data;

  @override
  bool get exists => true;

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
