/// 技能文件同步 & ZIP 加载 — 功能测试
///
/// 覆盖技能文件同步和 ZIP 加载的测试场景：
/// - ZIP 打包/解压基础流程
/// - FakeLanClientService 文件上传/下载
/// - FakeLanHostService 文件存储
///
/// 参考：
/// - DeviceClient.syncFolderSkillFiles (打包→下载→解压流程)
/// - DeviceClient._unpackZip (ZIP 解压实现)
/// - device_rpc_handler.dart methodPackSkillFolder (打包 RPC)
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - ServerTestFixture: 服务端完整生命周期模拟
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

import 'client_test_fixture.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

/// 创建临时目录（自动清理）
Directory _createTempDir(String prefix) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}wenzagent_test_${prefix}_${const Uuid().v4().substring(0, 8)}';
  final dir = Directory(path);
  dir.createSync(recursive: true);
  return dir;
}

/// 创建包含测试文件的临时目录
Directory _createTestSkillDir() {
  final dir = _createTempDir('skill');
  File('${dir.path}${Platform.pathSeparator}README.md')
    ..createSync(recursive: true)
    ..writeAsStringSync('# Test Skill\n\nThis is a test skill.');
  File('${dir.path}${Platform.pathSeparator}config.json')
    ..createSync(recursive: true)
    ..writeAsStringSync('{"name":"test","version":"1.0"}');
  Directory('${dir.path}${Platform.pathSeparator}src').createSync();
  File('${dir.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.dart')
    ..createSync()
    ..writeAsStringSync('void main() { print("hello"); }');
  return dir;
}

/// 将目录打包为 ZIP 字节
Uint8List _packDirectoryToZipBytes(String dirPath) {
  final encoder = ZipEncoder();
  final archive = Archive();
  _addDirectoryToArchive(archive, dirPath, '');
  return Uint8List.fromList(encoder.encode(archive)!);
}

void _addDirectoryToArchive(Archive archive, String dirPath, String prefix) {
  final dir = Directory(dirPath);
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final relPath = entity.path.substring(dirPath.length + 1).replaceAll('\\', '/');
      final bytes = entity.readAsBytesSync();
      final file = ArchiveFile(relPath, bytes.length, bytes);
      archive.addFile(file);
    }
  }
}

/// 解压 ZIP 字节到目标目录
void _unpackZipBytes(Uint8List zipBytes, String targetDir) {
  final target = Directory(targetDir);
  if (target.existsSync()) {
    target.deleteSync(recursive: true);
  }
  target.createSync(recursive: true);

  final decoder = ZipDecoder();
  final archive = decoder.decodeBytes(zipBytes);

  for (final file in archive) {
    final filePath = '${targetDir}${Platform.pathSeparator}${file.name}';
    if (file.isFile) {
      final outFile = File(filePath);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsBytesSync(file.content as List<int>);
    } else {
      Directory(filePath).createSync(recursive: true);
    }
  }
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: ZIP 打包/解压基础流程
  // ═══════════════════════════════════════════════════════════════

  group('ZIP 打包/解压基础流程', () {
    late Directory testDir;
    late Directory outputDir;

    tearDown(() {
      try {
        testDir.deleteSync(recursive: true);
      } catch (_) {}
      try {
        outputDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('1.1 文件夹打包为 ZIP', () {
      testDir = _createTestSkillDir();
      outputDir = _createTempDir('output');

      // 打包
      final zipBytes = _packDirectoryToZipBytes(testDir.path);

      // 验证 ZIP 非空
      expect(zipBytes.length, greaterThan(0));

      // 验证 ZIP 内容有效
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(zipBytes);
      expect(archive.files.length, equals(3)); // README.md, config.json, src/main.dart

      final fileNames = archive.files.map((f) => f.name).toSet();
      expect(fileNames, contains('README.md'));
      expect(fileNames, contains('config.json'));
      expect(fileNames, contains('src/main.dart'));
    });

    test('1.2 ZIP 解压到目标目录', () {
      testDir = _createTestSkillDir();
      outputDir = _createTempDir('output');

      // 打包 → 解压
      final zipBytes = _packDirectoryToZipBytes(testDir.path);
      _unpackZipBytes(zipBytes, outputDir.path);

      // 验证解压后的文件
      expect(File('${outputDir.path}${Platform.pathSeparator}README.md').existsSync(), isTrue);
      expect(File('${outputDir.path}${Platform.pathSeparator}config.json').existsSync(), isTrue);
      expect(File('${outputDir.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.dart').existsSync(), isTrue);

      // 验证内容
      final readme = File('${outputDir.path}${Platform.pathSeparator}README.md').readAsStringSync();
      expect(readme, contains('# Test Skill'));

      final config = File('${outputDir.path}${Platform.pathSeparator}config.json').readAsStringSync();
      final configMap = jsonDecode(config) as Map<String, dynamic>;
      expect(configMap['name'], equals('test'));
    });

    test('1.3 打包→解压 往返一致性', () {
      testDir = _createTestSkillDir();
      outputDir = _createTempDir('output');

      final zipBytes1 = _packDirectoryToZipBytes(testDir.path);
      _unpackZipBytes(zipBytes1, outputDir.path);
      final zipBytes2 = _packDirectoryToZipBytes(outputDir.path);

      // 两次打包的 ZIP 大小应该相近（时间戳差异允许小额偏差）
      expect((zipBytes1.length - zipBytes2.length).abs(), lessThan(100));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: FakeLanClientService 文件上传/下载
  // ═══════════════════════════════════════════════════════════════

  group('FakeLanClientService 文件上传/下载', () {
    late ClientTestFixture fixture;
    late Directory testDir;

    setUp(() async {
      fixture = await ClientTestFixture.create('file-upload');
      testDir = _createTestSkillDir();
    });

    tearDown(() async {
      await fixture.dispose();
      try {
        testDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('2.1 uploadFile 返回 fileId', () async {
      final fileId = await fixture.fakeLanClient.uploadFile(testDir.path);
      expect(fileId, isNotEmpty);
      expect(fileId, startsWith('fake-file-'));
      expect(fixture.fakeLanClient.uploadedFiles, contains(testDir.path));
    });

    test('2.2 downloadFile 记录下载请求', () async {
      final fileId = 'fake-file-123';
      final savePath = '${testDir.path}${Platform.pathSeparator}download_test';

      await fixture.fakeLanClient.downloadFile(fileId, savePath);

      expect(fixture.fakeLanClient.downloadRequests.length, equals(1));
      expect(fixture.fakeLanClient.downloadRequests.first.fileId, equals(fileId));
      expect(fixture.fakeLanClient.downloadRequests.first.savePath, equals(savePath));
    });

    test('2.3 多次上传累积记录', () async {
      await fixture.fakeLanClient.uploadFile('/path/file1.txt');
      await fixture.fakeLanClient.uploadFile('/path/file2.txt');
      await fixture.fakeLanClient.uploadFile('/path/file3.txt');

      expect(fixture.fakeLanClient.uploadedFiles.length, equals(3));
      expect(fixture.fakeLanClient.uploadedFiles[0], equals('/path/file1.txt'));
      expect(fixture.fakeLanClient.uploadedFiles[1], equals('/path/file2.txt'));
      expect(fixture.fakeLanClient.uploadedFiles[2], equals('/path/file3.txt'));
    });

    test('2.4 清空上传下载记录', () async {
      await fixture.fakeLanClient.uploadFile('/file.txt');
      await fixture.fakeLanClient.downloadFile('id-1', '/save.txt');

      fixture.fakeLanClient.clearSentMessages();

      expect(fixture.fakeLanClient.uploadedFiles, isEmpty);
      expect(fixture.fakeLanClient.downloadRequests, isEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: FakeLanHostService 文件存储
  // ═══════════════════════════════════════════════════════════════

  group('FakeLanHostService 文件存储', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('host-file');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('3.1 saveFile 存储并返回 fileId', () async {
      final testData = [1, 2, 3, 4, 5, 6, 7, 8];
      final fileId = await fixture.hostService.saveFile(testData, 'test.bin');

      expect(fileId, isNotEmpty);
      expect(fileId, startsWith('fake-file-'));
    });

    test('3.2 getFile 获取已存储的文件数据', () async {
      final testData = [10, 20, 30, 40, 50];
      final fileId = await fixture.hostService.saveFile(testData, 'data.bin');

      final retrieved = await fixture.hostService.getFile(fileId);
      expect(retrieved, equals(testData));
    });

    test('3.3 多个文件独立存储和获取', () async {
      final data1 = [1, 2, 3];
      final data2 = [4, 5, 6, 7];
      final data3 = [8, 9];

      final id1 = await fixture.hostService.saveFile(data1, 'f1.bin');
      final id2 = await fixture.hostService.saveFile(data2, 'f2.bin');
      final id3 = await fixture.hostService.saveFile(data3, 'f3.bin');

      expect(await fixture.hostService.getFile(id1), equals(data1));
      expect(await fixture.hostService.getFile(id2), equals(data2));
      expect(await fixture.hostService.getFile(id3), equals(data3));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 技能文件夹文件操作集成
  // ═══════════════════════════════════════════════════════════════

  group('技能文件夹文件操作集成', () {
    late Directory skillDir;

    tearDown(() {
      try {
        skillDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('4.1 创建技能文件夹结构', () {
      skillDir = _createTempDir('skill_folder');
      final skillName = 'my-custom-skill';

      // 模拟标准技能文件夹结构
      final skillPath = '${skillDir.path}${Platform.pathSeparator}$skillName';
      Directory(skillPath).createSync();

      File('$skillPath${Platform.pathSeparator}README.md')
        ..createSync()
        ..writeAsStringSync('# $skillName');

      File('$skillPath${Platform.pathSeparator}skill.md')
        ..createSync()
        ..writeAsStringSync('## Description\n\nA custom skill.');

      Directory('$skillPath${Platform.pathSeparator}tools').createSync();

      // 验证结构
      expect(Directory(skillPath).existsSync(), isTrue);
      expect(
        File('$skillPath${Platform.pathSeparator}README.md').existsSync(), isTrue);
      expect(
        File('$skillPath${Platform.pathSeparator}skill.md').existsSync(), isTrue);
      expect(
        Directory('$skillPath${Platform.pathSeparator}tools').existsSync(), isTrue);
    });

    test('4.2 技能文件夹 ZIP 导出与重新导入', () {
      skillDir = _createTestSkillDir();

      // 导出
      final zipBytes = _packDirectoryToZipBytes(skillDir.path);
      expect(zipBytes.length, greaterThan(0));

      // 模拟传输后重新导入
      final importDir = _createTempDir('skill_import');
      _unpackZipBytes(zipBytes, importDir.path);

      // 验证结构一致
      final srcFiles = Directory(skillDir.path)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.substring(skillDir.path.length))
          .toSet();
      final importedFiles = Directory(importDir.path)
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path.substring(importDir.path.length))
          .toSet();

      expect(importedFiles, equals(srcFiles));

      // 验证内容
      for (final relPath in srcFiles) {
        final srcContent =
            File('${skillDir.path}$relPath').readAsStringSync();
        final importedContent =
            File('${importDir.path}$relPath').readAsStringSync();
        expect(importedContent, equals(srcContent));
      }

      importDir.deleteSync(recursive: true);
    });

    test('4.3 空文件夹的 ZIP 处理', () {
      skillDir = _createTempDir('empty');
      // 空文件夹 (只有目录没有文件)

      final zipBytes = _packDirectoryToZipBytes(skillDir.path);
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(zipBytes);

      // 空文件夹 ZIP 应该没有文件条目
      expect(archive.files.length, equals(0));

      // 解压空 ZIP 不应报错
      final importDir = _createTempDir('empty_import');
      _unpackZipBytes(zipBytes, importDir.path);
      expect(Directory(importDir.path).existsSync(), isTrue);

      importDir.deleteSync(recursive: true);
    });

    test('4.4 嵌套子文件夹的 ZIP 处理', () {
      skillDir = _createTempDir('nested');
      Directory('${skillDir.path}${Platform.pathSeparator}level1').createSync();
      Directory('${skillDir.path}${Platform.pathSeparator}level1${Platform.pathSeparator}level2').createSync();
      File('${skillDir.path}${Platform.pathSeparator}level1${Platform.pathSeparator}level2${Platform.pathSeparator}deep.txt')
        ..createSync()
        ..writeAsStringSync('deep file');

      final zipBytes = _packDirectoryToZipBytes(skillDir.path);
      final decoder = ZipDecoder();
      final archive = decoder.decodeBytes(zipBytes);

      // 应该有 1 个文件在嵌套路径中
      final deepFile = archive.files.where((f) => f.name.contains('deep.txt'));
      expect(deepFile.length, equals(1));
      expect(deepFile.first.name, equals('level1/level2/deep.txt'));
    });
  });
}
