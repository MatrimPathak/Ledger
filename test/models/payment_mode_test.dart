import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/models/payment_mode.dart';

void main() {
  group('PaymentModeTypeExt.fromString', () {
    test('parses each persisted enum name', () {
      for (final type in PaymentModeType.values) {
        expect(PaymentModeTypeExt.fromString(type.name), type);
      }
    });

    test('falls back to cash for unknown persisted values', () {
      expect(PaymentModeTypeExt.fromString('wallet'), PaymentModeType.cash);
      expect(PaymentModeTypeExt.fromString(''), PaymentModeType.cash);
    });
  });

  group('PaymentModeType labels and icons', () {
    test('keeps UPI display metadata stable', () {
      expect(PaymentModeType.upi.label, 'UPI');
      expect(PaymentModeType.upi.iconName, 'upi');
    });

    test('keeps bank transfer display metadata stable', () {
      expect(PaymentModeType.bankTransfer.label, 'Bank Transfer');
      expect(PaymentModeType.bankTransfer.iconName, 'bank_transfer');
    });
  });
}
