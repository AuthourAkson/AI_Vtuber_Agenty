import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'screens/home_screen.dart';

/// shadcn dark palette constants — matched to LocalAIVtuber2 index.css .dark variables
class ShadColors {
  ShadColors._();

  // Core
  static const background = Color(0xFF1A1A1A);    // oklch(0.145 0 0)
  static const foreground = Color(0xFFF5F5F5);      // oklch(0.985 0 0)
  static const card = Color(0xFF252525);             // oklch(0.205 0 0)
  static const cardForeground = Color(0xFFF5F5F5);
  static const popover = Color(0xFF252525);

  // Primary / secondary
  static const primary = Color(0xFFE8E8E8);          // oklch(0.922 0 0)
  static const primaryForeground = Color(0xFF1C1C1C);
  static const secondary = Color(0xFF2E2E2E);        // oklch(0.269 0 0)
  static const secondaryForeground = Color(0xFFF5F5F5);

  // Muted
  static const muted = Color(0xFF2E2E2E);
  static const mutedForeground = Color(0xFF9E9E9E);  // oklch(0.708 0 0)

  // Accent
  static const accent = Color(0xFF2E2E2E);
  static const accentForeground = Color(0xFFF5F5F5);

  // Destructive
  static const destructive = Color(0xFFCC3333);

  // Border / input
  static const border = Color(0x1AFFFFFF);           // oklch(1 0 0 / 10%)
  static const input = Color(0x26FFFFFF);             // oklch(1 0 0 / 15%)
  static const ring = Color(0xFF707070);

  // Sidebar
  static const sidebar = Color(0xFF1C1C1C);          // oklch(0.205 0 0)
  static const sidebarForeground = Color(0xFFF5F5F5);
  static const sidebarPrimary = Color(0xFF6B8DFF);
  static const sidebarAccent = Color(0xFF2E2E2E);    // oklch(0.269 0 0)
  static const sidebarAccentForeground = Color(0xFFF5F5F5);
  static const sidebarBorder = Color(0x1AFFFFFF);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI VTuber Agent',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ShadColors.background,
        primaryColor: ShadColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: ShadColors.primary,
          secondary: ShadColors.secondary,
          surface: ShadColors.card,
          error: ShadColors.destructive,
          onPrimary: ShadColors.primaryForeground,
          onSecondary: ShadColors.secondaryForeground,
          onSurface: ShadColors.foreground,
        ),
        cardColor: ShadColors.card,
        dividerColor: ShadColors.border,
        appBarTheme: const AppBarTheme(
          backgroundColor: ShadColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        // Input decoration - shadcn style
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: ShadColors.secondary,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), // --radius: 0.625rem
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ShadColors.input),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: ShadColors.ring, width: 1.5),
          ),
          hintStyle: const TextStyle(color: ShadColors.mutedForeground, fontSize: 14),
        ),
        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: ShadColors.primary,
            foregroundColor: ShadColors.primaryForeground,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: ShadColors.foreground,
            side: const BorderSide(color: ShadColors.input),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
        ),
        // Switch
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return ShadColors.primary;
            return ShadColors.mutedForeground;
          }),
          trackColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) return ShadColors.primary.withAlpha(80);
            return ShadColors.border;
          }),
        ),
        // Slider
        sliderTheme: SliderThemeData(
          activeTrackColor: ShadColors.primary,
          inactiveTrackColor: ShadColors.secondary,
          thumbColor: ShadColors.primary,
          overlayColor: ShadColors.primary.withAlpha(40),
        ),
        // Tooltip
        tooltipTheme: TooltipThemeData(
          decoration: BoxDecoration(
            color: ShadColors.popover,
            borderRadius: BorderRadius.circular(6),
          ),
          textStyle: const TextStyle(color: ShadColors.foreground, fontSize: 12),
        ),
        // Text selection — visible highlight on dark background
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0x404CAF50),
          cursorColor: ShadColors.primary,
          selectionHandleColor: ShadColors.primary,
        ),
      ),
      home: const AppShell(),
    );
  }
}

/// App shell with bitsdojo_window native title bar buttons
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
            // Custom title bar
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
      color: ShadColors.background,
      child: Row(
        children: [
          Expanded(
            child: MoveWindow(
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 12),
                child: const Text(
                  'AI VTuber Agent',
                  style: TextStyle(
                    fontSize: 12,
                    color: ShadColors.mutedForeground,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
            ),
          ),
          MinimizeWindowButton(),
          MaximizeWindowButton(),
          CloseWindowButton(),
        ],
      ),
    );
  }
}
