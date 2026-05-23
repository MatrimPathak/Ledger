import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/sms/sms_service.dart';

class StepNotifications extends ConsumerStatefulWidget {
  final VoidCallback? onComplete;
  final bool isSaving;

  const StepNotifications({
    super.key,
    required this.onComplete,
    required this.isSaving,
  });

  @override
  ConsumerState<StepNotifications> createState() => _StepNotificationsState();
}

class _StepNotificationsState extends ConsumerState<StepNotifications> {
  final _smsService = SmsService();

  Future<void> _toggleAutoDetect(bool value) async {
    if (value) {
      final granted = await _smsService.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'SMS permission is required for auto-detection')),
          );
        }
        return;
      }
    }
    await ref.read(settingsProvider.notifier).setAutoDetect(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          Text('Almost done!', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text('Configure how Ledger notifies you',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 28),
          // Notifications toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outline),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.indigo500.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.notifications_outlined,
                      color: AppColors.indigo400),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Push Notifications',
                          style: theme.textTheme.titleMedium),
                      Text('Get alerts for your transactions',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Switch(
                  value: settings.notificationsEnabled,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setNotifications(v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Auto-detect toggle
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: settings.autoDetectEnabled
                    ? AppColors.indigo500.withOpacity(0.5)
                    : theme.colorScheme.outline,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.indigo500.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.sms_outlined,
                          color: AppColors.indigo400),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Auto-detect Transactions',
                              style: theme.textTheme.titleMedium),
                          Text('Read bank SMS & auto-add transactions',
                              style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    Switch(
                      value: settings.autoDetectEnabled,
                      onChanged: _toggleAutoDetect,
                    ),
                  ],
                ),
                if (settings.autoDetectEnabled) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.indigo500.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            color: AppColors.incomeGreenDark, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Transactions will be added automatically when a bank SMS is received — even when the app is closed.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: widget.isSaving ? null : widget.onComplete,
              child: widget.isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Start Using Ledger'),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}
