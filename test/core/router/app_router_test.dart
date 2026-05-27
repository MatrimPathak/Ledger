import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/router/app_router.dart';
import 'package:ledger/models/user_profile.dart';

void main() {
  group('resolveAuthRedirect', () {
    test('keeps unauthenticated users on login', () async {
      final redirect = await resolveAuthRedirect(
        userId: null,
        location: '/login',
        loadProfile: (_) => throw StateError('Profile should not load'),
      );

      expect(redirect, isNull);
    });

    test('sends unauthenticated users away from protected routes', () async {
      final redirect = await resolveAuthRedirect(
        userId: null,
        location: '/home',
        loadProfile: (_) => throw StateError('Profile should not load'),
      );

      expect(redirect, '/login');
    });

    test('sends signed-in users with missing profiles to onboarding', () async {
      final redirect = await resolveAuthRedirect(
        userId: 'user-1',
        location: '/login',
        loadProfile: (_) => null,
      );

      expect(redirect, '/onboarding');
    });

    test(
      'sends signed-in users with incomplete onboarding to onboarding',
      () async {
        final redirect = await resolveAuthRedirect(
          userId: 'user-1',
          location: '/login',
          loadProfile: (_) => _profile(onboardingComplete: false),
        );

        expect(redirect, '/onboarding');
      },
    );

    test('sends signed-in users with complete onboarding home', () async {
      final redirect = await resolveAuthRedirect(
        userId: 'user-1',
        location: '/login',
        loadProfile: (_) => _profile(onboardingComplete: true),
      );

      expect(redirect, '/home');
    });

    test('keeps signed-in users on protected routes without profile lookup',
        () async {
      var loadedProfile = false;

      final redirect = await resolveAuthRedirect(
        userId: 'user-1',
        location: '/home',
        loadProfile: (_) {
          loadedProfile = true;
          return _profile(onboardingComplete: true);
        },
      );

      expect(redirect, isNull);
      expect(loadedProfile, isFalse);
    });

    test('falls back home when profile lookup fails after sign-in', () async {
      final redirect = await resolveAuthRedirect(
        userId: 'user-1',
        location: '/login',
        loadProfile: (_) => throw StateError('Firestore unavailable'),
      );

      expect(redirect, '/home');
    });
  });

  group('AuthStateRefreshNotifier', () {
    test('notifies on auth stream changes until disposed', () async {
      final controller = StreamController<Object?>.broadcast();
      final notifier = AuthStateRefreshNotifier(controller.stream);
      var notifications = 0;
      notifier.addListener(() => notifications++);

      controller.add(null);
      await pumpEventQueue();

      expect(notifications, 1);

      notifier.dispose();
      controller.add(null);
      await pumpEventQueue();

      expect(notifications, 1);

      await controller.close();
    });
  });
}

UserProfile _profile({required bool onboardingComplete}) {
  return UserProfile(
    uid: 'user-1',
    name: 'Test User',
    email: 'test@example.com',
    onboardingComplete: onboardingComplete,
    createdAt: DateTime(2025),
  );
}
