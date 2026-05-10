import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'screens/home_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI VTuber Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFF4CAF50),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1E1E1E),
          error: Color(0xFFCF6679),
        ),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: const Color(0xFF2C2C2C),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1A1A1A),
          elevation: 0,
        ),
      ),
      home: const AppShell(),
    );
  }
}

/// App shell with custom window title bar for frameless mode.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Custom drag-to-move title bar
        _buildTitleBar(context),
        // Main content
        const Expanded(child: HomeScreen()),
      ],
    );
  }

  Widget _buildTitleBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: () => windowManager.maximizeOrRestore(),
      onPanStart: (_) => windowManager.startDragging(),
      child: Container(
        height: 32,
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Window title
            const Padding(
              padding: EdgeInsets.only(left: 12),
              child: Text(
                'AI VTuber Agent',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF888888),
                ),
              ),
            ),
            const Spacer(),
            // Window control buttons
            _windowButton(
              icon: Icons.minimize,
              onTap: () => windowManager.minimize(),
              tooltip: 'Minimize',
            ),
            _windowButton(
              icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
              onTap: () => windowManager.maximizeOrRestore(),
              tooltip: _isMaximized ? 'Restore' : 'Maximize',
            ),
            _windowButton(
              icon: Icons.close,
              onTap: () => windowManager.close(),
              tooltip: 'Close',
              isClose: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _windowButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
    bool isClose = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 46,
          height: 32,
          child: Icon(
            icon,
            size: 14,
            color: isClose ? const Color(0xFF888888) : const Color(0xFF666666),
          ),
        ),
      ),
    );
  }
}
