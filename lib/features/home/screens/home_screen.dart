import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/account.dart';
import '../../../models/category.dart';
import '../../../models/payment_mode.dart';
import '../../../models/transaction.dart';
import '../../../providers/accounts_provider.dart';
import '../../../providers/battery_opt_provider.dart';
import '../../../providers/categories_provider.dart';
import '../../../providers/payment_modes_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/transactions_provider.dart';
import '../../../services/battery_optimization_service.dart';
import '../widgets/account_month_filter.dart';
import '../widgets/category_bar_chart.dart';
import '../widgets/summary_card.dart';
import '../widgets/transaction_list_item.dart';

String resolveHomeCurrency(List<Account> accounts, String? accountId) {
  if (accounts.isEmpty) return 'INR';
  if (accountId == null) return accounts.first.currency;

  return accounts
          .where((account) => account.id == accountId)
          .map((account) => account.currency)
          .firstOrNull ??
      accounts.first.currency;
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Re-check battery opt status when the user returns from system settings.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(batteryOptProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final txAsync = ref.watch(filteredTransactionsProvider);
    final accountsAsync = ref.watch(accountsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final paymentModesAsync = ref.watch(paymentModesProvider);
    final filter = ref.watch(transactionFilterProvider);

    final accounts = accountsAsync.value ?? [];
    final categories = categoriesAsync.value ?? [];
    final paymentModes = paymentModesAsync.value ?? [];
    final currency = resolveHomeCurrency(accounts, filter.accountId);
    final settings = ref.watch(settingsProvider);
    final batteryOptAsync = ref.watch(batteryOptProvider);

    return Scaffold(
      body: txAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (transactions) {
          final grouped = _groupByDate(transactions);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                backgroundColor: theme.scaffoldBackgroundColor,
                title: const Text('Ledger',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                centerTitle: false,
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(88),
                  child: AccountMonthFilter(accounts: accounts),
                ),
              ),
              // Battery optimization warning — shown only when auto-detect
              // is on but background execution is still restricted by Android.
              if (settings.autoDetectEnabled)
                batteryOptAsync.maybeWhen(
                  data: (isIgnoring) => isIgnoring
                      ? const SliverToBoxAdapter(child: SizedBox.shrink())
                      : SliverToBoxAdapter(
                          child: _BatteryOptBanner(
                            onFix: () =>
                                BatteryOptimizationService.requestIgnore(),
                          ),
                        ),
                  orElse: () =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 12),
                  child: SummaryCard(
                    transactions: transactions,
                    accounts: accounts,
                    currency: currency,
                    filter: filter,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: CategoryBarChart(
                    transactions: transactions,
                    categories: categories,
                    currency: currency,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text('Transactions',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
              if (grouped.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined,
                            size: 56,
                            color: theme.colorScheme.onSurface.withOpacity(0.3)),
                        const SizedBox(height: 16),
                        Text('No transactions yet',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color:
                                  theme.colorScheme.onSurface.withOpacity(0.5),
                            )),
                        const SizedBox(height: 8),
                        Text('Tap + to add your first transaction',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                )
              else
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      int itemIndex = 0;
                      for (final group in grouped.entries) {
                        if (index == itemIndex) {
                          return _DateHeader(date: group.key);
                        }
                        itemIndex++;
                        for (final tx in group.value) {
                          if (index == itemIndex) {
                            return TransactionListItem(
                              transaction: tx,
                              category:
                                  _findCategory(tx.categoryId, categories),
                              paymentMode: _findPaymentMode(
                                  tx.paymentModeId, paymentModes),
                              onTap: () => context.push(
                                '/transaction/${tx.id}',
                                extra: tx,
                              ),
                            );
                          }
                          itemIndex++;
                        }
                      }
                      return null;
                    },
                    childCount: grouped.entries.fold<int>(
                      0,
                      (sum, e) => sum + 1 + e.value.length,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          );
        },
      ),
    );
  }

  Map<DateTime, List<Transaction>> _groupByDate(List<Transaction> transactions) {
    final map = <DateTime, List<Transaction>>{};
    for (final tx in transactions) {
      final day = DateTime(tx.date.year, tx.date.month, tx.date.day);
      map.putIfAbsent(day, () => []).add(tx);
    }
    return map;
  }

  Category? _findCategory(String? id, List<Category> categories) {
    if (id == null) return null;
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  PaymentMode? _findPaymentMode(String? id, List<PaymentMode> modes) {
    if (id == null) return null;
    try {
      return modes.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }
}

class _BatteryOptBanner extends StatelessWidget {
  final VoidCallback onFix;
  const _BatteryOptBanner({required this.onFix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.battery_alert_outlined,
              color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Allow background access for real-time SMS detection',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.orange[800]),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onFix,
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              foregroundColor: Colors.orange[800],
            ),
            child: const Text('Fix Now',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final DateTime date;
  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        DateFormatter.formatGroupHeader(date),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
