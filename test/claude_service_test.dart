import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:ledger/core/constants/app_constants.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
  group('ClaudeService analytics insights', () {
    test('returns demo insights without calling Claude when key is missing',
        () async {
      var wasCalled = false;
      final service = ClaudeService(
        AppConstants.claudeApiKeyPlaceholder,
        post: (url, {headers, body, encoding}) {
          wasCalled = true;
          return Future.value(http.Response('', 500));
        },
      );

      final insights = await service.generateInsightsOrThrow(
        transactionSummary: const [],
        currency: 'INR',
      );

      expect(wasCalled, isFalse);
      expect(insights, hasLength(1));
      expect(insights.single.title, 'Add your Claude API key');
    });

    test('parses successful Claude responses into analytics insights',
        () async {
      Object? requestBody;
      Map<String, String>? requestHeaders;
      final service = ClaudeService(
        'valid-key',
        post: (url, {headers, body, encoding}) {
          requestHeaders = headers;
          requestBody = body;
          return Future.value(
            http.Response(
              jsonEncode({
                'content': [
                  {
                    'text': jsonEncode([
                      {
                        'title': 'Food Trend',
                        'body': 'Dining spend is rising.',
                        'type': 'warning',
                      }
                    ]),
                  }
                ],
              }),
              200,
            ),
          );
        },
      );

      final insights = await service.generateInsightsOrThrow(
        transactionSummary: const [
          {'totalExpense': 1200}
        ],
        currency: 'INR',
      );

      expect(requestHeaders?['x-api-key'], 'valid-key');
      expect(jsonDecode(requestBody as String)['model'],
          AppConstants.claudeAnalyticsModel);
      expect(insights, hasLength(1));
      expect(insights.single.title, 'Food Trend');
      expect(insights.single.body, 'Dining spend is rising.');
      expect(insights.single.type, 'warning');
    });

    test('generateInsightsOrThrow surfaces invalid API key errors', () async {
      final service = ClaudeService(
        'bad-key',
        post: (url, {headers, body, encoding}) =>
            Future.value(http.Response('', 401)),
      );

      await expectLater(
        service.generateInsightsOrThrow(
          transactionSummary: const [
            {'totalExpense': 1200}
          ],
          currency: 'INR',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Invalid API key'),
          ),
        ),
      );
    });

    test('generateInsights keeps legacy demo fallback on Claude failures',
        () async {
      final service = ClaudeService(
        'bad-key',
        post: (url, {headers, body, encoding}) =>
            Future.value(http.Response('', 500)),
      );

      final insights = await service.generateInsights(
        transactionSummary: const [
          {'totalExpense': 1200}
        ],
        currency: 'INR',
      );

      expect(insights, hasLength(1));
      expect(insights.single.title, 'Add your Claude API key');
    });

    test('generateInsightsOrThrow surfaces Claude API failures', () async {
      final service = ClaudeService(
        'valid-key',
        post: (url, {headers, body, encoding}) =>
            Future.value(http.Response('', 500)),
      );

      await expectLater(
        service.generateInsightsOrThrow(
          transactionSummary: const [
            {'totalExpense': 1200}
          ],
          currency: 'INR',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Claude API error 500'),
          ),
        ),
      );
    });

    test('generateInsightsOrThrow turns timeouts into retryable errors',
        () async {
      final service = ClaudeService(
        'valid-key',
        post: (url, {headers, body, encoding}) =>
            Future.error(TimeoutException('slow')),
      );

      await expectLater(
        service.generateInsightsOrThrow(
          transactionSummary: const [
            {'totalExpense': 1200}
          ],
          currency: 'INR',
        ),
        throwsA(
          isA<Exception>().having(
            (error) => error.toString(),
            'message',
            contains('Request timed out'),
          ),
        ),
      );
    });
  });
}
