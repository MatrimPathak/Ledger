import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { expense, income }

enum TransactionSource { manual, sms }

class Transaction {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final TransactionType type;
  final DateTime date;
  final String categoryId;
  final String accountId;
  final String? paymentModeId;
  final String? notes;
  final TransactionSource source;
  final String? rawSms;
  final DateTime createdAt;
  final bool affectsBalance;

  const Transaction({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    required this.categoryId,
    required this.accountId,
    this.paymentModeId,
    this.notes,
    this.source = TransactionSource.manual,
    this.rawSms,
    required this.createdAt,
    this.affectsBalance = true,
  });

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Transaction(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      type: data['type'] == 'income'
          ? TransactionType.income
          : TransactionType.expense,
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      categoryId: data['categoryId'] ?? '',
      accountId: data['accountId'] ?? '',
      paymentModeId: data['paymentModeId'],
      notes: data['notes'],
      source: data['source'] == 'sms'
          ? TransactionSource.sms
          : TransactionSource.manual,
      rawSms: data['rawSms'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      affectsBalance: data['affectsBalance'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'userId': userId,
        'title': title,
        'amount': amount,
        'type': type.name,
        'date': Timestamp.fromDate(date),
        'categoryId': categoryId,
        'accountId': accountId,
        'paymentModeId': paymentModeId,
        'notes': notes,
        'source': source.name,
        'rawSms': rawSms,
        'createdAt': Timestamp.fromDate(createdAt),
        'affectsBalance': affectsBalance,
      };

  Transaction copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    DateTime? date,
    String? categoryId,
    String? accountId,
    String? paymentModeId,
    String? notes,
    bool clearPaymentModeId = false,
    bool clearNotes = false,
    bool? affectsBalance,
  }) =>
      Transaction(
        id: id ?? this.id,
        userId: userId,
        title: title ?? this.title,
        amount: amount ?? this.amount,
        type: type ?? this.type,
        date: date ?? this.date,
        categoryId: categoryId ?? this.categoryId,
        accountId: accountId ?? this.accountId,
        paymentModeId:
            clearPaymentModeId ? null : (paymentModeId ?? this.paymentModeId),
        notes: clearNotes ? null : (notes ?? this.notes),
        source: source,
        rawSms: rawSms,
        createdAt: createdAt,
        affectsBalance: affectsBalance ?? this.affectsBalance,
      );
}
