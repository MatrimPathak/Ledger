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

  group('FirestoreService atomic balance writes', () {
    test('createTransactionWithBalanceUpdate applies the balance delta atomically',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      await firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts')
          .doc('checking')
          .set({'balance': 1000});

      final tx = _newTransaction(amount: 250);
      final saved = await service.createTransactionWithBalanceUpdate(
        tx,
        balanceAdjustments: const [
          BalanceAdjustment(accountId: 'checking', delta: -250),
        ],
      );

      expect(saved.id, isNotEmpty);
      final accountDoc = await firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts')
          .doc('checking')
          .get();
      expect(accountDoc.data()!['balance'], 750);
    });

    test('createTransactionWithBalanceUpdate skips balance writes when no adjustments are given',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      await firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts')
          .doc('checking')
          .set({'balance': 1000});

      await service.createTransactionWithBalanceUpdate(_newTransaction());

      final accountDoc = await firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts')
          .doc('checking')
          .get();
      expect(accountDoc.data()!['balance'], 1000);
    });

    test('updateTransactionWithBalanceAdjustments applies deltas to two accounts atomically',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final accounts = firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts');
      await accounts.doc('checking').set({'balance': 1000});
      await accounts.doc('savings').set({'balance': 500});

      final created = await service.createTransactionWithBalanceUpdate(
        _newTransaction(accountId: 'checking', amount: 250),
        balanceAdjustments: const [
          BalanceAdjustment(accountId: 'checking', delta: -250),
        ],
      );

      final moved = created.copyWith(accountId: 'savings');
      await service.updateTransactionWithBalanceAdjustments(
        moved,
        balanceAdjustments: const [
          BalanceAdjustment(accountId: 'checking', delta: 250),
          BalanceAdjustment(accountId: 'savings', delta: -250),
        ],
      );

      expect((await accounts.doc('checking').get()).data()!['balance'], 1000);
      expect((await accounts.doc('savings').get()).data()!['balance'], 250);
    });

    test('deleteTransactionWithBalanceUpdate removes the doc and reverses the balance',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final accounts = firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts');
      await accounts.doc('checking').set({'balance': 1000});

      final created = await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 250),
        balanceAdjustments: const [
          BalanceAdjustment(accountId: 'checking', delta: -250),
        ],
      );

      await service.deleteTransactionWithBalanceUpdate(
        'user-1',
        created.id,
        balanceAdjustments: const [
          BalanceAdjustment(accountId: 'checking', delta: 250),
        ],
      );

      final txDoc = await firestore
          .collection('users')
          .doc('user-1')
          .collection('transactions')
          .doc(created.id)
          .get();
      expect(txDoc.exists, isFalse);
      expect((await accounts.doc('checking').get()).data()!['balance'], 1000);
    });
  });

  group('FirestoreService credit card accounting', () {
    test('a sequence of purchases and payments keeps currentOutstanding correct',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final cardRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('creditCardAccounts')
          .doc('card-1');
      await cardRef.set({'userId': 'user-1', 'currentOutstanding': 0.0});

      // Purchase ₹1500
      await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 1500),
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: 1500),
        ],
      );
      expect((await cardRef.get()).data()!['currentOutstanding'], 1500);

      // Purchase ₹2000
      await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 2000),
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: 2000),
        ],
      );
      expect((await cardRef.get()).data()!['currentOutstanding'], 3500);

      // Bill payment of ₹3500 — outstanding returns to zero
      await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 3500),
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: -3500),
        ],
      );
      expect((await cardRef.get()).data()!['currentOutstanding'], 0.0);
    });

    test('a credit card purchase never touches the linked bank account balance',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final accounts = firestore
          .collection('users')
          .doc('user-1')
          .collection('accounts');
      await accounts.doc('checking').set({'balance': 1000});
      final cardRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('creditCardAccounts')
          .doc('card-1');
      await cardRef.set({'userId': 'user-1', 'currentOutstanding': 0.0});

      // No balanceAdjustments passed — a credit-card purchase's
      // affectsBalance is false, mirroring sms_service.dart's behavior.
      await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 500),
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: 500),
        ],
      );

      expect((await accounts.doc('checking').get()).data()!['balance'], 1000);
      expect((await cardRef.get()).data()!['currentOutstanding'], 500);
    });

    test('deleting a purchase transaction reverses the outstanding adjustment',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final cardRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('creditCardAccounts')
          .doc('card-1');
      await cardRef.set({'userId': 'user-1', 'currentOutstanding': 0.0});

      final created = await service.createTransactionWithBalanceUpdate(
        _newTransaction(amount: 800),
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: 800),
        ],
      );
      expect((await cardRef.get()).data()!['currentOutstanding'], 800);

      await service.deleteTransactionWithBalanceUpdate(
        'user-1',
        created.id,
        creditCardAdjustments: const [
          CreditCardAdjustment(creditCardAccountId: 'card-1', delta: -800),
        ],
      );
      expect((await cardRef.get()).data()!['currentOutstanding'], 0.0);
    });
  });

  group('FirestoreService dedup checks', () {
    test('transactionExistsByExternalRef finds a matching reference number',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      await service.createTransactionWithBalanceUpdate(
        _newTransaction().copyWith(
          externalTransactionId: () => 'UTR123456',
        ),
      );

      expect(
        await service.transactionExistsByExternalRef('user-1', 'UTR123456'),
        isTrue,
      );
      expect(
        await service.transactionExistsByExternalRef('user-1', 'UTR999999'),
        isFalse,
      );
    });

    test('transactionExistsByHashNearby finds a matching hash within the time window',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final txDate = DateTime.utc(2026, 6, 1, 12, 0);
      await service.createTransactionWithBalanceUpdate(
        _newTransaction().copyWith(
          date: txDate,
          sourceMessageHash: () => 'hash-abc',
        ),
      );

      expect(
        await service.transactionExistsByHashNearby(
          'user-1',
          'hash-abc',
          txDate.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
      expect(
        await service.transactionExistsByHashNearby(
          'user-1',
          'hash-abc',
          txDate.add(const Duration(minutes: 10)),
        ),
        isFalse,
        reason: 'outside the default 2-minute window',
      );
      expect(
        await service.transactionExistsByHashNearby(
          'user-1',
          'hash-different',
          txDate,
        ),
        isFalse,
      );
    });
  });
}

app_model.Transaction _newTransaction({
  String accountId = 'checking',
  double amount = 250,
  app_model.TransactionType type = app_model.TransactionType.expense,
}) {
  final now = DateTime.utc(2026, 6, 1);
  return app_model.Transaction(
    id: '',
    userId: 'user-1',
    title: 'Coffee Shop',
    amount: amount,
    type: type,
    date: now,
    categoryId: 'food',
    accountId: accountId,
    createdAt: now,
  );
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
