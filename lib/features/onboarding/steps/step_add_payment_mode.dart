import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/account.dart';
import '../../../models/payment_mode.dart';
import '../../../core/theme/app_colors.dart';

class StepAddPaymentMode extends StatefulWidget {
  final String userId;
  final Account? account;
  final void Function(PaymentMode mode) onNext;
  final VoidCallback onSkip;

  const StepAddPaymentMode({
    super.key,
    required this.userId,
    this.account,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<StepAddPaymentMode> createState() => _StepAddPaymentModeState();
}

class _StepAddPaymentModeState extends State<StepAddPaymentMode> {
  PaymentModeType _selectedType = PaymentModeType.upi;
  final _lastFourCtrl = TextEditingController();
  final _upiCtrl = TextEditingController();

  void _submit() {
    String title;
    switch (_selectedType) {
      case PaymentModeType.upi:
        title = _upiCtrl.text.isNotEmpty
            ? 'UPI ••${_upiCtrl.text}'
            : 'UPI';
        break;
      case PaymentModeType.creditCard:
        title = _lastFourCtrl.text.isNotEmpty
            ? 'Credit Card ••${_lastFourCtrl.text}'
            : 'Credit Card';
        break;
      case PaymentModeType.debitCard:
        title = _lastFourCtrl.text.isNotEmpty
            ? 'Debit Card ••${_lastFourCtrl.text}'
            : 'Debit Card';
        break;
      default:
        title = _selectedType.label;
        break;
    }

    // Only set lastFourDigits for card types; only set upiId for UPI type.
    final isCard = _selectedType == PaymentModeType.creditCard ||
        _selectedType == PaymentModeType.debitCard ||
        _selectedType == PaymentModeType.atm;
    final isUpi = _selectedType == PaymentModeType.upi;

    final mode = PaymentMode(
      id: '',
      userId: widget.userId,
      type: _selectedType,
      accountId: widget.account?.id,
      title: title,
      lastFourDigits: isCard && _lastFourCtrl.text.isNotEmpty
          ? _lastFourCtrl.text
          : null,
      upiId: isUpi && _upiCtrl.text.isNotEmpty ? _upiCtrl.text : null,
      createdAt: DateTime.now(),
    );
    widget.onNext(mode);
  }

  @override
  void dispose() {
    _lastFourCtrl.dispose();
    _upiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Add a payment mode', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('How do you usually pay?', style: theme.textTheme.bodySmall),
          const SizedBox(height: 20),
          // Type selector chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PaymentModeType.values.map((type) {
              final selected = _selectedType == type;
              return FilterChip(
                label: Text(type.label),
                selected: selected,
                onSelected: (_) => setState(() => _selectedType = type),
                selectedColor: AppColors.indigo500,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                checkmarkColor: Colors.white,
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          // Conditional fields
          if (_selectedType == PaymentModeType.upi) ...[
            TextFormField(
              controller: _upiCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Last 6 chars of UPI ID (before @)',
                hintText: 'e.g. abc123',
              ),
              maxLength: 6,
            ),
          ] else if (_selectedType == PaymentModeType.creditCard ||
              _selectedType == PaymentModeType.debitCard ||
              _selectedType == PaymentModeType.atm) ...[
            TextFormField(
              controller: _lastFourCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                labelText: 'Last 4 digits of card',
              ),
              maxLength: 4,
            ),
          ],
          // Preview
          const SizedBox(height: 8),
          _PaymentModePreview(
            type: _selectedType,
            lastFour: _lastFourCtrl.text,
            upiId: _upiCtrl.text,
            accountName: widget.account?.title ?? 'No account',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Continue'),
            ),
          ),
          TextButton(
            onPressed: widget.onSkip,
            child: const Text('Skip for now'),
          ),
          const SizedBox(height: 20),
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
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.indigo500.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child:
                const Icon(Icons.payment, color: AppColors.indigo400, size: 22),
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
          Text(accountName,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.indigo400,
              )),
        ],
      ),
    );
  }
}
