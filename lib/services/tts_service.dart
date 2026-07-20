import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:ffi/ffi.dart';
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
    stopGptSovitsServer();
  }

  // ═══════════════════════════════════════════════════════════════
  // GPT-SoVITS (api_v2.py subprocess + HTTP)
  // ═══════════════════════════════════════════════════════════════

  // ── Windows Job Object (auto-kill subprocess on parent exit) ──

  static final DynamicLibrary _kernel32 = DynamicLibrary.open('kernel32.dll');
  static final Pointer<IntPtr> Function(Pointer<Utf16> name, Pointer<Utf16> name2) _CreateJobObjectW =
      _kernel32.lookupFunction<Pointer<IntPtr> Function(Pointer<Utf16>, Pointer<Utf16>),
          Pointer<IntPtr> Function(Pointer<Utf16>, Pointer<Utf16>)>('CreateJobObjectW');
  static final int Function(Pointer<IntPtr> job, int infoClass, Pointer<Void> info, int infoLen) _SetInformationJobObject =
      _kernel32.lookupFunction<Int32 Function(Pointer<IntPtr>, Uint32, Pointer<Void>, Uint32),
          int Function(Pointer<IntPtr>, int, Pointer<Void>, int)>('SetInformationJobObject');
  static final int Function(Pointer<IntPtr> job, Pointer<Void> process) _AssignProcessToJobObject =
      _kernel32.lookupFunction<Int32 Function(Pointer<IntPtr>, Pointer<Void>),
          int Function(Pointer<IntPtr>, Pointer<Void>)>('AssignProcessToJobObject');
  static final Pointer<Void> Function(int access, int inherit, int pid) _OpenProcess =
      _kernel32.lookupFunction<Pointer<Void> Function(Uint32, Int32, Uint32),
          Pointer<Void> Function(int, int, int)>('OpenProcess');
  static final int Function(Pointer<Void> handle) _CloseHandle =
      _kernel32.lookupFunction<Int32 Function(Pointer<Void>),
          int Function(Pointer<Void>)>('CloseHandle');

  static Pointer<IntPtr>? _gptJobHandle;

  /// Create a Windows Job Object that auto-kills children when parent exits.
  static void _ensureJobObject() {
    if (_gptJobHandle != null) return;
    _gptJobHandle = _CreateJobObjectW(nullptr, nullptr);
    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION: LimitFlags at offset 16
    const int JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    final ptr = calloc<Uint8>(144);
    ptr[16] = 0x00; ptr[17] = 0x20; ptr[18] = 0x00; ptr[19] = 0x00;
    _SetInformationJobObject(_gptJobHandle!, 9, ptr.cast<Void>(), 144);
    calloc.free(ptr);
  }

  /// Assign a process to the Job Object so it dies with us.
  static void _assignToJob(int pid) {
    if (_gptJobHandle == null) return;
    const int PROCESS_SET_QUOTA = 0x0100;
    const int PROCESS_TERMINATE = 0x0001;
    final hProcess = _OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE, 0, pid);
    if (hProcess != nullptr) {
      _AssignProcessToJobObject(_gptJobHandle!, hProcess);
      _CloseHandle(hProcess);
    }
  }

  // ── Server lifecycle ──

  Process? _gptSovitsProcess;
  String _gptSovitsBaseUrl = 'http://127.0.0.1:9880';
  final _gptStderrBuf = <String>[];
  final _gptStdoutBuf = <String>[];

  /// Start GPT-SoVITS api_v2.py server.
  /// [pythonPath] — path to python executable (default: 'python')
  /// [projectPath] — GPT-Sovits-Main root directory
  /// [port] — port for api server (default 9880)
  /// [device] — 'cuda' or 'cpu'
  /// Returns null on success, error message on failure.
  Future<String?> startGptSovitsServer({
    required String pythonPath,
    required String projectPath,
    int port = 9880,
    String device = 'cuda',
  }) async {
    if (_gptSovitsProcess != null) return null; // already running

    _gptSovitsBaseUrl = 'http://127.0.0.1:$port';
    _gptStderrBuf.clear();
    _gptStdoutBuf.clear();
    final apiScript = p.join(projectPath, 'api_v2.py');

    if (!File(apiScript).existsSync()) {
      return 'api_v2.py not found at $apiScript';
    }

    try {
      // Write a temp config with the requested device (api_v2.py reads from YAML)
      final tempConfigPath = p.join(_cacheDir, 'tts_infer_temp.yaml');
      final isHalf = device == 'cuda';
      File(tempConfigPath).writeAsStringSync(
        'custom:\n'
        '  device: $device\n'
        '  is_half: $isHalf\n'
        '  version: v2\n'
      );

      _gptSovitsProcess = await Process.start(
        pythonPath,
        ['api_v2.py', '-a', '127.0.0.1', '-p', '$port', '-c', tempConfigPath],
        workingDirectory: projectPath,
        mode: ProcessStartMode.normal,
      );

      // Auto-kill subprocess when parent exits (Windows Job Object)
      _ensureJobObject();
      _assignToJob(_gptSovitsProcess!.pid);

      // Drain stdout to prevent backpressure (also capture for error reporting)
      _gptSovitsProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        _gptStdoutBuf.add(line);
        if (_gptStdoutBuf.length > 50) _gptStdoutBuf.removeAt(0);
      });

      // Capture stderr for debugging
      _gptSovitsProcess!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((line) {
        _gptStderrBuf.add(line);
        if (_gptStderrBuf.length > 50) _gptStderrBuf.removeAt(0);
      });

      // Capture exit future once (single-subscription)
      final exitFuture = _gptSovitsProcess!.exitCode;

      // Check if process died immediately (race exit vs 1s delay)
      final earlyDeath = await Future.any([
        exitFuture,
        Future.delayed(Duration(seconds: 1), () => -1),
      ]);
      if (earlyDeath != -1) {
        _gptSovitsProcess = null;
        final tail = _buildGptErrorTail();
        return 'Python process exited with code $earlyDeath.\n$tail';
      }

      // Health check: retry up to 8 times with growing intervals (total ~60s)
      bool alive = false;
      for (int i = 0; i < 8; i++) {
        final delay = i < 3 ? 3 : 5; // first 3 attempts: 3s, rest: 5s
        await Future.delayed(Duration(seconds: delay));
        alive = await _checkGptSovitsAlive();
        if (alive) break;
        // Check if process died while waiting
        final deathCheck = await Future.any([
          exitFuture,
          Future.delayed(Duration.zero, () => -1),
        ]);
        if (deathCheck != -1) {
          _gptSovitsProcess = null;
          final tail = _buildGptErrorTail();
          return 'Python process exited with code $deathCheck while loading.\n$tail';
        }
      }
      if (!alive) {
        _gptSovitsProcess?.kill();
        _gptSovitsProcess = null;
        final tail = _buildGptErrorTail();
        final output = tail.isNotEmpty ? '\n$tail' : '\n(no stdout/stderr output)';
        return 'Server not responding after 60s.$output\n\nTry running manually: cd "$projectPath" && $pythonPath api_v2.py -p $port';
      }
    } catch (e) {
      return 'Failed to start GPT-SoVITS server: $e';
    }

    return null; // success
  }

  void stopGptSovitsServer() {
    _gptSovitsProcess?.kill();
    _gptSovitsProcess = null;
  }

  bool get isGptSovitsRunning => _gptSovitsProcess != null;

  /// Build combined stdout+stderr error tail.
  String _buildGptErrorTail() {
    final parts = <String>[];
    if (_gptStdoutBuf.isNotEmpty) {
      parts.add('--- stdout ---\n${_gptStdoutBuf.join('\n')}');
    }
    if (_gptStderrBuf.isNotEmpty) {
      parts.add('--- stderr ---\n${_gptStderrBuf.join('\n')}');
    }
    return parts.join('\n');
  }

  Future<bool> _checkGptSovitsAlive() async {
    try {
      final port = Uri.parse(_gptSovitsBaseUrl).port;
      final socket = await Socket.connect('127.0.0.1', port,
        timeout: Duration(seconds: 3));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize text via GPT-SoVITS HTTP API.
  /// Returns audio bytes (WAV) or null on failure.
  Future<List<int>?> synthesizeGptSovits({
    required String text,
    String textLang = 'zh',
    required String refAudioPath,
    String promptText = '',
    String promptLang = 'zh',
    double speed = 1.0,
    int topK = 5,
    double topP = 1.0,
    double temperature = 1.0,
    int batchSize = 1,
    String mediaType = 'wav',
  }) async {
    // Strip emoji to avoid GBK encoding errors in GPT-SoVITS Python server
    final cleanText = text.replaceAll(RegExp(r'[\u{1F600}-\u{1FFFF}\u{2600}-\u{27BF}\u{FE00}-\u{FEFF}\u{200D}\u{200C}]', unicode: true), '');
    final uri = Uri.parse('$_gptSovitsBaseUrl/tts');
    print('[GPT-SoVITS] TTS request:\n  text=${cleanText.length>50 ? "${cleanText.substring(0,50)}..." : cleanText}\n  ref_audio=$refAudioPath\n  prompt_text=$promptText\n  prompt_lang=$promptLang');
    final body = utf8.encode(jsonEncode({
      'text': cleanText,
      'text_lang': textLang,
      'ref_audio_path': refAudioPath,
      'aux_ref_audio_paths': [],
      'prompt_text': promptText,
      'prompt_lang': promptLang,
      'top_k': topK,
      'top_p': topP,
      'temperature': temperature,
      'text_split_method': 'cut0',
      'batch_size': batchSize,
      'batch_threshold': 0.75,
      'split_bucket': true,
      'speed_factor': speed,
      'fragment_interval': 0.3,
      'seed': -1,
      'media_type': mediaType,
      'streaming_mode': false,
      'parallel_infer': true,
      'repetition_penalty': 1.35,
      'sample_steps': 32,
      'super_sampling': false,
    }));

    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Content-Length', body.length.toString());
      request.add(body);
      final response = await request.close().timeout(Duration(seconds: 60));

      if (response.statusCode == 200) {
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        print('[GPT-SoVITS] TTS success: ${bytes.length} bytes');
        return bytes;
      } else {
        // Read error body
        String errorBody = '';
        try {
          errorBody = await response.transform(utf8.decoder).join();
        } catch (_) {}
        print('[GPT-SoVITS] TTS error ${response.statusCode}: $errorBody');
      }
    } catch (e) {
      print('[GPT-SoVITS] TTS request failed: $e');
    } finally {
      client.close();
    }

    return null;
  }

  /// Synthesize and play via GPT-SoVITS.
  Future<bool> synthesizeGptSovitsAndPlay({
    required String text,
    String textLang = 'zh',
    required String refAudioPath,
    String promptText = '',
    String promptLang = 'zh',
  }) async {
    final bytes = await synthesizeGptSovits(
      text: text,
      textLang: textLang,
      refAudioPath: refAudioPath,
      promptText: promptText,
      promptLang: promptLang,
    );
    if (bytes == null || bytes.isEmpty) return false;

    // Write to temp file and play
    final tempFile = File(p.join(_cacheDir, 'gpt_sovits_temp.wav'));
    tempFile.writeAsBytesSync(bytes);

    try {
      await _player.stop();
      await _player.play(DeviceFileSource(tempFile.path));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Synthesize via GPT-SoVITS, compute mouth volume sequence, and play.
  /// Returns (audioPath, volumeSequence).
  Future<(String?, List<double>)> synthesizeGptSovitsWithVolumes(
    String text, {
    String textLang = 'zh',
    required String refAudioPath,
    String promptText = '',
    String promptLang = 'zh',
  }) async {
    final bytes = await synthesizeGptSovits(
      text: text,
      textLang: textLang,
      refAudioPath: refAudioPath,
      promptText: promptText,
      promptLang: promptLang,
    );
    if (bytes == null || bytes.isEmpty) return (null, <double>[]);

    final tempFile = File(p.join(_cacheDir, 'gpt_sovits_temp.wav'));
    tempFile.writeAsBytesSync(bytes);

    final volumes = await computeVolumeSequence(tempFile.path);

    try {
      await _player.stop();
      await _player.play(DeviceFileSource(tempFile.path));
      return (tempFile.path, volumes);
    } catch (_) {
      return (null, <double>[]);
    }
  }

  /// Switch GPT weights via api_v2.py.
  Future<bool> setGptWeights(String weightsPath) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_gptSovitsBaseUrl/set_gpt_weights?weights_path=${Uri.encodeComponent(weightsPath)}');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Switch SoVITS weights via api_v2.py.
  Future<bool> setSovitsWeights(String weightsPath) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('$_gptSovitsBaseUrl/set_sovits_weights?weights_path=${Uri.encodeComponent(weightsPath)}');
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  /// Scan reference audio directories under {projectPath}/ref_audios/.
  /// Returns list of {name, audioPath, promptText, promptLang}.
  static List<Map<String, String>> scanRefAudios(String projectPath) {
    final dir = Directory(p.join(projectPath, 'ref_audios'));
    if (!dir.existsSync()) return [];

    final results = <Map<String, String>>[];
    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      final metaFile = File(p.join(entry.path, 'metadata.json'));
      final wavFile = File(p.join(entry.path, 'reference.wav'));

      Map<String, dynamic> meta = {};
      if (metaFile.existsSync()) {
        try {
          meta = jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        } catch (_) {}
      }

      // Try to find any .wav file
      String? wavPath;
      if (wavFile.existsSync()) {
        wavPath = wavFile.path;
      } else {
        for (final f in entry.listSync()) {
          if (f is File && f.path.endsWith('.wav')) {
            wavPath = f.path;
            break;
          }
        }
      }

      if (wavPath != null) {
        results.add({
          'name': name,
          'audioPath': wavPath,
          'promptText': (meta['prompt_text'] as String?) ?? '',
          'promptLang': (meta['prompt_lang'] as String?) ?? 'zh',
        });
      }
    }
    return results;
  }

  /// Upload a reference audio to GPT-SoVITS ref_audios directory.
  /// Copies the source wav file and writes metadata.json.
  static Future<String?> uploadRefAudio({
    required String projectPath,
    required String voiceName,
    required String sourceWavPath,
    required String promptText,
    required String promptLang,
  }) async {
    final voiceDir = Directory(p.join(projectPath, 'ref_audios', voiceName));
    if (!voiceDir.existsSync()) {
      voiceDir.createSync(recursive: true);
    }

    // Copy audio file
    final destPath = p.join(voiceDir.path, 'reference.wav');
    try {
      File(sourceWavPath).copySync(destPath);
    } catch (e) {
      return 'Failed to copy audio: $e';
    }

    // Write metadata
    final metaPath = p.join(voiceDir.path, 'metadata.json');
    try {
      File(metaPath).writeAsStringSync(jsonEncode({
        'prompt_text': promptText,
        'prompt_lang': promptLang,
        'audio_file': 'reference.wav',
      }));
    } catch (e) {
      return 'Failed to write metadata: $e';
    }

    return null; // success
  }

  /// Delete a reference audio voice.
  static bool deleteRefAudio(String projectPath, String voiceName) {
    final voiceDir = Directory(p.join(projectPath, 'ref_audios', voiceName));
    if (!voiceDir.existsSync()) return false;
    try {
      voiceDir.deleteSync(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Scan for .ckpt and .pth weight files under GPT-SoVITS directories.
  /// Searches both pretrained_models/ (base models) and the versioned
  /// GPT_weights_v*/SoVITS_weights_v* directories at project root.
  static List<Map<String, String>> scanWeights(String projectPath) {
    final ckpts = <Map<String, String>>[];
    final pths = <Map<String, String>>[];

    void scan(Directory dir) {
      if (!dir.existsSync()) return;
      for (final entry in dir.listSync()) {
        if (entry is Directory) {
          scan(entry);
        } else if (entry is File) {
          if (entry.path.endsWith('.ckpt')) {
            ckpts.add({
              'name': p.basename(entry.path),
              'path': entry.path,
              'type': 'gpt',
            });
          } else if (entry.path.endsWith('.pth')) {
            // Skip vocoder.pth (not a SoVITS model)
            if (p.basename(entry.path) == 'vocoder.pth') continue;
            pths.add({
              'name': p.basename(entry.path),
              'path': entry.path,
              'type': 'sovits',
            });
          }
        }
      }
    }

    // 1. Pretrained models (base models under GPT_SoVITS/)
    final pretrainedDir = Directory(p.join(projectPath, 'GPT_SoVITS', 'pretrained_models'));
    scan(pretrainedDir);

    // 2. Fine-tuned GPT models (versioned weight dirs at project root)
    for (final subdir in [
      'GPT_weights', 'GPT_weights_v2', 'GPT_weights_v3',
      'GPT_weights_v4', 'GPT_weights_v2Pro', 'GPT_weights_v2ProPlus',
    ]) {
      scan(Directory(p.join(projectPath, subdir)));
    }

    // 3. Fine-tuned SoVITS models
    for (final subdir in [
      'SoVITS_weights', 'SoVITS_weights_v2', 'SoVITS_weights_v3',
      'SoVITS_weights_v4', 'SoVITS_weights_v2Pro', 'SoVITS_weights_v2ProPlus',
    ]) {
      scan(Directory(p.join(projectPath, subdir)));
    }

    return [...ckpts, ...pths];
  }
}
