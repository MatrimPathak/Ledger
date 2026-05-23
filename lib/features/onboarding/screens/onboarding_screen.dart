import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/account.dart';
import '../../../models/payment_mode.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../steps/step_welcome.dart';
import '../steps/step_add_account.dart';
import '../steps/step_add_payment_mode.dart';
import '../steps/step_balance_currency.dart';
import '../steps/step_notifications.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _saving = false;

  // Collected data
  Account? _account;
  PaymentMode? _paymentMode;

  static const int _totalSteps = 5;

  void _nextPage() {
    if (_currentPage < _totalSteps - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _complete();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _complete() async {
    final user = ref.read(authStateProvider).value;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Not signed in. Please sign in again.')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final firestoreService = ref.read(firestoreServiceProvider);

      if (_account != null) {
        await firestoreService.createAccount(_account!);
      }

      // Save payment mode independently — not nested inside account block
      if (_paymentMode != null) {
        await firestoreService.createPaymentMode(_paymentMode!);
      }

      await firestoreService.markOnboardingComplete(user.uid);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Setup failed. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).value;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  if (_currentPage > 0)
                    IconButton(
                      onPressed: _prevPage,
                      icon: const Icon(Icons.arrow_back_ios, size: 18),
                      padding: EdgeInsets.zero,
                    )
                  else
                    const SizedBox(width: 40),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (_currentPage + 1) / _totalSteps,
                      backgroundColor:
                          theme.colorScheme.outline.withOpacity(0.3),
                      valueColor: const AlwaysStoppedAnimation(
                          AppColors.indigo500),
                      borderRadius: BorderRadius.circular(4),
                      minHeight: 4,
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            // Step indicator
            Text(
              'Step ${_currentPage + 1} of $_totalSteps',
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentPage = i),
                children: [
                  StepWelcome(
                    userName: user?.displayName?.split(' ').first ?? 'there',
                    onNext: _nextPage,
                  ),
                  StepAddAccount(
                    userId: user?.uid ?? '',
                    onNext: (account) {
                      if (user == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text(
                                  'Not signed in. Please sign in again.')),
                        );
                        return;
                      }
                      setState(() => _account = account);
                      _nextPage();
                    },
                    onSkip: _nextPage,
                  ),
                  StepAddPaymentMode(
                    userId: user?.uid ?? '',
                    account: _account,
                    onNext: (mode) {
                      setState(() => _paymentMode = mode);
                      _nextPage();
                    },
                    onSkip: _nextPage,
                  ),
                  StepBalanceCurrency(
                    account: _account,
                    onNext: (updatedAccount) {
                      setState(() => _account = updatedAccount);
                      _nextPage();
                    },
                    onSkip: _nextPage,
                  ),
                  StepNotifications(
                    onComplete: _saving ? null : _complete,
                    isSaving: _saving,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
