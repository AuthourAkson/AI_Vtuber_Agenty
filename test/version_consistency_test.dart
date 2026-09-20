import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_vtuber_agent/services/app_version.dart';

/// Guards the "single source of truth" version scheme:
/// the only place a release version is written is `pubspec.yaml`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersion', () {
    test('parses semver and build number from a pubspec document', () {
      expect(AppVersion.parse('name: x\nversion: 2.3.4+7\n'), isTrue);
      expect(AppVersion.semver, '2.3.4');
      expect(AppVersion.build, '7');
      expect(AppVersion.full, '2.3.4+7');
      expect(AppVersion.tagged, 'v2.3.4');
    });

    test('handles a version without build number', () {
      expect(AppVersion.parse('version: 1.2.0\n'), isTrue);
      expect(AppVersion.semver, '1.2.0');
      expect(AppVersion.build, isEmpty);
      expect(AppVersion.full, '1.2.0');
    });

    test('ignores nested version keys and trailing comments', () {
      expect(
        AppVersion.parse('name: x\nversion: 9.9.9  # release\ndeps:\n  a:\n    version: 0.0.1\n'),
        isTrue,
      );
      expect(AppVersion.semver, '9.9.9');
    });

    test('reports failure when no top-level version exists', () {
      expect(AppVersion.parse('name: x\ndeps:\n  a:\n    version: 1.0.0\n'), isFalse);
    });

    test('pubspec.yaml on disk matches what the app bundle serves', () async {
      final onDisk = File('pubspec.yaml').readAsStringSync();

      final match = RegExp(
        r'^version:[ \t]*([^\s#]+)',
        multiLine: true,
      ).firstMatch(onDisk);
      expect(match, isNotNull, reason: 'pubspec.yaml must declare a version');

      final bundled = await rootBundle.loadString(AppVersion.assetPath);
      expect(bundled, onDisk,
          reason: 'pubspec.yaml must be registered under flutter.assets');

      await AppVersion.load();
      expect(AppVersion.full, match!.group(1)!.trim(),
          reason: 'AppVersion must reflect pubspec.yaml — never hardcode it elsewhere');
    });
  });
}
