import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' hide Category;
import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/credit_card_account.dart';
import '../../models/merchant.dart';
import '../../models/payment_mode.dart';
import '../../models/subscription.dart';
import '../../models/transaction.dart' as app_model;
import '../../models/user_profile.dart';
import '../../core/constants/default_categories.dart';

/// A single account-balance increment to apply as part of an atomic
/// transaction write, e.g. `{accountId: 'checking', delta: -250}`.
class BalanceAdjustment {
  const BalanceAdjustment({required this.accountId, required this.delta});

  final String accountId;
  final double delta;
}

/// A single credit-card-outstanding increment to apply atomically
/// alongside a transaction write — positive for a purchase (outstanding
/// grows), negative for a bill payment (outstanding shrinks).
class CreditCardAdjustment {
  const CreditCardAdjustment(
      {required this.creditCardAccountId, required this.delta});

  final String creditCardAccountId;
  final double delta;
}

class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // Collection refs
  DocumentReference _userDoc(String uid) => _db.collection('users').doc(uid);

  CollectionReference _accounts(String uid) =>
      _userDoc(uid).collection('accounts');

  CollectionReference _paymentModes(String uid) =>
      _userDoc(uid).collection('paymentModes');

  CollectionReference _categories(String uid) =>
      _userDoc(uid).collection('categories');

  CollectionReference _transactions(String uid) =>
      _userDoc(uid).collection('transactions');

  CollectionReference _merchants(String uid) =>
      _userDoc(uid).collection('merchants');

  CollectionReference _creditCardAccounts(String uid) =>
      _userDoc(uid).collection('creditCardAccounts');

  CollectionReference _subscriptions(String uid) =>
      _userDoc(uid).collection('subscriptions');

  // User profile
  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _userDoc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromFirestore(doc);
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _userDoc(profile.uid).set(profile.toFirestore(), SetOptions(merge: true));
  }

  Future<void> markOnboardingComplete(String uid) async {
    await _userDoc(uid).set({'onboardingComplete': true}, SetOptions(merge: true));
  }

  // Seed default categories (batch write, called once on first login)
  Future<void> seedDefaultCategories(String uid) async {
    final batch = _db.batch();
    final existing = await _categories(uid).limit(1).get();
    if (existing.docs.isNotEmpty) return;

    for (final cat in DefaultCategories.list) {
      final ref = _categories(uid).doc();
      batch.set(ref, {
        'userId': uid,
        'title': cat['title'],
        'iconCodePoint': (cat['icon'] as dynamic).codePoint,
        'colorValue': (cat['color'] as dynamic).value,
        'isDefault': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  // Accounts
  Stream<List<Account>> watchAccounts(String uid) {
    return _accounts(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Account.fromFirestore).toList());
  }

  Future<Account> createAccount(Account account) async {
    await _accounts(account.userId).add(account.toFirestore());
    return account.copyWith();
  }

  Future<void> updateAccount(Account account) async {
    await _accounts(account.userId).doc(account.id).update(account.toFirestore());
  }

  Future<void> deleteAccount(String uid, String accountId) async {
    await _accounts(uid).doc(accountId).delete();
  }

  Future<void> updateAccountBalance(String uid, String accountId, double delta) async {
    await _accounts(uid)
        .doc(accountId)
        .update({'balance': FieldValue.increment(delta)});
  }

  Future<List<Account>> fetchAccounts(String uid) async {
    final snap = await _accounts(uid).get();
    return snap.docs.map(Account.fromFirestore).toList();
  }

  // Payment modes
  Stream<List<PaymentMode>> watchPaymentModes(String uid) {
    return _paymentModes(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(PaymentMode.fromFirestore).toList());
  }

  Future<PaymentMode> createPaymentMode(PaymentMode mode) async {
    await _paymentModes(mode.userId).add(mode.toFirestore());
    return mode;
  }

  Future<void> updatePaymentMode(PaymentMode mode) async {
    await _paymentModes(mode.userId).doc(mode.id).update(mode.toFirestore());
  }

  Future<void> deletePaymentMode(String uid, String modeId) async {
    await _paymentModes(uid).doc(modeId).delete();
  }

  Future<List<PaymentMode>> fetchPaymentModes(String uid) async {
    final snap = await _paymentModes(uid).get();
    return snap.docs.map(PaymentMode.fromFirestore).toList();
  }

  // Categories
  Stream<List<Category>> watchCategories(String uid) {
    return _categories(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Category.fromFirestore).toList());
  }

  Future<Category> createCategory(Category category) async {
    final docRef = await _categories(category.userId).add(category.toFirestore());
    return Category(
      id: docRef.id,
      userId: category.userId,
      title: category.title,
      iconCodePoint: category.iconCodePoint,
      colorValue: category.colorValue,
      isDefault: category.isDefault,
      createdAt: category.createdAt,
    );
  }

  Future<void> deleteCategory(String uid, String categoryId) async {
    await _categories(uid).doc(categoryId).delete();
  }

  // Transactions
  Stream<List<app_model.Transaction>> watchTransactions(
    String uid, {
    DateTime? from,
    DateTime? to,
    String? accountId,
  }) {
    Query query = _transactions(uid);
    if (from != null) {
      query = query.where('date',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from));
    }
    if (to != null) {
      query = query.where('date',
          isLessThanOrEqualTo: Timestamp.fromDate(to));
    }
    return query
        .orderBy('date', descending: true)
        .limit(500)
        .snapshots()
        .map((s) => transactionsFromDocs(s.docs, accountId: accountId));
  }

  @visibleForTesting
  static List<app_model.Transaction> transactionsFromDocs(
    Iterable<DocumentSnapshot<Object?>> docs, {
    String? accountId,
  }) {
    return docs
        .where((doc) =>
            accountId == null ||
            (doc.data() as Map<String, dynamic>)['accountId'] == accountId)
        .map(app_model.Transaction.fromFirestore)
        .toList();
  }

  Future<app_model.Transaction> createTransaction(app_model.Transaction tx) async {
    final docRef = await _transactions(tx.userId).add(tx.toFirestore());
    return tx.copyWith(id: docRef.id);
  }

  Future<void> updateTransaction(app_model.Transaction tx) async {
    await _transactions(tx.userId).doc(tx.id).update(tx.toFirestore());
  }

  Future<app_model.Transaction?> getTransaction(
      String uid, String txId) async {
    final doc = await _transactions(uid).doc(txId).get();
    if (!doc.exists) return null;
    return app_model.Transaction.fromFirestore(doc);
  }

  Future<void> deleteTransaction(String uid, String txId) async {
    await _transactions(uid).doc(txId).delete();
  }

  /// Creates [tx] and applies every [balanceAdjustments]/
  /// [creditCardAdjustments] increment in a single atomic write, so a
  /// crash mid-write can no longer desync the transaction doc from the
  /// account balance or card outstanding it affects.
  Future<app_model.Transaction> createTransactionWithBalanceUpdate(
    app_model.Transaction tx, {
    List<BalanceAdjustment> balanceAdjustments = const [],
    List<CreditCardAdjustment> creditCardAdjustments = const [],
  }) async {
    final docRef = _transactions(tx.userId).doc();
    await _db.runTransaction((transaction) async {
      transaction.set(docRef, tx.toFirestore());
      for (final adjustment in balanceAdjustments) {
        transaction.update(
          _accounts(tx.userId).doc(adjustment.accountId),
          {'balance': FieldValue.increment(adjustment.delta)},
        );
      }
      for (final adjustment in creditCardAdjustments) {
        transaction.update(
          _creditCardAccounts(tx.userId).doc(adjustment.creditCardAccountId),
          {'currentOutstanding': FieldValue.increment(adjustment.delta)},
        );
      }
    });
    return tx.copyWith(id: docRef.id);
  }

  /// Updates [tx] and applies every [balanceAdjustments]/
  /// [creditCardAdjustments] increment atomically — used for edits, where
  /// up to two accounts (old/new) may need reversal/reapplication.
  Future<void> updateTransactionWithBalanceAdjustments(
    app_model.Transaction tx, {
    List<BalanceAdjustment> balanceAdjustments = const [],
    List<CreditCardAdjustment> creditCardAdjustments = const [],
  }) async {
    await _db.runTransaction((transaction) async {
      transaction.update(
          _transactions(tx.userId).doc(tx.id), tx.toFirestore());
      for (final adjustment in balanceAdjustments) {
        transaction.update(
          _accounts(tx.userId).doc(adjustment.accountId),
          {'balance': FieldValue.increment(adjustment.delta)},
        );
      }
      for (final adjustment in creditCardAdjustments) {
        transaction.update(
          _creditCardAccounts(tx.userId).doc(adjustment.creditCardAccountId),
          {'currentOutstanding': FieldValue.increment(adjustment.delta)},
        );
      }
    });
  }

  /// Deletes the transaction and reverses [balanceAdjustments]/
  /// [creditCardAdjustments] atomically.
  Future<void> deleteTransactionWithBalanceUpdate(
    String uid,
    String txId, {
    List<BalanceAdjustment> balanceAdjustments = const [],
    List<CreditCardAdjustment> creditCardAdjustments = const [],
  }) async {
    await _db.runTransaction((transaction) async {
      transaction.delete(_transactions(uid).doc(txId));
      for (final adjustment in balanceAdjustments) {
        transaction.update(
          _accounts(uid).doc(adjustment.accountId),
          {'balance': FieldValue.increment(adjustment.delta)},
        );
      }
      for (final adjustment in creditCardAdjustments) {
        transaction.update(
          _creditCardAccounts(uid).doc(adjustment.creditCardAccountId),
          {'currentOutstanding': FieldValue.increment(adjustment.delta)},
        );
      }
    });
  }

  /// Firestore-side dedup check layered on top of the device-local
  /// fingerprint list: true when a transaction with this bank/UPI reference
  /// number already exists for this user. The strongest dedup signal when
  /// present, since it's independent of device state (survives app-data
  /// clears/reinstalls that would otherwise defeat the SharedPreferences
  /// fingerprint fast-path).
  Future<bool> transactionExistsByExternalRef(
      String uid, String externalTransactionId) async {
    final snap = await _transactions(uid)
        .where('externalTransactionId', isEqualTo: externalTransactionId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// Fallback dedup check when no reference number was extracted: true when
  /// a transaction with the same normalized-SMS-body hash already exists
  /// within [window] of [near] (the SMS's own timestamp). Scoped to a time
  /// window rather than an unbounded hash lookup since the same merchant
  /// SMS wording can legitimately recur across unrelated transactions.
  Future<bool> transactionExistsByHashNearby(
    String uid,
    String sourceMessageHash,
    DateTime near, {
    Duration window = const Duration(minutes: 2),
  }) async {
    final snap = await _transactions(uid)
        .where('sourceMessageHash', isEqualTo: sourceMessageHash)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(near.subtract(window)))
        .where('date',
            isLessThanOrEqualTo: Timestamp.fromDate(near.add(window)))
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  Future<List<app_model.Transaction>> fetchTransactionsForAnalytics(
      String uid, int days) async {
    final from = DateTime.now().subtract(Duration(days: days));
    final snap = await _transactions(uid)
        .where('date',
            isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .orderBy('date', descending: true)
        .get();
    return snap.docs
        .map(app_model.Transaction.fromFirestore)
        .toList();
  }

  // Merchants
  Stream<List<Merchant>> watchMerchants(String uid) {
    return _merchants(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Merchant.fromFirestore).toList());
  }

  Future<List<Merchant>> fetchMerchants(String uid) async {
    final snap = await _merchants(uid).get();
    return snap.docs.map(Merchant.fromFirestore).toList();
  }

  Future<Merchant> createMerchant(Merchant merchant) async {
    final docRef = await _merchants(merchant.userId).add(merchant.toFirestore());
    return Merchant(
      id: docRef.id,
      userId: merchant.userId,
      displayName: merchant.displayName,
      normalizedKey: merchant.normalizedKey,
      defaultCategoryId: merchant.defaultCategoryId,
      aliasPatterns: merchant.aliasPatterns,
      createdAt: merchant.createdAt,
    );
  }

  Future<void> updateMerchant(Merchant merchant) async {
    await _merchants(merchant.userId).doc(merchant.id).update(merchant.toFirestore());
  }

  // Credit card accounts
  Stream<List<CreditCardAccount>> watchCreditCardAccounts(String uid) {
    return _creditCardAccounts(uid)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((s) => s.docs.map(CreditCardAccount.fromFirestore).toList());
  }

  Future<List<CreditCardAccount>> fetchCreditCardAccounts(String uid) async {
    final snap = await _creditCardAccounts(uid).get();
    return snap.docs.map(CreditCardAccount.fromFirestore).toList();
  }

  Future<CreditCardAccount> createCreditCardAccount(
      CreditCardAccount account) async {
    final docRef =
        await _creditCardAccounts(account.userId).add(account.toFirestore());
    return CreditCardAccount(
      id: docRef.id,
      userId: account.userId,
      paymentModeId: account.paymentModeId,
      title: account.title,
      bankName: account.bankName,
      lastFourDigits: account.lastFourDigits,
      creditLimit: account.creditLimit,
      currentOutstanding: account.currentOutstanding,
      statementDay: account.statementDay,
      dueDay: account.dueDay,
      minimumDuePercent: account.minimumDuePercent,
      currency: account.currency,
      createdAt: account.createdAt,
      needsReconciliation: account.needsReconciliation,
    );
  }

  /// Excludes `currentOutstanding` — that field is only ever written via
  /// the atomic `FieldValue.increment()` calls above. Writing the full
  /// `toFirestore()` map here would let a stale in-memory snapshot (e.g.
  /// editing the card's due date) clobber an outstanding-balance increment
  /// that landed concurrently from a new purchase/payment.
  Future<void> updateCreditCardAccount(CreditCardAccount account) async {
    final data = account.toFirestore()..remove('currentOutstanding');
    await _creditCardAccounts(account.userId).doc(account.id).update(data);
  }

  // Subscriptions / recurring detection
  Stream<List<Subscription>> watchSubscriptions(String uid) {
    return _subscriptions(uid)
        .orderBy('nextExpectedDate', descending: false)
        .snapshots()
        .map((s) => s.docs.map(Subscription.fromFirestore).toList());
  }

  Future<List<Subscription>> fetchSubscriptions(String uid) async {
    final snap = await _subscriptions(uid).get();
    return snap.docs.map(Subscription.fromFirestore).toList();
  }

  Future<Subscription> createSubscription(Subscription subscription) async {
    final docRef =
        await _subscriptions(subscription.userId).add(subscription.toFirestore());
    return Subscription(
      id: docRef.id,
      userId: subscription.userId,
      merchantId: subscription.merchantId,
      merchantNameRaw: subscription.merchantNameRaw,
      kind: subscription.kind,
      expectedAmount: subscription.expectedAmount,
      amountTolerancePercent: subscription.amountTolerancePercent,
      intervalDays: subscription.intervalDays,
      lastSeenDate: subscription.lastSeenDate,
      nextExpectedDate: subscription.nextExpectedDate,
      matchedTransactionIds: subscription.matchedTransactionIds,
      status: subscription.status,
      detectionSource: subscription.detectionSource,
      createdAt: subscription.createdAt,
    );
  }

  Future<void> updateSubscription(Subscription subscription) async {
    await _subscriptions(subscription.userId)
        .doc(subscription.id)
        .update(subscription.toFirestore());
  }

  Future<void> deleteSubscription(String uid, String subscriptionId) async {
    await _subscriptions(uid).doc(subscriptionId).delete();
  }

  // Delete all user data. A single WriteBatch caps out at 500 operations —
  // the transactions collection alone routinely exceeds that for an
  // SMS-ingesting ledger — so deletes are chunked across as many batches as
  // needed rather than committed all at once.
  static const int _maxBatchOps = 500;

  Future<void> deleteAllUserData(String uid) async {
    final collections = [
      'accounts',
      'paymentModes',
      'categories',
      'transactions',
      'merchants',
      'creditCardAccounts',
      'subscriptions',
    ];

    var batch = _db.batch();
    var opsInBatch = 0;

    Future<void> flush() async {
      if (opsInBatch == 0) return;
      await batch.commit();
      batch = _db.batch();
      opsInBatch = 0;
    }

    for (final col in collections) {
      final snap = await _userDoc(uid).collection(col).get();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
        opsInBatch++;
        if (opsInBatch >= _maxBatchOps) await flush();
      }
    }
    batch.delete(_userDoc(uid));
    opsInBatch++;
    await flush();
  }
}
