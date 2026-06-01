import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:window_manager/window_manager.dart';
import 'services/live2d_server.dart';

/// Character Pop Out window — separate window for OBS capture.
/// Supports Live2D and VRM with Chroma Key background.
/// Receives live settings via method channel from main window.
void characterPopoutMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> config = {};
  if (args.isNotEmpty) {
    try {
      config = jsonDecode(args[0]);
    } catch (_) {}
  }

  runApp(_PopoutApp(config: config));
}

class _PopoutApp extends StatefulWidget {
  final Map<String, dynamic> config;
  const _PopoutApp({required this.config});

  @override
  State<_PopoutApp> createState() => _PopoutAppState();
}

class _PopoutAppState extends State<_PopoutApp> {
  // Model settings — updated via method channel
  late String? _modelPath;
  late bool _use3D;
  late double _positionX;
  late double _positionY;
  late double _scale;
  late Color _backgroundColor;

  @override
  void initState() {
    super.initState();
    final c = widget.config;
    _modelPath = c['modelPath'] as String?;
    _use3D = (c['use3D'] as bool?) ?? false;
    _positionX = (c['positionX'] as num?)?.toDouble() ?? 50;
    _positionY = (c['positionY'] as num?)?.toDouble() ?? 50;
    _scale = (c['scale'] as num?)?.toDouble() ?? 0.08;
    final bgHex = c['bgColor'] as String?;
    _backgroundColor = bgHex != null
        ? Color(int.parse(bgHex, radix: 16) | 0xFF000000)
        : const Color(0xFF00FF00); // default green

    _setupIPC();
  }

  Future<void> _setupIPC() async {
    final controller = await WindowController.fromCurrentEngine();
    controller.setWindowMethodHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'updateModel':
          setState(() {
            _modelPath = call.arguments['modelPath'] as String?;
            _use3D = (call.arguments['use3D'] as bool?) ?? _use3D;
          });
          break;
        case 'updatePosition':
          setState(() {
            _positionX = (call.arguments['x'] as num?)?.toDouble() ?? _positionX;
            _positionY = (call.arguments['y'] as num?)?.toDouble() ?? _positionY;
          });
          break;
        case 'updateScale':
          setState(() {
            _scale = (call.arguments['scale'] as num?)?.toDouble() ?? _scale;
          });
          break;
        case 'updateBackground':
          final hex = call.arguments['color'] as String?;
          if (hex != null) {
            setState(() {
              _backgroundColor = Color(int.parse(hex, radix: 16) | 0xFF000000);
            });
          }
          break;
        case 'updateAll':
          setState(() {
            final a = call.arguments;
            if (a['modelPath'] != null) _modelPath = a['modelPath'] as String?;
            if (a['use3D'] != null) _use3D = a['use3D'] as bool;
            if (a['x'] != null) _positionX = (a['x'] as num).toDouble();
            if (a['y'] != null) _positionY = (a['y'] as num).toDouble();
            if (a['scale'] != null) _scale = (a['scale'] as num).toDouble();
            if (a['bgColor'] != null) {
              _backgroundColor = Color(
                  int.parse(a['bgColor'] as String, radix: 16) | 0xFF000000);
            }
          });
          break;
        case 'close':
          await windowManager.close();
          break;
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_modelPath == null || _modelPath!.isEmpty) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF00FF00),
          body: Center(
            child: Text('No model selected',
                style: TextStyle(color: Colors.white, fontSize: 18)),
          ),
        ),
      );
    }

    if (_use3D) {
      return _buildVRM();
    }
    return _buildLive2D();
  }

  Widget _buildVRM() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _backgroundColor,
        body: _VrmPopoutView(
          modelPath: _modelPath!,
          scale: _scale,
          bgColor: _backgroundColor,
        ),
      ),
    );
  }

  Widget _buildLive2D() {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: _backgroundColor,
        body: _Live2DPopoutView(
          modelPath: _modelPath!,
          positionX: _positionX,
          positionY: _positionY,
          scale: _scale,
          bgColor: _backgroundColor,
        ),
      ),
    );
  }
}

/// Lightweight Live2D renderer for pop-out (no Provider dependency)
class _Live2DPopoutView extends StatefulWidget {
  final String modelPath;
  final double positionX;
  final double positionY;
  final double scale;
  final Color bgColor;

  const _Live2DPopoutView({
    required this.modelPath,
    required this.positionX,
    required this.positionY,
    required this.scale,
    required this.bgColor,
  });

  @override
  State<_Live2DPopoutView> createState() => _Live2DPopoutViewState();
}

class _Live2DPopoutViewState extends State<_Live2DPopoutView> {
  InAppWebViewController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _syncBackground();
  }

  @override
  void didUpdateWidget(covariant _Live2DPopoutView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bgColor != widget.bgColor) _syncBackground();
    if (oldWidget.modelPath != widget.modelPath) _loadModel();
    if (oldWidget.positionX != widget.positionX ||
        oldWidget.positionY != widget.positionY) _syncPosition();
    if (oldWidget.scale != widget.scale) _syncScale();
  }

  void _syncBackground() {
    final hex = '#${(widget.bgColor.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase()}';
    _callJS("setBackgroundColor('$hex')");
  }

  void _syncPosition() {
    _callJS(
        'setModelPosition(${widget.positionX.toInt()}, ${widget.positionY.toInt()})');
  }

  void _syncScale() {
    _callJS('setModelScale(${widget.scale})');
  }

  void _loadModel() {
    final url = Live2DServer.toModelUrl(widget.modelPath);
    final safe = url.replaceAll("'", "\\'");
    _callJS("loadModel('$safe')");
  }

  void _callJS(String code) {
    if (_controller != null && _ready) {
      _controller!.evaluateJavascript(source: code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final htmlUrl =
        'http://localhost:${Live2DServer.port}/live2d_web/renderer.html';

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(htmlUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        allowContentAccess: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (ctrl) {
        _controller = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'onLive2DEvent',
          callback: (args) {
            if (args.isEmpty) return;
            try {
              final event = jsonDecode(args[0] as String);
              if (event['type'] == 'rendererReady') {
                _ready = true;
                _loadModel();
                Future.delayed(const Duration(milliseconds: 800), () {
                  _syncBackground();
                  _syncPosition();
                  _syncScale();
                });
              }
            } catch (_) {}
          },
        );
      },
      onLoadStop: (ctrl, url) {
        _ready = true;
        Future.delayed(const Duration(milliseconds: 500), () {
          _loadModel();
          Future.delayed(const Duration(milliseconds: 600), () {
            _syncBackground();
            _syncPosition();
            _syncScale();
          });
        });
      },
    );
  }
}

/// Lightweight VRM renderer for pop-out (no Provider dependency)
class _VrmPopoutView extends StatefulWidget {
  final String modelPath;
  final double scale;
  final Color bgColor;

  const _VrmPopoutView({
    required this.modelPath,
    required this.scale,
    required this.bgColor,
  });

  @override
  State<_VrmPopoutView> createState() => _VrmPopoutViewState();
}

class _VrmPopoutViewState extends State<_VrmPopoutView> {
  InAppWebViewController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _syncBackground();
  }

  @override
  void didUpdateWidget(covariant _VrmPopoutView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bgColor != widget.bgColor) _syncBackground();
    if (oldWidget.modelPath != widget.modelPath) _loadModel();
    if (oldWidget.scale != widget.scale) _syncScale();
  }

  void _syncBackground() {
    final hex = '#${(widget.bgColor.value & 0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0')
        .toUpperCase()}';
    _callJS("vrmSetBackground('$hex')");
    // Also sync body background for full coverage
    _callJS(
        "document.body.style.backgroundColor = '$hex'; document.body.style.setProperty('background-color', '$hex', 'important')");
  }

  void _syncScale() {
    _callJS('window.setVRMScale && window.setVRMScale(${widget.scale})');
  }

  void _loadModel() {
    final url = Live2DServer.toModelUrl(widget.modelPath);
    final safe = url.replaceAll("'", "\\'");
    _callJS("loadVRM('$safe')");
  }

  void _callJS(String code) {
    if (_controller != null && _ready) {
      _controller!.evaluateJavascript(source: code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final htmlUrl =
        'http://localhost:${Live2DServer.port}/vrm_web/vrm_renderer.html';

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(htmlUrl)),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: false,
        allowContentAccess: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (ctrl) {
        _controller = ctrl;
        ctrl.addJavaScriptHandler(
          handlerName: 'onVRMEvent',
          callback: (args) {
            if (args.isEmpty) return;
            try {
              final event = jsonDecode(args[0] as String);
              if (event['type'] == 'rendererReady') {
                _ready = true;
                _loadModel();
                Future.delayed(const Duration(milliseconds: 1500), () {
                  _syncBackground();
                  _syncScale();
                });
              }
            } catch (_) {}
          },
        );
      },
      onLoadStop: (ctrl, url) {
        _ready = true;
        Future.delayed(const Duration(milliseconds: 800), () {
          _loadModel();
          Future.delayed(const Duration(milliseconds: 1000), () {
            _syncBackground();
            _syncScale();
          });
        });
      },
    );
  }
}
