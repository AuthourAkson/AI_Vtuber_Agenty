import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/app_sidebar.dart';
import '../widgets/api_sidebar.dart';
import 'chat_screen.dart';
import 'character_screen.dart';
import 'llm_screen.dart';
import 'tts_screen.dart';
import 'vision_screen.dart';
import 'memory_screen.dart';
import 'stream_screen.dart';
import 'settings_screen.dart';
import 'pipeline_monitor_screen.dart';

/// Top-level screen: Material sidebar + content area + optional API sidebar
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _activePage = 'home';
  bool _showApiSidebar = false;

  final _pages = <String, Widget>{
    'home': const ChatScreen(),
    'input': const ChatScreen(),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsProvider>().loadSettings();
      context.read<ChatProvider>().initFromSavedState();
    });
  }

  void _toggleApiSidebar() {
    setState(() => _showApiSidebar = !_showApiSidebar);
  }

  @override
  Widget build(BuildContext context) {
    final isChat = _activePage == 'home';

    return Row(
      children: [
        AppSidebar(
          activePage: _activePage,
          onPageSelected: (page) => setState(() {
            _activePage = page;
            if (page != 'home') _showApiSidebar = false;
          }),
        ),
        // Main content area
        Expanded(child: _buildPage(isChat)),
        // API Sidebar on right when chat is active
        if (isChat)
          ApiSidebar(
            visible: _showApiSidebar,
            onClose: _toggleApiSidebar,
          ),
      ],
    );
  }

  Widget _buildPage(bool isChat) {
    switch (_activePage) {
      case 'home':
        return ChatScreen(onToggleApi: _toggleApiSidebar);
      case 'input':
        return const ChatScreen();
      case 'character':
        return const CharacterScreen();
      case 'llm':
        return const LLMScreen();
      case 'memory':
        return const MemoryScreen();
      case 'vision':
        return const VisionScreen();
      case 'tts':
        return const TTSScreen();
      case 'pipeline':
        return const PipelineMonitorScreen();
      case 'stream':
        return const StreamScreen();
      case 'settings':
        return const SettingsScreen();
      default:
        return ChatScreen(onToggleApi: _toggleApiSidebar);
    }
  }
}
