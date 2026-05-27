import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
      expect(profile.createdAt, createdAt);
      expect(profile.onboardingComplete, isTrue);
    });
  });
}
