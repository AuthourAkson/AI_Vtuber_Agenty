import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'app.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/multi_agent_provider.dart';
import 'providers/stream_provider.dart';
import 'services/live2d_server.dart';
import 'providers/appearance_provider.dart';
import 'character_popout_main.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Route to Character Pop Out sub-window via SharedPreferences flag.
  // (detection via WindowController.fromCurrentEngine() unreliable on Windows)
  final prefs = await SharedPreferences.getInstance();
  final isPopoutLaunch = prefs.getBool('_popout_launch') ?? false;
  if (isPopoutLaunch) {
    await prefs.remove('_popout_launch');
    final configJson = prefs.getString('popout_config');
    final configArgs = configJson != null ? [configJson] : <String>[];
    characterPopoutMain(configArgs);
    return;
  }

  // ─── Main app window ───

  // Start Live2D HTTP file server
  await Live2DServer.start();

  // Initialize acrylic/mica effect on Windows
  await acrylic.Window.initialize();
  await acrylic.Window.setEffect(
    effect: acrylic.WindowEffect.mica,
  );

  // Load saved preferences
  await SharedPreferences.getInstance();

  // ─── Process signal handler: kill pet subprocess on app exit ───
  ProcessSignal.sigterm.watch().listen((_) {
    Live2DServer.killPet();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AgentManager()),
        ChangeNotifierProvider(create: (_) => LiveStreamProvider()),
        ChangeNotifierProvider(create: (_) => AppearanceProvider()..load()),
      ],
      child: const MyApp(),
    ),
  );

  // Configure frameless window with bitsdojo_window
  doWhenWindowReady(() {
    appWindow.size = const Size(1400, 900);
    appWindow.minSize = const Size(1200, 800);
    appWindow.alignment = Alignment.center;
    appWindow.title = 'AI VTuber Agent';
    appWindow.show();
  });
}
