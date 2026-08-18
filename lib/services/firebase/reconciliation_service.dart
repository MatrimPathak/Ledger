import 'package:cloud_functions/cloud_functions.dart';

/// Thin wrapper around the reconcileBalances Cloud Function — an on-demand
/// safety net that recomputes each credit card's outstanding balance
/// server-side from the transaction ledger and flags (never silently
/// corrects) any card whose stored value disagrees.
class ReconciliationService {
  ReconciliationService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<ReconciliationResult> reconcileBalances() async {
    final callable = _functions.httpsCallable('reconcileBalances');
    final response = await callable.call<Map<String, dynamic>>();
    final data = response.data;
    return ReconciliationResult(
      checked: (data['checked'] as num?)?.toInt() ?? 0,
      mismatched: (data['mismatched'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReconciliationResult {
  const ReconciliationResult({required this.checked, required this.mismatched});

  final int checked;
  final int mismatched;

  bool get allMatch => mismatched == 0;
}
