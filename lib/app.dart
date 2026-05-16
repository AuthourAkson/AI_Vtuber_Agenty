import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/appearance_provider.dart';
import 'models/appearance_prefs.dart';

/// shadcn dark palette constants — matched to LocalAIVtuber2 index.css .dark variables.
/// Fallback defaults when no AppearanceProvider is available.
class ShadColors {
  ShadColors._();

  // Core
  static const background = Color(0xFF1A1A1A);
  static const foreground = Color(0xFFF5F5F5);
  static const card = Color(0xFF252525);
  static const cardForeground = Color(0xFFF5F5F5);
  static const popover = Color(0xFF252525);

  // Primary / secondary
  static const primary = Color(0xFFE8E8E8);
  static const primaryForeground = Color(0xFF1C1C1C);
  static const secondary = Color(0xFF2E2E2E);
  static const secondaryForeground = Color(0xFFF5F5F5);

  // Muted
  static const muted = Color(0xFF2E2E2E);
  static const mutedForeground = Color(0xFF9E9E9E);

  // Accent
  static const accent = Color(0xFF2E2E2E);
  static const accentForeground = Color(0xFFF5F5F5);

  // Destructive
  static const destructive = Color(0xFFCC3333);

  // Border / input
  static const border = Color(0x1AFFFFFF);
  static const input = Color(0x26FFFFFF);
  static const ring = Color(0xFF707070);

  // Sidebar
  static const sidebar = Color(0xFF1C1C1C);
  static const sidebarForeground = Color(0xFFF5F5F5);
  static const sidebarPrimary = Color(0xFF6B8DFF);
  static const sidebarAccent = Color(0xFF2E2E2E);
  static const sidebarAccentForeground = Color(0xFFF5F5F5);
  static const sidebarBorder = Color(0x1AFFFFFF);

  // ─── Light-mode palette ─────────────────────────────

  static const lightBg = Color(0xFFF8F8F8);
  static const lightFg = Color(0xFF1A1A1A);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSecondary = Color(0xFFF0F0F0);
  static const lightMutedFg = Color(0xFF6B6B6B);
  static const lightSidebar = Color(0xFFF0F0F0);
  static const lightSidebarAccent = Color(0xFFE4E4E4);
  static const lightBorder = Color(0xFFE0E0E0);
  static const lightInput = Color(0xFFD8D8D8);
}

// ════════════════════════════════════════════════════════════

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppearanceProvider>(
      builder: (context, ap, _) {
        final accent = Color(ap.accentColorValue);
        final isDark = ap.isDark;
        final fontSize = ap.fontSize;
        final patternIndex = ap.bgPatternIndex;
        final bgImagePath = ap.bgImagePath;

        return MaterialApp(
          title: 'AI VTuber Agent',
          debugShowCheckedModeBanner: false,
          theme: _buildTheme(isDark, accent, fontSize),
          home: AppShell(
            accent: accent,
            isDark: isDark,
            bgPatternIndex: patternIndex,
            bgImagePath: bgImagePath,
          ),
        );
      },
    );
  }

  ThemeData _buildTheme(bool isDark, Color accent, double fontSize) {
    final bg = isDark ? ShadColors.background : ShadColors.lightBg;
    final fg = isDark ? ShadColors.foreground : ShadColors.lightFg;
    final card = isDark ? ShadColors.card : ShadColors.lightCard;
    final secondary = isDark ? ShadColors.secondary : ShadColors.lightSecondary;
    final mutedFg = isDark ? ShadColors.mutedForeground : ShadColors.lightMutedFg;
    final bdr = isDark ? ShadColors.border : ShadColors.lightBorder;
    final inp = isDark ? ShadColors.input : ShadColors.lightInput;

    final baseText = TextStyle(
      fontSize: fontSize,
      color: fg,
      fontFamily: 'Inter, sans-serif',
    );

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: Colors.transparent, // our Stack handles bg
      primaryColor: accent,
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: accent,
        secondary: accent,
        surface: card,
        error: ShadColors.destructive,
        onPrimary: isDark ? ShadColors.primaryForeground : Colors.white,
        onSecondary: isDark ? ShadColors.secondaryForeground : Colors.white,
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
        titleLarge: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.w600, color: fg),
        titleMedium: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.w600, color: fg),
        titleSmall: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
        labelLarge: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: fg),
        labelMedium: TextStyle(fontSize: fontSize - 1, color: mutedFg),
        labelSmall: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.w600, color: mutedFg),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: secondary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
          foregroundColor: isDark ? ShadColors.primaryForeground : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          elevation: 0,
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: inp),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 80 : 20), blurRadius: 8)],
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

  const AppShell({
    super.key,
    required this.accent,
    required this.isDark,
    required this.bgPatternIndex,
    this.bgImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? ShadColors.background : ShadColors.lightBg;

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
                // Custom title bar
                _buildTitleBar(bg),
                // Main content
                const Expanded(child: HomeScreen()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground(Color fallback) {
    // Priority: image > pattern > solid
    if (bgImagePath != null) {
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
      // None — solid fill
      return Container(color: fallback);
    }
    return CustomPaint(
      painter: _BgPatternPainter(
        pattern: bgPatternIndex,
        color: isDark
            ? ShadColors.mutedForeground.withAlpha(18)
            : ShadColors.lightMutedFg.withAlpha(25),
      ),
      child: Container(color: fallback),
    );
  }

  Widget _buildTitleBar(Color bg) {
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
                    color: isDark ? ShadColors.mutedForeground : ShadColors.lightMutedFg,
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
// Background pattern painter — same patterns as the preview
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
        final gp = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
        for (double x = 0; x <= w; x += step) canvas.drawLine(Offset(x, 0), Offset(x, h), gp);
        for (double y = 0; y <= h; y += step) canvas.drawLine(Offset(0, y), Offset(w, y), gp);
        break;
      case 3: // Diagonal
        final d = step * 1.5;
        final dp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
        for (double x = -h; x < w + h; x += d) canvas.drawLine(Offset(x, 0), Offset(x + h, h), dp);
        break;
      case 4: // Lines
        final lp = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.8;
        for (double y = step; y < h; y += step * 1.5) canvas.drawLine(Offset(0, y), Offset(w, y), lp);
        break;
      case 5: // Crosshatch
        final d2 = step * 1.5;
        final cp = Paint()..color = color.withAlpha(20)..style = PaintingStyle.stroke..strokeWidth = 0.6;
        for (double x = -h; x < w + h; x += d2) canvas.drawLine(Offset(x, 0), Offset(x + h, h), cp);
        for (double x = 0; x < w + h * 2; x += d2) canvas.drawLine(Offset(x, 0), Offset(x - h, h), cp);
        break;
      case 6: // Zigzag
        final zp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
        final d3 = step * 1.5;
        for (double y = -d3; y < h + d3 * 3; y += d3 * 3) {
          var path = Path();
          var up = true;
          for (double x = 0; x <= w; x += d3 * 1.5) {
            if (x == 0) { path.moveTo(x, up ? y : y + d3); }
            else { path.lineTo(x, up ? y : y + d3); }
            up = !up;
          }
          canvas.drawPath(path, zp);
        }
        break;
      case 7: // Waves
        final wp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
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
        final cirFill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
        final cirStroke = Paint()..color = color.withAlpha(35)..style = PaintingStyle.stroke..strokeWidth = 0.6;
        for (double x = step; x < w + step; x += step * 2.5) {
          for (double y = step; y < h + step; y += step * 2.5) {
            canvas.drawCircle(Offset(x, y), r2, cirFill);
            canvas.drawCircle(Offset(x, y), r2, cirStroke);
          }
        }
        break;
      case 10: // Triangles
        _drawTriangles(canvas, w, h, step);
        break;
      case 11: // Diamonds
        _drawDiamonds(canvas, w, h, step);
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
    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    final rows = (h / r / 1.5).ceil() + 2;
    final cols = (w / r / math.sqrt(3)).ceil() + 2;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < cols; col++) {
        final cx = col * r * math.sqrt(3) + (row.isOdd ? r * math.sqrt(3) / 2 : 0);
        final cy = row * r * 1.5;
        final path = Path();
        for (int i = 0; i < 6; i++) {
          final angle = i * math.pi / 3 - math.pi / 6;
          final pt = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
          if (i == 0) { path.moveTo(pt.dx, pt.dy); }
          else { path.lineTo(pt.dx, pt.dy); }
        }
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, stroke);
      }
    }
  }

  void _drawTriangles(Canvas c, double w, double h, double step) {
    final d = step * 2.5;
    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double x = 0; x < w + d; x += d) {
      for (double y = 0; y < h + d; y += d) {
        final even = ((x / d).round() + (y / d).round()).isEven;
        final path = Path();
        if (even) {
          path.moveTo(x, y + d);
          path.lineTo(x + d / 2, y);
          path.lineTo(x + d, y + d);
        } else {
          path.moveTo(x, y);
          path.lineTo(x + d / 2, y + d);
          path.lineTo(x + d, y);
        }
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, stroke);
      }
    }
  }

  void _drawDiamonds(Canvas c, double w, double h, double step) {
    final d = step * 2.5;
    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
    for (double x = -d / 2; x < w + d; x += d) {
      for (double y = -d / 2; y < h + d; y += d) {
        final path = Path();
        path.moveTo(x + d / 2, y);
        path.lineTo(x + d, y + d / 2);
        path.lineTo(x + d / 2, y + d);
        path.lineTo(x, y + d / 2);
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BgPatternPainter old) =>
      old.pattern != pattern || old.color != color;
}
