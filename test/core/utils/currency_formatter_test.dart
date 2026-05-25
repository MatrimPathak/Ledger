import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/core/utils/currency_formatter.dart';

void main() {
  group('CurrencyFormatter.format', () {
    test('uses Indian digit grouping for INR values', () {
      expect(CurrencyFormatter.format(1234567.89), '₹12,34,567.89');
    });

    test('uses the configured symbol for supported foreign currencies', () {
      expect(
        CurrencyFormatter.format(1234.5, currency: 'USD'),
        r'$1,234.5',
      );
    });

    test('falls back to the currency code when no symbol is configured', () {
      expect(
        CurrencyFormatter.format(1234.5, currency: 'JPY'),
        'JPY1,234.5',
      );
    });
  });

  group('CurrencyFormatter.formatCompact', () {
    test('keeps small values in full precision formatting', () {
      expect(CurrencyFormatter.formatCompact(999.99), '₹999.99');
    });

    test('formats thousand values with the K suffix', () {
      expect(CurrencyFormatter.formatCompact(1250), '₹1.3K');
    });

    test('formats lakh values with the L suffix', () {
      expect(CurrencyFormatter.formatCompact(150000), '₹1.50L');
    });

    test('formats crore values with the Cr suffix', () {
      expect(CurrencyFormatter.formatCompact(25000000), '₹2.50Cr');
    });
  });

  group('CurrencyFormatter.formatNoSymbol', () {
    test('formats values without currency symbols', () {
      expect(CurrencyFormatter.formatNoSymbol(1234567.89), '12,34,567.89');
    });
  });
}
