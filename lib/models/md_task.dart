import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import '../providers/appearance_provider.dart';

/// MarkdownText IDE 任务模型（wenzmark 风格）。
enum MdTaskStatus {
  waiting('waiting'),
  running('running'),
  failed('failed'),
  completed('completed');

  final String key;
  const MdTaskStatus(this.key);

  static MdTaskStatus fromKey(String key) =>
      MdTaskStatus.values.firstWhere((s) => s.key == key,
          orElse: () => MdTaskStatus.waiting);
}

/// 任务执行器：发送给 MultiAgent 员工，或外接独立 CLI（Claude Code / Codex）。
enum MdTaskExecutor {
  employee('employee'),
  claudeCli('claudeCli'),
  codexCli('codexCli'); // Codex CLI 预留（后续添加）

  final String key;
  const MdTaskExecutor(this.key);

  static MdTaskExecutor fromKey(String key) =>
      MdTaskExecutor.values.firstWhere((e) => e.key == key,
          orElse: () => MdTaskExecutor.employee);
}

/// CLI 会话事件类型：文本块（Markdown 渲染）/ 工具调用（进度卡片）/ 最终结果。
enum MdEventType { text, tool, result }

/// CLI 会话的结构化事件。
///
/// 与 [MdTask.transcript] 并存：events 驱动富渲染（Markdown 文本块 +
/// 🔧 工具进度行 + 耗时），transcript 保留纯文本供复制/旧数据回退。
class MdTaskEvent {
  final MdEventType type;

  /// 文本/结果内容，或工具参数摘要（content_block_start 时可能为空，
  /// assistant 聚合消息到达后用完整 input 更新）。
  String content;

  /// 工具名（Bash / Read / Patch / Glob …），仅 tool 事件。
  final String? toolName;

  /// 工具调用 ID（匹配 tool_result 计算耗时）。
  final String? toolId;
  final int? startMs;

  /// 工具完成时间（tool_result 到达时写入；null = 仍在执行）。
  int? endMs;

  MdTaskEvent({
    required this.type,
    required this.content,
    this.toolName,
    this.toolId,
    this.startMs,
    this.endMs,
  });

  /// 工具是否仍在执行（进行中显示 spinner，完成显示耗时）。
  bool get toolRunning => type == MdEventType.tool && endMs == null;

  /// 工具执行耗时（完成时）。
  Duration? get duration {
    if (startMs == null || endMs == null || endMs! < startMs!) return null;
    return Duration(milliseconds: endMs! - startMs!);
  }

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'content': content,
    'toolName': toolName,
    'toolId': toolId,
    'startMs': startMs,
    'endMs': endMs,
  };

  factory MdTaskEvent.fromJson(Map<String, dynamic> json) => MdTaskEvent(
    type: MdEventType.values.firstWhere(
      (e) => e.name == json['type'],
      orElse: () => MdEventType.text,
    ),
    content: json['content'] as String? ?? '',
    toolName: json['toolName'] as String?,
    toolId: json['toolId'] as String?,
    startMs: (json['startMs'] as num?)?.toInt(),
    endMs: (json['endMs'] as num?)?.toInt(),
  );
}

class MdTask {
  final String id;
  String title;
  MdTaskStatus status;
  final String projectPath;
  final String model;
  final String? employeeId;
  final MdTaskExecutor executor;
  final String? providerName;
  String? prompt;
  final DateTime createdAt;
  String? error;

  /// CLI 运行时的实时会话输出（逐行追加，展示在任务卡片上）。
  String transcript = '';

  /// CLI 会话的结构化事件（工具进度 + Markdown 文本块 + 结果）。
  /// 为空（旧数据/员工任务）时 UI 回退到 [transcript] 纯文本渲染。
  final List<MdTaskEvent> events;

  /// 流式文本累积缓冲：text_delta 先暂存，遇到工具/结果时 flush 成 text 事件。
  /// 不持久化：运行中任务切页恢复即标记 failed，缓冲丢弃无碍。
  String pendingText = '';

  /// 只读会话查看卡片（选中历史 Claude Code 会话时插入，非用户提交的任务）：
  /// 不持久化（_persistTasks 过滤），切页后消失。
  final bool viewOnly;

  /// 所属会话分组 id：历史 Claude Code 会话 = jsonl uuid；新会话 = 'newsession-<ts>'；
  /// null = 无分组（员工任务平铺显示）。⚠️ 可变：平铺 CLI 任务在 result 事件拿到
  /// 实际 session_id 后自动归属到自己的会话组（消除孤儿卡残留）。
  String? sessionId;

  /// 本轮实际使用的 Claude Code 会话 id（result 事件提取；组内下一轮 --resume 用）。
  String? cliSessionId;

  MdTask({
    required this.id,
    required this.title,
    this.status = MdTaskStatus.waiting,
    required this.projectPath,
    this.model = 'Codex',
    this.employeeId,
    this.executor = MdTaskExecutor.employee,
    this.providerName,
    this.prompt,
    DateTime? createdAt,
    this.error,
    this.viewOnly = false,
    this.sessionId,
    this.cliSessionId,
    List<MdTaskEvent>? events,
  }) : createdAt = createdAt ?? DateTime.now(),
       events = events ?? [];

  /// 序列化为 JSON（用于任务列表持久化：切页后 State 销毁重建可恢复）。
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'status': status.key,
    'projectPath': projectPath,
    'model': model,
    'employeeId': employeeId,
    'executor': executor.key,
    'providerName': providerName,
    'prompt': prompt,
    'createdAt': createdAt.toIso8601String(),
    'error': error,
    'transcript': transcript,
    'events': [for (final e in events) e.toJson()],
    'viewOnly': viewOnly,
    'sessionId': sessionId,
    'cliSessionId': cliSessionId,
  };

  factory MdTask.fromJson(Map<String, dynamic> json) => MdTask(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    status: MdTaskStatus.fromKey(json['status'] as String? ?? 'waiting'),
    projectPath: json['projectPath'] as String? ?? '',
    model: json['model'] as String? ?? 'Codex',
    employeeId: json['employeeId'] as String?,
    executor: MdTaskExecutor.fromKey(json['executor'] as String? ?? 'employee'),
    providerName: json['providerName'] as String?,
    prompt: json['prompt'] as String?,
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    error: json['error'] as String?,
    viewOnly: json['viewOnly'] as bool? ?? false,
    sessionId: json['sessionId'] as String?,
    cliSessionId: json['cliSessionId'] as String?,
    events: (json['events'] as List?)
        ?.map((e) => MdTaskEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
  )..transcript = json['transcript'] as String? ?? '';
}

/// wenzmark 风格 IDE 动态主题。
///
/// 通过 [MdIdeTheme.of] 读取全局 AppearanceProvider：
/// - 深/浅色板跟随 `darkMode`
/// - 强调色跟随 `themeColor`（themeColorEnabled 时）
/// - 状态色（成功/错误/警告/信息）在浅色下加深保证对比度
class MdIdeTheme {
  final bool isDark;
  final Color accent;

  const MdIdeTheme({required this.isDark, required this.accent});

  static MdIdeTheme of(BuildContext context) {
    final ap = context.watch<AppearanceProvider>();
    return MdIdeTheme(
      isDark: ap.isDark,
      accent: Color(ap.accentColorValue),
    );
  }

  // ── 背景层级（深色参照 gpt-advice.md / VS Code Dark+）──

  Color get background => isDark ? const Color(0xFF101214) : const Color(0xFFF6F6F4);
  Color get sidebar => isDark ? const Color(0xFF151718) : const Color(0xFFECECE9);
  Color get editor => isDark ? const Color(0xFF111315) : const Color(0xFFFAFAF8);
  Color get card => isDark ? const Color(0xFF191C1F) : const Color(0xFFFFFFFF);
  Color get cardHover => isDark ? const Color(0xFF1E2226) : const Color(0xFFF1F1EE);
  Color get border => isDark ? const Color(0xFF303438) : const Color(0xFFD6D6D3);
  Color get borderSubtle => isDark ? const Color(0xFF23272B) : const Color(0xFFE5E5E2);

  // ── 文字 ──

  Color get foreground => isDark ? const Color(0xFFE6E6E6) : const Color(0xFF1A1C1E);
  Color get muted => isDark ? const Color(0xFF8B8F94) : const Color(0xFF6B7075);
  Color get faint => isDark ? const Color(0xFF5A5E63) : const Color(0xFF9A9EA3);

  // ── 强调 ──

  Color get accentDim => accent.withAlpha(0x33);

  // ── 状态色 ──

  Color get success => isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color get error => isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  Color get warning => isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
  Color get info => isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
}
