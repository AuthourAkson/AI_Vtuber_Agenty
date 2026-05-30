import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as p;
import '../app.dart';
import '../services/live2d_server.dart';

class Live2DEvent {
  final String type;
  final Map<String, dynamic> data;
  Live2DEvent({required this.type, required this.data});

  factory Live2DEvent.fromJson(String json) {
    final decoded = jsonDecode(json) as Map<String, dynamic>;
    return Live2DEvent(
      type: decoded['type'] as String? ?? '',
      data: decoded['data'] as Map<String, dynamic>? ?? {},
    );
  }
}

class Live2DView extends StatefulWidget {
  final String? modelPath;
  final double positionX;
  final double positionY;
  final double scale;
  final void Function(Live2DEvent)? onEvent;
  final bool interactive;
  final Color? backgroundColor;

  const Live2DView({
    super.key,
    this.modelPath,
    this.positionX = 46,
    this.positionY = 51,
    this.scale = 0.16,
    this.onEvent,
    this.interactive = true,
    this.backgroundColor,
  });

  @override
  State<Live2DView> createState() => Live2DViewState();
}

class Live2DViewState extends State<Live2DView> {
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _loading = true;
  String? _loadedModelPath;

  static const _port = Live2DServer.port;
  String _htmlUrl = 'http://localhost:${Live2DServer.port}/live2d_web/renderer.html';

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  void didUpdateWidget(Live2DView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only reload model if path actually changed
    if (widget.modelPath != oldWidget.modelPath && _ready) {
      _loadModel();
    }
    // Position/scale: only update if already loaded
    if (_loadedModelPath != null &&
        (widget.positionX != oldWidget.positionX ||
         widget.positionY != oldWidget.positionY)) {
      _updatePosition();
    }
    if (_loadedModelPath != null && widget.scale != oldWidget.scale) {
      _updateScale();
    }
    if (widget.backgroundColor != oldWidget.backgroundColor) {
      _syncBackground();
    }
  }

  Future<void> _syncBackground() async {
    if (_controller == null || !_ready) return;
    final color = widget.backgroundColor;
    if (color != null) {
      final hex = '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
      await _controller!.evaluateJavascript(
        source: "setBackground('$hex')"
      );
    } else {
      await _controller!.evaluateJavascript(
        source: "setBackground('transparent')"
      );
    }
  }

  Future<void> _loadModel() async {
    if (_controller == null || !_ready) return;
    final path = widget.modelPath;
    if (path == null || path.isEmpty) {
      await _controller!.evaluateJavascript(source: 'loadModel(null)');
      _loadedModelPath = null;
      return;
    }
    // Avoid reloading the same model
    if (path == _loadedModelPath) return;

      final modelUrl = Live2DServer.toModelUrl(path);
      debugPrint('Loading model: $modelUrl');
    // Escape backslashes and quotes for JS string
    final escapedUrl = modelUrl.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
    await _controller!.evaluateJavascript(
      source: "loadModel('$escapedUrl', ${widget.scale}, ${widget.positionX}, ${widget.positionY})"
    );
    _loadedModelPath = path;
  }

  Future<void> _updatePosition() async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: 'setModelPosition(${widget.positionX}, ${widget.positionY})'
    );
  }

  Future<void> _updateScale() async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: 'setModelScale(${widget.scale})'
    );
  }

  Future<void> showChatDialog(List<Map<String, dynamic>> messages) async {
    if (_controller == null) return;
    final json = jsonEncode(messages);
    await _controller!.evaluateJavascript(source: 'showChatDialog($json)');
  }

  Future<void> hideChatDialog() async {
    if (_controller == null) return;
    await _controller!.evaluateJavascript(source: 'hideChatDialog()');
  }

  Future<void> setMouthOpen(double value) async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: 'setMouthOpen(${value.clamp(0.0, 1.0)})'
    );
  }

  /// Enable/disable eye tracking (mouse follow)
  Future<void> setMouseTracking(bool enabled) async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: 'setMouseTracking($enabled)'
    );
  }

  /// Set background color for chroma key capture (e.g. '#00FF00')
  Future<void> setChromaBackground(String hexColor) async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: "setBackground('$hexColor')"
    );
  }

  Future<void> setExpression(String name) async {
    if (_controller == null || !_ready) return;
    final escaped = name.replaceAll("'", "\\'");
    await _controller!.evaluateJavascript(
      source: "setExpression('$escaped')"
    );
  }

  /// Set eye target from global mouse tracking (Dart→Win32→JS)
  Future<void> setEyeTarget(double ox, double oy) async {
    if (_controller == null || !_ready) return;
    await _controller!.evaluateJavascript(
      source: 'setEyeTarget($ox, $oy)'
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background color — WebView2 on Windows can't do true transparency
        Container(color: widget.backgroundColor ?? Colors.transparent),
        InAppWebView(
            key: ValueKey('live2d_webview'), // Stable key to prevent rebuild
            initialUrlRequest: URLRequest(url: WebUri(_htmlUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              transparentBackground: true,
              allowContentAccess: true,
              mediaPlaybackRequiresUserGesture: false,
              javaScriptCanOpenWindowsAutomatically: false,
            ),
            onWebViewCreated: (controller) {
              _controller = controller;
              controller.addJavaScriptHandler(
                handlerName: 'onLive2DEvent',
                callback: (args) {
                  if (args.isNotEmpty) {
                    try {
                      final event = Live2DEvent.fromJson(args[0] as String);
                      _handleEvent(event);
                    } catch (e) {
                      debugPrint('Live2D event parse error: $e');
                    }
                  }
                },
              );
            },
            onLoadStop: (controller, url) async {
              _ready = true;
              setState(() => _loading = false);
              _syncBackground();
              if (widget.modelPath != null && widget.modelPath!.isNotEmpty) {
                await Future.delayed(const Duration(milliseconds: 800));
                _loadModel();
              }
            },
            onConsoleMessage: (controller, msg) {
              debugPrint('Live2D JS: ${msg.message}');
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
                      color: ShadTheme.of(context).primary, strokeWidth: 2),
                    SizedBox(height: 8),
                    Text('Initializing Live2D...',
                      style: TextStyle(color: ShadTheme.of(context).mutedForeground, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
    );
  }

  void _handleEvent(Live2DEvent event) {
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
      case 'modelUnloaded':
        _loadedModelPath = null;
        break;
      case 'chatDialogClosed':
        break;
    }
    widget.onEvent?.call(event);
  }
}
