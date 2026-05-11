import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages Live2D model files on disk.
/// Models stored at D:\AiVtuber_Agent_profile\models\live2d\<model_name>\
class Live2DModelService {
  static const _profileDir = r'D:\AiVtuber_Agent_profile';
  static const _modelsDir = 'models';
  static const _live2dDir = 'live2d';

  String get modelsPath => p.join(_profileDir, _modelsDir, _live2dDir);

  Live2DModelService() {
    _ensureDirs();
  }

  void _ensureDirs() {
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
  }

  /// List available Live2D models (each is a subdirectory with a .model3.json)
  List<Map<String, String>> listModels() {
    final dir = Directory(modelsPath);
    if (!dir.existsSync()) return [];

    final models = <Map<String, String>>[];
    for (final entity in dir.listSync()) {
      if (entity is Directory) {
        final modelJson = _findModelJson(entity.path);
        if (modelJson != null) {
          models.add({
            'name': p.basename(entity.path),
            'path': modelJson,
          });
        }
      }
    }
    return models;
  }

  /// Find .model3.json (Cubism 4) or .model.json (Cubism 2) in a directory
  String? _findModelJson(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return null;

    // Prefer Cubism 4 format
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.model3.json')) {
        return entity.path;
      }
    }
    // Fallback to Cubism 2 format
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.model.json')) {
        return entity.path;
      }
    }
    return null;
  }

  /// Get the model JSON path for a given model name
  String? getModelJsonPath(String modelName) {
    final dirPath = p.join(modelsPath, modelName);
    return _findModelJson(dirPath);
  }

  /// Import a model from a directory path (copy to profile)
  Future<String?> importModel(String sourceDir) async {
    final src = Directory(sourceDir);
    if (!src.existsSync()) return null;

    final modelJson = _findModelJson(sourceDir);
    if (modelJson == null) return null; // No valid model found

    final modelName = p.basename(sourceDir);
    final destPath = p.join(modelsPath, modelName);

    // Remove existing if present
    if (Directory(destPath).existsSync()) {
      Directory(destPath).deleteSync(recursive: true);
    }

    // Copy entire directory
    await _copyDirectory(src, Directory(destPath));
    return destPath;
  }

  /// Delete a model
  bool deleteModel(String modelName) {
    final dirPath = p.join(modelsPath, modelName);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return false;
    dir.deleteSync(recursive: true);
    return true;
  }

  Future<void> _copyDirectory(Directory source, Directory destination) async {
    await destination.create(recursive: true);
    await for (final entity in source.list()) {
      if (entity is Directory) {
        await _copyDirectory(
          entity,
          Directory(p.join(destination.path, p.basename(entity.path))),
        );
      } else if (entity is File) {
        await entity.copy(p.join(destination.path, p.basename(entity.path)));
      }
    }
  }
}
