import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentModeType {
  upi,
  creditCard,
  debitCard,
  bankTransfer,
  atm,
  cash,
}

extension PaymentModeTypeExt on PaymentModeType {
  String get label {
    switch (this) {
      case PaymentModeType.upi:
        return 'UPI';
      case PaymentModeType.creditCard:
        return 'Credit Card';
      case PaymentModeType.debitCard:
        return 'Debit Card';
      case PaymentModeType.bankTransfer:
        return 'Bank Transfer';
      case PaymentModeType.atm:
        return 'ATM';
      case PaymentModeType.cash:
        return 'Cash';
    }
  }

  String get iconName {
    switch (this) {
      case PaymentModeType.upi:
        return 'upi';
      case PaymentModeType.creditCard:
        return 'credit_card';
      case PaymentModeType.debitCard:
        return 'debit_card';
      case PaymentModeType.bankTransfer:
        return 'bank_transfer';
      case PaymentModeType.atm:
        return 'atm';
      case PaymentModeType.cash:
        return 'cash';
    }
  }

  static PaymentModeType fromString(String value) {
    return PaymentModeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentModeType.cash,
    );
  }
}

class PaymentMode {
  final String id;
  final String userId;
  final PaymentModeType type;
  final String? accountId;
  final String title;
  final String? lastFourDigits;
  final String? upiId;
  final DateTime createdAt;

  const PaymentMode({
    required this.id,
    required this.userId,
    required this.type,
    this.accountId,
    required this.title,
    this.lastFourDigits,
    this.upiId,
    required this.createdAt,
  });

  factory PaymentMode.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PaymentMode(
      id: doc.id,
      userId: data['userId'] ?? '',
      type: PaymentModeTypeExt.fromString(data['type'] ?? 'cash'),
      accountId: data['accountId'],
      title: data['title'] ?? '',
      lastFourDigits: data['lastFourDigits'],
      upiId: data['upiId'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'type': type.name,
        'accountId': accountId,
        'title': title,
        'lastFourDigits': lastFourDigits,
        'upiId': upiId,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  PaymentMode copyWith({
    PaymentModeType? type,
    String? accountId,
    String? title,
    String? lastFourDigits,
    String? upiId,
  }) =>
      PaymentMode(
        id: id,
        userId: userId,
        type: type ?? this.type,
        accountId: accountId ?? this.accountId,
        title: title ?? this.title,
        lastFourDigits: lastFourDigits ?? this.lastFourDigits,
        upiId: upiId ?? this.upiId,
        createdAt: createdAt,
      );
}
