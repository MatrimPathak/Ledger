import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/ai/claude_service.dart';
import '../core/constants/app_constants.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';
import 'accounts_provider.dart';
import '../models/transaction.dart' as app_model;
import '../models/subscription.dart' as sub_model;
import 'subscriptions_provider.dart';

final analyticsInsightsProvider =
    FutureProvider<List<AnalyticsInsight>>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return [];

  final firestoreService = ref.watch(firestoreServiceProvider);
  final transactions =
      await firestoreService.fetchTransactionsForAnalytics(user.uid, 90);
  final accounts = await ref.read(accountsProvider.future);

  if (transactions.isEmpty) {
    return [
      const AnalyticsInsight(
        title: 'Add your first transaction',
        body:
            'Start tracking your expenses to get AI-powered insights on your spending patterns.',
        type: 'neutral',
      )
    ];
  }

  // Aggregate transaction data to minimize Claude API tokens
  final summary = buildAnalyticsSummary(transactions);
  final currency = accounts.isNotEmpty ? accounts.first.currency : 'INR';

  const storage = FlutterSecureStorage();
  final secureKey =
      await storage.read(key: AppConstants.prefKeyClaudeApiKey);
  final prefs = await SharedPreferences.getInstance();
  final rawKey = secureKey ??
      prefs.getString(AppConstants.prefKeyClaudeApiKey) ??
      AppConstants.claudeApiKeyPlaceholder;
  final apiKey = rawKey.trim().isEmpty
      ? AppConstants.claudeApiKeyPlaceholder
      : rawKey.trim();

  // Fast-path: return a friendly card without constructing ClaudeService.
  // ClaudeService.generateInsightsOrThrow has the same guard, but checking
  // here avoids an unnecessary object allocation and keeps the provider
  // responsible for the "key not configured" user-facing message.
  if (apiKey == AppConstants.claudeApiKeyPlaceholder || apiKey.isEmpty) {
    return [
      const AnalyticsInsight(
        title: 'Add your Claude API key',
        body: 'Go to Settings → Claude API Key and enter your key from console.anthropic.com.',
        type: 'tip',
      )
    ];
  }

  final claudeService = ClaudeService(apiKey);
  final results = await claudeService.generateInsightsOrThrow(
    transactionSummary: summary,
    currency: currency,
  );
  return results;
});

/// Transaction categories that move money between the user's own
/// accounts/instruments rather than representing real spend or income —
/// excluded from every analytics aggregate so a credit-card bill payment or
/// an account-to-account transfer never inflates (or deflates) the numbers
/// Claude reasons about.
const _nonSpendTxnCategories = {
  app_model.TxnCategory.transfer,
  app_model.TxnCategory.creditCardPayment,
  app_model.TxnCategory.adjustment,
};

@visibleForTesting
List<Map<String, dynamic>> buildAnalyticsSummary(
    List<app_model.Transaction> transactions) {
  double totalExpense = 0;
  double totalIncome = 0;
  var countedTransactions = 0;
  final categoryTotals = <String, double>{};
  final merchantCounts = <String, int>{};

  for (final tx in transactions) {
    if (_nonSpendTxnCategories.contains(tx.txnCategory)) continue;
    countedTransactions++;

    if (tx.type == app_model.TransactionType.expense) {
      totalExpense += tx.amount;
      categoryTotals[tx.categoryId] =
          (categoryTotals[tx.categoryId] ?? 0) + tx.amount;
    } else {
      totalIncome += tx.amount;
    }
    merchantCounts[tx.title] = (merchantCounts[tx.title] ?? 0) + 1;
  }

  return [
    {
      'period': 'last_90_days',
      'totalExpense': totalExpense,
      'totalIncome': totalIncome,
      'netSavings': totalIncome - totalExpense,
      'savingsRate': totalIncome > 0
          ? ((totalIncome - totalExpense) / totalIncome)
          : 0,
      'transactionCount': countedTransactions,
      'categoryBreakdown': categoryTotals.entries
          .map((e) => {'categoryId': e.key, 'total': e.value})
          .toList(),
      'topMerchants': merchantCounts.entries
          .toList()
          .sorted((a, b) => b.value.compareTo(a.value))
          .take(5)
          .map((e) => {'name': e.key, 'count': e.value})
          .toList(),
      'subscriptionsSummary': _buildSubscriptionsSummary(transactions),
    }
  ];
}

/// Folds locally-detected recurring patterns into the same aggregated JSON
/// already sent to Claude for insights — reuses the existing detection
/// pipeline (`detectSubscriptions`) rather than issuing a second AI call or
/// duplicating any logic.
Map<String, dynamic> _buildSubscriptionsSummary(
    List<app_model.Transaction> transactions) {
  final detected = detectSubscriptions('_analytics', transactions);
  int countOf(sub_model.SubscriptionKind kind) =>
      detected.where((s) => s.kind == kind).length;

  return {
    'subscriptionCount': countOf(sub_model.SubscriptionKind.subscription),
    'recurringBillCount': countOf(sub_model.SubscriptionKind.recurringBill),
    'recurringIncomeCount':
        countOf(sub_model.SubscriptionKind.recurringIncome),
    'recurringTransferCount':
        countOf(sub_model.SubscriptionKind.recurringTransfer),
    'items': detected
        .map((s) => {
              'name': s.displayName,
              'kind': s.kind.name,
              'expectedAmount': s.expectedAmount,
              'intervalDays': s.intervalDays,
            })
        .toList(),
  };
}

extension _ListExt<T> on List<T> {
  List<T> sorted(int Function(T, T) compare) {
    final list = List<T>.from(this);
    list.sort(compare);
    return list;
  }
}
