import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/battery_optimization_service.dart';

final batteryOptProvider = FutureProvider.autoDispose<bool>((ref) {
  return BatteryOptimizationService.isIgnoring();
});
