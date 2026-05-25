import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/services/sms/bank_sms_filter.dart';

void main() {
  group('BankSmsFilter.looksLikeBankSms', () {
    test('accepts UPI debit alerts', () {
      const body =
          'A/C XX1234 debited by Rs.450.00 for UPI ref 123456789012. '
          'Available balance is Rs.12,345.67';

      expect(BankSmsFilter.looksLikeBankSms(body), isTrue);
    });

    test('accepts salary credit alerts', () {
      const body =
          'INR 50000 credited to your acct via NEFT salary transfer.';

      expect(BankSmsFilter.looksLikeBankSms(body), isTrue);
    });

    test('rejects common OTP messages without banking keywords', () {
      const body = 'Your OTP is 123456. Do not share it with anyone.';

      expect(BankSmsFilter.looksLikeBankSms(body), isFalse);
    });

    test('matches keywords case-insensitively', () {
      const body = 'Your BANK transaction was successful.';

      expect(BankSmsFilter.looksLikeBankSms(body), isTrue);
    });
  });
}
