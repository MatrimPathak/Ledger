import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger/services/ai/claude_service.dart';

http.Response _claudeTextResponse(String text) {
  return http.Response(
    jsonEncode({
      'content': [
        {'text': text},
      ],
    }),
    200,
  );
}

void main() {
  group('ClaudeService.parseSmsTransaction', () {
    test('parses fenced JSON responses at the configured confidence threshold',
        () async {
      final service = ClaudeService(
        'test-api-key',
        client: MockClient((request) async {
          return _claudeTextResponse('''
```json
{
  "title": "Coffee Shop",
  "amount": 250.75,
  "type": "expense",
  "accountId": null,
  "paymentModeId": "upi-1",
  "suggestedCategorySlug": "food",
  "confidence": 0.45
}
```
''');
        }),
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 250.75 debited from your account at Coffee Shop',
        accounts: const [],
        paymentModes: const [],
      );

      expect(parsed, isNotNull);
      expect(parsed!.title, 'Coffee Shop');
      expect(parsed.amount, 250.75);
      expect(parsed.type, 'expense');
      expect(parsed.paymentModeId, 'upi-1');
      expect(parsed.suggestedCategorySlug, 'food');
      expect(parsed.confidence, 0.45);
      expect(parsed.rawSms, contains('Coffee Shop'));
    });

    test('rejects parsed SMS responses below the confidence threshold',
        () async {
      final service = ClaudeService(
        'test-api-key',
        client: MockClient((request) async {
          return _claudeTextResponse('''
{
  "title": "Unknown Merchant",
  "amount": 99,
  "type": "expense",
  "confidence": 0.39
}
''');
        }),
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 99 debited',
        accounts: const [],
        paymentModes: const [],
      );

      expect(parsed, isNull);
    });
  });

  group('ClaudeService.generateInsightsOrThrow', () {
    test('uses the supported analytics model and parses fenced JSON arrays',
        () async {
      late Map<String, dynamic> requestBody;
      final service = ClaudeService(
        'test-api-key',
        client: MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _claudeTextResponse('''
```json
[
  {
    "title": "Food Spike",
    "body": "Food spending rose this month.",
    "type": "warning"
  }
]
```
''');
        }),
      );

      final insights = await service.generateInsightsOrThrow(
        transactionSummary: const [
          {'category': 'food', 'amount': 1200},
        ],
        currency: 'INR',
      );

      expect(requestBody['model'], 'claude-haiku-4-5-20251001');
      expect(insights, hasLength(1));
      expect(insights.single.title, 'Food Spike');
      expect(insights.single.body, 'Food spending rose this month.');
      expect(insights.single.type, 'warning');
    });

    test('surfaces Claude API error messages from non-200 responses',
        () async {
      final service = ClaudeService(
        'test-api-key',
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'error': {
                'message': 'model claude-sonnet-4-6 was not found',
              },
            }),
            400,
          );
        }),
      );

      expect(
        () => service.generateInsightsOrThrow(
          transactionSummary: const [],
          currency: 'INR',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('model claude-sonnet-4-6 was not found'),
          ),
        ),
      );
    });
  });
}
