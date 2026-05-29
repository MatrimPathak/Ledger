import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/account.dart';
import '../../../models/category.dart';
import '../../../models/payment_mode.dart';
import '../../../models/transaction.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../../../providers/payment_modes_provider.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/notification/notification_service.dart';
import '../../home/widgets/transaction_list_item.dart';

class TransactionDetailScreen extends ConsumerWidget {
  final Transaction? transaction;
  final String? transactionId;

  const TransactionDetailScreen({
    super.key,
    this.transaction,
    this.transactionId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // If a full Transaction object was passed, render directly.
    // Otherwise load by transactionId (e.g. when arriving via deep-link / notification).
    if (transaction != null) {
      return _TransactionDetailBody(transaction: transaction!);
    }
    if (transactionId == null || transactionId!.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Transaction not found.')),
      );
    }
    return _TransactionLoader(transactionId: transactionId!);
  }
}

/// Loads a transaction by ID then delegates to [_TransactionDetailBody].
class _TransactionLoader extends ConsumerWidget {
  final String transactionId;
  const _TransactionLoader({required this.transactionId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).value;
    if (user == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final firestoreService = ref.watch(firestoreServiceProvider);
    return FutureBuilder<Transaction?>(
      future: firestoreService.getTransaction(user.uid, transactionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final tx = snapshot.data;
        if (tx == null) {
          return const Scaffold(
            body: Center(child: Text('Transaction not found.')),
          );
        }
        return _TransactionDetailBody(transaction: tx);
      },
    );
  }
}

class _TransactionDetailBody extends ConsumerWidget {
  final Transaction transaction;
  const _TransactionDetailBody({required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoriesProvider).value ?? [];
    final paymentModes = ref.watch(paymentModesProvider).value ?? [];
    final accounts = ref.watch(accountsProvider).value ?? [];

    Category? category;
    try {
      category = categories.firstWhere((c) => c.id == transaction.categoryId);
    } catch (_) {}

    PaymentMode? paymentMode;
    try {
      if (transaction.paymentModeId != null) {
        paymentMode = paymentModes.firstWhere(
            (m) => m.id == transaction.paymentModeId);
      }
    } catch (_) {}

    Account? account;
    try {
      account = accounts.firstWhere((a) => a.id == transaction.accountId);
    } catch (_) {}

    final isExpense = transaction.type == TransactionType.expense;
    final amountColor =
        isExpense ? AppColors.expenseRedDark : AppColors.incomeGreenDark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transaction Details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () =>
                context.push('/add-transaction', extra: transaction),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.expenseRedDark),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // Preview card
          TransactionPreviewCard(
            transaction: transaction,
            category: category,
            paymentMode: paymentMode,
          ),
          const SizedBox(height: 8),
          // Amount prominently
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${isExpense ? '-' : '+'}${CurrencyFormatter.format(transaction.amount, currency: account?.currency ?? 'INR')}',
                style: theme.textTheme.displayMedium?.copyWith(
                  color: amountColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          // Details
          _DetailCard(
            children: [
              _DetailRow(
                icon: Icons.calendar_today_outlined,
                label: 'Date & Time',
                value: DateFormatter.formatDateTime(transaction.date),
              ),
              _DetailRow(
                icon: category?.icon ?? Icons.category_outlined,
                label: 'Category',
                value: category?.title ?? 'Unknown',
                iconColor: category?.color,
              ),
              _DetailRow(
                icon: Icons.account_balance_outlined,
                label: 'Account',
                value: account != null
                    ? '${account.title} ••${account.lastSixDigits}'
                    : 'Unknown',
              ),
              if (paymentMode != null)
                _DetailRow(
                  icon: Icons.payment_outlined,
                  label: 'Payment Mode',
                  value: paymentMode.title,
                ),
              _DetailRow(
                icon: transaction.type == TransactionType.expense
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                label: 'Type',
                value: transaction.type == TransactionType.expense
                    ? 'Expense'
                    : 'Income',
                iconColor: amountColor,
              ),
              _DetailRow(
                icon: transaction.source == TransactionSource.sms
                    ? Icons.sms_outlined
                    : Icons.edit_outlined,
                label: 'Source',
                value: transaction.source == TransactionSource.sms
                    ? 'Auto-detected (SMS)'
                    : 'Manual entry',
              ),
            ],
          ),
          // Notes
          if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
            const SizedBox(height: 8),
            _DetailCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notes_outlined, size: 18),
                          const SizedBox(width: 8),
                          Text('Notes', style: theme.textTheme.labelMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(transaction.notes!,
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
          ],
          // Raw SMS (if auto-detected)
          if (transaction.source == TransactionSource.sms &&
              transaction.rawSms != null) ...[
            const SizedBox(height: 8),
            _DetailCard(
              children: [
                Theme(
                  data: Theme.of(context)
                      .copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    leading: const Icon(Icons.sms_outlined, size: 18),
                    title: Text('Original SMS',
                        style: theme.textTheme.labelMedium),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        child: Text(
                          transaction.rawSms!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
            'This action cannot be undone. The account balance will be adjusted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.expenseRedDark),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      final firestoreService = ref.read(firestoreServiceProvider);
      await firestoreService.deleteTransaction(user.uid, transaction.id);

      // Reverse the balance effect only if the transaction originally affected balance
      if (transaction.affectsBalance) {
        final reverseDelta = transaction.type == TransactionType.income
            ? -transaction.amount
            : transaction.amount;
        await firestoreService.updateAccountBalance(
            user.uid, transaction.accountId, reverseDelta);
      }

      final notificationsOn = ref.read(settingsProvider).notificationsEnabled;
      if (notificationsOn) {
        await NotificationService.showTransactionDeletedNotification(
            transaction.title);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
        return;
      }
    }

    if (context.mounted) context.pop();
  }
}

class _DetailCard extends StatelessWidget {
  final List<Widget> children;
  const _DetailCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outline),
      ),
      child: Column(children: children),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? iconColor;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon,
              size: 18,
              color: iconColor ??
                  theme.colorScheme.onSurface.withOpacity(0.6)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
