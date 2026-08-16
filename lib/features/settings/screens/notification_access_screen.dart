import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/notification_events_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/notification/notification_listener_bridge.dart';

/// Explains exactly what notification-listener access reads and discards,
/// and links out to the system settings screen that grants/revokes it —
/// Android allows no in-app grant mechanism for this permission. Reachable
/// only from Settings, never forced during onboarding.
class NotificationAccessScreen extends ConsumerStatefulWidget {
  const NotificationAccessScreen({super.key});

  @override
  ConsumerState<NotificationAccessScreen> createState() =>
      _NotificationAccessScreenState();
}

class _NotificationAccessScreenState
    extends ConsumerState<NotificationAccessScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(notificationAccessGrantedProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final accessGranted = ref.watch(notificationAccessGrantedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notification Access')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.privacy_tip_outlined,
                        color: AppColors.indigo400),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text('What this reads',
                          style: theme.textTheme.titleMedium),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _bullet(theme,
                    'Only the app package, timestamp, and an amount pulled out of the notification text by a simple pattern match.'),
                _bullet(theme,
                    'The full notification text is read for a split second to find that amount, then thrown away — it is never stored, logged, or sent to our servers.'),
                _bullet(theme,
                    'Nothing here is written to your device\'s storage or to Firestore. Events only live in memory for a few minutes, purely to match a payment-app notification (e.g. a UPI app) to a bank SMS you already received.'),
                _bullet(theme,
                    'You confirm or reject every suggested match yourself — nothing is ever applied automatically.'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          accessGranted.when(
            data: (granted) => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: granted
                      ? AppColors.incomeGreenDark.withOpacity(0.5)
                      : theme.colorScheme.outline,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        granted
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: granted
                            ? AppColors.incomeGreenDark
                            : theme.colorScheme.onSurface.withOpacity(0.5),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          granted
                              ? 'Notification access granted'
                              : 'Notification access not granted',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await NotificationListenerBridge.openSettings();
                      },
                      child: Text(granted
                          ? 'Open system settings'
                          : 'Grant access in system settings'),
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Suggest matches from notifications',
                          style: theme.textTheme.titleMedium),
                      Text(
                        'Also requires notification access above to be granted.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.correlationEnabled,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setCorrelationEnabled(v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bullet(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 8),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurface.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
