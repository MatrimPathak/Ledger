import 'package:cloud_firestore/cloud_firestore.dart';

/// A learned, generalized bank-SMS shape: the constant (boilerplate) text
/// of a real message with every variable span (amount, reference number,
/// merchant name, etc.) replaced by a `{type}` placeholder drawn from
/// [placeholderPatterns]. Templates are learned once by Claude (see
/// ClaudeService.parseSmsTransaction) from a genuinely novel SMS shape
/// that no static rule in bank_patterns.json matched, then published to
/// the shared `smsTemplates` Firestore collection so every user's local
/// parser can match that shape for free from then on — this is the
/// "self-improving" tier of the parsing pipeline, sitting between the
/// hand-maintained static rules and the full AI fallback.
///
/// Templates carry no PII: the skeleton is the bank's fixed message
/// wording with every user-specific value (amount, name, account digits)
/// replaced by a placeholder token, which is exactly what makes it safe
/// to share globally across all users.
///
/// The [skeleton] alone is the single source of truth for what a
/// template extracts — there is deliberately no separate
/// name/type/constant-segments bookkeeping to drift out of sync with it.
class SmsTemplate {
  final String id;
  final String bank;
  final String bankCode;
  final String transactionType;
  final String? direction; // 'debit' | 'credit' | null
  final String? paymentMethod; // PaymentModeType.name or null
  final String? txnCategoryHint; // TxnCategory.name or null
  final String skeleton;
  final double templateConfidence;
  final int matchCount;
  final DateTime createdAt;
  final DateTime lastMatchedAt;

  const SmsTemplate({
    required this.id,
    required this.bank,
    required this.bankCode,
    required this.transactionType,
    this.direction,
    this.paymentMethod,
    this.txnCategoryHint,
    required this.skeleton,
    required this.templateConfidence,
    this.matchCount = 0,
    required this.createdAt,
    required this.lastMatchedAt,
  });

  factory SmsTemplate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SmsTemplate(
      id: doc.id,
      bank: data['bank'] ?? '',
      bankCode: data['bankCode'] ?? '',
      transactionType: data['transactionType'] ?? 'other',
      direction: data['direction'],
      paymentMethod: data['paymentMethod'],
      txnCategoryHint: data['txnCategoryHint'],
      skeleton: data['skeleton'] ?? '',
      templateConfidence: (data['templateConfidence'] as num?)?.toDouble() ?? 0.0,
      matchCount: (data['matchCount'] as num?)?.toInt() ?? 0,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastMatchedAt: (data['lastMatchedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toFirestore() => {
        'bank': bank,
        'bankCode': bankCode,
        'transactionType': transactionType,
        'direction': direction,
        'paymentMethod': paymentMethod,
        'txnCategoryHint': txnCategoryHint,
        'skeleton': skeleton,
        'templateConfidence': templateConfidence,
        'matchCount': matchCount,
        'createdAt': Timestamp.fromDate(createdAt),
        'lastMatchedAt': Timestamp.fromDate(lastMatchedAt),
      };

  /// A sender ID (e.g. "VM-HDFCBK-T") is considered a match for this
  /// template if it contains the template's bank code — DLT sender
  /// headers vary by telecom operator/region, but all embed the bank's
  /// brand code, which is the one stable substring across variants.
  /// Deliberately permissive: the compiled [skeleton] regex is the real
  /// gate (structural match against the whole message), this is only a
  /// cheap pre-filter to avoid trying every bank's templates against
  /// every message.
  bool senderMatches(String? sender) {
    if (bankCode.isEmpty) return true;
    if (sender == null || sender.isEmpty) return false;
    return sender.toUpperCase().contains(bankCode.toUpperCase());
  }

  /// Attempts to extract transaction fields by matching [body] against
  /// this template's compiled skeleton. Returns null if the skeleton
  /// fails to compile (malformed/unsafe template — never thrown) or
  /// doesn't structurally match this particular message.
  SmsTemplateExtraction? tryMatch(String body) {
    final compiled = SmsTemplateCompiler.compile(skeleton);
    if (compiled == null) return null;
    return compiled.match(body);
  }
}

/// Result of a successful template match: whichever fields the
/// template's placeholders were able to pull out of this message.
class SmsTemplateExtraction {
  final double? amount;
  final String? referenceNumber;
  final String? merchantCandidate;
  final String? accountLastDigits;

  const SmsTemplateExtraction({
    this.amount,
    this.referenceNumber,
    this.merchantCandidate,
    this.accountLastDigits,
  });
}

/// Fixed vocabulary of placeholder types a template's `{type}` tokens may
/// use, mapped to the regex fragment that recognizes an occurrence of
/// that type in real SMS text. Deliberately closed — an AI-produced
/// skeleton using any type outside this set fails to compile rather than
/// falling back to an unbounded/guessed pattern, since a wrong regex here
/// would silently corrupt shared, cross-user parsing data.
///
/// Kept in sync with the identical table in
/// android/app/src/main/kotlin/com/matrimpathak/ledger/SmsTemplateCompiler.kt.
const Map<String, String> placeholderPatterns = {
  'amount': r'[0-9][0-9,]*(?:\.[0-9]{1,2})?',
  'balance': r'[0-9][0-9,]*(?:\.[0-9]{1,2})?',
  'refno': r'[A-Za-z0-9]{6,}',
  'acct_last4': r'[0-9]{4}',
  'acct_last6': r'[0-9]{4,6}',
  'card_last4': r'[0-9]{4}',
  'phone': r'[0-9]{6,12}',
  'date': r'[0-9]{1,2}[-/][A-Za-z0-9]{2,4}[-/][0-9]{2,4}',
  'time': r'[0-9]{1,2}:[0-9]{2}(?::[0-9]{2})?\s*(?:[AaPp][Mm])?',
  'merchant': r'.{2,40}?',
  'vpa': r'[A-Za-z0-9.\-_]{2,40}@[A-Za-z0-9.\-_]{2,20}',
  'bank_name': r'[A-Za-z ]{2,25}',
};

/// Placeholder types whose captured text feeds each [SmsTemplateExtraction]
/// field. Types not listed here (date, time, phone, bank_name) are matched
/// structurally (so the surrounding literal text still has to line up) but
/// their captured value isn't consumed — mirrors how the static rules in
/// bank_patterns.json don't extract a date either (the transaction date
/// comes from the SMS's own timestamp, not its text).
const Set<String> _amountTypes = {'amount'};
const Set<String> _refTypes = {'refno'};
const Set<String> _merchantTypes = {'merchant', 'vpa'};
const Set<String> _digitTypes = {'acct_last4', 'acct_last6', 'card_last4'};

final RegExp _placeholderToken = RegExp(r'\{([a-z0-9_]+)\}');

/// Compiles a skeleton string (constant text interleaved with `{type}`
/// tokens) into a single regex that matches the whole shape at once and
/// reports which capture group belongs to which placeholder type.
class SmsTemplateCompiler {
  const SmsTemplateCompiler._(this._regex, this._typesByGroup);

  final RegExp _regex;
  final List<String> _typesByGroup;

  /// Returns null (never throws) for a skeleton that doesn't compile to a
  /// safe, well-formed matcher: an unknown placeholder type, two
  /// placeholders with no literal text between them (structurally
  /// ambiguous — which one owns which characters?), or a skeleton with no
  /// `{amount}` placeholder at all (nothing worth extracting).
  static SmsTemplateCompiler? compile(String skeleton) {
    if (skeleton.isEmpty || skeleton.length > 500) return null;
    if (!skeleton.contains('{amount}')) return null;

    final buffer = StringBuffer();
    final types = <String>[];
    var lastEnd = 0;
    var lastWasPlaceholder = false;

    for (final match in _placeholderToken.allMatches(skeleton)) {
      final literal = skeleton.substring(lastEnd, match.start);
      if (lastWasPlaceholder && literal.isEmpty) {
        return null; // two placeholders with nothing between them
      }
      buffer.write(RegExp.escape(literal));

      final type = match.group(1)!;
      final pattern = placeholderPatterns[type];
      if (pattern == null) return null; // unknown placeholder type

      buffer.write('($pattern)');
      types.add(type);
      lastEnd = match.end;
      lastWasPlaceholder = true;
    }
    buffer.write(RegExp.escape(skeleton.substring(lastEnd)));

    if (types.isEmpty) return null;

    try {
      final regex = RegExp(buffer.toString(), caseSensitive: false, dotAll: false);
      return SmsTemplateCompiler._(regex, types);
    } on FormatException {
      return null;
    }
  }

  SmsTemplateExtraction? match(String body) {
    final m = _regex.firstMatch(body);
    if (m == null) return null;

    double? amount;
    String? referenceNumber;
    String? merchantCandidate;
    String? accountLastDigits;

    for (var i = 0; i < _typesByGroup.length; i++) {
      final type = _typesByGroup[i];
      final raw = m.group(i + 1)?.trim();
      if (raw == null || raw.isEmpty) continue;

      if (amount == null && _amountTypes.contains(type)) {
        amount = double.tryParse(raw.replaceAll(',', ''));
      } else if (referenceNumber == null && _refTypes.contains(type)) {
        referenceNumber = raw;
      } else if (merchantCandidate == null && _merchantTypes.contains(type)) {
        merchantCandidate = raw.replaceAll(RegExp(r'\s+'), ' ');
      } else if (accountLastDigits == null && _digitTypes.contains(type)) {
        accountLastDigits = raw;
      }
    }

    return SmsTemplateExtraction(
      amount: amount,
      referenceNumber: referenceNumber,
      merchantCandidate: merchantCandidate,
      accountLastDigits: accountLastDigits,
    );
  }
}
