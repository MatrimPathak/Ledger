import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/transaction.dart';
import 'auth_provider.dart';
import 'firestore_provider.dart';

class TransactionFilter {
  final String? accountId;
  final DateTime selectedMonth;

  TransactionFilter({
    this.accountId,
    DateTime? selectedMonth,
  }) : selectedMonth = selectedMonth ??
            DateTime(DateTime.now().year, DateTime.now().month);

  TransactionFilter copyWith({
    String? Function()? accountId,
    DateTime? selectedMonth,
  }) =>
      TransactionFilter(
        accountId: accountId != null ? accountId() : this.accountId,
        selectedMonth: selectedMonth ?? this.selectedMonth,
      );

  DateTime get from => DateTime(selectedMonth.year, selectedMonth.month, 1);
  DateTime get to => DateTime(selectedMonth.year, selectedMonth.month + 1, 0, 23, 59, 59);
}

final transactionFilterProvider =
    StateNotifierProvider<TransactionFilterNotifier, TransactionFilter>(
        (ref) => TransactionFilterNotifier());

class TransactionFilterNotifier extends StateNotifier<TransactionFilter> {
  TransactionFilterNotifier() : super(TransactionFilter());

  void setAccount(String? accountId) {
    state = state.copyWith(accountId: () => accountId);
  }

  void setMonth(DateTime month) {
    state = state.copyWith(selectedMonth: month);
  }

  void previousMonth() {
    final current = state.selectedMonth;
    state = state.copyWith(
        selectedMonth: DateTime(current.year, current.month - 1));
  }

  void nextMonth() {
    final current = state.selectedMonth;
    final next = DateTime(current.year, current.month + 1);
    if (next.isBefore(DateTime.now())) {
      state = state.copyWith(selectedMonth: next);
    }
  }
}

final filteredTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream<List<Transaction>>.empty();
  final filter = ref.watch(transactionFilterProvider);
  return ref.watch(firestoreServiceProvider).watchTransactions(
        user.uid,
        from: filter.from,
        to: filter.to,
        accountId: filter.accountId,
      );
});

final allTransactionsProvider = StreamProvider<List<Transaction>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream<List<Transaction>>.empty();
  return ref.watch(firestoreServiceProvider).watchTransactions(user.uid);
});
