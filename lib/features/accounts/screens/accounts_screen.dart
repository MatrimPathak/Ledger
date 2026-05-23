import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/account.dart';
import '../../../models/payment_mode.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../../../providers/payment_modes_provider.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accountsAsync = ref.watch(accountsProvider);
    final paymentModesAsync = ref.watch(paymentModesProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text('Accounts',
                style: TextStyle(fontWeight: FontWeight.w800)),
            centerTitle: false,
          ),
          // Accounts section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text('My Accounts',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.push('/add-account'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: accountsAsync.when(
              loading: () => const Center(
                  child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return _EmptyState(
                    icon: Icons.account_balance_outlined,
                    message: 'No accounts added yet',
                    action: 'Add Account',
                    onTap: () => context.push('/add-account'),
                  );
                }
                return SizedBox(
                  height: 160,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: accounts.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == accounts.length) {
                        return _AddAccountCard(
                          onTap: () => context.push('/add-account'),
                        );
                      }
                      return _AccountCard(
                        account: accounts[i],
                        onDelete: () => _deleteAccount(accounts[i]),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Payment modes section
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Text('Payment Modes',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => context.push('/add-payment-mode'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                  ),
                ],
              ),
            ),
          ),
          paymentModesAsync.when(
            loading: () => const SliverToBoxAdapter(
                child: Center(child: CircularProgressIndicator())),
            error: (e, _) =>
                SliverToBoxAdapter(child: Center(child: Text('Error: $e'))),
            data: (modes) {
              if (modes.isEmpty) {
                return SliverToBoxAdapter(
                  child: _EmptyState(
                    icon: Icons.payment_outlined,
                    message: 'No payment modes added yet',
                    action: 'Add Payment Mode',
                    onTap: () => context.push('/add-payment-mode'),
                  ),
                );
              }
              final accounts = accountsAsync.value ?? [];
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _PaymentModeItem(
                    mode: modes[i],
                    accountName: _accountName(accounts, modes[i].accountId),
                    onDelete: () => _deletePaymentMode(modes[i]),
                  ),
                  childCount: modes.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  String _accountName(List<Account> accounts, String? accountId) {
    if (accountId == null) return '';
    try {
      return accounts.firstWhere((a) => a.id == accountId).title;
    } catch (_) {
      return '';
    }
  }

  Future<void> _deleteAccount(Account account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: Text('Delete "${account.title}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .deleteAccount(user.uid, account.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
      }
    }
  }

  Future<void> _deletePaymentMode(PaymentMode mode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Payment Mode?'),
        content: Text('Delete "${mode.title}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
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
    final user = ref.read(authStateProvider).value;
    if (user == null) return;
    try {
      await ref
          .read(firestoreServiceProvider)
          .deletePaymentMode(user.uid, mode.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete payment mode: $e')),
        );
      }
    }
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onDelete;

  const _AccountCard({required this.account, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    // Generate a consistent gradient based on bank name
    final hue =
        (account.bankName.codeUnits.fold(0, (a, b) => a + b) % 60) + 220;
    final color1 = HSLColor.fromAHSL(1, hue.toDouble(), 0.6, 0.25).toColor();
    final color2 =
        HSLColor.fromAHSL(1, (hue + 30).toDouble(), 0.7, 0.15).toColor();

    return GestureDetector(
      onLongPress: onDelete,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color1, color2],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: color2.withOpacity(0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(account.title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const Spacer(),
                Text(account.bankName,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12)),
              ],
            ),
            const Spacer(),
            Text('•• ${account.lastSixDigits}',
                style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    letterSpacing: 4)),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(account.holderName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12)),
                ),
                Text(
                  CurrencyFormatter.format(account.balance,
                      currency: account.currency),
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
      ),
    );
  }
}

class _AddAccountCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddAccountCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.indigo500.withOpacity(0.4),
            style: BorderStyle.solid,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline,
                color: AppColors.indigo400, size: 32),
            SizedBox(height: 8),
            Text('Add Account',
                style: TextStyle(
                    color: AppColors.indigo400,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _PaymentModeItem extends StatelessWidget {
  final PaymentMode mode;
  final String accountName;
  final VoidCallback onDelete;

  const _PaymentModeItem({
    required this.mode,
    required this.accountName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dismissible(
      key: Key(mode.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.expenseRedDark,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
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
              child: const Icon(Icons.payment_outlined,
                  color: AppColors.indigo400, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mode.title, style: theme.textTheme.titleMedium),
                  Text(mode.type.label, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (accountName.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.indigo500.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(accountName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.indigo400,
                    )),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final String action;
  final VoidCallback onTap;

  const _EmptyState({
    required this.icon,
    required this.message,
    required this.action,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(icon,
              size: 48,
              color: theme.colorScheme.onSurface.withOpacity(0.3)),
          const SizedBox(height: 12),
          Text(message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
              )),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    );
  }
}
