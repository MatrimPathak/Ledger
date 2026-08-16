import 'package:cloud_firestore/cloud_firestore.dart';

/// Distinguishes what kind of recurring pattern was detected — recurring
/// alone isn't enough to call something a subscription (rent, salary, and
/// electricity are all recurring but none of them are subscriptions).
enum SubscriptionKind {
  subscription,
  recurringBill,
  recurringIncome,
  recurringTransfer,
}

extension SubscriptionKindExt on SubscriptionKind {
  static SubscriptionKind? fromString(String? value) {
    if (value == null) return null;
    for (final kind in SubscriptionKind.values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

enum SubscriptionStatus { active, paused, cancelled }

extension SubscriptionStatusExt on SubscriptionStatus {
  static SubscriptionStatus fromString(String? value) {
    if (value == null) return SubscriptionStatus.active;
    for (final status in SubscriptionStatus.values) {
      if (status.name == value) return status;
    }
    return SubscriptionStatus.active;
  }
}

enum SubscriptionDetectionSource { auto, userConfirmed }

extension SubscriptionDetectionSourceExt on SubscriptionDetectionSource {
  static SubscriptionDetectionSource fromString(String? value) {
    if (value == null) return SubscriptionDetectionSource.auto;
    for (final source in SubscriptionDetectionSource.values) {
      if (source.name == value) return source;
    }
    return SubscriptionDetectionSource.auto;
  }
}

/// A detected recurring pattern — merchant/amount/interval regularity in
/// the user's own transaction history. Detection is purely local
/// (subscriptions_provider.dart derives this from transactions already in
/// memory); no AI call is involved in finding the pattern itself.
class Subscription {
  final String id;
  final String userId;
  final String? merchantId;
  final String? merchantNameRaw;
  final SubscriptionKind kind;
  final double expectedAmount;
  final double amountTolerancePercent;
  final int intervalDays;
  final DateTime lastSeenDate;
  final DateTime nextExpectedDate;
  final List<String> matchedTransactionIds;
  final SubscriptionStatus status;
  final SubscriptionDetectionSource detectionSource;
  final DateTime createdAt;

  static const int maxMatchedTransactionIds = 12;

  const Subscription({
    required this.id,
    required this.userId,
    this.merchantId,
    this.merchantNameRaw,
    required this.kind,
    required this.expectedAmount,
    this.amountTolerancePercent = 0.05,
    required this.intervalDays,
    required this.lastSeenDate,
    required this.nextExpectedDate,
    this.matchedTransactionIds = const [],
    this.status = SubscriptionStatus.active,
    this.detectionSource = SubscriptionDetectionSource.auto,
    required this.createdAt,
  });

  factory Subscription.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Subscription(
      id: doc.id,
      userId: data['userId'] ?? '',
      merchantId: data['merchantId'],
      merchantNameRaw: data['merchantNameRaw'],
      kind: SubscriptionKindExt.fromString(data['kind'] as String?) ??
          SubscriptionKind.recurringBill,
      expectedAmount: (data['expectedAmount'] as num?)?.toDouble() ?? 0,
      amountTolerancePercent:
          (data['amountTolerancePercent'] as num?)?.toDouble() ?? 0.05,
      intervalDays: (data['intervalDays'] as num?)?.toInt() ?? 30,
      lastSeenDate:
          (data['lastSeenDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      nextExpectedDate:
          (data['nextExpectedDate'] as Timestamp?)?.toDate() ?? DateTime.now(),
      matchedTransactionIds: (data['matchedTransactionIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      status: SubscriptionStatusExt.fromString(data['status'] as String?),
      detectionSource: SubscriptionDetectionSourceExt.fromString(
          data['detectionSource'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'merchantId': merchantId,
        'merchantNameRaw': merchantNameRaw,
        'kind': kind.name,
        'expectedAmount': expectedAmount,
        'amountTolerancePercent': amountTolerancePercent,
        'intervalDays': intervalDays,
        'lastSeenDate': Timestamp.fromDate(lastSeenDate),
        'nextExpectedDate': Timestamp.fromDate(nextExpectedDate),
        'matchedTransactionIds': matchedTransactionIds,
        'status': status.name,
        'detectionSource': detectionSource.name,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  String get displayName => merchantNameRaw ?? 'Unknown';

  Subscription copyWith({
    SubscriptionKind? kind,
    double? expectedAmount,
    int? intervalDays,
    DateTime? lastSeenDate,
    DateTime? nextExpectedDate,
    List<String>? matchedTransactionIds,
    SubscriptionStatus? status,
  }) =>
      Subscription(
        id: id,
        userId: userId,
        merchantId: merchantId,
        merchantNameRaw: merchantNameRaw,
        kind: kind ?? this.kind,
        expectedAmount: expectedAmount ?? this.expectedAmount,
        amountTolerancePercent: amountTolerancePercent,
        intervalDays: intervalDays ?? this.intervalDays,
        lastSeenDate: lastSeenDate ?? this.lastSeenDate,
        nextExpectedDate: nextExpectedDate ?? this.nextExpectedDate,
        matchedTransactionIds:
            matchedTransactionIds ?? this.matchedTransactionIds,
        status: status ?? this.status,
        detectionSource: detectionSource,
        createdAt: createdAt,
      );
}
