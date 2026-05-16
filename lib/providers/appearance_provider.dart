import 'package:flutter/foundation.dart';
import '../models/appearance_prefs.dart';

/// Global appearance state — loaded once at startup, notifies all listeners on change.
///
/// Usage:
///   final ap = context.watch<AppearanceProvider>();
///   Color accent = ap.accentColor;
///   bool isDark = ap.isDark;
class AppearanceProvider extends ChangeNotifier {
  AppearancePrefs _prefs = AppearancePrefs();
  bool _loaded = false;

  // ─── Getters ──────────────────────────────────────────

  AppearancePrefs get prefs => _prefs;
  bool get loaded => _loaded;
  bool get isDark => _prefs.darkMode;
  double get fontSize => _prefs.fontSize;
  int get themeColorIndex => _prefs.themeColorIndex;
  int get bgPatternIndex => _prefs.bgPatternIndex;
  String? get bgImagePath => _prefs.bgImagePath;
  bool get startupAnimEnabled => _prefs.startupAnimEnabled;

  /// The currently selected theme accent color.
  int get accentColorValue => _prefs.selectedThemeColor;

  // ─── Init ─────────────────────────────────────────────

  void load() {
    _prefs = AppearancePrefs.load();
    _loaded = true;
    notifyListeners();
  }

  // ─── Mutations ────────────────────────────────────────

  void update(AppearancePrefs next) {
    _prefs = next;
    _prefs.save();
    notifyListeners();
  }

  /// One-tap reset to factory defaults.
  void resetToDefaults() {
    _prefs = AppearancePrefs();
    _prefs.save();
    notifyListeners();
  }
}
