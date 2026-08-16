import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/merchant.dart';
import '../models/subscription.dart';
import '../models/transaction.dart';
import 'auth_provider.dart';
import 'transactions_provider.dart';

/// Small, static, non-user-editable allowlist of merchant-name substrings
/// known to be subscription-type services. Seeded once for this release —
/// broadening subscription detection to any recurring UPI merchant (rather
/// than requiring a mandate/autopay signal too) would risk misclassifying
/// something like a recurring grocery order as a subscription.
const List<String> knownSubscriptionMerchants = [
  'netflix',
  'spotify',
  'amazon prime',
  'prime video',
  'youtube premium',
  'youtube music',
  'hotstar',
  'disney',
  'jiocinema',
  'apple music',
  'apple tv',
  'icloud',
  'google one',
  'google play',
  'sonyliv',
  'zee5',
  'audible',
  'notion',
  'chatgpt',
  'openai',
  'linkedin premium',
];

const List<String> _mandateKeywords = [
  'mandate',
  'e-mandate',
  'emandate',
  'autopay',
  'auto-pay',
  'auto pay',
  'umn',
  'nach',
];

/// Interval buckets (days) recurring charges are expected to cluster
/// around — weekly, fortnightly, monthly, yearly. Gaps are matched within
/// ±[_intervalToleranceDays] of a bucket; the buckets are far enough apart
/// that a real gap can only ever land in one of them.
const List<int> _intervalBuckets = [7, 14, 30, 365];
const int _intervalToleranceDays = 3;
const double _defaultAmountTolerancePercent = 0.05;
const int _minOccurrences = 3;

/// Categories that represent a real recurring merchant/counterparty charge
/// or income. `creditCardPayment`, `refund`, and `adjustment` are excluded:
/// they're settlements/reversals, not a merchant relationship that repeats.
const Set<TxnCategory> _eligibleCategories = {
  TxnCategory.expense,
  TxnCategory.income,
  TxnCategory.transfer,
  TxnCategory.creditCardPurchase,
};

class _RecurringMatch {
  _RecurringMatch(this.occurrences, this.intervalDays);
  final List<Transaction> occurrences;
  final int intervalDays;
}

/// Pure, purely-local detection of recurring transaction patterns —
/// subscription, recurring bill, recurring income, recurring transfer.
/// No AI call is involved: this only ever looks at transactions already in
/// memory. Exposed as a top-level function (rather than buried in the
/// provider) so it's both directly unit-testable and reusable from
/// `analytics_provider.dart`.
List<Subscription> detectSubscriptions(
  String userId,
  List<Transaction> transactions,
) {
  final eligible = transactions.where((t) =>
      _eligibleCategories.contains(t.txnCategory) &&
      t.processingStatus != TxnProcessingStatus.rejected);

  final groups = <String, List<Transaction>>{};
  for (final txn in eligible) {
    final key = txn.merchantId ?? Merchant.normalize(txn.title);
    if (key.isEmpty) continue;
    groups.putIfAbsent(key, () => []).add(txn);
  }

  final results = <Subscription>[];
  for (final entry in groups.entries) {
    final sorted = [...entry.value]..sort((a, b) => a.date.compareTo(b.date));
    final match = _findBestRecurringRun(sorted);
    if (match == null) continue;

    final run = match.occurrences;
    final amounts = run.map((t) => t.amount).toList();
    final expectedAmount = amounts.reduce((a, b) => a + b) / amounts.length;
    final last = run.last;
    final matchedIds = run.length > Subscription.maxMatchedTransactionIds
        ? run
            .sublist(run.length - Subscription.maxMatchedTransactionIds)
            .map((t) => t.id)
            .toList()
        : run.map((t) => t.id).toList();

    results.add(Subscription(
      id: 'auto:${entry.key}',
      userId: userId,
      merchantId: last.merchantId,
      merchantNameRaw: last.title,
      kind: _classifyKind(run),
      expectedAmount: expectedAmount,
      amountTolerancePercent: _defaultAmountTolerancePercent,
      intervalDays: match.intervalDays,
      lastSeenDate: last.date,
      nextExpectedDate: last.date.add(Duration(days: match.intervalDays)),
      matchedTransactionIds: matchedIds,
      status: SubscriptionStatus.active,
      detectionSource: SubscriptionDetectionSource.auto,
      createdAt: last.date,
    ));
  }
  return results;
}

/// Finds the longest contiguous run (by date) of >= [_minOccurrences]
/// transactions whose consecutive gaps cluster around one interval bucket
/// and whose amounts stay within tolerance of the run's mean. Returns the
/// best (longest) run across all buckets, or null if nothing qualifies.
_RecurringMatch? _findBestRecurringRun(List<Transaction> sorted) {
  if (sorted.length < _minOccurrences) return null;

  _RecurringMatch? best;
  for (final bucket in _intervalBuckets) {
    var runStart = 0;
    for (var i = 1; i <= sorted.length; i++) {
      final brokeInterval = i == sorted.length ||
          (sorted[i].date.difference(sorted[i - 1].date).inDays - bucket)
                  .abs() >
              _intervalToleranceDays;
      if (brokeInterval) {
        final run = sorted.sublist(runStart, i);
        if (run.length >= _minOccurrences &&
            _amountsRegular(run) &&
            (best == null || run.length > best.occurrences.length)) {
          best = _RecurringMatch(run, bucket);
        }
        runStart = i;
      }
    }
  }
  return best;
}

bool _amountsRegular(List<Transaction> run) {
  final amounts = run.map((t) => t.amount).toList();
  final mean = amounts.reduce((a, b) => a + b) / amounts.length;
  if (mean <= 0) return false;
  return amounts
      .every((a) => (a - mean).abs() / mean <= _defaultAmountTolerancePercent);
}

SubscriptionKind _classifyKind(List<Transaction> run) {
  final transferCount =
      run.where((t) => t.txnCategory == TxnCategory.transfer).length;
  if (transferCount > run.length / 2) {
    return SubscriptionKind.recurringTransfer;
  }

  final incomeCount =
      run.where((t) => t.type == TransactionType.income).length;
  if (incomeCount > run.length / 2) {
    return SubscriptionKind.recurringIncome;
  }

  if (_isUpiEligible(run) &&
      (_hasMandateKeyword(run) || _matchesKnownMerchant(run))) {
    return SubscriptionKind.subscription;
  }
  return SubscriptionKind.recurringBill;
}

bool _isUpiEligible(List<Transaction> run) {
  final hasUpi = run.any((t) => t.paymentMethod == TxnPaymentMethod.upi);
  final hasConflict = run.any(
      (t) => t.paymentMethod != null && t.paymentMethod != TxnPaymentMethod.upi);
  return hasUpi && !hasConflict;
}

bool _hasMandateKeyword(List<Transaction> run) {
  return run.any((t) {
    final sms = t.rawSms?.toLowerCase() ?? '';
    return _mandateKeywords.any(sms.contains);
  });
}

bool _matchesKnownMerchant(List<Transaction> run) {
  final title = Merchant.normalize(run.last.title);
  return knownSubscriptionMerchants.any((m) => title.contains(m));
}

/// Derived, client-side subscription detection over all of the user's
/// transactions. Recomputed whenever [allTransactionsProvider] changes;
/// nothing here is persisted to Firestore automatically.
final detectedSubscriptionsProvider = Provider<List<Subscription>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return const [];
  final transactions = ref.watch(allTransactionsProvider).value ?? const [];
  return detectSubscriptions(user.uid, transactions);
});
