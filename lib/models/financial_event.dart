/// A minimal signal extracted from another app's notification (e.g. a UPI
/// app's "paid to X" alert), used only to correlate against a transaction
/// already created from an SMS. Deliberately thin and never persisted to
/// Firestore or disk — the native listener discards the full notification
/// text immediately after extracting these fields, and this object itself
/// only ever lives in an in-memory, TTL-bounded ring buffer
/// ([NotificationListenerBridge] in
/// `lib/services/notification/notification_listener_bridge.dart`).
class FinancialEvent {
  final String packageName;
  final DateTime postTime;
  final double? amount;

  /// Coarse guess at debit/credit/unknown from keyword matching in native
  /// code — never the full notification text.
  final String? eventTypeGuess;

  const FinancialEvent({
    required this.packageName,
    required this.postTime,
    this.amount,
    this.eventTypeGuess,
  });

  factory FinancialEvent.fromMap(Map<dynamic, dynamic> map) {
    final postTimeMs = (map['postTime'] as num?)?.toInt();
    return FinancialEvent(
      packageName: map['packageName'] as String? ?? '',
      postTime: postTimeMs != null
          ? DateTime.fromMillisecondsSinceEpoch(postTimeMs)
          : DateTime.now(),
      amount: (map['amount'] as num?)?.toDouble(),
      eventTypeGuess: map['eventTypeGuess'] as String?,
    );
  }
}
