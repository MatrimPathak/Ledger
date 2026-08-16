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
    _cachedKeywords = (decoded['globalKeywords'] as List).cast<String>();
    _cachedWordBoundaryPatterns =
        (decoded['globalWordBoundaryKeywords'] as List)
            .cast<String>()
            .map((w) => RegExp('\\b$w\\b'))
            .toList();
  }

  /// Test-only escape hatch to inject a rule set directly rather than
  /// loading it from the asset bundle.
  static void debugLoadFrom(Map<String, dynamic> rules) {
    _cachedKeywords = (rules['globalKeywords'] as List).cast<String>();
    _cachedWordBoundaryPatterns = (rules['globalWordBoundaryKeywords'] as List)
        .cast<String>()
        .map((w) => RegExp('\\b$w\\b'))
        .toList();
  }

  static Future<bool> looksLikeBankSms(String body) async {
    await _ensureLoaded();
    final lower = body.toLowerCase();
    return _cachedKeywords!.any((k) => lower.contains(k)) ||
        _cachedWordBoundaryPatterns!.any((p) => p.hasMatch(lower));
  }
}
