import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path/path.dart' as p;
import 'storage_service.dart';

/// TTS service using edge-tts CLI (subprocess).
/// Audio cached in D:\\AiVtuber_Agent_profile\\tts_cache\\
class TTSService {
  final StorageService _storage;
  final AudioPlayer _player = AudioPlayer();

  String _voice = 'zh-CN-XiaoxiaoNeural';
  String _pitch = '+0Hz';
  String _rate = '+0%';
  String _volume = '+0%';
  final _cacheDir = p.join(StorageService.profileDir, 'tts_cache');

  TTSService(this._storage) {
    _ensureCacheDir();
  }

  String get voice => _voice;
  String get pitch => _pitch;
  String get rate => _rate;
  String get volume => _volume;

  void _ensureCacheDir() {
    final dir = Directory(_cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// Change TTS voice.
  void setVoice(String v) => _voice = v;

  /// Set EdgeTTS parameters.
  void setParams({
    String? voice,
    String? pitch,
    String? rate,
    String? volume,
  }) {
    if (voice != null) _voice = voice;
    if (pitch != null) _pitch = pitch;
    if (rate != null) _rate = rate;
    if (volume != null) _volume = volume;
  }

  /// Synthesize text to speech. Returns WAV audio bytes.
  Future<List<int>> synthesize(String text) async {
    final path = await synthesizeToFile(text);
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) {
        return file.readAsBytesSync();
      }
    }
    return <int>[];
  }

  /// Synthesize text to speech, returns file path to cached audio.
  Future<String?> synthesizeToFile(String text) async {
    if (text.trim().isEmpty) return null;

    // Check cache
    final cacheKey = _cacheKey(text, _voice, _pitch, _rate, _volume);
    final cacheFile = File(p.join(_cacheDir, cacheKey));
    if (cacheFile.existsSync()) {
      return cacheFile.path;
    }

    // Use edge-tts CLI
    try {
      final tempMp3 = p.join(_cacheDir, '${cacheKey}_temp.mp3');
      final result = await Process.run(
        'edge-tts',
        [
          '--voice', _voice,
          '--text', text,
          '--pitch', _pitch,
          '--rate', _rate,
          '--volume', _volume,
          '--write-media', tempMp3,
        ],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final tempFile = File(tempMp3);
        if (tempFile.existsSync()) {
          // Move to cache
          tempFile.copySync(cacheFile.path);
          tempFile.deleteSync();
          return cacheFile.path;
        }
      }
    } catch (_) {
      // edge-tts not available — return null
    }

    return null;
  }

  /// Synthesize and play audio immediately.
  /// Returns true if playback started successfully.
  Future<bool> synthesizeAndPlay(String text) async {
    final path = await synthesizeToFile(text);
    if (path == null) return false;

    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize to file, compute mouth volume sequence, and play.
  /// Returns (audioPath, volumeSequence) — volumeSequence is empty on failure.
  /// Volume values are [0.0, 1.0] at ~50ms intervals (20 FPS).
  /// [onBeforePlay] is called after synthesis but before playback starts —
  /// gives VRM pop-out a head start on fetching/decoding the audio.
  Future<(String?, List<double>)> synthesizeWithVolumes(String text,
      {void Function(String path)? onBeforePlay}) async {
    final path = await synthesizeToFile(text);
    if (path == null) return (null, <double>[]);

    final volumes = await computeVolumeSequence(path);

    // VRM head start: push audio URL before playback begins
    onBeforePlay?.call(path);

    try {
      await _player.stop();
      await _player.play(DeviceFileSource(path));
    } catch (_) {
      return (path, volumes);
    }

    return (path, volumes);
  }

  /// Compute RMS volume sequence from an audio file.
  /// Uses ffmpeg to extract raw PCM, then slices into 50ms chunks.
  /// Returns normalized values [0.0, 1.0] at ~20 FPS resolution.
  /// Falls back to empty list if ffmpeg is unavailable.
  Future<List<double>> computeVolumeSequence(String audioPath) async {
    try {
      // ffmpeg: extract 16-bit signed PCM mono at 16kHz
      final result = await Process.run(
        'ffmpeg',
        [
          '-i', audioPath,
          '-f', 's16le',
          '-acodec', 'pcm_s16le',
          '-ar', '16000',
          '-ac', '1',
          'pipe:1',
        ],
        stdoutEncoding: null, // raw bytes
        runInShell: true,
      );

      if (result.exitCode != 0) return <double>[];

      final rawBytes = result.stdout as List<int>;
      if (rawBytes.length < 2) return <double>[];

      // 16kHz mono → 50ms = 800 samples = 1600 bytes
      const samplesPerChunk = 800;
      const bytesPerChunk = samplesPerChunk * 2; // int16 = 2 bytes
      final chunkCount = rawBytes.length ~/ bytesPerChunk;

      final volumes = <double>[];
      final byteData = ByteData.sublistView(Uint8List.fromList(rawBytes));

      for (int i = 0; i < chunkCount; i++) {
        final offset = i * bytesPerChunk;
        double sumSq = 0;
        for (int s = 0; s < samplesPerChunk; s++) {
          final sampleOffset = offset + s * 2;
          if (sampleOffset + 1 >= rawBytes.length) break;
          final sample = byteData.getInt16(sampleOffset, Endian.little);
          sumSq += (sample * sample).toDouble();
        }
        final rms = sqrt(sumSq / samplesPerChunk);
        // Normalize to LAV2-compatible scale: divisor ~2000 matches Web Audio API
        // getByteFrequencyData() sum/15096 sensitivity (LAV2's approach)
        final normalized = (rms / 2000.0).clamp(0.0, 1.0);
        volumes.add(normalized);
      }

      return volumes;
    } catch (_) {
      return <double>[];
    }
  }

  /// Stop current playback.
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  /// Check if currently playing.
  bool get isPlaying {
    try {
      return _player.state == PlayerState.playing;
    } catch (_) {
      return false;
    }
  }

  /// Stream of player state changes.
  Stream<PlayerState> get onPlayerStateChanged => _player.onPlayerStateChanged;

  /// Stream that fires when audio playback completes naturally.
  Stream<void> get onPlayerComplete => _player.onPlayerComplete;

  /// List available edge-tts voices.
  Future<List<Map<String, String>>> listVoices() async {
    try {
      final result = await Process.run(
        'edge-tts',
        ['--list-voices'],
        runInShell: true,
      );
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).split('\n');
        final voices = <Map<String, String>>[];
        final seen = <String>{};
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Name:') || trimmed.startsWith('ShortName:')) {
            final name = trimmed.split(':').last.trim();
            if (seen.add(name)) {
              // Extract locale info from name (e.g., "Microsoft Server Speech Text to Speech Voice (zh-CN, XiaoxiaoNeural)")
              voices.add(_parseVoiceEntry(trimmed));
            }
          }
        }
        return voices;
      }
    } catch (_) {}
    return _defaultVoices();
  }

  Map<String, String> _parseVoiceEntry(String line) {
    // Try to extract locale and display name
    final parts = line.split(RegExp(r'[():,]'));
    String locale = '';
    String displayName = '';
    String shortName = line.split(':').last.trim();

    for (int i = 0; i < parts.length; i++) {
      final p = parts[i].trim();
      if (RegExp(r'^[a-z]{2}-[A-Z]{2}$').hasMatch(p)) {
        locale = p;
      } else if (p.contains('Neural') || p.contains('Standard')) {
        displayName = p;
      }
    }

    if (displayName.isEmpty) displayName = shortName;

    return {
      'shortName': shortName,
      'locale': locale,
      'displayName': displayName,
    };
  }

  List<Map<String, String>> _defaultVoices() {
    return [
      {'shortName': 'zh-CN-XiaoxiaoNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoxiao (晓晓)'},
      {'shortName': 'zh-CN-YunxiNeural', 'locale': 'zh-CN', 'displayName': 'Yunxi (云希)'},
      {'shortName': 'zh-CN-YunyangNeural', 'locale': 'zh-CN', 'displayName': 'Yunyang (云扬)'},
      {'shortName': 'zh-CN-XiaoyiNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoyi (晓伊)'},
      {'shortName': 'zh-CN-YunjianNeural', 'locale': 'zh-CN', 'displayName': 'Yunjian (云健)'},
      {'shortName': 'zh-CN-XiaochenNeural', 'locale': 'zh-CN', 'displayName': 'Xiaochen (晓辰)'},
      {'shortName': 'zh-CN-XiaohanNeural', 'locale': 'zh-CN', 'displayName': 'Xiaohan (晓涵)'},
      {'shortName': 'zh-CN-XiaomengNeural', 'locale': 'zh-CN', 'displayName': 'Xiaomeng (晓萌)'},
      {'shortName': 'zh-CN-XiaomoNeural', 'locale': 'zh-CN', 'displayName': 'Xiaomo (晓墨)'},
      {'shortName': 'zh-CN-XiaoqiuNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoqiu (晓秋)'},
      {'shortName': 'zh-CN-XiaoruiNeural', 'locale': 'zh-CN', 'displayName': 'Xiaorui (晓睿)'},
      {'shortName': 'zh-CN-XiaoshuangNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoshuang (晓双)'},
      {'shortName': 'zh-CN-XiaoxuanNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoxuan (晓萱)'},
      {'shortName': 'zh-CN-XiaoyanNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoyan (晓颜)'},
      {'shortName': 'zh-CN-XiaoyouNeural', 'locale': 'zh-CN', 'displayName': 'Xiaoyou (晓悠)'},
      {'shortName': 'zh-CN-XiaozhenNeural', 'locale': 'zh-CN', 'displayName': 'Xiaozhen (晓臻)'},
      {'shortName': 'en-US-JennyNeural', 'locale': 'en-US', 'displayName': 'Jenny'},
      {'shortName': 'en-US-AriaNeural', 'locale': 'en-US', 'displayName': 'Aria'},
      {'shortName': 'ja-JP-NanamiNeural', 'locale': 'ja-JP', 'displayName': 'Nanami'},
      {'shortName': 'ja-JP-KeitaNeural', 'locale': 'ja-JP', 'displayName': 'Keita'},
    ];
  }

  String _cacheKey(String text, String voice, String pitch, String rate, String volume) {
    final combined = '$text|$voice|$pitch|$rate|$volume';
    final hash = combined.hashCode.toRadixString(16);
    return 'tts_${voice}_$hash.mp3';
  }

  /// Dispose resources.
  void dispose() {
    _player.dispose();
  }
}
