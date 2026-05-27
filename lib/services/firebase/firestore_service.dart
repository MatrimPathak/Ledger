import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/account.dart';
import '../../models/category.dart';
import '../../models/payment_mode.dart';
import '../../models/transaction.dart' as app_model;
import '../../models/user_profile.dart';
import '../../core/constants/default_categories.dart';

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
    await _categories(category.userId).add(category.toFirestore());
    return category;
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
        .map((s) => s.docs
            .where((doc) =>
                accountId == null ||
                (doc.data() as Map<String, dynamic>)['accountId'] == accountId)
            .map(app_model.Transaction.fromFirestore)
            .toList());
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

  // Delete all user data
  Future<void> deleteAllUserData(String uid) async {
    final batch = _db.batch();
    final collections = ['accounts', 'paymentModes', 'categories', 'transactions'];
    for (final col in collections) {
      final snap = await _userDoc(uid).collection(col).get();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
    }
    batch.delete(_userDoc(uid));
    await batch.commit();
  }
}
