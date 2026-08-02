import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';

/// 打开的文件 Tab 数据。
class MdOpenTab {
  final String path; // 相对项目根的路径
  final String title; // 文件名
  /// 绝对 file:// URI（HTML 预览用，可选）。
  final String? fileUri;
  String content;
  String original;
  bool dirty;

  MdOpenTab({
    required this.path,
    required this.title,
    required this.content,
    required this.original,
    this.fileUri,
    this.dirty = false,
  });

  bool get isDirty => content != original;
}

/// 文件扩展名小写（不含点，如 'html'、'md'、''）。
String _extOf(String path) {
  final name = path.split('/').last;
  final idx = name.lastIndexOf('.');
  if (idx <= 0) return '';
  return name.substring(idx + 1).toLowerCase();
}

bool _isMarkdown(String path) {
  final e = _extOf(path);
  return e == 'md' || e == 'markdown';
}

bool _isHtml(String path) {
  final e = _extOf(path);
  return e == 'html' || e == 'htm';
}

bool _canPreview(String path) => _isMarkdown(path) || _isHtml(path);

/// wenzmark 风格中间编辑区（通用 IDE）。
///
/// 结构：Tab 栏（40px，当前 Tab 底部青绿线）→ Notion 风格编辑器（padding 40px）
/// 预览按文件类型分流：
/// - .md → flutter_markdown 渲染
/// - .html/.htm → InAppWebView 加载磁盘文件（file://，等同浏览器双击效果，
///   相对引用的 css/js/图片正常；显示已保存版本，保存后自动刷新）
/// - 其他 → 无预览按钮
class MdMarkdownEditor extends StatelessWidget {
  final List<MdOpenTab> tabs;
  final String? activeTabPath;
  final bool previewMode;
  final TextEditingController controller;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onTogglePreview;
  final VoidCallback? onSave;
  /// HTML 预览刷新信号：保存成功后 +1，触发 WebView 重新加载。
  final int htmlReloadTick;

  const MdMarkdownEditor({
    super.key,
    required this.tabs,
    required this.activeTabPath,
    required this.previewMode,
    required this.controller,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.onTogglePreview,
    this.onSave,
    this.htmlReloadTick = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);

    final active = tabs.firstWhere(
      (t) => t.path == activeTabPath,
      orElse: () => tabs.isEmpty ? MdOpenTab(path: '', title: '', content: '', original: '') : tabs.first,
    );

    return Container(
      color: theme.editor,
      child: Column(
        children: [
          // ── Tab 栏（40px）──
          _TabStrip(
            tabs: tabs,
            activeTabPath: activeTabPath,
            onSelectTab: onSelectTab,
            onCloseTab: onCloseTab,
            closeLabel: l10n.mdClose,
            theme: theme,
            showSave: onSave != null && active.isDirty,
            onSave: onSave,
            showPreview: _canPreview(active.path),
            previewMode: previewMode,
            onTogglePreview: onTogglePreview,
          ),
          const Divider(height: 1),
          // ── 编辑 / 预览区 ──
          Expanded(
            child: tabs.isEmpty
                ? _EmptyEditor(theme: theme, l10n: l10n)
                : previewMode
                    ? (_isHtml(active.path)
                        ? _HtmlPreviewPane(
                            key: ValueKey('html-${active.path}-$htmlReloadTick'),
                            fileUri: active.fileUri,
                            isDirty: active.isDirty,
                            onSave: onSave,
                            theme: theme,
                            l10n: l10n,
                          )
                        : _PreviewPane(content: active.content, theme: theme))
                    : _EditorPane(
                        controller: controller,
                        theme: theme,
                      ),
          ),
        ],
      ),
    );
  }
}

/// 编辑区 / Tab 栏滚动条开关：桌面平台（Windows）MaterialScrollBehavior 会
/// 自动给所有 Scrollable 包 RawScrollbar——编辑区 TextField 因此出现"系统
/// 自动滑块 + 自绘 _VScrollThumb"双滑块（用户实测两个都能拖）。
/// 禁用方式：`ScrollConfiguration.of(context).copyWith(scrollbars: false)`
/// （本 Flutter 版本官方 API，Dart 3.11 无 ScrollbarFactory 类型）。

/// Tab 栏（40px）：横向滚动 Tab 列表 + 保存/预览按钮。
///
/// StatefulWidget 持有 Tab 列表的 ScrollController，提供 VSCode 风格
/// 常显水平滚动条——文件多时提示可横向滚动，避免 Tab 被误认为
/// "被右侧面板遮挡"。
class _TabStrip extends StatefulWidget {
  final List<MdOpenTab> tabs;
  final String? activeTabPath;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final String closeLabel;
  final MdIdeTheme theme;
  final bool showSave;
  final VoidCallback? onSave;
  final bool showPreview;
  final bool previewMode;
  final VoidCallback onTogglePreview;

  const _TabStrip({
    required this.tabs,
    required this.activeTabPath,
    required this.onSelectTab,
    required this.onCloseTab,
    required this.closeLabel,
    required this.theme,
    required this.showSave,
    this.onSave,
    required this.showPreview,
    required this.previewMode,
    required this.onTogglePreview,
  });

  @override
  State<_TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<_TabStrip> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _TabStrip old) {
    super.didUpdateWidget(old);
    // 新打开的 Tab 追加到列表末尾，自动滚动到可见——
    // 否则新 Tab 在视口外（裁剪边缘紧贴右侧面板），看起来像"被挡住"。
    if (widget.tabs.length > old.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return SizedBox(
      height: 40,
      child: Container(
        color: theme.sidebar,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // ── 右侧固定按钮区（保存/预览）──
            final rightBtns = <Widget>[
              const SizedBox(width: 6),
              // 保存按钮（有未保存修改时高亮）
              if (widget.showSave && widget.onSave != null) ...[
                GestureDetector(
                  onTap: widget.onSave,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: theme.accentDim,
                      border: Border.all(color: theme.accent.withAlpha(90)),
                    ),
                    child: Icon(Icons.save_outlined, size: 13, color: theme.accent),
                  ),
                ),
              ],
              // Preview toggle（仅可预览类型显示）
              if (widget.showPreview)
                GestureDetector(
                  onTap: widget.onTogglePreview,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: widget.previewMode ? theme.accentDim : theme.card,
                      border: Border.all(
                        color: widget.previewMode
                            ? theme.accent.withAlpha(90)
                            : theme.borderSubtle,
                      ),
                    ),
                    child: Icon(
                      widget.previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                      size: 13,
                      color: widget.previewMode ? theme.accent : theme.muted,
                    ),
                  ),
                ),
            ];
            // 右侧按钮区宽度（与上面渲染一致：margin+padding+icon）
            final rightW = 6.0 +
                (widget.showSave && widget.onSave != null ? 33.0 : 0.0) +
                (widget.showPreview ? 37.0 : 0.0);
            final availW = constraints.maxWidth - rightW;

            final count = widget.tabs.length;
            if (count == 0) {
              return Row(children: rightBtns);
            }

            // ── VSCode 式 Tab 宽度策略（editor.tabSizing: fit）──
            // 平铺模式：每个 Tab 包 Flexible（自然宽，超宽时自动均匀收缩，
            // 标题 ellipsis + hover tooltip 看全名）——不依赖宽度估算，
            // 由布局引擎吸收超宽，绝不溢出（曾因估算偏差溢出 2.0px）。
            // 每个 Tab 平均空间 < 最小宽度时退回横向滚动模式（20+ Tab 极端）。
            // （rightW/availW 见上方声明）
            const minTabW = 72.0; // 固定项：padding24+dirty12+gap6+close20=62 + 文本
            final tooMany = availW / count < minTabW;

            Widget tabItem(MdOpenTab t) => _TabItem(
                  tab: t,
                  isActive: t.path == widget.activeTabPath,
                  onTap: () => widget.onSelectTab(t.path),
                  onClose: () => widget.onCloseTab(t.path),
                  closeLabel: widget.closeLabel,
                  theme: theme,
                );

            if (!tooMany) {
              // 平铺模式：所有 Tab 可见；超宽时 Flexible 自动收缩
              return Row(
                children: [
                  for (final t in widget.tabs)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: minTabW),
                        child: tabItem(t),
                      ),
                    ),
                  ...rightBtns,
                ],
              );
            }

            // 极端：Tab 太多 → 横向滚动模式（常显滚动条 + 新 Tab 自动滚动）
            return Row(
              children: [
                Expanded(
                  child: Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    // 方向由 Scrollbar 自动检测（无 scrollDirection 参数，
                    // 传了会报 GC6690633）。
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context)
                          .copyWith(scrollbars: false),
                      child: ListView(
                        controller: _scroll,
                        scrollDirection: Axis.horizontal,
                        children: [for (final t in widget.tabs) tabItem(t)],
                      ),
                    ),
                  ),
                ),
                ...rightBtns,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  final MdOpenTab tab;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final String closeLabel;
  final MdIdeTheme theme;

  const _TabItem({
    required this.tab,
    required this.isActive,
    required this.onTap,
    required this.onClose,
    required this.closeLabel,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: tab.title,
        // 桌面平台 hover 即显示 tooltip（默认 triggerMode: longPress 时
        // hover 生效）；不要传 TooltipTriggerMode.hover——该枚举值不存在
        // （G75B77105），只有 longPress/tap/manual 三个值。
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? theme.editor : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isActive ? theme.accent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tab.isDirty)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.warning,
                  ),
                ),
              // fit 收缩模式下标题可截断（ellipsis），hover tooltip 看全名
              Flexible(
                child: Text(
                  tab.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? theme.foreground : theme.muted,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 关闭按钮：用 IconButton 独立手势，避免与外层 onTap 冲突
              IconButton(
                onPressed: onClose,
                icon: Icon(Icons.close, size: 12, color: theme.faint),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                visualDensity: VisualDensity.compact,
                tooltip: closeLabel,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyEditor extends StatelessWidget {
  final MdIdeTheme theme;
  final AppLocalizations l10n;
  const _EmptyEditor({required this.theme, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 40, color: theme.faint),
          const SizedBox(height: 12),
          Text(
            l10n.mdEmptyEditor,
            style: TextStyle(fontSize: 13, color: theme.faint),
          ),
        ],
      ),
    );
  }
}

/// VSCode 风格源码编辑区。
///
/// 左侧行号列（gutter）+ 当前行高亮 + 不折行（长行水平滚动）。
/// 行号与逻辑行严格一一对应（不软换行），跟随垂直滚动同步位移。
class _EditorPane extends StatefulWidget {
  final TextEditingController controller;
  final MdIdeTheme theme;

  const _EditorPane({required this.controller, required this.theme});

  @override
  State<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends State<_EditorPane> {
  final ScrollController _vScroll = ScrollController();
  final ScrollController _hScroll = ScrollController();
  int _cursorLine = 0;

  // 全文 TextPainter 缓存（文本变化时重算），用于内容宽度 + 每行实测位置
  TextPainter? _cachedTp;
  String _cachedTpText = '';
  List<LineMetrics>? _cachedMetrics;

  static const _padTop = 12.0, _padBottom = 12.0;
  static const _padLeft = 16.0, _padRight = 16.0;
  static const _gutterLeftPad = 10.0, _gutterRightGap = 8.0;

  TextStyle get _textStyle => TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        color: widget.theme.foreground,
        height: 1.6,
      );

  int get _lineCount => '\n'.allMatches(widget.controller.text).length + 1;

  double get _gutterWidth {
    final digits = _lineCount.toString().length;
    return _gutterLeftPad + digits * 6.6 + _gutterRightGap;
  }

  /// 全文 TextPainter（已 layout），与 TextField 用相同 style/引擎，
  /// 保证行号/高亮与文本渲染严格对齐。缓存到文本变化为止。
  TextPainter _fullTp() {
    final text = widget.controller.text;
    if (_cachedTp != null && _cachedTpText == text) return _cachedTp!;
    final tp = TextPainter(
      text: TextSpan(text: text, style: _textStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _cachedTp = tp;
    _cachedTpText = text;
    _cachedMetrics = tp.computeLineMetrics();
    return tp;
  }

  /// 文本内容宽度（最长行宽 + 左右 padding）。
  double _contentWidth() => _fullTp().width + _padLeft + _padRight;

  List<LineMetrics> get _metrics => _cachedMetrics ?? const [];

  /// 逻辑行 i 相对文本内容区顶部的 y（实测行顶；末尾空行按最后行高推算）。
  double _lineTop(int i) {
    final m = _metrics;
    if (m.isEmpty) return i * 20.8;
    if (i < m.length) return m[i].baseline - m[i].ascent;
    final last = m.last;
    return (last.baseline - last.ascent) + last.height * (i - m.length + 1);
  }

  /// 逻辑行 i 的实际行高（末尾空行用最后一行行高）。
  double _lineHeightAt(int i) {
    final m = _metrics;
    if (m.isEmpty) return 20.8;
    if (i < m.length) return m[i].height;
    return m.last.height;
  }

  /// 垂直滚动偏移（未 attach 时返回 0——首次 build 时 TextField 内部的
  /// Scrollable 尚未挂载，直接读 .offset 会抛 "not attached" 断言）。
  double get _vOffset => _vScroll.hasClients ? _vScroll.offset : 0;

  void _updateCursorLine() {
    final sel = widget.controller.selection;
    final text = widget.controller.text;
    int line = 0;
    final end = sel.baseOffset.clamp(0, text.length);
    for (var i = 0; i < end; i++) {
      if (text.codeUnitAt(i) == 0x0A) line++;
    }
    if (line != _cursorLine && mounted) {
      setState(() => _cursorLine = line);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_updateCursorLine);
    // 行号列/当前行高亮需要跟随垂直滚动重绘
    _vScroll.addListener(() {
      if (mounted) setState(() {});
    });
    _updateCursorLine();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_updateCursorLine);
    _vScroll.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final gutterW = _gutterWidth;
    // 当前行位置/高度用全文实测（与 TextField 渲染严格对齐，滚动不错位）
    final cursorTop = _padTop + _lineTop(_cursorLine) - _vOffset;
    final cursorH = _lineHeightAt(_cursorLine);

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentW =
            math.max(_contentWidth(), constraints.maxWidth - gutterW);
        final lineTops = List<double>.generate(_lineCount, _lineTop);
        final lineHeights = List<double>.generate(_lineCount, _lineHeightAt);
        return Container(
          color: theme.editor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 行号列（gutter）──
              SizedBox(
                width: gutterW,
                child: ClipRect(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _LineNumberPainter(
                            lineCount: _lineCount,
                            cursorLine: _cursorLine,
                            scrollOffset: _vOffset,
                            lineTops: lineTops,
                            lineHeights: lineHeights,
                            padTop: _padTop,
                            padRight: _gutterRightGap,
                            theme: theme,
                          ),
                        ),
                      ),
                      // gutter 侧当前行高亮
                      Positioned(
                        left: 0,
                        right: 0,
                        top: cursorTop,
                        height: cursorH,
                        child: Container(color: theme.accent.withAlpha(0x14)),
                      ),
                    ],
                  ),
                ),
              ),
              // ── 编辑区（不折行，长行水平滚动）──
              Expanded(
                child: ClipRect(
                  child: Stack(
                    children: [
                      // 当前行高亮（横贯编辑区，不随水平滚动）
                      Positioned(
                        left: 0,
                        right: 0,
                        top: cursorTop,
                        height: cursorH,
                        child: Container(color: theme.accent.withAlpha(0x10)),
                      ),
                      // 水平滚动条 + 文本（不折行，长行水平滚动）
                      // 注意：Scrollbar 无 scrollDirection 参数（方向自动跟随
                      // 滚动视图），传了会报 GC6690633 编译错误。
                      Scrollbar(
                        controller: _hScroll,
                        thumbVisibility: true,
                        child: SingleChildScrollView(
                          controller: _hScroll,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: contentW,
                            height: constraints.maxHeight,
                            // 禁用系统自动 Scrollbar（桌面平台默认会给
                            // Scrollable 包 RawScrollbar），滚动条由自绘
                            // _VScrollThumb 提供，避免双滑块。
                            child: ScrollConfiguration(
                              behavior: ScrollConfiguration.of(context)
                                  .copyWith(scrollbars: false),
                              child: TextField(
                                controller: widget.controller,
                                scrollController: _vScroll,
                                maxLines: null,
                                expands: true,
                                textAlignVertical: TextAlignVertical.top,
                                style: _textStyle,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  // 显式关闭全局 InputDecorationTheme 的 filled
                                  // （app.dart 全局 filled:true 会让编辑区被 secondary 色填充）
                                  filled: false,
                                  contentPadding: const EdgeInsets.fromLTRB(
                                    _padLeft, _padTop, _padRight, _padBottom,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 垂直滚动条（视口右侧 overlay，VSCode 风格常显，可拖拽）。
                      // 自绘 thumb + 手势：thumb 渲染稳定常显，拖拽/点击轨道
                      // 直接驱动 _vScroll（jumpTo），不依赖 Scrollbar widget。
                      Positioned(
                        top: 0,
                        right: 0,
                        bottom: 0,
                        width: 12,
                        child: _VScrollThumb(
                          controller: _vScroll,
                          theme: theme,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 行号列绘制器：右对齐数字，当前行高亮色，视口外行跳过。
/// 每行位置/高度来自调用方实测（与 TextField 渲染一致）。
class _LineNumberPainter extends CustomPainter {
  final int lineCount;
  final int cursorLine;
  final double scrollOffset;
  final List<double> lineTops; // 每行相对文本内容区顶部的 y
  final List<double> lineHeights;
  final double padTop;
  final double padRight;
  final MdIdeTheme theme;

  const _LineNumberPainter({
    required this.lineCount,
    required this.cursorLine,
    required this.scrollOffset,
    required this.lineTops,
    required this.lineHeights,
    required this.padTop,
    required this.padRight,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (var i = 0; i < lineCount; i++) {
      final top = i < lineTops.length ? lineTops[i] : i * 20.8;
      final h = i < lineHeights.length ? lineHeights[i] : 20.8;
      final y = padTop + top - scrollOffset;
      if (y + h < 0 || y > size.height) continue; // 视口外
      final isCursor = i == cursorLine;
      tp.text = TextSpan(
        text: '${i + 1}',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: isCursor ? theme.foreground : theme.faint,
        ),
      );
      tp.layout();
      tp.paint(
        canvas,
        Offset(
          size.width - padRight - tp.width,
          y + (h - tp.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineNumberPainter old) =>
      old.lineCount != lineCount ||
      old.cursorLine != cursorLine ||
      old.scrollOffset != scrollOffset ||
      old.lineTops != lineTops ||
      old.lineHeights != lineHeights ||
      old.theme != theme;
}

/// 可拖拽的垂直滚动条（自绘 thumb + 手势）。
///
/// 几何与绘制复用 [_VScrollThumbPainter]；手势：
/// - 拖拽 thumb → 按比例换算 scroll offset（jumpTo）
/// - 点击 thumb 外的轨道 → 跳到对应位置
class _VScrollThumb extends StatefulWidget {
  final ScrollController controller;
  final MdIdeTheme theme;

  const _VScrollThumb({required this.controller, required this.theme});

  @override
  State<_VScrollThumb> createState() => _VScrollThumbState();
}

class _VScrollThumbState extends State<_VScrollThumb> {
  double? _dragStartY; // 拖拽开始时指针在槽内的 y
  double? _dragStartPx; // 拖拽开始时的 scroll offset

  ScrollPosition? get _pos =>
      widget.controller.hasClients ? widget.controller.position : null;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.maxHeight;
        final pos = _pos;
        final maxExtent = pos?.maxScrollExtent ?? 0.0;
        final contentH = viewport + maxExtent;
        final thumbH =
            math.max(24.0, viewport * viewport / contentH).clamp(24.0, viewport);
        final thumbTop = (pos == null || maxExtent <= 0)
            ? 0.0
            : (pos.pixels / maxExtent) * (viewport - thumbH);

        void jump(double target) {
          final p = _pos;
          if (p == null || maxExtent <= 0) return;
          p.jumpTo(target.clamp(0.0, maxExtent));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (d) {
            _dragStartY = d.localPosition.dy;
            _dragStartPx = _pos?.pixels;
          },
          onVerticalDragUpdate: (d) {
            if (_dragStartY == null) return;
            final delta = d.localPosition.dy - _dragStartY!;
            final px = _dragStartPx ?? 0.0;
            jump(px + (delta / (viewport - thumbH)) * maxExtent);
          },
          onTapUp: (d) {
            // 点击 thumb 上的点不跳转；点击轨道空白处跳到对应位置
            if (d.localPosition.dy >= thumbTop - 1 &&
                d.localPosition.dy <= thumbTop + thumbH + 1) {
              return;
            }
            jump((d.localPosition.dy / viewport) * maxExtent);
          },
          child: CustomPaint(
            painter: _VScrollThumbPainter(position: pos, theme: widget.theme),
          ),
        );
      },
    );
  }
}

/// 编辑区垂直滚动条 thumb（自绘，VSCode 风格常显）。
///
/// 几何直接来自 [ScrollPosition]：thumb 高度按视口/内容比例，
/// 位置按 scroll offset 比例。不依赖 Scrollbar widget 的渲染条件，
/// 保证任何情况下都绘制（`position` 为 null 时留空——首次 build
/// 时 TextField 内部 Scrollable 尚未挂载，属正常）。
class _VScrollThumbPainter extends CustomPainter {
  final ScrollPosition? position;
  final MdIdeTheme theme;

  const _VScrollThumbPainter({required this.position, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final pos = position;
    if (pos == null) return;
    final viewport = pos.viewportDimension;
    if (viewport <= 0) return;
    final maxExtent = pos.maxScrollExtent;
    final contentH = viewport + maxExtent;
    // thumb 高度：内容越长 thumb 越短，最小 24
    final thumbH = math.max(24.0, viewport * viewport / contentH);
    final thumbTop =
        maxExtent > 0 ? (pos.pixels / maxExtent) * (viewport - thumbH) : 0.0;
    final rect = Rect.fromLTWH(
      size.width - 9, // 12px 槽内右侧 3px 边距 → thumb 宽 6
      thumbTop + 2,
      6,
      thumbH - 4,
    );
    if (rect.height <= 0 || rect.width <= 0) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = theme.faint.withAlpha(150),
    );
  }

  @override
  bool shouldRepaint(covariant _VScrollThumbPainter old) =>
      old.position != position || old.theme != theme;
}

/// Markdown 预览（flutter_markdown 渲染）。
class _PreviewPane extends StatelessWidget {
  final String content;
  final MdIdeTheme theme;

  const _PreviewPane({required this.content, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.editor,
      // 注意：Markdown 内部是 ListView.builder（自带滚动），
      // 不能包 SingleChildScrollView，否则 "unbounded height" 崩溃。
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Markdown(
          data: content,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: theme.foreground, fontSize: 14, height: 1.6),
            h1: TextStyle(
              color: theme.foreground,
              fontSize: 32,
              fontWeight: FontWeight.w700,
            ),
            h2: TextStyle(
              color: theme.foreground,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            h3: TextStyle(
              color: theme.foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            code: TextStyle(
              color: theme.accent,
              backgroundColor: theme.card,
              fontSize: 13,
            ),
            codeblockDecoration: BoxDecoration(
              color: theme.card,
              borderRadius: BorderRadius.circular(6),
            ),
            blockquoteDecoration: BoxDecoration(
              border: Border(left: BorderSide(color: theme.accent, width: 3)),
            ),
            listBullet: TextStyle(color: theme.accent),
          ),
        ),
      ),
    );
  }
}

/// HTML 预览：InAppWebView 加载磁盘文件（file://），效果等同浏览器双击打开。
///
/// 显示已保存版本；有未保存修改时顶部显示提示条（点击即保存）。
/// key 由调用方带 [MdMarkdownEditor.htmlReloadTick]，保存成功后重建重载。
class _HtmlPreviewPane extends StatefulWidget {
  final String? fileUri;
  final bool isDirty;
  final VoidCallback? onSave;
  final MdIdeTheme theme;
  final AppLocalizations l10n;

  const _HtmlPreviewPane({
    super.key,
    this.fileUri,
    required this.isDirty,
    this.onSave,
    required this.theme,
    required this.l10n,
  });

  @override
  State<_HtmlPreviewPane> createState() => _HtmlPreviewPaneState();
}

class _HtmlPreviewPaneState extends State<_HtmlPreviewPane> {
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    final uri = widget.fileUri;
    if (uri == null) {
      return Center(
        child: Text(
          widget.l10n.mdNoPreview,
          style: TextStyle(fontSize: 12, color: widget.theme.faint),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(uri)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              allowFileAccess: true,
              allowContentAccess: true,
            ),
            onLoadStart: (_, __) {
              if (mounted) setState(() => _loading = true);
            },
            onLoadStop: (_, __) {
              if (mounted) setState(() => _loading = false);
            },
            onReceivedError: (_, __, ___) {
              if (mounted) setState(() => _loading = false);
            },
          ),
        ),
        // 加载指示（仅首次/重载瞬间）
        if (_loading)
          Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: widget.theme.accent,
              ),
            ),
          ),
        // 未保存修改提示条（点击保存并刷新）
        if (widget.isDirty && widget.onSave != null)
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: widget.onSave,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.theme.card.withAlpha(0xE6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.theme.warning.withAlpha(140),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(30),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 13, color: widget.theme.warning),
                      const SizedBox(width: 6),
                      Text(
                        widget.l10n.mdPreviewSavedOnly,
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.theme.foreground,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.l10n.save,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: widget.theme.accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
