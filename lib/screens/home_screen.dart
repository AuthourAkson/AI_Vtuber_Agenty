     1|import 'package:flutter/material.dart';
     2|import 'package:provider/provider.dart';
     3|import '../app.dart';
     4|import '../providers/chat_provider.dart';
     5|import '../providers/settings_provider.dart';
     6|import '../providers/multi_agent_provider.dart'; // AgentManager
     7|import '../widgets/app_sidebar.dart';
     8|import 'chat_screen.dart';
     9|import 'character_screen.dart';
    10|import 'tts_screen.dart';
    11|import 'vision_screen.dart';
    12|import 'memory_screen.dart';
    13|import 'stream_screen.dart';
    14|import 'settings_screen.dart';
    15|import 'pipeline_monitor_screen.dart';
    16|import 'multi_agent_screen.dart';
    17|
    18|/// Top-level layout matching LocalAIVtuber2's Mainpage.
    19|/// Only builds the active page — not all at once.
    20|class HomeScreen extends StatefulWidget {
    21|  const HomeScreen({super.key});
    22|
    23|  @override
    24|  State<HomeScreen> createState() => _HomeScreenState();
    25|}
    26|
    27|class _HomeScreenState extends State<HomeScreen> {
    28|  String _activePage = 'home';
    29|
    30|  // Page builders — only the active page is built
    31|  Widget _buildPage(String page) {
    32|    switch (page) {
    33|      case 'home':
    34|        return const ChatScreen();
    35|      case 'input':
    36|        return const ChatScreen();
    37|      case 'character':
    38|        return const CharacterScreen();
    39|      case 'memory':
    40|        return MemoryScreen(onNavigateHome: () => setState(() => _activePage = 'home'));
    41|      case 'vision':
    42|        return const VisionScreen();
    43|      case 'tts':
    44|        return const TTSScreen();
    45|      case 'pipeline':
    46|        return const PipelineMonitorScreen();
    47|      case 'stream':
    48|        return const StreamScreen();
    49|      case 'settings':
    50|        return const SettingsScreen();
    51|      case 'agents':
    52|        return const MultiAgentScreen();
    53|      default:
    54|        return const ChatScreen();
    55|    }
    56|  }
    57|
    58|  @override
    59|  void initState() {
    60|    super.initState();
    61|    WidgetsBinding.instance.addPostFrameCallback((_) {
    62|      context.read<SettingsProvider>().loadSettings();
    63|      context.read<ChatProvider>().initFromSavedState();
    64|    });
    65|  }
    66|
    67|  @override
    68|  Widget build(BuildContext context) {
    69|    return Row(
    70|      children: [
    71|        // Collapsible sidebar
    72|        AppSidebar(
    73|          activePage: _activePage,
    74|          onPageSelected: (page) => setState(() => _activePage = page),
    75|        ),
    76|        // Main content — only build the active page
    77|        Expanded(
    78|          child: Container(
    79|            color: ShadTheme.of(context).background,
    80|            child: _buildPage(_activePage),
    81|          ),
    82|        ),
    83|      ],
    84|    );
    85|  }
    86|}
    87|