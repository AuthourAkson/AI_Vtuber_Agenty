1|import 'dart:io';
2|import 'dart:math' as math;
3|import 'package:flutter/material.dart';
4|import 'package:bitsdojo_window/bitsdojo_window.dart';
5|import 'package:provider/provider.dart';
6|import 'screens/home_screen.dart';
7|import 'providers/appearance_provider.dart';
8|import 'models/appearance_prefs.dart';
9|
10|/// shadcn dark palette constants — matched to LocalAIVtuber2 index.css .dark variables.
11|/// Fallback defaults when no AppearanceProvider is available.
12|class ShadColors {
13|  ShadColors._();
14|
15|  // Core
16|  static const background = Color(0xFF1A1A1A);
17|  static const foreground = Color(0xFFF5F5F5);
18|  static const card = Color(0xFF252525);
19|  static const cardForeground = Color(0xFFF5F5F5);
20|  static const popover = Color(0xFF252525);
21|
22|  // Primary / secondary
23|  static const primary = Color(0xFFE8E8E8);
24|  static const primaryForeground = Color(0xFF1C1C1C);
25|  static const secondary = Color(0xFF2E2E2E);
26|  static const secondaryForeground = Color(0xFFF5F5F5);
27|
28|  // Muted
29|  static const muted = Color(0xFF2E2E2E);
30|  static const mutedForeground = Color(0xFF9E9E9E);
31|
32|  // Accent
33|  static const accent = Color(0xFF2E2E2E);
34|  static const accentForeground = Color(0xFFF5F5F5);
35|
36|  // Destructive
37|  static const destructive = Color(0xFFCC3333);
38|
39|  // Border / input
40|  static const border = Color(0x1AFFFFFF);
41|  static const input = Color(0x26FFFFFF);
42|  static const ring = Color(0xFF707070);
43|
44|  // Sidebar
45|  static const sidebar = Color(0xFF1C1C1C);
46|  static const sidebarForeground = Color(0xFFF5F5F5);
47|  static const sidebarPrimary = Color(0xFF6B8DFF);
48|  static const sidebarAccent = Color(0xFF2E2E2E);
49|  static const sidebarAccentForeground = Color(0xFFF5F5F5);
50|  static const sidebarBorder = Color(0x1AFFFFFF);
51|
52|  // ─── Light-mode palette ─────────────────────────────
53|
54|  static const lightBg = Color(0xFFF8F8F8);
55|  static const lightFg = Color(0xFF1A1A1A);
56|  static const lightCard = Color(0xFFFFFFFF);
57|  static const lightSecondary = Color(0xFFF0F0F0);
58|  static const lightMutedFg = Color(0xFF6B6B6B);
59|  static const lightSidebar = Color(0xFFF0F0F0);
60|  static const lightSidebarAccent = Color(0xFFE4E4E4);
61|  static const lightBorder = Color(0xFFE0E0E0);
62|  static const lightInput = Color(0xFFD8D8D8);
63|}
64|
65|// ════════════════════════════════════════════════════════════
66|// Dynamic theme color accessor — reads AppearanceProvider.
67|// Replaces hardcoded ShadColors.XXX throughout the app.
68|//
69|// Usage:  final t = ShadTheme.of(context);
70|//         t.background   t.foreground   t.card   t.primary  ...
71|// ════════════════════════════════════════════════════════════
72|
73|class ShadTheme {
74|  final BuildContext _ctx;
75|
76|  ShadTheme._(this._ctx);
77|
78|  /// Obtain dynamic colors from the nearest AppearanceProvider.
79|  static ShadTheme of(BuildContext context) => ShadTheme._(context);
80|
81|  AppearanceProvider get _ap => _ctx.read<AppearanceProvider>();
82|  bool get _isDark => _ap.isDark;
83|  Color get _accent => Color(_ap.accentColorValue);
84|
// ── Core ──
Color get background => _isDark ? ShadColors.background : ShadColors.lightBg;
Color get foreground => _isDark ? ShadColors.foreground : ShadColors.lightFg;
Color get card => _isDark ? ShadColors.card : ShadColors.lightCard;
Color get cardForeground => _isDark ? ShadColors.cardForeground : ShadColors.lightFg;
Color get popover => _isDark ? ShadColors.popover : ShadColors.lightCard;

// ── Primary / secondary ──
Color get primary => _accent;
Color get primaryForeground => _isDark ? ShadColors.primaryForeground : Colors.white;
Color get secondary => _isDark ? ShadColors.secondary : ShadColors.lightSecondary;
Color get secondaryForeground => _isDark ? ShadColors.secondaryForeground : ShadColors.lightFg;

// ── Muted ──
Color get muted => _isDark ? ShadColors.muted : ShadColors.lightSecondary;
Color get mutedForeground => _isDark ? ShadColors.mutedForeground : ShadColors.lightMutedFg;

// ── Accent ──
Color get accent => _isDark ? ShadColors.accent : ShadColors.lightSidebarAccent;
Color get accentForeground => _isDark ? ShadColors.accentForeground : ShadColors.lightFg;

// ── Destructive ──
Color get destructive => ShadColors.destructive;

// ── Border / input ──
Color get border => _isDark ? ShadColors.border : ShadColors.lightBorder;
Color get input => _isDark ? ShadColors.input : ShadColors.lightInput;
Color get ring => ShadColors.ring;

// ── Sidebar ──
Color get sidebar => _isDark ? ShadColors.sidebar : ShadColors.lightSidebar;
Color get sidebarForeground => _isDark ? ShadColors.sidebarForeground : ShadColors.lightFg;
Color get sidebarPrimary => _accent;
Color get sidebarAccent => _isDark ? ShadColors.sidebarAccent : ShadColors.lightSidebarAccent;
Color get sidebarAccentForeground => _isDark ? ShadColors.sidebarAccentForeground : ShadColors.lightFg;
Color get sidebarBorder => _isDark ? ShadColors.sidebarBorder : ShadColors.lightBorder;
121|}
122|
123|// ════════════════════════════════════════════════════════════
124|
125|class MyApp extends StatelessWidget {
126|  const MyApp({super.key});
127|
128|  @override
129|  Widget build(BuildContext context) {
130|    return Consumer<AppearanceProvider>(
131|      builder: (context, ap, _) {
132|        final accent = Color(ap.accentColorValue);
133|        final isDark = ap.isDark;
134|        final fontSize = ap.fontSize;
135|        final patternIndex = ap.bgPatternIndex;
136|        final bgImagePath = ap.bgImagePath;
137|
138|        return MaterialApp(
139|          title: 'AI VTuber Agent',
140|          debugShowCheckedModeBanner: false,
141|          theme: _buildTheme(isDark, accent, fontSize),
142|          home: AppShell(
143|            accent: accent,
144|            isDark: isDark,
145|            bgPatternIndex: patternIndex,
146|            bgImagePath: bgImagePath,
147|          ),
148|        );
149|      },
150|    );
151|  }
152|
153|  ThemeData _buildTheme(bool isDark, Color accent, double fontSize) {
final bg = isDark ? ShadColors.background : ShadColors.lightBg;
final fg = isDark ? ShadColors.foreground : ShadColors.lightFg;
final card = isDark ? ShadColors.card : ShadColors.lightCard;
final secondary = isDark ? ShadColors.secondary : ShadColors.lightSecondary;
final mutedFg = isDark ? ShadColors.mutedForeground : ShadColors.lightMutedFg;
final bdr = isDark ? ShadColors.border : ShadColors.lightBorder;
final inp = isDark ? ShadColors.input : ShadColors.lightInput;
161|
162|    final baseText = TextStyle(
163|      fontSize: fontSize,
164|      color: fg,
165|      fontFamily: 'Inter, sans-serif',
166|    );
167|
168|    return ThemeData(
169|      brightness: isDark ? Brightness.dark : Brightness.light,
170|      scaffoldBackgroundColor: Colors.transparent, // our Stack handles bg
171|      primaryColor: accent,
172|      colorScheme: ColorScheme(
173|        brightness: isDark ? Brightness.dark : Brightness.light,
174|        primary: accent,
175|        secondary: accent,
176|        surface: card,
177|        error: ShadTheme.of(context).destructive,
178|        onPrimary: isDark ? ShadTheme.of(context).primaryForeground : Colors.white,
179|        onSecondary: isDark ? ShadTheme.of(context).secondaryForeground : Colors.white,
180|        onSurface: fg,
181|        onError: Colors.white,
182|      ),
183|      cardColor: card,
184|      dividerColor: bdr,
185|      appBarTheme: AppBarTheme(
186|        backgroundColor: bg,
187|        elevation: 0,
188|        scrolledUnderElevation: 0,
189|        foregroundColor: fg,
190|      ),
191|      textTheme: TextTheme(
192|        bodyLarge: baseText,
193|        bodyMedium: baseText,
194|        bodySmall: TextStyle(fontSize: fontSize - 2, color: mutedFg),
195|        titleLarge: TextStyle(fontSize: fontSize + 4, fontWeight: FontWeight.w600, color: fg),
196|        titleMedium: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.w600, color: fg),
197|        titleSmall: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: fg),
198|        labelLarge: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500, color: fg),
199|        labelMedium: TextStyle(fontSize: fontSize - 1, color: mutedFg),
200|        labelSmall: TextStyle(fontSize: fontSize - 2, fontWeight: FontWeight.w600, color: mutedFg),
201|      ),
202|      inputDecorationTheme: InputDecorationTheme(
203|        filled: true,
204|        fillColor: secondary,
205|        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
206|        border: OutlineInputBorder(
207|          borderRadius: BorderRadius.circular(10),
208|          borderSide: BorderSide.none,
209|        ),
210|        enabledBorder: OutlineInputBorder(
211|          borderRadius: BorderRadius.circular(10),
212|          borderSide: BorderSide(color: inp),
213|        ),
214|        focusedBorder: OutlineInputBorder(
215|          borderRadius: BorderRadius.circular(10),
216|          borderSide: BorderSide(color: accent, width: 1.5),
217|        ),
218|        hintStyle: TextStyle(color: mutedFg, fontSize: fontSize),
219|      ),
220|      elevatedButtonTheme: ElevatedButtonThemeData(
221|        style: ElevatedButton.styleFrom(
222|          backgroundColor: accent,
223|          foregroundColor: isDark ? ShadTheme.of(context).primaryForeground : Colors.white,
224|          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
225|          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
226|          elevation: 0,
227|          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w500),
228|        ),
229|      ),
230|      outlinedButtonTheme: OutlinedButtonThemeData(
231|        style: OutlinedButton.styleFrom(
232|          foregroundColor: fg,
233|          side: BorderSide(color: inp),
234|          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
235|          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
236|          textStyle: TextStyle(fontSize: fontSize),
237|        ),
238|      ),
239|      switchTheme: SwitchThemeData(
240|        thumbColor: WidgetStateProperty.resolveWith((states) {
241|          if (states.contains(WidgetState.selected)) return accent;
242|          return mutedFg;
243|        }),
244|        trackColor: WidgetStateProperty.resolveWith((states) {
245|          if (states.contains(WidgetState.selected)) return accent.withAlpha(80);
246|          return bdr;
247|        }),
248|      ),
249|      sliderTheme: SliderThemeData(
250|        activeTrackColor: accent,
251|        inactiveTrackColor: secondary,
252|        thumbColor: accent,
253|        overlayColor: accent.withAlpha(40),
254|      ),
255|      tooltipTheme: TooltipThemeData(
256|        decoration: BoxDecoration(
257|          color: card,
258|          borderRadius: BorderRadius.circular(6),
259|          boxShadow: [BoxShadow(color: Colors.black.withAlpha(isDark ? 80 : 20), blurRadius: 8)],
260|        ),
261|        textStyle: TextStyle(color: fg, fontSize: fontSize - 2),
262|      ),
263|      textSelectionTheme: TextSelectionThemeData(
264|        selectionColor: accent.withAlpha(60),
265|        cursorColor: accent,
266|        selectionHandleColor: accent,
267|      ),
268|    );
269|  }
270|}
271|
272|// ════════════════════════════════════════════════════════════
273|// AppShell with dynamic background (pattern / image / solid)
274|// ════════════════════════════════════════════════════════════
275|
276|class AppShell extends StatelessWidget {
277|  final Color accent;
278|  final bool isDark;
279|  final int bgPatternIndex;
280|  final String? bgImagePath;
281|
282|  const AppShell({
283|    super.key,
284|    required this.accent,
285|    required this.isDark,
286|    required this.bgPatternIndex,
287|    this.bgImagePath,
288|  });
289|
290|  @override
291|  Widget build(BuildContext context) {
292|    final bg = isDark ? ShadTheme.of(context).background : ShadColors.lightBg;
293|
294|    return ClipRRect(
295|      borderRadius: BorderRadius.circular(12),
296|      child: Scaffold(
297|        backgroundColor: Colors.transparent,
298|        body: Stack(
299|          children: [
300|            // ── Background layer ──
301|            Positioned.fill(child: _buildBackground(bg)),
302|
303|            // ── Content ──
304|            Column(
305|              children: [
306|                // Custom title bar
307|                _buildTitleBar(bg),
308|                // Main content
309|                const Expanded(child: HomeScreen()),
310|              ],
311|            ),
312|          ],
313|        ),
314|      ),
315|    );
316|  }
317|
318|  Widget _buildBackground(Color fallback) {
319|    // Priority: image > pattern > solid
320|    if (bgImagePath != null) {
321|      final file = File(bgImagePath!);
322|      if (file.existsSync()) {
323|        return Image.file(
324|          file,
325|          fit: BoxFit.cover,
326|          errorBuilder: (_, __, ___) => _patternOrSolid(fallback),
327|        );
328|      }
329|    }
330|    return _patternOrSolid(fallback);
331|  }
332|
333|  Widget _patternOrSolid(Color fallback) {
334|    if (bgPatternIndex == 0) {
335|      // None — solid fill
336|      return Container(color: fallback);
337|    }
338|    return CustomPaint(
339|      painter: _BgPatternPainter(
340|        pattern: bgPatternIndex,
341|        color: isDark
? ShadColors.mutedForeground.withAlpha(18)
: ShadColors.lightMutedFg.withAlpha(25),
344|      ),
345|      child: Container(color: fallback),
346|    );
347|  }
348|
349|  Widget _buildTitleBar(Color bg) {
350|    return Container(
351|      height: 32,
352|      color: bg,
353|      child: Row(
354|        children: [
355|          Expanded(
356|            child: MoveWindow(
357|              child: Container(
358|                alignment: Alignment.centerLeft,
359|                padding: const EdgeInsets.only(left: 12),
360|                child: Text(
361|                  'AI VTuber Agent',
362|                  style: TextStyle(
363|                    fontSize: 12,
364|                    color: isDark ? ShadColors.mutedForeground : ShadColors.lightMutedFg,
365|                    decoration: TextDecoration.none,
366|                  ),
367|                ),
368|              ),
369|            ),
370|          ),
371|          MinimizeWindowButton(),
372|          MaximizeWindowButton(),
373|          CloseWindowButton(),
374|        ],
375|      ),
376|    );
377|  }
378|}
379|
380|// ════════════════════════════════════════════════════════════
381|// Background pattern painter — same patterns as the preview
382|// ════════════════════════════════════════════════════════════
383|
384|class _BgPatternPainter extends CustomPainter {
385|  final int pattern;
386|  final Color color;
387|
388|  _BgPatternPainter({required this.pattern, required this.color});
389|
390|  @override
391|  void paint(Canvas canvas, Size size) {
392|    final paint = Paint()
393|      ..color = color
394|      ..style = PaintingStyle.stroke
395|      ..strokeWidth = 1.0;
396|
397|    final step = 16.0;
398|    final w = size.width;
399|    final h = size.height;
400|
401|    switch (pattern) {
402|      case 1: // Dots
403|        final fill = Paint()..color = color.withAlpha(40);
404|        for (double x = step; x < w; x += step * 2) {
405|          for (double y = step; y < h; y += step * 2) {
406|            canvas.drawCircle(Offset(x, y), 2.0, fill);
407|          }
408|        }
409|        break;
410|      case 2: // Grid
411|        final gp = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
412|        for (double x = 0; x <= w; x += step) canvas.drawLine(Offset(x, 0), Offset(x, h), gp);
413|        for (double y = 0; y <= h; y += step) canvas.drawLine(Offset(0, y), Offset(w, y), gp);
414|        break;
415|      case 3: // Diagonal
416|        final d = step * 1.5;
417|        final dp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
418|        for (double x = -h; x < w + h; x += d) canvas.drawLine(Offset(x, 0), Offset(x + h, h), dp);
419|        break;
420|      case 4: // Lines
421|        final lp = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.8;
422|        for (double y = step; y < h; y += step * 1.5) canvas.drawLine(Offset(0, y), Offset(w, y), lp);
423|        break;
424|      case 5: // Crosshatch
425|        final d2 = step * 1.5;
426|        final cp = Paint()..color = color.withAlpha(20)..style = PaintingStyle.stroke..strokeWidth = 0.6;
427|        for (double x = -h; x < w + h; x += d2) canvas.drawLine(Offset(x, 0), Offset(x + h, h), cp);
428|        for (double x = 0; x < w + h * 2; x += d2) canvas.drawLine(Offset(x, 0), Offset(x - h, h), cp);
429|        break;
430|      case 6: // Zigzag
431|        final zp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
432|        final d3 = step * 1.5;
433|        for (double y = -d3; y < h + d3 * 3; y += d3 * 3) {
434|          var path = Path();
435|          var up = true;
436|          for (double x = 0; x <= w; x += d3 * 1.5) {
437|            if (x == 0) { path.moveTo(x, up ? y : y + d3); }
438|            else { path.lineTo(x, up ? y : y + d3); }
439|            up = !up;
440|          }
441|          canvas.drawPath(path, zp);
442|        }
443|        break;
444|      case 7: // Waves
445|        final wp = Paint()..color = color.withAlpha(25)..style = PaintingStyle.stroke..strokeWidth = 0.8;
446|        final d4 = step * 2;
447|        for (double y = d4 / 2; y < h + d4; y += d4) {
448|          var path = Path();
449|          path.moveTo(0, y);
450|          for (double x = 0; x <= w; x += 4) {
451|            path.lineTo(x, y + math.sin(x / 12) * d4 / 4);
452|          }
453|          canvas.drawPath(path, wp);
454|        }
455|        break;
456|      case 8: // Hexagon
457|        _drawHexagons(canvas, w, h, step);
458|        break;
459|      case 9: // Circles
460|        final r2 = step * 0.7;
461|        final cirFill = Paint()..color = color.withAlpha(20)..style = PaintingStyle.fill;
462|        final cirStroke = Paint()..color = color.withAlpha(35)..style = PaintingStyle.stroke..strokeWidth = 0.6;
463|        for (double x = step; x < w + step; x += step * 2.5) {
464|          for (double y = step; y < h + step; y += step * 2.5) {
465|            canvas.drawCircle(Offset(x, y), r2, cirFill);
466|            canvas.drawCircle(Offset(x, y), r2, cirStroke);
467|          }
468|        }
469|        break;
470|      case 10: // Triangles
471|        _drawTriangles(canvas, w, h, step);
472|        break;
473|      case 11: // Diamonds
474|        _drawDiamonds(canvas, w, h, step);
475|        break;
476|      case 12: // Chess
477|        final chessFill = Paint()..style = PaintingStyle.fill;
478|        final d5 = step * 2;
479|        for (double x = 0; x < w; x += d5) {
480|          for (double y = 0; y < h; y += d5) {
481|            if (((x / d5).round() + (y / d5).round()).isEven) {
482|              chessFill.color = color.withAlpha(25);
483|              canvas.drawRect(Rect.fromLTWH(x, y, d5, d5), chessFill);
484|            }
485|          }
486|        }
487|        break;
488|    }
489|  }
490|
491|  void _drawHexagons(Canvas c, double w, double h, double step) {
492|    final r = step * 0.8;
493|    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
494|    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
495|    final rows = (h / r / 1.5).ceil() + 2;
496|    final cols = (w / r / math.sqrt(3)).ceil() + 2;
497|    for (int row = 0; row < rows; row++) {
498|      for (int col = 0; col < cols; col++) {
499|        final cx = col * r * math.sqrt(3) + (row.isOdd ? r * math.sqrt(3) / 2 : 0);
500|        final cy = row * r * 1.5;
501|        final path = Path();
502|        for (int i = 0; i < 6; i++) {
503|          final angle = i * math.pi / 3 - math.pi / 6;
504|          final pt = Offset(cx + r * math.cos(angle), cy + r * math.sin(angle));
505|          if (i == 0) { path.moveTo(pt.dx, pt.dy); }
506|          else { path.lineTo(pt.dx, pt.dy); }
507|        }
508|        path.close();
509|        c.drawPath(path, fill);
510|        c.drawPath(path, stroke);
511|      }
512|    }
513|  }
514|
515|  void _drawTriangles(Canvas c, double w, double h, double step) {
516|    final d = step * 2.5;
517|    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
518|    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
519|    for (double x = 0; x < w + d; x += d) {
520|      for (double y = 0; y < h + d; y += d) {
521|        final even = ((x / d).round() + (y / d).round()).isEven;
522|        final path = Path();
523|        if (even) {
524|          path.moveTo(x, y + d);
525|          path.lineTo(x + d / 2, y);
526|          path.lineTo(x + d, y + d);
527|        } else {
528|          path.moveTo(x, y);
529|          path.lineTo(x + d / 2, y + d);
530|          path.lineTo(x + d, y);
531|        }
532|        path.close();
533|        c.drawPath(path, fill);
534|        c.drawPath(path, stroke);
535|      }
536|    }
537|  }
538|
539|  void _drawDiamonds(Canvas c, double w, double h, double step) {
540|    final d = step * 2.5;
541|    final fill = Paint()..color = color.withAlpha(15)..style = PaintingStyle.fill;
542|    final stroke = Paint()..color = color.withAlpha(30)..style = PaintingStyle.stroke..strokeWidth = 0.5;
543|    for (double x = -d / 2; x < w + d; x += d) {
544|      for (double y = -d / 2; y < h + d; y += d) {
545|        final path = Path();
546|        path.moveTo(x + d / 2, y);
547|        path.lineTo(x + d, y + d / 2);
548|        path.lineTo(x + d / 2, y + d);
549|        path.lineTo(x, y + d / 2);
550|        path.close();
551|        c.drawPath(path, fill);
552|        c.drawPath(path, stroke);
553|      }
554|    }
555|  }
556|
557|  @override
558|  bool shouldRepaint(covariant _BgPatternPainter old) =>
559|      old.pattern != pattern || old.color != color;
560|}
561|