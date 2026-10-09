/// 技能数据同步 — 端到端功能测试
///
/// 覆盖两种技能管理器的同步场景：
/// - SkillManager（员工技能，按 employeeId 绑定）
/// - GlobalSkillManager（全局技能，独立于员工）
///
/// 参考前端 SkillTabController 的技能同步流程：
///   设备上线 → syncSkillsFromDevices()
///   创建/更新 → broadcastSkillToAllDevices(employeeId)
///   事件驱动 → onSkillChanged → refresh
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - ServerTestFixture: 服务端完整生命周期模拟
/// - LanTestHarness: 端到端通信桥接
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'dart:async';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/global_skill_manager.dart';
import 'package:auakagent/src/service/skill_manager.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

AiEmployeeSkillEntity _createEmployeeSkill({
  String? uuid,
  String? employeeId,
  String? name,
  String? description,
  String skillType = 'mcp',
  String? config,
  String? globalSkillId,
  int enabled = 1,
  int deleted = 0,
  DateTime? deleteTime,
  int sortOrder = 0,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return AiEmployeeSkillEntity(
    uuid: uuid ?? const Uuid().v4(),
    employeeId: employeeId ?? const Uuid().v4(),
    name: name ?? 'Test Skill',
    description: description,
    skillType: skillType,
    config: config,
    globalSkillId: globalSkillId,
    enabled: enabled,
    sortOrder: sortOrder,
    deleted: deleted,
    deleteTime: deleteTime,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

GlobalSkillEntity _createGlobalSkill({
  String? uuid,
  String? name,
  String? description,
  String skillType = 'config',
  String? config,
  int enabled = 1,
  int deleted = 0,
  DateTime? deleteTime,
  int sortOrder = 0,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return GlobalSkillEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? 'Global Skill',
    description: description,
    skillType: skillType,
    config: config,
    enabled: enabled,
    sortOrder: sortOrder,
    deleted: deleted,
    deleteTime: deleteTime,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: Client ↔ Server RPC 员工技能同步
  // ═══════════════════════════════════════════════════════════════

  group('Client ↔ Server RPC 员工技能同步', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('skill-sync-rpc');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 push employee skill via methodSyncSkills', () async {
      final skillId = const Uuid().v4();
      final empId = const Uuid().v4();
      final skill = _createEmployeeSkill(
        uuid: skillId,
        employeeId: empId,
        name: 'MCP Server Config',
        description: 'An MCP tool',
        skillType: 'mcp',
        config: '{"url":"http://localhost:8080"}',
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('MCP Server Config'));
      expect(found!.employeeId, equals(empId));
      expect(found!.skillType, equals('mcp'));
      expect(found!.deleted, equals(0));
    });

    test('1.2 pull employee skills via methodGetAllSkills', () async {
      final empId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(employeeId: empId, name: 'Skill-A', skillType: 'mcp'));
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(employeeId: empId, name: 'Skill-B', skillType: 'note'));

      final result = await fixture.callRpc(
        HostRpcConfig.methodGetAllSkills,
        {},
      );

      expect(result['skills'], isNotNull);
      final skills = result['skills'] as List<dynamic>;
      expect(skills.length, greaterThanOrEqualTo(2));
    });

    test('1.3 update employee skill push', () async {
      final skillId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      await fixture.skillManager.createSkill(_createEmployeeSkill(
        uuid: skillId, name: 'Old Name',
        createTime: createTime, updateTime: createTime));

      await Future.delayed(const Duration(milliseconds: 10));
      final updated = _createEmployeeSkill(
        uuid: skillId, name: 'New Name',
        description: 'Updated desc',
        createTime: createTime, updateTime: DateTime.now());

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [updated.toMap()]},
      );
      expect(result['count'], equals(1));

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('New Name'));
      expect(found!.description, equals('Updated desc'));
    });

    test('1.4 soft-delete employee skill push', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'ToDelete'));

      final deleted = _createEmployeeSkill(
        uuid: skillId, name: 'ToDelete', deleted: 1,
        deleteTime: DateTime.now(), updateTime: DateTime.now());

      await fixture.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [deleted.toMap()]},
      );

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found, isNull);

      final incDel = await fixture.skillManager.getSkillIncludingDeleted(skillId);
      expect(incDel, isNotNull);
      expect(incDel!.deleted, equals(1));
    });

    test('1.5 bulk sync multiple employee skills', () async {
      final s1 = _createEmployeeSkill(name: 'Bulk-A');
      final s2 = _createEmployeeSkill(name: 'Bulk-B');
      final s3 = _createEmployeeSkill(name: 'Bulk-C');

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [s1.toMap(), s2.toMap(), s3.toMap()]},
      );
      expect(result['count'], equals(3));

      final all = await fixture.skillManager.getAllSkills();
      expect(all.where((s) => s.deleted != 1).length, greaterThanOrEqualTo(3));
    });

    test('1.6 pull employee skills with includeDeleted', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'IncDel'));
      await fixture.skillManager.deleteSkill(skillId);

      final result = await fixture.callRpc(
        HostRpcConfig.methodGetAllSkills,
        {'includeDeleted': true},
      );

      final skills = result['skills'] as List<dynamic>;
      final deletedSkill = skills.cast<Map<String, dynamic>>()
          .where((s) => s['uuid'] == skillId);
      expect(deletedSkill.length, equals(1));
      expect(deletedSkill.first['deleted'], equals(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: Client ↔ Server RPC 全局技能同步
  // ═══════════════════════════════════════════════════════════════

  group('Client ↔ Server RPC 全局技能同步', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('gskill-sync-rpc');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 push global skill via methodSyncGlobalSkills', () async {
      final skillId = const Uuid().v4();
      final skill = _createGlobalSkill(
        uuid: skillId, name: 'Global Config Skill',
        skillType: 'config', config: '{"key":"value"}');

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      final gsm = fixture.deviceClient.globalSkillManager;
      final found = await gsm.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('Global Config Skill'));
      expect(found!.skillType, equals('config'));
    });

    test('2.2 pull global skills via methodGetGlobalSkills', () async {
      final gsm = fixture.deviceClient.globalSkillManager;
      await gsm.createSkill(_createGlobalSkill(name: 'GS-A'));
      await gsm.createSkill(_createGlobalSkill(name: 'GS-B'));

      final result = await fixture.callRpc(
        HostRpcConfig.methodGetGlobalSkills,
        {},
      );

      expect(result['skills'], isNotNull);
      final skills = result['skills'] as List<dynamic>;
      expect(skills.length, greaterThanOrEqualTo(2));
    });

    test('2.3 update global skill push', () async {
      final skillId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));
      final gsm = fixture.deviceClient.globalSkillManager;

      await gsm.createSkill(_createGlobalSkill(
        uuid: skillId, name: 'Old GS',
        createTime: createTime, updateTime: createTime));

      await Future.delayed(const Duration(milliseconds: 10));
      final updated = _createGlobalSkill(
        uuid: skillId, name: 'New GS', description: 'Updated',
        createTime: createTime, updateTime: DateTime.now());

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [updated.toMap()]},
      );
      expect(result['count'], equals(1));

      final found = await gsm.getSkill(skillId);
      expect(found!.name, equals('New GS'));
    });

    test('2.4 soft-delete global skill push', () async {
      final skillId = const Uuid().v4();
      final gsm = fixture.deviceClient.globalSkillManager;
      await gsm.createSkill(_createGlobalSkill(uuid: skillId, name: 'DelGS'));

      final deleted = _createGlobalSkill(
        uuid: skillId, name: 'DelGS', deleted: 1,
        deleteTime: DateTime.now(), updateTime: DateTime.now());

      await fixture.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [deleted.toMap()]},
      );

      final found = await gsm.getSkill(skillId);
      expect(found, isNull);
      final incDel = await gsm.getSkillIncludingDeleted(skillId);
      expect(incDel!.deleted, equals(1));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 单 Client 本地 SkillManager CRUD
  // ═══════════════════════════════════════════════════════════════

  group('单 Client 本地 SkillManager CRUD', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('skill-local');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('3.1 createSkill and query', () async {
      final skillId = const Uuid().v4();
      final empId = const Uuid().v4();
      final skill = _createEmployeeSkill(
        uuid: skillId, employeeId: empId, name: 'My Skill');

      final created = await fixture.skillManager.createSkill(skill);
      expect(created.uuid, equals(skillId));

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('My Skill'));
    });

    test('3.2 updateSkill', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'Old'));

      await fixture.skillManager.updateSkill(
        _createEmployeeSkill(uuid: skillId, name: 'Updated'));

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found!.name, equals('Updated'));
    });

    test('3.3 deleteSkill soft-delete', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'DelMe'));

      await fixture.skillManager.deleteSkill(skillId);

      final found = await fixture.skillManager.getSkill(skillId);
      expect(found, isNull);

      final incDel = await fixture.skillManager.getSkillIncludingDeleted(skillId);
      expect(incDel!.deleted, equals(1));
    });

    test('3.4 getSkills by employeeId', () async {
      final empA = const Uuid().v4();
      final empB = const Uuid().v4();

      await fixture.skillManager.createSkill(
        _createEmployeeSkill(employeeId: empA, name: 'EmpA-S1'));
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(employeeId: empA, name: 'EmpA-S2'));
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(employeeId: empB, name: 'EmpB-S1'));

      final empASkills = await fixture.skillManager.getSkills(empA);
      expect(empASkills.length, equals(2));

      final empBSkills = await fixture.skillManager.getSkills(empB);
      expect(empBSkills.length, equals(1));
    });

    test('3.5 setSkillEnabled', () async {
      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'Toggle', enabled: 1));

      await fixture.skillManager.setSkillEnabled(skillId, false);
      final disabled = await fixture.skillManager.getSkill(skillId);
      expect(disabled!.enabled, equals(0));

      await fixture.skillManager.setSkillEnabled(skillId, true);
      final enabled = await fixture.skillManager.getSkill(skillId);
      expect(enabled!.enabled, equals(1));
    });

    test('3.6 onSkillChanged events', () async {
      final events = <SkillChangeEvent>[];
      final sub = fixture.skillManager.onSkillChanged.listen(events.add);

      final skillId = const Uuid().v4();
      await fixture.skillManager.createSkill(
        _createEmployeeSkill(uuid: skillId, name: 'EventSkill'));

      await Future.delayed(Duration.zero);

      final created = events.where((e) => e.type == SkillChangeType.created);
      expect(created.length, greaterThanOrEqualTo(1));
      expect(created.any((e) => e.skillUuid == skillId), isTrue);

      await sub.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 单 Client 本地 GlobalSkillManager CRUD
  // ═══════════════════════════════════════════════════════════════

  group('单 Client 本地 GlobalSkillManager CRUD', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('gskill-local');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('4.1 createSkill and query', () async {
      final skillId = const Uuid().v4();
      final skill = _createGlobalSkill(uuid: skillId, name: 'Global Alpha');

      final created = await fixture.globalSkillManager.createSkill(skill);
      expect(created.uuid, equals(skillId));

      final found = await fixture.globalSkillManager.getSkill(skillId);
      expect(found!.name, equals('Global Alpha'));
    });

    test('4.2 updateSkill', () async {
      final skillId = const Uuid().v4();
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(uuid: skillId, name: 'Old Global'));

      await fixture.globalSkillManager.updateSkill(
        _createGlobalSkill(uuid: skillId, name: 'New Global'));

      final found = await fixture.globalSkillManager.getSkill(skillId);
      expect(found!.name, equals('New Global'));
    });

    test('4.3 deleteSkill soft-delete', () async {
      final skillId = const Uuid().v4();
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(uuid: skillId, name: 'DelGlobal'));

      await fixture.globalSkillManager.deleteSkill(skillId);

      final found = await fixture.globalSkillManager.getSkill(skillId);
      expect(found, isNull);

      final incDel =
          await fixture.globalSkillManager.getSkillIncludingDeleted(skillId);
      expect(incDel!.deleted, equals(1));
    });

    test('4.4 getAllSkills', () async {
      for (int i = 0; i < 4; i++) {
        await fixture.globalSkillManager.createSkill(
          _createGlobalSkill(name: 'GS-$i'));
      }

      final all = await fixture.globalSkillManager.getAllSkills();
      expect(all.length, greaterThanOrEqualTo(4));
    });

    test('4.5 searchSkills', () async {
      final tag = 'Srch_${const Uuid().v4().substring(0, 8)}';
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(name: 'Alpha $tag'));
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(name: 'Beta Other'));
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(name: 'Gamma $tag'));

      final results = await fixture.globalSkillManager.searchSkills(tag);
      expect(results.length, equals(2));

      final noResults = await fixture.globalSkillManager
          .searchSkills('NoMatch_${const Uuid().v4()}');
      expect(noResults, isEmpty);
    });

    test('4.6 onSkillChanged events', () async {
      final events = <GlobalSkillChangeEvent>[];
      final sub = fixture.globalSkillManager.onSkillChanged.listen(events.add);

      final skillId = const Uuid().v4();
      await fixture.globalSkillManager.createSkill(
        _createGlobalSkill(uuid: skillId, name: 'EventGS'));

      await Future.delayed(Duration.zero);

      final created =
          events.where((e) => e.type == GlobalSkillChangeType.created);
      expect(created.length, greaterThanOrEqualTo(1));
      expect(created.any((e) => e.skillUuid == skillId), isTrue);

      await sub.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: 双 Client 技能广播同步
  // ═══════════════════════════════════════════════════════════════

  group('双 Client 技能广播同步', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'skill-e2e',
        clientDeviceName: 'Client-Skill',
        serverHostName: 'Host-Skill',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('5.1 broadcast employee skill to Server via RPC', () async {
      final skillId = const Uuid().v4();
      final empId = const Uuid().v4();
      final skill = _createEmployeeSkill(
        uuid: skillId, employeeId: empId, name: 'BroadcastSkill');

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      final found = await harness.server.skillManager.getSkill(skillId);
      expect(found, isNotNull);
      expect(found!.name, equals('BroadcastSkill'));
    });

    test('5.2 broadcast global skill to Server via RPC', () async {
      final skillId = const Uuid().v4();
      final skill = _createGlobalSkill(
        uuid: skillId, name: 'BroadcastGlobal');

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [skill.toMap()]},
      );

      expect(result['count'], equals(1));

      final gsm = harness.serverClient.globalSkillManager;
      final found = await gsm.getSkill(skillId);
      expect(found!.name, equals('BroadcastGlobal'));
    });

    test('5.3 delete employee skill broadcast', () async {
      final skillId = const Uuid().v4();
      final skill = _createEmployeeSkill(
        uuid: skillId, name: 'DelBroadcast');

      await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [skill.toMap()]},
      );

      final deleted = _createEmployeeSkill(
        uuid: skillId, name: 'DelBroadcast', deleted: 1,
        deleteTime: DateTime.now(), updateTime: DateTime.now());

      await harness.server.callRpc(
        HostRpcConfig.methodSyncSkills,
        {'skills': [deleted.toMap()]},
      );

      final active = await harness.server.skillManager.getSkill(skillId);
      expect(active, isNull);
    });

    test('5.4 delete global skill broadcast', () async {
      final skillId = const Uuid().v4();
      final skill = _createGlobalSkill(uuid: skillId, name: 'DelGlobalBr');

      await harness.server.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [skill.toMap()]},
      );

      final deleted = _createGlobalSkill(
        uuid: skillId, name: 'DelGlobalBr', deleted: 1,
        deleteTime: DateTime.now(), updateTime: DateTime.now());

      await harness.server.callRpc(
        HostRpcConfig.methodSyncGlobalSkills,
        {'skills': [deleted.toMap()]},
      );

      final gsm = harness.serverClient.globalSkillManager;
      final active = await gsm.getSkill(skillId);
      expect(active, isNull);
    });

    test('5.5 network disconnect/recover preserves RPC methods', () {
      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);

      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodSyncSkills), isTrue);
      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodSyncGlobalSkills),
        isTrue);
    });
  });
}
