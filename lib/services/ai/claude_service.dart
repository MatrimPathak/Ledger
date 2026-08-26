import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../../models/account.dart';
import '../../models/payment_mode.dart';
import '../../models/sms_template.dart';

export '../../core/utils/sms_redaction.dart' show redactSensitiveDigits;

// Strip markdown code fences that models return despite being asked not to.
String _stripMarkdown(String text) {
  final stripped = text.trim();
  final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)```$', multiLine: false);
  final match = fence.firstMatch(stripped);
  return match != null ? match.group(1)!.trim() : stripped;
}

class ParsedSmsTransaction {
  final String title;
  final double amount;
  final String type; // 'expense' or 'income'
  final String? accountId;
  final String? paymentModeId;
  final String? suggestedCategorySlug;
  final double confidence; // 0.0 - 1.0
  final String? rawSms;
  // Only ever set by parseSmsTransaction (the full-SMS, lowest-confidence
  // path — exactly the case where no static rule or cached template
  // already handled this shape). Already passed the self-consistency
  // check in _buildLearnedTemplate: null here means either the AI didn't
  // return a template, returned one below the confidence bar, or the
  // template failed to correctly re-parse the very message it came from.
  final SmsTemplate? learnedTemplate;

  const ParsedSmsTransaction({
    required this.title,
    required this.amount,
    required this.type,
    this.accountId,
    this.paymentModeId,
    this.suggestedCategorySlug,
    required this.confidence,
    this.rawSms,
    this.learnedTemplate,
  });
}

class AnalyticsInsight {
  final String title;
  final String body;
  final String type; // 'tip', 'warning', 'positive', 'neutral'

  const AnalyticsInsight({
    required this.title,
    required this.body,
    required this.type,
  });

  factory AnalyticsInsight.fromJson(Map<String, dynamic> json) =>
      AnalyticsInsight(
        title: json['title'] ?? '',
        body: json['body'] ?? json['description'] ?? '',
        type: json['type'] ?? 'neutral',
      );
}

const _specialCases = '''
Special cases:
- E-Mandate / NACH / auto-debit notifications ("will be deducted", "E-Mandate!", "UMN"): treat as expense, extract the mandate description as title (e.g. "Amazon India" from "Amazon India mandate"), use "bills" as category.
- Credit card bill payment (a payment received/confirmed towards a credit card, not a purchase on it): this settles card debt from an existing balance — it is a transfer, not new spending. Use category "transfer".
- ATM withdrawal: treat as expense, category "other".''';

const _responseSchema = '''
Return JSON:
{
  "title": "merchant or description (max 30 chars)",
  "amount": number,
  "type": "expense" or "income",
  "accountId": "matching account id or null",
  "paymentModeId": "matching payment mode id or null",
  "suggestedCategorySlug": one of [food, transport, entertainment, shopping, bills, health, salary, investment, groceries, education, travel, transfer, other],
  "confidence": float 0.0-1.0
}''';

// Only used by parseSmsTransaction — the full-SMS path, reached only when
// nothing local (static rule or a previously learned template) already
// recognized this message's shape. Asks the model to also generalize the
// SMS into a reusable template, so the *next* message of this exact shape
// — from this user or any other Ledger user, since templates are shared
// and contain no personal data by construction — never needs an AI call
// again. This is the "self-improving" tier of the parsing pipeline.
const _templateInstructions = '''
Additionally, generalize this SMS into a reusable template for future messages of the exact same shape from the same bank. Every part of the message that would differ in another message of this shape (amount, date, reference number, account digits, payee name, phone numbers, etc.) must be replaced by exactly one placeholder token from this fixed set: {amount} {refno} {acct_last4} {acct_last6} {card_last4} {phone} {date} {time} {merchant} {vpa} {bank_name} {balance}. Everything else — fixed wording, punctuation, line breaks — must be copied verbatim from the original message. Two placeholders must never sit directly next to each other with no literal text between them. The skeleton must include an {amount} placeholder.''';

const _responseSchemaWithTemplate = '''
Return JSON:
{
  "title": "merchant or description (max 30 chars)",
  "amount": number,
  "type": "expense" or "income",
  "accountId": "matching account id or null",
  "paymentModeId": "matching payment mode id or null",
  "suggestedCategorySlug": one of [food, transport, entertainment, shopping, bills, health, salary, investment, groceries, education, travel, transfer, other],
  "confidence": float 0.0-1.0,
  "template": {
    "bank": "HDFC Bank" or null if unidentifiable,
    "bankCode": "short uppercase token identifying the bank from the sender id or message, e.g. HDFCBK, SBIINB, ICICIB, or null",
    "transactionType": one of [upi_debit, upi_credit, card_purchase, card_bill_payment, atm_withdrawal, bank_debit, bank_credit, refund, emandate, balance_inquiry, other],
    "direction": "debit" or "credit" or null,
    "paymentMethod": one of [upi, creditCard, debitCard, bankTransfer, atm, cash] or null,
    "txnCategoryHint": one of [creditCardPurchase, creditCardPayment, refund, expense] or null -- only when transactionType implies one of these, otherwise null,
    "skeleton": "the generalized message with placeholders, see instructions above",
    "constantVsVariable": "one sentence describing what is fixed boilerplate vs what varies message to message",
    "confidence": float 0.0-1.0 for how confidently this skeleton generalizes -- low if the message is ambiguous or unusual, or you are unsure a variable span was correctly identified
  } or null if this message is too unusual/ambiguous to safely generalize
}''';

class ClaudeService {
  final String apiKey;
  final http.Client? _client;
  final Duration _retryDelay;

  ClaudeService(
    this.apiKey, {
    http.Client? client,
    Duration retryDelay = const Duration(seconds: 2),
  })  : _client = client,
        _retryDelay = retryDelay;

  // In-memory cache for identical SMS resends within this process's
  // lifetime — SMS text is otherwise non-repeating across genuine
  // transactions, so a hit here means an actual duplicate delivery, not a
  // false-positive worth worrying about. Bounded so a pathological stream
  // of unique messages can't grow this unboundedly.
  static final Map<String, ParsedSmsTransaction?> _smsParseCache = {};
  static const int _maxCacheEntries = 100;

  static void _cacheResult(String cacheKey, ParsedSmsTransaction? result) {
    if (!_smsParseCache.containsKey(cacheKey) &&
        _smsParseCache.length >= _maxCacheEntries) {
      _smsParseCache.remove(_smsParseCache.keys.first);
    }
    _smsParseCache[cacheKey] = result;
  }

  /// Test-only: clears the shared parse cache so tests don't leak state
  /// into each other.
  static void debugClearCache() => _smsParseCache.clear();

  Future<http.Response> _postToClaude(Map<String, dynamic> body) {
    final client = _client;
    final uri = Uri.parse(AppConstants.claudeApiUrl);
    final headers = {
      'x-api-key': apiKey,
      'anthropic-version': AppConstants.claudeApiVersion,
      'content-type': 'application/json',
    };

    if (client != null) {
      return client.post(uri, headers: headers, body: jsonEncode(body));
    }

    return http.post(uri, headers: headers, body: jsonEncode(body));
  }

  /// Single retry with a short backoff, but only for network-level
  /// failures (timeout, connection errors) — never for a non-200 HTTP
  /// response, which is a real answer from the API, not a transient
  /// failure retrying would fix.
  ///
  /// The retry shares [timeout]'s overall budget rather than getting a
  /// fresh one — applying the full timeout twice let one call block for
  /// up to `timeout * 2 + retryDelay` (e.g. 62s on the 30s/2s defaults) on
  /// a user-visible path (`generateInsightsOrThrow`), well past what the
  /// caller asked for.
  Future<http.Response> _postWithRetry(
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    try {
      return await _postToClaude(body).timeout(timeout);
    } on TimeoutException {
      await Future.delayed(_retryDelay);
      return await _postToClaude(body).timeout(_remaining(deadline));
    } on http.ClientException {
      await Future.delayed(_retryDelay);
      return await _postToClaude(body).timeout(_remaining(deadline));
    }
  }

  Duration _remaining(DateTime deadline) {
    final left = deadline.difference(DateTime.now());
    return left > Duration.zero ? left : const Duration(milliseconds: 1);
  }

  Future<ParsedSmsTransaction?> parseSmsTransaction({
    required String smsBody,
    required List<Account> accounts,
    required List<PaymentMode> paymentModes,
    String? cacheKey,
    // The SMS sender/header id (e.g. "VM-HDFCBK-T"), passed through so the
    // model can identify a reliable bankCode for template matching even
    // when the message body itself doesn't spell out a canonical bank
    // name. Extraction/categorization don't need it — only template
    // generation does.
    String? sender,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return null;
    }

    // Namespaced so an identical cacheKey passed to parseSmsPartial (a
    // different prompt shape, different rawSms treatment) can never return
    // this method's cached result or vice versa.
    final scopedKey = cacheKey != null ? 'full:$cacheKey' : null;
    if (scopedKey != null && _smsParseCache.containsKey(scopedKey)) {
      return _smsParseCache[scopedKey];
    }

    final accountsContext = accounts
        .map((a) => '{"id":"${a.id}","title":"${a.title}","bank":"${a.bankName}","last6":"${a.lastSixDigits}"}')
        .join(',');
    final modesContext = paymentModes
        .map((m) => '{"id":"${m.id}","type":"${m.type.name}","last4":"${m.lastFourDigits ?? ''}","upiId":"${m.upiId ?? ''}"}')
        .join(',');

    final senderLine = (sender != null && sender.isNotEmpty)
        ? '\nSMS sender/header id: "$sender"'
        : '';

    final prompt = '''
You are a financial SMS parser for Indian banking. Parse the SMS and return ONLY valid JSON with no markdown or explanation.

Accounts: [$accountsContext]
PaymentModes: [$modesContext]

SMS: "$smsBody"$senderLine

$_specialCases

$_templateInstructions

$_responseSchemaWithTemplate''';

    ParsedSmsTransaction? result;
    try {
      final response = await _postWithRetry({
        'model': AppConstants.claudeSmsFastModel,
        'max_tokens': 512,
        'system': 'You are a financial SMS parser. Return ONLY valid JSON.',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      });

      if (response.statusCode != 200) {
        result = null;
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = (data['content'] as List).first['text'] as String;
        final json = jsonDecode(_stripMarkdown(content)) as Map<String, dynamic>;

        final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
        if (confidence < AppConstants.smsConfidenceThreshold / 100.0) {
          result = null;
        } else {
          final amount = (json['amount'] as num?)?.toDouble() ?? 0.0;
          result = ParsedSmsTransaction(
            title: json['title'] ?? 'Transaction',
            amount: amount,
            type: json['type'] ?? 'expense',
            accountId: json['accountId'],
            paymentModeId: json['paymentModeId'],
            suggestedCategorySlug: json['suggestedCategorySlug'],
            confidence: confidence,
            rawSms: smsBody,
            learnedTemplate: _buildLearnedTemplate(
              json['template'] as Map<String, dynamic>?,
              sourceBody: smsBody,
              aiAmount: amount,
            ),
          );
        }
      }
    } on TimeoutException {
      result = null;
    } catch (_) {
      result = null;
    }

    if (scopedKey != null) _cacheResult(scopedKey, result);
    return result;
  }

  static const double _minTemplateConfidence = 0.75;

  /// Validates and converts the model's raw `template` JSON into an
  /// [SmsTemplate], or null if it isn't safe to publish to the shared
  /// template library. Never throws.
  ///
  /// The critical check is the last one: the skeleton must correctly
  /// re-parse the exact SMS it was generalized from, and the amount that
  /// comes back must match what the model itself reported for this
  /// message. A skeleton that fails to reproduce its own source message
  /// is very likely malformed (wrong placeholder type, a variable span
  /// left as literal text, etc.) — publishing it to a collection every
  /// user's local parser reads from would risk silently mis-parsing
  /// other users' future transactions, so it's rejected rather than
  /// trusted on the model's word alone.
  static SmsTemplate? _buildLearnedTemplate(
    Map<String, dynamic>? template, {
    required String sourceBody,
    required double aiAmount,
  }) {
    if (template == null) return null;

    final skeleton = template['skeleton'] as String?;
    final templateConfidence =
        (template['confidence'] as num?)?.toDouble() ?? 0.0;
    if (skeleton == null ||
        skeleton.isEmpty ||
        templateConfidence < _minTemplateConfidence) {
      return null;
    }

    final compiled = SmsTemplateCompiler.compile(skeleton);
    if (compiled == null) return null;

    final selfExtraction = compiled.match(sourceBody);
    if (selfExtraction == null || selfExtraction.amount == null) return null;
    if ((selfExtraction.amount! - aiAmount).abs() > 0.01) return null;

    final now = DateTime.now();
    return SmsTemplate(
      id: '', // caller (firestore_service.dart) derives the deterministic doc id
      bank: template['bank'] as String? ?? '',
      bankCode: (template['bankCode'] as String? ?? '').toUpperCase(),
      transactionType: template['transactionType'] as String? ?? 'other',
      direction: template['direction'] as String?,
      paymentMethod: template['paymentMethod'] as String?,
      txnCategoryHint: template['txnCategoryHint'] as String?,
      skeleton: skeleton,
      templateConfidence: templateConfidence,
      matchCount: 0,
      createdAt: now,
      lastMatchedAt: now,
    );
  }

  /// Medium-confidence fallback: the local parser already extracted some
  /// fields reliably, so only a redacted snippet plus the still-uncertain
  /// fields are sent — never the full SMS. Used when local confidence is
  /// in the [0.40, 0.80) band; the full-SMS parseSmsTransaction stays the
  /// fallback for the < 0.40 band, where local extraction found too little
  /// to build a meaningfully smaller request from.
  Future<ParsedSmsTransaction?> parseSmsPartial({
    required String redactedSmsSnippet,
    required List<Account> accounts,
    required List<PaymentMode> paymentModes,
    double? knownAmount,
    String? knownDirection,
    String? knownPaymentMethod,
    String? knownReferenceNumber,
    String? cacheKey,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return null;
    }

    final scopedKey = cacheKey != null ? 'partial:$cacheKey' : null;
    if (scopedKey != null && _smsParseCache.containsKey(scopedKey)) {
      return _smsParseCache[scopedKey];
    }

    final accountsContext = accounts
        .map((a) => '{"id":"${a.id}","title":"${a.title}","bank":"${a.bankName}","last6":"${a.lastSixDigits}"}')
        .join(',');
    final modesContext = paymentModes
        .map((m) => '{"id":"${m.id}","type":"${m.type.name}","last4":"${m.lastFourDigits ?? ''}","upiId":"${m.upiId ?? ''}"}')
        .join(',');

    final knownFields = [
      if (knownAmount != null) 'amount: $knownAmount',
      if (knownDirection != null) 'direction: $knownDirection',
      if (knownPaymentMethod != null) 'paymentMethod: $knownPaymentMethod',
      if (knownReferenceNumber != null) 'referenceNumber: $knownReferenceNumber',
    ].join(', ');

    final prompt = '''
You are a financial SMS parser for Indian banking. Some fields were already extracted locally with reasonable confidence — treat them as reliable unless the SMS snippet clearly contradicts them. Focus on completing/confirming the rest. Return ONLY valid JSON with no markdown or explanation.

Already extracted: {$knownFields}

Accounts: [$accountsContext]
PaymentModes: [$modesContext]

SMS snippet (account numbers/balance figures redacted, not needed to classify the transaction): "$redactedSmsSnippet"

$_specialCases

$_responseSchema''';

    ParsedSmsTransaction? result;
    try {
      final response = await _postWithRetry({
        'model': AppConstants.claudeSmsFastModel,
        'max_tokens': 256,
        'system': 'You are a financial SMS parser. Return ONLY valid JSON.',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      });

      if (response.statusCode != 200) {
        result = null;
      } else {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final content = (data['content'] as List).first['text'] as String;
        final json = jsonDecode(_stripMarkdown(content)) as Map<String, dynamic>;

        final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
        if (confidence < AppConstants.smsConfidenceThreshold / 100.0) {
          result = null;
        } else {
          result = ParsedSmsTransaction(
            title: json['title'] ?? 'Transaction',
            amount: (json['amount'] as num?)?.toDouble() ?? knownAmount ?? 0.0,
            type: json['type'] ?? 'expense',
            accountId: json['accountId'],
            paymentModeId: json['paymentModeId'],
            suggestedCategorySlug: json['suggestedCategorySlug'],
            confidence: confidence,
            rawSms: redactedSmsSnippet,
          );
        }
      }
    } on TimeoutException {
      result = null;
    } catch (_) {
      result = null;
    }

    if (scopedKey != null) _cacheResult(scopedKey, result);
    return result;
  }

  Future<List<AnalyticsInsight>> generateInsights({
    required List<Map<String, dynamic>> transactionSummary,
    required String currency,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return _demoInsights();
    }
    try {
      return await _fetchInsights(transactionSummary, currency);
    } on TimeoutException {
      return _demoInsights();
    } catch (_) {
      return _demoInsights();
    }
  }

  // Like generateInsights but throws on API failure so the caller can surface
  // a real error state instead of silently showing the demo "Add your key" card.
  Future<List<AnalyticsInsight>> generateInsightsOrThrow({
    required List<Map<String, dynamic>> transactionSummary,
    required String currency,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return _demoInsights();
    }
    try {
      return await _fetchInsights(transactionSummary, currency);
    } on TimeoutException {
      throw Exception(
          'Request timed out. Please check your connection and try again.');
    } catch (e) {
      rethrow;
    }
  }

  Future<List<AnalyticsInsight>> _fetchInsights(
    List<Map<String, dynamic>> transactionSummary,
    String currency,
  ) async {
    final prompt = '''
You are a personal finance advisor for an Indian user. Analyze the spending data and return a JSON array of insights.

Currency: $currency
Data: ${jsonEncode(transactionSummary)}

Return ONLY a JSON array (no markdown):
[
  {
    "title": "string (max 8 words)",
    "body": "1-2 specific actionable sentences",
    "type": "tip" | "warning" | "positive" | "neutral"
  }
]
Return 4-6 most valuable insights.''';

    final response = await _postWithRetry({
      'model': AppConstants.claudeAnalyticsModel,
      'max_tokens': 1024,
      'system':
          'You are a personal finance advisor. Return ONLY a valid JSON array of insights.',
      'messages': [
        {'role': 'user', 'content': prompt}
      ],
    });

    if (response.statusCode == 401) {
      throw Exception('Invalid API key. Please check your key in Settings.');
    }
    if (response.statusCode != 200) {
      String detail = 'Claude API error ${response.statusCode}.';
      try {
        final errBody = jsonDecode(response.body) as Map<String, dynamic>;
        final errMsg =
            (errBody['error'] as Map<String, dynamic>?)?['message'] as String?;
        if (errMsg != null && errMsg.isNotEmpty) detail = errMsg;
      } catch (_) {}
      throw Exception(detail);
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] as List).first['text'] as String;
      final jsonList = jsonDecode(_stripMarkdown(content)) as List;
      return jsonList
          .map((e) => AnalyticsInsight.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      throw Exception('Invalid response from Claude API. Please try again.');
    }
  }

  List<AnalyticsInsight> _demoInsights() => [
        const AnalyticsInsight(
          title: 'Add your Claude API key',
          body:
              'Add your Claude API key in Settings to enable AI-powered insights. Get a key at console.anthropic.com.',
          type: 'tip',
        ),
      ];
}
