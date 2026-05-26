import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';
import '../../models/account.dart';
import '../../models/payment_mode.dart';

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

  const ParsedSmsTransaction({
    required this.title,
    required this.amount,
    required this.type,
    this.accountId,
    this.paymentModeId,
    this.suggestedCategorySlug,
    required this.confidence,
    this.rawSms,
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

class ClaudeService {
  final String apiKey;

  ClaudeService(this.apiKey);

  Future<ParsedSmsTransaction?> parseSmsTransaction({
    required String smsBody,
    required List<Account> accounts,
    required List<PaymentMode> paymentModes,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return null;
    }

    final accountsContext = accounts
        .map((a) => '{"id":"${a.id}","title":"${a.title}","bank":"${a.bankName}","last6":"${a.lastSixDigits}"}')
        .join(',');
    final modesContext = paymentModes
        .map((m) => '{"id":"${m.id}","type":"${m.type.name}","last4":"${m.lastFourDigits ?? ''}","upiId":"${m.upiId ?? ''}"}')
        .join(',');

    final prompt = '''
You are a financial SMS parser for Indian banking. Parse the SMS and return ONLY valid JSON with no markdown or explanation.

Accounts: [$accountsContext]
PaymentModes: [$modesContext]

SMS: "$smsBody"

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

    try {
      final response = await http
          .post(
            Uri.parse(AppConstants.claudeApiUrl),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': AppConstants.claudeApiVersion,
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': AppConstants.claudeSmsFastModel,
              'max_tokens': 256,
              'system': 'You are a financial SMS parser. Return ONLY valid JSON.',
              'messages': [
                {'role': 'user', 'content': prompt}
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content = (data['content'] as List).first['text'] as String;
      final json = jsonDecode(_stripMarkdown(content)) as Map<String, dynamic>;

      final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
      if (confidence < AppConstants.smsConfidenceThreshold / 100.0) return null;

      return ParsedSmsTransaction(
        title: json['title'] ?? 'Transaction',
        amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
        type: json['type'] ?? 'expense',
        accountId: json['accountId'],
        paymentModeId: json['paymentModeId'],
        suggestedCategorySlug: json['suggestedCategorySlug'],
        confidence: confidence,
        rawSms: smsBody,
      );
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
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

    final response = await http
        .post(
          Uri.parse(AppConstants.claudeApiUrl),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': AppConstants.claudeApiVersion,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': AppConstants.claudeAnalyticsModel,
            'max_tokens': 1024,
            'system':
                'You are a personal finance advisor. Return ONLY a valid JSON array of insights.',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

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

  // Like generateInsights but throws on API failure so the caller can surface
  // a real error state instead of silently showing the demo "Add your key" card.
  Future<List<AnalyticsInsight>> generateInsightsOrThrow({
    required List<Map<String, dynamic>> transactionSummary,
    required String currency,
  }) async {
    if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
      return _demoInsights();
    }

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

    final response = await http
        .post(
          Uri.parse(AppConstants.claudeApiUrl),
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': AppConstants.claudeApiVersion,
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'model': AppConstants.claudeAnalyticsModel,
            'max_tokens': 1024,
            'system':
                'You are a personal finance advisor. Return ONLY a valid JSON array of insights.',
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode == 401) {
      throw Exception('Invalid API key. Please check your key in Settings.');
    }
    if (response.statusCode != 200) {
      throw Exception('Claude API error ${response.statusCode}. Please try again.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final content = (data['content'] as List).first['text'] as String;
    final jsonList = jsonDecode(content.trim()) as List;
    return jsonList
        .map((e) => AnalyticsInsight.fromJson(e as Map<String, dynamic>))
        .toList();
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
