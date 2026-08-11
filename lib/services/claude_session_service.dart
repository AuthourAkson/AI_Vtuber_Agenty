import 'dart:convert';
import 'dart:io';

import '../models/md_task.dart';

/// Claude Code 历史会话信息（从 ~/.claude/projects/<编码目录>/*.jsonl 解析）。
///
/// 每个 .jsonl 文件 = 一个会话。id 为文件名去扩展名（即 --resume 的 session id）。
class ClaudeSessionInfo {
  final String id;
  final String title;
  final DateTime modified;
  final int lineCount;

  const ClaudeSessionInfo({
    required this.id,
    required this.title,
    required this.modified,
    required this.lineCount,
  });
}

/// 读取 Claude Code 本地会话（会话管理能力来自 Claude Code 自身）。
///
/// 会话目录规则：`~/.claude/projects/<项目路径编码>/`，编码 = 路径中所有
/// 非字母数字字符替换为 `-`（例：`D:\AiVtuber_Agent-Web` → `D--AiVtuber-Agent-Web`，
/// 与 Claude Code 实际落盘目录一致，本机已验证）。
class ClaudeSessionService {
  /// 项目路径 → Claude Code 会话目录名（与官方编码规则一致）。
  static String encodeProjectDir(String projectPath) =>
      projectPath.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-');

  /// `~/.claude` 根目录（Windows 为 %USERPROFILE%\.claude）。
  static String get claudeHomeDir {
    final profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      return '$profile\\.claude';
    }
    return '${Platform.environment['HOME'] ?? '.'}\\.claude';
  }

  /// 列出当前项目的 Claude Code 历史会话（按修改时间倒序，最多 30 个）。
  static Future<List<ClaudeSessionInfo>> listSessions(String projectPath) async {
    final dir = Directory('$claudeHomeDir\\projects\\${encodeProjectDir(projectPath)}');
    if (!dir.existsSync()) return const [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    final result = <ClaudeSessionInfo>[];
    for (final f in files.take(30)) {
      final stat = f.statSync();
      result.add(ClaudeSessionInfo(
        id: f.uri.pathSegments.last.replaceAll('.jsonl', ''),
        title: await _extractTitle(f),
        modified: stat.modified,
        lineCount: stat.size > 0 ? _countLines(f) : 0,
      ));
    }
    return result;
  }

  /// 从 jsonl 提取会话标题：优先最后一个 summary 事件，其次首条 user 消息。
  static Future<String> _extractTitle(File file) async {
    String? summary;
    String? firstUser;
    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Object? obj;
        try {
          obj = jsonDecode(line);
        } catch (_) {
          continue;
        }
        if (obj is! Map<String, dynamic>) continue;
        final type = obj['type'] as String?;
        if (type == 'summary') {
          final s = obj['summary'] as String?;
          if (s != null && s.trim().isNotEmpty) summary = s;
        } else if (type == 'user' && firstUser == null) {
          final msg = obj['message'] as Map<String, dynamic>?;
          firstUser = _extractUserText(msg?['content']);
        }
      }
    } catch (_) {
      // 文件损坏/读取失败 → 走兜底标题
    }
    final raw = summary ?? firstUser;
    if (raw == null || raw.trim().isEmpty) return 'Untitled';
    // 清洗：压平换行/制表符，截断
    final flat = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length > 60 ? '${flat.substring(0, 60)}...' : flat;
  }

  /// user 消息 content 可能是字符串或内容块数组，统一提取文本。
  static String? _extractUserText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buf = StringBuffer();
      for (final block in content) {
        if (block is Map && block['type'] == 'text') {
          final t = block['text'] as String?;
          if (t != null && t.isNotEmpty) buf.writeln(t);
        }
      }
      return buf.toString().trim();
    }
    return null;
  }

  /// 解析历史会话文件为结构化事件（供查看卡片富渲染）。
  ///
  /// 返回 null 表示会话文件不存在/解析失败。events 与 transcript 双层级与实时
  /// CLI 任务保持一致：text 块（Markdown 渲染）/ 🔧 工具行（tool_result 配对写
  /// 耗时）/ 纯文本 transcript（复制用）。未配对的工具视为完成（endMs=startMs），
  /// 避免查看卡片上 spinner 永远转。
  static Future<({List<MdTaskEvent> events, String transcript})?> parseSession(
      String projectPath, String sessionId) async {
    final file = File(
        '$claudeHomeDir\\projects\\${encodeProjectDir(projectPath)}\\$sessionId.jsonl');
    if (!file.existsSync()) return null;

    final events = <MdTaskEvent>[];
    final buf = StringBuffer();
    final pending = <String, MdTaskEvent>{}; // toolId → 未完成工具事件

    try {
      final lines = await file.readAsLines();
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        Object? obj;
        try {
          obj = jsonDecode(line);
        } catch (_) {
          continue;
        }
        if (obj is! Map<String, dynamic>) continue;
        final ts = _tsMs(obj['timestamp']);
        switch (obj['type'] as String?) {
          case 'user':
            final msg = obj['message'] as Map<String, dynamic>?;
            final content = msg?['content'];
            if (content is String && content.trim().isNotEmpty) {
              _addText(events, buf, content);
            } else if (content is List) {
              for (final block in content) {
                if (block is! Map<String, dynamic>) continue;
                if (block['type'] == 'tool_result') {
                  final tid = block['tool_use_id'] as String?;
                  final e = tid != null ? pending.remove(tid) : null;
                  if (e != null) {
                    final s = e.startMs ?? 0;
                    e.endMs = (ts > 0 && ts >= s) ? ts : s + 1;
                  }
                } else if (block['type'] == 'text') {
                  final t = block['text'] as String?;
                  if (t != null && t.trim().isNotEmpty) _addText(events, buf, t);
                }
              }
            }
          case 'assistant':
            final msg = obj['message'] as Map<String, dynamic>?;
            final content = msg?['content'];
            if (content is List) {
              for (final block in content) {
                if (block is! Map<String, dynamic>) continue;
                final btype = block['type'];
                if (btype == 'text') {
                  final t = block['text'] as String?;
                  if (t != null && t.trim().isNotEmpty) _addText(events, buf, t);
                } else if (btype == 'tool_use') {
                  final tid = block['id'] as String?;
                  final name = block['name'] as String? ?? 'tool';
                  final input = jsonEncode(block['input'] ?? const {});
                  final shown = input.length > 160
                      ? '${input.substring(0, 160)}...'
                      : input;
                  final e = MdTaskEvent(
                    type: MdEventType.tool,
                    content: shown,
                    toolName: name,
                    toolId: tid,
                    startMs: ts > 0 ? ts : null,
                  );
                  events.add(e);
                  if (tid != null) pending[tid] = e;
                  buf.writeln('\n⚙ $name $shown');
                }
              }
            }
          default:
            break; // system / queue-operation / summary 等噪音忽略
        }
      }
    } catch (_) {
      return null;
    }
    // 未配对工具：不显示 spinner（查看场景无实时性），视为瞬间完成
    for (final e in pending.values) {
      e.endMs = e.endMs ?? e.startMs;
    }
    return (events: events, transcript: buf.toString());
  }

  static int _tsMs(Object? ts) {
    if (ts is! String) return 0;
    return DateTime.tryParse(ts)?.millisecondsSinceEpoch ?? 0;
  }

  static void _addText(List<MdTaskEvent> events, StringBuffer buf, String text) {
    // events 内容截断防大文本拖垮渲染；transcript 保留全文供复制
    events.add(MdTaskEvent(
      type: MdEventType.text,
      content: text.length > 800 ? '${text.substring(0, 800)}...' : text,
    ));
    buf.writeln(text);
  }

  /// 删除历史会话文件（jsonl）。返回是否删除成功。
  static Future<bool> deleteSession(String projectPath, String sessionId) async {
    try {
      final file = File(
          '$claudeHomeDir\\projects\\${encodeProjectDir(projectPath)}\\$sessionId.jsonl');
      if (!file.existsSync()) return false;
      await file.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static int _countLines(File file) {
    try {
      return file.readAsLinesSync().length;
    } catch (_) {
      return 0;
    }
  }
}
