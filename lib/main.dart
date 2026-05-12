import 'dart:io';
import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';
import 'services/live2d_server.dart';
import 'services/live2d_overlay_ffi.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Main app window ───

  // Start Live2D HTTP file server
  await Live2DServer.start();

  // Initialize native overlay FFI (VTube Studio-style transparent window)
  Live2DOverlayFfi.instance.load();

  // Initialize acrylic/mica effect on Windows
  await acrylic.Window.initialize();
  await acrylic.Window.setEffect(
    effect: acrylic.WindowEffect.mica,
  );

  // Load saved preferences
  await SharedPreferences.getInstance();

  // ─── Process signal handler: kill pet subprocess on app exit ───
  // When the Flutter desktop app is closed, the runtime sends SIGTERM.
  // We use this to clean up the Python pet subprocess before exiting.
  ProcessSignal.sigterm.watch().listen((_) {
    Live2DServer.killPet();
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
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
