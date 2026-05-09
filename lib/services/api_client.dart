import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/settings.dart';

/// HTTP client for LocalAIVtuber2 backend API (localhost:8000)
class ApiClient {
  final String baseUrl;

  ApiClient({this.baseUrl = 'http://localhost:8000'});

  // ─── Settings ───

  Future<AppSettings> getSettings() async {
    final res = await http.get(Uri.parse('$baseUrl/api/settings'));
    if (res.statusCode == 200) {
      return AppSettings.fromJson(jsonDecode(res.body));
    }
    throw Exception('Failed to load settings: ${res.statusCode}');
  }

  Future<void> updateSettings(AppSettings settings) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/settings/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings.toJson()),
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to update settings: ${res.statusCode}');
    }
  }

  // ─── Chat Completion (streaming) ───

  Stream<String> completionStream({
    required String text,
    required List<HistoryItem> history,
    required String systemPrompt,
  }) async* {
    final request = http.Request('POST', Uri.parse('$baseUrl/api/completion'))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'text': text,
        'history': history.map((h) => h.toJson()).toList(),
        'systemPrompt': systemPrompt,
      });

    final response = await http.Client().send(request);
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      yield chunk;
    }
  }

  // ─── Chat Sessions ───

  Future<String> createSession() async {
    final res = await http.post(Uri.parse('$baseUrl/api/chat/session/create'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body)['id'] as String;
    }
    throw Exception('Failed to create session');
  }

  Future<void> updateSession(String id, List<HistoryItem> history) async {
    await http.post(
      Uri.parse('$baseUrl/api/chat/session/update'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id': id,
        'title': 'Chat Session',
        'history': history.map((h) => h.toJson()).toList(),
      }),
    );
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    final res = await http.get(Uri.parse('$baseUrl/api/chat/sessions'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    throw Exception('Failed to list sessions');
  }

  Future<Map<String, dynamic>> getSession(String id) async {
    final res = await http.get(Uri.parse('$baseUrl/api/chat/session/$id'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Failed to get session');
  }

  Future<void> deleteSession(String id) async {
    await http.delete(Uri.parse('$baseUrl/api/chat/session/$id'));
  }

  // ─── TTS ───

  Future<List<int>> ttsSynthesize(String text) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/tts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text}),
    );
    if (res.statusCode == 200) {
      return res.bodyBytes.toList();
    }
    throw Exception('TTS failed: ${res.statusCode}');
  }

  Future<List<Map<String, dynamic>>> listTTSVoices() async {
    final res = await http.get(Uri.parse('$baseUrl/api/tts/voices'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  // ─── LLM Models ───

  Future<List<Map<String, dynamic>>> listLLMModels() async {
    final res = await http.get(Uri.parse('$baseUrl/api/llm/models'));
    if (res.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(res.body));
    }
    return [];
  }

  // ─── Character Models ───

  Future<List<String>> listLive2DModels() async {
    final res = await http.get(Uri.parse('$baseUrl/api/character/live2d/models'));
    if (res.statusCode == 200) {
      return List<String>.from(jsonDecode(res.body));
    }
    return [];
  }

  // ─── Memory ───

  Future<List<String>> queryMemory(String text, {int limit = 3}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/memory/context'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'limit': limit}),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final context = data['context'] as List?;
      if (context != null) {
        return context
            .map((c) => (c is Map ? c['document'] as String? ?? '' : ''))
            .where((s) => s.isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  // ─── Vision ───

  Future<Map<String, dynamic>> captureScreenshot() async {
    final res = await http.get(Uri.parse('$baseUrl/api/screenshot'));
    if (res.statusCode == 200) {
      return jsonDecode(res.body);
    }
    throw Exception('Screenshot failed: ${res.statusCode}');
  }
}
