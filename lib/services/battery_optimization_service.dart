import 'package:flutter/services.dart';

class BatteryOptimizationService {
  static const _channel = MethodChannel('com.matrimpathak.ledger/battery');

  /// Returns true if battery optimization is already disabled for this app.
  static Future<bool> isIgnoring() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
    } catch (_) {
      return true; // Non-Android: no restriction
    }
  }

  /// Opens the system dialog to disable battery optimization for this app.
  static Future<void> requestIgnore() async {
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (_) {}
  }
}
