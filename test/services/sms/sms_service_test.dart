import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/models/category.dart';
import 'package:ledger/services/firebase/firestore_service.dart';
import 'package:ledger/services/sms/sms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveBackgroundSmsUid', () {
    test('prefers the current Firebase Auth uid when it is available',
        () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: 'stored-uid',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: 'auth-uid',
          prefs: prefs,
        ),
        'auth-uid',
      );
    });

    test('falls back to the stored uid for background isolates', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: 'stored-uid',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: null,
          prefs: prefs,
        ),
        'stored-uid',
      );
    });

    test('returns null when neither uid source is usable', () async {
      SharedPreferences.setMockInitialValues({
        AppConstants.prefKeyUid: '',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        resolveBackgroundSmsUid(
          firebaseAuthUid: '',
          prefs: prefs,
        ),
        isNull,
      );
    });
  });

  group('computeSmsHash', () {
    test('is stable for the exact same body', () {
      const body = 'Rs.250 debited from A/C XX1234 at Coffee Shop';

      expect(computeSmsHash(body), computeSmsHash(body));
    });

    test('normalizes whitespace and case before hashing', () {
      const a = 'Rs.250  debited   from A/C XX1234';
      const b = 'rs.250 debited from a/c xx1234';

      expect(computeSmsHash(a), computeSmsHash(b));
    });

    test('differs for genuinely different content', () {
      expect(
        computeSmsHash('Rs.250 debited'),
        isNot(computeSmsHash('Rs.500 debited')),
      );
    });
  });

  group('isPlausibleAmount', () {
    test('rejects zero and negative amounts', () {
      expect(isPlausibleAmount(0), isFalse);
      expect(isPlausibleAmount(-50), isFalse);
    });

    test('rejects amounts above the sanity ceiling', () {
      expect(isPlausibleAmount(10000001), isFalse);
    });

    test('accepts ordinary positive amounts', () {
      expect(isPlausibleAmount(250.75), isTrue);
      expect(isPlausibleAmount(10000000), isTrue);
    });
  });

  group('isPlausibleTransactionDate', () {
    test('accepts past and present dates', () {
      expect(isPlausibleTransactionDate(DateTime.now()), isTrue);
      expect(
        isPlausibleTransactionDate(
            DateTime.now().subtract(const Duration(days: 30))),
        isTrue,
      );
    });

    test('rejects dates more than a day in the future', () {
      expect(
        isPlausibleTransactionDate(
            DateTime.now().add(const Duration(days: 2))),
        isFalse,
      );
    });
  });

  group('resolveOrCreateCategory', () {
    test('matches an existing category by slug substring', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);
      final existing = Category(
        id: '',
        userId: 'user-1',
        title: 'Food & Dining',
        iconCodePoint: 1,
        colorValue: 1,
        isDefault: true,
        createdAt: DateTime.utc(2026),
      );
      final created = await service.createCategory(existing);

      final resolved = await resolveOrCreateCategory(
        slug: 'food',
        categories: [created],
        uid: 'user-1',
        firestoreService: service,
      );

      expect(resolved.id, created.id);
    });

    test('falls back to Other when slug is null', () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);

      final resolved = await resolveOrCreateCategory(
        slug: null,
        categories: const [],
        uid: 'user-1',
        firestoreService: service,
      );

      expect(resolved.title, 'Other');
    });

    test('creates a default category when no user category matches the slug',
        () async {
      final firestore = FakeFirebaseFirestore();
      final service = FirestoreService(firestore: firestore);

      final resolved = await resolveOrCreateCategory(
        slug: 'travel',
        categories: const [],
        uid: 'user-1',
        firestoreService: service,
      );

      expect(resolved.title, 'Travel');
      expect(resolved.id, isNotEmpty);
    });
  });
}
