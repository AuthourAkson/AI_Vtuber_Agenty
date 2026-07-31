import 'dart:io';
import 'package:path/path.dart' as p;

/// Represents a node in the project-summary file tree.
class SummaryNode {
  final String name;
  final String relativePath;
  final bool isDirectory;
  final List<SummaryNode> children;

  const SummaryNode({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    this.children = const [],
  });
}

/// Service for managing the project-summary/ documentation structure.
///
/// Reads/writes .md files under `project-summary/` at the project root,
/// builds a browsable tree structure, and supports creating new files/folders.
class ProjectSummaryService {
  String _basePath;

  ProjectSummaryService({String? projectRoot})
      : _basePath = _buildBasePath(projectRoot ?? Directory.current.path);

  static String _buildBasePath(String projectRoot) =>
      p.join(projectRoot, 'project-summary');

  String get basePath => _basePath;

  /// Switch to a different project root. All subsequent operations
  /// will use the new project's project-summary/ directory.
  void setProjectRoot(String projectRoot) {
    _basePath = _buildBasePath(projectRoot);
  }

  /// Ensure the base directory exists.
  Future<void> ensureBaseDir() async {
    final dir = Directory(_basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Build a tree of all .md files and directories under project-summary/.
  /// Excludes hidden files/dirs (starting with '.') and non-.md files.
  Future<List<SummaryNode>> buildTree() async {
    await ensureBaseDir();
    return _scanDir(_basePath, '');
  }

  Future<List<SummaryNode>> _scanDir(String absPath, String relPath) async {
    final dir = Directory(absPath);
    if (!await dir.exists()) return [];

    final nodes = <SummaryNode>[];
    final entities = await dir.list().toList();

    // Sort: directories first, then files, both alphabetically
    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return p.basename(a.path).compareTo(p.basename(b.path));
    });

    for (final entity in entities) {
      final name = p.basename(entity.path);
      // Skip hidden files/dirs
      if (name.startsWith('.')) continue;

      final childRelPath = relPath.isEmpty ? name : p.join(relPath, name);

      if (entity is Directory) {
        final children = await _scanDir(entity.path, childRelPath);
        if (children.isNotEmpty) {
          nodes.add(SummaryNode(
            name: name,
            relativePath: childRelPath,
            isDirectory: true,
            children: children,
          ));
        }
      } else if (entity is File && name.endsWith('.md')) {
        nodes.add(SummaryNode(
          name: name,
          relativePath: childRelPath,
          isDirectory: false,
        ));
      }
    }

    return nodes;
  }

  /// Read the content of a .md file by its relative path.
  Future<String> readFile(String relativePath) async {
    final filePath = p.join(_basePath, relativePath);
    final file = File(filePath);
    if (!await file.exists()) {
      return '';
    }
    return file.readAsString();
  }

  /// Write content to a .md file by its relative path.
  Future<void> writeFile(String relativePath, String content) async {
    final filePath = p.join(_basePath, relativePath);
    final file = File(filePath);
    // Ensure parent directory exists
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// Create a new .md file in the given directory.
  Future<SummaryNode> createFile(String dirRelPath, String fileName) async {
    final name = fileName.endsWith('.md') ? fileName : '$fileName.md';
    final relPath = dirRelPath.isEmpty ? name : p.join(dirRelPath, name);
    final filePath = p.join(_basePath, relPath);

    final file = File(filePath);
    if (await file.exists()) {
      throw Exception('File already exists: $relPath');
    }
    await file.parent.create(recursive: true);
    await file.writeAsString('# $fileName\n\nStart writing here...\n');
    return SummaryNode(name: name, relativePath: relPath, isDirectory: false);
  }

  /// Create a new subdirectory.
  Future<SummaryNode> createDirectory(String parentRelPath, String dirName) async {
    final relPath = parentRelPath.isEmpty ? dirName : p.join(parentRelPath, dirName);
    final dirPath = p.join(_basePath, relPath);
    final dir = Directory(dirPath);
    if (await dir.exists()) {
      throw Exception('Directory already exists: $relPath');
    }
    await dir.create(recursive: true);
    return SummaryNode(name: dirName, relativePath: relPath, isDirectory: true);
  }

  /// Delete a file or empty directory by relative path.
  Future<void> delete(String relativePath) async {
    final fullPath = p.join(_basePath, relativePath);
    final entity = FileSystemEntity.typeSync(fullPath);
    if (entity == FileSystemEntityType.notFound) {
      throw Exception('Not found: $relativePath');
    }
    if (entity == FileSystemEntityType.directory) {
      await Directory(fullPath).delete(recursive: true);
    } else {
      await File(fullPath).delete();
    }
  }

  /// Get the absolute path for a relative path (for display/debug).
  String absolutePath(String relativePath) => p.join(_basePath, relativePath);

  /// Check if a node exists at the given relative path.
  Future<bool> exists(String relativePath) async {
    return FileSystemEntity.typeSync(p.join(_basePath, relativePath)) !=
        FileSystemEntityType.notFound;
  }
}
