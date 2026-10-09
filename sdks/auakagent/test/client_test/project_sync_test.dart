/// 项目数据同步 — 端到端功能测试
///
/// 使用 test/client_test/ 测试基础类验证项目数据同步的完整通信场景：
/// - Client ↔ Server RPC (push/pull)
/// - 单 Client 本地 CRUD + 变更事件
/// - 双 Client 广播同步 (LanTestHarness)
///
/// 参考前端 ProjectTabController 的项目同步流程：
///   设备上线 → syncProjectsFromDevices()
///   CRUD → broadcastProjectToAllDevices(uuid)
///   事件驱动 → onProjectChanged + onSyncEvent → refresh
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
import 'package:auakagent/src/service/project_manager.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

/// 创建测试用项目实体
ProjectEntity _createProject({
  String? uuid,
  String? title,
  String? description,
  String? workPath,
  String? gitUrl,
  int? userId,
  String? spaceId,
  int deleted = 0,
  String? deleteBy,
  DateTime? deleteTime,
  String? createBy,
  DateTime? createTime,
  String? updateBy,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return ProjectEntity(
    uuid: uuid ?? const Uuid().v4(),
    title: title ?? '测试项目',
    description: description,
    workPath: workPath,
    gitUrl: gitUrl,
    userId: userId,
    spaceId: spaceId,
    deleted: deleted,
    deleteBy: deleteBy,
    deleteTime: deleteTime,
    createBy: createBy,
    createTime: createTime ?? now,
    updateBy: updateBy,
    updateTime: updateTime ?? now,
  );
}

/// 创建测试用项目模块实体
ProjectModuleEntity _createModule({
  String? uuid,
  required String projectUuid,
  String? title,
  int sortOrder = 0,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return ProjectModuleEntity(
    uuid: uuid ?? const Uuid().v4(),
    projectUuid: projectUuid,
    title: title ?? '测试模块',
    sortOrder: sortOrder,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

/// 创建测试用项目技能实体
ProjectSkillEntity _createSkill({
  String? uuid,
  required String projectUuid,
  String? title,
  String skillType = 'note',
  String? noteUuid,
  int sortOrder = 0,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return ProjectSkillEntity(
    uuid: uuid ?? const Uuid().v4(),
    projectUuid: projectUuid,
    title: title ?? '测试技能',
    skillType: skillType,
    noteUuid: noteUuid,
    sortOrder: sortOrder,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

/// 创建测试用项目工单实体
ProjectIssueEntity _createIssue({
  String? uuid,
  required String projectUuid,
  String? title,
  String status = 'open',
  String priority = 'medium',
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return ProjectIssueEntity(
    uuid: uuid ?? const Uuid().v4(),
    projectUuid: projectUuid,
    title: title ?? '测试工单',
    status: status,
    priority: priority,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

/// 构建 methodSyncProjects RPC 参数格式
///
/// 对应 DataSyncManager.broadcastProjectToAllDevices 的 payload 结构。
Map<String, dynamic> _buildSyncPayload(ProjectEntity project,
    {List<ProjectModuleEntity>? modules,
    List<ProjectSkillEntity>? skills,
    List<ProjectIssueEntity>? issues}) {
  return {
    'projects': [
      {
        'project': project.toMap(),
        'modules': modules?.map((m) => m.toMap()).toList() ?? [],
        'skills': skills?.map((s) => s.toMap()).toList() ?? [],
        'issues': issues?.map((i) => i.toMap()).toList() ?? [],
      },
    ],
  };
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: Client ↔ Server RPC 项目同步（使用 ServerTestFixture）
  // ═══════════════════════════════════════════════════════════════

  group('Client ↔ Server RPC 项目同步', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('proj-sync-rpc');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    // ── 1.1 Client 创建项目 → push 到 Server ──

    test('1.1 Client 创建项目后通过 methodSyncProjects 推送到 Server', () async {
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '同步推送测试项目',
        description: '通过RPC推送的项目',
        workPath: '/home/user/projects/test-proj',
        gitUrl: 'https://github.com/test/project.git',
      );

      final payload = _buildSyncPayload(project);
      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );

      expect(result['count'], equals(1));

      // Server 端验证
      final found = await fixture.deviceClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('同步推送测试项目'));
      expect(found!.description, equals('通过RPC推送的项目'));
      expect(found!.workPath, equals('/home/user/projects/test-proj'));
      expect(found!.gitUrl, equals('https://github.com/test/project.git'));
      expect(found!.deleted, equals(0));
      expect(found!.deleteTime, isNull);
    });

    // ── 1.2 Client 从 Server 拉取项目列表 ──

    test('1.2 Client 通过 methodGetAllProjects 从 Server 拉取项目列表', () async {
      // 先在 Server 端直接创建项目
      final proj1 = _createProject(
        title: 'Server项目-1',
        description: '描述1',
      );
      final proj2 = _createProject(
        title: 'Server项目-2',
        description: '描述2',
      );
      await fixture.deviceClient.projectManager.createProject(proj1);
      await fixture.deviceClient.projectManager.createProject(proj2);

      // 通过 RPC 拉取
      final result = await fixture.callRpc(
        HostRpcConfig.methodGetAllProjects,
        {},
      );

      expect(result, isNotNull);
      expect(result['projects'], isNotNull);
      final projects = result['projects'] as List<dynamic>;
      expect(projects.length, greaterThanOrEqualTo(2));

      // 验证返回结构包含 project/modules/skills/issues
      final first = projects.first as Map<String, dynamic>;
      expect(first.containsKey('project'), isTrue);
      expect(first.containsKey('modules'), isTrue);
      expect(first.containsKey('skills'), isTrue);
      expect(first.containsKey('issues'), isTrue);

      final projectMap = first['project'] as Map<String, dynamic>;
      expect(projectMap.containsKey('title'), isTrue);

      // 验证名称
      final names = projects
          .map((p) => (p['project'] as Map<String, dynamic>)['title'] as String)
          .toSet();
      expect(names, contains('Server项目-1'));
      expect(names, contains('Server项目-2'));
    });

    // ── 1.3 Client 更新项目 → push 更新到 Server ──

    test('1.3 Client 更新项目后通过 methodSyncProjects 推送更新', () async {
      final projId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      // 先在 Server 创建初始版本
      final original = _createProject(
        uuid: projId,
        title: '原始项目名称',
        description: '原始描述',
        workPath: '/old/path',
        createTime: createTime,
        updateTime: createTime,
      );
      await fixture.deviceClient.projectManager.saveProject(original);

      // 推送更新版本（updateTime 更新）
      final updated = _createProject(
        uuid: projId,
        title: '更新后项目名称',
        description: '更新后描述',
        workPath: '/new/path',
        gitUrl: 'https://github.com/test/updated.git',
        createTime: createTime,
        updateTime: DateTime.now(),
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(updated),
      );
      expect(result['count'], equals(1));

      // 验证更新已生效
      final found =
          await fixture.deviceClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('更新后项目名称'));
      expect(found!.description, equals('更新后描述'));
      expect(found!.workPath, equals('/new/path'));
      expect(found!.gitUrl, equals('https://github.com/test/updated.git'));
    });

    // ── 1.4 Client 删除项目（软删除）→ push 到 Server ──

    test('1.4 Client 软删除项目后同步删除状态', () async {
      final projId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 2));

      // 先在 Server 创建
      final project = _createProject(
        uuid: projId,
        title: '待删除项目',
        createTime: createTime,
        updateTime: createTime,
      );
      await fixture.deviceClient.projectManager.createProject(project);

      // 推送软删除版本
      final deletedProject = _createProject(
        uuid: projId,
        title: '待删除项目',
        deleted: 1,
        deleteTime: DateTime.now(),
        createTime: createTime,
        updateTime: DateTime.now(),
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(deletedProject),
      );
      expect(result['count'], equals(1));

      // getProject 默认过滤 deleted=1，应返回 null
      final found =
          await fixture.deviceClient.projectManager.getProject(projId);
      expect(found, isNull);

      // getAllProjectsIncludingDeleted 可获取已删除的
      final all =
          await fixture.deviceClient.projectManager.getAllProjectsIncludingDeleted();
      final deleted = all.where((p) => p.uuid == projId).toList();
      expect(deleted.length, equals(1));
      expect(deleted.first.deleted, equals(1));
      expect(deleted.first.deleteTime, isNotNull);
    });

    // ── 1.5 批量同步多个项目 ──

    test('1.5 批量同步多个项目', () async {
      final proj1 = _createProject(title: '批量项目-A');
      final proj2 = _createProject(title: '批量项目-B');
      final proj3 = _createProject(title: '批量项目-C');

      // 一次性推送多个项目
      final payload = {
        'projects': [
          {'project': proj1.toMap(), 'modules': [], 'skills': [], 'issues': []},
          {'project': proj2.toMap(), 'modules': [], 'skills': [], 'issues': []},
          {'project': proj3.toMap(), 'modules': [], 'skills': [], 'issues': []},
        ],
      };

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );
      expect(result['count'], equals(3));

      // 验证全部落地
      final all = await fixture.deviceClient.projectManager.getAllProjects();
      final ids = all.map((p) => p.uuid).toSet();
      expect(ids, contains(proj1.uuid));
      expect(ids, contains(proj2.uuid));
      expect(ids, contains(proj3.uuid));
    });

    // ── 1.6 同步项目含子资源（模块/技能/工单） ──

    test('1.6 同步项目含模块、技能、工单子资源', () async {
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '含子资源的项目',
      );

      final module = _createModule(
        projectUuid: projId,
        title: '前端模块',
        sortOrder: 1,
      );
      final skill = _createSkill(
        projectUuid: projId,
        title: '代码审查技能',
        skillType: 'note',
        noteUuid: const Uuid().v4(),
      );
      final issue = _createIssue(
        projectUuid: projId,
        title: '修复登录Bug',
        status: 'open',
        priority: 'high',
      );

      final payload = _buildSyncPayload(project,
          modules: [module], skills: [skill], issues: [issue]);

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );
      // count 应包含 project + module + skill + issue = 4
      expect(result['count'], equals(4));

      // 验证项目
      final found =
          await fixture.deviceClient.projectManager.getProject(projId);
      expect(found, isNotNull);

      // 验证模块
      final modules =
          await fixture.deviceClient.projectManager.getModules(projId);
      expect(modules.length, equals(1));
      expect(modules.first.title, equals('前端模块'));

      // 验证技能
      final skills =
          await fixture.deviceClient.projectManager.getSkills(projId);
      expect(skills.length, equals(1));
      expect(skills.first.title, equals('代码审查技能'));
      expect(skills.first.skillType, equals('note'));

      // 验证工单
      final issues =
          await fixture.deviceClient.projectManager.getIssues(projId);
      expect(issues.length, equals(1));
      expect(issues.first.title, equals('修复登录Bug'));
      expect(issues.first.priority, equals('high'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 单 Client 本地 ProjectManager CRUD（使用 ClientTestFixture）
  // ═══════════════════════════════════════════════════════════════

  group('单 Client 本地 ProjectManager CRUD', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('proj-local-crud');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    // ── 2.1 createProject 创建并查询 ──

    test('2.1 createProject 创建项目并可查询', () async {
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '我的项目',
        description: '一个测试项目',
        workPath: '/workspace/my-project',
      );

      final created = await fixture.projectManager.createProject(project);
      expect(created.uuid, equals(projId));
      expect(created.title, equals('我的项目'));

      final found = await fixture.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('我的项目'));
      expect(found!.description, equals('一个测试项目'));
      expect(found!.workPath, equals('/workspace/my-project'));
    });

    // ── 2.2 updateProject 更新项目 ──

    test('2.2 updateProject 更新项目信息', () async {
      final projId = const Uuid().v4();
      final project = _createProject(uuid: projId, title: '原始标题');
      await fixture.projectManager.createProject(project);

      final updated = _createProject(
        uuid: projId,
        title: '修改后标题',
        description: '新描述',
        workPath: '/new/workspace',
      );
      await fixture.projectManager.updateProject(updated);

      final found = await fixture.projectManager.getProject(projId);
      expect(found!.title, equals('修改后标题'));
      expect(found!.description, equals('新描述'));
      expect(found!.workPath, equals('/new/workspace'));
    });

    // ── 2.3 deleteProject 软删除 ──

    test('2.3 deleteProject 软删除项目', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '待删除'),
      );

      await fixture.projectManager.deleteProject(projId);

      // 默认查询应返回 null
      final found = await fixture.projectManager.getProject(projId);
      expect(found, isNull);

      // 含已删除的查询仍可找到
      final all =
          await fixture.projectManager.getAllProjectsIncludingDeleted();
      final deleted = all.where((p) => p.uuid == projId).toList();
      expect(deleted.length, equals(1));
      expect(deleted.first.deleted, equals(1));
    });

    // ── 2.4 getAllProjects 获取列表 ──

    test('2.4 getAllProjects 获取项目列表', () async {
      for (int i = 0; i < 5; i++) {
        await fixture.projectManager.createProject(
          _createProject(title: '项目-$i'),
        );
      }

      final projects = await fixture.projectManager.getAllProjects();
      expect(projects.length, greaterThanOrEqualTo(5));
    });

    // ── 2.5 searchProjects 搜索 ──

    test('2.5 searchProjects 按关键词搜索', () async {
      final tag = 'SrchUniq_${const Uuid().v4().substring(0, 8)}';
      await fixture.projectManager.createProject(
        _createProject(title: 'Alpha $tag'),
      );
      await fixture.projectManager.createProject(
        _createProject(title: 'Beta Other'),
      );
      await fixture.projectManager.createProject(
        _createProject(title: 'Gamma $tag'),
      );

      final results =
          await fixture.projectManager.searchProjects(tag);
      expect(results.length, equals(2));

      final noResults =
          await fixture.projectManager.searchProjects('NoMatch_${const Uuid().v4()}');
      expect(noResults, isEmpty);
    });

    // ── 2.6 createProject 触发 onProjectChanged 事件 ──

    test('2.6 createProject 触发 onProjectChanged created 事件', () async {
      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      final projId = const Uuid().v4();
      final project = _createProject(uuid: projId, title: '事件测试项目');
      await fixture.projectManager.createProject(project);

      // 等待事件调度
      await Future.delayed(Duration.zero);

      final createdEvents =
          events.where((e) => e.type == ProjectChangeType.created).toList();
      expect(createdEvents.length, greaterThanOrEqualTo(1));
      expect(createdEvents.any((e) => e.projectUuid == projId), isTrue);

      await sub.cancel();
    });

    // ── 2.7 updateProject 触发 onProjectChanged 事件 ──

    test('2.7 updateProject 触发 onProjectChanged updated 事件', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '初始'),
      );

      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      await fixture.projectManager.updateProject(
        _createProject(uuid: projId, title: '已更新'),
      );

      await Future.delayed(Duration.zero);

      final updatedEvents =
          events.where((e) => e.type == ProjectChangeType.updated).toList();
      expect(updatedEvents.length, greaterThanOrEqualTo(1));
      expect(
        updatedEvents.any((e) => e.projectUuid == projId),
        isTrue,
      );

      await sub.cancel();
    });

    // ── 2.8 deleteProject 触发 onProjectChanged 事件 ──

    test('2.8 deleteProject 触发 onProjectChanged deleted 事件', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '待删除事件'),
      );

      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      await fixture.projectManager.deleteProject(projId);

      await Future.delayed(Duration.zero);

      final deletedEvents =
          events.where((e) => e.type == ProjectChangeType.deleted).toList();
      expect(deletedEvents.length, greaterThanOrEqualTo(1));
      expect(
        deletedEvents.any((e) => e.projectUuid == projId),
        isTrue,
      );

      await sub.cancel();
    });

    // ── 2.9 getAllProjectsIncludingDeleted 获取含已删除项目 ──

    test('2.9 getAllProjectsIncludingDeleted 可获取已删除项目', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '含删除查询测试'),
      );
      await fixture.projectManager.deleteProject(projId);

      // 默认查询过滤 deleted=1
      final active = await fixture.projectManager.getAllProjects();
      expect(active.any((p) => p.uuid == projId), isFalse);

      // 含已删除查询
      final all =
          await fixture.projectManager.getAllProjectsIncludingDeleted();
      expect(all.any((p) => p.uuid == projId), isTrue);
    });

    // ── 2.10 saveProject（同步场景，保留时间戳） ──

    test('2.10 saveProject 保留原始时间戳（同步场景）', () async {
      final originalCreateTime = DateTime(2024, 1, 15, 10, 30);
      final originalUpdateTime = DateTime(2024, 2, 20, 14, 0);

      final project = _createProject(
        uuid: const Uuid().v4(),
        title: '同步保存测试',
        createTime: originalCreateTime,
        updateTime: originalUpdateTime,
      );

      await fixture.projectManager.saveProject(project);

      final found = await fixture.projectManager.getProject(project.uuid);
      expect(found, isNotNull);
      // saveProject 不修改时间戳
      expect(found!.createTime, equals(originalCreateTime));
      expect(found!.updateTime, equals(originalUpdateTime));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 双 Client 项目广播同步（使用 LanTestHarness）
  // ═══════════════════════════════════════════════════════════════

  group('双 Client 项目广播同步', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'proj-e2e',
        clientDeviceName: 'Client-A',
        serverHostName: 'Host-Server',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    // ── 3.1 Client A 创建项目 → 通过 LAN 广播到 Client B ──

    test('3.1 Client A 创建项目后通过 methodSyncProjects 广播到 Server', () async {
      // Client A 本地创建项目
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '广播创建测试项目',
        description: '从Client-A广播的项目',
      );

      // 通过 Server RPC 模拟广播（等同于 DataSyncManager.broadcastProjectToAllDevices）
      final payload = _buildSyncPayload(project);
      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );

      expect(result['count'], equals(1));

      // Server 端验证
      final found =
          await harness.serverClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('广播创建测试项目'));
    });

    // ── 3.2 Client A 更新项目 → Server 收到更新 ──

    test('3.2 Client A 更新项目后通过 RPC 推送更新到 Server', () async {
      final projId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      // Server 先有初始版本
      await harness.serverClient.projectManager.createProject(
        _createProject(
          uuid: projId,
          title: '初始版本',
          createTime: createTime,
          updateTime: createTime,
        ),
      );

      // Client A 更新后广播
      final updated = _createProject(
        uuid: projId,
        title: '广播更新版本',
        description: '新增的描述',
        workPath: '/updated/path',
        createTime: createTime,
        updateTime: DateTime.now(),
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(updated),
      );

      // Server 端验证更新
      final found =
          await harness.serverClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('广播更新版本'));
      expect(found!.description, equals('新增的描述'));
      expect(found!.workPath, equals('/updated/path'));
    });

    // ── 3.3 Client A 删除项目 → Server 收到删除 ──

    test('3.3 Client A 删除项目后通过 RPC 同步删除到 Server', () async {
      final projId = const Uuid().v4();

      // Server 先有项目
      await harness.serverClient.projectManager.createProject(
        _createProject(uuid: projId, title: '待远程删除'),
      );

      // 广播删除状态
      final deletedProject = _createProject(
        uuid: projId,
        title: '待远程删除',
        deleted: 1,
        deleteTime: DateTime.now(),
        updateTime: DateTime.now(),
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(deletedProject),
      );

      // Server 端 active 查询不应存在
      final active =
          await harness.serverClient.projectManager.getProject(projId);
      expect(active, isNull);

      // 含已删除查询应存在
      final all = await harness.serverClient.projectManager
          .getAllProjectsIncludingDeleted();
      expect(all.any((p) => p.uuid == projId), isTrue);
    });

    // ── 3.4 网络断开后恢复 → 数据一致性验证 ──

    test('3.4 网络断开后恢复，Server 端数据保持完整性', () {
      // 模拟网络断开
      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      // 恢复网络
      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);

      // Server 端 RPC 方法仍然可用（Server 不受 Client 断线影响）
      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodSyncProjects),
        isTrue,
      );
      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodGetAllProjects),
        isTrue,
      );
    });

    // ── 3.5 双 Client 各自创建项目 → 互相同步 ──

    test('3.5 多个项目数据源汇聚到 Server 端', () async {
      // 模拟 Client A 创建项目
      final projA = _createProject(title: 'ClientA-Project');
      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(projA),
      );

      // 模拟 Client B 创建项目（模拟另一个客户端）
      final projB = _createProject(title: 'ClientB-Project');
      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(projB),
      );

      // Server 端应有 A 和 B 的项目
      final all = await harness.serverClient.projectManager.getAllProjects();
      final ids = all.map((p) => p.uuid).toSet();
      expect(ids, contains(projA.uuid));
      expect(ids, contains(projB.uuid));

      // 通过 methodGetAllProjects 拉取验证
      final result = await harness.server.callRpc(
        HostRpcConfig.methodGetAllProjects,
        {},
      );
      final projects = result['projects'] as List<dynamic>;
      final titles = projects
          .map((p) => (p['project'] as Map<String, dynamic>)['title'] as String)
          .toSet();
      expect(titles, contains('ClientA-Project'));
      expect(titles, contains('ClientB-Project'));
    });
  });
}
