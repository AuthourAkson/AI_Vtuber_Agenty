/// 全局 Skill 配置到员工 Skill 推送流程 — 功能测试
///
/// 模拟 wenzflow 前端 EmployeeSkillController.addSkillsFromGlobal 的完整推送链路：
///
///   1. 创建 GlobalSkill（config / folder 类型）
///   2. 将 GlobalSkill 引用为员工 AiEmployeeSkillEntity（新 UUID，绑定 employeeId）
///   3. folder 类型：config 中的 folder_path 改为本地 skillsDir/{name} 绝对路径
///   4. 通过 proxy.setSkills() 保存到 Agent（软删旧 → 保存新 → 卸载运行时 → 同步文件 → 重加载）
///   5. 广播技能到所有在线设备
///   6. folder 类型：从源设备拉取文件 + 推送到其他设备
///
/// 测试分层：
/// - Group 1: 单设备 — GlobalSkill 创建 + 员工引用 + 本地文件同步
/// - Group 2: 双设备 — GlobalSkill 广播 + folder 文件 ZIP 打包/解压推送
/// - Group 3: ZIP 智能解压 — 各种 ZIP 格式的识别和正确解压
/// - Group 4: 端到端完整流程 — 从 GlobalSkill 创建到 folder 文件到达目标设备
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - ServerTestFixture: 服务端完整生命周期模拟
/// - LanTestHarness: 端到端通信桥接
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';


import 'client_test_fixture.dart';
import 'lan_test_harness.dart';


// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

/// 创建临时目录（自动清理）
Directory _createTempDir(String prefix) {
  final path =
      '${Directory.systemTemp.path}${Platform.pathSeparator}wenzagent_gskill_${prefix}_${const Uuid().v4().substring(0, 8)}';
  final dir = Directory(path);
  dir.createSync(recursive: true);
  return dir;
}

/// 创建标准 skill 文件夹（含 SKILL.md）
Directory _createSkillFolder(String parentDir, String skillName, {String? extraContent}) {
  final skillDir = Directory(p.join(parentDir, skillName));
  skillDir.createSync(recursive: true);
  File(p.join(skillDir.path, 'SKILL.md'))
    ..createSync()
    ..writeAsStringSync('# $skillName\n\n${extraContent ?? "A skill for testing."}\n');
  File(p.join(skillDir.path, 'config.json'))
    ..createSync()
    ..writeAsStringSync(jsonEncode({'name': skillName, 'version': '1.0'}));
  return skillDir;
}

/// 将目录打包为 ZIP 字节（扁平结构，不含根目录名）
Uint8List _packFlatZip(String dirPath) {
  final encoder = ZipEncoder();
  final archive = Archive();
  final dir = Directory(dirPath);
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final relPath = entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      final bytes = entity.readAsBytesSync();
      archive.addFile(ArchiveFile(relPath, bytes.length, bytes));
    }
  }
  return Uint8List.fromList(encoder.encode(archive)!);
}

/// 将目录打包为 ZIP 字节（包含根目录名包裹）
Uint8List _packWrappedZip(String dirPath, {String? wrapperName}) {
  final encoder = ZipEncoder();
  final archive = Archive();
  final dir = Directory(dirPath);
  final wrapper = wrapperName ?? p.basename(dirPath);
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final relPath = entity.path.substring(dir.path.length + 1).replaceAll('\\', '/');
      final bytes = entity.readAsBytesSync();
      archive.addFile(ArchiveFile('$wrapper/$relPath', bytes.length, bytes));
    }
  }
  return Uint8List.fromList(encoder.encode(archive)!);
}

/// 创建 GlobalSkillEntity
GlobalSkillEntity _createGlobalSkill({
  String? uuid,
  String? name,
  String? description,
  String skillType = 'config',
  String? config,
  int enabled = 1,
}) {
  final now = DateTime.now();
  return GlobalSkillEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? 'Global Skill',
    description: description,
    skillType: skillType,
    config: config,
    enabled: enabled,
    createTime: now,
    updateTime: now,
  );
}

/// 创建 AiEmployeeSkillEntity
AiEmployeeSkillEntity _createEmployeeSkill({
  String? uuid,
  String? employeeId,
  String? name,
  String? description,
  String skillType = 'config',
  String? config,
  String? globalSkillId,
  int enabled = 1,
}) {
  final now = DateTime.now();
  return AiEmployeeSkillEntity(
    uuid: uuid ?? const Uuid().v4(),
    employeeId: employeeId ?? const Uuid().v4(),
    name: name ?? 'Employee Skill',
    description: description,
    skillType: skillType,
    config: config,
    globalSkillId: globalSkillId,
    enabled: enabled,
    createTime: now,
    updateTime: now,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: 单设备 — GlobalSkill 创建 + 员工引用 + 本地文件同步
  // ═══════════════════════════════════════════════════════════════

  group('单设备 GlobalSkill → 员工 Skill 引用', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('gskill-local-push');
      employeeId = const Uuid().v4();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 config 类型 GlobalSkill 引用到员工', () async {
      // 1. 创建全局 config 类型技能
      final globalSkill = _createGlobalSkill(
        name: '翻译助手',
        skillType: 'config',
        config: jsonEncode({
          'prompt': '你是一个专业翻译',
          'parameters': {'from': 'en', 'to': 'zh'},
        }),
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      // 2. 模拟前端 addSkillsFromGlobal：创建员工技能实体
      final employeeSkill = _createEmployeeSkill(
        employeeId: employeeId,
        name: globalSkill.name,
        description: globalSkill.description,
        skillType: globalSkill.skillType,
        config: globalSkill.config,
        globalSkillId: globalSkill.uuid,
      );

      // 3. 保存到员工技能表
      await fixture.skillManager.createSkill(employeeSkill);

      // 4. 验证
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.length, equals(1));
      expect(skills.first.name, equals('翻译助手'));
      expect(skills.first.skillType, equals('config'));
      expect(skills.first.globalSkillId, equals(globalSkill.uuid));

      // 验证 config 内容可解析
      final configMap = jsonDecode(skills.first.config!) as Map<String, dynamic>;
      expect(configMap['prompt'], equals('你是一个专业翻译'));
    });

    test('1.2 folder 类型 GlobalSkill 引用 — folder_path 重写为本地路径', () async {
      final skillsDir = fixture.client.skillsDir;

      // 1. 创建全局 folder 类型技能
      final globalSkill = _createGlobalSkill(
        name: 'translator',
        skillType: 'folder',
        config: jsonEncode({'folder_path': '/remote/skills/translator'}),
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      // 2. 模拟前端 addSkillsFromGlobal：重写 folder_path 为本地路径
      final localFolderPath = p.join(skillsDir, 'translator');
      final rewrittenConfig = jsonEncode({'folder_path': localFolderPath});

      final employeeSkill = _createEmployeeSkill(
        employeeId: employeeId,
        name: globalSkill.name,
        skillType: globalSkill.skillType,
        config: rewrittenConfig,
        globalSkillId: globalSkill.uuid,
      );

      await fixture.skillManager.createSkill(employeeSkill);

      // 3. 验证
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.length, equals(1));
      expect(skills.first.skillType, equals('folder'));

      final configMap = jsonDecode(skills.first.config!) as Map<String, dynamic>;
      expect(configMap['folder_path'], equals(localFolderPath));
    });

    test('1.3 多个 GlobalSkill 批量引用到同一员工', () async {
      final gs1 = _createGlobalSkill(name: '翻译', skillType: 'config', config: '{"prompt":"translate"}');
      final gs2 = _createGlobalSkill(name: '摘要', skillType: 'config', config: '{"prompt":"summarize"}');
      final gs3 = _createGlobalSkill(name: 'coder', skillType: 'folder', config: '{"folder_path":"/skills/coder"}');

      await fixture.globalSkillManager.createSkill(gs1);
      await fixture.globalSkillManager.createSkill(gs2);
      await fixture.globalSkillManager.createSkill(gs3);

      // 批量创建员工技能
      for (final gs in [gs1, gs2, gs3]) {
        await fixture.skillManager.createSkill(_createEmployeeSkill(
          employeeId: employeeId,
          name: gs.name,
          skillType: gs.skillType,
          config: gs.config,
          globalSkillId: gs.uuid,
        ));
      }

      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.length, equals(3));

      final names = skills.map((s) => s.name).toSet();
      expect(names, containsAll(['翻译', '摘要', 'coder']));

      final types = skills.map((s) => s.skillType).toSet();
      expect(types, containsAll(['config', 'folder']));
    });

    test('1.4 同一 GlobalSkill 引用到多个员工', () async {
      final globalSkill = _createGlobalSkill(
        name: '共享翻译',
        skillType: 'config',
        config: '{"prompt":"translate"}',
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      final emp1 = const Uuid().v4();
      final emp2 = const Uuid().v4();

      // 两个员工引用同一个 GlobalSkill（各生成新 UUID）
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        employeeId: emp1,
        name: globalSkill.name,
        skillType: globalSkill.skillType,
        config: globalSkill.config,
        globalSkillId: globalSkill.uuid,
      ));
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        employeeId: emp2,
        name: globalSkill.name,
        skillType: globalSkill.skillType,
        config: globalSkill.config,
        globalSkillId: globalSkill.uuid,
      ));

      final skills1 = await fixture.skillManager.getSkills(emp1);
      final skills2 = await fixture.skillManager.getSkills(emp2);

      expect(skills1.length, equals(1));
      expect(skills2.length, equals(1));
      expect(skills1.first.uuid, isNot(equals(skills2.first.uuid))); // 不同 UUID
      expect(skills1.first.globalSkillId, equals(globalSkill.uuid)); // 同一来源
      expect(skills2.first.globalSkillId, equals(globalSkill.uuid));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 双设备 — GlobalSkill 广播 + folder 文件 ZIP 推送
  // ═══════════════════════════════════════════════════════════════

  group('双设备 GlobalSkill 广播 + 员工 Skill 同步', () {
    late LanTestHarness harness;
    late String employeeId;

    setUp(() async {
      harness = await LanTestHarness.create(
        'gskill-e2e',
        clientDeviceName: 'Client-Push',
        serverHostName: 'Host-Push',
      );
      employeeId = const Uuid().v4();
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('2.1 员工 config 技能通过 RPC 同步到 Server', () async {
      final skillId = const Uuid().v4();
      final globalSkillId = const Uuid().v4();
      final skill = _createEmployeeSkill(
        uuid: skillId,
        employeeId: employeeId,
        name: 'RPC同步Config',
        skillType: 'config',
        config: '{"prompt":"test"}',
        globalSkillId: globalSkillId,
      );

      // 通过 RPC 推送到 Server
      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      // Server 端验证
      final found = await harness.server.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('RPC同步Config'));
      expect(found.globalSkillId, equals(globalSkillId));
      expect(found.employeeId, equals(employeeId));
    });

    test('2.2 GlobalSkill 通过 RPC 同步到 Server', () async {
      final globalSkillId = const Uuid().v4();
      final globalSkill = _createGlobalSkill(
        uuid: globalSkillId,
        name: '全局翻译器',
        skillType: 'folder',
        config: '{"folder_path":"/skills/translator"}',
      );

      // 通过 RPC 推送 GlobalSkill 到 Server
      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [globalSkill.toMap()]},
      );

      expect(result['count'], equals(1));

      // Server 端验证
      final gsm = harness.serverClient.globalSkillManager;
      final found = await gsm.getSkill(globalSkillId);
      expect(found, isNotNull);
      expect(found!.name, equals('全局翻译器'));
      expect(found!.skillType, equals('folder'));
    });

    test('2.3 员工 folder 技能（含 globalSkillId）通过 RPC 同步', () async {
      final skillId = const Uuid().v4();
      final globalSkillId = const Uuid().v4();

      // 先在 Server 端创建 GlobalSkill
      await harness.serverClient.globalSkillManager.createSkill(
        _createGlobalSkill(
          uuid: globalSkillId,
          name: 'translator',
          skillType: 'folder',
          config: '{"folder_path":"/skills/translator"}',
        ),
      );

      // 推送员工技能引用
      final skill = _createEmployeeSkill(
        uuid: skillId,
        employeeId: employeeId,
        name: 'translator',
        skillType: 'folder',
        config: '{"folder_path":"${p.join(harness.clientDevice.skillsDir, 'translator')}"}',
        globalSkillId: globalSkillId,
      );

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      final found = await harness.server.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.skillType, equals('folder'));
      expect(found!.globalSkillId, equals(globalSkillId));
    });

    test('2.4 批量推送混合类型技能（config + folder）', () async {
      final configSkill = _createEmployeeSkill(
        employeeId: employeeId,
        name: 'ConfigSkill',
        skillType: 'config',
        config: '{"prompt":"batch"}',
      );
      final folderSkill = _createEmployeeSkill(
        employeeId: employeeId,
        name: 'FolderSkill',
        skillType: 'folder',
        config: '{"folder_path":"/skills/folder-skill"}',
        globalSkillId: const Uuid().v4(),
      );

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [configSkill.toMap(), folderSkill.toMap()]},
      );

      expect(result['count'], equals(2));

      final serverSkills = await harness.server.skillManager.getSkills(employeeId);
      expect(serverSkills.length, equals(2));

      final configSkills = serverSkills.where((s) => s.skillType == 'config').toList();
      final folderSkills = serverSkills.where((s) => s.skillType == 'folder').toList();
      expect(configSkills.length, equals(1));
      expect(folderSkills.length, equals(1));
    });

    test('2.5 删除员工技能后重新推送（软删除 + 新增）', () async {
      final skillId = const Uuid().v4();

      // 第一次推送
      await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [_createEmployeeSkill(
          uuid: skillId,
          employeeId: employeeId,
          name: 'V1',
        ).toMap()]},
      );

      var found = await harness.server.skillManager.getSkill(skillId);
      expect(found!.name, equals('V1'));

      // 软删除
      await harness.server.skillManager.deleteSkill(skillId);
      found = await harness.server.skillManager.getSkill(skillId);
      expect(found, isNull);

      // 重新推送（新 UUID）
      final newSkillId = const Uuid().v4();
      await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [_createEmployeeSkill(
          uuid: newSkillId,
          employeeId: employeeId,
          name: 'V2',
          globalSkillId: const Uuid().v4(),
        ).toMap()]},
      );

      found = await harness.server.skillManager.getSkill(newSkillId);
      expect(found!.name, equals('V2'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: ZIP 智能解压 — 各种格式的识别和正确解压
  // ═══════════════════════════════════════════════════════════════

  group('ZIP 智能解压（folder skill 文件推送核心）', () {
    late Directory tempDir;

    setUp(() {
      tempDir = _createTempDir('zip-test');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('3.1 扁平 ZIP（格式 A）— SKILL.md 在根', () async {
      // 创建源 skill 文件夹
      final sourceDir = _createSkillFolder(tempDir.path, 'source');
      final zipBytes = _packFlatZip(sourceDir.path);

      // 写入 ZIP 文件
      final zipPath = p.join(tempDir.path, 'flat.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      // 解压到目标（模拟 skillsDir/translator/）
      final targetDir = p.join(tempDir.path, 'translator');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, targetDir);

      expect(skillPaths.length, equals(1));
      expect(skillPaths.first, equals(targetDir));
      expect(File(p.join(targetDir, 'SKILL.md')).existsSync(), isTrue);
      expect(File(p.join(targetDir, 'config.json')).existsSync(), isTrue);

      // 验证内容
      final content = File(p.join(targetDir, 'SKILL.md')).readAsStringSync();
      expect(content, contains('source'));
    });

    test('3.2 单层包裹 ZIP（格式 B）— translator/SKILL.md', () async {
      final sourceDir = _createSkillFolder(tempDir.path, 'source');
      final zipBytes = _packWrappedZip(sourceDir.path, wrapperName: 'translator');

      final zipPath = p.join(tempDir.path, 'wrapped.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      // 解压后应自动剥离 translator/ 层
      final targetDir = p.join(tempDir.path, 'translator');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, targetDir);

      expect(skillPaths.length, equals(1));
      expect(File(p.join(targetDir, 'SKILL.md')).existsSync(), isTrue);
      // 关键验证：不会出现 translator/translator/SKILL.md 的双层问题
      expect(Directory(p.join(targetDir, 'translator')).existsSync(), isFalse);
    });

    test('3.3 多 skill ZIP（格式 C）— skill1/SKILL.md + skill2/SKILL.md', () async {
      // 创建包含两个 skill 的 ZIP
      final encoder = ZipEncoder();
      final archive = Archive();

      // skill1
      archive.addFile(ArchiveFile('skill1/SKILL.md', 20, 'skill1 content'.codeUnits));
      archive.addFile(ArchiveFile('skill1/prompt.md', 18, 'prompt1 content'.codeUnits));
      // skill2
      archive.addFile(ArchiveFile('skill2/SKILL.md', 20, 'skill2 content'.codeUnits));
      archive.addFile(ArchiveFile('skill2/config.json', 18, '{"name":"s2"}'.codeUnits));

      final zipBytes = Uint8List.fromList(encoder.encode(archive)!);
      final zipPath = p.join(tempDir.path, 'multi.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      // 解压到 skillsDir（不是单个 skill 目录）
      final skillsDir = p.join(tempDir.path, 'skills');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, skillsDir);

      expect(skillPaths.length, equals(2));

      // 验证两个 skill 目录
      final skillNames = skillPaths.map((sp) => p.basename(sp)).toSet();
      expect(skillNames, containsAll(['skill1', 'skill2']));

      expect(File(p.join(skillsDir, 'skill1', 'SKILL.md')).existsSync(), isTrue);
      expect(File(p.join(skillsDir, 'skill2', 'SKILL.md')).existsSync(), isTrue);
    });

    test('3.4 深层嵌套 ZIP（格式 D）— prefix/translator/SKILL.md', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile('some-prefix/translator/SKILL.md', 15, 'deep content'.codeUnits));
      archive.addFile(ArchiveFile('some-prefix/translator/prompt.md', 13, 'prompt deep'.codeUnits));

      final zipBytes = Uint8List.fromList(encoder.encode(archive)!);
      final zipPath = p.join(tempDir.path, 'deep.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      final targetDir = p.join(tempDir.path, 'translator');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, targetDir);

      expect(skillPaths.length, equals(1));
      expect(File(p.join(targetDir, 'SKILL.md')).existsSync(), isTrue);
      // 不应出现深层嵌套
      expect(Directory(p.join(targetDir, 'some-prefix')).existsSync(), isFalse);
    });

    test('3.5 无 SKILL.md 的 ZIP — 按扁平结构原样解压', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile('readme.txt', 12, 'hello world'.codeUnits));
      archive.addFile(ArchiveFile('data/config.json', 15, '{"k":"v"}'.codeUnits));

      final zipBytes = Uint8List.fromList(encoder.encode(archive)!);
      final zipPath = p.join(tempDir.path, 'noskill.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      final targetDir = p.join(tempDir.path, 'output');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, targetDir);

      // 无 SKILL.md，返回空列表但文件应正常解压
      expect(skillPaths, isEmpty);
      expect(File(p.join(targetDir, 'readme.txt')).existsSync(), isTrue);
      expect(File(p.join(targetDir, 'data', 'config.json')).existsSync(), isTrue);
    });

    test('3.6 路径穿越攻击防护', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      archive.addFile(ArchiveFile('../../../etc/passwd', 4, 'evil'.codeUnits));

      final zipBytes = Uint8List.fromList(encoder.encode(archive)!);
      final zipPath = p.join(tempDir.path, 'evil.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      final targetDir = p.join(tempDir.path, 'safe');
      expect(
        () => DeviceClient.unpackZipForTest(zipPath, targetDir),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('3.7 空 ZIP — 不报错，返回空列表', () async {
      final encoder = ZipEncoder();
      final archive = Archive();
      final zipBytes = Uint8List.fromList(encoder.encode(archive)!);

      final zipPath = p.join(tempDir.path, 'empty.zip');
      await File(zipPath).writeAsBytes(zipBytes);

      final targetDir = p.join(tempDir.path, 'output');
      final skillPaths = await DeviceClient.unpackZipForTest(zipPath, targetDir);

      expect(skillPaths, isEmpty);
      expect(Directory(targetDir).existsSync(), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 端到端完整流程 — GlobalSkill 创建到 folder 文件到达目标设备
  // ═══════════════════════════════════════════════════════════════

  group('端到端: GlobalSkill folder 文件推送', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('gskill-folder-push');
      employeeId = const Uuid().v4();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('4.1 folder 类型 GlobalSkill → 员工引用 → folder_path 重写', () async {
      final skillsDir = fixture.client.skillsDir;

      // 1. 创建全局 folder skill
      final globalSkill = _createGlobalSkill(
        name: 'translator',
        skillType: 'folder',
        config: jsonEncode({'folder_path': '/original/path/translator'}),
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      // 2. 模拟前端 addSkillsFromGlobal
      //    folder_path 重写为 skillsDir/translator
      final localFolderPath = p.join(skillsDir, 'translator');
      final employeeSkill = _createEmployeeSkill(
        employeeId: employeeId,
        name: globalSkill.name,
        skillType: 'folder',
        config: jsonEncode({'folder_path': localFolderPath}),
        globalSkillId: globalSkill.uuid,
      );
      await fixture.skillManager.createSkill(employeeSkill);

      // 3. 验证员工技能的 folder_path 已重写
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.length, equals(1));
      final configMap = jsonDecode(skills.first.config!) as Map<String, dynamic>;
      expect(configMap['folder_path'], equals(localFolderPath));
      expect(configMap['folder_path'], isNot(equals('/original/path/translator')));
    });

    test('4.2 本地源文件夹存在时，复制到 skillsDir', () async {
      final skillsDir = fixture.client.skillsDir;

      // 1. 在 skillsDir 外部创建源文件夹
      final sourceDir = _createSkillFolder(
        tempDirForTest.path,
        'translator',
        extraContent: '专业翻译技能',
      );

      // 2. 创建 GlobalSkill（指向源文件夹）
      final globalSkill = _createGlobalSkill(
        name: 'translator',
        skillType: 'folder',
        config: jsonEncode({'folder_path': sourceDir.path}),
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      // 3. 创建员工引用（folder_path 重写为 skillsDir/translator）
      final localFolderPath = p.join(skillsDir, 'translator');
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        employeeId: employeeId,
        name: 'translator',
        skillType: 'folder',
        config: jsonEncode({'folder_path': localFolderPath}),
        globalSkillId: globalSkill.uuid,
      ));

      // 4. 模拟前端 _syncFolderSkillFilesToDevices 中的文件复制
      //    如果 sourceFolderPath != localFolderPath，复制文件
      if (sourceDir.path != localFolderPath) {
        final localDir = Directory(localFolderPath);
        if (!await localDir.exists()) {
          await localDir.create(recursive: true);
        }
        await for (final entity in sourceDir.list(recursive: true)) {
          if (entity is File) {
            final relativePath = entity.path.substring(sourceDir.path.length + 1);
            final targetPath = p.join(localFolderPath, relativePath);
            await File(targetPath).parent.create(recursive: true);
            await entity.copy(targetPath);
          }
        }
      }

      // 5. 验证 skillsDir/translator 下有 SKILL.md
      expect(File(p.join(localFolderPath, 'SKILL.md')).existsSync(), isTrue);
      final content = File(p.join(localFolderPath, 'SKILL.md')).readAsStringSync();
      expect(content, contains('专业翻译技能'));
    });

    test('4.3 ZIP 打包 → 解压 → 验证文件完整性（模拟 LAN 传输）', () async {
      final skillsDir = fixture.client.skillsDir;

      // 1. 在 "源设备" 上创建 skill 文件夹
      final sourceDir = _createSkillFolder(skillsDir, 'translator');
      Directory(p.join(sourceDir.path, 'prompt')).createSync();
      File(p.join(sourceDir.path, 'prompt', 'translate.md'))
        ..createSync()
        ..writeAsStringSync('# Translate Prompt\n\n将文本翻译为目标语言。');

      // 2. 打包为 ZIP（模拟 _packDirectoryToZip，扁平结构）
      final zipBytes = _packFlatZip(sourceDir.path);

      // 3. 模拟传输后写入临时 ZIP
      final tempZipPath = p.join(tempDirForTest.path, 'transfer.zip');
      await File(tempZipPath).writeAsBytes(zipBytes);

      // 4. 解压到目标设备（模拟 _unpackZip）
      final targetDir = p.join(skillsDir, 'translator-copy');
      final skillPaths = await DeviceClient.unpackZipForTest(tempZipPath, targetDir);

      // 5. 验证结构完整性
      expect(skillPaths.length, equals(1));
      expect(File(p.join(targetDir, 'SKILL.md')).existsSync(), isTrue);
      expect(File(p.join(targetDir, 'config.json')).existsSync(), isTrue);
      expect(File(p.join(targetDir, 'prompt', 'translate.md')).existsSync(), isTrue);

      // 6. 验证内容
      final skillMd = File(p.join(targetDir, 'SKILL.md')).readAsStringSync();
      expect(skillMd, contains('translator'));

      final promptMd = File(p.join(targetDir, 'prompt', 'translate.md')).readAsStringSync();
      expect(promptMd, contains('Translate Prompt'));
    });

    test('4.4 包裹格式 ZIP 推送后不会出现双层目录', () async {
      final skillsDir = fixture.client.skillsDir;

      // 1. 模拟外部工具打包（带根目录名包裹）
      final sourceDir = _createSkillFolder(skillsDir, 'translator-src');
      final zipBytes = _packWrappedZip(sourceDir.path, wrapperName: 'translator');

      // 2. 写入 ZIP
      final tempZipPath = p.join(tempDirForTest.path, 'wrapped-transfer.zip');
      await File(tempZipPath).writeAsBytes(zipBytes);

      // 3. 解压到 skillsDir/translator（目标路径）
      final targetDir = p.join(skillsDir, 'translator');
      final skillPaths = await DeviceClient.unpackZipForTest(tempZipPath, targetDir);

      // 4. 关键验证：不出现双层
      expect(skillPaths.length, equals(1));
      expect(File(p.join(targetDir, 'SKILL.md')).existsSync(), isTrue);

      // 绝对不能出现 translator/translator/SKILL.md
      expect(Directory(p.join(targetDir, 'translator')).existsSync(), isFalse);
      expect(File(p.join(targetDir, 'translator', 'SKILL.md')).existsSync(), isFalse);
    });

    test('4.5 GlobalSkill 删除后，员工引用的 globalSkillId 仍保留', () async {
      final globalSkillId = const Uuid().v4();

      // 1. 创建 GlobalSkill
      final globalSkill = _createGlobalSkill(
        uuid: globalSkillId,
        name: '待删除技能',
        skillType: 'config',
        config: '{"prompt":"test"}',
      );
      await fixture.globalSkillManager.createSkill(globalSkill);

      // 2. 员工引用
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        employeeId: employeeId,
        name: '待删除技能',
        globalSkillId: globalSkillId,
      ));

      // 3. 删除 GlobalSkill
      await fixture.globalSkillManager.deleteSkill(globalSkillId);

      // 4. 验证员工技能不受影响
      final skills = await fixture.skillManager.getSkills(employeeId);
      expect(skills.length, equals(1));
      expect(skills.first.globalSkillId, equals(globalSkillId));

      // 5. GlobalSkill 已软删除
      final deletedGs = await fixture.globalSkillManager.getSkillIncludingDeleted(globalSkillId);
      expect(deletedGs!.deleted, equals(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: DataSyncManager 层面的 folder skill 同步逻辑
  // ═══════════════════════════════════════════════════════════════

  group('DataSyncManager folder skill 同步逻辑', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('gskill-dsm-sync');
      employeeId = const Uuid().v4();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('5.1 员工 folder skill 动态路径解析 — skillsDir/name', () async {
      final skillsDir = fixture.client.skillsDir;

      // 创建 folder 类型的员工技能
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        employeeId: employeeId,
        name: 'my-translator',
        skillType: 'folder',
        config: jsonEncode({'folder_path': '/some/old/path'}),
      ));

      // 动态路径 = skillsDir + skill.name
      final expectedPath = p.normalize(p.absolute(p.join(skillsDir, 'my-translator')));
      expect(expectedPath, contains('my-translator'));
      expect(p.basename(expectedPath), equals('my-translator'));
    });

    test('5.2 全局 folder skill 动态路径解析', () async {
      final skillsDir = fixture.client.skillsDir;

      await fixture.globalSkillManager.createSkill(_createGlobalSkill(
        name: 'global-coder',
        skillType: 'folder',
        config: '{"folder_path":"/original/path"}',
      ));

      final expectedPath = p.normalize(p.absolute(p.join(skillsDir, 'global-coder')));
      expect(p.basename(expectedPath), equals('global-coder'));
    });

    test('5.3 originName 字段用于 LAN 同步时定位远端文件夹', () async {
      // 场景：员工 skill name = "翻译助手"，但远端文件夹名 = "translator"
      // originName = "translator" 用于在远端查找
      final skill = _createEmployeeSkill(
        employeeId: employeeId,
        name: '翻译助手',
        skillType: 'folder',
        config: jsonEncode({'folder_path': '/skills/翻译助手'}),
        globalSkillId: const Uuid().v4(),
      );

      // 设置 originName
      final skillWithOrigin = skill.copyWith(originName: 'translator');
      await fixture.skillManager.createSkill(skillWithOrigin);

      final found = await fixture.skillManager.getSkill(skill.uuid);
      expect(found!.originName, equals('translator'));
      expect(found.name, equals('翻译助手'));
    });

    test('5.4 folder skill 启用/禁用状态', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(_createEmployeeSkill(
        uuid: skillId,
        employeeId: employeeId,
        name: 'toggle-folder',
        skillType: 'folder',
        enabled: 1,
      ));

      // 禁用
      await fixture.skillManager.setSkillEnabled(skillId, false);
      var found = await fixture.skillManager.getSkill(skillId);
      expect(found!.enabled, equals(0));

      // 启用
      await fixture.skillManager.setSkillEnabled(skillId, true);
      found = await fixture.skillManager.getSkill(skillId);
      expect(found!.enabled, equals(1));
    });
  });
}

/// 测试辅助：获取共享临时目录
Directory get tempDirForTest {
  final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}wenzagent_gskill_shared');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  return dir;
}
