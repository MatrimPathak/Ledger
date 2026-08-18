import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/account.dart';
import 'package:ledger/models/payment_mode.dart';
import 'package:ledger/services/sms/local_sms_parser.dart';

LocalSmsParser _loadParser() {
  final rulesJson = jsonDecode(
    File('assets/sms_patterns/bank_patterns.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return LocalSmsParser.fromJson(rulesJson);
}

List<Map<String, dynamic>> _loadSamples() {
  final fixture = jsonDecode(
    File('test/fixtures/sms_samples.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  return (fixture['samples'] as List).cast<Map<String, dynamic>>();
}

void main() {
  final parser = _loadParser();
  final samples = _loadSamples();

  group('LocalSmsParser against shared fixtures', () {
    for (final sample in samples) {
      final id = sample['id'] as String;
      final body = sample['body'] as String;
      final expected = sample['expected'] as Map<String, dynamic>;

      test(id, () {
        final result = parser.parse(body);

        expect(result.amount, expected['amount']);
        expect(result.direction, expected['direction']);
        expect(result.paymentMethod, expected['paymentMethod']);
        expect(result.txnCategoryHint, expected['txnCategoryHint']);
        expect(result.referenceNumber, expected['referenceNumber']);
        expect(result.merchantCandidate, expected['merchantCandidate']);
        expect(result.accountLastDigits, expected['accountLastDigits']);
        expect(result.matchedRuleId, expected['matchedRuleId']);

        switch (expected['tier'] as String) {
          case 'high':
            expect(result.isHighConfidence, isTrue,
                reason: 'expected high confidence, got ${result.confidence}');
            break;
          case 'medium':
            expect(result.isMediumConfidence, isTrue,
                reason:
                    'expected medium confidence, got ${result.confidence}');
            break;
          case 'low':
            expect(result.isLowConfidence, isTrue,
                reason: 'expected low confidence, got ${result.confidence}');
            break;
        }
      });
    }
  });

  group('LocalSmsParser confidence rubric', () {
    test('matching a known account last-digits adds the instrument bonus', () {
      const body =
          'INR 12000.00 debited from your account for NEFT transfer to A/C XX4321. Avl Bal INR 45000.00';
      final withoutAccount = parser.parse(body);
      final withAccount = parser.parse(
        body,
        accounts: [
          Account(
            id: 'acc-1',
            userId: 'user-1',
            title: 'Checking',
            bankName: 'Test Bank',
            lastSixDigits: '564321',
            balance: 0,
            holderName: 'Test User',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      expect(withAccount.matchedAccountId, 'acc-1');
      expect(withAccount.confidence - withoutAccount.confidence, closeTo(0.20, 0.001));
    });

    test('matching a known payment mode last-digits adds the instrument bonus',
        () {
      const body =
          'Rs.4500.00 spent using your Credit Card XX9988 at a merchant on 12-08-26.';
      final withoutMode = parser.parse(body);
      final withMode = parser.parse(
        body,
        paymentModes: [
          PaymentMode(
            id: 'mode-1',
            userId: 'user-1',
            type: PaymentModeType.creditCard,
            title: 'HDFC Card',
            lastFourDigits: '9988',
            createdAt: DateTime.utc(2026),
          ),
        ],
      );

      expect(withMode.matchedPaymentModeId, 'mode-1');
      expect(withMode.confidence - withoutMode.confidence, closeTo(0.20, 0.001));
    });

    test('an empty string yields zero confidence and no rule match', () {
      final result = parser.parse('');

      expect(result.amount, isNull);
      expect(result.matchedRuleId, 'none');
      expect(result.confidence, 0.0);
      expect(result.isLowConfidence, isTrue);
    });

    test('tier boundaries are inclusive/exclusive as documented', () {
      expect(
        const LocalParseResult(matchedRuleId: 'none', confidence: 0.80)
            .isHighConfidence,
        isTrue,
      );
      expect(
        const LocalParseResult(matchedRuleId: 'none', confidence: 0.79)
            .isHighConfidence,
        isFalse,
      );
      expect(
        const LocalParseResult(matchedRuleId: 'none', confidence: 0.40)
            .isMediumConfidence,
        isTrue,
      );
      expect(
        const LocalParseResult(matchedRuleId: 'none', confidence: 0.39)
            .isMediumConfidence,
        isFalse,
      );
      expect(
        const LocalParseResult(matchedRuleId: 'none', confidence: 0.39)
            .isLowConfidence,
        isTrue,
      );
    });
  });
}
