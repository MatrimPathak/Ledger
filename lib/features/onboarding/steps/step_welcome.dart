import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class StepWelcome extends StatelessWidget {
  final String userName;
  final VoidCallback onNext;

  const StepWelcome({super.key, required this.userName, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.indigo500, AppColors.indigo700],
              ),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: AppColors.indigo500.withOpacity(0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 52,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Welcome, $userName!',
            style: theme.textTheme.headlineLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            "Let's set up Ledger in a few quick steps.\nTrack every rupee, effortlessly.",
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.6),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Feature highlights
          ..._features.map(
            (f) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.indigo500.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(f['icon'] as IconData,
                        color: AppColors.indigo400, size: 20),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f['title'] as String,
                            style: theme.textTheme.titleMedium),
                        Text(f['subtitle'] as String,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 3),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: onNext,
              child: const Text('Get Started'),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static const _features = [
    {
      'icon': Icons.bar_chart,
      'title': 'Smart Tracking',
      'subtitle': 'Auto-categorize and analyze your spending',
    },
    {
      'icon': Icons.sms_outlined,
      'title': 'Auto SMS Detection',
      'subtitle': 'Transactions added automatically from bank SMS',
    },
    {
      'icon': Icons.auto_awesome_outlined,
      'title': 'AI Insights',
      'subtitle': 'Personalized financial advice powered by Claude',
    },
  ];
}
