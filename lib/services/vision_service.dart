import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'storage_service.dart';
import 'dart:io';

/// Vision service: capture screenshot and perform OCR.
/// Uses mss (via Python subprocess) for capture + easyocr for OCR.
class VisionService {
  final StorageService _storage;
  final _cacheDir = p.join(StorageService.profileDir, 'screenshots');

  VisionService(this._storage) {
    final dir = Directory(_cacheDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// Get list of available monitors.
  Future<List<Map<String, dynamic>>> getMonitors() async {
    try {
      final result = await _runPython('''
import json
import mss
with mss.mss() as sct:
    monitors = [
        {"index": i, "width": m["width"], "height": m["height"],
         "left": m["left"], "top": m["top"],
         "is_primary": (m["left"] == 0 and m["top"] == 0)}
        for i, m in enumerate(sct.monitors) if i > 0
    ]
    print(json.dumps(monitors))
''');
      if (result != null) {
        return (jsonDecode(result) as List).cast<Map<String, dynamic>>();
      }
    } catch (_) {}
    return [{'index': 1, 'width': 1920, 'height': 1080, 'left': 0, 'top': 0, 'is_primary': true}];
  }

  /// Capture screenshot and perform OCR.
  /// Returns {image: base64, caption: '', extracted_text: '', ocr_results: [...]}
  Future<Map<String, dynamic>> captureScreenshot({int monitorIndex = 1}) async {
    try {
      final screenshotPath = p.join(_cacheDir, 'screenshot_${DateTime.now().millisecondsSinceEpoch}.png');

      // Use Python mss to capture
      final result = await _runPython('''
import json
import base64
import io
import mss
from PIL import Image

with mss.mss() as sct:
    monitor = sct.monitors[$monitorIndex]
    screenshot = sct.grab(monitor)
    img = Image.frombytes("RGB", screenshot.size, screenshot.bgra, "raw", "BGRX")

    # Save to file
    img.save(r"$screenshotPath")

    # Base64 encode
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("utf-8")
    print(json.dumps({"image": b64}))
''');
      if (result != null) {
        final data = jsonDecode(result) as Map<String, dynamic>;
        final ocrText = await _performOCR(screenshotPath);
        return {
          'success': true,
          'image': data['image'],
          'caption': '',
          'extracted_text': ocrText,
          'ocr_count': ocrText.isNotEmpty ? 1 : 0,
          'ocr_results': ocrText.isNotEmpty
              ? [{'text': ocrText, 'confidence': 0.8, 'bbox': [0, 0, 100, 100]}]
              : <Map<String, dynamic>>[],
          'ocr_scale_factor': 0.5,
        };
      }
    } catch (e) {
      // Fallback: return error
    }
    return {
      'success': false,
      'image': '',
      'caption': '',
      'extracted_text': '',
      'ocr_count': 0,
      'ocr_results': <Map<String, dynamic>>[],
    };
  }

  Future<String> _performOCR(String imagePath) async {
    try {
      final result = await _runPython('''
import json
import easyocr
reader = easyocr.Reader(["ch_sim", "en"], gpu=False)
results = reader.readtext(r"$imagePath")
texts = [r[1] for r in results]
print(json.dumps("\\n".join(texts)))
''');
      if (result != null) {
        final text = jsonDecode(result) as String;
        return text;
      }
    } catch (_) {}
    return '';
  }

  Future<String?> _runPython(String code) async {
    try {
      final result = await Process.run(
        'python',
        ['-c', code],
        runInShell: true,
        stdoutEncoding: utf8,
      );
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
    } catch (_) {}
    return null;
  }
}
