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
        var i = 0;
        while (i < lines.length) {
          final line = lines[i];
          if (!loggingCall.hasMatch(line)) {
            i++;
            continue;
          }
          // Accumulate every line of this call through its closing
          // parenthesis — a multi-line call can place a sensitive
          // identifier on a later argument line, past what a single-line
          // check would see.
          final callLines = <String>[];
          var depth = 0;
          var started = false;
          var j = i;
          while (j < lines.length) {
            final l = lines[j];
            for (final ch in l.split('')) {
              if (ch == '(') {
                depth++;
                started = true;
              } else if (ch == ')') {
                depth--;
              }
            }
            callLines.add(l);
            j++;
            if (started && depth <= 0) break;
          }
          final callText = callLines.join('\n');
          if (sensitiveIdentifiers.any(callText.contains)) {
            offenders.add('${file.path}:${i + 1}: ${callLines.first.trim()}');
          }
          i = j;
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'Sensitive identifier logged:\n${offenders.join('\n')}');
  });
}
