import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/analytics_provider.dart';
import '../../../services/ai/claude_service.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final insightsAsync = ref.watch(analyticsInsightsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text('Analytics',
                style: TextStyle(fontWeight: FontWeight.w800)),
            centerTitle: false,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.indigo500.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.indigo500.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome,
                                size: 14, color: AppColors.indigo400),
                            const SizedBox(width: 4),
                            Text(
                              'Powered by Claude AI',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: AppColors.indigo400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: insightsAsync.isLoading
                            ? null
                            : () => ref.invalidate(analyticsInsightsProvider),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI Insights',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    'Based on your last 90 days of transactions',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          insightsAsync.when(
            loading: () => SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, _) => const _InsightShimmer(),
                childCount: 4,
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  children: [
                    Icon(Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.onSurface.withOpacity(0.3)),
                    const SizedBox(height: 16),
                    Text('Failed to load insights',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          ref.invalidate(analyticsInsightsProvider),
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
            data: (insights) {
              if (insights.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'No insights yet. Tap Generate to analyse your spending.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _InsightCard(insight: insights[i]),
                  childCount: insights.length,
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final AnalyticsInsight insight;

  const _InsightCard({required this.insight});

  Color get _typeColor {
    switch (insight.type) {
      case 'warning':
        return const Color(0xFFF59E0B);
      case 'positive':
        return AppColors.incomeGreenDark;
      case 'tip':
        return AppColors.indigo400;
      default:
        return AppColors.darkTextSecondary;
    }
  }

  IconData get _typeIcon {
    switch (insight.type) {
      case 'warning':
        return Icons.warning_amber_outlined;
      case 'positive':
        return Icons.trending_up;
      case 'tip':
        return Icons.lightbulb_outline;
      default:
        return Icons.info_outline;
    }
  }

  String get _typeLabel {
    switch (insight.type) {
      case 'warning':
        return 'Warning';
      case 'positive':
        return 'Positive';
      case 'tip':
        return 'Tip';
      default:
        return 'Insight';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border(
          left: BorderSide(color: _typeColor, width: 3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_typeIcon, color: _typeColor, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    insight.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _typeColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _typeLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: _typeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(insight.body,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withOpacity(0.8),
                  height: 1.5,
                )),
          ],
        ),
      ),
    );
  }
}

class _InsightShimmer extends StatelessWidget {
  const _InsightShimmer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      height: 90,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}
