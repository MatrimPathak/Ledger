import 'package:cloud_firestore/cloud_firestore.dart';
import 'payment_mode.dart';

enum TransactionType { expense, income }

enum TransactionSource { manual, sms }

/// Accounting-level classification, orthogonal to [TransactionType].
///
/// [TransactionType] keeps driving whether a transaction adds to or
/// subtracts from whatever balance it touches (unchanged, existing
/// semantics). [TxnCategory] is the finer-grained taxonomy analytics and
/// credit-card accounting use to decide what counts as real spend versus a
/// transfer/settlement — e.g. a [creditCardPayment] is a [TransactionType]
/// expense from the paying bank account's point of view, but must not be
/// counted as spend.
enum TxnCategory {
  expense,
  income,
  transfer,
  creditCardPurchase,
  creditCardPayment,
  refund,
  adjustment,
}

extension TxnCategoryExt on TxnCategory {
  static TxnCategory? fromString(String? value) {
    if (value == null) return null;
    for (final category in TxnCategory.values) {
      if (category.name == value) return category;
    }
    return null;
  }

  /// Backward-compat default for documents written before this field
  /// existed: fall back to the coarse legacy [TransactionType].
  static TxnCategory fromLegacyType(TransactionType type) =>
      type == TransactionType.income ? TxnCategory.income : TxnCategory.expense;
}

/// Detected payment method, distinct from [Transaction.paymentModeId] (the
/// user's configured instrument). Used for analytics/dedup independent of
/// whether a specific [PaymentMode] doc was resolved.
enum TxnPaymentMethod {
  upi,
  bankTransfer,
  debitCard,
  creditCard,
  cash,
  atm,
  wallet,
}

extension TxnPaymentMethodExt on TxnPaymentMethod {
  static TxnPaymentMethod? fromString(String? value) {
    if (value == null) return null;
    for (final method in TxnPaymentMethod.values) {
      if (method.name == value) return method;
    }
    return null;
  }

  static TxnPaymentMethod fromPaymentModeType(PaymentModeType type) {
    switch (type) {
      case PaymentModeType.upi:
        return TxnPaymentMethod.upi;
      case PaymentModeType.creditCard:
        return TxnPaymentMethod.creditCard;
      case PaymentModeType.debitCard:
        return TxnPaymentMethod.debitCard;
      case PaymentModeType.bankTransfer:
        return TxnPaymentMethod.bankTransfer;
      case PaymentModeType.atm:
        return TxnPaymentMethod.atm;
      case PaymentModeType.cash:
        return TxnPaymentMethod.cash;
    }
  }
}

/// Drives the offline-first "always create locally" flow: a transaction is
/// created immediately in [local] status and moves forward as local parsing
/// and/or AI enrichment resolve it, rather than being silently dropped.
enum TxnProcessingStatus {
  local,
  needsAiReview,
  aiProcessed,
  confirmed,
  rejected,
}

extension TxnProcessingStatusExt on TxnProcessingStatus {
  static TxnProcessingStatus fromString(String? value) {
    if (value == null) return TxnProcessingStatus.confirmed;
    for (final status in TxnProcessingStatus.values) {
      if (status.name == value) return status;
    }
    return TxnProcessingStatus.confirmed;
  }
}

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

  /// Verbatim counterparty from SMS/notification (e.g. a UPI display name
  /// like "Rajesh Kumar"). Set once at creation, never overwritten — the
  /// inferred [merchantId] is a separate, always-correctable field so the
  /// original payee is never lost.
  final String? payeeRaw;

  /// FK into the `merchants` collection — the inferred normalized merchant
  /// (e.g. "Uber"). Always user-overridable.
  final String? merchantId;

  /// 0.0-1.0 confidence of the merchant inference at the time it was set.
  /// UI-only signal (e.g. to show a "suggested — confirm?" chip).
  final double? merchantConfidence;

  final TxnCategory txnCategory;

  /// Detected payment method; null means "not yet determined" (falls back
  /// to deriving it from the linked [PaymentMode] via
  /// [resolvePaymentMethod], not persisted retroactively).
  final TxnPaymentMethod? paymentMethod;

  /// Stable device-local SMS/notification id — identity anchor for
  /// dedup/audit.
  final String? sourceMessageId;

  /// SHA-256 of the normalized source message body — content-based dedup
  /// independent of message id (handles resends with different metadata).
  final String? sourceMessageHash;

  /// Bank/UPI reference number (UTR/RRN) — the strongest dedup/audit signal
  /// when present.
  final String? externalTransactionId;

  /// Bank-reported transaction time, kept alongside (not replacing) [date]
  /// since [date] already drives existing query ranges.
  final DateTime? transactionAt;

  final TxnProcessingStatus processingStatus;

  /// Stored (not discard-only like the pre-refactor pipeline), so a
  /// low-confidence AI result becomes a reviewable transaction instead of
  /// silently vanishing.
  final double? aiConfidence;

  /// Which model produced the AI-assisted fields, for audit.
  final String? aiModel;

  /// FK into `creditCardAccounts` when [paymentMethod] is
  /// [TxnPaymentMethod.creditCard].
  final String? creditCardAccountId;

  /// Pairs the two legs of a transfer/credit-card-payment so UI/analytics
  /// never double-count.
  final String? linkedTransferTransactionId;

  Transaction({
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
    this.payeeRaw,
    this.merchantId,
    this.merchantConfidence,
    TxnCategory? txnCategory,
    this.paymentMethod,
    this.sourceMessageId,
    this.sourceMessageHash,
    this.externalTransactionId,
    this.transactionAt,
    this.processingStatus = TxnProcessingStatus.confirmed,
    this.aiConfidence,
    this.aiModel,
    this.creditCardAccountId,
    this.linkedTransferTransactionId,
  }) : txnCategory = txnCategory ?? _defaultTxnCategory(type);

  static TxnCategory _defaultTxnCategory(TransactionType type) =>
      TxnCategoryExt.fromLegacyType(type);

  factory Transaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] == 'income'
        ? TransactionType.income
        : TransactionType.expense;
    return Transaction(
      id: doc.id,
      userId: data['userId'] ?? '',
      title: data['title'] ?? '',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      type: type,
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
      payeeRaw: data['payeeRaw'],
      merchantId: data['merchantId'],
      merchantConfidence: (data['merchantConfidence'] as num?)?.toDouble(),
      txnCategory:
          TxnCategoryExt.fromString(data['txnCategory'] as String?) ??
              TxnCategoryExt.fromLegacyType(type),
      paymentMethod:
          TxnPaymentMethodExt.fromString(data['paymentMethod'] as String?),
      sourceMessageId: data['sourceMessageId'],
      sourceMessageHash: data['sourceMessageHash'],
      externalTransactionId: data['externalTransactionId'],
      transactionAt: (data['transactionAt'] as Timestamp?)?.toDate(),
      processingStatus:
          TxnProcessingStatusExt.fromString(data['processingStatus'] as String?),
      aiConfidence: (data['aiConfidence'] as num?)?.toDouble(),
      aiModel: data['aiModel'],
      creditCardAccountId: data['creditCardAccountId'],
      linkedTransferTransactionId: data['linkedTransferTransactionId'],
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
        'payeeRaw': payeeRaw,
        'merchantId': merchantId,
        'merchantConfidence': merchantConfidence,
        'txnCategory': txnCategory.name,
        'paymentMethod': paymentMethod?.name,
        'sourceMessageId': sourceMessageId,
        'sourceMessageHash': sourceMessageHash,
        'externalTransactionId': externalTransactionId,
        'transactionAt':
            transactionAt != null ? Timestamp.fromDate(transactionAt!) : null,
        'processingStatus': processingStatus.name,
        'aiConfidence': aiConfidence,
        'aiModel': aiModel,
        'creditCardAccountId': creditCardAccountId,
        'linkedTransferTransactionId': linkedTransferTransactionId,
      };

  /// Resolves the effective payment method for display/analytics: the
  /// explicitly detected [paymentMethod] if present, else derived from the
  /// linked [mode]'s type (not persisted retroactively — callers pass in
  /// whatever [PaymentMode] they already have resolved for this
  /// transaction's [paymentModeId]).
  TxnPaymentMethod? resolvePaymentMethod(PaymentMode? mode) {
    if (paymentMethod != null) return paymentMethod;
    if (mode == null) return null;
    return TxnPaymentMethodExt.fromPaymentModeType(mode.type);
  }

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
    String? Function()? payeeRaw,
    String? Function()? merchantId,
    double? Function()? merchantConfidence,
    TxnCategory? txnCategory,
    TxnPaymentMethod? Function()? paymentMethod,
    String? Function()? sourceMessageId,
    String? Function()? sourceMessageHash,
    String? Function()? externalTransactionId,
    DateTime? Function()? transactionAt,
    TxnProcessingStatus? processingStatus,
    double? Function()? aiConfidence,
    String? Function()? aiModel,
    String? Function()? creditCardAccountId,
    String? Function()? linkedTransferTransactionId,
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
        payeeRaw: payeeRaw != null ? payeeRaw() : this.payeeRaw,
        merchantId: merchantId != null ? merchantId() : this.merchantId,
        merchantConfidence: merchantConfidence != null
            ? merchantConfidence()
            : this.merchantConfidence,
        txnCategory: txnCategory ?? this.txnCategory,
        paymentMethod:
            paymentMethod != null ? paymentMethod() : this.paymentMethod,
        sourceMessageId:
            sourceMessageId != null ? sourceMessageId() : this.sourceMessageId,
        sourceMessageHash: sourceMessageHash != null
            ? sourceMessageHash()
            : this.sourceMessageHash,
        externalTransactionId: externalTransactionId != null
            ? externalTransactionId()
            : this.externalTransactionId,
        transactionAt:
            transactionAt != null ? transactionAt() : this.transactionAt,
        processingStatus: processingStatus ?? this.processingStatus,
        aiConfidence: aiConfidence != null ? aiConfidence() : this.aiConfidence,
        aiModel: aiModel != null ? aiModel() : this.aiModel,
        creditCardAccountId: creditCardAccountId != null
            ? creditCardAccountId()
            : this.creditCardAccountId,
        linkedTransferTransactionId: linkedTransferTransactionId != null
            ? linkedTransferTransactionId()
            : this.linkedTransferTransactionId,
      );
}
