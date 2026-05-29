import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../../core/utils/currency_formatter.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const _smsChannelId = 'ledger_sms';
  static const _smsChannelName = 'Auto-detected Transactions';
  static const _txChannelId = 'ledger_transactions';
  static const _txChannelName = 'Transaction Updates';

  static bool notificationsEnabled = true;

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
    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // Request POST_NOTIFICATIONS permission (required on Android 13+).
    await androidPlugin?.requestNotificationsPermission();
    await _createChannels(androidPlugin);
  }

  static Future<void> _createChannels(
      AndroidFlutterLocalNotificationsPlugin? androidPlugin) async {
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _smsChannelId,
        _smsChannelName,
        description: 'Notifications for automatically detected transactions',
        importance: Importance.high,
        playSound: true,
      ),
    );
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _txChannelId,
        _txChannelName,
        description: 'Notifications for manually added or edited transactions',
        importance: Importance.defaultImportance,
        playSound: true,
      ),
    );
  }

  static void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      _tapController.add(payload);
    }
  }

  // ── SMS auto-detect notifications ─────────────────────────────────────────

  static Future<void> showProcessingNotification(String smsPreview) async {
    if (!notificationsEnabled) return;
    const androidDetails = AndroidNotificationDetails(
      _smsChannelId,
      _smsChannelName,
      channelDescription: 'Auto-detected transaction notification',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      0,
      'Ledger — Processing bank SMS…',
      smsPreview.length > 80 ? '${smsPreview.substring(0, 80)}…' : smsPreview,
      details,
    );
  }

  static Future<void> showSmsErrorNotification(String reason) async {
    if (!notificationsEnabled) return;
    const androidDetails = AndroidNotificationDetails(
      _smsChannelId,
      _smsChannelName,
      channelDescription: 'Auto-detected transaction notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(0, 'Ledger — Auto-detect failed', reason, details);
  }

  static Future<void> showTransactionDetectedNotification({
    required int id,
    required String title,
    required String body,
    required String transactionId,
  }) async {
    if (!notificationsEnabled) return;
    const androidDetails = AndroidNotificationDetails(
      _smsChannelId,
      _smsChannelName,
      channelDescription: 'Auto-detected transaction notification',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Transaction detected',
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(id, title, body, details, payload: transactionId);
  }

  // ── Manual transaction notifications ──────────────────────────────────────

  static Future<void> showTransactionSavedNotification(
      String title, double amount, String currency, bool isIncome) async {
    final formatted = CurrencyFormatter.format(amount, currency: currency);
    final typeLabel = isIncome ? 'income' : 'expense';
    const androidDetails = AndroidNotificationDetails(
      _txChannelId,
      _txChannelName,
      channelDescription: 'Transaction update notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      1,
      'Transaction saved',
      '$formatted $typeLabel · $title',
      const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showTransactionUpdatedNotification(
      String title, double amount, String currency, bool isIncome) async {
    final formatted = CurrencyFormatter.format(amount, currency: currency);
    final typeLabel = isIncome ? 'income' : 'expense';
    const androidDetails = AndroidNotificationDetails(
      _txChannelId,
      _txChannelName,
      channelDescription: 'Transaction update notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      1,
      'Transaction updated',
      '$formatted $typeLabel · $title',
      const NotificationDetails(android: androidDetails),
    );
  }

  static Future<void> showTransactionDeletedNotification(String title) async {
    const androidDetails = AndroidNotificationDetails(
      _txChannelId,
      _txChannelName,
      channelDescription: 'Transaction update notification',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
    await _plugin.show(
      1,
      'Transaction deleted',
      title,
      const NotificationDetails(android: androidDetails),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String buildNotificationTitle(
      String merchantName, double amount, String currency) {
    final formatted = CurrencyFormatter.format(amount, currency: currency);
    return '$formatted added · $merchantName';
  }
}
