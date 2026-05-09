import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';
import '../models/settings.dart';

/// Direct LLM client using OpenAI-compatible streaming API.
/// No local backend needed — calls cloud providers directly.
class LLMService {
  String baseUrl = 'https://api.siliconflow.cn/v1';
  String apiKey = '';
  String model = 'deepseek-ai/DeepSeek-V3.2';
  double temperature = 0.7;
  double topP = 0.9;

  void updateFromSettings(AppSettings settings) {
    if (settings.apiRelayBaseUrl.isNotEmpty) baseUrl = settings.apiRelayBaseUrl;
    if (settings.apiRelayApiKey.isNotEmpty) apiKey = settings.apiRelayApiKey;
    if (settings.apiRelayModel.isNotEmpty) model = settings.apiRelayModel;
  }

  /// Stream text completion from the LLM provider.
  Stream<String> completionStream({
    required String text,
    required List<HistoryItem> history,
    required String systemPrompt,
  }) async* {
    final client = http.Client();
    try {
      final messages = <Map<String, String>>[];

      if (systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': systemPrompt});
      }

      for (final h in history) {
        messages.add({'role': h.role, 'content': h.content});
      }
      messages.add({'role': 'user', 'content': text});

      // Normalize base URL (remove trailing /v1 if present, then re-add)
      var url = baseUrl.replaceAll(RegExp(r'/+$'), '');
      if (!url.endsWith('/v1')) {
        url = '$url/v1';
      }
      url = '$url/chat/completions';

      final request = http.Request('POST', Uri.parse(url))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        })
        ..body = jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'top_p': topP,
          'max_tokens': 2048,
          'stream': true,
        });

      final response = await client.send(request);

      if (response.statusCode != 200) {
        final errorBody = await response.stream.bytesToString();
        throw Exception('LLM API error ${response.statusCode}: $errorBody');
      }

      // Parse SSE stream
      await for (final chunk in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.isEmpty || !chunk.startsWith('data: ')) continue;
        final data = chunk.substring(6).trim();
        if (data == '[DONE]') break;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final delta = choices[0]['delta'] as Map<String, dynamic>?;
            final content = delta?['content'] as String?;
            if (content != null && content.isNotEmpty) {
              yield content;
            }
          }
        } catch (_) {
          // Skip malformed chunks
        }
      }
    } finally {
      client.close();
    }
  }

  /// Get available models from the provider.
  Future<List<Map<String, dynamic>>> listModels() async {
    try {
      var url = baseUrl.replaceAll(RegExp(r'/+$'), '');
      if (!url.endsWith('/v1')) url = '$url/v1';
      url = '$url/models';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $apiKey'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final models = (data['data'] as List)
            .map((m) => {'id': m['id'] as String, 'name': m['id'] as String})
            .toList();
        return models;
      }
    } catch (_) {}
    return [];
  }
}
