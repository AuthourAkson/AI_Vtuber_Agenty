import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../app.dart';
import '../models/appearance_prefs.dart';
import '../providers/appearance_provider.dart';

/// MultiAgent Settings → Preferences → Appearance
///
/// All changes apply globally through AppearanceProvider.
/// Sections:
///   1. Dark Mode
///   2. Font Size
///   3. Theme Color (16 presets)
///   4. Background Pattern (13 previews)
///   5. Background Image
///   6. Startup Animation
///   7. Reset to Default
class MultiAgentAppearancePage extends StatelessWidget {
  const MultiAgentAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ap = context.watch<AppearanceProvider>();
    final accent = Color(ap.accentColorValue);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('Appearance', Icons.palette_outlined, accent),
          const SizedBox(height: 24),

          // 1. Dark Mode
          _buildDarkMode(ap, accent),
          const SizedBox(height: 24),

          // 2. Font Size
          _buildFontSize(ap, accent),
          const SizedBox(height: 24),

          // 3. Theme Color
          _buildThemeColor(ap, accent),
          const SizedBox(height: 24),

          // 4. Background Pattern
          _buildBgPattern(ap, accent),
          const SizedBox(height: 24),

          // 5. Background Image
          _buildBgImage(ap, accent, context),
          const SizedBox(height: 24),

          // 6. Startup Animation
          _buildStartupAnim(ap, accent),
          const SizedBox(height: 24),

          // 7. Reset to Default
          _buildResetSection(ap, accent, context),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // Helpers
  // ═══════════════════════════════════════════════════════

  Widget _sectionHeader(String title, IconData icon, Color accent) {
    return Row(
      children: [
        Icon(icon, size: 20, color: accent),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: ShadColors.foreground)),
      ],
    );
  }

  Widget _sectionLabel(String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ShadColors.foreground)),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: ShadColors.mutedForeground)),
          ],
        ],
      ),
    );
  }

  Widget _settingCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ShadColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ShadColors.border),
      ),
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 1. Dark Mode
  // ═══════════════════════════════════════════════════════

  Widget _buildDarkMode(AppearanceProvider ap, Color accent) {
    return _settingCard(
      child: Row(
        children: [
          const Icon(Icons.dark_mode, size: 22, color: ShadColors.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: _sectionLabel('Dark Mode', 'Switch between dark and light theme'),
          ),
          Switch(
            value: ap.isDark,
            onChanged: (v) => ap.update(ap.prefs.copyWith(darkMode: v)),
            activeColor: accent,
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 2. Font Size
  // ═══════════════════════════════════════════════════════

  Widget _buildFontSize(AppearanceProvider ap, Color accent) {
    return _settingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.format_size, size: 22, color: ShadColors.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: _sectionLabel('Font Size', 'Adjust text size across the app'),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withAlpha(25),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${ap.fontSize.toInt()} px',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: accent,
              inactiveTrackColor: ShadColors.secondary,
              thumbColor: accent,
              overlayColor: accent.withAlpha(40),
            ),
            child: Slider(
              value: ap.fontSize,
              min: 12,
              max: 20,
              divisions: 8,
              onChanged: (v) => ap.update(ap.prefs.copyWith(fontSize: v)),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The quick brown fox jumps over the lazy dog.',
                style: TextStyle(fontSize: ap.fontSize, color: ShadColors.foreground),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 3. Theme Color (16 presets)
  // ═══════════════════════════════════════════════════════

  Widget _buildThemeColor(AppearanceProvider ap, Color accent) {
    final colors = AppearancePrefs.themeColors;
    return _settingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.color_lens, size: 22, color: ShadColors.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: _sectionLabel('Theme Color', 'Choose your accent color'),
              ),
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: accent.withAlpha(80), blurRadius: 8)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(colors.length, (i) {
              final c = colors[i];
              final selected = ap.themeColorIndex == i;
              return GestureDetector(
                onTap: () => ap.update(ap.prefs.copyWith(themeColorIndex: i)),
                child: Tooltip(
                  message: c.label,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Color(c.color),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? ShadColors.foreground : Colors.transparent,
                        width: selected ? 2.5 : 0,
                      ),
                      boxShadow: selected
                          ? [BoxShadow(color: Color(c.color).withAlpha(100), blurRadius: 8, spreadRadius: 1)]
                          : [],
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 4. Background Pattern
  // ═══════════════════════════════════════════════════════

  Widget _buildBgPattern(AppearanceProvider ap, Color accent) {
    final patterns = AppearancePrefs.bgPatterns;
    return _settingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.texture, size: 22, color: ShadColors.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: _sectionLabel('Background Pattern',
                    ap.bgPatternIndex == 0 ? 'No pattern' : patterns[ap.bgPatternIndex].label),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(patterns.length, (i) {
              final selected = ap.bgPatternIndex == i;
              return GestureDetector(
                onTap: () => ap.update(ap.prefs.copyWith(bgPatternIndex: i)),
                child: Tooltip(
                  message: patterns[i].label,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 64, height: 56,
                    decoration: BoxDecoration(
                      color: ShadColors.secondary,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? accent : ShadColors.border,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: _PatternPreview(
                      pattern: i,
                      color: selected ? accent : ShadColors.mutedForeground,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 5. Background Image
  // ═══════════════════════════════════════════════════════

  Widget _buildBgImage(AppearanceProvider ap, Color accent, BuildContext context) {
    final hasImage = ap.bgImagePath != null;
    return _settingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.image, size: 22, color: ShadColors.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: _sectionLabel('Background Image', 'Set a custom background image'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                children: [
                  Image.file(
                    File(ap.bgImagePath!),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 140,
                      color: ShadColors.secondary,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 32, color: ShadColors.mutedForeground),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 4, top: 4,
                    child: GestureDetector(
                      onTap: () => ap.update(ap.prefs.copyWith(clearBgImage: true)),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.close, size: 16, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(ap.bgImagePath!, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: ShadColors.mutedForeground)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _pickBgImage(ap),
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(hasImage ? 'Change Image' : 'Choose Image'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ShadColors.foreground,
                side: const BorderSide(color: ShadColors.border),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickBgImage(AppearanceProvider ap) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
        ap.update(ap.prefs.copyWith(bgImagePath: result.files.single.path));
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════════════════
  // 6. Startup Animation
  // ═══════════════════════════════════════════════════════

  Widget _buildStartupAnim(AppearanceProvider ap, Color accent) {
    return _settingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.animation, size: 22, color: ShadColors.foreground),
              const SizedBox(width: 12),
              Expanded(
                child: _sectionLabel('Startup Animation',
                    'Smooth transition when launching the app'),
              ),
              Switch(
                value: ap.startupAnimEnabled,
                onChanged: (v) => ap.update(ap.prefs.copyWith(startupAnimEnabled: v)),
                activeColor: accent,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: ShadColors.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ShadColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14,
                    color: ap.startupAnimEnabled ? ShadColors.mutedForeground : const Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ap.startupAnimEnabled
                        ? 'Startup animation will play when launching the app.'
                        : 'This feature is not yet implemented. Enable it now to auto-activate when available.',
                    style: TextStyle(fontSize: 12,
                        color: ap.startupAnimEnabled ? ShadColors.mutedForeground : const Color(0xFFF59E0B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  // 7. Reset to Default
  // ═══════════════════════════════════════════════════════

  Widget _buildResetSection(AppearanceProvider ap, Color accent, BuildContext ctx) {
    return _settingCard(
      child: Row(
        children: [
          const Icon(Icons.restore, size: 22, color: ShadColors.foreground),
          const SizedBox(width: 12),
          Expanded(
            child: _sectionLabel('Default', 'Restore all appearance settings to factory defaults'),
          ),
          OutlinedButton.icon(
            onPressed: () => _confirmReset(ap, ctx),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Reset'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ShadColors.destructive,
              side: const BorderSide(color: ShadColors.destructive),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmReset(AppearanceProvider ap, BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        backgroundColor: ShadColors.card,
        title: const Text('Reset to Default', style: TextStyle(color: ShadColors.foreground)),
        content: const Text(
          'This will restore all appearance settings to their factory defaults.',
          style: TextStyle(color: ShadColors.mutedForeground),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel', style: TextStyle(color: ShadColors.mutedForeground)),
          ),
          TextButton(
            onPressed: () {
              ap.resetToDefaults();
              Navigator.pop(dCtx);
            },
            child: const Text('Reset All', style: TextStyle(color: ShadColors.destructive)),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Pattern Preview painter
// ══════════════════════════════════════════════════════════

class _PatternPreview extends StatelessWidget {
  final int pattern;
  final Color color;

  const _PatternPreview({required this.pattern, required this.color});

  @override
  Widget build(BuildContext context) {
    if (pattern == 0) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        painter: _PreviewPainter(pattern: pattern, color: color),
        size: const Size(64, 56),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  final int pattern;
  final Color color;

  _PreviewPainter({required this.pattern, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final step = 8.0;
    final w = size.width;
    final h = size.height;

    switch (pattern) {
      case 1: // Dots
        final fill = Paint()..color = color.withAlpha(30);
        for (double x = step; x < w; x += step * 2) {
          for (double y = step; y < h; y += step * 2) {
            canvas.drawCircle(Offset(x, y), 1.5, fill);
            canvas.drawCircle(Offset(x, y), 1.5, paint);
          }
        }
        break;
      case 2: // Grid
        for (double x = 0; x <= w; x += step) canvas.drawLine(Offset(x, 0), Offset(x, h), paint);
        for (double y = 0; y <= h; y += step) canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        break;
      case 3: // Diagonal
        final d = step * 1.5;
        for (double x = -h; x < w + h; x += d) canvas.drawLine(Offset(x, 0), Offset(x + h, h), paint);
        break;
      case 4: // Lines
        for (double y = step; y < h; y += step * 1.5) canvas.drawLine(Offset(0, y), Offset(w, y), paint);
        break;
      case 5: // Crosshatch
        final d2 = step * 1.5;
        final p2 = Paint()..color = color.withAlpha(80)..style = PaintingStyle.stroke..strokeWidth = 1.2;
        for (double x = -h; x < w + h; x += d2) canvas.drawLine(Offset(x, 0), Offset(x + h, h), paint);
        for (double x = 0; x < w + h * 2; x += d2) canvas.drawLine(Offset(x, 0), Offset(x - h, h), p2);
        break;
      case 6: // Zigzag
        final d3 = step * 1.5;
        for (double y = -d3; y < h + d3 * 3; y += d3 * 3) {
          final path = Path();
          var up = true;
          for (double x = 0; x <= w; x += d3 * 1.5) {
            if (x == 0) { path.moveTo(x, up ? y : y + d3); }
            else { path.lineTo(x, up ? y : y + d3); }
            up = !up;
          }
          canvas.drawPath(path, paint);
        }
        break;
      case 7: // Waves
        final d4 = step * 2;
        for (double y = d4 / 2; y < h + d4; y += d4) {
          final path = Path();
          path.moveTo(0, y);
          for (double x = 0; x <= w; x += 4) path.lineTo(x, y + math.sin(x / 8) * d4 / 3);
          canvas.drawPath(path, paint);
        }
        break;
      case 8: // Hexagon
        _drawHex(canvas, w, h, step, paint);
        break;
      case 9: // Circles
        final r = step * 0.6;
        final cf = Paint()..color = color.withAlpha(25)..style = PaintingStyle.fill;
        for (double x = step; x < w + step; x += step * 2.5) {
          for (double y = step; y < h + step; y += step * 2.5) {
            canvas.drawCircle(Offset(x, y), r, cf);
            canvas.drawCircle(Offset(x, y), r, paint);
          }
        }
        break;
      case 10: // Triangles
        _drawTri(canvas, w, h, step, paint);
        break;
      case 11: // Diamonds
        _drawDia(canvas, w, h, step, paint);
        break;
      case 12: // Chess
        final d5 = step * 2;
        final cf2 = Paint()..style = PaintingStyle.fill;
        for (double x = 0; x < w; x += d5) {
          for (double y = 0; y < h; y += d5) {
            if (((x / d5).round() + (y / d5).round()).isEven) {
              cf2.color = color.withAlpha(30);
              canvas.drawRect(Rect.fromLTWH(x, y, d5, d5), cf2);
            }
          }
        }
        break;
    }
  }

  void _drawHex(Canvas c, double w, double h, double step, Paint p) {
    final r = step * 0.6;
    final rows = (h / r / 1.5).ceil() + 2;
    final cols = (w / r / math.sqrt(3)).ceil() + 2;
    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
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
        c.drawPath(path, p);
      }
    }
  }

  void _drawTri(Canvas c, double w, double h, double step, Paint p) {
    final d = step * 2;
    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
    for (double x = 0; x < w + d; x += d) {
      for (double y = 0; y < h + d; y += d) {
        final even = ((x / d).round() + (y / d).round()).isEven;
        final path = Path();
        if (even) {
          path.moveTo(x, y + d); path.lineTo(x + d / 2, y); path.lineTo(x + d, y + d);
        } else {
          path.moveTo(x, y); path.lineTo(x + d / 2, y + d); path.lineTo(x + d, y);
        }
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, p);
      }
    }
  }

  void _drawDia(Canvas c, double w, double h, double step, Paint p) {
    final d = step * 2;
    final fill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
    for (double x = -d / 2; x < w + d; x += d) {
      for (double y = -d / 2; y < h + d; y += d) {
        final path = Path();
        path.moveTo(x + d / 2, y); path.lineTo(x + d, y + d / 2);
        path.lineTo(x + d / 2, y + d); path.lineTo(x, y + d / 2);
        path.close();
        c.drawPath(path, fill);
        c.drawPath(path, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) =>
      old.pattern != pattern || old.color != color;
}
