import 'package:flutter/material.dart';
import '../app.dart';
import '../l10n/app_localizations.dart';

/// Collapsible sidebar matching LocalAIVtuber2's shadcn/ui Sidebar.
/// - Expanded: 200px wide, icon + text
/// - Collapsed: 48px wide, icon only with tooltip
/// Uses AnimatedContainer for smooth, reliable animation.
class AppSidebar extends StatefulWidget {
final String activePage;
final Function(String) onPageSelected;

AppSidebar({
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
static final _testPipeline = ['home', 'character', 'memory', 'agents', 'markdownText'];
static final _footer = [
'input',
'vision',
'tts',
'pipeline',
'stream',
'settings',
];

static final _icons = {
'home': Icons.home,
'character': Icons.person,
'memory': Icons.storage_rounded,
'agents': Icons.hub,
'markdownText': Icons.article_outlined,
'input': Icons.mic,
'vision': Icons.remove_red_eye,
'tts': Icons.record_voice_over,
'pipeline': Icons.square_foot,
'stream': Icons.cast,
'settings': Icons.settings,
};

String _localizedTitle(String key) {
final l10n = AppLocalizations.of(context);
switch (key) {
case 'home': return l10n.sidebarHome;
case 'character': return l10n.sidebarCharacter;
case 'memory': return l10n.sidebarMemory;
case 'agents': return l10n.sidebarAgents;
case 'markdownText': return l10n.sidebarMarkdownText;
case 'input': return l10n.sidebarInput;
case 'vision': return l10n.sidebarVision;
case 'tts': return l10n.sidebarTTS;
case 'pipeline': return l10n.sidebarPipeline;
case 'stream': return l10n.sidebarStream;
case 'settings': return l10n.sidebarSettings;
default: return key;
}
}

void _toggle() => setState(() => _expanded = !_expanded);

@override
Widget build(BuildContext context) {
return AnimatedContainer(
duration: Duration(milliseconds: 200),
curve: Curves.easeInOut,
width: _expanded ? 200.0 : 48.0,
decoration: BoxDecoration(
color: ShadTheme.of(context).sidebar,
border: Border(
right: BorderSide(color: ShadTheme.of(context).sidebarBorder),
),
),
child: Column(
children: [
// Toggle button
_buildToggle(),
SizedBox(height: 8),
// Test Pipeline section label
if (_expanded)
Padding(
padding: EdgeInsets.only(left: 12, bottom: 4),
child: Align(
alignment: Alignment.centerLeft,
child: Text(
'Test pipeline',
style: TextStyle(
fontSize: 11,
color: ShadTheme.of(context).mutedForeground,
fontWeight: FontWeight.w600,
),
),
),
),
..._testPipeline.map((key) => _navItem(key)),
Spacer(),
// Footer separator
Container(
height: 1,
color: ShadTheme.of(context).sidebarBorder,
margin: EdgeInsets.symmetric(horizontal: 8),
),
SizedBox(height: 4),
..._footer.map((key) => _navItem(key)),
SizedBox(height: 4),
// Dark mode indicator
Padding(
padding: EdgeInsets.only(bottom: 12),
child: Icon(
Icons.dark_mode,
size: 16,
color: ShadTheme.of(context).mutedForeground.withAlpha(140),
),
),
],
),
);
}

Widget _buildToggle() {
return Padding(
padding: EdgeInsets.only(top: 8, right: 8),
child: Align(
alignment: Alignment.centerRight,
child: GestureDetector(
onTap: _toggle,
child: Container(
width: 24,
height: 24,
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(4),
color: ShadTheme.of(context).sidebarAccent,
),
child: Icon(
_expanded ? Icons.chevron_left : Icons.chevron_right,
size: 14,
color: ShadTheme.of(context).sidebarAccentForeground,
),
),
),
),
);
}

Widget _navItem(String key) {
final isActive = widget.activePage == key;
final title = _localizedTitle(key);
final icon = _icons[key] ?? Icons.circle;

Widget item = GestureDetector(
onTap: () => widget.onPageSelected(key),
child: Container(
height: 36,
margin: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
padding: EdgeInsets.only(left: _expanded ? 10 : 0),
decoration: BoxDecoration(
color: isActive ? ShadTheme.of(context).sidebarAccent : null,
borderRadius: BorderRadius.circular(6),
),
child: _expanded
? Row(
children: [
Icon(
icon,
size: 18,
color: isActive
                ? ShadTheme.of(context).sidebarAccentForeground
: ShadTheme.of(context).mutedForeground,
),
SizedBox(width: 10),
Flexible(
child: Text(
title,
overflow: TextOverflow.ellipsis,
style: TextStyle(
fontSize: 13,
fontWeight:
isActive ? FontWeight.w600 : FontWeight.w400,
color: isActive
                ? ShadTheme.of(context).sidebarAccentForeground
: ShadTheme.of(context).mutedForeground,
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
                ? ShadTheme.of(context).sidebarAccentForeground
: ShadTheme.of(context).mutedForeground,
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
