import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/merchant.dart';

void main() {
  group('Merchant.normalize', () {
    test('lowercases and strips punctuation', () {
      expect(Merchant.normalize('Uber India Pvt. Ltd.'), 'uber india pvt ltd');
    });

    test('collapses repeated whitespace', () {
      expect(Merchant.normalize('  Amazon   Pay  '), 'amazon pay');
    });
  });

  group('Merchant.withAlias', () {
    Merchant merchant({List<String> aliases = const []}) => Merchant(
          id: 'merchant-1',
          userId: 'user-1',
          displayName: 'Uber',
          normalizedKey: 'uber',
          aliasPatterns: aliases,
          createdAt: DateTime.utc(2026),
        );

    test('appends a new alias', () {
      final updated = merchant().withAlias('Rajesh Kumar');

      expect(updated.aliasPatterns, ['Rajesh Kumar']);
    });

    test('does not duplicate an existing alias', () {
      final updated =
          merchant(aliases: ['Rajesh Kumar']).withAlias('Rajesh Kumar');

      expect(updated.aliasPatterns, ['Rajesh Kumar']);
    });

    test('evicts the oldest alias once the bound is exceeded', () {
      final aliases =
          List.generate(Merchant.maxAliasPatterns, (i) => 'payee-$i');
      final updated = merchant(aliases: aliases).withAlias('payee-new');

      expect(updated.aliasPatterns.length, Merchant.maxAliasPatterns);
      expect(updated.aliasPatterns.first, 'payee-1');
      expect(updated.aliasPatterns.last, 'payee-new');
    });
  });

  group('Merchant Firestore round trip', () {
    test('preserves alias patterns and default category through persistence',
        () async {
      final firestore = FakeFirebaseFirestore();
      final merchant = Merchant(
        id: '',
        userId: 'user-1',
        displayName: 'Uber',
        normalizedKey: 'uber',
        defaultCategoryId: 'transport',
        aliasPatterns: const ['Rajesh Kumar', 'Ganesh Kumar'],
        createdAt: DateTime.utc(2026, 1, 1),
      );

      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('merchants')
          .doc('merchant-1');
      await docRef.set(merchant.toFirestore());

      final roundTripped = Merchant.fromFirestore(await docRef.get());

      expect(roundTripped.displayName, 'Uber');
      expect(roundTripped.normalizedKey, 'uber');
      expect(roundTripped.defaultCategoryId, 'transport');
      expect(roundTripped.aliasPatterns, ['Rajesh Kumar', 'Ganesh Kumar']);
    });

    test('defaults alias patterns to empty for documents without the field',
        () async {
      final firestore = FakeFirebaseFirestore();
      final docRef = firestore
          .collection('users')
          .doc('user-1')
          .collection('merchants')
          .doc('merchant-legacy');
      await docRef.set({
        'userId': 'user-1',
        'displayName': 'Netflix',
        'normalizedKey': 'netflix',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      });

      final roundTripped = Merchant.fromFirestore(await docRef.get());

      expect(roundTripped.aliasPatterns, isEmpty);
      expect(roundTripped.defaultCategoryId, isNull);
    });
  });
}
