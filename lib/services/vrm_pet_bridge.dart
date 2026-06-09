import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global bridge between AiVtuber_Agent and AI-Pet-Engine (MateEngineBridge HTTP server).
///
/// Manages the MateEngine process lifecycle and survives page navigation.
/// Use [runningNotifier] to listen for state changes in UI.
///
/// Lifecycle:
///   1. VrmPetBridge.launch()          — starts MateEngineX.exe
///   2. VrmPetBridge.pushSystemPrompt()— sync Flutter's system prompt
///   3. VrmPetBridge.forwardMessage()  — each chat message
///   4. VrmPetBridge.close()          — kills the process
class VrmPetBridge {
  static const int port = 9867;
  static const String defaultPath = r'D:\AI-Pet-Engine\Build\MateEngineX.exe';
  static const String _prefsKey = 'vrm_pet_path';

  static final ValueNotifier<bool> runningNotifier = ValueNotifier<bool>(false);
  static final HttpClient _client = HttpClient();

  static Process? _process;
  static String _exePath = defaultPath;

  static bool get isRunning => _process != null;

  // ── Path management ──

  static String get exePath => _exePath;

  static Future<void> loadPath() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null && saved.isNotEmpty) {
        _exePath = saved;
      }
    } catch (_) {}
  }

  static Future<void> savePath(String path) async {
    _exePath = path;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, path);
    } catch (_) {}
  }

  // ── Launch / Close ──

  /// Launch AI-Pet-Engine. Returns null on success, error string on failure.
  static Future<String?> launch() async {
    if (_process != null) return null; // already running

    final exeFile = File(_exePath);
    if (!await exeFile.exists()) {
      return 'Not found: $_exePath';
    }

    try {
      final workingDir = exeFile.parent.path;
      final process = await Process.start(
        _exePath,
        [],
        workingDirectory: workingDir,
        mode: ProcessStartMode.normal,
      );

      _process = process;
      runningNotifier.value = true;

      // Drain stdout/stderr
      process.stdout.transform(utf8.decoder).listen((_) {});
      process.stderr.transform(utf8.decoder).listen((_) {});

      // Listen for exit
      process.exitCode.then((code) {
        debugPrint('[VrmPetBridge] MateEngine exited with code $code');
        clearSystemPrompt();
        _process = null;
        runningNotifier.value = false;
      });

      // Wait for HTTP bridge to come alive
      await Future.delayed(const Duration(seconds: 2));
      final alive = await checkAlive();

      return alive ? null : 'timeout'; // null = success, "timeout" = launched but bridge not ready
    } catch (e) {
      debugPrint('[VrmPetBridge] Failed to launch: $e');
      _process = null;
      runningNotifier.value = false;
      return e.toString();
    }
  }

  /// Kill the MateEngine process.
  static void close() {
    if (_process == null) return;
    try {
      _process!.kill();
    } catch (_) {}
    clearSystemPrompt();
    _process = null;
    runningNotifier.value = false;
  }

  // ── HTTP bridge ──

  /// Forward a chat message. Fire-and-forget.
  static Future<bool> forwardMessage(String message) async {
    if (_process == null) return false;

    try {
      final request = await _client
          .postUrl(Uri.parse('http://localhost:$port/chat'))
          .timeout(const Duration(seconds: 2));

      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'message': message}));

      final response = await request.close().timeout(const Duration(seconds: 3));
      final ok = response.statusCode == 200;
      if (!ok) await response.drain();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Push AiVtuber_Agent's system prompt to Mate Engine.
  /// When set, Mate Engine uses this prompt ONLY for bridge messages.
  /// Standalone mode still uses its own prompt.
  static Future<bool> pushSystemPrompt(String prompt) async {
    if (_process == null || prompt.isEmpty) return false;

    try {
      final request = await _client
          .postUrl(Uri.parse('http://localhost:$port/config'))
          .timeout(const Duration(seconds: 2));

      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'systemPrompt': prompt}));

      final response = await request.close().timeout(const Duration(seconds: 3));
      final ok = response.statusCode == 200;
      if (!ok) await response.drain();
      return ok;
    } catch (_) {
      return false;
    }
  }

  /// Clear the external prompt override (restore Mate Engine's own).
  static Future<bool> clearSystemPrompt() async {
    return pushSystemPrompt('');
  }

  /// Check if MateEngineBridge HTTP server is reachable.
  static Future<bool> checkAlive() async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://localhost:$port/status'))
          .timeout(const Duration(seconds: 1));

      final response = await request.close().timeout(const Duration(seconds: 2));
      final alive = response.statusCode == 200;
      await response.drain();
      return alive;
    } catch (_) {
      return false;
    }
  }
}
