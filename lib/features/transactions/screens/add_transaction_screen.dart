import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/account.dart';
import '../../../models/category.dart';
import '../../../models/payment_mode.dart';
import '../../../models/transaction.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../../../providers/payment_modes_provider.dart';
import '../../categories/widgets/add_category_bottom_sheet.dart';
import '../../home/widgets/transaction_list_item.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  final Transaction? editTransaction;

  const AddTransactionScreen({super.key, this.editTransaction});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  TransactionType _type = TransactionType.expense;
  DateTime _date = DateTime.now();
  String? _categoryId;
  String? _accountId;
  String? _paymentModeId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final tx = widget.editTransaction;
    if (tx != null) {
      _titleCtrl.text = tx.title;
      _amountCtrl.text = tx.amount.toStringAsFixed(2);
      _notesCtrl.text = tx.notes ?? '';
      _type = tx.type;
      _date = tx.date;
      _categoryId = tx.categoryId;
      _accountId = tx.accountId;
      _paymentModeId = tx.paymentModeId;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_accountId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an account')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authStateProvider).value!;
      final firestoreService = ref.read(firestoreServiceProvider);
      final amount = double.parse(_amountCtrl.text);

      if (widget.editTransaction != null) {
        // Edit mode
        final updated = widget.editTransaction!.copyWith(
          title: _titleCtrl.text.trim(),
          amount: amount,
          type: _type,
          date: _date,
          categoryId: _categoryId ?? '',
          accountId: _accountId ?? '',
          paymentModeId: _paymentModeId,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
        await firestoreService.updateTransaction(updated);

        // Adjust balance: handle account change
        final oldAccountId = widget.editTransaction!.accountId;
        final oldAmount = widget.editTransaction!.amount;
        final oldType = widget.editTransaction!.type;
        final oldDelta =
            oldType == TransactionType.income ? oldAmount : -oldAmount;
        final newDelta = _type == TransactionType.income ? amount : -amount;

        if (oldAccountId != _accountId!) {
          // Account changed: reverse old account, apply to new account
          await firestoreService.updateAccountBalance(
              user.uid, oldAccountId, -oldDelta);
          await firestoreService.updateAccountBalance(
              user.uid, _accountId!, newDelta);
        } else {
          // Same account: apply net delta
          await firestoreService.updateAccountBalance(
              user.uid, _accountId!, newDelta - oldDelta);
        }
      } else {
        // Create mode
        final now = DateTime.now();
        final tx = Transaction(
          id: '',
          userId: user.uid,
          title: _titleCtrl.text.trim(),
          amount: amount,
          type: _type,
          date: _date,
          categoryId: _categoryId ?? '',
          accountId: _accountId ?? '',
          paymentModeId: _paymentModeId,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          createdAt: now,
        );
        await firestoreService.createTransaction(tx);
        final delta = _type == TransactionType.income ? amount : -amount;
        await firestoreService.updateAccountBalance(
            user.uid, _accountId!, delta);
      }

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final ctx = context;
    final picked = await showDatePicker(
      context: ctx,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
    );
    setState(() {
      _date = DateTime(
        picked.year,
        picked.month,
        picked.day,
        pickedTime?.hour ?? _date.hour,
        pickedTime?.minute ?? _date.minute,
      );
    });
  }

  Future<void> _addCategory() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AddCategoryBottomSheet(userId: user.uid),
    );
    if (result != null) {
      setState(() => _categoryId = result.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoriesAsync = ref.watch(categoriesProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final paymentModesAsync = ref.watch(paymentModesProvider);

    final categories = categoriesAsync.value ?? [];
    final accounts = accountsAsync.value ?? [];
    final allModes = paymentModesAsync.value ?? [];
    final filteredModes = _accountId != null
        ? allModes.where((m) => m.accountId == _accountId).toList()
        : allModes;

    final Category? selectedCategory = _categoryId != null
        ? _findCategory(categories, _categoryId!)
        : null;
    final Account? selectedAccount = _accountId != null
        ? _findAccount(accounts, _accountId!)
        : null;
    final PaymentMode? selectedMode = _paymentModeId != null
        ? _findPaymentMode(allModes, _paymentModeId!)
        : null;

    // Build preview transaction
    final previewTx = Transaction(
      id: '',
      userId: '',
      title: _titleCtrl.text.isEmpty ? 'Transaction Title' : _titleCtrl.text,
      amount: double.tryParse(_amountCtrl.text) ?? 0,
      type: _type,
      date: _date,
      categoryId: _categoryId ?? '',
      accountId: _accountId ?? '',
      paymentModeId: _paymentModeId,
      createdAt: DateTime.now(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editTransaction != null
            ? 'Edit Transaction'
            : 'Add Transaction'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            // Live preview
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            TransactionPreviewCard(
              transaction: previewTx,
              category: selectedCategory,
              paymentMode: selectedMode,
            ),
            const SizedBox(height: 20),
            // Form fields
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Title
                  TextFormField(
                    controller: _titleCtrl,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'What was this for?',
                    ),
                    validator: (v) => v!.isEmpty ? 'Enter a title' : null,
                  ),
                  const SizedBox(height: 12),
                  // Amount
                  TextFormField(
                    controller: _amountCtrl,
                    onChanged: (_) => setState(() {}),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}')),
                    ],
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '₹ ',
                    ),
                    validator: (v) {
                      final val = double.tryParse(v ?? '');
                      if (val == null || val <= 0) return 'Enter a valid amount';
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Type toggle
                  Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _TypeToggle(
                            label: 'Expense',
                            icon: Icons.arrow_upward_rounded,
                            selected: _type == TransactionType.expense,
                            color: AppColors.expenseRedDark,
                            onTap: () => setState(
                                () => _type = TransactionType.expense),
                          ),
                        ),
                        Expanded(
                          child: _TypeToggle(
                            label: 'Income',
                            icon: Icons.arrow_downward_rounded,
                            selected: _type == TransactionType.income,
                            color: AppColors.incomeGreenDark,
                            onTap: () => setState(
                                () => _type = TransactionType.income),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Date & Time
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.colorScheme.outline),
                        borderRadius: BorderRadius.circular(12),
                        color: theme.colorScheme.surface,
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 18),
                          const SizedBox(width: 12),
                          Text(DateFormatter.formatDateTime(_date),
                              style: theme.textTheme.bodyMedium),
                          const Spacer(),
                          const Icon(Icons.chevron_right, size: 18),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Category
                  _SectionDropdown(
                    label: 'Category',
                    displayText: selectedCategory?.title ?? 'Select category',
                    leading: selectedCategory != null
                        ? Icon(selectedCategory.icon,
                            color: selectedCategory.color, size: 20)
                        : const Icon(Icons.category_outlined, size: 20),
                    onTap: () => _showCategoryPicker(categories),
                  ),
                  const SizedBox(height: 12),
                  // Account
                  _SectionDropdown(
                    label: 'Account',
                    displayText: selectedAccount?.title ?? 'Select account',
                    leading: const Icon(Icons.account_balance_outlined, size: 20),
                    onTap: () => _showAccountPicker(accounts),
                  ),
                  const SizedBox(height: 12),
                  // Payment mode
                  _SectionDropdown(
                    label: 'Payment Mode',
                    displayText: selectedMode?.title ?? 'Select payment mode',
                    leading: const Icon(Icons.payment_outlined, size: 20),
                    onTap: filteredModes.isEmpty
                        ? null
                        : () => _showPaymentModePicker(filteredModes),
                  ),
                  const SizedBox(height: 12),
                  // Notes
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      hintText: 'Add any notes...',
                      alignLabelWithHint: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.editTransaction != null
                      ? 'Update Transaction'
                      : 'Save Transaction'),
            ),
          ),
        ),
      ),
    );
  }

  void _showCategoryPicker(List<Category> categories) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Category',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: categories.length + 1,
              itemBuilder: (ctx, i) {
                if (i == categories.length) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(ctx);
                      _addCategory();
                    },
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.indigo500,
                                style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.add,
                              color: AppColors.indigo500),
                        ),
                        const SizedBox(height: 4),
                        const Text('New',
                            style: TextStyle(fontSize: 11),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  );
                }
                final cat = categories[i];
                final selected = _categoryId == cat.id;
                return GestureDetector(
                  onTap: () {
                    setState(() => _categoryId = cat.id);
                    Navigator.pop(ctx);
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cat.color.withOpacity(selected ? 0.3 : 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: selected
                              ? Border.all(color: cat.color, width: 2)
                              : null,
                        ),
                        child: Icon(cat.icon, color: cat.color, size: 24),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        cat.title,
                        style: const TextStyle(fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showAccountPicker(List<Account> accounts) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Account',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ...accounts.map((a) => ListTile(
                  leading: const Icon(Icons.account_balance_outlined),
                  title: Text(a.title),
                  subtitle: Text('${a.bankName} ••${a.lastSixDigits}'),
                  selected: _accountId == a.id,
                  onTap: () {
                    setState(() {
                      _accountId = a.id;
                      _paymentModeId = null;
                    });
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _showPaymentModePicker(List<PaymentMode> modes) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select Payment Mode',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ...modes.map((m) => ListTile(
                  leading: const Icon(Icons.payment_outlined),
                  title: Text(m.title),
                  subtitle: Text(m.type.label),
                  selected: _paymentModeId == m.id,
                  onTap: () {
                    setState(() => _paymentModeId = m.id);
                    Navigator.pop(ctx);
                  },
                )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Category? _findCategory(List<Category> items, String id) {
    try {
      return items.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  Account? _findAccount(List<Account> items, String id) {
    try {
      return items.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  PaymentMode? _findPaymentMode(List<PaymentMode> items, String id) {
    try {
      return items.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _TypeToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? color : Colors.grey, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? color : Colors.grey,
                fontWeight:
                    selected ? FontWeight.w700 : FontWeight.w400,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionDropdown extends StatelessWidget {
  final String label;
  final String displayText;
  final Widget? leading;
  final VoidCallback? onTap;

  const _SectionDropdown({
    required this.label,
    required this.displayText,
    this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface,
        ),
        child: Row(
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.6),
                      )),
                  const SizedBox(height: 2),
                  Text(displayText, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right, size: 18),
          ],
        ),
      ),
    );
  }
}
