import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../../models/account.dart';
import '../../models/payment_mode.dart';

/// Result of running the declarative rule set (assets/sms_patterns/
/// bank_patterns.json) against a single SMS body. Never throws — an SMS
/// that matches nothing still yields a result with a low/zero confidence
/// rather than null, so the caller always has a uniform decision point.
class LocalParseResult {
  final double? amount;
  final String? direction; // 'debit' | 'credit'
  final String? paymentMethod; // TxnPaymentMethod.name or null
  final String? txnCategoryHint; // TxnCategory.name or null (derive from direction if null)
  final String? referenceNumber;
  final String? merchantCandidate;
  final String? accountLastDigits;
  final String? matchedAccountId;
  final String? matchedPaymentModeId;
  final String matchedRuleId; // rule id, or 'none'
  final double confidence; // 0.0-1.0, see LocalSmsParser's rubric doc comment

  const LocalParseResult({
    this.amount,
    this.direction,
    this.paymentMethod,
    this.txnCategoryHint,
    this.referenceNumber,
    this.merchantCandidate,
    this.accountLastDigits,
    this.matchedAccountId,
    this.matchedPaymentModeId,
    required this.matchedRuleId,
    required this.confidence,
  });

  /// Three-tier routing per the local-parser confidence rubric:
  /// >= 0.80 accept locally with no AI call, [0.40, 0.80) send a minimized
  /// partial-field AI request, < 0.40 fall back to a full-SMS AI request.
  bool get isHighConfidence => confidence >= 0.80;
  bool get isMediumConfidence => confidence >= 0.40 && confidence < 0.80;
  bool get isLowConfidence => confidence < 0.40;
}

/// Interprets the shared declarative bank-SMS pattern rules
/// (assets/sms_patterns/bank_patterns.json). The Kotlin counterpart
/// (android/app/src/main/kotlin/com/matrimpathak/ledger/LocalSmsParser.kt)
/// reads the same JSON and mirrors this scoring rubric field-for-field;
/// test/fixtures/sms_samples.json is asserted against by both languages'
/// test suites so the two interpreters can't silently drift apart.
///
/// Confidence rubric (points out of 100, normalized to 0.0-1.0):
///  - Amount extracted and numeric:                          +30
///  - Debit/credit direction unambiguous:                    +20
///  - Reference number (UTR/RRN/UPI ref) present:             +15
///  - Account/card last digits present AND match a known
///    Account or PaymentMode:                                +20
///  - Payment method unambiguous from keywords:               +10
///  - Merchant/payee candidate text extracted:                +5
class LocalSmsParser {
  LocalSmsParser._(this._rules) {
    _amountRegex = RegExp(_rules['amountRegex'] as String, caseSensitive: false);
    final lastDigitsPattern = _rules['accountLastDigitsRegex'] as String?;
    _accountLastDigitsRegex = lastDigitsPattern != null
        ? RegExp(lastDigitsPattern, caseSensitive: false)
        : null;
  }

  final Map<String, dynamic> _rules;
  late final RegExp _amountRegex;
  late final RegExp? _accountLastDigitsRegex;

  static LocalSmsParser? _cached;

  /// Loads the shared rule set from the Flutter asset bundle, caching the
  /// parsed result for the process lifetime (the JSON never changes at
  /// runtime).
  static Future<LocalSmsParser> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final raw =
        await rootBundle.loadString('assets/sms_patterns/bank_patterns.json');
    final parser = LocalSmsParser.fromJson(
        jsonDecode(raw) as Map<String, dynamic>);
    _cached = parser;
    return parser;
  }

  /// Builds a parser directly from an already-decoded rule set — used by
  /// tests (via test/fixtures/sms_samples.json's companion rule file) to
  /// avoid needing the Flutter asset bundle.
  factory LocalSmsParser.fromJson(Map<String, dynamic> rules) =>
      LocalSmsParser._(rules);

  LocalParseResult parse(
    String body, {
    List<Account> accounts = const [],
    List<PaymentMode> paymentModes = const [],
  }) {
    final lower = body.toLowerCase();
    final rules = (_rules['rules'] as List).cast<Map<String, dynamic>>();

    Map<String, dynamic>? matchedRule;
    for (final rule in rules) {
      if (_ruleMatches(rule, lower)) {
        matchedRule = rule;
        break;
      }
    }

    final amount = _extractAmount(body);
    final refNumber = matchedRule != null
        ? _extractGroup(body, matchedRule['refNumberRegex'] as String?)
        : null;
    final merchant = matchedRule != null
        ? _extractGroup(body, matchedRule['merchantRegex'] as String?)
        : null;
    final lastDigitsRegex = _accountLastDigitsRegex;
    final lastDigits =
        lastDigitsRegex != null ? _firstMatchGroup(body, lastDigitsRegex) : null;

    String? direction = matchedRule?['direction'] as String?;
    direction ??= _inferDirectionFromKeywords(lower);

    final paymentMethod = matchedRule?['paymentMethod'] as String?;
    final txnCategoryHint = matchedRule?['txnCategoryHint'] as String?;

    String? matchedAccountId;
    String? matchedPaymentModeId;
    var lastDigitsMatchedKnownInstrument = false;
    if (lastDigits != null) {
      for (final account in accounts) {
        if (_digitsSuffixMatch(lastDigits, account.lastSixDigits)) {
          matchedAccountId = account.id;
          lastDigitsMatchedKnownInstrument = true;
          break;
        }
      }
      for (final mode in paymentModes) {
        final modeDigits = mode.lastFourDigits;
        if (modeDigits != null && _digitsSuffixMatch(lastDigits, modeDigits)) {
          matchedPaymentModeId = mode.id;
          lastDigitsMatchedKnownInstrument = true;
          break;
        }
      }
    }

    final confidence = _score(
      hasAmount: amount != null,
      hasDirection: direction != null,
      hasRefNumber: refNumber != null && refNumber.isNotEmpty,
      hasKnownInstrumentMatch: lastDigitsMatchedKnownInstrument,
      hasPaymentMethod: paymentMethod != null,
      hasMerchant: merchant != null && merchant.isNotEmpty,
    );

    return LocalParseResult(
      amount: amount,
      direction: direction,
      paymentMethod: paymentMethod,
      txnCategoryHint: txnCategoryHint,
      referenceNumber: refNumber,
      merchantCandidate: merchant,
      accountLastDigits: lastDigits,
      matchedAccountId: matchedAccountId,
      matchedPaymentModeId: matchedPaymentModeId,
      matchedRuleId: matchedRule?['id'] as String? ?? 'none',
      confidence: confidence,
    );
  }

  bool _ruleMatches(Map<String, dynamic> rule, String lower) {
    final keywords = (rule['keywords'] as List?)?.cast<String>() ?? const [];
    final requireKeywords =
        (rule['requireKeywords'] as List?)?.cast<String>() ?? const [];
    final excludeKeywords =
        (rule['excludeKeywords'] as List?)?.cast<String>() ?? const [];

    if (keywords.isEmpty || !keywords.any(lower.contains)) return false;
    if (requireKeywords.isNotEmpty && !requireKeywords.any(lower.contains)) {
      return false;
    }
    if (excludeKeywords.any(lower.contains)) return false;
    return true;
  }

  double? _extractAmount(String body) {
    final match = _amountRegex.firstMatch(body);
    if (match == null) return null;
    final raw = match.group(1)?.replaceAll(',', '');
    if (raw == null) return null;
    return double.tryParse(raw);
  }

  String? _extractGroup(String body, String? pattern) {
    if (pattern == null) return null;
    final regex = RegExp(pattern, caseSensitive: false);
    final match = regex.firstMatch(body);
    final group = match?.group(1)?.trim();
    return (group == null || group.isEmpty) ? null : group;
  }

  String? _firstMatchGroup(String body, RegExp regex) {
    final match = regex.firstMatch(body);
    return match?.group(1)?.trim();
  }

  String? _inferDirectionFromKeywords(String lower) {
    final debited = lower.contains('debited');
    final credited = lower.contains('credited');
    if (debited && !credited) return 'debit';
    if (credited && !debited) return 'credit';
    return null;
  }

  /// True when [extractedDigits] (last 4-6 digits from the SMS) matches the
  /// trailing digits of [knownDigits] (or vice versa, since the SMS and the
  /// stored account/payment-mode may record a different number of digits).
  bool _digitsSuffixMatch(String extractedDigits, String knownDigits) {
    if (extractedDigits.isEmpty || knownDigits.isEmpty) return false;
    final shorter = extractedDigits.length <= knownDigits.length
        ? extractedDigits
        : knownDigits;
    final longer = extractedDigits.length <= knownDigits.length
        ? knownDigits
        : extractedDigits;
    return longer.endsWith(shorter);
  }

  double _score({
    required bool hasAmount,
    required bool hasDirection,
    required bool hasRefNumber,
    required bool hasKnownInstrumentMatch,
    required bool hasPaymentMethod,
    required bool hasMerchant,
  }) {
    var points = 0;
    if (hasAmount) points += 30;
    if (hasDirection) points += 20;
    if (hasRefNumber) points += 15;
    if (hasKnownInstrumentMatch) points += 20;
    if (hasPaymentMethod) points += 10;
    if (hasMerchant) points += 5;
    return points / 100.0;
  }
}
