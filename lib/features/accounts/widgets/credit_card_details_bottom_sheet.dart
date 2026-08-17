import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/credit_card_account.dart';
import '../../../models/payment_mode.dart';
import '../../../providers/firestore_provider.dart';

/// Additive card-details editor: creates or updates the CreditCardAccount
/// linked to a creditCard PaymentMode. Until a user opens this once,
/// credit-card transactions keep working exactly as before this feature
/// existed (expense, not touching the bank balance) — this is purely
/// optional enrichment, never required.
class CreditCardDetailsBottomSheet extends ConsumerStatefulWidget {
  final String userId;
  final PaymentMode paymentMode;
  final CreditCardAccount? existing;

  const CreditCardDetailsBottomSheet({
    super.key,
    required this.userId,
    required this.paymentMode,
    this.existing,
  });

  @override
  ConsumerState<CreditCardDetailsBottomSheet> createState() =>
      _CreditCardDetailsBottomSheetState();
}

class _CreditCardDetailsBottomSheetState
    extends ConsumerState<CreditCardDetailsBottomSheet> {
  late final TextEditingController _bankNameCtrl;
  late final TextEditingController _limitCtrl;
  late final TextEditingController _statementDayCtrl;
  late final TextEditingController _dueDayCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _bankNameCtrl = TextEditingController(text: existing?.bankName ?? '');
    _limitCtrl = TextEditingController(
        text: existing != null && existing.creditLimit > 0
            ? existing.creditLimit.toStringAsFixed(0)
            : '');
    _statementDayCtrl =
        TextEditingController(text: existing?.statementDay?.toString() ?? '');
    _dueDayCtrl =
        TextEditingController(text: existing?.dueDay?.toString() ?? '');
  }

  @override
  void dispose() {
    _bankNameCtrl.dispose();
    _limitCtrl.dispose();
    _statementDayCtrl.dispose();
    _dueDayCtrl.dispose();
    super.dispose();
  }

  /// Parses a 1-31 day-of-month field, treating an out-of-range or
  /// unparseable value the same as "not provided" rather than persisting a
  /// value like 45 that `_ordinalSuffix` would later render as "45th".
  int? _parseDay(String text) {
    final value = int.tryParse(text.trim());
    if (value == null || value < 1 || value > 31) return null;
    return value;
  }

  Future<void> _save() async {
    final limitText = _limitCtrl.text.trim();
    final limit = limitText.isEmpty ? 0.0 : double.tryParse(limitText);
    if (limit == null || limit < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid credit limit')),
      );
      return;
    }
    final statementDayText = _statementDayCtrl.text.trim();
    if (statementDayText.isNotEmpty && _parseDay(statementDayText) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Statement day must be between 1 and 31')),
      );
      return;
    }
    final dueDayText = _dueDayCtrl.text.trim();
    if (dueDayText.isNotEmpty && _parseDay(dueDayText) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Due day must be between 1 and 31')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      final statementDay = _parseDay(statementDayText);
      final dueDay = _parseDay(dueDayText);

      final existing = widget.existing;
      if (existing != null) {
        await firestoreService.updateCreditCardAccount(existing.copyWith(
          bankName: _bankNameCtrl.text.trim(),
          creditLimit: limit,
          statementDay: () => statementDay,
          dueDay: () => dueDay,
        ));
      } else {
        await firestoreService.createCreditCardAccount(CreditCardAccount(
          id: '',
          userId: widget.userId,
          paymentModeId: widget.paymentMode.id,
          title: widget.paymentMode.title,
          bankName: _bankNameCtrl.text.trim(),
          lastFourDigits: widget.paymentMode.lastFourDigits ?? '',
          creditLimit: limit,
          statementDay: statementDay,
          dueDay: dueDay,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save card details: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.paymentMode.title} details',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Optional — lets Ledger track outstanding balance, available '
            'credit, and due date for this card.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _bankNameCtrl,
            decoration: const InputDecoration(labelText: 'Bank name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _limitCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Credit limit'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _statementDayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Statement day', hintText: '1-31'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _dueDayCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Due day', hintText: '1-31'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
