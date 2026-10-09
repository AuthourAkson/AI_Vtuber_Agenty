/// 智能解压 ZIP 测试
///
/// 验证 _unpackZip 对三种 ZIP 格式的识别和解压：
///   格式 A — 扁平结构：SKILL.md 在 ZIP 根
///   格式 B — 单层包裹：skill-name/SKILL.md
///   格式 C — 多 skill：skill1/SKILL.md, skill2/SKILL.md
///   格式 D — 深层嵌套：prefix/skill-name/SKILL.md
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助函数
// ═══════════════════════════════════════════════════════════════

/// 创建测试用 ZIP 文件
///
/// [entries] 格式: { '相对路径': '文件内容' }
/// 路径使用 / 分隔，目录条目以 / 结尾
Future<String> createTestZip(
  Map<String, dynamic> entries, {
  required String tempDir,
  String zipName = 'test.zip',
}) async {
  final archive = Archive();

  for (final entry in entries.entries) {
    final path = entry.key;
    if (path.endsWith('/')) {
      // 目录条目
      continue; // archive 库会自动创建目录
    } else {
      final content =
          entry.value is String ? entry.value.codeUnits : entry.value as List<int>;
      final file = ArchiveFile(path.replaceAll('\\', '/'), content.length, content);
      archive.addFile(file);
    }
  }

  final zipData = ZipEncoder().encode(archive);
  final zipPath = p.join(tempDir, zipName);
  await File(zipPath).writeAsBytes(zipData!);
  return zipPath;
}

/// 收集目录下所有文件的相对路径（使用 / 分隔）
Future<List<String>> listFilesRecursive(String dirPath) async {
  final files = <String>[];
  final dir = Directory(dirPath);
  if (!await dir.exists()) return files;

  await for (final entity in dir.list(recursive: true)) {
    if (entity is File) {
      final relative = p.relative(entity.path, from: dirPath).replaceAll('\\', '/');
      files.add(relative);
    }
  }
  files.sort();
  return files;
}

/// 检查文件是否存在且内容匹配
Future<bool> fileContentEquals(String filePath, String expected) async {
  final file = File(filePath);
  if (!await file.exists()) return false;
  final content = await file.readAsString();
  return content == expected;
}

// ═══════════════════════════════════════════════════════════════
// 模拟 _unpackZip（来自 device_client.dart 的智能版本）
// ═══════════════════════════════════════════════════════════════

const String _skillMarker = 'SKILL.md';

enum _ZipFormat { flat, singleWrapped, multiSkill }

class _ZipStructure {
  final _ZipFormat format;
  final List<String> skillRoots;
  final String stripPrefix;
  const _ZipStructure({
    required this.format,
    required this.skillRoots,
    required this.stripPrefix,
  });
}

_ZipStructure _analyzeZipStructure(Archive archive) {
  final allFiles = <String>[];
  for (final f in archive) {
    final name = f.name.replaceAll('\\', '/');
    if (f.isFile && name.isNotEmpty) {
      allFiles.add(name);
    }
  }

  if (allFiles.isEmpty) {
    return _ZipStructure(format: _ZipFormat.flat, skillRoots: [], stripPrefix: '');
  }

  final skillMdPaths = <String>[];
  for (final filePath in allFiles) {
    final parts = filePath.split('/');
    if (parts.contains(_skillMarker)) {
      skillMdPaths.add(filePath);
    }
  }

  if (skillMdPaths.isEmpty) {
    return _ZipStructure(format: _ZipFormat.flat, skillRoots: [], stripPrefix: '');
  }

  final skillDepths = <int, List<String>>{};
  for (final skillPath in skillMdPaths) {
    final parts = skillPath.split('/');
    final depth = parts.indexOf(_skillMarker);
    skillDepths.putIfAbsent(depth, () => []).add(skillPath);
  }

  final minDepth = skillDepths.keys.reduce((a, b) => a < b ? a : b);

  if (minDepth == 0) {
    return _ZipStructure(format: _ZipFormat.flat, skillRoots: [''], stripPrefix: '');
  }

  if (minDepth == 1) {
    final skillDirs = <String>[];
    for (final skillPath in skillDepths[minDepth]!) {
      final parts = skillPath.split('/');
      skillDirs.add(parts[0]);
    }
    final uniqueDirs = skillDirs.toSet().toList();

    if (uniqueDirs.length == 1) {
      final rootDir = uniqueDirs[0];
      return _ZipStructure(
        format: _ZipFormat.singleWrapped,
        skillRoots: [''],
        stripPrefix: '$rootDir/',
      );
    } else {
      return _ZipStructure(
        format: _ZipFormat.multiSkill,
        skillRoots: uniqueDirs,
        stripPrefix: '',
      );
    }
  }

  // minDepth >= 2
  final skillDirs = <String>[];
  for (final skillPath in skillDepths[minDepth]!) {
    final parts = skillPath.split('/');
    skillDirs.add(parts[minDepth - 1]);
  }
  final uniqueDirs = skillDirs.toSet().toList();

  final prefixParts = skillDepths[minDepth]!.first.split('/');
  final stripParts = prefixParts.sublist(0, minDepth - 1);
  final stripPrefix = '${stripParts.join('/')}/';

  if (uniqueDirs.length == 1) {
    final fullStrip = prefixParts.sublist(0, minDepth).join('/');
    return _ZipStructure(
      format: _ZipFormat.singleWrapped,
      skillRoots: [''],
      stripPrefix: '$fullStrip/',
    );
  } else {
    return _ZipStructure(
      format: _ZipFormat.multiSkill,
      skillRoots: uniqueDirs,
      stripPrefix: stripPrefix,
    );
  }
}

Future<List<String>> unpackZipSmart(String zipPath, String targetDir) async {
  final target = Directory(targetDir);
  if (await target.exists()) {
    await target.delete(recursive: true);
  }
  await target.create(recursive: true);

  final zipBytes = await File(zipPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(zipBytes);

  final structure = _analyzeZipStructure(archive);
  final stripPrefix = structure.stripPrefix;

  // 安全校验
  for (final file in archive) {
    final normalizedName = file.name.replaceAll('\\', '/');
    if (normalizedName.contains('..')) {
      throw FileSystemException('ZIP 条目包含非法路径穿越: ${file.name}');
    }
  }

  for (final file in archive) {
    String entryName = file.name.replaceAll('\\', '/');

    if (stripPrefix.isNotEmpty && entryName.startsWith(stripPrefix)) {
      entryName = entryName.substring(stripPrefix.length);
    }

    if (entryName.isEmpty) continue;

    final filePath = p.join(targetDir, entryName.replaceAll('/', Platform.pathSeparator));

    if (file.isFile) {
      final outFile = File(filePath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>);
    } else {
      if (entryName != '/' && !entryName.endsWith('/')) {
        await Directory(filePath).create(recursive: true);
      }
    }
  }

  final skillPaths = <String>[];
  for (final root in structure.skillRoots) {
    if (root.isEmpty) {
      if (await File(p.join(targetDir, 'SKILL.md')).exists()) {
        skillPaths.add(targetDir);
      }
    } else {
      final skillDir = p.join(targetDir, root);
      if (await File(p.join(skillDir, 'SKILL.md')).exists()) {
        skillPaths.add(skillDir);
      }
    }
  }

  return skillPaths;
}

// ═══════════════════════════════════════════════════════════════
// 测试
// ═══════════════════════════════════════════════════════════════

void main() {
  late String tempDir;

  setUp(() async {
    tempDir = (await Directory.systemTemp.createTemp('zip_smart_test_')).path;
  });

  tearDown(() async {
    await Directory(tempDir).delete(recursive: true);
  });

  group('格式 A — 扁平结构（SKILL.md 在 ZIP 根）', () {
    test('单 skill 扁平解压', () async {
      final zipPath = await createTestZip({
        'SKILL.md': '# Translator Skill',
        'prompt/translate.md': 'Translate: {{input}}',
        'resources/dict.csv': 'hello,你好',
      }, tempDir: tempDir, zipName: 'flat.zip');

      final outputDir = p.join(tempDir, 'output', 'translator');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(skillPaths[0], equals(outputDir));

      // 验证文件结构
      final files = await listFilesRecursive(outputDir);
      expect(files, containsAll(['SKILL.md', 'prompt/translate.md', 'resources/dict.csv']));

      // 验证内容
      expect(await fileContentEquals(p.join(outputDir, 'SKILL.md'), '# Translator Skill'), isTrue);
      expect(
          await fileContentEquals(p.join(outputDir, 'prompt', 'translate.md'), 'Translate: {{input}}'),
          isTrue);
    });

    test('只有 SKILL.md 的最简扁平 ZIP', () async {
      final zipPath = await createTestZip({
        'SKILL.md': '# Minimal Skill',
      }, tempDir: tempDir, zipName: 'minimal.zip');

      final outputDir = p.join(tempDir, 'output', 'minimal');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(await File(p.join(outputDir, 'SKILL.md')).exists(), isTrue);
    });
  });

  group('格式 B — 单层包裹（skill-name/SKILL.md）', () {
    test('单 skill 带同名根目录，自动剥离', () async {
      final zipPath = await createTestZip({
        'translator/SKILL.md': '# Translator Skill',
        'translator/prompt/translate.md': 'Translate: {{input}}',
        'translator/resources/dict.csv': 'hello,你好',
      }, tempDir: tempDir, zipName: 'wrapped.zip');

      final outputDir = p.join(tempDir, 'output', 'translator');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(skillPaths[0], equals(outputDir));

      // 关键验证：不应该出现双层目录
      final badPath = p.join(outputDir, 'translator', 'SKILL.md');
      expect(await File(badPath).exists(), isFalse, reason: '不应出现双层目录');

      // 正确路径应存在
      expect(await File(p.join(outputDir, 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'prompt', 'translate.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'resources', 'dict.csv')).exists(), isTrue);
    });

    test('根目录名与目标目录名不同，也能正确剥离', () async {
      final zipPath = await createTestZip({
        'my-awesome-skill/SKILL.md': '# My Skill',
        'my-awesome-skill/tools/helper.py': 'print("hello")',
      }, tempDir: tempDir, zipName: 'diff_name.zip');

      final outputDir = p.join(tempDir, 'output', 'renamed-skill');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(await File(p.join(outputDir, 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'tools', 'helper.py')).exists(), isTrue);
    });
  });

  group('格式 C — 多 skill 包裹', () {
    test('两个 skill 各自独立目录', () async {
      final zipPath = await createTestZip({
        'translator/SKILL.md': '# Translator',
        'translator/prompt/translate.md': 'Translate: {{input}}',
        'summarizer/SKILL.md': '# Summarizer',
        'summarizer/prompt/summarize.md': 'Summarize: {{text}}',
      }, tempDir: tempDir, zipName: 'multi.zip');

      final outputDir = p.join(tempDir, 'output', 'skills');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(2));

      // 验证两个 skill 都正确解压
      expect(await File(p.join(outputDir, 'translator', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'translator', 'prompt', 'translate.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'summarizer', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'summarizer', 'prompt', 'summarize.md')).exists(), isTrue);
    });

    test('三个 skill 各自独立目录', () async {
      final zipPath = await createTestZip({
        'skill-a/SKILL.md': '# Skill A',
        'skill-b/SKILL.md': '# Skill B',
        'skill-c/SKILL.md': '# Skill C',
        'skill-c/data/config.json': '{"key": "value"}',
      }, tempDir: tempDir, zipName: 'multi3.zip');

      final outputDir = p.join(tempDir, 'output', 'skills');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(3));
      expect(await File(p.join(outputDir, 'skill-a', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-b', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-c', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-c', 'data', 'config.json')).exists(), isTrue);
    });
  });

  group('格式 D — 深层嵌套', () {
    test('prefix/skill-name/SKILL.md 自动剥离前缀', () async {
      final zipPath = await createTestZip({
        'some-prefix/translator/SKILL.md': '# Translator',
        'some-prefix/translator/prompt/translate.md': 'Translate: {{input}}',
      }, tempDir: tempDir, zipName: 'deep_single.zip');

      final outputDir = p.join(tempDir, 'output', 'translator');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(await File(p.join(outputDir, 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'prompt', 'translate.md')).exists(), isTrue);
    });

    test('prefix/skill1/SKILL.md + prefix/skill2/SKILL.md 多 skill 深层', () async {
      final zipPath = await createTestZip({
        'v2/skill-a/SKILL.md': '# Skill A',
        'v2/skill-a/tools/run.py': 'print("a")',
        'v2/skill-b/SKILL.md': '# Skill B',
        'v2/skill-b/tools/run.py': 'print("b")',
      }, tempDir: tempDir, zipName: 'deep_multi.zip');

      final outputDir = p.join(tempDir, 'output', 'skills');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(2));
      expect(await File(p.join(outputDir, 'skill-a', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-a', 'tools', 'run.py')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-b', 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'skill-b', 'tools', 'run.py')).exists(), isTrue);
    });
  });

  group('边界情况', () {
    test('空 ZIP', () async {
      final zipPath = await createTestZip({}, tempDir: tempDir, zipName: 'empty.zip');

      final outputDir = p.join(tempDir, 'output', 'empty');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(0));
    });

    test('无 SKILL.md 的 ZIP', () async {
      final zipPath = await createTestZip({
        'readme.txt': 'This is not a skill',
        'data/info.json': '{}',
      }, tempDir: tempDir, zipName: 'no_skill.zip');

      final outputDir = p.join(tempDir, 'output', 'noskill');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(0));
      // 文件仍然被解压
      expect(await File(p.join(outputDir, 'readme.txt')).exists(), isTrue);
    });

    test('路径穿越攻击被拒绝', () async {
      // 手动构造恶意 ZIP
      final archive = Archive();
      final malicious = ArchiveFile('../../../etc/passwd', 4, 'root'.codeUnits);
      archive.addFile(malicious);
      final zipData = ZipEncoder().encode(archive);
      final zipPath = p.join(tempDir, 'malicious.zip');
      await File(zipPath).writeAsBytes(zipData!);

      final outputDir = p.join(tempDir, 'output', 'safe');
      expect(
        () => unpackZipSmart(zipPath, outputDir),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('混合文件和 skill 共存', () async {
      final zipPath = await createTestZip({
        'SKILL.md': '# Mixed Skill',
        'prompt/test.md': 'Test prompt',
        'extra-data.txt': 'Some extra data at root',
      }, tempDir: tempDir, zipName: 'mixed.zip');

      final outputDir = p.join(tempDir, 'output', 'mixed');
      final skillPaths = await unpackZipSmart(zipPath, outputDir);

      expect(skillPaths.length, equals(1));
      expect(await File(p.join(outputDir, 'SKILL.md')).exists(), isTrue);
      expect(await File(p.join(outputDir, 'extra-data.txt')).exists(), isTrue);
    });
  });

  group('结构分析单元测试', () {
    test('扁平结构识别', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('SKILL.md', 5, 'hello'.codeUnits));
      archive.addFile(ArchiveFile('prompt/a.md', 3, 'abc'.codeUnits));

      final structure = _analyzeZipStructure(archive);
      expect(structure.format, equals(_ZipFormat.flat));
      expect(structure.stripPrefix, isEmpty);
      expect(structure.skillRoots, equals(['']));
    });

    test('单层包裹识别', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('translator/SKILL.md', 5, 'hello'.codeUnits));

      final structure = _analyzeZipStructure(archive);
      expect(structure.format, equals(_ZipFormat.singleWrapped));
      expect(structure.stripPrefix, equals('translator/'));
      expect(structure.skillRoots, equals(['']));
    });

    test('多 skill 识别', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('skill-a/SKILL.md', 5, 'hello'.codeUnits));
      archive.addFile(ArchiveFile('skill-b/SKILL.md', 5, 'world'.codeUnits));

      final structure = _analyzeZipStructure(archive);
      expect(structure.format, equals(_ZipFormat.multiSkill));
      expect(structure.stripPrefix, isEmpty);
      expect(structure.skillRoots, containsAll(['skill-a', 'skill-b']));
    });

    test('深层嵌套单 skill 识别', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('prefix/translator/SKILL.md', 5, 'hello'.codeUnits));

      final structure = _analyzeZipStructure(archive);
      expect(structure.format, equals(_ZipFormat.singleWrapped));
      expect(structure.stripPrefix, equals('prefix/translator/'));
    });

    test('深层嵌套多 skill 识别', () async {
      final archive = Archive();
      archive.addFile(ArchiveFile('v2/skill-a/SKILL.md', 5, 'hello'.codeUnits));
      archive.addFile(ArchiveFile('v2/skill-b/SKILL.md', 5, 'world'.codeUnits));

      final structure = _analyzeZipStructure(archive);
      expect(structure.format, equals(_ZipFormat.multiSkill));
      expect(structure.stripPrefix, equals('v2/'));
      expect(structure.skillRoots, containsAll(['skill-a', 'skill-b']));
    });
  });
}
