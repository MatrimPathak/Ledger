import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';

class SettingsState {
  final ThemeMode themeMode;
  final bool notificationsEnabled;
  final bool autoDetectEnabled;

  /// Whether the notification-correlation feature is enabled at all — a
  /// separate gate from the OS-level notification-access permission
  /// (checked live via [NotificationListenerBridge.isAccessGranted]). Off
  /// by default until soaked; even with access granted, no suggestion
  /// chip is shown unless this is also on.
  final bool correlationEnabled;

  const SettingsState({
    this.themeMode = ThemeMode.dark,
    this.notificationsEnabled = true,
    this.autoDetectEnabled = false,
    this.correlationEnabled = false,
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    bool? notificationsEnabled,
    bool? autoDetectEnabled,
    bool? correlationEnabled,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        autoDetectEnabled: autoDetectEnabled ?? this.autoDetectEnabled,
        correlationEnabled: correlationEnabled ?? this.correlationEnabled,
      );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeModeIndex =
        prefs.getInt(AppConstants.prefKeyThemeMode) ?? 0; // 0=dark, 1=light
    state = state.copyWith(
      themeMode: themeModeIndex == 1 ? ThemeMode.light : ThemeMode.dark,
      notificationsEnabled:
          prefs.getBool(AppConstants.prefKeyNotifications) ?? true,
      autoDetectEnabled:
          prefs.getBool(AppConstants.prefKeyAutoDetect) ?? false,
      correlationEnabled:
          prefs.getBool(AppConstants.prefKeyCorrelationEnabled) ?? false,
    );
  }

  Future<void> toggleTheme() async {
    final newMode = state.themeMode == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    state = state.copyWith(themeMode: newMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
        AppConstants.prefKeyThemeMode, newMode == ThemeMode.dark ? 0 : 1);
  }

  Future<void> setNotifications(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefKeyNotifications, value);
  }

  Future<void> setAutoDetect(bool value) async {
    state = state.copyWith(autoDetectEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefKeyAutoDetect, value);
  }

  Future<void> setCorrelationEnabled(bool value) async {
    state = state.copyWith(correlationEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefKeyCorrelationEnabled, value);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, SettingsState>(
        (ref) => SettingsNotifier());
