import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/features/analytics/screens/analytics_screen.dart';
import 'package:ledger/providers/analytics_provider.dart';

void main() {
  testWidgets('shows analytics API errors without the Exception prefix',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsInsightsProvider.overrideWith(
            (ref) async => throw Exception(
              'Invalid API key. Please check your key in Settings.',
            ),
          ),
        ],
        child: const MaterialApp(
          home: AnalyticsScreen(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Failed to load insights'), findsOneWidget);
    expect(
      find.text('Invalid API key. Please check your key in Settings.'),
      findsOneWidget,
    );
    expect(find.textContaining('Exception:'), findsNothing);
    expect(find.text('Try Again'), findsOneWidget);
  });
}
