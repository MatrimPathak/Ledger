import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/services/sms/bank_sms_filter.dart';

void main() {
  setUpAll(() {
    final rules = jsonDecode(
      File('assets/sms_patterns/bank_patterns.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    BankSmsFilter.debugLoadFrom(rules);
  });

  group('BankSmsFilter.looksLikeBankSms', () {
    test('accepts UPI debit alerts', () async {
      const body =
          'A/C XX1234 debited by Rs.450.00 for UPI ref 123456789012. '
          'Available balance is Rs.12,345.67';

      expect(await BankSmsFilter.looksLikeBankSms(body), isTrue);
    });

    test('accepts salary credit alerts', () async {
      const body =
          'INR 50000 credited to your acct via NEFT salary transfer.';

      expect(await BankSmsFilter.looksLikeBankSms(body), isTrue);
    });

    test('rejects common OTP messages without banking keywords', () async {
      const body = 'Your OTP is 123456. Do not share it with anyone.';

      expect(await BankSmsFilter.looksLikeBankSms(body), isFalse);
    });

    test('matches keywords case-insensitively', () async {
      const body = 'Your BANK transaction was successful.';

      expect(await BankSmsFilter.looksLikeBankSms(body), isTrue);
    });
  });
}
