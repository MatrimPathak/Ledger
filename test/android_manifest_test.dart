import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registers the another_telephony SMS receiver for auto-detect', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

    expect(
      manifest,
      contains(
        'android:name="com.shounakmulay.telephony.sms.IncomingSmsReceiver"',
      ),
    );
    expect(
      manifest,
      isNot(contains('android:name="com.matrimpathak.ledger.SmsReceiver"')),
    );
  });
}
