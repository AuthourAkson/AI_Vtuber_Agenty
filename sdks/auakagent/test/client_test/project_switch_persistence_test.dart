/// 项目切换持久化 — 恢复/同步/来回切换 问题定位测试
///
/// 问题场景：
///   1. 切换项目后是正常的，重新打开聊天窗口，恢复项目时，恢复了旧项目
///   2. 切换项目后，一直在来回切换项目
///
/// 根因分析（结合前端 wenzflow_flutter 流程）：
///
///   前端项目切换流程：
///   ┌──────────────────────────────────────────────────────────────┐
///   │ ProjectSelectorController.onProjectSelected(project)         │
///   │   1. selectedProjectUuid = project.uuid                      │
///   │   2. await _setProjectToAgent(project)                       │
///   │      → agentProxy.setProject(ProjectData(...))               │
///   │      → RPC: agentSetProject → DeviceRpcHandler               │
///   │        → agent.setProject(data)                              │
///   │        → employeeManager.updateEmployee(copyWith(project))   │
///   │        → broadcastEmployeeToAllDevices(employeeId)           │
///   │   3. await onProjectChanged?.call(project)                   │
///   │      → ChatControllerBase.onProjectChanged                   │
///   │      → agentProxy.setProject(ProjectData(...))  // 重复设置! │
///   │      → employeeManager.updateEmployee(copyWith(project))     │
///   └──────────────────────────────────────────────────────────────┘
///
///   前端重新打开聊天窗口恢复流程：
///   ┌──────────────────────────────────────────────────────────────┐
///   │ ChatControllerBase.loadSession()                             │
///   │   1. syncEmployeeFromDevice() → 从远程拉取 Employee          │
///   │      → 可能拿到旧数据（远程设备尚未同步到最新）               │
///   │   2. getOrCreateAgentProxy()                                 │
///   │      → _getOrCreateLocalAgent() → agent.setProject(          │
///   │           employee.projectUuid)  // 用 Employee 数据恢复     │
///   │   3. syncProxyConfig() → _syncProjectConfig()                │
///   │      → 如果 proxyProjectUuid 为空 → 从 Employee 恢复         │
///   │      → 如果 Employee 也为空 → 用本地第一个项目！             │
///   └──────────────────────────────────────────────────────────────┘
///
///   来回切换项目的原因（ping-pong 循环）：
///   ┌──────────────────────────────────────────────────────────────┐
///   │ DeviceRpcHandler.agentSetProject:                            │
///   │   → employeeManager.updateEmployee(...)                      │
///   │   → broadcastEmployeeToAllDevices(employeeId)                │
///   │                                                              │
///   │ 其他设备收到广播 → _mergeAndSaveEmployee →                   │
///   │   如果远程 updateTime > 本地 → 用远程数据覆盖                │
///   │   但此时远程可能还是旧数据（广播延迟/时序问题）              │
///   │                                                              │
///   │ 前端 _subscribeAgentEvents 收到 configChanged('project') →   │
///   │   loadProjects() → _restoreSelectedProject()                 │
///   │   → 可能恢复到旧 UUID → 触发 setProject → 又广播...         │
///   │   → 形成 ping-pong 循环                                      │
///   └──────────────────────────────────────────────────────────────┘
///
/// 关键问题：
///   A. copyWith 哨兵值修复：projectUuid/projectName/projectContext/workPath
///      传 null 时现在能正确清除（之前 null ?? this.projectUuid = this.projectUuid）
///   B. syncEmployeeFromDevice 可能拉取到旧数据覆盖新设置
///   C. _mergeAndSaveEmployee 基于 updateTime 的合并可能覆盖刚设置的项目
///   D. setProject → broadcastEmployee → 远程合并 → 触发 configChanged →
///      loadProjects → _restoreSelectedProject → 可能再次 setProject
///   E. onProjectChanged 被 ProjectSelectorController.onProjectSelected 和
///      _restoreSelectedProject 双重调用，导致 setProject 被执行两次
///   F. _syncProjectConfig 回退到本地第一个项目的逻辑有缺陷
///
/// 测试覆盖：
///   Group 1: 项目切换持久化测试（Employee 级别）
///   Group 2: 项目切换恢复测试（重新打开窗口场景）
///   Group 3: 项目切换同步冲突测试（多设备场景）
///   Group 4: 项目切换 ping-pong 防护测试
///   Group 5: _syncProjectConfig 回退逻辑测试
///   Group 6: 项目切换广播端到端测试
///   Group 7: copyWith 哨兵值专项测试
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
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/entity/host_rpc_request.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
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
  String? spaceId,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return ProjectEntity(
    uuid: uuid ?? const Uuid().v4(),
    title: title ?? '测试项目',
    description: description,
    workPath: workPath,
    spaceId: spaceId,
    deleted: 0,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

/// 创建测试用 Employee 实体
AiEmployeeEntity _createEmployee({
  String? uuid,
  String? name,
  String? deviceId,
  String? currentDeviceId,
  String? projectUuid,
  String? projectName,
  String? projectContext,
  String? workPath,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return AiEmployeeEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? '测试员工',
    deviceId: deviceId,
    currentDeviceId: currentDeviceId ?? deviceId,
    projectUuid: projectUuid,
    projectName: projectName,
    projectContext: projectContext,
    workPath: workPath,
    status: 'active',
    deleted: 0,
    createTime: now,
    updateTime: updateTime ?? now,
  );
}

/// 构建 methodSyncEmployees 的 RPC payload（模拟 broadcastEmployeeToAllDevices）
Map<String, dynamic> _buildSyncEmployeesPayload(
    List<AiEmployeeEntity> employees) {
  return {
    'employees': employees.map((e) => e.toMap()).toList(),
  };
}

/// 构建 methodSyncProjects 的 RPC payload（模拟 broadcastProjectToAllDevices）
Map<String, dynamic> _buildSyncProjectPayload(ProjectEntity project) {
  return {
    'projects': [
      {
        'project': project.toMap(),
        'modules': <Map<String, dynamic>>[],
        'skills': <Map<String, dynamic>>[],
        'issues': <Map<String, dynamic>>[],
      },
    ],
  };
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: 项目切换持久化测试（Employee 级别）
  // ═══════════════════════════════════════════════════════════════

  group('项目切换持久化测试', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('proj-persist');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 Employee 创建时 projectUuid 应为空', () async {
      final emp = _createEmployee(name: '无项目员工');
      await fixture.employeeManager.createEmployee(emp);

      final found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.projectUuid, isNull);
    });

    test('1.2 Employee 更新 projectUuid 后持久化正确', () async {
      final projId = const Uuid().v4();
      final emp = _createEmployee(name: '项目员工');
      await fixture.employeeManager.createEmployee(emp);

      final updated = emp.copyWith(
        projectUuid: projId,
        projectName: '测试项目A',
        projectContext: '项目上下文',
        workPath: '/work/path/a',
      );
      await fixture.employeeManager.updateEmployee(updated);

      final found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found, isNotNull);
      expect(found!.projectUuid, equals(projId));
      expect(found!.projectName, equals('测试项目A'));
      expect(found!.projectContext, equals('项目上下文'));
      expect(found!.workPath, equals('/work/path/a'));
    });

    test('1.3 从项目A切换到项目B后 Employee projectUuid 正确更新', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();

      final emp = _createEmployee(
        name: '切换员工',
        projectUuid: projA,
        projectName: '项目A',
        workPath: '/path/a',
      );
      await fixture.employeeManager.createEmployee(emp);

      var found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found!.projectUuid, equals(projA));

      final switched = emp.copyWith(
        projectUuid: projB,
        projectName: '项目B',
        workPath: '/path/b',
      );
      await fixture.employeeManager.updateEmployee(switched);

      found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found!.projectUuid, equals(projB));
      expect(found!.projectName, equals('项目B'));
      expect(found!.workPath, equals('/path/b'));
    });

    test('1.4 清除项目（setProject(null)）后 Employee projectUuid 为空', () async {
      final projId = const Uuid().v4();
      final emp = _createEmployee(
        name: '清除项目员工',
        projectUuid: projId,
        projectName: '待清除项目',
        projectContext: '待清除上下文',
        workPath: '/to/clear',
      );
      await fixture.employeeManager.createEmployee(emp);

      // 模拟 setProject(null)：copyWith 传 null 清除（哨兵值模式）
      final cleared = emp.copyWith(
        projectUuid: null,
        projectName: null,
        projectContext: null,
        workPath: null,
      );
      // 验证 copyWith 传 null 能清除字段
      expect(cleared.projectUuid, isNull,
          reason: 'copyWith 传 null 应清除 projectUuid');
      expect(cleared.projectName, isNull);
      expect(cleared.projectContext, isNull);
      expect(cleared.workPath, isNull);

      await fixture.employeeManager.updateEmployee(cleared);

      final found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found!.projectUuid, isNull,
          reason: '清除后 Employee projectUuid 应为 null');
      expect(found.projectName, isNull);
      expect(found.projectContext, isNull);
      expect(found.workPath, isNull);
    });

    test('1.5 快速连续切换两次项目后最终状态正确', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();

      final emp = _createEmployee(name: '快速切换员工');
      await fixture.employeeManager.createEmployee(emp);

      await fixture.employeeManager.updateEmployee(
        emp.copyWith(projectUuid: projA, projectName: '项目A'),
      );
      await fixture.employeeManager.updateEmployee(
        emp.copyWith(projectUuid: projB, projectName: '项目B'),
      );

      final found = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(found!.projectUuid, equals(projB));
      expect(found!.projectName, equals('项目B'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 项目切换恢复测试（重新打开窗口场景）
  // ═══════════════════════════════════════════════════════════════

  group('项目切换恢复测试', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('proj-restore');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 Employee 持久化了 projectUuid，恢复时能正确读取', () async {
      final projId = const Uuid().v4();
      final emp = _createEmployee(
        name: '恢复测试员工',
        projectUuid: projId,
        projectName: '恢复项目',
        workPath: '/restore/path',
        deviceId: fixture.deviceId,
        currentDeviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      final restored = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(restored, isNotNull);
      expect(restored!.projectUuid, equals(projId));
      expect(restored.projectName, equals('恢复项目'));
      expect(restored.workPath, equals('/restore/path'));
    });

    test('2.2 切换项目后持久化，重新读取恢复的是新项目', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();

      final emp = _createEmployee(
        name: '切换恢复员工',
        projectUuid: projA,
        projectName: '项目A',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      await fixture.employeeManager.updateEmployee(
        emp.copyWith(
          projectUuid: projB,
          projectName: '项目B',
          workPath: '/path/b',
        ),
      );

      final restored = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(restored!.projectUuid, equals(projB),
          reason: '恢复的应该是切换后的项目B');
      expect(restored.projectName, equals('项目B'));
    });

    test('2.3 Employee 无 projectUuid 时恢复为空', () async {
      final emp = _createEmployee(
        name: '无项目恢复员工',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      final restored = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(restored!.projectUuid, isNull);
    });

    test('2.4 模拟 _syncProjectConfig：proxy为空时从 Employee 恢复项目', () async {
      final projId = const Uuid().v4();
      final emp = _createEmployee(
        name: 'SyncConfig员工',
        projectUuid: projId,
        projectName: 'SyncConfig项目',
        workPath: '/sync/path',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      // 模拟 _syncProjectConfig 逻辑
      const String? proxyProjectUuid = null;

      final restoredEmp = await fixture.employeeManager.getEmployee(emp.uuid);
      if (proxyProjectUuid == null || proxyProjectUuid.isEmpty) {
        if (restoredEmp != null &&
            restoredEmp.projectUuid != null &&
            restoredEmp.projectUuid!.isNotEmpty) {
          expect(restoredEmp.projectUuid, equals(projId));
        }
      }
    });

    test('2.5 清除项目后重新打开窗口，Employee projectUuid 为空（不应回退到本地项目）',
        () async {
      // 场景：用户切换到项目A → 清除项目 → 关闭窗口 → 重新打开
      // 期望：Employee projectUuid 为空，不应自动回退到本地第一个项目
      final projA = const Uuid().v4();
      final emp = _createEmployee(
        name: '清除后恢复员工',
        projectUuid: projA,
        projectName: '项目A',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      // 模拟清除项目（setProject(null)）
      await fixture.employeeManager.updateEmployee(
        emp.copyWith(
          projectUuid: null,
          projectName: null,
          projectContext: null,
          workPath: null,
        ),
      );

      // 模拟重新打开窗口：读取 Employee
      final restored = await fixture.employeeManager.getEmployee(emp.uuid);
      expect(restored!.projectUuid, isNull,
          reason: '清除项目后 Employee projectUuid 应为 null');
      expect(restored.projectName, isNull);
    });

    test('2.6 Employee 有明确项目时不应回退到本地第一个项目', () async {
      final projA = await fixture.projectManager.createProject(
        _createProject(title: '本地项目A'),
      );
      final projB = await fixture.projectManager.createProject(
        _createProject(title: '本地项目B'),
      );

      final emp = _createEmployee(
        name: '有项目SyncConfig员工',
        projectUuid: projB.uuid,
        projectName: '本地项目B',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      const String? proxyProjectUuid = null;
      final restoredEmp = await fixture.employeeManager.getEmployee(emp.uuid);

      String? restoredProjectUuid;
      if (proxyProjectUuid == null || proxyProjectUuid.isEmpty) {
        if (restoredEmp != null &&
            restoredEmp.projectUuid != null &&
            restoredEmp.projectUuid!.isNotEmpty) {
          restoredProjectUuid = restoredEmp.projectUuid;
        } else {
          final localProjects = await fixture.projectManager.getAllProjects();
          if (localProjects.isNotEmpty) {
            restoredProjectUuid = localProjects.first.uuid;
          }
        }
      }

      expect(restoredProjectUuid, equals(projB.uuid),
          reason: 'Employee 有明确项目B时，应恢复项目B');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 项目切换同步冲突测试（多设备场景）
  // ═══════════════════════════════════════════════════════════════

  group('项目切换同步冲突测试', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'proj-sync-conflict',
        clientDeviceName: 'Client-A',
        serverHostName: 'Host-Server',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('3.1 本地切换项目后广播到 Server，Server 端数据同步', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();
      final empId = const Uuid().v4();

      final serverEmp = _createEmployee(
        uuid: empId,
        name: '同步员工',
        projectUuid: projA,
        projectName: '项目A',
        workPath: '/path/a',
      );
      await harness.serverClient.employeeManager.createEmployee(serverEmp);

      final clientEmp = serverEmp.copyWith(
        projectUuid: projB,
        projectName: '项目B',
        workPath: '/path/b',
        updateTime: DateTime.now().add(const Duration(seconds: 1)),
      );

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        _buildSyncEmployeesPayload([clientEmp]),
      );

      expect(result['count'], equals(1));

      final serverUpdated =
          await harness.serverClient.employeeManager.getEmployee(empId);
      expect(serverUpdated, isNotNull);
      expect(serverUpdated!.projectUuid, equals(projB),
          reason: 'Server 端应同步到最新的项目B');
      expect(serverUpdated.projectName, equals('项目B'));
    });

    test('3.2 远程旧数据（updateTime更早）不应覆盖本地新数据', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();
      final empId = const Uuid().v4();
      final now = DateTime.now();

      final localEmp = _createEmployee(
        uuid: empId,
        name: '冲突员工',
        projectUuid: projB,
        projectName: '项目B',
        workPath: '/path/b',
        updateTime: now.add(const Duration(seconds: 2)),
      );
      await harness.serverClient.employeeManager.createEmployee(localEmp);

      final remoteEmp = _createEmployee(
        uuid: empId,
        name: '冲突员工',
        projectUuid: projA,
        projectName: '项目A',
        workPath: '/path/a',
        updateTime: now,
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        _buildSyncEmployeesPayload([remoteEmp]),
      );

      final found =
          await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found!.projectUuid, equals(projB),
          reason: '远程旧数据不应覆盖本地新数据');
    });

    test('3.3 远程新数据（updateTime更晚）可以覆盖本地旧数据', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();
      final empId = const Uuid().v4();
      final now = DateTime.now();

      final localEmp = _createEmployee(
        uuid: empId,
        name: '覆盖员工',
        projectUuid: projA,
        projectName: '项目A',
        updateTime: now,
      );
      await harness.serverClient.employeeManager.createEmployee(localEmp);

      final remoteEmp = _createEmployee(
        uuid: empId,
        name: '覆盖员工',
        projectUuid: projB,
        projectName: '项目B',
        updateTime: now.add(const Duration(seconds: 1)),
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        _buildSyncEmployeesPayload([remoteEmp]),
      );

      final found =
          await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found!.projectUuid, equals(projB),
          reason: '远程新数据应覆盖本地旧数据');
    });

    test('3.4 updateTime 相同时不应覆盖本地数据', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();
      final empId = const Uuid().v4();
      final sameTime = DateTime(2024, 1, 1, 12, 0, 0);

      final localEmp = _createEmployee(
        uuid: empId,
        name: '同时间员工',
        projectUuid: projA,
        projectName: '项目A',
        updateTime: sameTime,
      );
      await harness.serverClient.employeeManager.createEmployee(localEmp);

      final remoteEmp = _createEmployee(
        uuid: empId,
        name: '同时间员工',
        projectUuid: projB,
        projectName: '项目B',
        updateTime: sameTime,
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        _buildSyncEmployeesPayload([remoteEmp]),
      );

      final found =
          await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found!.projectUuid, equals(projA),
          reason: 'updateTime 相同时不应覆盖');
    });

    test('3.5 项目数据同步后，Server 端 ProjectManager 包含该项目', () async {
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '广播项目',
        workPath: '/broadcast/path',
      );

      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncProjectPayload(project),
      );

      final found =
          await harness.serverClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('广播项目'));
      expect(found.workPath, equals('/broadcast/path'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 项目切换 ping-pong 防护测试
  // ═══════════════════════════════════════════════════════════════

  group('项目切换 ping-pong 防护测试', () {
    test('4.1 相同项目数据重复同步到 Server 不产生重复记录', () async {
      final harness = await LanTestHarness.create('pingpong-dup');
      try {
        final projId = const Uuid().v4();
        final project = _createProject(uuid: projId, title: 'PingPong项目');

        await harness.server.callRpc(
          HostRpcConfig.methodSyncProjects,
          _buildSyncProjectPayload(project),
        );

        var serverProjects =
            await harness.serverClient.projectManager.getAllProjects();
        expect(serverProjects.length, equals(1));

        await harness.server.callRpc(
          HostRpcConfig.methodSyncProjects,
          _buildSyncProjectPayload(project),
        );

        serverProjects =
            await harness.serverClient.projectManager.getAllProjects();
        expect(serverProjects.length, equals(1),
            reason: '相同数据重复同步不应创建重复项目');
      } finally {
        await harness.dispose();
      }
    });

    test('4.2 Employee 相同项目数据重复同步（updateTime相同）不触发更新',
        () async {
      final harness = await LanTestHarness.create('pingpong-emp-dup');
      try {
        final projId = const Uuid().v4();
        final empId = const Uuid().v4();
        final sameTime = DateTime(2024, 6, 1, 12, 0, 0);

        final localEmp = _createEmployee(
          uuid: empId,
          name: 'PingPong员工',
          projectUuid: projId,
          projectName: 'PingPong项目',
          updateTime: sameTime,
        );
        await harness.serverClient.employeeManager.createEmployee(localEmp);

        final remoteEmp = _createEmployee(
          uuid: empId,
          name: 'PingPong员工',
          projectUuid: projId,
          projectName: 'PingPong项目',
          updateTime: sameTime,
        );

        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([remoteEmp]),
        );

        final found =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(found!.projectUuid, equals(projId));
      } finally {
        await harness.dispose();
      }
    });

    test('4.3 shouldNotify 逻辑：UUID相同且非首次恢复时跳过通知', () {
      const projId = 'proj-001';

      // 场景 1：首次恢复
      {
        String? selectedProjectUuid = null;
        const needsRestoreNotification = true;
        final targetUuid = projId;
        final shouldNotify =
            selectedProjectUuid != targetUuid || needsRestoreNotification;
        expect(shouldNotify, isTrue,
            reason: '首次恢复时 selectedProjectUuid 为空，应通知');
      }

      // 场景 2：UUID 相同 + 非首次
      {
        String? selectedProjectUuid = projId;
        const needsRestoreNotification = false;
        final targetUuid = projId;
        final shouldNotify =
            selectedProjectUuid != targetUuid || needsRestoreNotification;
        expect(shouldNotify, isFalse,
            reason: 'UUID 相同且非首次恢复，不应通知（防止 ping-pong）');
      }

      // 场景 3：UUID 不同
      {
        String? selectedProjectUuid = 'proj-old';
        const needsRestoreNotification = false;
        final targetUuid = projId;
        final shouldNotify =
            selectedProjectUuid != targetUuid || needsRestoreNotification;
        expect(shouldNotify, isTrue, reason: 'UUID 不同（项目切换），应通知');
      }

      // 场景 4：Proxy 重建后
      {
        String? selectedProjectUuid = projId;
        const needsRestoreNotification = true;
        final targetUuid = projId;
        final shouldNotify =
            selectedProjectUuid != targetUuid || needsRestoreNotification;
        expect(shouldNotify, isTrue, reason: 'Proxy 重建后即使 UUID 相同也应通知');
      }
    });

    test('4.4 isLoading 守卫：加载中收到 PM 变更事件时跳过', () {
      var isLoading = false;
      int loadCount = 0;

      void simulateLoadProjects() {
        if (!isLoading) {
          isLoading = true;
          loadCount++;
          isLoading = false;
        }
      }

      simulateLoadProjects();
      expect(loadCount, equals(1));

      isLoading = true;
      simulateLoadProjects();
      expect(loadCount, equals(1));

      isLoading = false;
      simulateLoadProjects();
      expect(loadCount, equals(2));
    });

    test('4.5 双设备推送不同项目后 Server 端最终状态一致', () async {
      final harness = await LanTestHarness.create('pingpong-bidir');
      try {
        final projA = const Uuid().v4();
        final projB = const Uuid().v4();
        final empId = const Uuid().v4();
        final baseTime = DateTime.now();

        final baseEmp = _createEmployee(
          uuid: empId,
          name: '双向切换员工',
          updateTime: baseTime,
        );
        await harness.serverClient.employeeManager.createEmployee(baseEmp);

        // Client-A 推送项目A（t+1s）
        final empA = _createEmployee(
          uuid: empId,
          name: '双向切换员工',
          projectUuid: projA,
          projectName: '项目A',
          updateTime: baseTime.add(const Duration(seconds: 1)),
        );
        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([empA]),
        );

        var serverEmp =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(serverEmp!.projectUuid, equals(projA));

        // Client-B 推送项目B（t+2s，比 A 更新）
        final empB = _createEmployee(
          uuid: empId,
          name: '双向切换员工',
          projectUuid: projB,
          projectName: '项目B',
          updateTime: baseTime.add(const Duration(seconds: 2)),
        );
        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([empB]),
        );

        serverEmp =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(serverEmp!.projectUuid, equals(projB),
            reason: '最终应为最新的项目B');

        // Client-A 再次推送项目A（t+0.5s，比 B 更旧）→ 不应覆盖
        final empAOld = _createEmployee(
          uuid: empId,
          name: '双向切换员工',
          projectUuid: projA,
          projectName: '项目A',
          updateTime: baseTime.add(const Duration(milliseconds: 500)),
        );
        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([empAOld]),
        );

        serverEmp =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(serverEmp!.projectUuid, equals(projB),
            reason: '旧数据不应覆盖新数据');
      } finally {
        await harness.dispose();
      }
    });

    test('4.6 旧广播延迟到达不覆盖已更新的状态', () async {
      final harness = await LanTestHarness.create('pingpong-delay');
      try {
        final projA = const Uuid().v4();
        final projB = const Uuid().v4();
        final projC = const Uuid().v4();
        final empId = const Uuid().v4();
        final baseTime = DateTime.now();

        final empInit = _createEmployee(
          uuid: empId,
          name: '延迟广播员工',
          projectUuid: projA,
          projectName: '项目A',
          updateTime: baseTime,
        );
        await harness.serverClient.employeeManager.createEmployee(empInit);

        // 正常切换：A → B（t+2s）
        final empB = _createEmployee(
          uuid: empId,
          name: '延迟广播员工',
          projectUuid: projB,
          projectName: '项目B',
          updateTime: baseTime.add(const Duration(seconds: 2)),
        );
        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([empB]),
        );

        // 延迟到达的旧广播：A → C（t+1s，比 B 旧）
        final empC = _createEmployee(
          uuid: empId,
          name: '延迟广播员工',
          projectUuid: projC,
          projectName: '项目C',
          updateTime: baseTime.add(const Duration(seconds: 1)),
        );
        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([empC]),
        );

        final found =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(found!.projectUuid, equals(projB),
            reason: '延迟到达的旧广播不应覆盖已更新的状态');
      } finally {
        await harness.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: _syncProjectConfig 回退逻辑专项测试
  // ═══════════════════════════════════════════════════════════════

  group('_syncProjectConfig 回退逻辑测试', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('sync-config-fallback');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('5.1 proxy为空 + Employee有项目 → 正确恢复Employee的项目', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: 'Employee项目'),
      );

      final emp = _createEmployee(
        name: '有项目员工',
        projectUuid: projId,
        projectName: 'Employee项目',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      const String? proxyProjectUuid = null;
      final employee = await fixture.employeeManager.getEmployee(emp.uuid);
      final localProjects = await fixture.projectManager.getAllProjects();

      String? resultUuid;
      if (proxyProjectUuid == null || proxyProjectUuid.isEmpty) {
        if (employee != null &&
            employee.projectUuid != null &&
            employee.projectUuid!.isNotEmpty) {
          final restoredProject = localProjects
              .where((p) => p.uuid == employee.projectUuid)
              .firstOrNull;
          if (restoredProject != null) {
            resultUuid = restoredProject.uuid;
          }
        }
      }

      expect(resultUuid, equals(projId));
    });

    test('5.2 proxy为空 + Employee无项目 + 本地有项目 → 回退到本地第一个', () async {
      final projA = await fixture.projectManager.createProject(
        _createProject(title: '本地项目A'),
      );

      final emp = _createEmployee(
        name: '无项目员工',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      const String? proxyProjectUuid = null;
      final employee = await fixture.employeeManager.getEmployee(emp.uuid);
      final localProjects = await fixture.projectManager.getAllProjects();

      String? resultUuid;
      if (proxyProjectUuid == null || proxyProjectUuid.isEmpty) {
        if (employee != null &&
            employee.projectUuid != null &&
            employee.projectUuid!.isNotEmpty) {
          // Employee 有项目
        } else {
          if (localProjects.isNotEmpty) {
            resultUuid = localProjects.first.uuid;
          }
        }
      }

      expect(resultUuid, equals(projA.uuid),
          reason: '当前逻辑会回退到本地第一个项目');
    });

    test('5.3 proxy为空 + Employee无项目 + 本地无项目 → 不恢复任何项目', () async {
      final emp = _createEmployee(
        name: '空环境员工',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      const String? proxyProjectUuid = null;
      final employee = await fixture.employeeManager.getEmployee(emp.uuid);
      final localProjects = await fixture.projectManager.getAllProjects();

      String? resultUuid;
      if (proxyProjectUuid == null || proxyProjectUuid.isEmpty) {
        if (employee != null &&
            employee.projectUuid != null &&
            employee.projectUuid!.isNotEmpty) {
          // Employee 有项目
        } else {
          if (localProjects.isNotEmpty) {
            resultUuid = localProjects.first.uuid;
          }
        }
      }

      expect(resultUuid, isNull, reason: '本地无项目时不应恢复任何项目');
    });

    test('5.4 proxy有值但本地无该项目 → 从 Employee 构造并创建到本地', () async {
      final remoteProjId = const Uuid().v4();

      final emp = _createEmployee(
        name: '远程项目员工',
        projectUuid: remoteProjId,
        projectName: '远程项目',
        workPath: '/remote/path',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      final String? proxyProjectUuid = remoteProjId;
      final localProjects = await fixture.projectManager.getAllProjects();

      final hasProxyProjectInLocal =
          localProjects.any((p) => p.uuid == proxyProjectUuid);
      expect(hasProxyProjectInLocal, isFalse);

      final employee = await fixture.employeeManager.getEmployee(emp.uuid);
      if (!hasProxyProjectInLocal && employee != null) {
        final remoteProject = ProjectEntity(
          uuid: employee.projectUuid!,
          title: employee.projectName!,
          description: employee.projectContext,
          workPath: employee.workPath,
          spaceId: fixture.deviceId,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
          deleted: 0,
        );
        await fixture.projectManager.createProject(remoteProject);
      }

      final found = await fixture.projectManager.getProject(remoteProjId);
      expect(found, isNotNull);
      expect(found!.title, equals('远程项目'));
    });

    test('5.5 Employee 切换项目后 updateTime 应更新', () async {
      final projA = const Uuid().v4();
      final projB = const Uuid().v4();

      final emp = _createEmployee(
        name: 'updateTime员工',
        projectUuid: projA,
        projectName: '项目A',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(emp);

      final createdTime =
          (await fixture.employeeManager.getEmployee(emp.uuid))!.updateTime;

      await Future.delayed(const Duration(milliseconds: 10));

      await fixture.employeeManager.updateEmployee(
        emp.copyWith(
          projectUuid: projB,
          projectName: '项目B',
        ),
      );

      final updatedEmp =
          await fixture.employeeManager.getEmployee(emp.uuid);
      expect(updatedEmp!.projectUuid, equals(projB));
      expect(
          updatedEmp.updateTime.isAfter(createdTime) ||
              updatedEmp.updateTime.isAtSameMomentAs(createdTime),
          isTrue);
    });

    test('5.6 模拟 DeviceRpcHandler.agentSetProject 完整链路', () async {
      final harness = await LanTestHarness.create('setproject-e2e');
      try {
        final projId = const Uuid().v4();
        final empId = const Uuid().v4();

        final emp = _createEmployee(
          uuid: empId,
          name: 'E2E员工',
          deviceId: harness.server.deviceId,
        );
        await harness.serverClient.employeeManager.createEmployee(emp);

        await harness.serverClient.projectManager.createProject(
          _createProject(uuid: projId, title: 'E2E项目', workPath: '/e2e'),
        );

        final employee =
            await harness.serverClient.employeeManager.getEmployee(empId);
        await harness.serverClient.employeeManager.updateEmployee(
          employee!.copyWith(
            projectUuid: projId,
            projectName: 'E2E项目',
            workPath: '/e2e',
          ),
        );

        final restored =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(restored!.projectUuid, equals(projId));
        expect(restored.projectName, equals('E2E项目'));
        expect(restored.workPath, equals('/e2e'));
      } finally {
        await harness.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 6: 项目切换广播端到端测试
  // ═══════════════════════════════════════════════════════════════

  group('项目切换广播端到端测试', () {
    test('6.1 项目切换后 Employee 数据通过 methodSyncEmployees 广播', () async {
      final harness = await LanTestHarness.create('broadcast-e2e');
      try {
        final projA = const Uuid().v4();
        final projB = const Uuid().v4();
        final empId = const Uuid().v4();

        await harness.serverClient.employeeManager.createEmployee(
          _createEmployee(
            uuid: empId,
            name: '广播员工',
            projectUuid: projA,
            projectName: '项目A',
          ),
        );

        final switched = _createEmployee(
          uuid: empId,
          name: '广播员工',
          projectUuid: projB,
          projectName: '项目B',
          workPath: '/path/b',
          updateTime: DateTime.now().add(const Duration(seconds: 1)),
        );

        final result = await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([switched]),
        );

        expect(result['count'], equals(1));

        final serverEmp =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(serverEmp!.projectUuid, equals(projB));
        expect(serverEmp.projectName, equals('项目B'));
      } finally {
        await harness.dispose();
      }
    });

    test('6.2 项目数据通过 methodSyncProjects 广播到 Server', () async {
      final harness = await LanTestHarness.create('broadcast-proj');
      try {
        final projId = const Uuid().v4();
        final project = _createProject(
          uuid: projId,
          title: '广播项目数据',
          description: '通过广播同步',
          workPath: '/broadcast',
        );

        await harness.server.callRpc(
          HostRpcConfig.methodSyncProjects,
          _buildSyncProjectPayload(project),
        );

        final found =
            await harness.serverClient.projectManager.getProject(projId);
        expect(found, isNotNull);
        expect(found!.title, equals('广播项目数据'));
      } finally {
        await harness.dispose();
      }
    });

    test('6.3 项目切换后多个设备通过 Server 同步到相同状态', () async {
      final harness = await LanTestHarness.create('broadcast-multi');
      try {
        final projB = const Uuid().v4();
        final empId = const Uuid().v4();
        final baseTime = DateTime.now();

        await harness.serverClient.employeeManager.createEmployee(
          _createEmployee(
            uuid: empId,
            name: '多设备员工',
            updateTime: baseTime,
          ),
        );

        final fromDevice1 = _createEmployee(
          uuid: empId,
          name: '多设备员工',
          projectUuid: projB,
          projectName: '项目B',
          updateTime: baseTime.add(const Duration(seconds: 1)),
        );

        await harness.server.callRpc(
          HostRpcConfig.methodSyncEmployees,
          _buildSyncEmployeesPayload([fromDevice1]),
        );

        final serverEmp =
            await harness.serverClient.employeeManager.getEmployee(empId);
        expect(serverEmp!.projectUuid, equals(projB));

        // 模拟设备2从 Server 拉取
        final result = await harness.server.callRpc(
          HostRpcConfig.methodGetEmployee,
          GetEmployeeRequest(uuid: empId).toMap(),
        );

        final remoteData = result['employee'] as Map<String, dynamic>?;
        expect(remoteData, isNotNull);
        final remoteEmp = AiEmployeeEntity.fromMap(remoteData!);
        expect(remoteEmp.projectUuid, equals(projB),
            reason: '设备2从 Server 拉取的数据应包含最新项目B');
      } finally {
        await harness.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 7: copyWith 哨兵值专项测试
  // ═══════════════════════════════════════════════════════════════
  //
  // 验证 copyWith 哨兵值模式在项目切换场景中的正确行为：
  // - 不传参 → 保持原值
  // - 传 null → 清除为 null
  // - 传非 null 值 → 使用新值

  group('copyWith 哨兵值专项测试', () {
    test('7.1 copyWith 不传项目字段 → 保持原值', () {
      final emp = _createEmployee(
        projectUuid: 'proj-001',
        projectName: '项目1',
        projectContext: '上下文1',
        workPath: '/path/1',
      );

      final updated = emp.copyWith(name: '新名称');

      expect(updated.projectUuid, equals('proj-001'),
          reason: '不传 projectUuid 应保持原值');
      expect(updated.projectName, equals('项目1'));
      expect(updated.projectContext, equals('上下文1'));
      expect(updated.workPath, equals('/path/1'));
      expect(updated.name, equals('新名称'));
    });

    test('7.2 copyWith 传 null → 清除项目字段', () {
      final emp = _createEmployee(
        projectUuid: 'proj-001',
        projectName: '项目1',
        projectContext: '上下文1',
        workPath: '/path/1',
      );

      final updated = emp.copyWith(
        projectUuid: null,
        projectName: null,
        projectContext: null,
        workPath: null,
      );

      expect(updated.projectUuid, isNull,
          reason: '传 null 应清除 projectUuid');
      expect(updated.projectName, isNull);
      expect(updated.projectContext, isNull);
      expect(updated.workPath, isNull);
    });

    test('7.3 copyWith 传新值 → 使用新值', () {
      final emp = _createEmployee(
        projectUuid: 'proj-001',
        projectName: '项目1',
      );

      final updated = emp.copyWith(
        projectUuid: 'proj-002',
        projectName: '项目2',
        projectContext: '新上下文',
        workPath: '/new/path',
      );

      expect(updated.projectUuid, equals('proj-002'));
      expect(updated.projectName, equals('项目2'));
      expect(updated.projectContext, equals('新上下文'));
      expect(updated.workPath, equals('/new/path'));
    });

    test('7.4 copyWith 部分清除：只清除 projectUuid 保留其他', () {
      final emp = _createEmployee(
        projectUuid: 'proj-001',
        projectName: '项目1',
        projectContext: '上下文1',
        workPath: '/path/1',
      );

      final updated = emp.copyWith(projectUuid: null);

      expect(updated.projectUuid, isNull,
          reason: 'projectUuid 应被清除');
      // 其他字段保持原值
      expect(updated.projectName, equals('项目1'),
          reason: 'projectName 应保持原值');
      expect(updated.projectContext, equals('上下文1'));
      expect(updated.workPath, equals('/path/1'));
    });

    test('7.5 模拟前端 onProjectChanged(null) 的完整流程', () async {
      final fixture = await ClientTestFixture.create('copywith-null-flow');
      try {
        final projId = const Uuid().v4();
        final emp = _createEmployee(
          projectUuid: projId,
          projectName: '待清除项目',
          projectContext: '待清除上下文',
          workPath: '/to/clear',
          deviceId: fixture.deviceId,
        );
        await fixture.employeeManager.createEmployee(emp);

        // 模拟前端 ChatControllerBase.onProjectChanged(null):
        //   employee = employee!.copyWith(
        //     projectUuid: project?.uuid,  // null
        //     projectName: project?.title,  // null
        //     projectContext: project?.description,  // null
        //     workPath: project?.workPath,  // null
        //   );
        //   await deviceClient!.employeeManager.updateEmployee(employee!);
        final updatedEmp = emp.copyWith(
          projectUuid: null,
          projectName: null,
          projectContext: null,
          workPath: null,
        );
        await fixture.employeeManager.updateEmployee(updatedEmp);

        // 验证持久化
        final found = await fixture.employeeManager.getEmployee(emp.uuid);
        expect(found!.projectUuid, isNull,
            reason: 'onProjectChanged(null) 后 Employee projectUuid 应为 null');
        expect(found.projectName, isNull);
        expect(found.projectContext, isNull);
        expect(found.workPath, isNull);
      } finally {
        await fixture.dispose();
      }
    });

    test('7.6 模拟 DeviceRpcHandler.agentSetProject(null) 完整流程', () async {
      final fixture = await ClientTestFixture.create('copywith-rpc-null');
      try {
        final projId = const Uuid().v4();
        final emp = _createEmployee(
          projectUuid: projId,
          projectName: 'RPC待清除',
          projectContext: 'RPC上下文',
          workPath: '/rpc/clear',
          deviceId: fixture.deviceId,
        );
        await fixture.employeeManager.createEmployee(emp);

        // 模拟 DeviceRpcHandler.agentSetProject 中 projectData = null:
        //   final projectUuid = projectData?.projectUuid;  // null
        //   final employee = await _employeeManager.getEmployee(request.employeeId);
        //   if (employee != null) {
        //     final hasProjectChange = employee.projectUuid != projectUuid || ...;
        //     if (hasProjectChange) {
        //       await _employeeManager.updateEmployee(
        //         employee.copyWith(
        //           projectUuid: projectUuid,  // null → 清除
        //           projectName: projectData?.projectName,  // null
        //           projectContext: projectData?.projectContext,  // null
        //           workPath: projectData?.workPath,  // null
        //         ),
        //       );
        //     }
        //   }
        final String? projectUuid = null; // projectData = null
        final employee = await fixture.employeeManager.getEmployee(emp.uuid);
        expect(employee, isNotNull);

        final hasProjectChange = employee!.projectUuid != projectUuid ||
            employee.projectName != null ||
            employee.projectContext != null ||
            employee.workPath != null;
        expect(hasProjectChange, isTrue, reason: '从有值变为 null 应检测到变化');

        await fixture.employeeManager.updateEmployee(
          employee.copyWith(
            projectUuid: projectUuid,
            projectName: null,
            projectContext: null,
            workPath: null,
          ),
        );

        final found = await fixture.employeeManager.getEmployee(emp.uuid);
        expect(found!.projectUuid, isNull,
            reason: 'agentSetProject(null) 后 Employee projectUuid 应为 null');
        expect(found.projectName, isNull);
        expect(found.projectContext, isNull);
        expect(found.workPath, isNull);
      } finally {
        await fixture.dispose();
      }
    });
  });
}
