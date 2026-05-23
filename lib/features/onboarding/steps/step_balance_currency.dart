import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/account.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';

class StepBalanceCurrency extends StatefulWidget {
  final Account? account;
  final void Function(Account? updatedAccount) onNext;
  final VoidCallback onSkip;

  const StepBalanceCurrency({
    super.key,
    this.account,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<StepBalanceCurrency> createState() => _StepBalanceCurrencyState();
}

class _StepBalanceCurrencyState extends State<StepBalanceCurrency> {
  late TextEditingController _balanceCtrl;
  late String _currency;

  @override
  void initState() {
    super.initState();
    _balanceCtrl =
        TextEditingController(text: widget.account?.balance.toString() ?? '0');
    _currency = widget.account?.currency ?? 'INR';
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final balance = double.tryParse(_balanceCtrl.text) ?? 0;
    final updated = widget.account?.copyWith(
      balance: balance,
      currency: _currency,
    );
    widget.onNext(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final symbol = AppConstants.currencySymbols[_currency] ?? _currency;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Set initial balance', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            widget.account != null
                ? 'What is your current balance in ${widget.account!.title}?'
                : 'You can set account balances later.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 40),
          if (widget.account != null) ...[
            // Large balance input
            Center(
              child: Column(
                children: [
                  Text(symbol,
                      style: theme.textTheme.headlineLarge?.copyWith(
                        color: AppColors.indigo400,
                      )),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 200,
                    child: TextField(
                      controller: _balanceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ],
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Container(
                    height: 2,
                    width: 200,
                    color: AppColors.indigo500,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Currency selector
            Text('Currency', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: AppConstants.supportedCurrencies.map((c) {
                final selected = _currency == c;
                final sym = AppConstants.currencySymbols[c] ?? c;
                return FilterChip(
                  label: Text('$sym $c'),
                  selected: selected,
                  onSelected: (_) => setState(() => _currency = c),
                  selectedColor: AppColors.indigo500,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                  checkmarkColor: Colors.white,
                );
              }).toList(),
            ),
          ] else ...[
            Center(
              child: Column(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined,
                      size: 64, color: AppColors.indigo400),
                  const SizedBox(height: 16),
                  Text(
                    'No account added yet',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You can add accounts and set balances from the Accounts screen.',
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _submit,
              child: const Text('Continue'),
            ),
          ),
          if (widget.account != null)
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('Skip'),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
