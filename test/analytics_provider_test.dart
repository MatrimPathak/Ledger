import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/providers/analytics_provider.dart';
import 'package:ledger/services/ai/claude_service.dart';

void main() {
  group('analyticsInsightsProvider', () {
    test('is kept alive so navigation does not discard cached insights', () {
      expect(
        analyticsInsightsProvider,
        isA<FutureProvider<List<AnalyticsInsight>>>(),
      );
      expect(
        analyticsInsightsProvider,
        isNot(isA<AutoDisposeFutureProvider<List<AnalyticsInsight>>>()),
      );
    });
  });
}
