import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/firestore_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/accounts/screens/accounts_screen.dart';
import '../../features/accounts/screens/add_account_screen.dart';
import '../../features/accounts/screens/add_payment_mode_screen.dart';
import '../../features/accounts/screens/edit_account_screen.dart';
import '../../features/accounts/screens/edit_payment_mode_screen.dart';
import '../../features/transactions/screens/add_transaction_screen.dart';
import '../../features/transactions/screens/transaction_detail_screen.dart';
import '../../features/analytics/screens/analytics_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../widgets/main_shell.dart';
import '../../models/account.dart';
import '../../models/payment_mode.dart';
import '../../models/transaction.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authStateProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) async {
      final isLoggedIn = authState.value != null;
      final location = state.matchedLocation;

      if (!isLoggedIn) {
        return location == '/login' ? null : '/login';
      }

      if (isLoggedIn && location == '/login') {
        final firestoreService = ref.read(firestoreServiceProvider);
        final profile = await firestoreService.getProfile(authState.value!.uid);
        if (profile == null || !profile.onboardingComplete) {
          return '/onboarding';
        }
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, __) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: '/accounts',
            builder: (_, __) => const AccountsScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, __) => const AnalyticsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/add-transaction',
        builder: (context, state) {
          final tx = state.extra as Transaction?;
          return AddTransactionScreen(editTransaction: tx);
        },
      ),
      GoRoute(
        path: '/transaction/:id',
        builder: (context, state) {
          final tx = state.extra as Transaction?;
          final transactionId = state.pathParameters['id'];
          return TransactionDetailScreen(
            transaction: tx,
            transactionId: transactionId,
          );
        },
      ),
      GoRoute(
        path: '/add-account',
        builder: (_, __) => const AddAccountScreen(),
      ),
      GoRoute(
        path: '/edit-account',
        builder: (context, state) {
          final account = state.extra;
          if (account is! Account) return const AccountsScreen();
          return EditAccountScreen(account: account);
        },
      ),
      GoRoute(
        path: '/add-payment-mode',
        builder: (_, __) => const AddPaymentModeScreen(),
      ),
      GoRoute(
        path: '/edit-payment-mode',
        builder: (context, state) {
          final mode = state.extra;
          if (mode is! PaymentMode) return const AccountsScreen();
          return EditPaymentModeScreen(mode: mode);
        },
      ),
    ],
  );
});
