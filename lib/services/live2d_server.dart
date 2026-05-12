import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Global HTTP file server for Live2D assets and models.
/// Started once at app startup, serves from D:\AiVtuber_Agent_profile
class Live2DServer {
  static const _profileRoot = r'D:\AiVtuber_Agent_profile';
  static const _webDir = r'D:\AiVtuber_Agent_profile\live2d_web';
  static const port = 48888;

  static HttpServer? _server;
  static Process? _petProcess;

  static bool get isRunning => _server != null;
  static bool get petRunning => _petProcess != null;

  static Future<void> start() async {
    if (_server != null) return;

    // Copy web assets to disk
    await _copyAssets();

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen(_handleRequest);
    debugPrint('Live2D HTTP server on http://localhost:$port');
  }

  static void stop() {
    _server?.close(force: true);
    _server = null;
  }

  /// Register the Python pet subprocess for lifecycle management.
  static void setPetProcess(Process? process) {
    _petProcess = process;
  }

  /// Kill the pet subprocess if it's running.
  static void killPet() {
    if (_petProcess != null) {
      debugPrint('[Live2DServer] Killing pet process...');
      _petProcess!.kill(ProcessSignal.sigterm);
      _petProcess = null;
    }
  }

  static Future<void> _copyAssets() async {
    final dir = Directory(_webDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    final assets = [
      'assets/live2d/renderer.html',
      'assets/live2d/pet.html',
      'assets/live2d/pixi.min.js',
      'assets/live2d/live2dcubismcore.min.js',
      'assets/live2d/live2d.min.js',
      'assets/live2d/cubism4.min.js',
      'assets/live2d/qwebchannel.js',
    ];

    for (final assetPath in assets) {
      final dest = p.join(_webDir, p.basename(assetPath));
      try {
        final data = await rootBundle.load(assetPath);
        await File(dest).writeAsBytes(data.buffer.asUint8List());
      } catch (_) {}
    }
  }

  static Future<void> _handleRequest(HttpRequest request) async {
    try {
      var safePath = Uri.decodeComponent(request.uri.path);
      if (safePath.startsWith('/')) safePath = safePath.substring(1);

      // Health check endpoint — used by Python ParentAliveChecker
      if (safePath == '' || safePath == 'health') {
        request.response
          ..statusCode = 200
          ..headers.contentType = ContentType.json
          ..headers.set('Access-Control-Allow-Origin', '*')
          ..write('{"status":"ok"}');
        await request.response.close();
        return;
      }

      if (safePath.startsWith('/')) safePath = safePath.substring(1);
      if (safePath.contains('..')) {
        request.response.statusCode = 403;
        await request.response.close();
        return;
      }

      final file = File(p.join(_profileRoot, safePath));
      if (!await file.exists()) {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }

      final bytes = await file.readAsBytes();
      request.response
        ..statusCode = 200
        ..headers.contentType = _contentType(p.extension(file.path))
        ..headers.set('Access-Control-Allow-Origin', '*')
        ..add(bytes);
      await request.response.close();
    } catch (_) {
      request.response.statusCode = 500;
      await request.response.close();
    }
  }

  static ContentType _contentType(String ext) {
    switch (ext) {
      case '.html': return ContentType.html;
      case '.js': return ContentType.parse('application/javascript');
      case '.json': return ContentType.json;
      case '.png': return ContentType.parse('image/png');
      case '.jpg': case '.jpeg': return ContentType.parse('image/jpeg');
      default: return ContentType.binary;
    }
  }

  /// Convert disk path to localhost URL
  static String toModelUrl(String diskPath) {
    final root = _profileRoot.replaceAll('\\', '/');
    var relative = diskPath.replaceAll('\\', '/');
    if (relative.toLowerCase().startsWith(root.toLowerCase())) {
      relative = relative.substring(root.length);
      if (relative.startsWith('/')) relative = relative.substring(1);
    }
    final segs = relative.split('/').map((s) => Uri.encodeComponent(s)).join('/');
    return 'http://localhost:$port/$segs';
  }

  // Utility for debug print in non-Flutter context
  static void debugPrint(String msg) {
    // ignore: avoid_print
    print(msg);
  }
}
