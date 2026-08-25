import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' show Color;
import 'live2d_overlay_ffi.dart';
import 'live2d_server.dart';

/// 角色透明Overlay窗口服务
///
/// 底层是原生C++窗口(WebView2)，支持:
/// - 透明背景 (WS_EX_NOREDIRECTIONBITMAP + DWM per-pixel alpha)
/// - 始终置顶 (WS_EX_TOPMOST)
/// - 鼠标穿透 (默认启用, 按F2切换)
/// - 左键拖拽移动
/// - ESC关闭
/// - Ctrl+Shift+Q强制关闭
/// - Ctrl+Shift+F2切换穿透
///
/// OBS/直播姬 → 窗口捕获 → 选择"AI VTuber - Overlay"窗口 → 放置到任意位置
class OverlayService {
  static final OverlayService instance = OverlayService._();
  OverlayService._();

  int _windowId = 0;
  bool get isRunning => _windowId > 0 && _ffi.isAlive(_windowId);

  final Live2DOverlayFfi _ffi = Live2DOverlayFfi.instance;

  /// 启动Live2D角色透明Overlay
  /// [modelPath] 磁盘路径, 如 D:\\AiVtuber_Agent_profile\\models\\live2d\\xxx
  /// [scale] 缩放比例, 默认0.15
  Future<bool> startLive2D({
    required String modelPath,
    double scale = 0.15,
    int x = 200,
    int y = 100,
    int width = 500,
    int height = 600,
  }) async {
    if (!_ffi.isAvailable) {
      print('[OverlayService] Native overlay FFI not available');
      return false;
    }

    // 关闭已有窗口
    if (_windowId > 0) await stop();

    // 构建URL: renderer.html + model参数
    final modelUrl = Live2DServer.toModelUrl(modelPath);
    final encodedModel = Uri.encodeComponent(modelUrl);
    final url =
        'http://localhost:${Live2DServer.port}'
        '/live2d_web/renderer.html'
        '?model=$encodedModel'
        '&scale=$scale'
        '&x=50&y=50';

    _windowId = _ffi.create(url, x: x, y: y, width: width, height: height);
    if (_windowId > 0) {
      print('[OverlayService] Live2D overlay created (id=$_windowId)');
      return true;
    }
    print('[OverlayService] Failed to create overlay');
    return false;
  }

  /// 启动VRM 3D角色透明Overlay
  /// TODO: vrm_renderer.html目前不支持query param加载，需要用JS bridge
  Future<bool> startVRM({
    required String modelPath,
    double scale = 0.8,
    int x = 200,
    int y = 100,
    int width = 500,
    int height = 600,
  }) async {
    if (!_ffi.isAvailable) return false;
    if (_windowId > 0) await stop();

    final vrmUrl = Live2DServer.toModelUrl(modelPath);
    final encodedModel = Uri.encodeComponent(vrmUrl);
    final url =
        'http://localhost:${Live2DServer.port}'
        '/vrm_web/vrm_renderer.html'
        '?model=$encodedModel'
        '&scale=$scale';

    _windowId = _ffi.create(url, x: x, y: y, width: width, height: height);
    return _windowId > 0;
  }

  /// 移动窗口
  void move(int x, int y) {
    if (_windowId > 0) _ffi.move(_windowId, x, y);
  }

  /// 调整窗口大小
  void resize(int w, int h) {
    if (_windowId > 0) _ffi.resize(_windowId, w, h);
  }

  /// 显示/隐藏
  void setVisible(bool visible) {
    if (_windowId > 0) _ffi.show(_windowId, visible: visible);
  }

  /// 设置鼠标穿透
  void setClickThrough(bool enable) {
    if (_windowId > 0) _ffi.setClickThrough(_windowId, enable);
  }

  /// 执行JavaScript（如切换鼠标追踪）
  void executeScript(String script) {
    if (_windowId > 0) _ffi.executeScript(_windowId, script);
  }

  /// 设置鼠标追踪（Live2D眼睛跟随鼠标）
  void setMouseTracking(bool enabled) {
    executeScript('setMouseTracking($enabled)');
  }

  /// 关闭
  Future<void> stop() async {
    if (_windowId > 0) {
      _ffi.destroy(_windowId);
      _windowId = 0;
      print('[OverlayService] Overlay destroyed');
    }
  }

  // ═══ Character Pop Out (for OBS capture) ═══

  int _popoutId = 0;
  bool _popoutIs3D = false; // true when pop-out is VRM, false for Live2D

  /// Whether a Character Pop Out window is currently open.
  bool get isPopoutRunning => _popoutId > 0 && _ffi.isAlive(_popoutId);

  /// Whether the current pop-out is a VRM (3D) window.
  bool get isPopout3D => _popoutIs3D;

  /// Open a Character Pop Out window — normal window with Chroma Key bg.
  /// [use3D] — true for VRM, false for Live2D.
  /// [modelPath] — disk path to the model file.
  /// [backgroundColor] — Chroma Key color (e.g. green/magenta).
  Future<bool> startCharacterPopout({
    required bool use3D,
    required String modelPath,
    Color? backgroundColor,
    double scale = 0.08,
    int x = 100,
    int y = 100,
    int width = 500,
    int height = 600,
  }) async {
    if (!_ffi.isAvailable) {
      print('[OverlayService] Native overlay FFI not available');
      return false;
    }

    // Close existing pop-out
    if (_popoutId > 0) await stopPopout();

    final modelUrl = Live2DServer.toModelUrl(modelPath);
    final bgHex = backgroundColor != null
        ? (backgroundColor.value & 0xFFFFFF)
              .toRadixString(16)
              .padLeft(6, '0')
              .toUpperCase()
        : null;

    String url;
    if (use3D) {
      url = 'http://localhost:${Live2DServer.port}/vrm_web/vrm_renderer.html';
    } else {
      final encodedModel = Uri.encodeComponent(modelUrl);
      url =
          'http://localhost:${Live2DServer.port}'
          '/live2d_web/renderer.html'
          '?model=$encodedModel'
          '&scale=$scale'
          '&x=50&y=50'
          '${bgHex != null ? "&bg=$bgHex" : ""}';
    }

    _popoutId = _ffi.create(url, x: x, y: y, width: width, height: height);
    _popoutIs3D = use3D;
    if (_popoutId > 0) {
      _ffi.setClickThrough(_popoutId, false);
      _ffi.setTopMost(_popoutId, false);

      // VRM: load model + set background + sync mouthScale after scene initializes
      if (use3D) {
        final safeModelUrl = modelUrl.replaceAll("'", "\\'");
        final scale = _mouthScale; // capture current value
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (_popoutId > 0) {
            if (bgHex != null) {
              executePopoutScript("vrmSetBackground('#$bgHex');");
            }
            executePopoutScript("vrmLoadModel('$safeModelUrl');");
            // Sync mouth scale after model loads
            Future.delayed(const Duration(milliseconds: 2000), () {
              if (_popoutId > 0) {
                executePopoutScript('vrmSetMouthScale($scale);');
              }
            });
          }
        });
      }

      print('[OverlayService] Character pop-out created (id=$_popoutId)');
      return true;
    }
    print('[OverlayService] Failed to create character pop-out');
    return false;
  }

  /// Send JavaScript to the pop-out window (for live sync).
  void executePopoutScript(String script) {
    if (_popoutId > 0) _ffi.executeScript(_popoutId, script);
  }

  /// Update pop-out background color.
  void setPopoutBackground(Color color) {
    final hex =
        '#${(color.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    executePopoutScript("setBackground('$hex');");
    executePopoutScript(
      "vrmSetBackground('$hex');",
    ); // VRM too (no-op if not VRM)
  }

  /// Close the Character Pop Out.
  Future<void> stopPopout() async {
    _stopMouthAnimation();
    if (_popoutId > 0) {
      _ffi.destroy(_popoutId);
      _popoutId = 0;
      _popoutIs3D = false;
      print('[OverlayService] Pop-out destroyed');
    }
  }

  // ═══ Mouth sync animation ═══

  Timer? _mouthTimer;
  int _mouthIndex = 0;
  List<double> _mouthVolumes = const [];

  /// Dynamic mouth scale multiplier.
  /// Live2D: amplifies precomputed RMS volumes in the animation timer.
  /// VRM: pushed to renderer as speakAnimation.weight via vrmSetMouthScale.
  /// Adjustable at runtime from the Character page slider.
  double _mouthScale = 3.0;
  double get mouthScale => _mouthScale;
  set mouthScale(double v) {
    _mouthScale = v;
    // Push to VRM pop-out immediately for real-time feedback
    if (isPopoutRunning && _popoutIs3D) {
      executePopoutScript('vrmSetMouthScale($v);');
    }
  }

  /// Whether a mouth animation is currently running.
  bool get isMouthAnimating => _mouthTimer != null;

  /// Start mouth animation driven by real audio volume data.
  /// [volumes] — precomputed RMS values [0.0, 1.0] at ~50ms intervals.
  /// Pass empty list for fallback sine-wave animation.
  /// NOTE: VRM pop-out uses its own Web Audio API analysis (vrmPlayAudio),
  /// so this timer is only used for Live2D.
  void startMouthAnimation([List<double> volumes = const []]) {
    _stopMouthAnimation(); // cancel any previous animation
    print(
      '[OverlayService] startMouthAnimation volumes=${volumes.length} '
      'popout=$isPopoutRunning is3D=$_popoutIs3D',
    );
    if (!isPopoutRunning) return;

    if (volumes.isEmpty) {
      // Fallback: simple sine wave (no audio analysis available)
      _startSineWaveAnimation();
      return;
    }

    _mouthVolumes = volumes;
    _mouthIndex = 0;

    // 50ms intervals = 20 FPS (matches AUAK_Live2D_Desktop_AI chunk_ms=50)
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!isPopoutRunning) {
        _stopMouthAnimation();
        return;
      }
      if (_mouthIndex >= _mouthVolumes.length) {
        _stopMouthAnimation(); // sequence complete
        return;
      }

      final rawValue = _mouthVolumes[_mouthIndex];
      _mouthIndex++;
      final value = (rawValue * mouthScale).clamp(0.0, 1.0);

      if (_popoutIs3D) {
        executePopoutScript('vrmSetVolume($value);');
      } else {
        executePopoutScript('setMouthOpen($value);');
      }
    });
  }

  /// Drive the VRM pop-out with a precomputed A/I/U/E/O viseme timeline.
  /// This uses Flutter's own timer and does not depend on Web Audio inside the
  /// pop-out, which is more reliable across WebView2 versions.
  void startVisemeTimelineAnimation(List<Map<String, dynamic>> frames) {
    _stopMouthAnimation();
    print(
      '[OverlayService] startVisemeTimelineAnimation frames=${frames.length} '
      'popout=$isPopoutRunning is3D=$_popoutIs3D',
    );
    if (!isPopoutRunning || !_popoutIs3D || frames.isEmpty) return;

    final start = DateTime.now();
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!isPopoutRunning) {
        _stopMouthAnimation();
        return;
      }

      final elapsed = DateTime.now().difference(start).inMilliseconds / 1000.0;
      Map<String, dynamic>? current;
      for (final f in frames) {
        final ft = (f['t'] as num?)?.toDouble() ?? 0;
        if (ft >= elapsed) {
          current = f;
          break;
        }
      }

      if (current == null) {
        executePopoutScript('vrmSetVisemeValues(0,0,0,0,0);');
        _stopMouthAnimation();
        return;
      }

      final a = ((current['a'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      final i = ((current['i'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      final u = ((current['u'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      final e = ((current['e'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      final o = ((current['o'] as num?)?.toDouble() ?? 0).clamp(0.0, 1.0);
      executePopoutScript('vrmSetVisemeValues($a,$i,$u,$e,$o);');
    });
  }

  /// Fallback sine-wave animation when no audio volume data is available.
  void _startSineWaveAnimation() {
    final random = Random();
    double phase = 0;

    _mouthTimer = Timer.periodic(const Duration(milliseconds: 80), (timer) {
      if (!isPopoutRunning) {
        _stopMouthAnimation();
        return;
      }
      phase += 0.2 + random.nextDouble() * 0.4;
      final value =
          ((sin(phase) * 0.5 + 0.5) * 0.85 + random.nextDouble() * 0.15).clamp(
            0.0,
            1.0,
          );

      if (_popoutIs3D) {
        executePopoutScript('vrmSetVolume($value);');
      } else {
        executePopoutScript('setMouthOpen($value);');
      }
    });
  }

  /// Stop mouth animation and reset mouth to closed.
  void _stopMouthAnimation() {
    _mouthTimer?.cancel();
    _mouthTimer = null;
    _mouthVolumes = const [];
    _mouthIndex = 0;
    // Reset mouth to closed
    if (isPopoutRunning) {
      if (_popoutIs3D) {
        executePopoutScript('vrmSetVolume(0);');
        executePopoutScript('vrmSetVisemeValues(0,0,0,0,0);');
      } else {
        executePopoutScript('setMouthOpen(0);');
      }
    }
  }

  /// Public stop that can be called from outside (e.g., when TTS finishes).
  void stopMouthAnimation() => _stopMouthAnimation();

  /// Push TTS audio URL to the pop-out renderer for real-time analysis.
  /// VRM: injects vrmPlayAudio(url) → Web Audio API → currentVolume → speak anim.
  /// Live2D: no-op (Live2D uses the Dart volume timer instead).
  void pushAudioToPopout(
    String audioUrl, [
    List<Map<String, dynamic>>? visemeFrames,
  ]) {
    if (!isPopoutRunning) return;
    if (_popoutIs3D) {
      final safeUrl = audioUrl.replaceAll('\\', '\\').replaceAll("'", "\'");
      if (visemeFrames != null && visemeFrames.isNotEmpty) {
        final framesJson = jsonEncode(
          visemeFrames,
        ).replaceAll('\\', '\\').replaceAll("'", "\'");
        executePopoutScript("vrmPlayAudio('$safeUrl', '$framesJson');");
      } else {
        executePopoutScript("vrmPlayAudio('$safeUrl');");
      }
    }
  }
}
