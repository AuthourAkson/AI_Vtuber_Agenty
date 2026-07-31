import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';

/// wenzmark 风格底部状态栏（24px）。
///
/// 左：项目路径 > 目录
/// 右：锁 / 附件 / 未保存 / 行词字符统计 / 任务数
class MdBottomStatusBar extends StatelessWidget {
  final String projectRoot;
  final String currentPath;
  final bool dirty;
  final String content;
  final int taskCount;

  const MdBottomStatusBar({
    super.key,
    required this.projectRoot,
    required this.currentPath,
    required this.dirty,
    required this.content,
    required this.taskCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);
    final (lines, words, chars) = _stats(content);
    final statsText = l10n.mdLinesWordsChars
        .replaceAll(r'${lines}', '$lines')
        .replaceAll(r'${words}', '$words')
        .replaceAll(r'${chars}', '$chars');

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: theme.sidebar,
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 10, color: theme.faint),
          const SizedBox(width: 8),
          // 路径 breadcrumb
          Expanded(
            child: Text(
              _breadcrumb(),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: theme.muted),
            ),
          ),
          const SizedBox(width: 8),
          Icon(Icons.attach_file, size: 10, color: theme.faint),
          const SizedBox(width: 4),
          Text(l10n.mdAllAttachments, style: TextStyle(fontSize: 10, color: theme.muted)),
          const SizedBox(width: 12),
          Text(
            dirty ? l10n.mdUnsaved : l10n.mdSaved,
            style: TextStyle(
              fontSize: 10,
              color: dirty ? theme.warning : theme.faint,
            ),
          ),
          const SizedBox(width: 12),
          Text(statsText, style: TextStyle(fontSize: 10, color: theme.muted)),
          const SizedBox(width: 12),
          Icon(Icons.check_circle_outline, size: 10, color: theme.success),
          const SizedBox(width: 4),
          Text('$taskCount${l10n.mdTasksSuffix}', style: TextStyle(fontSize: 10, color: theme.muted)),
        ],
      ),
    );
  }

  String _breadcrumb() {
    if (projectRoot.isEmpty) return 'wenzmark';
    final parts = projectRoot.replaceAll('\\', '/').split('/').where((p) => p.isNotEmpty).toList();
    final project = parts.isEmpty ? 'wenzmark' : parts.last;
    if (currentPath.isEmpty) return project;
    return '$project > ${currentPath.replaceAll('/', ' > ')}';
  }

  (int, int, int) _stats(String text) {
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;
    final words = text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;
    return (lines, words, text.length);
  }
}
