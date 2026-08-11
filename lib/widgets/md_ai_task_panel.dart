import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';
import '../services/claude_session_service.dart';
import 'md_task_session_view.dart';

/// wenzmark 风格右侧 AI 任务中心。
///
/// 结构：任务搜索框 → 状态筛选行 → 任务卡片列表 → AI 输入框（100px）。
class MdAiTaskPanel extends StatefulWidget {
  final List<MdTask> tasks;
  final String? selectedEmployeeName;
  final MdTaskExecutor executor;
  final String? providerName;
  final List<String> providerNames;
  final List<ClaudeSessionInfo> claudeSessions;
  final String? resumeSessionId;
  final ValueChanged<String?> onResumeSessionChanged;
  final Map<String, String> sessionTitles;
  final ValueChanged<String> onDeleteSession;
  final ValueChanged<String> onPromptSubmitted;
  final ValueChanged<MdTaskExecutor> onExecutorChanged;
  final ValueChanged<String> onProviderChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<MdTaskStatus?> onFilterChanged;
  final ValueChanged<MdTask> onDeleteTask;
  final ValueChanged<MdTask> onRetryTask;
  final ValueChanged<MdTask> onEditTask;
  final ValueChanged<MdTask> onViewTask;
  final VoidCallback onPickEmployee;

  const MdAiTaskPanel({
    super.key,
    required this.tasks,
    required this.selectedEmployeeName,
    required this.executor,
    required this.providerName,
    required this.providerNames,
    required this.claudeSessions,
    required this.resumeSessionId,
    required this.onResumeSessionChanged,
    required this.sessionTitles,
    required this.onDeleteSession,
    required this.onPromptSubmitted,
    required this.onExecutorChanged,
    required this.onProviderChanged,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onDeleteTask,
    required this.onRetryTask,
    required this.onEditTask,
    required this.onViewTask,
    required this.onPickEmployee,
  });

  @override
  State<MdAiTaskPanel> createState() => _MdAiTaskPanelState();
}

class _MdAiTaskPanelState extends State<MdAiTaskPanel> {
  final _searchCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  MdTaskStatus? _filter;

  /// 会话组折叠状态（groupId → 是否折叠；默认展开）。
  final Map<String, bool> _collapsed = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  List<MdTask> get _visibleTasks {
    final q = _searchCtrl.text.trim().toLowerCase();
    return widget.tasks.where((t) {
      if (_filter != null && t.status != _filter) return false;
      if (q.isNotEmpty && !t.title.toLowerCase().contains(q)) return false;
      return true;
    }).toList();
  }

  void _submit() {
    final text = _promptCtrl.text.trim();
    if (text.isEmpty) return;
    widget.onPromptSubmitted(text);
    _promptCtrl.clear();
  }

  String _executorLabel(AppLocalizations l10n) {
    switch (widget.executor) {
      case MdTaskExecutor.employee:
        return l10n.mdExecutorEmployee;
      case MdTaskExecutor.claudeCli:
        return l10n.mdExecutorClaudeCli;
      case MdTaskExecutor.codexCli:
        return l10n.mdExecutorCodexCli;
    }
  }

  /// 构造带图标 + 选中勾选的 PopupMenuItem。
  PopupMenuItem<T> _menuItem<T>(
    T value,
    IconData icon,
    String label,
    MdIdeTheme theme,
  ) {
    final selected = value == widget.executor ||
        (value is String && value == widget.providerName);
    return PopupMenuItem<T>(
      value: value,
      height: 30,
      child: Row(
        children: [
          Icon(icon, size: 12, color: selected ? theme.accent : theme.muted),
          const SizedBox(width: 8),
          // ⚠️ 不用 Expanded：PopupMenuItem 宽度约束可能无界（布局崩溃）
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: selected ? theme.accent : theme.foreground,
              ),
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check, size: 12, color: theme.accent),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final tasks = _visibleTasks;
    final counts = _counts();
    final entries = _buildEntries(tasks);

    return Container(
      width: double.infinity,
      color: theme.background,
      child: Column(
        children: [
          // ── 搜索框 ──
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: theme.sidebar,
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
                        hintText: l10n.mdSearchTasks,
                        hintStyle: TextStyle(fontSize: 12, color: theme.faint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── 状态筛选行 ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _FilterChip(
                  label: l10n.mdFilterAll,
                  count: counts.total,
                  selected: _filter == null,
                  onTap: () => setState(() => _filter = null),
                  theme: theme,
                ),
                _FilterChip(
                  label: l10n.mdFilterQueue,
                  count: counts.queue,
                  selected: _filter == MdTaskStatus.running,
                  onTap: () => setState(() => _filter = MdTaskStatus.running),
                  theme: theme,
                ),
                _FilterChip(
                  label: l10n.mdFilterError,
                  count: counts.failed,
                  selected: _filter == MdTaskStatus.failed,
                  onTap: () => setState(() => _filter = MdTaskStatus.failed),
                  theme: theme,
                ),
                _FilterChip(
                  label: l10n.mdFilterPending,
                  count: counts.pending,
                  selected: _filter == MdTaskStatus.waiting,
                  onTap: () => setState(() => _filter = MdTaskStatus.waiting),
                  theme: theme,
                ),
                _FilterChip(
                  label: l10n.mdFilterCompleted,
                  count: counts.completed,
                  selected: _filter == MdTaskStatus.completed,
                  onTap: () => setState(() => _filter = MdTaskStatus.completed),
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // ── 任务卡片列表（会话分组 + 无分组平铺）──
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      widget.tasks.isEmpty ? l10n.mdNoTasks : l10n.mdNoMatch,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: theme.faint),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final e = entries[i];
                      if (e.isHeader) {
                        return _SessionHeader(
                          title: e.groupTitle!,
                          count: e.groupCount!,
                          collapsed: _collapsed[e.groupId] == true,
                          onToggle: () => setState(() {
                            _collapsed[e.groupId!] = !(_collapsed[e.groupId!] == true);
                          }),
                          onDelete: () => widget.onDeleteSession(e.groupId!),
                          l10n: l10n,
                          theme: theme,
                        );
                      }
                      final t = e.task!;
                      return _TaskCard(
                        task: t,
                        onDelete: () => widget.onDeleteTask(t),
                        onRetry: () => widget.onRetryTask(t),
                        onEdit: () => widget.onEditTask(t),
                        onView: () => widget.onViewTask(t),
                        l10n: l10n,
                        theme: theme,
                      );
                    },
                  ),
          ),
          // ── AI 输入框（100px）──
          _buildPromptBox(theme, l10n),
        ],
      ),
    );
  }

  _TaskCounts _counts() {
    int total = 0, queue = 0, failed = 0, pending = 0, completed = 0;
    for (final t in widget.tasks) {
      total++;
      switch (t.status) {
        case MdTaskStatus.waiting: pending++;
        case MdTaskStatus.running: queue++;
        case MdTaskStatus.failed: failed++;
        case MdTaskStatus.completed: completed++;
      }
    }
    return _TaskCounts(total, queue, failed, pending, completed);
  }

  /// 任务列表分组结构：有 sessionId 的按会话组折叠（组头 + 展开的组内卡），
  /// 无分组任务平铺。组排序按组内最新卡时间倒序（活跃组在前）；组内历史
  /// 内容卡（viewOnly）强制排最前，其余按时间正序（对话顺序）。
  List<_ListEntry> _buildEntries(List<MdTask> tasks) {
    final groups = <String, List<MdTask>>{};
    final order = <String>[];
    final orphans = <MdTask>[];
    for (final t in tasks) {
      final sid = t.sessionId;
      if (sid == null || sid.isEmpty) {
        orphans.add(t);
        continue;
      }
      if (!groups.containsKey(sid)) order.add(sid);
      groups.putIfAbsent(sid, () => []).add(t);
    }
    order.sort((a, b) => _latestIn(groups[b]!).compareTo(_latestIn(groups[a]!)));
    final entries = <_ListEntry>[];
    for (final sid in order) {
      final g = groups[sid]!;
      g.sort((a, b) {
        if (a.viewOnly != b.viewOnly) return a.viewOnly ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
      entries.add(_ListEntry.header(
        sid,
        widget.sessionTitles[sid] ?? g.first.title,
        g.length,
      ));
      if (_collapsed[sid] != true) {
        for (final t in g) {
          entries.add(_ListEntry.task(t));
        }
      }
    }
    orphans.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final t in orphans) {
      entries.add(_ListEntry.task(t));
    }
    return entries;
  }

  static DateTime _latestIn(List<MdTask> tasks) {
    var latest = tasks.first.createdAt;
    for (final t in tasks) {
      if (t.createdAt.isAfter(latest)) latest = t.createdAt;
    }
    return latest;
  }

  Widget _buildPromptBox(MdIdeTheme theme, AppLocalizations l10n) {
    return Container(
      height: 100,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: theme.sidebar,
        border: Border(top: BorderSide(color: theme.borderSubtle)),
      ),
      child: Column(
        children: [
          Expanded(
            child: TextField(
              controller: _promptCtrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              style: TextStyle(fontSize: 12, color: theme.foreground, height: 1.4),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: l10n.mdPromptHint,
                hintStyle: TextStyle(fontSize: 12, color: theme.faint),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // 左侧组（附件 + 执行器 + 员工/服务商）：可整体收缩，
              // 防止长名称把行撑爆（曾溢出 7.3px 到发送按钮上）
              Flexible(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.attach_file, size: 14, color: theme.faint),
                    const SizedBox(width: 8),
                    // 执行器选择（员工 / Claude Code CLI / Codex CLI 预留）
                    Flexible(
                      child: _SelectorChip<MdTaskExecutor>(
                        icon: widget.executor == MdTaskExecutor.employee
                            ? Icons.smart_toy_outlined
                            : Icons.terminal,
                        iconColor: theme.accent,
                        label: _executorLabel(l10n),
                        theme: theme,
                        items: () => [
                          _menuItem(
                            MdTaskExecutor.employee,
                            Icons.smart_toy_outlined,
                            l10n.mdExecutorEmployee,
                            theme,
                          ),
                          _menuItem(
                            MdTaskExecutor.claudeCli,
                            Icons.terminal,
                            l10n.mdExecutorClaudeCli,
                            theme,
                          ),
                        ],
                        onSelected: widget.onExecutorChanged,
                      ),
                    ),
                    const SizedBox(width: 6),
                    // 员工模式：显示员工选择；CLI 模式：显示 AI 服务商选择
                    if (widget.executor == MdTaskExecutor.employee)
                      Flexible(
                        child: GestureDetector(
                          onTap: widget.onPickEmployee,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: theme.card,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: theme.borderSubtle),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_outline, size: 11, color: theme.muted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    widget.selectedEmployeeName ?? l10n.mdSelectEmployee,
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                    style: TextStyle(fontSize: 11, color: theme.foreground),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.arrow_drop_down, size: 14, color: theme.muted),
                              ],
                            ),
                          ),
                        ),
                      )
                    else ...[
                      Flexible(
                        child: _SelectorChip<String>(
                          icon: Icons.cloud_outlined,
                          iconColor: theme.muted,
                          label: widget.providerName ?? l10n.mdSelectProvider,
                          theme: theme,
                          items: () => widget.providerNames.isEmpty
                              ? [
                                  PopupMenuItem<String>(
                                    enabled: false,
                                    child: Text(
                                      l10n.mdNoProviderMenu,
                                      style: TextStyle(fontSize: 12, color: theme.faint),
                                    ),
                                  ),
                                ]
                              : [
                                  for (final name in widget.providerNames)
                                    _menuItem(name, Icons.cloud_outlined, name, theme),
                                ],
                          onSelected: widget.onProviderChanged,
                        ),
                      ),
                      // Claude Code CLI：会话选择（resume 历史会话）
                      if (widget.executor == MdTaskExecutor.claudeCli) ...[
                        const SizedBox(width: 6),
                        Flexible(child: _sessionSelector(theme, l10n)),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.arrow_upward, size: 16, color: theme.background),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Claude Code CLI 会话选择（resume 历史会话）──

  Widget _sessionSelector(MdIdeTheme theme, AppLocalizations l10n) {
    ClaudeSessionInfo? selected;
    for (final s in widget.claudeSessions) {
      if (s.id == widget.resumeSessionId) {
        selected = s;
        break;
      }
    }
    // ⚠️ 哨兵值 '' 表示「新会话」：不能用 null（showMenu 返回 null = 取消）
    return _SelectorChip<String>(
      icon: Icons.history,
      iconColor: selected != null ? theme.accent : theme.muted,
      label: selected?.title ?? l10n.mdNewSession,
      theme: theme,
      items: () => [
        _newSessionItem(theme, l10n),
        if (widget.claudeSessions.isEmpty)
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              l10n.mdNoSessions,
              style: TextStyle(fontSize: 12, color: theme.faint),
            ),
          )
        else
          for (final s in widget.claudeSessions) _sessionMenuItem(s, theme),
      ],
      onSelected: (v) => widget.onResumeSessionChanged(v.isEmpty ? null : v),
    );
  }

  PopupMenuItem<String> _newSessionItem(MdIdeTheme theme, AppLocalizations l10n) {
    final selected = widget.resumeSessionId == null;
    return PopupMenuItem<String>(
      value: '',
      height: 30,
      child: Row(
        children: [
          Icon(Icons.add_comment_outlined,
              size: 12, color: selected ? theme.accent : theme.muted),
          const SizedBox(width: 8),
          Text(
            l10n.mdNewSession,
            style: TextStyle(
              fontSize: 12,
              color: selected ? theme.accent : theme.foreground,
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check, size: 12, color: theme.accent),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<String> _sessionMenuItem(ClaudeSessionInfo s, MdIdeTheme theme) {
    final selected = s.id == widget.resumeSessionId;
    return PopupMenuItem<String>(
      value: s.id,
      height: 34,
      child: Row(
        children: [
          Icon(Icons.history, size: 12, color: selected ? theme.accent : theme.muted),
          const SizedBox(width: 8),
          // ⚠️ 不用 Expanded：PopupMenuItem 宽度约束可能无界（布局崩溃）
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    color: selected ? theme.accent : theme.foreground,
                  ),
                ),
                Text(
                  _fmtSessionMeta(s),
                  style: TextStyle(fontSize: 10, color: theme.faint),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 6),
            Icon(Icons.check, size: 12, color: theme.accent),
          ],
        ],
      ),
    );
  }

  /// 会话元信息：`MM-dd HH:mm · 行数`（纯数字，无 i18n 负担）。
  static String _fmtSessionMeta(ClaudeSessionInfo s) {
    final t = s.modified.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)} · ${s.lineCount}';
  }
}

class _TaskCounts {
  final int total, queue, failed, pending, completed;
  const _TaskCounts(this.total, this.queue, this.failed, this.pending, this.completed);
}

/// 任务列表扁平条目：会话分组头（isHeader）或任务卡。
class _ListEntry {
  final bool isHeader;
  final String? groupId;
  final String? groupTitle;
  final int? groupCount;
  final MdTask? task;

  const _ListEntry.header(this.groupId, this.groupTitle, this.groupCount)
      : isHeader = true,
        task = null;
  const _ListEntry.task(this.task)
      : isHeader = false,
        groupId = null,
        groupTitle = null,
        groupCount = null;
}

/// 会话分组头：点击（除删除按钮）折叠/展开，右侧删除整个会话组。
class _SessionHeader extends StatelessWidget {
  final String title;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final AppLocalizations l10n;
  final MdIdeTheme theme;

  const _SessionHeader({
    required this.title,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.onDelete,
    required this.l10n,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8, top: 2),
      padding: const EdgeInsets.only(left: 4, right: 4, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: theme.sidebar,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Row(
        children: [
          // 折叠/展开区（箭头 + 标题 + 计数）；删除按钮独立避免手势冲突
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      collapsed ? Icons.chevron_right : Icons.expand_more,
                      size: 16,
                      color: theme.muted,
                    ),
                  ),
                  Icon(Icons.forum_outlined, size: 13, color: theme.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: theme.foreground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$count ${l10n.mdRounds}',
                    style: TextStyle(fontSize: 10, color: theme.faint),
                  ),
                ],
              ),
            ),
          ),
          _CardAction(
            icon: Icons.delete_outline,
            tooltip: l10n.mdDeleteSession,
            onTap: onDelete,
            color: theme.error,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

/// 输入框行的可点击胶囊选择器（执行器 / AI 服务商）。
///
/// 点击后在芯片下方弹出 [showMenu]；文本可收缩 + ellipsis，防止长名称撑爆行。
class _SelectorChip<T> extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final MdIdeTheme theme;
  final List<PopupMenuEntry<T>> Function() items;
  final ValueChanged<T> onSelected;

  const _SelectorChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.theme,
    required this.items,
    required this.onSelected,
  });

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final pos = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final selected = await showMenu<T>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy + 26, pos.dx, pos.dy + 26),
      color: theme.card,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.borderSubtle),
      ),
      items: items(),
    );
    if (selected != null && context.mounted) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: theme.card,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: iconColor),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: TextStyle(fontSize: 11, color: theme.foreground),
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 14, color: theme.muted),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  final MdIdeTheme theme;

  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: selected ? theme.accentDim : theme.card,
          border: Border.all(
            color: selected ? theme.accent.withAlpha(90) : theme.borderSubtle,
          ),
        ),
        child: Text(
          '$label $count',
          style: TextStyle(
            fontSize: 11,
            color: selected ? theme.accent : theme.muted,
          ),
        ),
      ),
    );
  }
}

/// 任务卡片（95% 宽，110px 高，12px 圆角）。
class _TaskCard extends StatelessWidget {
  final MdTask task;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback onEdit;
  final VoidCallback onView;
  final AppLocalizations l10n;
  final MdIdeTheme theme;

  const _TaskCard({
    required this.task,
    required this.onDelete,
    required this.onRetry,
    required this.onEdit,
    required this.onView,
    required this.l10n,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusStyle(task.status, l10n, theme);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题 + 状态标签
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 13, color: theme.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  task.title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: theme.foreground),
                ),
              ),
              _StatusBadge(label: label, color: color, theme: theme),
            ],
          ),
          const SizedBox(height: 8),
          // 项目路径
          Row(
            children: [
              Icon(Icons.folder_outlined, size: 11, color: theme.faint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  task.projectPath,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: theme.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 模型信息 + 操作按钮
          Row(
            children: [
              Icon(Icons.model_training, size: 11, color: theme.faint),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  task.executor == MdTaskExecutor.employee
                      ? '${task.model} · high'
                      : task.model,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: theme.muted),
                ),
              ),
              if (task.providerName != null) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    '· ${task.providerName}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: theme.faint),
                  ),
                ),
              ],
              const Spacer(),
              if (task.status == MdTaskStatus.failed)
                _CardAction(
                  icon: Icons.refresh,
                  tooltip: l10n.mdRetry,
                  onTap: onRetry,
                  color: theme.accent,
                  theme: theme,
                ),
              _CardAction(
                icon: Icons.visibility_outlined,
                tooltip: l10n.mdViewLog,
                onTap: onView,
                color: theme.info,
                theme: theme,
              ),
              _CardAction(
                icon: Icons.edit_outlined,
                tooltip: l10n.mdEdit,
                onTap: onEdit,
                theme: theme,
              ),
              _CardAction(icon: Icons.delete_outline, tooltip: l10n.mdDelete, onTap: onDelete, color: theme.error, theme: theme),
            ],
          ),
          // CLI 任务：实时会话日志（运行中自动贴底滚动）
          if (task.transcript.isNotEmpty) ...[
            const SizedBox(height: 6),
            _TaskLogBox(task: task, l10n: l10n, theme: theme),
          ],
        ],
      ),
    );
  }

  (String, Color) _statusStyle(MdTaskStatus status, AppLocalizations l10n, MdIdeTheme theme) {
    // 新会话草稿（waiting 且未填 prompt）：显示「新会话」标签而非「排队中」
    if (status == MdTaskStatus.waiting && task.prompt == null) {
      return (l10n.mdNewSession, theme.accent);
    }
    switch (status) {
      case MdTaskStatus.waiting: return (l10n.mdStatusWaiting, theme.muted);
      case MdTaskStatus.running: return (l10n.mdStatusRunning, theme.info);
      case MdTaskStatus.failed: return (l10n.mdStatusFailed, theme.error);
      case MdTaskStatus.completed: return (l10n.mdStatusCompleted, theme.success);
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final MdIdeTheme theme;
  const _StatusBadge({required this.label, required this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  final MdIdeTheme theme;

  const _CardAction({required this.icon, required this.tooltip, required this.onTap, this.color, required this.theme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 22,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          color: theme.sidebar,
        ),
        child: Icon(icon, size: 12, color: color ?? theme.muted),
      ),
    );
  }
}

/// 任务卡片内的实时会话日志（CLI 任务运行时逐行追加）。
///
/// 有结构化事件（events）时渲染富视图：Markdown 文本块 + 🔧 工具进度行；
/// 旧数据（无 events）回退为纯文本行。reverse ListView：新内容在底部，
/// 自动贴底展示最新输出；超长纯文本行按 240 字符切块，避免布局开销过大。
class _TaskLogBox extends StatelessWidget {
  final MdTask task;
  final AppLocalizations l10n;
  final MdIdeTheme theme;

  const _TaskLogBox({required this.task, required this.l10n, required this.theme});

  List<String> _lines() {
    final out = <String>[];
    for (final line in task.transcript.split('\n')) {
      if (line.length <= 240) {
        out.add(line);
      } else {
        for (var i = 0; i < line.length; i += 240) {
          out.add(line.substring(i, i + 240 > line.length ? line.length : i + 240));
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final running = task.status == MdTaskStatus.running;
    final hasEvents = task.events.isNotEmpty || task.pendingText.isNotEmpty;
    final items = hasEvents
        ? buildSessionItems(
            events: task.events,
            pendingText: task.pendingText,
            theme: theme,
          )
        : null;
    final lines = hasEvents ? null : _lines();

    // 非运行且无内容：不渲染日志区（避免空白框）
    if (!running && (items ?? const []).isEmpty && (lines ?? const []).isEmpty) {
      return const SizedBox.shrink();
    }

    // 展开内容：结构化事件（md 块 + 工具行）或旧数据纯文本行
    final expanded = <Widget>[];
    if (hasEvents) {
      expanded.addAll(items!);
    } else if (lines != null && lines.isNotEmpty) {
      for (final line in lines) {
        expanded.add(Text(
          line,
          style: TextStyle(
            fontSize: 10,
            height: 1.35,
            color: theme.muted,
            fontFamily: 'monospace',
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.terminal, size: 10, color: theme.faint),
            const SizedBox(width: 4),
            Text(l10n.mdSessionLog, style: TextStyle(fontSize: 10, color: theme.faint)),
            const SizedBox(width: 6),
            Text(
              hasEvents
                  ? '${task.events.length} events'
                  : '${lines!.length} lines',
              style: TextStyle(fontSize: 10, color: theme.faint),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: theme.sidebar,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.borderSubtle),
          ),
          // 运行中：固定高度滚动框（reverse 贴底看最新输出，防卡片跳动）；
          // 完成后：默认展开完整内容（高度自适应，随任务卡片列表滚动）
          child: running
              ? SizedBox(
                  height: 110,
                  child: expanded.isEmpty
                      ? Text(l10n.mdStatusRunning, style: TextStyle(fontSize: 10, color: theme.faint))
                      : ListView.builder(
                          reverse: true,
                          padding: EdgeInsets.zero,
                          itemCount: expanded.length,
                          itemBuilder: (context, i) => expanded[expanded.length - 1 - i],
                        ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: expanded,
                ),
        ),
      ],
    );
  }
}
