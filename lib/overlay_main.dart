import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'services/live2d_server.dart';

/// Entry point for the Live2D desktop pet overlay window.
void overlayMain(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> config = {};
  if (args.isNotEmpty) {
    try { config = jsonDecode(args[0]); } catch (_) {}
  }
  final initModel = config['modelPath'] as String?;

  runApp(_OverlayApp(initialModel: initModel));
}

class _OverlayApp extends StatefulWidget {
  final String? initialModel;
  const _OverlayApp({this.initialModel});

  @override
  State<_OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<_OverlayApp> {
  InAppWebViewController? _controller;
  bool _ready = false;
  bool _loading = true;
  String? _currentModel;

  @override
  void initState() {
    super.initState();
    _setupIPC();
  }

  Future<void> _setupIPC() async {
    final controller = await WindowController.fromCurrentEngine();
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case 'loadModel':
          final path = call.arguments['path'] as String?;
          if (path != null) _loadModel(path);
          break;
        case 'setPosition':
          _callJS('setModelPosition(${call.arguments['x']}, ${call.arguments['y']})');
          break;
        case 'setScale':
          _callJS('setModelScale(${call.arguments['scale']})');
          break;
        case 'setMouthOpen':
          _callJS('setMouthOpen(${call.arguments['value']})');
          break;
        case 'setMouseTracking':
          _callJS('setMouseTracking(${call.arguments['enabled']})');
          break;
        case 'showChatDialog':
          final msgs = call.arguments['messages'];
          if (msgs != null) _callJS('showChatDialog(${jsonEncode(msgs)})');
          break;
        case 'hideChatDialog':
          _callJS('hideChatDialog()');
          break;
        case 'setExpression':
          final expr = call.arguments['expression'] as String? ?? '';
          _callJS("setExpression('${expr.replaceAll("'", "\\'")}')");
          break;
      }
      return null;
    });

    if (widget.initialModel != null) {
      _currentModel = widget.initialModel;
    }
  }

  void _callJS(String code) {
    if (_controller != null && _ready) {
      _controller!.evaluateJavascript(source: code);
    }
  }

  void _loadModel(String path) {
    if (path == _currentModel) return;
    _currentModel = path;
    final url = Live2DServer.toModelUrl(path);
    final safe = url.replaceAll("'", "\\'");
    _callJS("loadModel('$safe')");
    _callJS('setMouseTracking(true)');
  }

  @override
  Widget build(BuildContext context) {
    final htmlUrl = 'http://localhost:${Live2DServer.port}/live2d_web/renderer.html';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(htmlUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                transparentBackground: true,
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
                        setState(() => _loading = false);
                        if (_currentModel != null) _loadModel(_currentModel!);
                      }
                    } catch (_) {}
                  },
                );
              },
              onLoadStop: (ctrl, url) async {
                _ready = true;
                setState(() => _loading = false);
                await Future.delayed(const Duration(milliseconds: 500));
                if (_currentModel != null) _loadModel(_currentModel!);
                _callJS('setMouseTracking(true)');
              },
            ),
            if (_loading)
              const Center(
                child: CircularProgressIndicator(color: Color(0xFF4CAF50), strokeWidth: 2)),
          ],
        ),
      ),
    );
  }
}
