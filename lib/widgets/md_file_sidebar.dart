import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';
import '../services/project_summary_service.dart';

/// wenzmark 风格左侧文件管理器。
///
/// 结构：项目标题 → 搜索框 → 文件树（ExpansionTile 风格，节点 32px）。
class MdFileSidebar extends StatefulWidget {
  final String? projectRoot;
  final List<SummaryNode> tree;
  final bool loading;
  final String selectedPath;
  final VoidCallback onPickProject;
  final ValueChanged<String> onSelectPath;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onAddFile;
  final VoidCallback onAddFolder;
  final VoidCallback onRefresh;

  const MdFileSidebar({
    super.key,
    required this.projectRoot,
    required this.tree,
    required this.loading,
    required this.selectedPath,
    required this.onPickProject,
    required this.onSelectPath,
    required this.onSearchChanged,
    required this.onAddFile,
    required this.onAddFolder,
    required this.onRefresh,
  });

  @override
  State<MdFileSidebar> createState() => _MdFileSidebarState();
}

class _MdFileSidebarState extends State<MdFileSidebar> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      color: theme.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 项目标题 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 6),
            child: GestureDetector(
              onTap: widget.onPickProject,
              child: Row(
                children: [
                  Icon(Icons.folder, size: 16, color: theme.accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.projectRoot == null
                              ? l10n.mdNoProject
                              : _basename(widget.projectRoot!),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: theme.foreground,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          widget.projectRoot ?? l10n.mdPickProjectHint,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: theme.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.unfold_more, size: 14, color: theme.faint),
                ],
              ),
            ),
          ),
          // ── 搜索框 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.editor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 14, color: theme.faint),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: widget.onSearchChanged,
                      style: TextStyle(fontSize: 12, color: theme.foreground),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: l10n.mdSearchFiles,
                        hintStyle: TextStyle(fontSize: 12, color: theme.faint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // ── 工具按钮行 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _ToolIcon(icon: Icons.refresh, tooltip: l10n.mdRefresh, onTap: widget.onRefresh, theme: theme),
                _ToolIcon(icon: Icons.note_add_outlined, tooltip: l10n.mdNewFile, onTap: widget.onAddFile, theme: theme),
                _ToolIcon(icon: Icons.create_new_folder_outlined, tooltip: l10n.mdNewFolder, onTap: widget.onAddFolder, theme: theme),
                const Spacer(),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── 文件树 ──
          Expanded(
            child: widget.loading
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.accent,
                      ),
                    ),
                  )
                : widget.tree.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            l10n.mdEmptyDocs,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, color: theme.faint),
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: widget.tree
                            .map((n) => _TreeNode(
                                  node: n,
                                  depth: 0,
                                  selectedPath: widget.selectedPath,
                                  onSelect: widget.onSelectPath,
                                  theme: theme,
                                ))
                            .toList(),
                      ),
          ),
        ],
      ),
    );
  }

  String _basename(String path) {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }
}

class _ToolIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final MdIdeTheme theme;
  const _ToolIcon({required this.icon, required this.tooltip, this.onTap, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(icon, size: 14, color: theme.muted),
        ),
      ),
    );
  }
}

/// 文件树节点（ExpansionTile 风格，32px 高）。
class _TreeNode extends StatefulWidget {
  final SummaryNode node;
  final int depth;
  final String selectedPath;
  final ValueChanged<String> onSelect;
  final MdIdeTheme theme;

  const _TreeNode({
    required this.node,
    required this.depth,
    required this.selectedPath,
    required this.onSelect,
    required this.theme,
  });

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isDir = node.isDirectory;
    final isSelected = !isDir && widget.selectedPath == node.relativePath;
    final theme = widget.theme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Node row (32px)
        InkWell(
          onTap: () {
            if (isDir) {
              setState(() => _expanded = !_expanded);
            } else {
              widget.onSelect(node.relativePath);
            }
          },
          child: Container(
            height: 32,
            padding: EdgeInsets.only(left: 8.0 + widget.depth * 14.0, right: 6),
            color: isSelected ? theme.accentDim : Colors.transparent,
            child: Row(
              children: [
                // Expand arrow for dirs
                SizedBox(
                  width: 16,
                  child: isDir
                      ? Icon(
                          _expanded ? Icons.arrow_drop_down : Icons.arrow_right,
                          size: 18,
                          color: theme.muted,
                        )
                      : null,
                ),
                const SizedBox(width: 2),
                Icon(
                  isDir
                      ? (_expanded ? Icons.folder_open : Icons.folder)
                      : Icons.description_outlined,
                  size: 14,
                  color: isDir ? theme.info : theme.muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? theme.accent : theme.foreground,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Children
        if (isDir && _expanded)
          ...node.children.map(
            (child) => _TreeNode(
              node: child,
              depth: widget.depth + 1,
              selectedPath: widget.selectedPath,
              onSelect: widget.onSelect,
              theme: theme,
            ),
          ),
      ],
    );
  }
}
