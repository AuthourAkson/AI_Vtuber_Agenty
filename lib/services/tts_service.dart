import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'storage_service.dart';

/// TTS service using edge-tts CLI (subprocess).
/// Audio cached in D:\AiVtuber_Agent_profile\tts_cache\
class TTSService {
  final StorageService _storage;

  String _voice = 'zh-CN-XiaoxiaoNeural';
  final _cacheDir = p.join(StorageService.profileDir, 'tts_cache');

  TTSService(this._storage) {
    _ensureCacheDir();
  }

  String get voice => _voice;

  void _ensureCacheDir() {
    final dir = Directory(_cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// Change TTS voice.
  void setVoice(String v) => _voice = v;

  /// Synthesize text to speech. Returns WAV audio bytes.
  Future<List<int>> synthesize(String text) async {
    if (text.trim().isEmpty) return <int>[];

    // Check cache
    final cacheKey = _cacheKey(text, _voice);
    final cacheFile = File(p.join(_cacheDir, cacheKey));
    if (cacheFile.existsSync()) {
      return cacheFile.readAsBytesSync();
    }

    // Use edge-tts CLI
    try {
      final tempWav = p.join(_cacheDir, '${cacheKey}_temp.mp3');
      final result = await Process.run(
        'edge-tts',
        ['--voice', _voice, '--text', text, '--write-media', tempWav],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final tempFile = File(tempWav);
        if (tempFile.existsSync()) {
          final bytes = tempFile.readAsBytesSync();
          // Move to cache
          tempFile.copySync(cacheFile.path);
          tempFile.deleteSync();
          return bytes;
        }
      }
    } catch (_) {
      // edge-tts not available — return empty
    }

    return <int>[];
  }

  /// List available edge-tts voices.
  Future<List<Map<String, dynamic>>> listVoices() async {
    try {
      final result = await Process.run(
        'edge-tts',
        ['--list-voices'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        final voices = <Map<String, dynamic>>[];
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Name:') || trimmed.startsWith('ShortName:')) {
            final name = trimmed.split(':').last.trim();
            voices.add({'name': name, 'id': name});
          }
        }
        // Deduplicate
        final seen = <String>{};
        return voices.where((v) => seen.add(v['name'] as String)).toList();
      }
    } catch (_) {}
    return [
      {'name': 'zh-CN-XiaoxiaoNeural', 'id': 'zh-CN-XiaoxiaoNeural'},
      {'name': 'zh-CN-YunxiNeural', 'id': 'zh-CN-YunxiNeural'},
      {'name': 'en-US-JennyNeural', 'id': 'en-US-JennyNeural'},
      {'name': 'ja-JP-NanamiNeural', 'id': 'ja-JP-NanamiNeural'},
    ];
  }

  String _cacheKey(String text, String voice) {
    final hash = (text.hashCode ^ voice.hashCode).toRadixString(16);
    return 'tts_${voice}_$hash.mp3';
  }
}
