import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Log severity level, ordered from least to most severe.
enum LogLevel { debug, info, warn, error }

/// Extension for display-friendly labels and colours.
extension LogLevelX on LogLevel {
  String get label {
    switch (this) {
      case LogLevel.debug: return 'Debug';
      case LogLevel.info:  return 'Info';
      case LogLevel.warn:  return 'WARN';
      case LogLevel.error: return 'ERROR';
    }
  }

  /// Index for filter ordering (0=Debug, 3=Error).
  int get severity => index;
}

/// A single log entry captured by [LogService].
class LogEntry {
  final int id;
  final DateTime timestamp;
  final LogLevel level;
  final String module;
  final String message;
  final String? stackTrace;

  const LogEntry({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.stackTrace,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'level': level.label,
        'module': module,
        'message': message,
        if (stackTrace != null) 'stackTrace': stackTrace,
      };
}

/// Singleton in-memory log store.
///
/// Usage anywhere in the app:
/// ```dart
/// LogService().info('LLMService', 'Connected to API');
/// LogService().error('ChatProvider', 'Null check failed', stackTrace);
/// ```
class LogService {
  LogService._internal();
  static final LogService _instance = LogService._internal();
  factory LogService() => _instance;

  final List<LogEntry> _logs = [];
  final List<VoidCallback> _listeners = [];
  int _idCounter = 0;

  // ── Public API ──────────────────────────────────────────

  /// Read-only view of all logs (newest first).
  List<LogEntry> get entries => List.unmodifiable(_logs.reversed);

  int get count => _logs.length;

  void debug(String module, String message) =>
      _add(LogLevel.debug, module, message);

  void info(String module, String message) =>
      _add(LogLevel.info, module, message);

  void warn(String module, String message) =>
      _add(LogLevel.warn, module, message);

  void error(String module, String message, [StackTrace? stack]) =>
      _add(LogLevel.error, module, message, stack);

  /// Filtered list (newest first) — used by the UI.
  List<LogEntry> filtered({
    String query = '',
    Set<LogLevel>? levels,
  }) {
    final results = _logs.where((e) {
      if (levels != null && !levels.contains(e.level)) return false;
      if (query.isNotEmpty) {
        final q = query.toLowerCase();
        if (!e.message.toLowerCase().contains(q) &&
            !e.module.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results;
  }

  void clear() {
    _logs.clear();
    _notify();
  }

  /// Export all logs as a JSON array string.
  String exportJson() {
    return const JsonEncoder.withIndent('  ')
        .convert(_logs.map((e) => e.toJson()).toList());
  }

  // ── Listener pattern (lightweight ChangeNotifier) ───────

  void addListener(VoidCallback cb) => _listeners.add(cb);
  void removeListener(VoidCallback cb) => _listeners.remove(cb);
  void _notify() {
    for (final cb in List<VoidCallback>.from(_listeners)) {
      cb();
    }
  }

  // ── Internal ────────────────────────────────────────────

  void _add(LogLevel level, String module, String message,
      [StackTrace? stack]) {
    _logs.add(LogEntry(
      id: ++_idCounter,
      timestamp: DateTime.now(),
      level: level,
      module: module,
      message: message,
      stackTrace: stack?.toString(),
    ));
    _notify();
  }

  /// Seed demo entries for UI preview — remove when real logging is wired.
  void seedDemoData() {
    if (_logs.isNotEmpty) return; // only seed once

    // Simulate startup sequence
    info('WenzAgentService', 'Initializing WenzAgent service on 127.0.0.1:9090');
    debug('WenzAgentService', 'Loading device registry from D:\\AiVtuber_Agent_profile\\wenzagent\\devices.json');
    info('WenzAgentService', 'WenzAgent LAN server connected — 3 peers online');
    warn('ChatProvider', 'Session history file truncated: unexpected EOF at offset 142');
    info('LLMService', 'Connected to API endpoint: https://api.openai.com/v1');
    debug('LLMService', 'Model list fetched: [gpt-4o, gpt-4o-mini, o4-mini]');
    info('AgentManager', 'Employee "Code Reviewer" (uuid: a1b2c3) bound to device DESKTOP-PC');

    // Simulate the exact error from the user's description
    error(
      'EmployeeListController',
      '打开LAN设置: 加载员工列表失败: Null check operator used on a null value',
      StackTrace.fromString(
        '#0      LogServiceImpl.error (package:wenzflow/service/log/impl/log_service_impl.dart:156)\n'
        '#1      AILogger.error (package:wenzflow/service/ai/ai_logger.dart:69)\n'
        '#2      BaseEmployeeListController._loadEmployees (package:wenzflow/view/common/ai/employee_list/base_controller.dart:144)\n'
        '<asynchronous suspension>\n'
        '#3      BaseEmployeeListController.refresh (package:wenzflow/view/common/ai/employee_list/base_controller.dart:125)\n'
        '<asynchronous suspension>',
      ),
    );

    warn('StorageService', 'Disk space below 500 MB on D: — TTS cache cleanup recommended');
    debug('VisionService', 'Screenshot dimensions: 1920×1080, PNG 1.2 MB');
    info('PipelineManager', 'Task #42 completed: LLM→TTS→Audio in 2.3s');
    error('TTSService', 'edge-tts subprocess exited with code 1: connection refused');
    info('AppearanceProvider', 'Theme preset changed to "Dracula"');
    debug('SessionManager', 'Autosaved session 2026-05-21-001.json (14 messages)');
    info('AppShell', 'Application started — v1.4.1, Flutter 3.32, Dart 3.11.0');

    _notify();
  }
}
