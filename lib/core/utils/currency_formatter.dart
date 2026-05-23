import 'package:intl/intl.dart';
import '../constants/app_constants.dart';

class CurrencyFormatter {
  static String format(double amount, {String currency = 'INR'}) {
    final symbol = AppConstants.currencySymbols[currency] ?? currency;
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return '$symbol${formatter.format(amount)}';
  }

  static String formatCompact(double amount, {String currency = 'INR'}) {
    final symbol = AppConstants.currencySymbols[currency] ?? currency;
    if (amount >= 10000000) {
      return '$symbol${(amount / 10000000).toStringAsFixed(2)}Cr';
    } else if (amount >= 100000) {
      return '$symbol${(amount / 100000).toStringAsFixed(2)}L';
    } else if (amount >= 1000) {
      return '$symbol${(amount / 1000).toStringAsFixed(1)}K';
    }
    return format(amount, currency: currency);
  }

  static String formatNoSymbol(double amount) {
    final formatter = NumberFormat('#,##,##0.##', 'en_IN');
    return formatter.format(amount);
  }
}
