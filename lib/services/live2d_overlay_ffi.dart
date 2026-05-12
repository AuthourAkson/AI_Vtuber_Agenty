import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

/// FFI bindings for the native Live2D overlay window (WebView2-based).
///
/// Provides a transparent, always-on-top, draggable window for VTube Studio-style
/// Live2D display. The window hosts a WebView2 control rendering the Live2D model
/// via the existing HTTP server (Live2DServer).
///
/// Usage:
///   final overlay = Live2DOverlayFfi.instance;
///   final id = overlay.create(url, x: 100, y: 100, width: 400, height: 600);
///   overlay.move(id, x: 200, y: 200);
///   overlay.destroy(id);

// C function signatures
typedef CreateOverlayNative = Int32 Function(
    Pointer<Utf16> url, Int32 x, Int32 y, Int32 width, Int32 height);
typedef CreateOverlayDart = int Function(
    Pointer<Utf16> url, int x, int y, int width, int height);

typedef DestroyOverlayNative = Void Function(Int32 windowId);
typedef DestroyOverlayDart = void Function(int windowId);

typedef MoveOverlayNative = Void Function(Int32 windowId, Int32 x, Int32 y);
typedef MoveOverlayDart = void Function(int windowId, int x, int y);

typedef ResizeOverlayNative = Void Function(Int32 windowId, Int32 width, Int32 height);
typedef ResizeOverlayDart = void Function(int windowId, int width, int height);

typedef NavigateOverlayNative = Void Function(Int32 windowId, Pointer<Utf16> url);
typedef NavigateOverlayDart = void Function(int windowId, Pointer<Utf16> url);

typedef ShowOverlayNative = Void Function(Int32 windowId, Int32 visible);
typedef ShowOverlayDart = void Function(int windowId, int visible);

typedef SetOverlayTopMostNative = Void Function(Int32 windowId, Int32 topmost);
typedef SetOverlayTopMostDart = void Function(int windowId, int topmost);

typedef IsOverlayAliveNative = Int32 Function(Int32 windowId);
typedef IsOverlayAliveDart = int Function(int windowId);

typedef GetOverlaySizeNative = Void Function(
    Int32 windowId, Pointer<Int32> width, Pointer<Int32> height);
typedef GetOverlaySizeDart = void Function(
    int windowId, Pointer<Int32> width, Pointer<Int32> height);

class Live2DOverlayFfi {
  static final Live2DOverlayFfi instance = Live2DOverlayFfi._();

  DynamicLibrary? _lib;
  bool _loaded = false;

  // Cached function pointers
  CreateOverlayDart? _createOverlay;
  DestroyOverlayDart? _destroyOverlay;
  MoveOverlayDart? _moveOverlay;
  ResizeOverlayDart? _resizeOverlay;
  NavigateOverlayDart? _navigateOverlay;
  ShowOverlayDart? _showOverlay;
  SetOverlayTopMostDart? _setOverlayTopMost;
  IsOverlayAliveDart? _isOverlayAlive;
  GetOverlaySizeDart? _getOverlaySize;

  Live2DOverlayFfi._();

  /// Try to load the native library.
  bool load() {
    if (_loaded) return _lib != null;
    if (!Platform.isWindows) {
      _loaded = true;
      return false;
    }

    try {
      // DynamicLibrary.process() looks up symbols in the current process
      // (main exe + all loaded DLLs) — most reliable for in-process FFI
      _lib = DynamicLibrary.process();
      
      // Verify symbols exist by trying to look up one function
      _lib!.lookup('CreateOverlay');
      
      _createOverlay = _lib!
          .lookupFunction<CreateOverlayNative, CreateOverlayDart>('CreateOverlay');
      _destroyOverlay = _lib!
          .lookupFunction<DestroyOverlayNative, DestroyOverlayDart>('DestroyOverlay');
      _moveOverlay = _lib!
          .lookupFunction<MoveOverlayNative, MoveOverlayDart>('MoveOverlay');
      _resizeOverlay = _lib!
          .lookupFunction<ResizeOverlayNative, ResizeOverlayDart>('ResizeOverlay');
      _navigateOverlay = _lib!
          .lookupFunction<NavigateOverlayNative, NavigateOverlayDart>('NavigateOverlay');
      _showOverlay = _lib!
          .lookupFunction<ShowOverlayNative, ShowOverlayDart>('ShowOverlay');
      _setOverlayTopMost = _lib!
          .lookupFunction<SetOverlayTopMostNative, SetOverlayTopMostDart>(
              'SetOverlayTopMost');
      _isOverlayAlive = _lib!
          .lookupFunction<IsOverlayAliveNative, IsOverlayAliveDart>('IsOverlayAlive');
      _getOverlaySize = _lib!
          .lookupFunction<GetOverlaySizeNative, GetOverlaySizeDart>('GetOverlaySize');

      _loaded = true;
      return true;
    } catch (e) {
      print('Live2DOverlayFfi: Failed to load native functions: $e');
      _loaded = true;
      return false;
    }
  }

  bool get isAvailable => load();

  /// Create a Live2D overlay window.
  /// [url] - The HTTP URL to load (e.g., http://localhost:48888/live2d_web/renderer.html)
  /// Returns window ID (>0) on success, 0 on failure.
  int create(String url, {
    int x = 100,
    int y = 100,
    int width = 400,
    int height = 600,
  }) {
    if (!isAvailable) return 0;
    final urlPtr = url.toNativeUtf16();
    try {
      return _createOverlay!(urlPtr, x, y, width, height);
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Destroy the overlay window.
  void destroy(int windowId) {
    if (!isAvailable) return;
    _destroyOverlay!(windowId);
  }

  /// Move the overlay to a new position.
  void move(int windowId, int x, int y) {
    if (!isAvailable) return;
    _moveOverlay!(windowId, x, y);
  }

  /// Resize the overlay.
  void resize(int windowId, int width, int height) {
    if (!isAvailable) return;
    _resizeOverlay!(windowId, width, height);
  }

  /// Navigate to a new URL in the overlay.
  void navigate(int windowId, String url) {
    if (!isAvailable) return;
    final urlPtr = url.toNativeUtf16();
    try {
      _navigateOverlay!(windowId, urlPtr);
    } finally {
      calloc.free(urlPtr);
    }
  }

  /// Show or hide the overlay.
  void show(int windowId, {bool visible = true}) {
    if (!isAvailable) return;
    _showOverlay!(windowId, visible ? 1 : 0);
  }

  /// Set always-on-top.
  void setTopMost(int windowId, bool topmost) {
    if (!isAvailable) return;
    _setOverlayTopMost!(windowId, topmost ? 1 : 0);
  }

  /// Check if the overlay window is alive.
  bool isAlive(int windowId) {
    if (!isAvailable) return false;
    return _isOverlayAlive!(windowId) != 0;
  }

  /// Get overlay size.
  ({int width, int height})? getSize(int windowId) {
    if (!isAvailable) return null;
    final w = calloc<Int32>();
    final h = calloc<Int32>();
    try {
      _getOverlaySize!(windowId, w, h);
      return (width: w.value, height: h.value);
    } finally {
      calloc.free(w);
      calloc.free(h);
    }
  }
}
