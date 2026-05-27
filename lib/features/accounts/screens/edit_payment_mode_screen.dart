import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/account.dart';
import '../../../models/payment_mode.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/firestore_provider.dart';

class EditPaymentModeScreen extends ConsumerStatefulWidget {
  final PaymentMode mode;

  const EditPaymentModeScreen({super.key, required this.mode});

  @override
  ConsumerState<EditPaymentModeScreen> createState() =>
      _EditPaymentModeScreenState();
}

class _EditPaymentModeScreenState
    extends ConsumerState<EditPaymentModeScreen> {
  late PaymentModeType _type;
  late String? _accountId;
  late final TextEditingController _lastFourCtrl;
  late final TextEditingController _upiPrefixCtrl;
  late final TextEditingController _bankHandleCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.mode;
    _type = m.type;
    _accountId = m.accountId;
    _lastFourCtrl = TextEditingController(text: m.lastFourDigits ?? '');
    _upiPrefixCtrl = TextEditingController(text: m.upiId ?? '');
    _bankHandleCtrl = TextEditingController(text: m.bankHandle ?? '');
  }

  @override
  void dispose() {
    _lastFourCtrl.dispose();
    _upiPrefixCtrl.dispose();
    _bankHandleCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      String title;
      switch (_type) {
        case PaymentModeType.upi:
          final prefix = _upiPrefixCtrl.text.trim();
          final handle = _bankHandleCtrl.text.trim();
          final upiDisplay = prefix.isNotEmpty
              ? (handle.isNotEmpty ? '$prefix@$handle' : prefix)
              : 'UPI';
          title = 'UPI $upiDisplay';
        case PaymentModeType.creditCard:
          title = _lastFourCtrl.text.isNotEmpty
              ? 'Credit Card ••${_lastFourCtrl.text}'
              : 'Credit Card';
        case PaymentModeType.debitCard:
          title = _lastFourCtrl.text.isNotEmpty
              ? 'Debit Card ••${_lastFourCtrl.text}'
              : 'Debit Card';
        case PaymentModeType.atm:
          title = 'ATM';
        case PaymentModeType.cash:
          title = 'Cash';
        default:
          title = _type.label;
      }

      final updated = widget.mode.copyWith(
        type: _type,
        accountId: () => (_type == PaymentModeType.cash ||
                _type == PaymentModeType.atm)
            ? null
            : _accountId,
        title: title,
        lastFourDigits: () =>
            _lastFourCtrl.text.isNotEmpty ? _lastFourCtrl.text : null,
        upiId: () =>
            _upiPrefixCtrl.text.isNotEmpty ? _upiPrefixCtrl.text : null,
        bankHandle: () =>
            _bankHandleCtrl.text.isNotEmpty ? _bankHandleCtrl.text : null,
      );
      await ref.read(firestoreServiceProvider).updatePaymentMode(updated);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accounts = ref.watch(accountsProvider).value ?? [];

    Account? selectedAccount;
    try {
      if (_accountId != null) {
        selectedAccount = accounts.firstWhere((a) => a.id == _accountId);
      }
    } catch (_) {}

    final bool showCardField = _type == PaymentModeType.creditCard ||
        _type == PaymentModeType.debitCard;
    final bool showUpiFields = _type == PaymentModeType.upi;
    final bool showAccountField =
        _type != PaymentModeType.cash && _type != PaymentModeType.atm;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Payment Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PaymentModePreview(
            type: _type,
            lastFour: _lastFourCtrl.text,
            upiPrefix: _upiPrefixCtrl.text,
            bankHandle: _bankHandleCtrl.text,
            accountName: selectedAccount?.title ?? 'No account linked',
          ),
          const SizedBox(height: 20),
          Text('Type', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentModeType.values.map((t) {
              final selected = _type == t;
              return FilterChip(
                label: Text(t.label),
                selected: selected,
                onSelected: (_) => setState(() {
                  _type = t;
                  _lastFourCtrl.clear();
                  _upiPrefixCtrl.clear();
                  _bankHandleCtrl.clear();
                  if (t == PaymentModeType.cash ||
                      t == PaymentModeType.atm) {
                    _accountId = null;
                  }
                }),
                selectedColor: AppColors.indigo500,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          if (showUpiFields) ...[
            TextFormField(
              controller: _upiPrefixCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'UPI ID prefix',
                hintText: 'e.g. yourname',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bankHandleCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Bank handle',
                hintText: 'oksbi',
                prefixText: '@',
              ),
            ),
          ] else if (showCardField)
            TextFormField(
              controller: _lastFourCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration:
                  const InputDecoration(labelText: 'Last 4 digits of card'),
              maxLength: 4,
            ),
          if (showAccountField) ...[
            const SizedBox(height: 8),
            Text('Associated Account', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            if (accounts.isEmpty)
              Text('No accounts available.',
                  style: theme.textTheme.bodySmall)
            else
              DropdownButtonFormField<String?>(
                value: _accountId,
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...accounts.map((a) =>
                      DropdownMenuItem(value: a.id, child: Text(a.title))),
                ],
                onChanged: (v) => setState(() => _accountId = v),
                decoration: const InputDecoration(labelText: 'Account'),
              ),
          ],
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Changes'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentModePreview extends StatelessWidget {
  final PaymentModeType type;
  final String lastFour;
  final String upiPrefix;
  final String bankHandle;
  final String accountName;

  const _PaymentModePreview({
    required this.type,
    required this.lastFour,
    required this.upiPrefix,
    required this.bankHandle,
    required this.accountName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String subtitle;
    switch (type) {
      case PaymentModeType.upi:
        if (upiPrefix.isNotEmpty && bankHandle.isNotEmpty) {
          subtitle = '$upiPrefix@$bankHandle';
        } else if (upiPrefix.isNotEmpty) {
          subtitle = upiPrefix;
        } else {
          subtitle = 'UPI';
        }
      case PaymentModeType.creditCard:
      case PaymentModeType.debitCard:
        subtitle = lastFour.isNotEmpty ? '•••• $lastFour' : '•••• ••••';
      case PaymentModeType.cash:
        subtitle = 'Always available';
      case PaymentModeType.atm:
        subtitle = 'Debit card withdrawal';
      default:
        subtitle = type.label;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.indigo500.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.payment_outlined,
                color: AppColors.indigo400, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(type.label, style: theme.textTheme.titleMedium),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (type != PaymentModeType.cash)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.indigo500.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(accountName,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppColors.indigo400)),
            ),
        ],
      ),
    );
  }
}
