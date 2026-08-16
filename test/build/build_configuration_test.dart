import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('environment asset configuration', () {
    test('declares the local .env file as a Flutter asset', () {
      final pubspecLines = File('pubspec.yaml').readAsLinesSync();

      expect(pubspecLines, contains('  assets:'));
      expect(pubspecLines, contains('    - .env'));
    });

    test('keeps a safe template for the required .env asset', () {
      final envExample = File('.env.example');

      expect(envExample.existsSync(), isTrue);
      expect(
        envExample.readAsLinesSync(),
        contains('CLAUDE_API_KEY=YOUR_CLAUDE_API_KEY_HERE'),
      );
    });

    test('keeps local .env secrets ignored while documenting the template', () {
      final gitignoreLines = File('.gitignore').readAsLinesSync();

      expect(gitignoreLines, contains('.env'));
      expect(
        gitignoreLines.any(
          (line) =>
              line.startsWith('# Copy .env.example') &&
              line.contains('Never commit .env.'),
        ),
        isTrue,
      );
    });
  });

  group('Android build configuration', () {
    test('disables Kotlin incremental compilation for cross-drive builds', () {
      final gradlePropertiesLines =
          File('android/gradle.properties').readAsLinesSync();

      expect(gradlePropertiesLines, contains('kotlin.incremental=false'));
      expect(gradlePropertiesLines, isNot(contains('kotlin.incremental=true')));
    });
  });
}
