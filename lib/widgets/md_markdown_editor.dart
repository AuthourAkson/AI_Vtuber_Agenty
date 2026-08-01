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
          SizedBox(
            height: 40,
            child: Container(
              color: theme.sidebar,
              child: Row(
                children: [
                  Expanded(
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (final tab in tabs)
                          _TabItem(
                            tab: tab,
                            isActive: tab.path == activeTabPath,
                            onTap: () => onSelectTab(tab.path),
                            onClose: () => onCloseTab(tab.path),
                            closeLabel: l10n.mdClose,
                            theme: theme,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 保存按钮（有未保存修改时高亮）
                  if (onSave != null && active.isDirty) ...[
                    GestureDetector(
                      onTap: onSave,
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
                  if (_canPreview(active.path))
                    GestureDetector(
                      onTap: onTogglePreview,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: previewMode ? theme.accentDim : theme.card,
                          border: Border.all(
                            color: previewMode
                                ? theme.accent.withAlpha(90)
                                : theme.borderSubtle,
                          ),
                        ),
                        child: Icon(
                          previewMode ? Icons.edit_outlined : Icons.visibility_outlined,
                          size: 13,
                          color: previewMode ? theme.accent : theme.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
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
            Text(
              tab.title,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? theme.foreground : theme.muted,
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

class _EditorPane extends StatelessWidget {
  final TextEditingController controller;
  final MdIdeTheme theme;

  const _EditorPane({required this.controller, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: theme.editor,
      child: TextField(
        controller: controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: theme.foreground,
          height: 1.6,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(40),
        ),
      ),
    );
  }
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
