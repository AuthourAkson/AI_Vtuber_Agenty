import 'package:flutter/services.dart' show rootBundle;

/// Single source of truth for the application version.
///
/// `pubspec.yaml` is registered as a Flutter asset, so the real `version:`
/// field is read at runtime. Releasing a new build therefore only requires
/// editing `version:` in `pubspec.yaml` — there is no second constant to keep
/// in sync (see `test/version_consistency_test.dart`, which guards this).
class AppVersion {
  AppVersion._();

  /// Asset path of the bundled pubspec.
  static const String assetPath = 'pubspec.yaml';

  /// Used before [load] completes, or if the asset cannot be parsed.
  static const String fallback = '1.0.0';

  static String _semver = fallback;
  static String _build = '';

  /// Semantic version without the build suffix, e.g. `1.0.0`.
  static String get semver => _semver;

  /// Build number from the `+N` suffix, empty when absent.
  static String get build => _build;

  /// Version exactly as written in `pubspec.yaml`, e.g. `1.0.0+1`.
  static String get full => _build.isEmpty ? _semver : '$_semver+$_build';

  /// Version prefixed with `v`, e.g. `v1.0.0` (used for release comparison).
  static String get tagged => 'v$semver';

  /// Loads the version from the bundled `pubspec.yaml`. Never throws —
  /// failures keep the previous value (initially [fallback]).
  static Future<void> load() async {
    try {
      parse(await rootBundle.loadString(assetPath));
    } catch (_) {
      // Keep the fallback version; a version string must never break startup.
    }
  }

  /// Parses the top-level `version:` field of a pubspec document.
  /// Returns `true` when a version was found and applied.
  static bool parse(String pubspecText) {
    final match = RegExp(
      r'^version:[ \t]*([^\s#]+)',
      multiLine: true,
    ).firstMatch(pubspecText);
    if (match == null) return false;

    final raw = match.group(1)!.trim();
    if (raw.isEmpty) return false;

    final parts = raw.split('+');
    _semver = parts.first;
    _build = parts.length > 1 ? parts[1] : '';
    return true;
  }
}
