     1|import 'package:flutter/material.dart';
     2|import '../app.dart';
     3|
     4|/// Collapsible sidebar matching LocalAIVtuber2's shadcn/ui Sidebar.
     5|/// - Expanded: 200px wide, icon + text
     6|/// - Collapsed: 48px wide, icon only with tooltip
     7|/// Uses AnimatedContainer for smooth, reliable animation.
     8|class AppSidebar extends StatefulWidget {
     9|  final String activePage;
    10|  final Function(String) onPageSelected;
    11|
    12|  const AppSidebar({
    13|    super.key,
    14|    required this.activePage,
    15|    required this.onPageSelected,
    16|  });
    17|
    18|  @override
    19|  State<AppSidebar> createState() => _AppSidebarState();
    20|}
    21|
    22|class _AppSidebarState extends State<AppSidebar> {
    23|  bool _expanded = true;
    24|
    25|  // Match LAV2 page-mapping sections exactly
    26|  static const _testPipeline = ['home', 'character', 'memory', 'agents'];
    27|  static const _footer = [
    28|    'input',
    29|    'vision',
    30|    'tts',
    31|    'pipeline',
    32|    'stream',
    33|    'settings',
    34|  ];
    35|
    36|  static const _icons = {
    37|    'home': Icons.home,
    38|    'character': Icons.person,
    39|    'memory': Icons.storage_rounded,
    40|    'agents': Icons.hub,
    41|    'input': Icons.mic,
    42|    'vision': Icons.remove_red_eye,
    43|    'tts': Icons.record_voice_over,
    44|    'pipeline': Icons.square_foot,
    45|    'stream': Icons.cast,
    46|    'settings': Icons.settings,
    47|  };
    48|
    49|  static const _titles = {
    50|    'home': 'Home',
    51|    'character': 'Character',
    52|    'memory': 'Memory',
    53|    'agents': 'Multi-Agent',
    54|    'input': 'Input',
    55|    'vision': 'Vision',
    56|    'tts': 'TTS',
    57|    'pipeline': 'Pipeline',
    58|    'stream': 'Stream',
    59|    'settings': 'Settings',
    60|  };
    61|
    62|  void _toggle() => setState(() => _expanded = !_expanded);
    63|
    64|  @override
    65|  Widget build(BuildContext context) {
    66|    return AnimatedContainer(
    67|      duration: const Duration(milliseconds: 200),
    68|      curve: Curves.easeInOut,
    69|      width: _expanded ? 200.0 : 48.0,
    70|      decoration: const BoxDecoration(
    71|        color: ShadTheme.of(context).sidebar,
    72|        border: Border(
    73|          right: BorderSide(color: ShadTheme.of(context).sidebarBorder),
    74|        ),
    75|      ),
    76|      child: Column(
    77|        children: [
    78|          // Toggle button
    79|          _buildToggle(),
    80|          const SizedBox(height: 8),
    81|          // Test Pipeline section label
    82|          if (_expanded)
    83|            const Padding(
    84|              padding: EdgeInsets.only(left: 12, bottom: 4),
    85|              child: Align(
    86|                alignment: Alignment.centerLeft,
    87|                child: Text(
    88|                  'Test pipeline',
    89|                  style: TextStyle(
    90|                    fontSize: 11,
    91|                    color: ShadTheme.of(context).mutedForeground,
    92|                    fontWeight: FontWeight.w600,
    93|                  ),
    94|                ),
    95|              ),
    96|            ),
    97|          ..._testPipeline.map((key) => _navItem(key)),
    98|          const Spacer(),
    99|          // Footer separator
   100|          Container(
   101|            height: 1,
   102|            color: ShadTheme.of(context).sidebarBorder,
   103|            margin: const EdgeInsets.symmetric(horizontal: 8),
   104|          ),
   105|          const SizedBox(height: 4),
   106|          ..._footer.map((key) => _navItem(key)),
   107|          const SizedBox(height: 4),
   108|          // Dark mode indicator
   109|          Padding(
   110|            padding: const EdgeInsets.only(bottom: 12),
   111|            child: Icon(
   112|              Icons.dark_mode,
   113|              size: 16,
   114|              color: ShadTheme.of(context).mutedForeground.withAlpha(140),
   115|            ),
   116|          ),
   117|        ],
   118|      ),
   119|    );
   120|  }
   121|
   122|  Widget _buildToggle() {
   123|    return Padding(
   124|      padding: const EdgeInsets.only(top: 8, right: 8),
   125|      child: Align(
   126|        alignment: Alignment.centerRight,
   127|        child: GestureDetector(
   128|          onTap: _toggle,
   129|          child: Container(
   130|            width: 24,
   131|            height: 24,
   132|            decoration: BoxDecoration(
   133|              borderRadius: BorderRadius.circular(4),
   134|              color: ShadTheme.of(context).sidebarAccent,
   135|            ),
   136|            child: Icon(
   137|              _expanded ? Icons.chevron_left : Icons.chevron_right,
   138|              size: 14,
   139|              color: ShadTheme.of(context).mutedForeground,
   140|            ),
   141|          ),
   142|        ),
   143|      ),
   144|    );
   145|  }
   146|
   147|  Widget _navItem(String key) {
   148|    final isActive = widget.activePage == key;
   149|    final title = _titles[key] ?? key;
   150|    final icon = _icons[key] ?? Icons.circle;
   151|
   152|    Widget item = GestureDetector(
   153|      onTap: () => widget.onPageSelected(key),
   154|      child: Container(
   155|        height: 36,
   156|        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
   157|        padding: EdgeInsets.only(left: _expanded ? 10 : 0),
   158|        decoration: BoxDecoration(
   159|          color: isActive ? ShadTheme.of(context).sidebarAccent : null,
   160|          borderRadius: BorderRadius.circular(6),
   161|        ),
   162|        child: _expanded
   163|            ? Row(
   164|                children: [
   165|                  Icon(
   166|                    icon,
   167|                    size: 18,
   168|                    color: isActive
   169|                        ? ShadTheme.of(context).foreground
   170|                        : ShadTheme.of(context).mutedForeground,
   171|                  ),
   172|                  const SizedBox(width: 10),
   173|                  Flexible(
   174|                    child: Text(
   175|                      title,
   176|                      overflow: TextOverflow.ellipsis,
   177|                      style: TextStyle(
   178|                        fontSize: 13,
   179|                        fontWeight:
   180|                            isActive ? FontWeight.w600 : FontWeight.w400,
   181|                        color: isActive
   182|                            ? ShadTheme.of(context).foreground
   183|                            : ShadTheme.of(context).mutedForeground,
   184|                      ),
   185|                    ),
   186|                  ),
   187|                ],
   188|              )
   189|            : Center(
   190|                child: Icon(
   191|                  icon,
   192|                  size: 18,
   193|                  color: isActive
   194|                      ? ShadTheme.of(context).foreground
   195|                      : ShadTheme.of(context).mutedForeground,
   196|                ),
   197|              ),
   198|      ),
   199|    );
   200|
   201|    if (!_expanded) {
   202|      item = Tooltip(
   203|        message: title,
   204|        preferBelow: false,
   205|        child: item,
   206|      );
   207|    }
   208|
   209|    return item;
   210|  }
   211|}
   212|