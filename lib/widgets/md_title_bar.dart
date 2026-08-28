import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/md_task.dart';

/// wenzmark 风格顶部菜单栏（约 35px）。
///
/// 左侧：Logo + 返回/前进 + 菜单（文件/编辑/视图/窗口/帮助）
/// 右侧：AI / 文档 / 主题 / 设置
/// 窗口控制按钮由主窗口 32px 系统标题栏负责，本页不重复放置。
class MdTitleBar extends StatelessWidget {
  final bool canBack;
  final bool canForward;
  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final VoidCallback? onOpenAi;
  final VoidCallback? onOpenDocs;
  final VoidCallback? onToggleTheme;

  /// AI 面板是否显示（控制 AI 按钮高亮态，实现侧栏开关的视觉反馈）。
  final bool aiActive;

  const MdTitleBar({
    super.key,
    required this.canBack,
    required this.canForward,
    this.onBack,
    this.onForward,
    this.onOpenAi,
    this.onOpenDocs,
    this.onToggleTheme,
    this.aiActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = MdIdeTheme.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      height: 35,
      color: theme.sidebar,
      child: Row(
        children: [
          // Logo
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, size: 14, color: theme.accent),
                const SizedBox(width: 6),
                Text(
                  'AgentMark',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.foreground,
                  ),
                ),
              ],
            ),
          ),
          // Back / Forward
          _IconButton(
            icon: Icons.arrow_back_ios_new,
            onTap: canBack ? onBack : null,
            theme: theme,
          ),
          _IconButton(
            icon: Icons.arrow_forward_ios,
            onTap: canForward ? onForward : null,
            theme: theme,
          ),
          const SizedBox(width: 6),
          // Menu items
          _MenuLabel(text: l10n.mdMenuFile, theme: theme),
          _MenuLabel(text: l10n.mdMenuEdit, theme: theme),
          _MenuLabel(text: l10n.mdMenuView, theme: theme),
          _MenuLabel(text: l10n.mdMenuWindow, theme: theme),
          _MenuLabel(text: l10n.mdMenuHelp, theme: theme),
          const Spacer(),
          // Right side buttons
          _ActionButton(
            label: l10n.mdAiButton,
            icon: Icons.auto_awesome,
            onTap: onOpenAi,
            highlighted: aiActive,
            theme: theme,
          ),
          _ActionButton(
            label: l10n.mdDocsButton,
            icon: Icons.description_outlined,
            onTap: onOpenDocs,
            theme: theme,
          ),
          _IconButton(
            icon: Icons.light_mode_outlined,
            onTap: onToggleTheme,
            theme: theme,
          ),
          _IconButton(
            icon: Icons.settings_outlined,
            onTap: () {},
            theme: theme,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  final String text;
  final MdIdeTheme theme;
  const _MenuLabel({required this.text, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Text(text, style: TextStyle(fontSize: 12, color: theme.muted)),
    );
  }
}

class _IconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final MdIdeTheme theme;
  const _IconButton({required this.icon, this.onTap, required this.theme});

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 26,
          height: 26,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: enabled && _hovered ? theme.cardHover : Colors.transparent,
          ),
          child: Icon(
            widget.icon,
            size: 13,
            color: enabled ? theme.foreground : theme.faint,
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlighted;
  final MdIdeTheme theme;
  const _ActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.highlighted = false,
    required this.theme,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final highlighted = widget.highlighted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: _hovered
                ? (highlighted ? theme.accent.withAlpha(0x4D) : theme.cardHover)
                : (highlighted ? theme.accentDim : theme.card),
            border: Border.all(
              color: highlighted
                  ? theme.accent.withAlpha(90)
                  : (_hovered ? theme.border : theme.borderSubtle),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 12,
                color: highlighted
                    ? theme.accent
                    : (_hovered ? theme.foreground : theme.muted),
              ),
              const SizedBox(width: 4),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 11,
                  color: highlighted ? theme.accent : theme.foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
