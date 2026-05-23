import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/account.dart';
import '../../../providers/transactions_provider.dart';

class AccountMonthFilter extends ConsumerWidget {
  final List<Account> accounts;

  const AccountMonthFilter({super.key, required this.accounts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        // Month navigator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () =>
                    ref.read(transactionFilterProvider.notifier).previousMonth(),
                icon: const Icon(Icons.chevron_left),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Expanded(
                child: Text(
                  DateFormatter.formatMonth(filter.selectedMonth),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: filter.selectedMonth.month == DateTime.now().month &&
                        filter.selectedMonth.year == DateTime.now().year
                    ? null
                    : () => ref
                        .read(transactionFilterProvider.notifier)
                        .nextMonth(),
                icon: const Icon(Icons.chevron_right),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
        ),
        // Account filter chips
        SizedBox(
          height: 36,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _AccountChip(
                label: 'All Accounts',
                selected: filter.accountId == null,
                onTap: () => ref
                    .read(transactionFilterProvider.notifier)
                    .setAccount(null),
              ),
              ...accounts.map((a) => _AccountChip(
                    label: a.title,
                    selected: filter.accountId == a.id,
                    onTap: () => ref
                        .read(transactionFilterProvider.notifier)
                        .setAccount(a.id),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AccountChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.indigo500 : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.indigo500
                : Theme.of(context).colorScheme.outline,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
