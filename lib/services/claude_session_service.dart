import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/md_task.dart';

/// Claude Code 历史会话信息（从 ~/.claude/projects/<编码目录>/*.jsonl 解析）。
///
/// 每个 .jsonl 文件 = 一个会话。id 为文件名去扩展名（即 --resume 的 session id）。
class ClaudeSessionInfo {
  final String id;
  final String title;
  final String? projectName;
  final DateTime modified;
  final int lineCount;

  const ClaudeSessionInfo({
    required this.id,
    required this.title,
    required this.modified,
    required this.lineCount,
    this.projectName,
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
      final extracted = await _extractTitle(f);
      // 过滤空壳 jsonl（无 user 消息也无 summary，如启动即失败的任务留下的
      // 只有 system/init 行的文件）——它们无标题可提取（Untitled 噪音来源）、
      // 无内容可 resume，不该出现在会话列表
      if (!extracted.hasContent) continue;
      result.add(ClaudeSessionInfo(
        id: f.uri.pathSegments.last.replaceAll('.jsonl', ''),
        title: extracted.title,
        projectName: extracted.projectName,
        modified: stat.modified,
        lineCount: stat.size > 0 ? _countLines(f) : 0,
      ));
    }
    return result;
  }

  /// 从 jsonl 提取会话标题 + 项目名 + 是否有内容。
  ///
  /// 标题：优先最后一个 summary 事件，其次首条 user 消息。⚠️ MarkdownText 产生的
  /// 会话**没有 summary 事件**（Claude Code 只给 CLI 交互写 summary），首条 user
  /// 消息是 `[MarkdownText Task]` 任务模板——此时提取 `User request:` 后的真实
  /// 提示词做标题（比整段模板截断可读得多），`Project:` 行做项目名（meta 显示）。
  /// hasContent：扫描到 user 或 summary 即为有内容；只有 system/init 行的空壳
  /// jsonl（启动即失败的任务遗留）无标题可提取，由 listSessions 过滤。
  ///
  /// ⚠️ 性能：jsonl 可能数 MB，全文件 readAsLines 会在每次列表刷新时把每个
  /// 会话文件整读一遍（30 个会话 = 30 次全读，进页面/任务完成都会卡）。
  /// 改为分段读取：头部 64KB 找首条 user 消息（几乎总在文件开头）、尾部
  /// 64KB 找 summary（Claude Code 的 summary 事件写到最后）。分段边界可能
  /// 切断一行 JSON / 半个 UTF-8 字符——jsonDecode 失败跳过、utf8 允许
  /// malformed，均安全。
  static Future<({String title, String? projectName, bool hasContent})>
      _extractTitle(File file) async {
    String? summary;
    String? firstUser;
    String? projectName;
    var hasContent = false;

    void scanText(String text) {
      for (final line in text.split('\n')) {
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
          if (s != null && s.trim().isNotEmpty) {
            summary = s;
            hasContent = true;
          }
        } else if (type == 'user') {
          final msg = obj['message'] as Map<String, dynamic>?;
          final text = _extractUserText(msg?['content']);
          if (text != null && text.trim().isNotEmpty) {
            hasContent = true;
            if (firstUser == null) {
              firstUser = text;
              // MarkdownText 任务模板：`Project: <path>` 行 → 项目名（取末段）
              final m = RegExp(r'Project:\s*(\S.*)').firstMatch(text);
              if (m != null) {
                final p = m.group(1)!.trim();
                final seg = p
                    .replaceAll(RegExp(r'[/\\]+$'), '')
                    .split(RegExp(r'[/\\]'))
                    .last;
                projectName ??= seg.isEmpty ? p : seg;
              }
            }
          }
        }
      }
    }

    try {
      final raf = await file.open();
      try {
        final size = await raf.length();
        const head = 64 * 1024;
        if (size <= head) {
          scanText(utf8.decode(await raf.read(size), allowMalformed: true));
        } else {
          // 头部：首条 user 消息；尾部：最后一个 summary（后扫描覆盖）
          scanText(utf8.decode(await raf.read(head), allowMalformed: true));
          await raf.setPosition(size - head);
          scanText(utf8.decode(await raf.read(head), allowMalformed: true));
        }
      } finally {
        await raf.close();
      }
    } catch (_) {
      // 文件损坏/读取失败 → 走兜底标题
    }
    var title = summary ?? firstUser;
    if (title == null || title.trim().isEmpty) title = 'Untitled';
    // MarkdownText 任务模板 → 提取 `User request:` 后的真实提示词
    if (title.contains('[MarkdownText Task]')) {
      final req = RegExp(r'User request:\s*([\s\S]*)').firstMatch(title!);
      if (req != null && req.group(1)!.trim().isNotEmpty) {
        title = req.group(1)!.trim();
      }
    }
    // 清洗：压平换行/制表符，截断
    final flat = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (
      title: flat.length > 60 ? '${flat.substring(0, 60)}...' : flat,
      projectName: projectName,
      hasContent: hasContent,
    );
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

  /// 统计 jsonl 行数（会话选择器元信息展示用）。
  ///
  /// ⚠️ 性能：不整读文件（readAsLinesSync 会为每个会话分配全部行对象），
  /// 分块读字节流统计 `\n` 数量，大文件也只需扫一遍原始字节。
  static int _countLines(File file) {
    try {
      final raf = file.openSync();
      try {
        var count = 0;
        final buf = Uint8List(64 * 1024);
        while (true) {
          final n = raf.readIntoSync(buf);
          if (n <= 0) break;
          for (var i = 0; i < n; i++) {
            if (buf[i] == 0x0A) count++;
          }
        }
        return count; // 行数 ≈ \n 数（末尾无换行的最后一行不计，元信息够用）
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return 0;
    }
  }
}
