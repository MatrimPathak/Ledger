import 'package:cloud_firestore/cloud_firestore.dart';

/// Liability accounting for a credit card, linked 1:1 to an existing
/// PaymentMode of type creditCard. Additive/optional: a creditCard
/// PaymentMode can exist with no linked CreditCardAccount (the app behaves
/// exactly as before this feature — purchases just don't touch the bank
/// account balance) until the user sets up the card's details.
class CreditCardAccount {
  final String id;
  final String userId;
  final String paymentModeId;
  final String title;
  final String bankName;
  final String lastFourDigits;
  final double creditLimit;

  /// previousOutstanding + purchases - payments, kept as a running total
  /// via atomic increments (mirrors Account.balance's pattern) so the same
  /// transaction can never be double-counted.
  final double currentOutstanding;

  final int? statementDay;
  final int? dueDay;
  final double minimumDuePercent;
  final String currency;
  final DateTime createdAt;

  /// Set by the reconciliation Cloud Function when a server-side recompute
  /// of currentOutstanding from the transaction ledger disagrees with the
  /// stored value — surfaced in the UI as a "verify balance" prompt rather
  /// than silently auto-corrected.
  final bool needsReconciliation;

  const CreditCardAccount({
    required this.id,
    required this.userId,
    required this.paymentModeId,
    required this.title,
    required this.bankName,
    required this.lastFourDigits,
    this.creditLimit = 0,
    this.currentOutstanding = 0,
    this.statementDay,
    this.dueDay,
    this.minimumDuePercent = 0.05,
    this.currency = 'INR',
    required this.createdAt,
    this.needsReconciliation = false,
  });

  double get availableCredit => creditLimit - currentOutstanding;

  double get minimumDue => currentOutstanding * minimumDuePercent;

  factory CreditCardAccount.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CreditCardAccount(
      id: doc.id,
      userId: data['userId'] ?? '',
      paymentModeId: data['paymentModeId'] ?? '',
      title: data['title'] ?? '',
      bankName: data['bankName'] ?? '',
      lastFourDigits: data['lastFourDigits'] ?? '',
      creditLimit: (data['creditLimit'] as num?)?.toDouble() ?? 0,
      currentOutstanding: (data['currentOutstanding'] as num?)?.toDouble() ?? 0,
      statementDay: (data['statementDay'] as num?)?.toInt(),
      dueDay: (data['dueDay'] as num?)?.toInt(),
      minimumDuePercent: (data['minimumDuePercent'] as num?)?.toDouble() ?? 0.05,
      currency: data['currency'] ?? 'INR',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      needsReconciliation: data['needsReconciliation'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'paymentModeId': paymentModeId,
        'title': title,
        'bankName': bankName,
        'lastFourDigits': lastFourDigits,
        'creditLimit': creditLimit,
        'currentOutstanding': currentOutstanding,
        'statementDay': statementDay,
        'dueDay': dueDay,
        'minimumDuePercent': minimumDuePercent,
        'currency': currency,
        'createdAt': Timestamp.fromDate(createdAt),
        'needsReconciliation': needsReconciliation,
      };

  CreditCardAccount copyWith({
    String? title,
    String? bankName,
    String? lastFourDigits,
    double? creditLimit,
    int? Function()? statementDay,
    int? Function()? dueDay,
    double? minimumDuePercent,
    String? currency,
    bool? needsReconciliation,
  }) =>
      CreditCardAccount(
        id: id,
        userId: userId,
        paymentModeId: paymentModeId,
        title: title ?? this.title,
        bankName: bankName ?? this.bankName,
        lastFourDigits: lastFourDigits ?? this.lastFourDigits,
        creditLimit: creditLimit ?? this.creditLimit,
        currentOutstanding: currentOutstanding,
        statementDay: statementDay != null ? statementDay() : this.statementDay,
        dueDay: dueDay != null ? dueDay() : this.dueDay,
        minimumDuePercent: minimumDuePercent ?? this.minimumDuePercent,
        currency: currency ?? this.currency,
        createdAt: createdAt,
        needsReconciliation: needsReconciliation ?? this.needsReconciliation,
      );
}
