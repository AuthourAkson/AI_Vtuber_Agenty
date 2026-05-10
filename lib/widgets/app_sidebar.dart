import 'package:flutter/material.dart';

/// Navigation sidebar matching LAV2 page layout
class AppSidebar extends StatelessWidget {
  final String activePage;
  final Function(String) onPageSelected;

  const AppSidebar({
    super.key,
    required this.activePage,
    required this.onPageSelected,
  });

  static const _testPipeline = ['home', 'character', 'memory'];
  static const _footer = ['input', 'llm', 'vision', 'tts', 'pipeline', 'stream', 'settings'];

  static const _icons = {
    'home': Icons.home,
    'character': Icons.person,
    'memory': Icons.memory,
    'input': Icons.mic,
    'llm': Icons.psychology,
    'vision': Icons.remove_red_eye,
    'tts': Icons.record_voice_over,
    'pipeline': Icons.square_foot,
    'stream': Icons.live_tv,
    'settings': Icons.settings,
  };

  static const _titles = {
    'home': 'Home',
    'character': 'Character',
    'memory': 'Memory',
    'input': 'Input',
    'llm': 'LLM',
    'vision': 'Vision',
    'tts': 'TTS',
    'pipeline': 'Pipeline',
    'stream': 'Stream',
    'settings': 'Settings',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
        border: Border(right: BorderSide(color: Color(0xFF2C2C2C))),
      ),
      child: Column(
        children: [
          // Test Pipeline section
          const SizedBox(height: 12),
          const Text('MAIN', style: TextStyle(color: Color(0xFF666666), fontSize: 10)),
          const SizedBox(height: 4),
          ..._testPipeline.map((key) => _navItem(key)),
          const Spacer(),
          // Footer items
          ..._footer.map((key) => _navItem(key)),
          const SizedBox(height: 8),
          // Dark mode indicator
          const Icon(Icons.dark_mode, color: Color(0xFF666666), size: 16),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _navItem(String key) {
    final isActive = activePage == key;
    return Tooltip(
      message: _titles[key] ?? key,
      preferBelow: false,
      child: InkWell(
        onTap: () => onPageSelected(key),
        child: Container(
          width: 56,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF2C2C2C) : null,
            border: isActive
                ? const Border(left: BorderSide(color: Color(0xFF4CAF50), width: 2))
                : null,
          ),
          child: Icon(
            _icons[key] ?? Icons.circle,
            size: 20,
            color: isActive ? const Color(0xFF4CAF50) : const Color(0xFF888888),
          ),
        ),
      ),
    );
  }
}
