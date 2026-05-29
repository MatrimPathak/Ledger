import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/battery_opt_provider.dart';
import '../../../providers/firestore_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/sms/sms_service.dart';
import '../../../services/battery_optimization_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(authStateProvider).value;
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            snap: true,
            title: const Text('Settings',
                style: TextStyle(fontWeight: FontWeight.w800)),
            centerTitle: false,
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              // Profile section
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.indigo700, AppColors.indigo900],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: user?.photoURL != null
                          ? CachedNetworkImageProvider(user!.photoURL!)
                          : null,
                      backgroundColor: AppColors.indigo500,
                      child: user?.photoURL == null
                          ? Text(
                              (user?.displayName?.isNotEmpty == true
                                      ? user!.displayName![0]
                                      : '?')
                                  .toUpperCase(),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.displayName ?? 'User',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            user?.email ?? '',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Preferences
              _SectionHeader('Preferences'),
              _SettingsTile(
                icon: Icons.dark_mode_outlined,
                title: 'Dark Mode',
                subtitle: 'Toggle dark / light theme',
                trailing: Switch(
                  value: settings.themeMode == ThemeMode.dark,
                  onChanged: (_) =>
                      ref.read(settingsProvider.notifier).toggleTheme(),
                ),
              ),
              _SettingsTile(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                subtitle: 'Receive transaction alerts',
                trailing: Switch(
                  value: settings.notificationsEnabled,
                  onChanged: (v) =>
                      ref.read(settingsProvider.notifier).setNotifications(v),
                ),
              ),
              _SettingsTile(
                icon: Icons.sms_outlined,
                title: 'Auto-detect Transactions',
                subtitle: 'Read bank SMS and add transactions automatically',
                trailing: Switch(
                  value: settings.autoDetectEnabled,
                  onChanged: (v) => _toggleAutoDetect(context, ref, v),
                ),
              ),
              if (settings.autoDetectEnabled)
                ref.watch(batteryOptProvider).maybeWhen(
                  data: (isIgnoring) => _SettingsTile(
                    icon: isIgnoring
                        ? Icons.battery_charging_full_outlined
                        : Icons.battery_alert_outlined,
                    iconColor: isIgnoring ? Colors.green : Colors.orange,
                    title: 'Background Processing',
                    subtitle: isIgnoring
                        ? 'Battery optimization disabled — SMS processed immediately'
                        : 'Tap to open battery settings and disable optimization for Ledger',
                    trailing: isIgnoring
                        ? const Icon(Icons.check_circle_outline,
                            color: Colors.green)
                        : null,
                    onTap: isIgnoring
                        ? null
                        : () => BatteryOptimizationService.requestIgnore(),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              // AI
              _SectionHeader('AI'),
              _SettingsTile(
                icon: Icons.key_outlined,
                title: 'Claude API Key',
                subtitle: 'Required for AI insights',
                onTap: () => _editApiKey(context),
              ),
              // Account
              _SectionHeader('Account'),
              _SettingsTile(
                icon: Icons.logout,
                title: 'Sign Out',
                iconColor: theme.colorScheme.onSurface,
                onTap: () => _signOut(context, ref),
              ),
              _SettingsTile(
                icon: Icons.delete_forever_outlined,
                title: 'Delete Account',
                subtitle: 'Permanently delete all your data',
                iconColor: AppColors.expenseRedDark,
                titleColor: AppColors.expenseRedDark,
                onTap: () => _deleteAccount(context, ref),
              ),
              // Version footer
              const SizedBox(height: 32),
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final version = snapshot.data?.version ?? '1.0.0';
                    return Text(
                      'Ledger v$version',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withOpacity(0.3),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _editApiKey(BuildContext context) async {
    const storage = FlutterSecureStorage();
    final current =
        await storage.read(key: AppConstants.prefKeyClaudeApiKey) ?? '';

    if (!context.mounted) return;
    final ctrl = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Claude API Key'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'sk-ant-...',
            helperText: 'Get your key at console.anthropic.com',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null) return;
    await storage.write(key: AppConstants.prefKeyClaudeApiKey, value: result);
    // Mirror to SharedPreferences so the background SMS isolate can read it.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefKeyClaudeApiKey, result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API key saved')),
      );
    }
  }

  Future<void> _toggleAutoDetect(
      BuildContext context, WidgetRef ref, bool value) async {
    if (value) {
      final granted = await SmsService().requestPermissions();
      if (!granted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('SMS permission required for auto-detection')),
          );
        }
        return;
      }
      await ref.read(settingsProvider.notifier).setAutoDetect(true);
      SmsService().startListening();
      // Automatically disable battery optimization so the SMS background
      // handler can make network calls immediately — no Doze delay.
      if (context.mounted) {
        final isIgnoring = await BatteryOptimizationService.isIgnoring();
        if (!isIgnoring) {
          await BatteryOptimizationService.requestIgnore();
        }
      }
    } else {
      await ref.read(settingsProvider.notifier).setAutoDetect(false);
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign Out?'),
        content: const Text('You will be returned to the login screen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(authServiceProvider).signOut();
      if (context.mounted) context.go('/login');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to sign out: $e')),
        );
      }
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
            'This will permanently delete ALL your data including transactions, accounts, and categories. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
                foregroundColor: AppColors.expenseRedDark),
            child: const Text('Delete Everything'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      await ref.read(authServiceProvider).deleteAccount();
      await ref.read(firestoreServiceProvider).deleteAllUserData(user.uid);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete account: $e')),
        );
        return;
      }
    }
    if (context.mounted) context.go('/login');
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? titleColor;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: iconColor ?? theme.colorScheme.onSurface),
      title: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(color: titleColor),
      ),
      subtitle: subtitle != null
          ? Text(subtitle!, style: theme.textTheme.bodySmall)
          : null,
      trailing: trailing ??
          (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }
}
