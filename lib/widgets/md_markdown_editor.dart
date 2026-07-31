import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';

/// 打开的文件 Tab 数据。
class MdOpenTab {
  final String path; // 相对 project-summary/ 的路径
  final String title; // 文件名
  String content;
  String original;
  bool dirty;

  MdOpenTab({
    required this.path,
    required this.title,
    required this.content,
    required this.original,
    this.dirty = false,
  });

  bool get isDirty => content != original;
}

/// wenzmark 风格中间 Markdown 编辑区。
///
/// 结构：Tab 栏（40px，当前 Tab 底部青绿线）→ Notion 风格编辑器（padding 40px）
/// 支持编辑/预览切换。
class MdMarkdownEditor extends StatelessWidget {
  final List<MdOpenTab> tabs;
  final String? activeTabPath;
  final bool previewMode;
  final TextEditingController controller;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;
  final VoidCallback onTogglePreview;
  final VoidCallback? onSave;

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
                  // Preview toggle
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
                    ? _PreviewPane(content: active.content, theme: theme)
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
