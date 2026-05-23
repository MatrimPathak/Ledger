import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/account.dart';
import '../../../models/payment_mode.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/firestore_provider.dart';

class AddPaymentModeScreen extends ConsumerStatefulWidget {
  const AddPaymentModeScreen({super.key});

  @override
  ConsumerState<AddPaymentModeScreen> createState() =>
      _AddPaymentModeScreenState();
}

class _AddPaymentModeScreenState extends ConsumerState<AddPaymentModeScreen> {
  PaymentModeType _type = PaymentModeType.upi;
  String? _accountId;
  final _lastFourCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _lastFourCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String title;
      switch (_type) {
        case PaymentModeType.upi:
          title = _upiCtrl.text.isNotEmpty
              ? 'UPI ••${_upiCtrl.text}'
              : 'UPI';
        case PaymentModeType.creditCard:
          title = _lastFourCtrl.text.isNotEmpty
              ? 'Credit Card ••${_lastFourCtrl.text}'
              : 'Credit Card';
        case PaymentModeType.debitCard:
          title = _lastFourCtrl.text.isNotEmpty
              ? 'Debit Card ••${_lastFourCtrl.text}'
              : 'Debit Card';
        case PaymentModeType.atm:
          title = _lastFourCtrl.text.isNotEmpty
              ? 'ATM ••${_lastFourCtrl.text}'
              : 'ATM Card';
        default:
          title = _type.label;
      }

      final mode = PaymentMode(
        id: '',
        userId: user.uid,
        type: _type,
        accountId: _accountId,
        title: title,
        lastFourDigits:
            _lastFourCtrl.text.isNotEmpty ? _lastFourCtrl.text : null,
        upiId: _upiCtrl.text.isNotEmpty ? _upiCtrl.text : null,
        createdAt: DateTime.now(),
      );
      await ref.read(firestoreServiceProvider).createPaymentMode(mode);
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
    final accountsAsync = ref.watch(accountsProvider);
    final accounts = accountsAsync.value ?? [];

    Account? selectedAccount;
    try {
      if (_accountId != null) {
        selectedAccount = accounts.firstWhere((a) => a.id == _accountId);
      }
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(title: const Text('Add Payment Mode')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Preview
          _PaymentModePreview(
            type: _type,
            lastFour: _lastFourCtrl.text,
            upiId: _upiCtrl.text,
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
                  _upiCtrl.clear();
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
          // Conditional fields
          if (_type == PaymentModeType.upi)
            TextFormField(
              controller: _upiCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Last 6 chars of UPI ID (before @)',
                hintText: 'e.g. abc123',
              ),
              maxLength: 6,
            )
          else if (_type == PaymentModeType.creditCard ||
              _type == PaymentModeType.debitCard ||
              _type == PaymentModeType.atm)
            TextFormField(
              controller: _lastFourCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(labelText: 'Last 4 digits of card'),
              maxLength: 4,
            ),
          const SizedBox(height: 8),
          // Account association
          Text('Associated Account', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          if (accounts.isEmpty)
            Text('No accounts available — add an account first.',
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
                  : const Text('Add Payment Mode'),
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
  final String upiId;
  final String accountName;

  const _PaymentModePreview({
    required this.type,
    required this.lastFour,
    required this.upiId,
    required this.accountName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String subtitle;
    switch (type) {
      case PaymentModeType.upi:
        subtitle = upiId.isNotEmpty ? '••$upiId@bank' : 'UPI';
      case PaymentModeType.creditCard:
      case PaymentModeType.debitCard:
      case PaymentModeType.atm:
        subtitle = lastFour.isNotEmpty ? '•••• $lastFour' : '•••• ••••';
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
