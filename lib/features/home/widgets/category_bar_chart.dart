import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/category.dart';
import '../../../models/transaction.dart';

class CategoryBarChart extends StatelessWidget {
  final List<Transaction> transactions;
  final List<Category> categories;
  final String currency;

  const CategoryBarChart({
    super.key,
    required this.transactions,
    required this.categories,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Aggregate expenses by category
    final Map<String, double> categoryTotals = {};
    for (final tx in transactions) {
      if (tx.type == TransactionType.expense) {
        categoryTotals[tx.categoryId] =
            (categoryTotals[tx.categoryId] ?? 0) + tx.amount;
      }
    }

    if (categoryTotals.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outline),
        ),
        child: Center(
          child: Text(
            'No expenses this month',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
        ),
      );
    }

    // Sort by amount and take top 6
    final sorted = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = sorted.take(6).toList();
    final total = top.fold(0.0, (sum, e) => sum + e.value);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spending by Category', style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 16,
              child: Row(
                children: top.map((entry) {
                  final cat = _findCategory(entry.key);
                  final width = entry.value / total;
                  return Flexible(
                    flex: (width * 1000).round(),
                    child: Container(
                      color: cat?.color ?? AppColors.indigo500,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Legend
          ...top.map((entry) {
            final cat = _findCategory(entry.key);
            final pct = (entry.value / total * 100).round();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: cat?.color ?? AppColors.indigo500,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      cat?.title ?? 'Other',
                      style: theme.textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    CurrencyFormatter.formatCompact(entry.value,
                        currency: currency),
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Category? _findCategory(String id) {
    try {
      return categories.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }
}
