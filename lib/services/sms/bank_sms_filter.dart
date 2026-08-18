import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// Coarse Layer-1 prefilter — "does this even look like a bank SMS" — cheap
/// enough to run on every incoming message before any parsing/AI work.
/// Keywords are sourced from the same assets/sms_patterns/bank_patterns.json
/// the local deterministic parser (LocalSmsParser) and its Kotlin
/// counterpart use, so there is exactly one keyword list, not three
/// independently hand-copied ones.
class BankSmsFilter {
  static List<String>? _cachedKeywords;
  static List<RegExp>? _cachedWordBoundaryPatterns;

  static Future<void> _ensureLoaded() async {
    if (_cachedKeywords != null) return;
    final raw =
        await rootBundle.loadString('assets/sms_patterns/bank_patterns.json');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    _publish(decoded);
  }

  /// Test-only escape hatch to inject a rule set directly rather than
  /// loading it from the asset bundle.
  static void debugLoadFrom(Map<String, dynamic> rules) => _publish(rules);

  /// Builds both caches into locals first and only publishes them together.
  /// [_ensureLoaded] treats a non-null [_cachedKeywords] as "already
  /// loaded" and short-circuits on every later call — if the two caches
  /// were assigned one at a time and building the second one threw, that
  /// guard would permanently short-circuit with [_cachedWordBoundaryPatterns]
  /// still null, and every later call would hit a null-check error.
  static void _publish(Map<String, dynamic> rules) {
    final keywords = (rules['globalKeywords'] as List).cast<String>();
    final wordBoundaryPatterns = (rules['globalWordBoundaryKeywords'] as List)
        .cast<String>()
        .map((w) => RegExp('\\b${RegExp.escape(w)}\\b'))
        .toList();
    _cachedKeywords = keywords;
    _cachedWordBoundaryPatterns = wordBoundaryPatterns;
  }

  static Future<bool> looksLikeBankSms(String body) async {
    await _ensureLoaded();
    final lower = body.toLowerCase();
    return _cachedKeywords!.any((k) => lower.contains(k)) ||
        _cachedWordBoundaryPatterns!.any((p) => p.hasMatch(lower));
  }
}
