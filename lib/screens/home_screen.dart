import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_sidebar.dart';
import 'chat_screen.dart';
import 'character_screen.dart';
import 'llm_screen.dart';
import 'tts_screen.dart';
import 'vision_screen.dart';
import 'memory_screen.dart';
import 'stream_screen.dart';
import 'settings_screen.dart';
import 'pipeline_monitor_screen.dart';

/// Top-level screen: sidebar + content area
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activePage = 'home';

  final _pages = <String, Widget>{
    'home': const ChatScreen(),
    'character': const CharacterScreen(),
    'memory': const MemoryScreen(),
    'input': const ChatScreen(),
    'vision': const VisionScreen(),
    'tts': const TTSScreen(),
    'pipeline': const PipelineMonitorScreen(),
    'stream': const StreamScreen(),
    'settings': const SettingsScreen(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
      context.read<ChatProvider>().connectToBackend();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            activePage: _activePage,
            onPageSelected: (page) => setState(() => _activePage = page),
          ),
          Expanded(child: _pages[_activePage] ?? const ChatScreen()),
        ],
      ),
    );
  }
}
