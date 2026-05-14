import 'package:flutter/material.dart';
import '../app.dart';

/// Collapsible sidebar matching LocalAIVtuber2's shadcn/ui Sidebar.
/// - Expanded: 200px wide, icon + text
/// - Collapsed: 48px wide, icon only with tooltip
/// Uses AnimatedContainer for smooth, reliable animation.
class AppSidebar extends StatefulWidget {
  final String activePage;
  final Function(String) onPageSelected;

  const AppSidebar({
    super.key,
    required this.activePage,
    required this.onPageSelected,
  });

  @override
  State<AppSidebar> createState() => _AppSidebarState();
}

class _AppSidebarState extends State<AppSidebar> {
  bool _expanded = true;

  // Match LAV2 page-mapping sections exactly
  static const _testPipeline = ['home', 'character', 'memory'];
  static const _footer = [
    'input',
    'vision',
    'tts',
    'pipeline',
    'stream',
    'settings',
  ];

  static const _icons = {
    'home': Icons.home,
    'character': Icons.person,
    'memory': Icons.storage_rounded,
    'input': Icons.mic,
    'vision': Icons.remove_red_eye,
    'tts': Icons.record_voice_over,
    'pipeline': Icons.square_foot,
    'stream': Icons.cast,
    'settings': Icons.settings,
  };

  static const _titles = {
    'home': 'Home',
    'character': 'Character',
    'memory': 'Memory',
    'input': 'Input',
    'vision': 'Vision',
    'tts': 'TTS',
    'pipeline': 'Pipeline',
    'stream': 'Stream',
    'settings': 'Settings',
  };

  void _toggle() => setState(() => _expanded = !_expanded);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: _expanded ? 200.0 : 48.0,
      decoration: const BoxDecoration(
        color: ShadColors.sidebar,
        border: Border(
          right: BorderSide(color: ShadColors.sidebarBorder),
        ),
      ),
      child: Column(
        children: [
          // Toggle button
          _buildToggle(),
          const SizedBox(height: 8),
          // Test Pipeline section label
          if (_expanded)
            const Padding(
              padding: EdgeInsets.only(left: 12, bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Test pipeline',
                  style: TextStyle(
                    fontSize: 11,
                    color: ShadColors.mutedForeground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ..._testPipeline.map((key) => _navItem(key)),
          const Spacer(),
          // Footer separator
          Container(
            height: 1,
            color: ShadColors.sidebarBorder,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          const SizedBox(height: 4),
          ..._footer.map((key) => _navItem(key)),
          const SizedBox(height: 4),
          // Dark mode indicator
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Icon(
              Icons.dark_mode,
              size: 16,
              color: ShadColors.mutedForeground.withAlpha(140),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: ShadColors.sidebarAccent,
            ),
            child: Icon(
              _expanded ? Icons.chevron_left : Icons.chevron_right,
              size: 14,
              color: ShadColors.mutedForeground,
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(String key) {
    final isActive = widget.activePage == key;
    final title = _titles[key] ?? key;
    final icon = _icons[key] ?? Icons.circle;

    Widget item = GestureDetector(
      onTap: () => widget.onPageSelected(key),
      child: Container(
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: EdgeInsets.only(left: _expanded ? 10 : 0),
        decoration: BoxDecoration(
          color: isActive ? ShadColors.sidebarAccent : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: _expanded
            ? Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isActive
                        ? ShadColors.foreground
                        : ShadColors.mutedForeground,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color: isActive
                            ? ShadColors.foreground
                            : ShadColors.mutedForeground,
                      ),
                    ),
                  ),
                ],
              )
            : Center(
                child: Icon(
                  icon,
                  size: 18,
                  color: isActive
                      ? ShadColors.foreground
                      : ShadColors.mutedForeground,
                ),
              ),
      ),
    );

    if (!_expanded) {
      item = Tooltip(
        message: title,
        preferBelow: false,
        child: item,
      );
    }

    return item;
  }
}
