import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/providers/transactions_provider.dart';

void main() {
  group('TransactionFilter', () {
    test('builds inclusive month boundaries for a leap-year February', () {
      final filter = TransactionFilter(
        selectedMonth: DateTime(2024, DateTime.february),
      );

      expect(filter.from, DateTime(2024, DateTime.february, 1));
      expect(
        filter.to,
        DateTime(2024, DateTime.february, 29, 23, 59, 59),
      );
    });

    test('builds inclusive month boundaries across a year rollover', () {
      final filter = TransactionFilter(
        selectedMonth: DateTime(2025, DateTime.december),
      );

      expect(filter.from, DateTime(2025, DateTime.december, 1));
      expect(
        filter.to,
        DateTime(2025, DateTime.december, 31, 23, 59, 59),
      );
    });

    test('copyWith preserves account selection unless explicitly changed', () {
      final filter = TransactionFilter(
        accountId: 'account-1',
        selectedMonth: DateTime(2025, DateTime.may),
      );

      expect(filter.copyWith().accountId, 'account-1');
      expect(filter.copyWith(accountId: () => null).accountId, isNull);
    });
  });

  group('TransactionFilterNotifier', () {
    test('previousMonth moves January to December of the previous year', () {
      final notifier = TransactionFilterNotifier()
        ..setMonth(DateTime(2025, DateTime.january));

      notifier.previousMonth();

      expect(
        notifier.state.selectedMonth,
        DateTime(2024, DateTime.december),
      );
    });

    test('nextMonth advances from a past month to the current month', () {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      final previousMonth = DateTime(now.year, now.month - 1);
      final notifier = TransactionFilterNotifier()..setMonth(previousMonth);

      notifier.nextMonth();

      expect(notifier.state.selectedMonth, currentMonth);
    });

    test('nextMonth does not advance beyond the current month', () {
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      final notifier = TransactionFilterNotifier()..setMonth(currentMonth);

      notifier.nextMonth();

      expect(notifier.state.selectedMonth, currentMonth);
    });
  });
}
