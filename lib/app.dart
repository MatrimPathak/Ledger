import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/settings_provider.dart';
import 'services/notification/notification_service.dart';
import 'services/secure/secure_prefs_bridge.dart';

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
    _notificationSub = NotificationService.onNotificationTap.listen((txId) {
      final router = ref.read(routerProvider);
      router.push('/transaction/$txId');
    });

    // Keep uid in sync with both mirrors used by pipelines that can't reach
    // FirebaseAuth directly: plaintext SharedPreferences (legacy fallback)
    // and the Keystore-backed SecurePrefsStore the native SmsProcessingWorker
    // actually reads. Without the secure mirror, a sign-in that happens
    // *after* main.dart's one-time seed (the common case — main.dart runs
    // before login on a fresh session) would never reach SecurePrefsStore,
    // and every background SMS job would silently exit for lack of a uid.
    ref.listenManual(authStateProvider, (_, next) async {
      final uid = next.valueOrNull?.uid;
      final prefs = await SharedPreferences.getInstance();
      if (uid != null) {
        await prefs.setString(AppConstants.prefKeyUid, uid);
        await SecurePrefsBridge.write(AppConstants.prefKeyUid, uid);
      } else {
        await prefs.remove(AppConstants.prefKeyUid);
        await SecurePrefsBridge.remove(AppConstants.prefKeyUid);
      }
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
