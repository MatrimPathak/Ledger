import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../models/category.dart';
import '../../../models/payment_mode.dart';
import '../../../models/transaction.dart';

class TransactionListItem extends StatelessWidget {
  final Transaction transaction;
  final Category? category;
  final PaymentMode? paymentMode;
  final String currency;
  final VoidCallback onTap;

  const TransactionListItem({
    super.key,
    required this.transaction,
    this.category,
    this.paymentMode,
    this.currency = 'INR',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor =
        isExpense ? AppColors.expenseRedDark : AppColors.incomeGreenDark;
    final amountPrefix = isExpense ? '-' : '+';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (category?.color ?? AppColors.indigo500).withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                category?.icon ?? Icons.more_horiz,
                color: category?.color ?? AppColors.indigo500,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // Title + details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.title,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (category != null)
                        Text(
                          category!.title,
                          style: theme.textTheme.bodySmall,
                        ),
                      if (category != null && paymentMode != null)
                        Text(' · ',
                            style: theme.textTheme.bodySmall),
                      if (paymentMode != null)
                        Text(
                          paymentMode!.title,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Amount + time
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$amountPrefix${CurrencyFormatter.format(transaction.amount, currency: currency)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: amountColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormatter.formatTime(transaction.date),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TransactionPreviewCard extends StatelessWidget {
  final Transaction transaction;
  final Category? category;
  final PaymentMode? paymentMode;

  const TransactionPreviewCard({
    super.key,
    required this.transaction,
    this.category,
    this.paymentMode,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = transaction.type == TransactionType.expense;
    final amountColor = isExpense ? AppColors.expenseRedDark : AppColors.incomeGreenDark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (category?.color ?? AppColors.indigo500).withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (category?.color ?? AppColors.indigo500).withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              category?.icon ?? Icons.more_horiz,
              color: category?.color ?? AppColors.indigo500,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title.isEmpty ? 'Transaction Title' : transaction.title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  category?.title ?? 'Category',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            '${isExpense ? '-' : '+'}${CurrencyFormatter.format(transaction.amount)}',
            style: theme.textTheme.titleLarge?.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
