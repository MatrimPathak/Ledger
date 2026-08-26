import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/account.dart';
import 'package:ledger/models/payment_mode.dart';
import 'package:ledger/models/sms_template.dart';
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

  group('LocalSmsParser learned-template tier', () {
    // A shape no static rule in bank_patterns.json covers at all — it
    // deliberately avoids every rule-triggering keyword ("debited",
    // "credited", "upi", "credit card", "atm", "refund"), same as the
    // real HDFC "Sent"/"Received" format that motivated this tier.
    // Exactly the case the template tier exists for: a bank format
    // previously seen only via the AI fallback (see
    // ClaudeService.parseSmsTransaction), now resolvable locally.
    final icici = SmsTemplate(
      id: 'tpl-icici-debit',
      bank: 'ICICI Bank',
      bankCode: 'ICICIB',
      transactionType: 'bank_debit',
      direction: 'debit',
      paymentMethod: 'bankTransfer',
      txnCategoryHint: null,
      skeleton: 'ICICI Alert: INR {amount} moved from A/C XX{acct_last4} '
          'to {merchant} on {date}. Ref {refno}.',
      templateConfidence: 0.92,
      createdAt: DateTime.utc(2026),
      lastMatchedAt: DateTime.utc(2026),
    );
    const icc = 'ICICI Alert: INR 1250.50 moved from A/C XX7788 to '
        'BLINKIT on 19-Aug-26. Ref 445566778899.';

    test('falls back to a matching template when no static rule fits, '
        'reporting matchedRuleId "template" and the template\'s id', () {
      final result = parser.parse(icc,
          sender: 'AD-ICICIB-S', templates: [icici]);

      expect(result.matchedRuleId, 'template');
      expect(result.matchedTemplateId, 'tpl-icici-debit');
      expect(result.amount, 1250.5);
      expect(result.direction, 'debit');
      expect(result.paymentMethod, 'bankTransfer');
      expect(result.referenceNumber, '445566778899');
      expect(result.merchantCandidate, 'BLINKIT');
      expect(result.accountLastDigits, '7788');
      expect(result.isHighConfidence, isTrue,
          reason: 'amount+direction+ref+paymentMethod+merchant = 80/100');
    });

    test('a template from a different bank\'s sender is not tried', () {
      final result = parser.parse(icc,
          sender: 'VM-HDFCBK-T', templates: [icici]);

      expect(result.matchedRuleId, 'none');
      expect(result.matchedTemplateId, isNull);
    });

    test('a static rule match takes priority over a template, even one '
        'that would also match this exact body', () {
      // upi_debit already covers this shape via bank_patterns.json's own
      // rules — the template tier must never be consulted once a static
      // rule fires, so a bad/duplicate learned template can't override
      // hand-verified extraction.
      const body =
          'Rs.286.00 debited from A/C XX1234 to VPA rajesh@okhdfc on '
          '15-08-26. UPI Ref No 402312345678. Not you? Call 1800123456';
      final decoyTemplate = SmsTemplate(
        id: 'decoy',
        bank: 'HDFC Bank',
        bankCode: '', // matches any sender, to prove the rule still wins
        transactionType: 'other',
        direction: 'credit', // deliberately wrong, to prove it's unused
        skeleton: 'totally different shape {amount}',
        templateConfidence: 0.9,
        createdAt: DateTime.utc(2026),
        lastMatchedAt: DateTime.utc(2026),
      );

      final result = parser.parse(body, templates: [decoyTemplate]);

      expect(result.matchedRuleId, 'upi_debit');
      expect(result.matchedTemplateId, isNull);
      expect(result.direction, 'debit');
    });
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

    test(
        'disambiguates between several UPI modes on different accounts by '
        'account + type, since a UPI id has no digits of its own to match',
        () {
      const body = 'Sent Rs.500.00\n'
          'From HDFC Bank A/C *4321\n'
          'To Test Merchant\n'
          'On 18-08-26\n'
          'Ref 999888777666\n'
          'Not You?\n'
          'Call 18002586161/SMS BLOCK UPI to 7308080808';

      final accounts = [
        Account(
          id: 'acc-1',
          userId: 'user-1',
          title: 'HDFC Savings',
          bankName: 'HDFC Bank',
          lastSixDigits: '004321',
          balance: 0,
          holderName: 'Test User',
          createdAt: DateTime.utc(2026),
        ),
        Account(
          id: 'acc-2',
          userId: 'user-1',
          title: 'ICICI Savings',
          bankName: 'ICICI Bank',
          lastSixDigits: '009988',
          balance: 0,
          holderName: 'Test User',
          createdAt: DateTime.utc(2026),
        ),
      ];
      final paymentModes = [
        PaymentMode(
          id: 'upi-on-acc2',
          userId: 'user-1',
          type: PaymentModeType.upi,
          accountId: 'acc-2',
          title: 'UPI on ICICI',
          createdAt: DateTime.utc(2026),
        ),
        PaymentMode(
          id: 'upi-on-acc1',
          userId: 'user-1',
          type: PaymentModeType.upi,
          accountId: 'acc-1',
          title: 'UPI on HDFC',
          createdAt: DateTime.utc(2026),
        ),
        PaymentMode(
          id: 'card-on-acc1',
          userId: 'user-1',
          type: PaymentModeType.debitCard,
          accountId: 'acc-1',
          title: 'HDFC Debit Card',
          createdAt: DateTime.utc(2026),
        ),
      ];

      final result =
          parser.parse(body, accounts: accounts, paymentModes: paymentModes);

      expect(result.matchedAccountId, 'acc-1');
      expect(result.matchedPaymentModeId, 'upi-on-acc1');
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
