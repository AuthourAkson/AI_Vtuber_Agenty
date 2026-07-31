import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/multi_agent_provider.dart'; // AgentManager
import '../providers/appearance_provider.dart';
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
import 'markdown_text_screen.dart';

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
return MemoryScreen(onNavigateHome: () => _navigate('home'));
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
case 'markdownText':
return MarkdownTextScreen();
default:
return ChatScreen();
}
}

void _navigate(String page) async {
setState(() => _activePage = page);
// Persist last page
final prefs = await SharedPreferences.getInstance();
await prefs.setString('last_page', page);
}

@override
void initState() {
super.initState();
WidgetsBinding.instance.addPostFrameCallback((_) async {
context.read<SettingsProvider>().loadSettings();
context.read<ChatProvider>().initFromSavedState();

// Auto-restore last page if enabled
try {
final ap = context.read<AppearanceProvider>();
if (ap.autoOpenLastPage) {
final prefs = await SharedPreferences.getInstance();
final lastPage = prefs.getString('last_page');
if (lastPage != null && lastPage.isNotEmpty && mounted) {
setState(() => _activePage = lastPage);
}
}
} catch (_) {}
});
}

@override
Widget build(BuildContext context) {
return Row(
children: [
// Collapsible sidebar
AppSidebar(
activePage: _activePage,
onPageSelected: (page) => _navigate(page),
),
// Main content — only build the active page
Expanded(
child: _buildPage(_activePage),
),
],
);
}
}
