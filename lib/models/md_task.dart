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

class MdTask {
  final String id;
  final String title;
  MdTaskStatus status;
  final String projectPath;
  final String model;
  final String? employeeId;
  final DateTime createdAt;
  String? error;

  MdTask({
    required this.id,
    required this.title,
    this.status = MdTaskStatus.waiting,
    required this.projectPath,
    this.model = 'Codex',
    this.employeeId,
    DateTime? createdAt,
    this.error,
  }) : createdAt = createdAt ?? DateTime.now();
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
