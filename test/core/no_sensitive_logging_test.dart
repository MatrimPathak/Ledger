import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the Phase 7 security sweep: no code path may print
/// or log the sensitive identifiers this app deliberately keeps out of
/// logs — raw SMS bodies, the verbatim UPI payee name, or raw notification
/// text. This only flags a logging call (print/debugPrint/Log.*/println)
/// whose own line also references one of those identifiers — it does not
/// forbid logging in general.
void main() {
  test('no print/debugPrint/Log call references a sensitive identifier', () {
    final sensitiveIdentifiers = [
      'rawSms',
      'payeeRaw',
      'smsBody',
      r'sbn.notification',
      r'extras.getCharSequence',
    ];
    final loggingCall = RegExp(
        r'\b(print|debugPrint|Log\.[a-z]|println)\s*\(');

    final offenders = <String>[];
    for (final root in ['lib', 'android/app/src/main']) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue;
      final files = dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.kt'));
      for (final file in files) {
        final lines = file.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (!loggingCall.hasMatch(line)) continue;
          if (sensitiveIdentifiers.any(line.contains)) {
            offenders.add('${file.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Sensitive identifier logged:\n${offenders.join('\n')}');
  });
}
