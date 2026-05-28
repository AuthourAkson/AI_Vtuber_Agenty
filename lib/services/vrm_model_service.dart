import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages VRM 3D model files on disk.
/// Models stored at D:\\AiVtuber_Agent_profile\\models\\vrm\\
/// Mirrors the LAV2 CharacterManager VRM handling.
class VrmModelService {
  static const _profileDir = r'D:\AiVtuber_Agent_profile';
  static const _modelsDir = 'models';
  static const _vrmDir = 'vrm';

  String get modelsPath => p.join(_profileDir, _modelsDir, _vrmDir);

  VrmModelService() {
    _ensureDirs();
  }

  void _ensureDirs() {
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// List available VRM models (.vrm files in models/vrm/)
  /// Returns list of {name, path} — path is the full disk path to the .vrm file.
  List<Map<String, String>> listModels() {
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) return [];

    final models = <Map<String, String>>[];
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vrm')) {
        models.add({
          'name': p.basenameWithoutExtension(entity.path)
            .replaceAll('_', ' ')
            .replaceAll('-', ' '),
          'path': entity.path,
        });
      }
    }
    return models;
  }

  /// Import a VRM model from a file path (copy to profile)
  Future<String?> importModel(String sourcePath) async {
    final src = File(sourcePath);
    if (!src.existsSync()) return null;
    if (!sourcePath.toLowerCase().endsWith('.vrm')) return null;

    final fileName = p.basename(sourcePath);
    final destPath = p.join(modelsPath, fileName);

    try {
      await src.copy(destPath);
      return destPath;
    } catch (e) {
      return null;
    }
  }

  /// Delete a VRM model by name (the display name matching the filename)
  bool deleteModel(String modelName) {
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) return false;

    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vrm')) {
        final name = p.basenameWithoutExtension(entity.path)
          .replaceAll('_', ' ')
          .replaceAll('-', ' ');
        if (name == modelName) {
          entity.deleteSync();
          return true;
        }
      }
    }
    return false;
  }

  /// Get the full disk path for a model by its display name or filename
  String? findModelPath(String nameOrPath) {
    // If it's already a valid path
    if (File(nameOrPath).existsSync()) return nameOrPath;

    // Search by name
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) return null;

    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vrm')) {
        final name = p.basenameWithoutExtension(entity.path)
          .replaceAll('_', ' ')
          .replaceAll('-', ' ');
        if (name == nameOrPath ||
            entity.path == nameOrPath ||
            p.basename(entity.path) == nameOrPath) {
          return entity.path;
        }
      }
    }
    return null;
  }

  /// Copy a default VRM model from LAV2's models directory
  Future<String?> copyDefaultModels() async {
    final srcDir = Directory(r'D:\LocalAIVtuber2\backend\services\Character\VRM3D\models');
    if (!srcDir.existsSync()) return null;

    String? firstImported;
    for (final entity in srcDir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vrm')) {
        final destPath = p.join(modelsPath, p.basename(entity.path));
        if (!File(destPath).existsSync()) {
          await entity.copy(destPath);
          firstImported ??= destPath;
        }
      }
    }
    return firstImported;
  }

  /// Copy VRM animations from LAV2
  Future<void> copyAnimations() async {
    final srcDir = Directory(r'D:\LocalAIVtuber2\backend\services\Character\VRM3D\animations');
    if (!srcDir.existsSync()) return;

    final animDest = p.join(_profileDir, _modelsDir, _vrmDir, 'animations');
    final destDir = Directory(animDest);
    if (!destDir.existsSync()) destDir.createSync(recursive: true);

    for (final entity in srcDir.listSync()) {
      if (entity is File && entity.path.toLowerCase().endsWith('.vrma')) {
        final destPath = p.join(animDest, p.basename(entity.path));
        if (!File(destPath).existsSync()) {
          await entity.copy(destPath);
        }
      }
    }
  }
}
