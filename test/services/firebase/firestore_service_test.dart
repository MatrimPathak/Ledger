import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/transaction.dart' as app_model;
import 'package:ledger/models/user_profile.dart';
import 'package:ledger/services/firebase/firestore_service.dart';

void main() {
  group('FirestoreService.markOnboardingComplete', () {
    test('creates the user document when it does not exist', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);

      await service.markOnboardingComplete('new-user');

      final doc = await firestore.collection('users').doc('new-user').get();
      expect(doc.exists, isTrue);
      expect(doc.data(), containsPair('onboardingComplete', true));
    });

    test('merges the completion flag into an existing profile', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final createdAt = DateTime.utc(2026, 1, 2, 3, 4, 5);

      await service.saveProfile(
        UserProfile(
          uid: 'existing-user',
          name: 'Existing User',
          email: 'existing@example.com',
          photoUrl: 'https://example.com/avatar.png',
          currency: 'USD',
          createdAt: createdAt,
        ),
      );

      await service.markOnboardingComplete('existing-user');

      final profile = await service.getProfile('existing-user');
      expect(profile, isNotNull);
      expect(profile!.name, 'Existing User');
      expect(profile.email, 'existing@example.com');
      expect(profile.photoUrl, 'https://example.com/avatar.png');
      expect(profile.currency, 'USD');
      expect(profile.createdAt.toUtc(), createdAt);
      expect(profile.onboardingComplete, isTrue);
    });
  });

  group('FirestoreService.transactionsFromDocs', () {
    test('filters matching account transactions while preserving query order',
        () {
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

  group('FirestoreService.createTransaction', () {
    test('returns the Firestore-assigned id used by notification deep links',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final createdAt = DateTime.utc(2026, 5, 27, 12);
      final transaction = app_model.Transaction(
        id: '',
        userId: 'user-1',
        title: 'Coffee Shop',
        amount: 250,
        type: app_model.TransactionType.expense,
        date: createdAt,
        categoryId: 'food',
        accountId: 'checking',
        paymentModeId: 'upi-1',
        source: app_model.TransactionSource.sms,
        rawSms: 'INR 250 debited at Coffee Shop',
        createdAt: createdAt,
      );

      final saved = await service.createTransaction(transaction);

      expect(saved.id, isNotEmpty);
      expect(saved.id, isNot(transaction.id));
      expect(saved.title, transaction.title);
      expect(saved.source, app_model.TransactionSource.sms);
      expect(saved.rawSms, transaction.rawSms);

      final snap = await firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .get();
      expect(snap.docs, hasLength(1));
      expect(snap.docs.single.id, saved.id);
      expect(snap.docs.single.data()['title'], 'Coffee Shop');
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
