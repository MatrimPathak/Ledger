import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/models/account.dart';
import 'package:ledger/models/payment_mode.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
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
            'confidence': 0.69,
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
