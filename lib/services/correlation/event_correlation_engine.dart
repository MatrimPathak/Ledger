import '../../models/financial_event.dart';
import '../../models/merchant.dart';
import '../../models/transaction.dart';

/// Coarse, non-authoritative hints from a notifying app's package name
/// toward a merchant display name. A hint only ever biases the score and
/// suggests a name to show the user — it's never applied automatically,
/// and it never substitutes for the amount/time checks below.
const Map<String, String> _knownPackageHints = {
  'com.ubercab': 'Uber',
  'com.ubercab.eats': 'Uber Eats',
  'in.swiggy.android': 'Swiggy',
  'com.application.zomato': 'Zomato',
  'com.phonepe.app': 'PhonePe',
  'net.one97.paytm': 'Paytm',
  'com.google.android.apps.nbu.paisa.user': 'Google Pay',
  'in.org.npci.upiapp': 'BHIM',
};

/// Pure, stateless scoring of how likely a [FinancialEvent] (a notification
/// from another app) corresponds to a given transaction. No I/O, no
/// persistence — every score is computed fresh per (transaction, event)
/// pair, so a new payee (a different driver, same ride-hailing app) still
/// scores purely on amount + time + payment-method plausibility, never off
/// a remembered payee-to-merchant mapping.
class EventCorrelationEngine {
  const EventCorrelationEngine();

  /// Below this, no suggestion is shown to the user at all.
  static const double suggestionThreshold = 0.6;

  static const int _maxPoints = 100;

  /// Returns a 0.0-1.0 confidence. A hard-reject signal (amount off by
  /// more than 5%, or more than 5 minutes apart) always returns 0.0
  /// regardless of any other signal.
  double scoreCorrelation({
    required Transaction candidateTx,
    required FinancialEvent event,
    Merchant? merchant,
  }) {
    final eventAmount = event.amount;
    if (eventAmount == null || candidateTx.amount <= 0) return 0.0;

    final amountDiff = (candidateTx.amount - eventAmount).abs();
    final relativeDiff = amountDiff / candidateTx.amount;
    if (relativeDiff > 0.05) return 0.0;

    final gap = candidateTx.date.difference(event.postTime).abs();
    if (gap > const Duration(minutes: 5)) return 0.0;

    // A debit notification can't correlate with an income transaction, and
    // a credit notification can't correlate with an expense — amount and
    // timing alone aren't enough to rule out that kind of mismatch. A
    // null/"unknown" guess (the common case — most notifications don't say
    // debit/credit explicitly) is not a conflict and scores normally.
    final guess = event.eventTypeGuess;
    final directionConflict = (guess == 'debit' &&
            candidateTx.type == TransactionType.income) ||
        (guess == 'credit' && candidateTx.type == TransactionType.expense);
    if (directionConflict) return 0.0;

    var points = 0;

    if (relativeDiff <= 0.001) {
      points += 45;
    } else if (relativeDiff <= 0.01) {
      points += 25;
    }

    if (gap <= const Duration(seconds: 30)) {
      points += 30;
    } else if (gap <= const Duration(minutes: 2)) {
      points += 20;
    } else {
      points += 10;
    }

    if (candidateTx.paymentMethod == TxnPaymentMethod.upi) {
      points += 15;
    } else if (candidateTx.paymentMethod != null) {
      points -= 10;
    }

    final hint = merchantHint(event);
    if (hint != null) {
      points += 10;
      if (merchant != null &&
          merchant.aliasPatterns
              .any((a) => a.toLowerCase() == hint.toLowerCase())) {
        points += 5;
      }
    }

    return (points / _maxPoints).clamp(0.0, 1.0);
  }

  /// Best-effort merchant display-name hint from the notifying app's
  /// package name. Coarse only — a suggestion for the user to confirm or
  /// reject, never applied automatically.
  String? merchantHint(FinancialEvent event) =>
      _knownPackageHints[event.packageName];

  /// Picks the single best-scoring event above [suggestionThreshold], or
  /// null if nothing qualifies — callers never see multiple ambiguous
  /// suggestions for one transaction.
  FinancialEvent? bestMatch({
    required Transaction candidateTx,
    required List<FinancialEvent> events,
    Merchant? merchant,
  }) {
    FinancialEvent? best;
    var bestScore = 0.0;
    for (final event in events) {
      final score = scoreCorrelation(
        candidateTx: candidateTx,
        event: event,
        merchant: merchant,
      );
      if (score > bestScore) {
        bestScore = score;
        best = event;
      }
    }
    return bestScore >= suggestionThreshold ? best : null;
  }
}
