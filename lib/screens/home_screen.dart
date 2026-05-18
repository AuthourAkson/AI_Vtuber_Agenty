import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/multi_agent_provider.dart'; // AgentManager
import '../widgets/app_sidebar.dart';
import 'chat_screen.dart';
import 'character_screen.dart';
import 'tts_screen.dart';
import 'vision_screen.dart';
import 'memory_screen.dart';
import 'stream_screen.dart';
import 'settings_screen.dart';
import 'pipeline_monitor_screen.dart';
import 'multi_agent_screen.dart';

/// Top-level layout matching LocalAIVtuber2's Mainpage.
/// Only builds the active page — not all at once.
class HomeScreen extends StatefulWidget {
const HomeScreen({super.key});

@override
State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
String _activePage = 'home';

// Page builders — only the active page is built
Widget _buildPage(String page) {
switch (page) {
case 'home':
return ChatScreen();
case 'input':
return ChatScreen();
case 'character':
return CharacterScreen();
case 'memory':
return MemoryScreen(onNavigateHome: () => setState(() => _activePage = 'home'));
case 'vision':
return VisionScreen();
case 'tts':
return TTSScreen();
case 'pipeline':
return PipelineMonitorScreen();
case 'stream':
return StreamScreen();
case 'settings':
return SettingsScreen();
case 'agents':
return MultiAgentScreen();
default:
return ChatScreen();
}
}

@override
void initState() {
super.initState();
WidgetsBinding.instance.addPostFrameCallback((_) {
context.read<SettingsProvider>().loadSettings();
context.read<ChatProvider>().initFromSavedState();
});
}

@override
Widget build(BuildContext context) {
return Row(
children: [
// Collapsible sidebar
AppSidebar(
activePage: _activePage,
onPageSelected: (page) => setState(() => _activePage = page),
),
        // Main content — only build the active page
        Expanded(
          child: _buildPage(_activePage),
        ),
],
);
}
}
