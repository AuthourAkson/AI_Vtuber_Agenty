import 'package:flutter/material.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'providers/chat_provider.dart';
import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize acrylic/mica effect on Windows
  await acrylic.Window.initialize();
  await acrylic.Window.setEffect(
    effect: acrylic.WindowEffect.mica,
  );

  // Load saved preferences
  await SharedPreferences.getInstance();

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
