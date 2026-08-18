import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/financial_event.dart';
import 'package:ledger/models/merchant.dart';
import 'package:ledger/models/transaction.dart';
import 'package:ledger/services/correlation/event_correlation_engine.dart';

void main() {
  const engine = EventCorrelationEngine();
  final now = DateTime(2026, 6, 1, 12, 0, 0);

  Transaction tx({
    double amount = 250,
    DateTime? date,
    TxnPaymentMethod? paymentMethod,
    TransactionType type = TransactionType.expense,
  }) =>
      Transaction(
        id: 'tx-1',
        userId: 'user-1',
        title: 'UPI Payment',
        amount: amount,
        type: type,
        date: date ?? now,
        categoryId: 'general',
        accountId: 'account-1',
        createdAt: now,
        paymentMethod: paymentMethod,
      );

  FinancialEvent event({
    String packageName = 'com.ubercab',
    double? amount = 250,
    DateTime? postTime,
    String? eventTypeGuess,
  }) =>
      FinancialEvent(
        eventTypeGuess: eventTypeGuess,
        packageName: packageName,
        postTime: postTime ?? now,
        amount: amount,
      );

  group('scoreCorrelation', () {
    test('exact amount, same timestamp, UPI, known package scores high', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(),
      );
      expect(score, greaterThanOrEqualTo(EventCorrelationEngine.suggestionThreshold));
    });

    test('fuzzy amount within 1% still scores below the exact-match tier', () {
      final exact = engine.scoreCorrelation(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: 250),
      );
      final fuzzy = engine.scoreCorrelation(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: 251.5), // 0.6% off
      );
      expect(fuzzy, lessThan(exact));
      expect(fuzzy, greaterThan(0));
    });

    test('amount off by more than 5% hard-rejects regardless of timing', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: 300), // 20% off
      );
      expect(score, 0.0);
    });

    test('more than 5 minutes apart hard-rejects regardless of amount', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(postTime: now.add(const Duration(minutes: 6))),
      );
      expect(score, 0.0);
    });

    test('no amount on the event never matches', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: null),
      );
      expect(score, 0.0);
    });

    test('a conflicting payment method (not UPI) lowers the score', () {
      final upiScore = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(),
      );
      final cashScore = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.cash),
        event: event(),
      );
      expect(cashScore, lessThan(upiScore));
    });

    test('known-merchant alias adds a small bonus over an unmatched merchant',
        () {
      // Use a fuzzy (not exact) amount so the base score isn't already at
      // the 1.0 ceiling — otherwise the +5 alias bonus would be invisible
      // after clamping.
      final merchant = Merchant(
        id: 'm1',
        userId: 'user-1',
        displayName: 'Uber',
        normalizedKey: 'uber',
        aliasPatterns: const ['Uber'],
        createdAt: now,
      );
      final withAlias = engine.scoreCorrelation(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: 251.5),
        merchant: merchant,
      );
      final withoutAlias = engine.scoreCorrelation(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        event: event(amount: 251.5),
      );
      expect(withAlias, greaterThan(withoutAlias));
    });

    test('an unrecognized package still scores on amount/time/method alone',
        () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(packageName: 'com.some.random.app'),
      );
      expect(score, greaterThan(0));
    });

    test('a credit event hard-rejects against an expense transaction', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(type: TransactionType.expense, paymentMethod: TxnPaymentMethod.upi),
        event: event(eventTypeGuess: 'credit'),
      );
      expect(score, 0.0);
    });

    test('a debit event hard-rejects against an income transaction', () {
      final score = engine.scoreCorrelation(
        candidateTx: tx(type: TransactionType.income, paymentMethod: TxnPaymentMethod.upi),
        event: event(eventTypeGuess: 'debit'),
      );
      expect(score, 0.0);
    });

    test('a null/unknown direction guess is not treated as a conflict', () {
      final unknownScore = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(eventTypeGuess: 'unknown'),
      );
      final nullScore = engine.scoreCorrelation(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        event: event(),
      );
      expect(unknownScore, greaterThan(0));
      expect(nullScore, greaterThan(0));
    });
  });

  group('bestMatch', () {
    test('returns null when no notification is buffered at all (graceful no-suggestion)', () {
      final match = engine.bestMatch(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        events: const [],
      );
      expect(match, isNull);
    });

    test('returns null when every candidate scores below the threshold', () {
      final match = engine.bestMatch(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        events: [event(amount: 259)], // 3.6% off — no hard reject, low score
      );
      expect(match, isNull);
    });

    test('with multiple candidates, picks the single highest-scoring one', () {
      final worse = event(
        packageName: 'com.some.random.app',
        amount: 249, // slightly off
      );
      final better = event(amount: 250); // exact + known package
      final match = engine.bestMatch(
        candidateTx: tx(paymentMethod: TxnPaymentMethod.upi),
        events: [worse, better],
      );
      expect(match, same(better));
    });

    test('a different transaction amount/time does not spuriously match', () {
      final unrelatedEvent = event(amount: 4999, postTime: now.add(const Duration(hours: 3)));
      final match = engine.bestMatch(
        candidateTx: tx(amount: 250, paymentMethod: TxnPaymentMethod.upi),
        events: [unrelatedEvent],
      );
      expect(match, isNull);
    });
  });

  group('merchantHint', () {
    test('resolves a known package to a display name', () {
      expect(engine.merchantHint(event(packageName: 'com.ubercab')), 'Uber');
    });

    test('returns null for an unknown package', () {
      expect(engine.merchantHint(event(packageName: 'com.unknown.app')), isNull);
    });
  });
}
