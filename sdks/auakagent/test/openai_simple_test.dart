import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:llm_dart/llm_dart.dart';

void main() async {
  // Never hardcode credentials in this file.
  // PowerShell: $env:OPENAI_API_KEY="sk-..."   cmd: set OPENAI_API_KEY=sk-...
  final apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
  if (apiKey.isEmpty) {
    print('⚠️  OPENAI_API_KEY is not set — skipping openai_simple_test.');
    print('   Set it as an environment variable and re-run.');
    return;
  }

  print('=== Test 1: Raw HttpClient through proxy ===');
  try {
    final client = HttpClient();
    client.findProxy = (uri) => "PROXY 127.0.0.1:7890";
    final request = await client.getUrl(Uri.parse('https://api.openai.com/v1/models'));
    request.headers.set('Authorization', 'Bearer $apiKey');
    final response = await request.close();
    print('✅ Raw HttpClient: ${response.statusCode}');
    client.close();
  } catch (e) {
    print('❌ Raw HttpClient failed: $e');
  }

  print('\n=== Test 2: Dio with IOHttpClientAdapter proxy ===');
  try {
    final dio = Dio(BaseOptions(
      baseUrl: 'https://api.openai.com/v1',
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      connectTimeout: Duration(seconds: 30),
      receiveTimeout: Duration(seconds: 30),
    ));

    // Configure proxy using IOHttpClientAdapter
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => "PROXY 127.0.0.1:7890";
        return client;
      },
    );

    final response = await dio.post(
      '/chat/completions',
      data: {
        'model': 'gpt-5.4',
        'messages': [{'role': 'user', 'content': 'Hello'}],
        'temperature': 0.7,
      },
    );
    print('✅ Dio with proxy: ${response.statusCode}');
    print('Response: ${(response.data as Map)['choices'][0]['message']['content']}');
  } catch (e) {
    print('❌ Dio with proxy failed: $e');
  }

  print('\n=== Test 3: llm_dart with proxy ===');
  try {
    final provider = await ai()
        .openai()
        .apiKey(apiKey)
        .model('gpt-4o-mini')
        .temperature(0.7)
        .http((http) => http.proxy('http://127.0.0.1:7890'))
        .build();
    final messages = [ChatMessage.user('Hello, world!')];
    final response = await provider.chat(messages);
    print('✅ llm_dart: ${response.text}');
  } catch (e) {
    print('❌ llm_dart failed: $e');
  }
}
