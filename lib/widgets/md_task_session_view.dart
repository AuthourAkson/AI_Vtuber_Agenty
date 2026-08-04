import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/md_task.dart';

/// CLI 任务会话的富渲染展示项构建器。
///
/// 把结构化事件（[MdTaskEvent]）转成 widget 列表，供两处复用：
/// - 任务卡片内的会话日志（reverse ListView 贴底滚动）
/// - 「查看」弹窗的完整会话（普通 Column + 滚动）
///
/// 渲染规则（对应 Claude Code 执行过程，Hermes 风格）：
/// - text / result 事件 → Markdown 渲染（表格/代码块/标题正常显示）
/// - tool 事件        → 🔧 进度行：工具名 + 参数摘要 + spinner（进行中）/ 耗时（完成）
/// - pendingText      → 运行中的流式尾部（纯文本，避免高频重渲 Markdown 卡顿）
List<Widget> buildSessionItems({
  required List<MdTaskEvent> events,
  required String pendingText,
  required MdIdeTheme theme,
  double fontSize = 11,
  EdgeInsets padding = const EdgeInsets.symmetric(vertical: 2),
}) {
  final items = <Widget>[];
  for (final e in events) {
    switch (e.type) {
      case MdEventType.text:
      case MdEventType.result:
        items.add(Padding(
          padding: padding,
          child: _MdBlock(text: e.content, theme: theme, fontSize: fontSize),
        ));
      case MdEventType.tool:
        items.add(Padding(
          padding: padding,
          child: _ToolRow(event: e, theme: theme, fontSize: fontSize),
        ));
    }
  }
  final pending = pendingText.trim();
  if (pending.isNotEmpty) {
    // 运行中尾部：只显示最近 600 字符，纯文本渲染（节流刷新时轻量）
    final shown = pending.length > 600 ? pending.substring(pending.length - 600) : pending;
    items.add(Padding(
      padding: padding,
      child: Text(
        shown,
        style: TextStyle(
          fontSize: fontSize - 1,
          height: 1.35,
          color: theme.muted,
          fontFamily: 'monospace',
        ),
      ),
    ));
  }
  return items;
}

/// 工具耗时标签（0.3s / 1m 12s）。
String formatToolDuration(Duration? d) {
  if (d == null) return '';
  final ms = d.inMilliseconds;
  if (ms < 1000) return '${ms}ms';
  if (ms < 60000) return '${(ms / 1000).toStringAsFixed(1)}s';
  return '${d.inMinutes}m ${d.inSeconds % 60}s';
}

/// Markdown 文本块（小字号，跟随 MdIdeTheme 配色）。
class _MdBlock extends StatelessWidget {
  final String text;
  final MdIdeTheme theme;
  final double fontSize;

  const _MdBlock({
    required this.text,
    required this.theme,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: text,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(fontSize: fontSize, color: theme.foreground, height: 1.45),
        code: TextStyle(
          fontSize: fontSize - 1,
          fontFamily: 'monospace',
          color: theme.info,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.borderSubtle),
        ),
        codeblockPadding: const EdgeInsets.all(8),
        h1: TextStyle(fontSize: fontSize + 2, fontWeight: FontWeight.bold, color: theme.foreground),
        h2: TextStyle(fontSize: fontSize + 1, fontWeight: FontWeight.bold, color: theme.foreground),
        h3: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold, color: theme.foreground),
        listBullet: TextStyle(fontSize: fontSize, color: theme.foreground),
        blockquoteDecoration: BoxDecoration(
          border: Border(left: BorderSide(color: theme.accent, width: 2)),
        ),
        blockquotePadding: const EdgeInsets.only(left: 8),
        a: TextStyle(color: theme.accent, fontSize: fontSize),
        tableHead: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: theme.foreground,
        ),
        tableBody: TextStyle(fontSize: fontSize, color: theme.foreground),
        tableBorder: TableBorder.all(color: theme.borderSubtle),
      ),
    );
  }
}

/// 🔧 工具执行进度行：图标 + 工具名 + 参数摘要 + 状态（spinner / 耗时）。
class _ToolRow extends StatelessWidget {
  final MdTaskEvent event;
  final MdIdeTheme theme;
  final double fontSize;

  const _ToolRow({
    required this.event,
    required this.theme,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final running = event.toolRunning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.card,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: running ? theme.accent.withAlpha(60) : theme.borderSubtle,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.construction,
            size: 12,
            color: running ? theme.accent : theme.muted,
          ),
          const SizedBox(width: 6),
          Text(
            event.toolName ?? 'tool',
            style: TextStyle(
              fontSize: fontSize - 0.5,
              fontWeight: FontWeight.w600,
              color: theme.foreground,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              event.content,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: fontSize - 1,
                color: theme.muted,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (running)
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: theme.accent),
            )
          else
            Text(
              formatToolDuration(event.duration),
              style: TextStyle(
                fontSize: fontSize - 1.5,
                color: theme.faint,
                fontFamily: 'monospace',
              ),
            ),
        ],
      ),
    );
  }
}
