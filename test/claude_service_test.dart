import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/models/account.dart';
import 'package:ledger/models/payment_mode.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
  group('parseSmsTransaction', () {
    test('strips markdown fences, accepts threshold confidence, and uses SMS model',
        () async {
      Map<String, dynamic>? requestJson;
      final service = ClaudeService(
        'test-key',
        post: _capturePost(
          text: '''
```json
{
  "title": "Coffee Shop",
  "amount": 125.5,
  "type": "expense",
  "accountId": "account-1",
  "paymentModeId": "mode-1",
  "suggestedCategorySlug": "food",
  "confidence": 0.4
}
```
''',
          onRequest: (body) {
            requestJson = jsonDecode(body as String) as Map<String, dynamic>;
          },
        ),
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'Rs 125.50 debited from A/C XX123456 at Coffee Shop',
        accounts: [_account()],
        paymentModes: [_paymentMode()],
      );

      expect(parsed, isNotNull);
      expect(parsed!.title, 'Coffee Shop');
      expect(parsed.amount, 125.5);
      expect(parsed.type, 'expense');
      expect(parsed.accountId, 'account-1');
      expect(parsed.paymentModeId, 'mode-1');
      expect(parsed.suggestedCategorySlug, 'food');
      expect(parsed.confidence, 0.4);
      expect(parsed.rawSms, contains('Coffee Shop'));
      expect(requestJson?['model'], AppConstants.claudeSmsFastModel);
    });

    test('rejects parsed SMS below configured confidence threshold', () async {
      final service = ClaudeService(
        'test-key',
        post: _capturePost(
          text: '''
{
  "title": "Unknown",
  "amount": 99,
  "type": "expense",
  "confidence": 0.39
}
''',
        ),
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'Maybe a transaction',
        accounts: const [],
        paymentModes: const [],
      );

      expect(parsed, isNull);
    });

    test('does not call Claude when the API key is missing', () async {
      final service = ClaudeService(
        AppConstants.claudeApiKeyPlaceholder,
        post: (_, {headers, body, encoding}) {
          fail('Claude should not be called without a configured API key');
        },
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'Rs 100 debited',
        accounts: const [],
        paymentModes: const [],
      );

      expect(parsed, isNull);
    });
  });

  group('generateInsightsOrThrow', () {
    test('strips markdown fences and uses analytics model', () async {
      Map<String, dynamic>? requestJson;
      final service = ClaudeService(
        'test-key',
        post: _capturePost(
          text: '''
```json
[
  {
    "title": "Dining spike",
    "body": "Food spending is up this month.",
    "type": "warning"
  }
]
```
''',
          onRequest: (body) {
            requestJson = jsonDecode(body as String) as Map<String, dynamic>;
          },
        ),
      );

      final insights = await service.generateInsightsOrThrow(
        transactionSummary: const [
          {'period': 'last_90_days', 'totalExpense': 1000}
        ],
        currency: 'INR',
      );

      expect(insights, hasLength(1));
      expect(insights.single.title, 'Dining spike');
      expect(insights.single.type, 'warning');
      expect(requestJson?['model'], AppConstants.claudeAnalyticsModel);
    });

    test('surfaces Anthropic error message for non-200 responses', () async {
      final service = ClaudeService(
        'test-key',
        post: _capturePost(
          response: http.Response(
            jsonEncode({
              'error': {'message': 'model not found'}
            }),
            400,
          ),
        ),
      );

      expect(
        () => service.generateInsightsOrThrow(
          transactionSummary: const [],
          currency: 'INR',
        ),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('model not found'),
        )),
      );
    });
  });
}

ClaudePost _capturePost({
  String? text,
  http.Response? response,
  void Function(Object? body)? onRequest,
}) {
  return (
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) async {
    onRequest?.call(body);
    return response ??
        http.Response(
          jsonEncode({
            'content': [
              {'text': text}
            ]
          }),
          200,
        );
  };
}

Account _account() => Account(
      id: 'account-1',
      userId: 'user-1',
      title: 'Salary Account',
      bankName: 'HDFC',
      lastSixDigits: '123456',
      balance: 1000,
      holderName: 'Test User',
      createdAt: DateTime(2026, 1, 1),
    );

PaymentMode _paymentMode() => PaymentMode(
      id: 'mode-1',
      userId: 'user-1',
      type: PaymentModeType.upi,
      accountId: 'account-1',
      title: 'Primary UPI',
      upiId: 'user@bank',
      createdAt: DateTime(2026, 1, 1),
    );
