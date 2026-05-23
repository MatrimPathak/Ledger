import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_provider.dart';
import 'services/notification/notification_service.dart';

class LedgerApp extends ConsumerStatefulWidget {
  const LedgerApp({super.key});

  @override
  ConsumerState<LedgerApp> createState() => _LedgerAppState();
}

class _LedgerAppState extends ConsumerState<LedgerApp> {
  StreamSubscription<String>? _notificationSub;

  @override
  void initState() {
    super.initState();
    // Listen for notification taps and navigate to the relevant transaction.
    _notificationSub = NotificationService.onNotificationTap.listen((txId) {
      final router = ref.read(routerProvider);
      router.push('/transaction/$txId');
    });
  }

  @override
  void dispose() {
    _notificationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Ledger',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: settings.themeMode,
      routerConfig: router,
    );
  }
}
