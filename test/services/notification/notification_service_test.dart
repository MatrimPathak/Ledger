import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/services/notification/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NotificationService.showTransactionDetectedNotification', () {
    late _RecordingNotificationsPlugin plugin;

    setUp(() {
      plugin = _RecordingNotificationsPlugin();
      NotificationService.debugSetPlugin(plugin);
    });

    tearDown(NotificationService.debugResetPlugin);

    test('uses the saved transaction id as the tap payload', () async {
      await NotificationService.showTransactionDetectedNotification(
        id: 42,
        title: 'INR 250 added - Coffee Shop',
        body: 'Auto-detected - Tap to review in Ledger',
        transactionId: 'firestore-transaction-id',
      );

      expect(plugin.shown, hasLength(1));

      final notification = plugin.shown.single;
      expect(notification.id, 42);
      expect(notification.title, 'INR 250 added - Coffee Shop');
      expect(notification.body, 'Auto-detected - Tap to review in Ledger');
      expect(notification.payload, 'firestore-transaction-id');
    });

    test('keeps Android details high-priority without empty expanded text',
        () async {
      await NotificationService.showTransactionDetectedNotification(
        id: 42,
        title: 'INR 250 added - Coffee Shop',
        body: 'Auto-detected - Tap to review in Ledger',
        transactionId: 'firestore-transaction-id',
      );

      final androidDetails = plugin.shown.single.details?.android;
      expect(androidDetails, isNotNull);
      expect(androidDetails!.channelId, 'ledger_sms');
      expect(androidDetails.channelName, 'Auto-detected Transactions');
      expect(androidDetails.importance, Importance.high);
      expect(androidDetails.priority, Priority.high);
      expect(androidDetails.ticker, 'Transaction detected');
      expect(androidDetails.styleInformation, isNull);
    });
  });
}

class _RecordingNotificationsPlugin extends FlutterLocalNotificationsPlugin {
  final shown = <_ShownNotification>[];

  @override
  Future<void> show(
    int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails, {
    String? payload,
  }) async {
    shown.add(
      _ShownNotification(
        id: id,
        title: title,
        body: body,
        details: notificationDetails,
        payload: payload,
      ),
    );
  }
}

class _ShownNotification {
  const _ShownNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.details,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final NotificationDetails? details;
  final String? payload;
}
