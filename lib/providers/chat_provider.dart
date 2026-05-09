import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/task.dart';
import '../services/api_client.dart';
import '../services/pipeline_manager.dart';
import '../services/session_manager.dart';

/// Central state for chat messages, sessions, and pipeline interaction.
/// Uses ChangeNotifier for Provider-based reactive UI updates.
class ChatProvider extends ChangeNotifier {
  final ApiClient api = ApiClient();
  late final PipelineManager pipeline;
  late final SessionManager sessionManager;

  final _messages = <HistoryItem>[];
  String? _sessionId;
  String _systemPrompt = '';
  String _visionPrompt = '';
  String _ocrPrompt = '';
  String _retrievedContext = '';
  bool _enableMemoryRetrieval = true;
  bool _connected = false;

  // Streaming state
  AbortController? _abortController;
  bool _isStreaming = false;

  ChatProvider() {
    pipeline = PipelineManager();
    sessionManager = SessionManager(api);
    pipeline.subscribe(_onPipelineUpdate);
  }

  // ─── Getters ───

  List<HistoryItem> get messages => List.unmodifiable(_messages);
  String? get sessionId => _sessionId;
  String get systemPrompt => _systemPrompt;
  String get visionPrompt => _visionPrompt;
  String get ocrPrompt => _ocrPrompt;
  String get retrievedContext => _retrievedContext;
  bool get enableMemoryRetrieval => _enableMemoryRetrieval;
  bool get connected => _connected;
  bool get isStreaming => _isStreaming;

  // ─── Setters ───

  set systemPrompt(String v) { _systemPrompt = v; notifyListeners(); }
  set visionPrompt(String v) { _visionPrompt = v; notifyListeners(); }
  set ocrPrompt(String v) { _ocrPrompt = v; notifyListeners(); }
  set enableMemoryRetrieval(bool v) {
    _enableMemoryRetrieval = v;
    if (!v) _retrievedContext = '';
    notifyListeners();
  }

  // ─── Connection ───

  Future<void> connectToBackend() async {
    try {
      await api.getSettings();
      _connected = true;
      notifyListeners();
    } catch (_) {
      _connected = false;
      notifyListeners();
    }
  }

  void disconnect() {
    _connected = false;
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

    try {
      // Query memory context if enabled
      String contextText = '';
      if (_enableMemoryRetrieval) {
        try {
          final docs = await api.queryMemory(input, limit: 3);
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
      }
      await sessionManager.updateSessionContent(_sessionId, _messages);

      // Stream from backend
      final history = _messages.length > 30
          ? _messages.sublist(_messages.length - 31, _messages.length - 1)
          : _messages.sublist(0, _messages.length - 1);

      String aiMessage = '';
      String currentText = '';
      String? actualTaskId = taskId;

      await for (final chunk in api.completionStream(
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

  /// Load a session
  Future<void> setSessionId(String? id) async {
    _sessionId = id;
    if (id != null) {
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
      // Note: sendMessage with taskId would be called from here
      // but to avoid recursion, the UI listens to pipeline state
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
