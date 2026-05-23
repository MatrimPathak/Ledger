import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/utils/currency_formatter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _channelId = 'ledger_sms';
  static const _channelName = 'Auto-detected Transactions';

  /// Stream that emits a transactionId whenever a notification is tapped.
  /// Listeners (e.g. in app.dart) can subscribe to navigate accordingly.
  static final StreamController<String> _tapController =
      StreamController<String>.broadcast();

  static Stream<String> get onNotificationTap => _tapController.stream;

  static Future<void> initialize() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _createChannel();
  }

  static Future<void> _createChannel() async {
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Notifications for automatically detected transactions',
      importance: Importance.high,
      playSound: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapController.add(payload);
    }
  }

  static Future<void> showTransactionDetectedNotification({
    required int id,
    required String title,
    required String body,
    required String transactionId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Auto-detected transaction notification',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Transaction detected',
      styleInformation: BigTextStyleInformation(''),
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: transactionId);
  }

  static String buildNotificationTitle(
      String merchantName, double amount, String currency) {
    final formatted = CurrencyFormatter.format(amount, currency: currency);
    return '$formatted added · $merchantName';
  }
}
