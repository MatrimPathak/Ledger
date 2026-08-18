import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/financial_event.dart';
import '../services/notification/notification_listener_bridge.dart';

/// Live buffered notification events, started lazily on first watch and
/// stopped when nothing is listening — the native side simply stops being
/// asked for events, it isn't told to shut down (the OS owns that via the
/// user's system settings).
final notificationEventsProvider =
    StreamProvider.autoDispose<List<FinancialEvent>>((ref) async* {
  final bridge = NotificationListenerBridge.instance;
  bridge.start();
  ref.onDispose(bridge.stop);
  // Seed with whatever's already buffered — without this, events that
  // arrived before this listener attached (e.g. while some other screen was
  // in the foreground) would be invisible until the *next* event arrives.
  yield bridge.recentEvents();
  yield* bridge.events;
});

/// Live OS-level check — not an app setting — of whether the user has
/// granted notification-listener access in system settings.
final notificationAccessGrantedProvider = FutureProvider.autoDispose<bool>((ref) {
  return NotificationListenerBridge.isAccessGranted();
});
