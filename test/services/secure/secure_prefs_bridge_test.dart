import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ledger/services/secure/secure_prefs_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.matrimpathak.ledger/secure_prefs');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('invokes the write method with the key and value', () async {
    MethodCall? captured;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });

    await SecurePrefsBridge.write('claude_api_key', 'sk-test-123');

    expect(captured, isNotNull);
    expect(captured!.method, 'write');
    expect(captured!.arguments, {'key': 'claude_api_key', 'value': 'sk-test-123'});
  });

  test('does not throw when no handler is registered (e.g. iOS/tests)',
      () async {
    await expectLater(
      SecurePrefsBridge.write('uid', 'user-1'),
      completes,
    );
  });

  test('does not throw when the platform reports an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'FAILED', message: 'boom');
    });

    await expectLater(
      SecurePrefsBridge.write('uid', 'user-1'),
      completes,
    );
  });
}
