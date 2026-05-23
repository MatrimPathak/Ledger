import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/account.dart';

class StepAddAccount extends StatefulWidget {
  final String userId;
  final void Function(Account account) onNext;
  final VoidCallback onSkip;

  const StepAddAccount({
    super.key,
    required this.userId,
    required this.onNext,
    required this.onSkip,
  });

  @override
  State<StepAddAccount> createState() => _StepAddAccountState();
}

class _StepAddAccountState extends State<StepAddAccount> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController(text: 'My Bank Account');
  final _bankCtrl = TextEditingController();
  final _digitsCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController(text: '0');
  String _currency = 'INR';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bankCtrl.dispose();
    _digitsCtrl.dispose();
    _holderCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final account = Account(
      id: '',
      userId: widget.userId,
      title: _titleCtrl.text.trim(),
      bankName: _bankCtrl.text.trim(),
      lastSixDigits: _digitsCtrl.text.trim(),
      balance: double.tryParse(_balanceCtrl.text) ?? 0,
      holderName: _holderCtrl.text.trim(),
      currency: _currency,
      createdAt: DateTime.now(),
    );
    widget.onNext(account);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text('Add your first account',
                style: theme.textTheme.headlineMedium),
            const SizedBox(height: 4),
            Text('You can add more accounts later',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 20),
            // Live preview card
            _AccountPreviewCard(
              title: _titleCtrl.text.isEmpty ? 'Account Name' : _titleCtrl.text,
              bankName: _bankCtrl.text.isEmpty ? 'Bank Name' : _bankCtrl.text,
              lastSix: _digitsCtrl.text.isEmpty ? '······' : _digitsCtrl.text,
              holderName:
                  _holderCtrl.text.isEmpty ? 'Your Name' : _holderCtrl.text,
              balance: double.tryParse(_balanceCtrl.text) ?? 0,
              currency: _currency,
            ),
            const SizedBox(height: 20),
            _field('Account Title', _titleCtrl,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter account title' : null),
            const SizedBox(height: 12),
            _field('Bank Name', _bankCtrl,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter bank name' : null),
            const SizedBox(height: 12),
            _field('Last 6 digits of account number', _digitsCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                validator: (v) =>
                    v == null || v.trim().length != 6 ? 'Enter exactly 6 digits' : null),
            const SizedBox(height: 12),
            _field('Account Holder Name', _holderCtrl,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Enter holder name' : null),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _field('Current Balance', _balanceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}')),
                      ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    items: const ['INR', 'USD', 'EUR', 'GBP']
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                    decoration: const InputDecoration(labelText: 'Currency'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),
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
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return StatefulBuilder(
      builder: (context, setS) => TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        validator: validator,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class _AccountPreviewCard extends StatelessWidget {
  final String title;
  final String bankName;
  final String lastSix;
  final String holderName;
  final double balance;
  final String currency;

  const _AccountPreviewCard({
    required this.title,
    required this.bankName,
    required this.lastSix,
    required this.holderName,
    required this.balance,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.indigo700, AppColors.indigo900],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.indigo900.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  )),
              const Spacer(),
              Text(bankName,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Text(
            '•• $lastSix',
            style: const TextStyle(
                color: Colors.white60,
                fontSize: 14,
                letterSpacing: 3),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(holderName,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13)),
              const Spacer(),
              Text(
                '$currency ${balance.toStringAsFixed(2)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
