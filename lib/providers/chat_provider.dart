import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';
import '../models/task.dart';
import '../services/backend_service.dart';
import '../services/pipeline_manager.dart';
import '../services/session_manager.dart';
import '../services/vrm_pet_bridge.dart';

/// Central state for chat messages, sessions, and pipeline interaction.
/// Uses ChangeNotifier for Provider-based reactive UI updates.
class ChatProvider extends ChangeNotifier {
  final BackendService backend = BackendService();
  late final PipelineManager pipeline;
  late final SessionManager sessionManager;

  final _messages = <HistoryItem>[];
  String? _sessionId;
  String _systemPrompt = '';
  String _visionPrompt = '';
  String _ocrPrompt = '';
  String _retrievedContext = '';
  bool _enableMemoryRetrieval = true;

  // Streaming state
  AbortController? _abortController;
  bool _isStreaming = false;

  ChatProvider() {
    pipeline = PipelineManager();
    sessionManager = SessionManager(backend);
    pipeline.subscribe(_onPipelineUpdate);
  }

  // ─── Getters ───

  List<HistoryItem> get messages => List.unmodifiable(_messages);
  String? get sessionId => _sessionId;
  String? get activeSessionId => _sessionId;
  String get activeSessionTitle {
    if (_sessionId == null) return 'New Session';
    // Use stored title from session cache
    final cached = sessionManager.getSessionsCache();
    for (final s in cached) {
      if (s['id'] == _sessionId) {
        final t = s['title'] as String?;
        if (t != null && t.isNotEmpty && t != 'Chat Session') return t;
        break;
      }
    }
    // Fallback: first user message, or session ID prefix
    final firstMsg = _messages.isNotEmpty ? _messages.first : null;
    if (firstMsg != null && firstMsg.role == 'user') {
      final truncated = firstMsg.content.length > 30
          ? '${firstMsg.content.substring(0, 30)}...'
          : firstMsg.content;
      return truncated;
    }
    return _sessionId!.substring(0, 8);
  }
  String get systemPrompt => _systemPrompt;
  String get visionPrompt => _visionPrompt;
  String get ocrPrompt => _ocrPrompt;
  String get retrievedContext => _retrievedContext;
  String get currentCaption => _visionPrompt;
  String get currentOcrText => _ocrPrompt;
  String get currentMemoryContext => _retrievedContext;
  String get fullSystemPrompt {
    final parts = <String>[];
    if (_visionPrompt.isNotEmpty) parts.add('[SCREEN CONTEXT]\n$_visionPrompt');
    if (_ocrPrompt.isNotEmpty) parts.add('[SCREEN TEXT]\n$_ocrPrompt');
    if (_retrievedContext.isNotEmpty) parts.add('[RETRIEVED MEMORY]\n$_retrievedContext');
    if (_systemPrompt.isNotEmpty) parts.add('[INSTRUCTIONS]\n$_systemPrompt');
    return parts.join('\n\n');
  }
  bool get enableMemoryRetrieval => _enableMemoryRetrieval;
  bool get connected => backend.connected;
  bool get isStreaming => _isStreaming;

  /// All sessions list
  List<Map<String, dynamic>> get sessions => sessionManager.getSessionsCache();

  /// Create a new session and switch to it
  Future<void> createNewSession({String? title}) async {
    final id = await sessionManager.createNewSession(title: title);
    if (id != null) {
      _sessionId = id;
      _messages.clear();
      // Persist as last active
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_session_id', id);
      notifyListeners();
    }
  }

  /// Rename a session
  Future<void> renameSession(String id, String newTitle) async {
    await sessionManager.renameSession(id, newTitle);
    notifyListeners();
  }

  /// Load session by ID
  Future<void> loadSession(String id) => setSessionId(id);

  // ─── Setters ───

  set systemPrompt(String v) { _systemPrompt = v; notifyListeners(); }
  set visionPrompt(String v) { _visionPrompt = v; notifyListeners(); }
  set ocrPrompt(String v) { _ocrPrompt = v; notifyListeners(); }
  set enableMemoryRetrieval(bool v) {
    _enableMemoryRetrieval = v;
    if (!v) _retrievedContext = '';
    notifyListeners();
  }

  // ─── Messages ───

  void setMessages(List<HistoryItem> msgs) {
    _messages.clear();
    _messages.addAll(msgs);
    notifyListeners();
  }

  /// Send a chat message with streaming response.
  /// Orchestrates: input -> memory query -> system prompt assembly -> LLM streaming.
  Future<void> sendMessage(String input, {String? taskId}) async {
    if (input.trim().isEmpty) return;

    _abortController = AbortController();
    _isStreaming = true;
    final userMsg = HistoryItem(role: 'user', content: input);
    _messages.add(userMsg);
    notifyListeners();

    // Forward to VRM Desktop Pet (AI-Pet-Engine) if running
    VrmPetBridge.forwardMessage(input);

    try {
      // Sync LLM config + system prompt from saved settings before making API call
      final settings = await backend.getSettings();
      if (settings.systemPrompt.isNotEmpty) {
        _systemPrompt = settings.systemPrompt;
      }
      _enableMemoryRetrieval = settings.enableMemoryRetrieval;

      // Query memory context if enabled
      String contextText = '';
      if (_enableMemoryRetrieval) {
        try {
          final docs = await backend.queryMemory(input, limit: 3);
          contextText = docs.join('\n');
          _retrievedContext = contextText;
        } catch (_) {}
      }

      // Assemble system prompt
      final visionSection = _visionPrompt.isNotEmpty
          ? '[SCREEN CONTEXT]\n$_visionPrompt\n\n'
          : '';
      final ocrSection = _ocrPrompt.isNotEmpty
          ? '[SCREEN TEXT]\n$_ocrPrompt\n\n'
          : '';
      final contextSection = contextText.isNotEmpty
          ? '[RETRIEVED MEMORY]\n$contextText\n\n'
          : '';
      final instructionsSection = '[INSTRUCTIONS]\n$_systemPrompt\n\n';
      final fullSystemPrompt = '$visionSection$ocrSection$contextSection$instructionsSection';

      // Create session if needed
      if (_sessionId == null) {
        _sessionId = await sessionManager.createNewSession();
        // Persist new session as last active
        if (_sessionId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('last_session_id', _sessionId!);
        }
      }
      await sessionManager.updateSessionContent(_sessionId, _messages);

      // Stream from local LLM service
      final history = _messages.length > 30
          ? _messages.sublist(_messages.length - 31, _messages.length - 1)
          : _messages.sublist(0, _messages.length - 1);

      String aiMessage = '';
      String currentText = '';
      String? actualTaskId = taskId;

      await for (final chunk in backend.completionStream(
        text: input,
        history: history,
        systemPrompt: fullSystemPrompt,
      )) {
        if (_abortController!.isAborted) break;
        aiMessage += chunk;
        currentText += chunk;

        // Update message list
        _messages.removeWhere((m) => m.role == 'assistant' && m.content == aiMessage.substring(0, aiMessage.length - chunk.length));
        _messages.add(HistoryItem(role: 'assistant', content: aiMessage));

        // Sentence splitting for TTS pipeline
        final parts = _splitSentences(currentText);
        for (final sentence in parts.sentences) {
          final trimmed = sentence.trim();
          if (trimmed.isNotEmpty) {
            if (actualTaskId == null) {
              actualTaskId = pipeline.createTaskFromLLM(input, trimmed);
            } else {
              pipeline.addLLMResponse(actualTaskId, trimmed);
            }
          }
        }
        currentText = parts.remaining;

        notifyListeners();
      }

      // Flush remaining text
      if (currentText.isNotEmpty) {
        if (actualTaskId == null) {
          actualTaskId = pipeline.createTaskFromLLM(input, currentText);
        } else {
          pipeline.addLLMResponse(actualTaskId, currentText);
        }
      }
      if (actualTaskId != null) {
        pipeline.markLLMFinished(actualTaskId);
      }

      await sessionManager.updateSessionContent(_sessionId, _messages);

    } catch (e) {
      if (e is AbortException) {
        // Interrupted - expected
      }
    } finally {
      _isStreaming = false;
      notifyListeners();
    }
  }

  /// Interrupt current streaming response
  void interrupt() {
    _abortController?.abort();
    pipeline.interruptCurrentTask();
    _isStreaming = false;
    notifyListeners();
  }

  /// Initialize from saved state: load settings + auto-restore last session.
  Future<void> initFromSavedState() async {
    try {
      final settings = await backend.getSettings();
      if (settings.systemPrompt.isNotEmpty) {
        _systemPrompt = settings.systemPrompt;
      }
      _enableMemoryRetrieval = settings.enableMemoryRetrieval;

      // Load session list into cache
      await sessionManager.loadSessions();

      // Auto-load last session from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final lastId = prefs.getString('last_session_id');
      if (lastId != null && lastId.isNotEmpty) {
        await setSessionId(lastId);
      }
    } catch (_) {}
    notifyListeners();
  }

  /// Load a session
  Future<void> setSessionId(String? id) async {
    _sessionId = id;
    if (id != null) {
      // Persist as last active session
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('last_session_id', id);
      try {
        final session = await sessionManager.fetchSessionContent(id);
        if (session != null) {
          final history = (session['history'] as List?)
              ?.map((h) => HistoryItem.fromJson(h as Map<String, dynamic>))
              .toList() ?? [];
          _messages
            ..clear()
            ..addAll(history);
        }
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Pipeline subscription callback
  void _onPipelineUpdate(List<Task> tasks) {
    final task = pipeline.getNextTaskForLLM();
    if (task != null && task.input != null) {
      pipeline.markLLMStarted(task.id);
    }
    notifyListeners();
  }

  /// Simple sentence splitting for TTS chunking
  _SplitResult _splitSentences(String text) {
    final sentences = <String>[];
    int lastSplit = 0;
    for (int i = 0; i < text.length; i++) {
      if ('.!?。！？\n'.contains(text[i]) && i > lastSplit) {
        sentences.add(text.substring(lastSplit, i + 1));
        lastSplit = i + 1;
      }
    }
    final remaining = text.substring(lastSplit);
    return _SplitResult(sentences, remaining);
  }
}

class _SplitResult {
  final List<String> sentences;
  final String remaining;
  _SplitResult(this.sentences, this.remaining);
}

/// Simple AbortController equivalent
class AbortController {
  bool _aborted = false;
  bool get isAborted => _aborted;
  void abort() { _aborted = true; }
}

class AbortException implements Exception {}
