import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/models/account.dart';
import 'package:ledger/models/payment_mode.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
  setUp(() => ClaudeService.debugClearCache());

  group('ClaudeService.parseSmsTransaction', () {
    test('maps a confident Claude response into a parsed SMS transaction',
        () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;

        return http.Response(
          _claudeMessageBody({
            'title': 'Cafe Coffee Day',
            'amount': 249.5,
            'type': 'expense',
            'accountId': 'account-1',
            'paymentModeId': 'upi-1',
            'suggestedCategorySlug': 'food',
            'confidence': 0.91,
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 249.50 debited from A/C ending 123456 at Cafe Coffee Day',
        accounts: [_account()],
        paymentModes: [_paymentMode()],
      );

      expect(capturedRequest.url, Uri.parse(AppConstants.claudeApiUrl));
      expect(capturedRequest.headers['x-api-key'], 'test-api-key');
      expect(capturedRequest.headers['anthropic-version'],
          AppConstants.claudeApiVersion);

      final requestJson =
          jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      expect(requestJson['model'], AppConstants.claudeSmsFastModel);
      final messages = requestJson['messages'] as List<dynamic>;
      final prompt = messages.first['content'] as String;
      expect(prompt, contains('account-1'));
      expect(prompt, contains('upi-1'));
      expect(prompt, contains('Cafe Coffee Day'));

      expect(parsed, isNotNull);
      expect(parsed!.title, 'Cafe Coffee Day');
      expect(parsed.amount, 249.5);
      expect(parsed.type, 'expense');
      expect(parsed.accountId, 'account-1');
      expect(parsed.paymentModeId, 'upi-1');
      expect(parsed.suggestedCategorySlug, 'food');
      expect(parsed.confidence, 0.91);
      expect(parsed.rawSms,
          'INR 249.50 debited from A/C ending 123456 at Cafe Coffee Day');
    });

    test('rejects low-confidence parser responses', () async {
      final client = MockClient((_) async {
        return http.Response(
          _claudeMessageBody({
            'title': 'Unknown merchant',
            'amount': 500,
            'type': 'expense',
            'confidence': 0.39,
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 500 debited',
        accounts: [_account()],
        paymentModes: [_paymentMode()],
      );

      expect(parsed, isNull);
    });

    test('does not call Claude when API key is missing', () async {
      var wasCalled = false;
      final client = MockClient((_) async {
        wasCalled = true;
        return http.Response('', 500);
      });
      final service = ClaudeService(
        AppConstants.claudeApiKeyPlaceholder,
        client: client,
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 500 debited',
        accounts: [_account()],
        paymentModes: [_paymentMode()],
      );

      expect(parsed, isNull);
      expect(wasCalled, isFalse);
    });

    test('retries once after a network error and succeeds on the second attempt',
        () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        if (callCount == 1) {
          throw http.ClientException('Connection reset');
        }
        return http.Response(
          _claudeMessageBody({
            'title': 'Coffee Shop',
            'amount': 250,
            'type': 'expense',
            'confidence': 0.9,
          }),
          200,
        );
      });
      final service = ClaudeService(
        'test-api-key',
        client: client,
        retryDelay: Duration.zero,
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 250 debited',
        accounts: const [],
        paymentModes: const [],
      );

      expect(callCount, 2);
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Coffee Shop');
    });

    test('does not retry on a non-200 HTTP response', () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        return http.Response('', 500);
      });
      final service = ClaudeService(
        'test-api-key',
        client: client,
        retryDelay: Duration.zero,
      );

      final parsed = await service.parseSmsTransaction(
        smsBody: 'INR 250 debited',
        accounts: const [],
        paymentModes: const [],
      );

      expect(callCount, 1);
      expect(parsed, isNull);
    });

    test('caches a result by cacheKey and does not re-call Claude on a repeat',
        () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        return http.Response(
          _claudeMessageBody({
            'title': 'Coffee Shop',
            'amount': 250,
            'type': 'expense',
            'confidence': 0.9,
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      final first = await service.parseSmsTransaction(
        smsBody: 'INR 250 debited',
        accounts: const [],
        paymentModes: const [],
        cacheKey: 'hash-1',
      );
      final second = await service.parseSmsTransaction(
        smsBody: 'INR 250 debited',
        accounts: const [],
        paymentModes: const [],
        cacheKey: 'hash-1',
      );

      expect(callCount, 1);
      expect(first, isNotNull);
      expect(second, isNotNull);
      expect(second!.title, first!.title);
    });

    test('does not cache across different cacheKeys', () async {
      var callCount = 0;
      final client = MockClient((_) async {
        callCount++;
        return http.Response(
          _claudeMessageBody({
            'title': 'Coffee Shop',
            'amount': 250,
            'type': 'expense',
            'confidence': 0.9,
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      await service.parseSmsTransaction(
        smsBody: 'INR 250 debited',
        accounts: const [],
        paymentModes: const [],
        cacheKey: 'hash-1',
      );
      await service.parseSmsTransaction(
        smsBody: 'INR 500 debited',
        accounts: const [],
        paymentModes: const [],
        cacheKey: 'hash-2',
      );

      expect(callCount, 2);
    });
  });

  group('ClaudeService.parseSmsPartial', () {
    test('sends the redacted snippet and known fields instead of the full SMS',
        () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          _claudeMessageBody({
            'title': 'Uber',
            'amount': 286,
            'type': 'expense',
            'suggestedCategorySlug': 'transport',
            'confidence': 0.85,
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      const rawSms =
          'Rs.286.00 debited from A/C XX1234 to VPA rajesh@okhdfc on '
          '15-08-26. Avl Bal Rs.125430.50';
      final redactedSnippet = redactSensitiveDigits(rawSms);

      final parsed = await service.parseSmsPartial(
        redactedSmsSnippet: redactedSnippet,
        accounts: [_account()],
        paymentModes: [_paymentMode()],
        knownAmount: 286.0,
        knownDirection: 'debit',
        knownPaymentMethod: 'upi',
        knownReferenceNumber: '402312345678',
      );

      final requestJson =
          jsonDecode(capturedRequest.body) as Map<String, dynamic>;
      final prompt =
          (requestJson['messages'] as List).first['content'] as String;
      expect(prompt, contains('amount: 286.0'));
      expect(prompt, contains('direction: debit'));
      expect(prompt, contains('paymentMethod: upi'));
      expect(prompt, contains('402312345678'));
      // The real balance figure never reaches the prompt — only its
      // redacted form does.
      expect(prompt, isNot(contains('125430')));
      expect(prompt, contains('rajesh@okhdfc'));

      expect(parsed, isNotNull);
      expect(parsed!.title, 'Uber');
      expect(parsed.suggestedCategorySlug, 'transport');
    });

    test('does not call Claude when API key is missing', () async {
      var wasCalled = false;
      final client = MockClient((_) async {
        wasCalled = true;
        return http.Response('', 500);
      });
      final service = ClaudeService(
        AppConstants.claudeApiKeyPlaceholder,
        client: client,
      );

      final parsed = await service.parseSmsPartial(
        redactedSmsSnippet: 'Rs.286 debited',
        accounts: const [],
        paymentModes: const [],
      );

      expect(parsed, isNull);
      expect(wasCalled, isFalse);
    });
  });

  group('ClaudeService.generateInsights', () {
    test('returns demo guidance when API key is missing', () async {
      var wasCalled = false;
      final client = MockClient((_) async {
        wasCalled = true;
        return http.Response('', 500);
      });
      final service = ClaudeService(
        AppConstants.claudeApiKeyPlaceholder,
        client: client,
      );

      final insights = await service.generateInsights(
        transactionSummary: const [
          {'period': 'last_90_days', 'totalExpense': 1000},
        ],
        currency: 'INR',
      );

      expect(insights, hasLength(1));
      expect(insights.single.title, 'Add your Claude API key');
      expect(insights.single.type, 'tip');
      expect(wasCalled, isFalse);
    });

    test('falls back to demo guidance when Claude returns invalid JSON',
        () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({
            'content': [
              {'text': 'not-json'}
            ],
          }),
          200,
        );
      });
      final service = ClaudeService('test-api-key', client: client);

      final insights = await service.generateInsights(
        transactionSummary: const [
          {'period': 'last_90_days', 'totalExpense': 1000},
        ],
        currency: 'INR',
      );

      expect(insights, hasLength(1));
      expect(insights.single.title, 'Add your Claude API key');
      expect(insights.single.type, 'tip');
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
          return http.Response(
            jsonEncode({
              'content': [
                {
                  'text': '''
```json
[
  {
    "title": "Food Spike",
    "body": "Food spending rose this month.",
    "type": "warning"
  }
]
```
'''
                },
              ],
            }),
            200,
          );
        }),
      );

      final insights = await service.generateInsightsOrThrow(
        transactionSummary: const [
          {'category': 'food', 'amount': 1200},
        ],
        currency: 'INR',
      );

      expect(requestBody['model'], AppConstants.claudeAnalyticsModel);
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

  group('redactSensitiveDigits', () {
    test('masks a 6+ digit balance figure near a balance keyword', () {
      const body = 'Rs.286.00 debited from A/C XX1234. Avl Bal Rs.125430.50';

      final redacted = redactSensitiveDigits(body);

      expect(redacted, isNot(contains('125430')));
      expect(redacted, contains('A/C XX1234'));
      expect(redacted, contains('Rs.286.00'));
    });

    test('masks a comma-grouped balance figure', () {
      const body = 'Available balance is Rs.12,345.67';

      final redacted = redactSensitiveDigits(body);

      expect(redacted, isNot(contains('12,345')));
    });

    test('leaves short last-4-digit references untouched', () {
      const body = 'A/C XX1234 debited by Rs.450.00';

      expect(redactSensitiveDigits(body), body);
    });

    test('leaves amounts unrelated to account/balance keywords untouched', () {
      const body = 'INR 12000.00 debited from your account for NEFT transfer';

      // "account" is a keyword but no digit run of 6+ immediately follows
      // it within the proximity window — nothing to redact here.
      expect(redactSensitiveDigits(body), body);
    });
  });
}

String _claudeMessageBody(Object contentJson) {
  return jsonEncode({
    'content': [
      {'text': jsonEncode(contentJson)}
    ],
  });
}

Account _account() {
  return Account(
    id: 'account-1',
    userId: 'user-1',
    title: 'Salary Account',
    bankName: 'Acme Bank',
    lastSixDigits: '123456',
    balance: 10000,
    holderName: 'Test User',
    createdAt: DateTime(2026, 1, 1),
  );
}

PaymentMode _paymentMode() {
  return PaymentMode(
    id: 'upi-1',
    userId: 'user-1',
    type: PaymentModeType.upi,
    accountId: 'account-1',
    title: 'Primary UPI',
    upiId: 'test@upi',
    createdAt: DateTime(2026, 1, 1),
  );
}
