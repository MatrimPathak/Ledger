import '../../models/payment_mode.dart';

List<PaymentMode> paymentModesForTransaction(
  Iterable<PaymentMode> modes, {
  required String? accountId,
}) {
  if (accountId == null) return modes.toList();

  return modes
      .where((mode) =>
          mode.accountId == accountId ||
          mode.type == PaymentModeType.cash ||
          (mode.type == PaymentModeType.atm &&
              (mode.accountId == null || mode.accountId == accountId)))
      .toList();
}

List<PaymentMode> paymentModesForAccountPage(
  Iterable<PaymentMode> modes, {
  required String? accountId,
}) {
  if (accountId == null) return modes.toList();

  return modes
      .where((mode) =>
          mode.accountId == accountId || mode.type == PaymentModeType.cash)
      .toList();
}
