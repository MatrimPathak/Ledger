import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/credit_card_account.dart';

void main() {
  group('CreditCardAccount derived getters', () {
    test('availableCredit is the limit minus current outstanding', () {
      final card = CreditCardAccount(
        id: 'card-1',
        userId: 'user-1',
        paymentModeId: 'mode-1',
        title: 'HDFC Regalia',
        bankName: 'HDFC',
        lastFourDigits: '9988',
        creditLimit: 100000,
        currentOutstanding: 18450,
        createdAt: DateTime.utc(2026),
      );

      expect(card.availableCredit, 81550);
    });

    test('minimumDue is currentOutstanding times minimumDuePercent', () {
      final card = CreditCardAccount(
        id: 'card-1',
        userId: 'user-1',
        paymentModeId: 'mode-1',
        title: 'HDFC Regalia',
        bankName: 'HDFC',
        lastFourDigits: '9988',
        currentOutstanding: 20000,
        minimumDuePercent: 0.05,
        createdAt: DateTime.utc(2026),
      );

      expect(card.minimumDue, 1000);
    });
  });

  group('CreditCardAccount Firestore round trip', () {
    test('preserves every field through persistence, including reconciliation flag',
        () async {
      final firestore = FakeFirebaseFirestore();
      final card = CreditCardAccount(
        id: '',
        userId: 'user-1',
        paymentModeId: 'mode-1',
        title: 'HDFC Regalia',
        bankName: 'HDFC',
        lastFourDigits: '9988',
        creditLimit: 100000,
        currentOutstanding: 18450,
        statementDay: 5,
        dueDay: 25,
        minimumDuePercent: 0.05,
        currency: 'INR',
        createdAt: DateTime.utc(2026, 1, 1),
        needsReconciliation: true,
      );

      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('creditCardAccounts')
          .doc('card-1');
      await docRef.set(card.toFirestore());

      final roundTripped =
          CreditCardAccount.fromFirestore(await docRef.get());

      expect(roundTripped.paymentModeId, 'mode-1');
      expect(roundTripped.creditLimit, 100000);
      expect(roundTripped.currentOutstanding, 18450);
      expect(roundTripped.statementDay, 5);
      expect(roundTripped.dueDay, 25);
      expect(roundTripped.needsReconciliation, isTrue);
    });

    test('defaults to a non-reconciliation-needed, zero-balance card for a legacy document',
        () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('creditCardAccounts')
          .doc('card-legacy');
      await docRef.set({
        'userId': 'user-1',
        'paymentModeId': 'mode-1',
        'title': 'Card',
        'bankName': 'Bank',
        'lastFourDigits': '1234',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final roundTripped =
          CreditCardAccount.fromFirestore(await docRef.get());

      expect(roundTripped.currentOutstanding, 0);
      expect(roundTripped.creditLimit, 0);
      expect(roundTripped.needsReconciliation, isFalse);
      expect(roundTripped.statementDay, isNull);
    });
  });
}
