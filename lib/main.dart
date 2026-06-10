import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/multi_agent_provider.dart';
import 'providers/stream_provider.dart';
import 'services/live2d_server.dart';
import 'services/vrm_pet_bridge.dart';
import 'providers/appearance_provider.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Live2D HTTP file server
  await Live2DServer.start();

  // Initialize acrylic/mica effect on Windows
  await acrylic.Window.initialize();
  await acrylic.Window.setEffect(
    effect: acrylic.WindowEffect.mica,
  );

  // Load saved preferences
  await SharedPreferences.getInstance();

  // ─── Cleanup child processes on signal (Ctrl+C / kill) ───
  // Window X close is handled automatically by Windows Job Object in VrmPetBridge.
  void cleanupAll() {
    VrmPetBridge.close();
    Live2DServer.killPet();
  }

  ProcessSignal.sigterm.watch().listen((_) { cleanupAll(); exit(0); });
  ProcessSignal.sigint.watch().listen((_)  { cleanupAll(); exit(0); });

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
