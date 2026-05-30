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
  /// [modelPath] 磁盘路径, 如 D:\AiVtuber_Agent_profile\models\live2d\xxx
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
    final url = 'http://localhost:${Live2DServer.port}'
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
    final url = 'http://localhost:${Live2DServer.port}'
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
}
