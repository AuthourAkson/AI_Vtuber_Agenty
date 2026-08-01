import 'dart:io';
import 'package:path/path.dart' as p;

/// Represents a node in the project file tree.
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

/// Service for browsing/editing files of a whole project (IDE mode).
///
/// 从 MarkdownText 的 project-summary/ 专属文档服务升级为通用项目文件服务：
/// - basePath = 项目根目录本身（不再是 project-summary/）
/// - buildTree 扫描整个项目，过滤噪音目录 / 二进制文件 / 超大文件
/// - 所有读写均以「相对项目根」的路径进行
/// - project-summary/ 现在只是项目里的普通目录，自然显示在树中
class ProjectSummaryService {
  String _basePath;

  ProjectSummaryService({String? projectRoot})
      : _basePath = projectRoot ?? Directory.current.path;

  String get basePath => _basePath;

  /// Switch to a different project root. All subsequent operations
  /// will use the new project root.
  void setProjectRoot(String projectRoot) {
    _basePath = projectRoot;
  }

  // ── 扫描过滤规则 ──
  static const _maxDepth = 6;
  static const _maxFileBytes = 1024 * 1024; // 单文件 >1MB 不读/不显示

  /// 噪音目录（构建产物 / 依赖 / 工具目录），递归时整棵跳过。
  static const _excludedDirs = {
    '.git', '.idea', '.vscode', '.dart_tool', 'build', 'node_modules',
    'dist', 'out', 'target', 'Debug', 'Release', 'x64', '.gradle',
    '.settings', '.vs', 'Pods', '.venv', 'venv', '__pycache__', '.next',
    '.nuxt', 'coverage', '.cache', 'tmp',
  };

  /// 可编辑文本文件扩展名白名单。
  static const _editableExts = {
    '.md', '.markdown', '.html', '.htm', '.dart', '.js', '.mjs', '.cjs',
    '.ts', '.tsx', '.jsx', '.css', '.scss', '.less', '.json', '.yaml',
    '.yml', '.py', '.txt', '.xml', '.svg', '.sh', '.bat', '.cmd', '.ps1',
    '.java', '.c', '.cpp', '.cc', '.h', '.hpp', '.go', '.rs', '.rb',
    '.php', '.sql', '.toml', '.ini', '.cfg', '.conf', '.properties',
  };

  /// Ensure the project root exists.
  Future<void> ensureBaseDir() async {
    final dir = Directory(_basePath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Build a tree of editable files of the whole project.
  /// Excludes hidden entries, noise dirs, non-text extensions and files >1MB.
  Future<List<SummaryNode>> buildTree() async {
    await ensureBaseDir();
    return _scanDir(_basePath, '', 0);
  }

  Future<List<SummaryNode>> _scanDir(
      String absPath, String relPath, int depth) async {
    if (depth > _maxDepth) return [];
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
        if (_excludedDirs.contains(name)) continue;
        final children = await _scanDir(entity.path, childRelPath, depth + 1);
        if (children.isNotEmpty) {
          nodes.add(SummaryNode(
            name: name,
            relativePath: childRelPath,
            isDirectory: true,
            children: children,
          ));
        }
      } else if (entity is File) {
        final ext = p.extension(name).toLowerCase();
        if (!_editableExts.contains(ext)) continue;
        // Skip oversized files (prevents UI freeze on huge assets)
        try {
          if (await entity.length() > _maxFileBytes) continue;
        } catch (_) {
          continue;
        }
        nodes.add(SummaryNode(
          name: name,
          relativePath: childRelPath,
          isDirectory: false,
        ));
      }
    }

    return nodes;
  }

  /// Read the content of a file by its project-relative path.
  Future<String> readFile(String relativePath) async {
    final filePath = p.join(_basePath, relativePath);
    final file = File(filePath);
    if (!await file.exists()) {
      return '';
    }
    try {
      if (await file.length() > _maxFileBytes) return '';
    } catch (_) {}
    return file.readAsString();
  }

  /// Write content to a file by its project-relative path.
  Future<void> writeFile(String relativePath, String content) async {
    final filePath = p.join(_basePath, relativePath);
    final file = File(filePath);
    // Ensure parent directory exists
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  /// Create a new text file in the given directory.
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

  /// Absolute path of a project-relative file (for WebView file:// loading).
  String absoluteFileUri(String relativePath) {
    return Uri.file(p.join(_basePath, relativePath)).toString();
  }

  /// Check if a node exists at the given relative path.
  Future<bool> exists(String relativePath) async {
    return FileSystemEntity.typeSync(p.join(_basePath, relativePath)) !=
        FileSystemEntityType.notFound;
  }
}
