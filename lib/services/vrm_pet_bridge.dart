import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global bridge between AiVtuber_Agent and AI-Pet-Engine (MateEngineBridge HTTP server).
///
/// Manages the MateEngine process lifecycle and survives page navigation.
/// Use [runningNotifier] to listen for state changes in UI.
///
/// Child process is placed in a Windows Job Object with
/// JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE — when the Flutter process exits
/// (window X button, crash, task kill), Windows auto-kills MateEngine.
///
/// Lifecycle:
///   1. VrmPetBridge.launch()          — starts MateEngineX.exe
///   2. VrmPetBridge.pushSystemPrompt()— sync Flutter's system prompt
///   3. VrmPetBridge.forwardMessage()  — each chat message
///   4. VrmPetBridge.close()          — kills the process
class VrmPetBridge {
  static const int unityPort = 9867;
  static const String defaultPath = r'D:\AI-Pet-Engine\Build\MateEngineX.exe';
  static const String _prefsKey = 'vrm_pet_path';

  static final ValueNotifier<bool> runningNotifier = ValueNotifier<bool>(false);
  static final HttpClient _client = HttpClient();

  static Process? _process;
  static String _exePath = defaultPath;
  static int _jobHandle = 0; // Windows Job Object

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

  // ── Windows Job Object (child auto-kill) ──

  static final _kernel32 = DynamicLibrary.open('kernel32.dll');

  static final _CreateJobObjectW = _kernel32
      .lookupFunction<IntPtr Function(Pointer<Void>, Pointer<Utf16>), int Function(Pointer<Void>, Pointer<Utf16>)>('CreateJobObjectW');
  static final _SetInformationJobObject = _kernel32
      .lookupFunction<Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32), int Function(int, int, Pointer<Void>, int)>('SetInformationJobObject');
  static final _AssignProcessToJobObject = _kernel32
      .lookupFunction<Int32 Function(IntPtr, IntPtr), int Function(int, int)>('AssignProcessToJobObject');
  static final _OpenProcess = _kernel32
      .lookupFunction<IntPtr Function(Uint32, Int32, Uint32), int Function(int, int, int)>('OpenProcess');
  static final _CloseHandle = _kernel32
      .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');

  static const int _PROCESS_SET_QUOTA = 0x0100;
  static const int _PROCESS_TERMINATE = 0x0001;
  static const int _JobObjectExtendedLimitInformation = 9;
  static const int _JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

  static void _createJobObject() {
    if (_jobHandle != 0) return;

    final job = _CreateJobObjectW(nullptr, nullptr);
    if (job == 0) {
      debugPrint('[VrmPetBridge] CreateJobObject failed');
      return;
    }
    _jobHandle = job;

    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION (Windows x64 layout)
    //   BasicLimitInformation (JOBOBJECT_BASIC_LIMIT_INFORMATION): 32 bytes
    //     PerProcessUserTimeLimit: 8
    //     PerJobUserTimeLimit: 8
    //     LimitFlags: 4
    //     MinimumWorkingSetSize: 4 (actually UIntPtr = 8 on x64)
    //     MaximumWorkingSetSize: 4 (actually UIntPtr = 8 on x64)
    //     ActiveProcessLimit: 4
    //     Affinity: 4 (actually UIntPtr = 8 on x64)
    //     PriorityClass: 4
    //     SchedulingClass: 4
    //   IoInfo (IO_COUNTERS): 48 bytes
    //   ProcessMemoryLimit: 8 (SIZE_T)
    //   JobMemoryLimit: 8 (SIZE_T)
    //   PeakProcessMemoryUsed: 8
    //   PeakJobMemoryUsed: 8

    // Simplified: allocate enough bytes, set LimitFlags at offset 16
    final size = 144; // safe size for the struct
    final ptr = calloc<Uint8>(size);
    // Zero out
    for (var i = 0; i < size; i++) {
      ptr[i] = 0;
    }

    // BasicLimitInformation.LimitFlags is at offset 16, 4 bytes (DWORD)
    // Write JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE as LE DWORD
    ptr[16] = 0x00;
    ptr[17] = 0x20;
    ptr[18] = 0x00;
    ptr[19] = 0x00;

    final result = _SetInformationJobObject(
      job,
      _JobObjectExtendedLimitInformation,
      ptr.cast<Void>(),
      size,
    );
    calloc.free(ptr);

    if (result == 0) {
      debugPrint('[VrmPetBridge] SetInformationJobObject failed');
    } else {
      debugPrint('[VrmPetBridge] Job Object OK — child auto-kill on parent exit');
    }
  }

  static void _assignProcessToJob(int pid) {
    if (_jobHandle == 0) return;
    final hProcess = _OpenProcess(
      _PROCESS_SET_QUOTA | _PROCESS_TERMINATE,
      0,
      pid,
    );
    if (hProcess != 0) {
      _AssignProcessToJobObject(_jobHandle, hProcess);
      _CloseHandle(hProcess);
    }
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
      _createJobObject();

      final workingDir = exeFile.parent.path;
      final process = await Process.start(
        _exePath,
        [],
        workingDirectory: workingDir,
        mode: ProcessStartMode.normal,
      );

      _process = process;
      runningNotifier.value = true;

      // Assign to Job Object → Windows kills it when we exit
      _assignProcessToJob(process.pid);

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

      return alive ? null : 'timeout';
    } catch (e) {
      debugPrint('[VrmPetBridge] Failed to launch: $e');
      _process = null;
      runningNotifier.value = false;
      return e.toString();
    }
  }

  /// Kill the MateEngine process — fire-and-forget, instant.
  static void close() {
    if (_process == null) return;
    final pid = _process!.pid;
    // Immediate TerminateProcess via taskkill /F (faster than Dart's Process.kill)
    Process.run('taskkill', ['/F', '/PID', '$pid', '/T'], runInShell: true);
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
          .postUrl(Uri.parse('http://localhost:$unityPort/chat'))
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
  static Future<bool> pushSystemPrompt(String prompt) async {
    if (_process == null || prompt.isEmpty) return false;

    try {
      final request = await _client
          .postUrl(Uri.parse('http://localhost:$unityPort/config'))
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

  /// Clear the external prompt override.
  static Future<bool> clearSystemPrompt() async {
    return pushSystemPrompt('');
  }

  /// Check if MateEngineBridge HTTP server is reachable.
  static Future<bool> checkAlive() async {
    try {
      final request = await _client
          .getUrl(Uri.parse('http://localhost:$unityPort/status'))
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
