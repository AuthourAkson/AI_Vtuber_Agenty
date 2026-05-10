import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
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
        scaffoldBackgroundColor: const Color(0xCC121212),
        primaryColor: const Color(0xFF4CAF50),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4CAF50),
          secondary: Color(0xFF4CAF50),
          surface: Color(0xFF1E1E1E),
          error: Color(0xFFCF6679),
        ),
        cardColor: const Color(0xFF1E1E1E),
        dividerColor: const Color(0x20FFFFFF),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xCC1A1A1A),
          elevation: 0,
        ),
      ),
      home: const AppShell(),
    );
  }
}

/// App shell with bitsdojo_window native title bar buttons + Mica background
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            // Custom title bar with bitsdojo_window native buttons
            _buildTitleBar(),
            // Main content
            const Expanded(child: HomeScreen()),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 32,
      color: const Color(0xCC1A1A1A),
      child: Row(
        children: [
          // Draggable area + window title
          Expanded(
            child: MoveWindow(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: const Text(
                  'AI VTuber Agent',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF888888),
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          // Native window buttons from bitsdojo_window
          MinimizeWindowButton(),
          MaximizeWindowButton(),
          CloseWindowButton(),
        ],
      ),
    );
  }
}
