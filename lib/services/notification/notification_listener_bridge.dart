import 'dart:async';
import 'package:flutter/services.dart';
import '../../models/financial_event.dart';

/// Bridges native notification events into a small in-memory ring buffer.
///
/// The native [LedgerNotificationListenerService] (Kotlin) extracts only a
/// package name, post time, and a regex-guessed amount/direction from each
/// notification, discarding the full text immediately — this class never
/// sees more than that. Nothing here is ever written to Firestore or disk:
/// events are useful for a few minutes at most (to correlate against a
/// just-created SMS transaction), then pruned.
class NotificationListenerBridge {
  NotificationListenerBridge._();
  static final NotificationListenerBridge instance =
      NotificationListenerBridge._();

  static const EventChannel _events =
      EventChannel('com.matrimpathak.ledger/notification_events');
  static const MethodChannel _access =
      MethodChannel('com.matrimpathak.ledger/notification_access');

  static const int maxBufferedEvents = 20;
  static const Duration eventTtl = Duration(minutes: 10);

  final List<FinancialEvent> _buffer = [];
  StreamSubscription<dynamic>? _subscription;
  final StreamController<List<FinancialEvent>> _controller =
      StreamController<List<FinancialEvent>>.broadcast();

  Stream<List<FinancialEvent>> get events => _controller.stream;

  /// Starts listening for native events. Safe to call multiple times — a
  /// second call is a no-op while already listening.
  void start() {
    _subscription ??= _events.receiveBroadcastStream().listen(
      (raw) {
        if (raw is! Map) return;
        _prune();
        _buffer.add(FinancialEvent.fromMap(raw));
        if (_buffer.length > maxBufferedEvents) {
          _buffer.removeAt(0);
        }
        _controller.add(List.unmodifiable(_buffer));
      },
      onError: (_) {},
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  List<FinancialEvent> recentEvents() {
    _prune();
    return List.unmodifiable(_buffer);
  }

  void _prune() {
    final cutoff = DateTime.now().subtract(eventTtl);
    _buffer.removeWhere((e) => e.postTime.isBefore(cutoff));
  }

  /// Whether the user has granted this app notification-listener access in
  /// system settings. This is a live OS-level check, not an app setting.
  static Future<bool> isAccessGranted() async {
    try {
      return await _access.invokeMethod<bool>('isAccessGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system's notification-access settings screen — the only way
  /// to grant/revoke [BIND_NOTIFICATION_LISTENER_SERVICE] access, by
  /// Android design (never a normal runtime permission dialog).
  static Future<void> openSettings() async {
    try {
      await _access.invokeMethod<void>('openSettings');
    } catch (_) {}
  }
}
