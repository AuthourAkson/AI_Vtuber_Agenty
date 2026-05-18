import 'dart:convert';
import 'dart:io';

/// Persisted appearance preferences for the MultiAgent settings page.
/// Saved as JSON at D:\AiVtuber_Agent_profile\appearance_prefs.json
class AppearancePrefs {
  static const _path = r'D:\AiVtuber_Agent_profile\appearance_prefs.json';

  // ─── Fields ────────────────────────────────────────────

  /// true = dark mode, false = light mode (default: true)
  bool darkMode;

  /// Font size multiplier applied app-wide (default: 14, range: 12-20)
  double fontSize;

  /// Index into the 16-color theme palette (default: 0 = Blue)
  int themeColorIndex;

  /// Index into the background pattern list (default: 0 = None/Solid)
  int bgPatternIndex;

  /// Path to a custom background image file, or null for none
  String? bgImagePath;

  /// Whether the background image is active. When false, falls back to pattern/solid.
  /// (default: true — image shows immediately when set)
  bool bgImageEnabled;

  /// Whether the startup transition animation is enabled (default: false)
  bool startupAnimEnabled;

  /// Whether theme color overrides are active. When false, uses default Blue. (default: true)
  bool themeColorEnabled;

  // ─── Constructor ───────────────────────────────────────

  AppearancePrefs({
    this.darkMode = true,
    this.fontSize = 14.0,
    this.themeColorIndex = 0,
    this.bgPatternIndex = 0,
    this.bgImagePath,
    this.bgImageEnabled = true,
    this.startupAnimEnabled = false,
    this.themeColorEnabled = true,
  });

  // ─── 16-color theme palette ────────────────────────────

  /// Each entry: (label, primaryColor in hex)
  static const List<({String label, int color})> themeColors = [
    (label: 'Blue',     color: 0xFF6B8DFF),
    (label: 'Purple',   color: 0xFFA855F7),
    (label: 'Pink',     color: 0xFFEC4899),
    (label: 'Red',      color: 0xFFEF4444),
    (label: 'Orange',   color: 0xFFF97316),
    (label: 'Amber',    color: 0xFFF59E0B),
    (label: 'Yellow',   color: 0xFFEAB308),
    (label: 'Lime',     color: 0xFF84CC16),
    (label: 'Green',    color: 0xFF22C55E),
    (label: 'Emerald',  color: 0xFF10B981),
    (label: 'Teal',     color: 0xFF14B8A6),
    (label: 'Cyan',     color: 0xFF06B6D4),
    (label: 'Sky',      color: 0xFF0EA5E9),
    (label: 'Indigo',   color: 0xFF6366F1),
    (label: 'Rose',     color: 0xFFF43F5E),
    (label: 'Slate',    color: 0xFF64748B),
  ];

  /// The currently selected theme color.
  int get selectedThemeColor =>
      (themeColorIndex >= 0 && themeColorIndex < themeColors.length)
          ? themeColors[themeColorIndex].color
          : themeColors[0].color;

  // ─── Background patterns ───────────────────────────────

  /// Pattern labels + internal identifiers.
  /// Index 0 = None (solid background).
  static const List<({String label, String id, String previewChar})> bgPatterns = [
    (label: 'None',     id: 'none',        previewChar: '■'),
    (label: 'Dots',     id: 'dots',        previewChar: '•'),
    (label: 'Grid',     id: 'grid',        previewChar: '⊞'),
    (label: 'Diagonal', id: 'diagonal',    previewChar: '╱'),
    (label: 'Lines',    id: 'lines',       previewChar: '≡'),
    (label: 'Cross',    id: 'crosshatch',  previewChar: '┼'),
    (label: 'Zigzag',   id: 'zigzag',      previewChar: '⏚'),
    (label: 'Waves',    id: 'waves',       previewChar: '～'),
    (label: 'Hexagon',  id: 'hexagon',     previewChar: '⬡'),
    (label: 'Circles',  id: 'circles',     previewChar: '⊙'),
    (label: 'Triangles',id: 'triangles',   previewChar: '▷'),
    (label: 'Diamonds', id: 'diamonds',    previewChar: '◇'),
    (label: 'Chess',    id: 'chess',       previewChar: '▦'),
  ];

  // ─── Persistence ───────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'darkMode': darkMode,
    'fontSize': fontSize,
    'themeColorIndex': themeColorIndex,
    'bgPatternIndex': bgPatternIndex,
    'bgImagePath': bgImagePath,
    'bgImageEnabled': bgImageEnabled,
    'startupAnimEnabled': startupAnimEnabled,
    'themeColorEnabled': themeColorEnabled,
  };

  factory AppearancePrefs.fromJson(Map<String, dynamic> json) {
    return AppearancePrefs(
      darkMode: json['darkMode'] as bool? ?? true,
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
      themeColorIndex: json['themeColorIndex'] as int? ?? 0,
      bgPatternIndex: json['bgPatternIndex'] as int? ?? 0,
      bgImagePath: json['bgImagePath'] as String?,
      bgImageEnabled: json['bgImageEnabled'] as bool? ?? true,
      startupAnimEnabled: json['startupAnimEnabled'] as bool? ?? false,
      themeColorEnabled: json['themeColorEnabled'] as bool? ?? true,
    );
  }

  /// Load from disk. Returns defaults if file missing or corrupt.
  static AppearancePrefs load() {
    try {
      final file = File(_path);
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        return AppearancePrefs.fromJson(raw);
      }
    } catch (_) {}
    return AppearancePrefs();
  }

  /// Save to disk atomically.
  void save() {
    try {
      final file = File(_path);
      file.parent.createSync(recursive: true);
      final tmp = File('${_path}.tmp');
      tmp.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(toJson()));
      tmp.renameSync(_path);
    } catch (_) {}
  }

  /// Create a copy with overridden fields.
  AppearancePrefs copyWith({
    bool? darkMode,
    double? fontSize,
    int? themeColorIndex,
    int? bgPatternIndex,
    String? bgImagePath,
    bool? startupAnimEnabled,
    bool clearBgImage = false,
    bool? themeColorEnabled,
    bool? bgImageEnabled,
  }) {
    return AppearancePrefs(
      darkMode: darkMode ?? this.darkMode,
      fontSize: fontSize ?? this.fontSize,
      themeColorIndex: themeColorIndex ?? this.themeColorIndex,
      bgPatternIndex: bgPatternIndex ?? this.bgPatternIndex,
      bgImagePath: clearBgImage ? null : (bgImagePath ?? this.bgImagePath),
      startupAnimEnabled: startupAnimEnabled ?? this.startupAnimEnabled,
      themeColorEnabled: themeColorEnabled ?? this.themeColorEnabled,
      bgImageEnabled: bgImageEnabled ?? this.bgImageEnabled,
    );
  }
}
