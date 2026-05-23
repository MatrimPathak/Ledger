import 'package:cloud_firestore/cloud_firestore.dart';

class Account {
  final String id;
  final String userId;
  final String title;
  final String bankName;
  final String lastSixDigits;
  final double balance;
  final String holderName;
  final String currency;
  final DateTime createdAt;

  const Account({
    required this.id,
    required this.userId,
    required this.title,
    required this.bankName,
    required this.lastSixDigits,
    required this.balance,
    required this.holderName,
    this.currency = 'INR',
    required this.createdAt,
  });

  factory Account.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Account(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      bankName: data['bankName'] ?? '',
      lastSixDigits: data['lastSixDigits'] ?? '',
      balance: (data['balance'] as num?)?.toDouble() ?? 0.0,
      holderName: data['holderName'] ?? '',
      currency: data['currency'] ?? 'INR',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'bankName': bankName,
        'lastSixDigits': lastSixDigits,
        'balance': balance,
        'holderName': holderName,
        'currency': currency,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  Account copyWith({
    String? title,
    String? bankName,
    String? lastSixDigits,
    double? balance,
    String? holderName,
    String? currency,
  }) =>
      Account(
        id: id,
        userId: userId,
        title: title ?? this.title,
        bankName: bankName ?? this.bankName,
        lastSixDigits: lastSixDigits ?? this.lastSixDigits,
        balance: balance ?? this.balance,
        holderName: holderName ?? this.holderName,
        currency: currency ?? this.currency,
        createdAt: createdAt,
      );
}
