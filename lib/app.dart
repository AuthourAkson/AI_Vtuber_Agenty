import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/appearance_provider.dart';
import 'models/appearance_prefs.dart';

// ════════════════════════════════════════════════════════════
// 16 Theme Presets — complete UI color palettes
// Each preset defines both dark and light variants.
// Switching presets changes the entire app look, not just accent.
// ════════════════════════════════════════════════════════════

class ThemePreset {
  final String label;
  final int accentColor; // 0xAARRGGBB

  // ── Dark mode slots ──
  final int darkBg;
  final int darkFg;
  final int darkCard;
  final int darkSecondary;
  final int darkMutedFg;
  final int darkBorder;
  final int darkInput;
  final int darkSidebar;

  // ── Light mode slots ──
  final int lightBg;
  final int lightFg;
  final int lightCard;
  final int lightSecondary;
  final int lightMutedFg;
  final int lightBorder;
  final int lightInput;
  final int lightSidebar;

  const ThemePreset({
    required this.label,
    required this.accentColor,
    required this.darkBg,
    required this.darkFg,
    required this.darkCard,
    required this.darkSecondary,
    required this.darkMutedFg,
    required this.darkBorder,
    required this.darkInput,
    required this.darkSidebar,
    required this.lightBg,
    required this.lightFg,
    required this.lightCard,
    required this.lightSecondary,
    required this.lightMutedFg,
    required this.lightBorder,
    required this.lightInput,
    required this.lightSidebar,
  });

  // ── Derived: text color that contrasts with accent ──
  Color get onAccent {
    final c = Color(accentColor);
    final lum = 0.299 * c.red + 0.587 * c.green + 0.114 * c.blue;
    return lum > 140 ? const Color(0xFF1C1C1C) : Colors.white;
  }

  static const destructive = 0xFFCC3333;
  static const ring = 0xFF707070;

  // ═══════════════════════════════════════════════════
  // 16 Presets
  // ═══════════════════════════════════════════════════

  static const List<ThemePreset> presets = [
    // 0: Blue (default — matches original ShadColors)
    ThemePreset(
      label: 'Blue', accentColor: 0xFF6B8DFF,
      darkBg: 0xFF1A1A1A, darkFg: 0xFFF5F5F5, darkCard: 0xFF252525,
      darkSecondary: 0xFF2E2E2E, darkMutedFg: 0xFF9E9E9E,
      darkBorder: 0x1AFFFFFF, darkInput: 0x26FFFFFF, darkSidebar: 0xFF1C1C1C,
      lightBg: 0xFFF8F8F8, lightFg: 0xFF1A1A1A, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFF0F0F0, lightMutedFg: 0xFF6B6B6B,
      lightBorder: 0xFFE0E0E0, lightInput: 0xFFD8D8D8, lightSidebar: 0xFFF0F0F0,
    ),
    // 1: Purple
    ThemePreset(
      label: 'Purple', accentColor: 0xFFA855F7,
      darkBg: 0xFF18161C, darkFg: 0xFFF3EEFF, darkCard: 0xFF221F2A,
      darkSecondary: 0xFF2D2838, darkMutedFg: 0xFF9B8EBA,
      darkBorder: 0x1BCBA6FF, darkInput: 0x26CBA6FF, darkSidebar: 0xFF1A1820,
      lightBg: 0xFFF9F6FF, lightFg: 0xFF1A1328, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFF0EBFA, lightMutedFg: 0xFF6E618A,
      lightBorder: 0xFFE0D8F0, lightInput: 0xFFD8CCEE, lightSidebar: 0xFFF0EBFA,
    ),
    // 2: Pink
    ThemePreset(
      label: 'Pink', accentColor: 0xFFEC4899,
      darkBg: 0xFF1C161A, darkFg: 0xFFFFF0F5, darkCard: 0xFF282022,
      darkSecondary: 0xFF352830, darkMutedFg: 0xFFB88A9E,
      darkBorder: 0x1BFF80BF, darkInput: 0x26FF80BF, darkSidebar: 0xFF1E181C,
      lightBg: 0xFFFFF5F8, lightFg: 0xFF2A1018, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFEEF5, lightMutedFg: 0xFF8C5E70,
      lightBorder: 0xFFF5D0E0, lightInput: 0xFFEEC0D5, lightSidebar: 0xFFFFEEF5,
    ),
    // 3: Red
    ThemePreset(
      label: 'Red', accentColor: 0xFFEF4444,
      darkBg: 0xFF1C1616, darkFg: 0xFFFFF0F0, darkCard: 0xFF282020,
      darkSecondary: 0xFF352828, darkMutedFg: 0xFFBA8888,
      darkBorder: 0x1BFF6666, darkInput: 0x26FF6666, darkSidebar: 0xFF1E1818,
      lightBg: 0xFFFFF6F6, lightFg: 0xFF2A1010, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFEEEE, lightMutedFg: 0xFF8C5E5E,
      lightBorder: 0xFFF5D0D0, lightInput: 0xFFEEC0C0, lightSidebar: 0xFFFFEEEE,
    ),
    // 4: Orange
    ThemePreset(
      label: 'Orange', accentColor: 0xFFF97316,
      darkBg: 0xFF1C1814, darkFg: 0xFFFFF5EE, darkCard: 0xFF282118,
      darkSecondary: 0xFF352C20, darkMutedFg: 0xFFBA9B80,
      darkBorder: 0x1BFF944D, darkInput: 0x26FF944D, darkSidebar: 0xFF1E1A14,
      lightBg: 0xFFFFF9F5, lightFg: 0xFF2A1808, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFF0E8, lightMutedFg: 0xFF8C6E50,
      lightBorder: 0xFFF5DCC0, lightInput: 0xFFEED0A8, lightSidebar: 0xFFFFF0E8,
    ),
    // 5: Amber
    ThemePreset(
      label: 'Amber', accentColor: 0xFFF59E0B,
      darkBg: 0xFF1C1A12, darkFg: 0xFFFFF8E0, darkCard: 0xFF282316,
      darkSecondary: 0xFF352E1E, darkMutedFg: 0xFFBAAB60,
      darkBorder: 0x1BFFC033, darkInput: 0x26FFC033, darkSidebar: 0xFF1E1C12,
      lightBg: 0xFFFFFCF0, lightFg: 0xFF2A2000, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFF8E0, lightMutedFg: 0xFF8C7A30,
      lightBorder: 0xFFF5E8A0, lightInput: 0xFFEEDC80, lightSidebar: 0xFFFFF8E0,
    ),
    // 6: Yellow
    ThemePreset(
      label: 'Yellow', accentColor: 0xFFEAB308,
      darkBg: 0xFF1C1C10, darkFg: 0xFFFFFDE0, darkCard: 0xFF282814,
      darkSecondary: 0xFF35341C, darkMutedFg: 0xFFBABA40,
      darkBorder: 0x1BFFE040, darkInput: 0x26FFE040, darkSidebar: 0xFF1E1E10,
      lightBg: 0xFFFFFEF0, lightFg: 0xFF2A2800, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFFCE0, lightMutedFg: 0xFF8C8600,
      lightBorder: 0xFFF5EE80, lightInput: 0xFFEEE860, lightSidebar: 0xFFFFFCE0,
    ),
    // 7: Lime
    ThemePreset(
      label: 'Lime', accentColor: 0xFF84CC16,
      darkBg: 0xFF181C12, darkFg: 0xFFF5FFE0, darkCard: 0xFF202818,
      darkSecondary: 0xFF2C3520, darkMutedFg: 0xFFA0BA70,
      darkBorder: 0x1BA6E040, darkInput: 0x26A6E040, darkSidebar: 0xFF1A1E12,
      lightBg: 0xFFF8FFF0, lightFg: 0xFF182800, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFF0FFE0, lightMutedFg: 0xFF6E8C30,
      lightBorder: 0xFFD8F5A0, lightInput: 0xFFC8EE80, lightSidebar: 0xFFF0FFE0,
    ),
    // 8: Green
    ThemePreset(
      label: 'Green', accentColor: 0xFF22C55E,
      darkBg: 0xFF141C16, darkFg: 0xFFE8FFF0, darkCard: 0xFF1C2820,
      darkSecondary: 0xFF28352C, darkMutedFg: 0xFF80BA90,
      darkBorder: 0x1B40E070, darkInput: 0x2640E070, darkSidebar: 0xFF161E18,
      lightBg: 0xFFF2FFF6, lightFg: 0xFF0A2814, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFE0FFEE, lightMutedFg: 0xFF408C58,
      lightBorder: 0xFFB8F5D0, lightInput: 0xFFA0EEC0, lightSidebar: 0xFFE0FFEE,
    ),
    // 9: Emerald
    ThemePreset(
      label: 'Emerald', accentColor: 0xFF10B981,
      darkBg: 0xFF141C18, darkFg: 0xFFE8FFF4, darkCard: 0xFF1C2822,
      darkSecondary: 0xFF28352E, darkMutedFg: 0xFF80BAA0,
      darkBorder: 0x1B30E090, darkInput: 0x2630E090, darkSidebar: 0xFF161E1A,
      lightBg: 0xFFF2FFFA, lightFg: 0xFF082818, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFE0FFF2, lightMutedFg: 0xFF3C8C68,
      lightBorder: 0xFFB8F5D8, lightInput: 0xFFA0EEC8, lightSidebar: 0xFFE0FFF2,
    ),
    // 10: Teal
    ThemePreset(
      label: 'Teal', accentColor: 0xFF14B8A6,
      darkBg: 0xFF141C1C, darkFg: 0xFFE8FFFC, darkCard: 0xFF1C2826,
      darkSecondary: 0xFF283533, darkMutedFg: 0xFF80BAB0,
      darkBorder: 0x1B30E0D0, darkInput: 0x2630E0D0, darkSidebar: 0xFF161E1C,
      lightBg: 0xFFF2FFFC, lightFg: 0xFF082820, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFE0FFF8, lightMutedFg: 0xFF3C8C80,
      lightBorder: 0xFFB8F5EE, lightInput: 0xFFA0EEE4, lightSidebar: 0xFFE0FFF8,
    ),
    // 11: Cyan
    ThemePreset(
      label: 'Cyan', accentColor: 0xFF06B6D4,
      darkBg: 0xFF121C1E, darkFg: 0xFFE0FBFF, darkCard: 0xFF1A282A,
      darkSecondary: 0xFF263538, darkMutedFg: 0xFF70BACC,
      darkBorder: 0x1B20E0FF, darkInput: 0x2620E0FF, darkSidebar: 0xFF141E20,
      lightBg: 0xFFF0FCFF, lightFg: 0xFF082830, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFE0F8FF, lightMutedFg: 0xFF3090A0,
      lightBorder: 0xFFB8EEF5, lightInput: 0xFFA0E4EE, lightSidebar: 0xFFE0F8FF,
    ),
    // 12: Sky
    ThemePreset(
      label: 'Sky', accentColor: 0xFF0EA5E9,
      darkBg: 0xFF141A20, darkFg: 0xFFE8F4FF, darkCard: 0xFF1C242C,
      darkSecondary: 0xFF28323C, darkMutedFg: 0xFF80AACC,
      darkBorder: 0x1B30C0FF, darkInput: 0x2630C0FF, darkSidebar: 0xFF161C22,
      lightBg: 0xFFF4FAFF, lightFg: 0xFF0A2030, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFE4F4FF, lightMutedFg: 0xFF4080A0,
      lightBorder: 0xFFC0E0F5, lightInput: 0xFFAAD8EE, lightSidebar: 0xFFE4F4FF,
    ),
    // 13: Indigo
    ThemePreset(
      label: 'Indigo', accentColor: 0xFF6366F1,
      darkBg: 0xFF161820, darkFg: 0xFFEEF0FF, darkCard: 0xFF1E2030,
      darkSecondary: 0xFF2A2D40, darkMutedFg: 0xFF8E90C0,
      darkBorder: 0x1B8080FF, darkInput: 0x268080FF, darkSidebar: 0xFF181A22,
      lightBg: 0xFFF6F8FF, lightFg: 0xFF101830, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFECEEFF, lightMutedFg: 0xFF5860A0,
      lightBorder: 0xFFD0D4F5, lightInput: 0xFFC0C4EE, lightSidebar: 0xFFECEEFF,
    ),
    // 14: Rose
    ThemePreset(
      label: 'Rose', accentColor: 0xFFF43F5E,
      darkBg: 0xFF1C1618, darkFg: 0xFFFFF0F2, darkCard: 0xFF282022,
      darkSecondary: 0xFF35282C, darkMutedFg: 0xFFBA8890,
      darkBorder: 0x1BFF6080, darkInput: 0x26FF6080, darkSidebar: 0xFF1E181A,
      lightBg: 0xFFFFF6F8, lightFg: 0xFF2A1018, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFFFEEF2, lightMutedFg: 0xFF8C5E68,
      lightBorder: 0xFFF5D0D8, lightInput: 0xFFEEC0CA, lightSidebar: 0xFFFFEEF2,
    ),
    // 15: Slate
    ThemePreset(
      label: 'Slate', accentColor: 0xFF64748B,
      darkBg: 0xFF18181A, darkFg: 0xFFF0F0F2, darkCard: 0xFF222225,
      darkSecondary: 0xFF2E2E32, darkMutedFg: 0xFF909098,
      darkBorder: 0x1AFFFFFF, darkInput: 0x26FFFFFF, darkSidebar: 0xFF1A1A1C,
      lightBg: 0xFFF8F8FA, lightFg: 0xFF18181C, lightCard: 0xFFFFFFFF,
      lightSecondary: 0xFFF0F0F2, lightMutedFg: 0xFF686870,
      lightBorder: 0xFFE0E0E4, lightInput: 0xFFD4D4D8, lightSidebar: 0xFFF0F0F2,
    ),
  ];

  /// Neutral fallback — no accent color, pure grayscale. Used when Theme Color is disabled.
  static const ThemePreset neutral = ThemePreset(
    label: 'Neutral', accentColor: 0xFF888888,
    darkBg: 0xFF1A1A1A, darkFg: 0xFFF5F5F5, darkCard: 0xFF252525,
    darkSecondary: 0xFF2E2E2E, darkMutedFg: 0xFF9E9E9E,
    darkBorder: 0x1AFFFFFF, darkInput: 0x26FFFFFF, darkSidebar: 0xFF1C1C1C,
    lightBg: 0xFFF8F8F8, lightFg: 0xFF1A1A1A, lightCard: 0xFFFFFFFF,
    lightSecondary: 0xFFF0F0F0, lightMutedFg: 0xFF6B6B6B,
    lightBorder: 0xFFE0E0E0, lightInput: 0xFFD8D8D8, lightSidebar: 0xFFF0F0F0,
  );
}

// ════════════════════════════════════════════════════════════
// Dynamic theme accessor — reads AppearanceProvider.
// Returns colors from the selected ThemePreset.
// ════════════════════════════════════════════════════════════

class ShadTheme {
  final BuildContext _ctx;

  ShadTheme._(this._ctx);

  static ShadTheme of(BuildContext context) => ShadTheme._(context);

  AppearanceProvider get _ap => _ctx.read<AppearanceProvider>();
  bool get _isDark => _ap.isDark;
  ThemePreset get _preset {
    if (!_ap.themeColorEnabled) return ThemePreset.neutral;
    final i = _ap.themeColorIndex;
    final idx = (i >= 0 && i < ThemePreset.presets.length) ? i : 0;
    return ThemePreset.presets[idx];
  }

  // ── Core ──
  Color get background =>
      _isDark ? Color(_preset.darkBg) : Color(_preset.lightBg);
  Color get foreground =>
      _isDark ? Color(_preset.darkFg) : Color(_preset.lightFg);
  Color get card =>
      _isDark ? Color(_preset.darkCard) : Color(_preset.lightCard);
  Color get cardForeground => foreground;
  Color get popover => card;

  // ── Primary / secondary ──
  Color get primary => Color(_preset.accentColor);
  Color get primaryForeground => _preset.onAccent;
  Color get secondary =>
      _isDark ? Color(_preset.darkSecondary) : Color(_preset.lightSecondary);
  Color get secondaryForeground => foreground;

  // ── Muted ──
  Color get muted => secondary;
  Color get mutedForeground =>
      _isDark ? Color(_preset.darkMutedFg) : Color(_preset.lightMutedFg);

  // ── Accent ──
  Color get accent => primary;
  Color get accentForeground => primaryForeground;

  // ── Destructive ──
  Color get destructive => const Color(ThemePreset.destructive);

  // ── Border / input ──
  Color get border =>
      _isDark ? Color(_preset.darkBorder) : Color(_preset.lightBorder);
  Color get input =>
      _isDark ? Color(_preset.darkInput) : Color(_preset.lightInput);
  Color get ring => const Color(ThemePreset.ring);

  // ── Sidebar ──
  Color get sidebar =>
      _isDark ? Color(_preset.darkSidebar) : Color(_preset.lightSidebar);
  Color get sidebarForeground => foreground;
  Color get sidebarPrimary => primary;
  Color get sidebarAccent => primary;
  Color get sidebarAccentForeground => primaryForeground;
  Color get sidebarBorder => border;
}

// ════════════════════════════════════════════════════════════

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppearanceProvider>(
      builder: (context, ap, _) {
        final preset = ap.themeColorEnabled
            ? ThemePreset.presets[ap.themeColorIndex]
            : ThemePreset.neutral;
        final accent = Color(preset.accentColor);
        final isDark = ap.isDark;
        final fontSize = ap.fontSize;
        final patternIndex = ap.bgPatternIndex;
        final bgImagePath = ap.bgImagePath;
        final bgImageEnabled = ap.bgImageEnabled;

        return MaterialApp(
          title: 'AI VTuber Agent',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(isDark, accent, fontSize, preset),
          home: AppShell(
            accent: accent,
            isDark: isDark,
            bgPatternIndex: patternIndex,
            bgImagePath: bgImagePath,
            bgImageEnabled: bgImageEnabled,
            preset: preset,
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(
      bool isDark, Color accent, double fontSize, ThemePreset preset) {
    final bg = isDark ? Color(preset.darkBg) : Color(preset.lightBg);
    final fg = isDark ? Color(preset.darkFg) : Color(preset.lightFg);
    final card = isDark ? Color(preset.darkCard) : Color(preset.lightCard);
    final secondary =
        isDark ? Color(preset.darkSecondary) : Color(preset.lightSecondary);
    final mutedFg =
        isDark ? Color(preset.darkMutedFg) : Color(preset.lightMutedFg);
    final bdr = isDark ? Color(preset.darkBorder) : Color(preset.lightBorder);
    final inp = isDark ? Color(preset.darkInput) : Color(preset.lightInput);

    final baseText = TextStyle(
      fontSize: fontSize,
      color: fg,
    );

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: accent,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        secondary: accent,
        surface: card,
        error: const Color(ThemePreset.destructive),
        onPrimary: preset.onAccent,
        onSecondary: preset.onAccent,
        onSurface: fg,
        onError: Colors.white,
      ),
      cardColor: card,
      dividerColor: bdr,
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: fg,
      ),
      textTheme: TextTheme(
        bodyLarge: baseText,
        bodyMedium: baseText,
        bodySmall: TextStyle(fontSize: fontSize - 2, color: mutedFg),
        titleLarge:
            TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.w600, color: fg),
        titleMedium:
            TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.w600, color: fg),
        titleSmall:
            TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
        labelLarge:
            TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: fg),
        labelMedium: TextStyle(fontSize: fontSize - 1, color: mutedFg),
        labelSmall:
            TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.w600, color: mutedFg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: inp),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: TextStyle(color: mutedFg, fontSize: fontSize),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: preset.onAccent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: inp),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: TextStyle(fontSize: fontSize),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return mutedFg;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent.withAlpha(80);
          return bdr;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: secondary,
        thumbColor: accent,
        overlayColor: accent.withAlpha(40),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(isDark ? 80 : 20), blurRadius: 8)
          ],
        ),
        textStyle: TextStyle(color: fg, fontSize: fontSize - 2),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: accent.withAlpha(60),
        cursorColor: accent,
        selectionHandleColor: accent,
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// AppShell with dynamic background (pattern / image / solid)
// ════════════════════════════════════════════════════════════

class AppShell extends StatelessWidget {
  final Color accent;
  final bool isDark;
  final int bgPatternIndex;
  final String? bgImagePath;
  final bool bgImageEnabled;
  final ThemePreset preset;

  const AppShell({
    super.key,
    required this.accent,
    required this.isDark,
    required this.bgPatternIndex,
    this.bgImagePath,
    required this.bgImageEnabled,
    required this.preset,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? Color(preset.darkBg) : Color(preset.lightBg);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // ── Background layer ──
            Positioned.fill(child: _buildBackground(bg)),
            // ── Content ──
            Column(
              children: [
                _buildTitleBar(bg),
                Expanded(child: HomeScreen()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Color fallback) {
    if (bgImageEnabled && bgImagePath != null) {
      final file = File(bgImagePath!);
      if (file.existsSync()) {
        return Image.file(
          file,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _patternOrSolid(fallback),
        );
      }
    }
    return _patternOrSolid(fallback);
  }

  Widget _patternOrSolid(Color fallback) {
    if (bgPatternIndex == 0) {
      return Container(color: fallback);
    }
    final ptnColor = isDark
        ? accent.withAlpha(28)
        : accent.withAlpha(40);
    return CustomPaint(
      foregroundPainter: _BgPatternPainter(
        pattern: bgPatternIndex,
        color: ptnColor,
      ),
      child: Container(color: fallback),
    );
  }

  Widget _buildTitleBar(Color bg) {
    final mutedFg = isDark
        ? Color(preset.darkMutedFg)
        : Color(preset.lightMutedFg);
    return Container(
      height: 32,
      color: bg,
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'AI VTuber Agent',
                  style: TextStyle(
                    fontSize: 12,
                    color: mutedFg.withAlpha(140),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          MinimizeWindowButton(),
          MaximizeWindowButton(),
          CloseWindowButton(),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════
// Background pattern painter
// ════════════════════════════════════════════════════════════

class _BgPatternPainter extends CustomPainter {
  final int pattern;
  final Color color;

  _BgPatternPainter({required this.pattern, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final step = 16.0;
    final w = size.width;
    final h = size.height;

    switch (pattern) {
      case 1: // Dots
        final fill = Paint()..color = color.withAlpha(40);
        for (double x = step; x < w; x += step * 2) {
          for (double y = step; y < h; y += step * 2) {
            canvas.drawCircle(Offset(x, y), 2.0, fill);
          }
        }
        break;
      case 2: // Grid
        final gp = Paint()
          ..color = color.withAlpha(30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5;
        for (double x = 0; x <= w; x += step)
          canvas.drawLine(Offset(x, 0), Offset(x, h), gp);
        for (double y = 0; y <= h; y += step)
          canvas.drawLine(Offset(0, y), Offset(w, y), gp);
        break;
      case 3: // Diagonal
        final d = step * 1.5;
        final dp = Paint()
          ..color = color.withAlpha(25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        for (double x = -h; x < w + h; x += d)
          canvas.drawLine(Offset(x, 0), Offset(x + h, h), dp);
        break;
      case 4: // Lines
        final lp = Paint()
          ..color = color.withAlpha(30)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        for (double y = step; y < h; y += step * 1.5)
          canvas.drawLine(Offset(0, y), Offset(w, y), lp);
        break;
      case 5: // Crosshatch
        final d2 = step * 1.5;
        final cp = Paint()
          ..color = color.withAlpha(20)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6;
        for (double x = -h; x < w + h; x += d2)
          canvas.drawLine(Offset(x, 0), Offset(x + h, h), cp);
        for (double x = 0; x < w + h * 2; x += d2)
          canvas.drawLine(Offset(x, 0), Offset(x - h, h), cp);
        break;
      case 6: // Zigzag
        final zp = Paint()
          ..color = color.withAlpha(25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        final d3 = step * 1.5;
        for (double y = -d3; y < h + d3 * 3; y += d3 * 3) {
          var path = Path();
          var up = true;
          for (double x = 0; x <= w; x += d3 * 1.5) {
            if (x == 0) {
              path.moveTo(x, up ? y : y + d3);
            } else {
              path.lineTo(x, up ? y : y + d3);
            }
            up = !up;
          }
          canvas.drawPath(path, zp);
        }
        break;
      case 7: // Waves
        final wp = Paint()
          ..color = color.withAlpha(25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8;
        final d4 = step * 2;
        for (double y = d4 / 2; y < h + d4; y += d4) {
          var path = Path();
          path.moveTo(0, y);
          for (double x = 0; x <= w; x += 4) {
            path.lineTo(x, y + math.sin(x / 12) * d4 / 4);
          }
          canvas.drawPath(path, wp);
        }
        break;
      case 8: // Hexagon
        _drawHexagons(canvas, w, h, step);
        break;
      case 9: // Circles
        final r2 = step * 0.7;
        final cirFill = Paint()
          ..color = color.withAlpha(20)
          ..style = PaintingStyle.fill;
        final cirStroke = Paint()
          ..color = color.withAlpha(35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6;
        for (double x = step; x < w + step; x += step * 2.5) {
          for (double y = step; y < h + step; y += step * 2.5) {
            canvas.drawCircle(Offset(x, y), r2, cirFill);
            canvas.drawCircle(Offset(x, y), r2, cirStroke);
          }
        }
        break;
      case 10: // Triangles
        _drawTriangles(canvas, w, h, step, paint);
        break;
      case 11: // Diamonds
        _drawDiamonds(canvas, w, h, step, paint);
        break;
      case 12: // Chess
        final chessFill = Paint()..style = PaintingStyle.fill;
        final d5 = step * 2;
        for (double x = 0; x < w; x += d5) {
          for (double y = 0; y < h; y += d5) {
            if (((x / d5).round() + (y / d5).round()).isEven) {
              chessFill.color = color.withAlpha(25);
              canvas.drawRect(Rect.fromLTWH(x, y, d5, d5), chessFill);
            }
          }
        }
        break;
    }
  }

  void _drawHexagons(Canvas c, double w, double h, double step) {
    final r = step * 0.8;
    final fill = Paint()
      ..color = color.withAlpha(15)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = color.withAlpha(30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final rows = (h / r / 1.5).ceil() + 2;
    final cols = (w / r / math.sqrt(3)).ceil() + 2;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cx =
            col * r * math.sqrt(3) + (row.isOdd ? r * math.sqrt(3) / 2 : 0);
        final cy = row * r * 1.5;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = i * math.pi / 3 - math.pi / 6;
          final pt = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, stroke);
      }
    }
  }

  void _drawTriangles(Canvas c, double w, double h, double step, Paint p) {
    final d = step * 2;
    final fill = Paint()
      ..color = color.withAlpha(20)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < w + d; x += d) {
      for (double y = 0; y < h + d; y += d) {
        final even = ((x / d).round() + (y / d).round()).isEven;
        final path = Path();
        final top = Offset(x + d / 2, even ? y : y + d);
        final bl = Offset(x, even ? y + d : y);
        final br = Offset(x + d, even ? y + d : y);
        path.moveTo(top.dx, top.dy);
        path.lineTo(br.dx, br.dy);
        path.lineTo(bl.dx, bl.dy);
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, p);
      }
    }
  }

  void _drawDiamonds(Canvas c, double w, double h, double step, Paint p) {
    final d = step * 2;
    final fill = Paint()
      ..color = color.withAlpha(20)
      ..style = PaintingStyle.fill;
    for (double x = 0; x < w + d; x += d) {
      for (double y = 0; y < h + d; y += d) {
        final path = Path();
        path.moveTo(x + d / 2, y);
        path.lineTo(x + d, y + d / 2);
        path.lineTo(x + d / 2, y + d);
        path.lineTo(x, y + d / 2);
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BgPatternPainter old) =>
      pattern != old.pattern || color != old.color;
}
