import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../app.dart';
import '../services/live2d_server.dart';

/// Event from the VRM renderer JavaScript side.
class VrmEvent {
  final String type;
  final Map<String, dynamic> data;
  VrmEvent({required this.type, required this.data});

  factory VrmEvent.fromJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return VrmEvent(
      type: decoded['type'] as String? ?? '',
      data: (decoded['data'] as Map<String, dynamic>?) ?? {},
    );
  }
}

/// Flutter WebView-based VRM 3D character renderer.
/// Mirrors LocalAIVtuber2's VRM3dCanvas component.
/// Uses the same Live2DServer HTTP server to serve the VRM renderer HTML + model files.
class VrmView extends StatefulWidget {
  final String? modelPath;
  final double positionX;
  final double positionY;
  final double scale;
  final void Function(VrmEvent)? onEvent;
  final Color? backgroundColor;

  const VrmView({
    super.key,
    this.modelPath,
    this.positionX = 0,
    this.positionY = 0,
    this.scale = 1.0,
    this.onEvent,
    this.backgroundColor,
  });

  @override
  State<VrmView> createState() => _VrmViewState();
}

class _VrmViewState extends State<VrmView> {
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _loading = true;
  String? _loadedModelPath;
  double _currentVolume = 0;

  static const _port = Live2DServer.port;
  String get _htmlUrl => 'http://localhost:$_port/vrm_web/vrm_renderer.html';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(VrmView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.modelPath != oldWidget.modelPath && _ready) {
      _loadModel();
    }
    if (widget.backgroundColor != oldWidget.backgroundColor && _ready) {
      _syncBackground();
    }
  }

  /// Load the VRM model in the WebView
  Future<void> _loadModel() async {
    if (_controller == null || !_ready) return;
    final path = widget.modelPath;
    if (path == null || path.isEmpty) return;
    if (path == _loadedModelPath) return;

    final modelUrl = Live2DServer.toModelUrl(path);
    debugPrint('[VrmView] Loading model: $modelUrl');

    final escapedUrl = modelUrl
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");
    await _controller!.evaluateJavascript(
      source: "vrmLoadModel('$escapedUrl')"
    );
    _loadedModelPath = path;
  }

  /// Sync background color to the WebView scene
  Future<void> _syncBackground() async {
    if (_controller == null || !_ready) return;
    final color = widget.backgroundColor ?? ShadTheme.of(context).background;
    final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
    await _controller!.evaluateJavascript(
      source: "vrmSetBackground('$hex')"
    );
  }

  /// Set speak volume for mouth animation (0.0 ~ 1.0)
  Future<void> setSpeakVolume(double volume) async {
    if (_controller == null || !_ready) return;
    if ((volume - _currentVolume).abs() < 0.01 && volume < 0.01) return;
    _currentVolume = volume;
    await _controller!.evaluateJavascript(
      source: 'vrmSetVolume($volume)'
    );
  }

  /// Reset camera to default position
  Future<void> resetCamera() async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(source: 'vrmResetCamera()');
  }

  /// Play a named VRM animation (.vrma file)
  Future<void> playAnimation(String animationUrl, {String type = 'gesture'}) async {
    if (_controller == null || !_ready) return;
    final escaped = animationUrl
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'");
    await _controller!.evaluateJavascript(
      source: "vrmPlayAnimation('$escaped', '$type')"
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background color Container (WebView2 on Windows can't do true transparency)
        Container(color: widget.backgroundColor ?? Colors.transparent),
        InAppWebView(
            key: const ValueKey('vrm_webview'),
            initialUrlRequest: URLRequest(url: WebUri(_htmlUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              allowContentAccess: true,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptCanOpenWindowsAutomatically: false,
              // Allow loading Three.js + VRM from CDN
              allowUniversalAccessFromFileURLs: true,
              // Allow CORS for model file loading
              disableDefaultErrorPage: true,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onVrmEvent',
                callback: (args) {
                  if (args.isNotEmpty) {
                    try {
                      final event = VrmEvent.fromJson(args[0] as String);
                      _handleEvent(event);
                    } catch (e) {
                      debugPrint('[VrmView] Event parse error: $e');
                    }
                  }
                },
              );
            },
            onLoadStop: (controller, url) async {
              // Poll window.__vrmReady until JS module finishes loading
              _pollVrmReady(controller);
            },
            onConsoleMessage: (controller, msg) {
              debugPrint('[VRM JS] ${msg.message}');
            },
            onReceivedError: (controller, request, error) {
              debugPrint('[VrmView] WebView error: ${error.description}');
            },
          ),
          if (_loading)
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: ShadTheme.of(context).primary,
                      strokeWidth: 2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Initializing VRM...',
                      style: TextStyle(
                        color: ShadTheme.of(context).mutedForeground,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
    );
  }

  /// Poll window.__vrmReady every 500ms until true, then load model.
  Future<void> _pollVrmReady(InAppWebViewController controller) async {
    for (int i = 0; i < 120; i++) {
      // max 60 seconds
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted || !_loading) return;
      try {
        final result = await controller.evaluateJavascript(
          source: 'window.__vrmReady',
        );
        if (result == true) {
          debugPrint('[VrmView] VRM engine ready (polled)');
          setState(() => _loading = false);
          _ready = true;
          _syncBackground();
          if (widget.modelPath != null && widget.modelPath!.isNotEmpty) {
            _loadModel();
          }
          return;
        }
      } catch (_) {
        // evaluateJavascript may fail if page not fully loaded
      }
    }
    // Timeout after 60s — force ready anyway
    if (mounted && _loading) {
      debugPrint('[VrmView] VRM polling timeout (60s) — forcing ready');
      setState(() => _loading = false);
      _ready = true;
    }
  }

  void _handleEvent(VrmEvent event) {
    switch (event.type) {
      case 'rendererReady':
        _ready = true;
        setState(() => _loading = false);
        _syncBackground();
        if (widget.modelPath != null && widget.modelPath!.isNotEmpty) {
          _loadModel();
        }
        break;
      case 'modelLoaded':
        _loadedModelPath = event.data['path'] as String?;
        break;
      case 'modelError':
        debugPrint('[VrmView] Model error: ${event.data['error']}');
        _loading = false;
        setState(() {});
        break;
      case 'initError':
        debugPrint('[VrmView] Init error: ${event.data['error']}');
        _loading = false;
        setState(() {});
        break;
    }
    widget.onEvent?.call(event);
  }
}
