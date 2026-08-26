import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/sms_template.dart';

void main() {
  group('SmsTemplateCompiler', () {
    // A shape none of assets/sms_patterns/bank_patterns.json's static
    // rules cover — proves the template tier can handle a bank format
    // never hand-coded, exactly the self-improving case it exists for.
    const skeleton =
        'ICICI Bank Acct XX{acct_last4} debited with INR {amount} on '
        '{date}; info: {merchant} (UPI Ref no {refno})';
    const body =
        'ICICI Bank Acct XX7788 debited with INR 1250.50 on 19-Aug-26; '
        'info: BLINKIT (UPI Ref no 445566778899)';

    test('compiles and extracts every mapped field from a novel shape', () {
      final compiled = SmsTemplateCompiler.compile(skeleton);
      expect(compiled, isNotNull);

      final result = compiled!.match(body);
      expect(result, isNotNull);
      expect(result!.amount, 1250.5);
      expect(result.referenceNumber, '445566778899');
      expect(result.merchantCandidate, 'BLINKIT');
      expect(result.accountLastDigits, '7788');
    });

    test('placeholder types with digits in their name still compile '
        '(acct_last4, acct_last6, card_last4)', () {
      // Regression: the token regex must accept digits in the type name,
      // not just letters/underscore — acct_last4 etc. would otherwise be
      // left as literal "{acct_last4}" text, which can never match real
      // SMS content, silently breaking every template using that type.
      for (final type in ['acct_last4', 'acct_last6', 'card_last4']) {
        final compiled =
            SmsTemplateCompiler.compile('Card {$type} charged {amount}');
        expect(compiled, isNotNull, reason: '$type should compile');
        final match = compiled!.match('Card 1234 charged 500.00');
        expect(match, isNotNull, reason: '$type should match');
        expect(match!.accountLastDigits, '1234');
      }
    });

    test('rejects a skeleton using an unrecognized placeholder type', () {
      expect(SmsTemplateCompiler.compile('Paid {amount} to {unknown_type}'),
          isNull);
    });

    test('rejects two placeholders with no literal text between them', () {
      expect(SmsTemplateCompiler.compile('{merchant}{amount}'), isNull);
    });

    test('rejects a skeleton with no {amount} placeholder at all', () {
      expect(
          SmsTemplateCompiler.compile('Hello {merchant}, OTP is {refno}'),
          isNull);
    });

    test('a compiled template returns null against unrelated text', () {
      final compiled = SmsTemplateCompiler.compile(skeleton);
      expect(compiled!.match('Some totally unrelated SMS with no structure'),
          isNull);
    });
  });

  group('SmsTemplate.senderMatches', () {
    final template = SmsTemplate(
      id: 't1',
      bank: 'ICICI Bank',
      bankCode: 'ICICIB',
      transactionType: 'bank_debit',
      skeleton: 'x {amount}',
      templateConfidence: 0.9,
      createdAt: DateTime.utc(2026),
      lastMatchedAt: DateTime.utc(2026),
    );

    test('matches when the sender contains the bank code', () {
      expect(template.senderMatches('AD-ICICIB-S'), isTrue);
      expect(template.senderMatches('VM-ICICIB-T'), isTrue);
    });

    test('does not match a different bank\'s sender', () {
      expect(template.senderMatches('VM-HDFCBK-T'), isFalse);
    });

    test('does not match a null/empty sender', () {
      expect(template.senderMatches(null), isFalse);
      expect(template.senderMatches(''), isFalse);
    });
  });
}
