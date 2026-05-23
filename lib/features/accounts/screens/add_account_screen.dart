import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/account.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../../../core/constants/app_constants.dart';

class AddAccountScreen extends ConsumerStatefulWidget {
  const AddAccountScreen({super.key});

  @override
  ConsumerState<AddAccountScreen> createState() => _AddAccountScreenState();
}

class _AddAccountScreenState extends ConsumerState<AddAccountScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _digitsCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController(text: '0');
  String _currency = 'INR';
  bool _saving = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bankCtrl.dispose();
    _digitsCtrl.dispose();
    _holderCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Not signed in')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final account = Account(
        id: '',
        userId: user.uid,
        title: _titleCtrl.text.trim(),
        bankName: _bankCtrl.text.trim(),
        lastSixDigits: _digitsCtrl.text.trim(),
        balance: double.tryParse(_balanceCtrl.text) ?? 0,
        holderName: _holderCtrl.text.trim(),
        currency: _currency,
        createdAt: DateTime.now(),
      );
      await ref.read(firestoreServiceProvider).createAccount(account);
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
    final balance = double.tryParse(_balanceCtrl.text) ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Add Account')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Live preview
            _AccountPreview(
              title: _titleCtrl.text.isEmpty ? 'Account Name' : _titleCtrl.text,
              bankName: _bankCtrl.text.isEmpty ? 'Bank Name' : _bankCtrl.text,
              lastSix: _digitsCtrl.text.isEmpty ? '······' : _digitsCtrl.text,
              holderName:
                  _holderCtrl.text.isEmpty ? 'Your Name' : _holderCtrl.text,
              balance: balance,
              currency: _currency,
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Account Title'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bankCtrl,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Bank Name'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _digitsCtrl,
              onChanged: (_) => setState(() {}),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: const InputDecoration(
                  labelText: 'Last 6 digits of account number'),
              validator: (v) =>
                  v!.length != 6 ? 'Enter exactly 6 digits' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _holderCtrl,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'Account Holder Name'),
              validator: (v) => v!.isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _balanceCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    decoration:
                        const InputDecoration(labelText: 'Current Balance'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _currency,
                    items: AppConstants.supportedCurrencies
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
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
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Add Account'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountPreview extends StatelessWidget {
  final String title;
  final String bankName;
  final String lastSix;
  final String holderName;
  final double balance;
  final String currency;

  const _AccountPreview({
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
      height: 150,
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
          ),
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
                      fontSize: 16)),
              const Spacer(),
              Text(bankName,
                  style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          const Spacer(),
          Text('•• $lastSix',
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 13,
                  letterSpacing: 4)),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(holderName,
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              const Spacer(),
              Text(
                CurrencyFormatter.format(balance, currency: currency),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
