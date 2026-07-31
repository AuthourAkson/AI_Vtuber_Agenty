import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';

/// wenzmark 风格右侧 AI 任务中心。
///
/// 结构：任务搜索框 → 状态筛选行 → 任务卡片列表 → AI 输入框（100px）。
class MdAiTaskPanel extends StatefulWidget {
  final List<MdTask> tasks;
  final String? selectedEmployeeName;
  final ValueChanged<String> onPromptSubmitted;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<MdTaskStatus?> onFilterChanged;
  final ValueChanged<MdTask> onDeleteTask;
  final ValueChanged<MdTask> onRetryTask;
  final VoidCallback onPickEmployee;

  const MdAiTaskPanel({
    super.key,
    required this.tasks,
    required this.selectedEmployeeName,
    required this.onPromptSubmitted,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onDeleteTask,
    required this.onRetryTask,
    required this.onPickEmployee,
  });

  @override
  State<MdAiTaskPanel> createState() => _MdAiTaskPanelState();
}

class _MdAiTaskPanelState extends State<MdAiTaskPanel> {
  final _searchCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  MdTaskStatus? _filter;

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

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final tasks = _visibleTasks;
    final counts = _counts();

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
          // ── 任务卡片列表 ──
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
                    itemCount: tasks.length,
                    itemBuilder: (context, i) => _TaskCard(
                      task: tasks[i],
                      onDelete: () => widget.onDeleteTask(tasks[i]),
                      onRetry: () => widget.onRetryTask(tasks[i]),
                      l10n: l10n,
                      theme: theme,
                    ),
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
              Icon(Icons.attach_file, size: 14, color: theme.faint),
              const SizedBox(width: 8),
              // 员工选择（点击切换）
              GestureDetector(
                onTap: widget.onPickEmployee,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.card,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: theme.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.smart_toy_outlined, size: 11, color: theme.accent),
                      const SizedBox(width: 4),
                      Text(
                        widget.selectedEmployeeName ?? l10n.mdSelectEmployee,
                        style: TextStyle(fontSize: 11, color: theme.foreground),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down, size: 14, color: theme.muted),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.card,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: theme.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.speed, size: 11, color: theme.muted),
                    const SizedBox(width: 4),
                    Text('high', style: TextStyle(fontSize: 11, color: theme.foreground)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_drop_down, size: 14, color: theme.muted),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _submit,
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: theme.accent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.add, size: 18, color: theme.background),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskCounts {
  final int total, queue, failed, pending, completed;
  const _TaskCounts(this.total, this.queue, this.failed, this.pending, this.completed);
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
  final AppLocalizations l10n;
  final MdIdeTheme theme;

  const _TaskCard({
    required this.task,
    required this.onDelete,
    required this.onRetry,
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
              Text(
                task.model,
                style: TextStyle(fontSize: 10, color: theme.muted),
              ),
              Text(
                ' · high',
                style: TextStyle(fontSize: 10, color: theme.faint),
              ),
              const Spacer(),
              if (task.status == MdTaskStatus.failed)
                _CardAction(
                  icon: Icons.refresh,
                  tooltip: l10n.mdRetry,
                  onTap: onRetry,
                  color: theme.accent,
                  theme: theme,
                ),
              _CardAction(icon: Icons.edit_outlined, tooltip: l10n.mdEdit, onTap: () {}, theme: theme),
              _CardAction(icon: Icons.delete_outline, tooltip: l10n.mdDelete, onTap: onDelete, color: theme.error, theme: theme),
            ],
          ),
        ],
      ),
    );
  }

  (String, Color) _statusStyle(MdTaskStatus status, AppLocalizations l10n, MdIdeTheme theme) {
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
