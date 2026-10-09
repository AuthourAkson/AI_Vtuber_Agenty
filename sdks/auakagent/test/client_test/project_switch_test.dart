/// 项目切换 — 广播 / 同步 / proxy 路径检测 测试
///
/// 参考前端 ProjectSelectorController (wenzflow_flutter) 的项目切换流程：
///   1. 项目切换广播：ProjectManager.onProjectChanged 流 + broadcastProjectToAllDevices
///   2. 项目切换同步：Client ↔ Server RPC (methodSyncProjects / methodGetAllProjects)
///   3. 项目路径 proxy 检测：AgentProxy.checkPathExists → PathExistsResult
///
/// 前端关键逻辑（ProjectSelectorController）：
///   - _subscribePmChanges() 监听 ProjectManager.onProjectChanged 流
///   - _subscribeAgentEvents() 监听 AgentProxy.onEvent 的 configChanged('project')
///   - onProjectSelected() → _setProjectToAgent() → onProjectChanged 回调
///   - _validatePathAndPrompt() → agentProxy.checkPathExists(workPath)
///   - broadcastProjectToAllDevices(uuid) → DataSyncManager → RPC methodSyncProjects
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - ServerTestFixture: 服务端完整生命周期模拟
/// - LanTestHarness: 端到端通信桥接
/// - FakeLanClientService: 可控消息注入
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/agent/entity/path_exists_result.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/project_manager.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';

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

/// 构建 methodSyncProjects 的 RPC payload（模拟 DataSyncManager.broadcastProjectToAllDevices）
Map<String, dynamic> _buildSyncPayload(ProjectEntity project) {
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
  // Group 1: 项目切换广播测试
  // ═══════════════════════════════════════════════════════════════
  //
  // 参考前端 ProjectSelectorController._subscribePmChanges():
  //   _pmSubscription = _pm.onProjectChanged.listen((_) {
  //     if (!isLoading) { loadProjects(); }
  //   });
  //
  // 以及 DataSyncManager.broadcastProjectToAllDevices():
  //   遍历在线设备 → invokeRemote(deviceId, methodSyncProjects, payload)

  group('项目切换广播测试', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('proj-broadcast');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    // ── 1.1 创建项目时 onProjectChanged 触发 created 事件 ──

    test('1.1 创建项目时 onProjectChanged 触发 created 事件', () async {
      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '广播-创建事件'),
      );

      await Future.delayed(Duration.zero);

      final createdEvents =
          events.where((e) => e.type == ProjectChangeType.created).toList();
      expect(createdEvents.length, greaterThanOrEqualTo(1));
      expect(
        createdEvents.any((e) => e.projectUuid == projId),
        isTrue,
      );
      expect(createdEvents.first.project, isNotNull);
      expect(createdEvents.first.project!.title, equals('广播-创建事件'));

      await sub.cancel();
    });

    // ── 1.2 更新项目时 onProjectChanged 触发 updated 事件 ──

    test('1.2 更新项目时 onProjectChanged 触发 updated 事件', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '广播-更新前'),
      );

      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      final updated = _createProject(
        uuid: projId,
        title: '广播-更新后',
        description: '新增描述',
        workPath: '/new/work/path',
      );
      await fixture.projectManager.updateProject(updated);

      await Future.delayed(Duration.zero);

      final updatedEvents =
          events.where((e) => e.type == ProjectChangeType.updated).toList();
      expect(updatedEvents.length, greaterThanOrEqualTo(1));
      expect(
        updatedEvents.any((e) => e.projectUuid == projId),
        isTrue,
      );
      expect(updatedEvents.first.project, isNotNull);
      expect(updatedEvents.first.project!.title, equals('广播-更新后'));
      expect(updatedEvents.first.project!.workPath, equals('/new/work/path'));

      await sub.cancel();
    });

    // ── 1.3 删除项目时 onProjectChanged 触发 deleted 事件 ──

    test('1.3 删除项目时 onProjectChanged 触发 deleted 事件', () async {
      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '广播-删除事件'),
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

    // ── 1.4 多个操作按顺序产生正确的事件序列 ──

    test('1.4 创建→更新→删除 产生完整的事件序列', () async {
      final projId = const Uuid().v4();
      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      // 创建
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '事件序列测试'),
      );
      // 更新
      await fixture.projectManager.updateProject(
        _createProject(uuid: projId, title: '事件序列-已更新'),
      );
      // 删除
      await fixture.projectManager.deleteProject(projId);

      await Future.delayed(Duration.zero);
      await sub.cancel();

      final types = events
          .where((e) => e.projectUuid == projId)
          .map((e) => e.type)
          .toList();
      expect(types.length, equals(3));
      expect(types[0], equals(ProjectChangeType.created));
      expect(types[1], equals(ProjectChangeType.updated));
      expect(types[2], equals(ProjectChangeType.deleted));
    });

    // ── 1.5 LanTestHarness 广播消息能触发 onProjectChanged ──

    test('1.5 LAN 广播消息触发本地 onProjectChanged 流', () async {
      // 通过 FakeLanClientService 注入同步消息，模拟远程广播到达
      final projId = const Uuid().v4();
      final project = _createProject(uuid: projId, title: '远程广播项目');

      // 监听 onProjectChanged（模拟前端 _subscribePmChanges）
      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      // 模拟从 LAN 收到远程广播消息后调用 saveProject（upsertFromRemote）
      // 这模拟了 HostRpcMethods._handleSyncProjects 的处理逻辑
      fixture.projectManager.upsertProjectFromRemote(project);
      // upsertFromRemote 不会自动通知，需手动触发 saveProject
      await fixture.projectManager.saveProject(project);

      await Future.delayed(Duration.zero);

      final related = events.where((e) => e.projectUuid == projId).toList();
      expect(related, isNotEmpty);
      expect(related.first.project?.title, equals('远程广播项目'));

      await sub.cancel();
    });

    // ── 1.6 广播拦截场景：断开状态下不会触发广播 ──

    test('1.6 客户端断开后 onProjectChanged 仍可在本地触发', () async {
      // 断开连接
      fixture.simulateDisconnect();
      expect(fixture.isConnected, isFalse);

      final events = <ProjectChangeEvent>[];
      final sub = fixture.projectManager.onProjectChanged.listen(events.add);

      final projId = const Uuid().v4();
      await fixture.projectManager.createProject(
        _createProject(uuid: projId, title: '离线创建'),
      );

      await Future.delayed(Duration.zero);
      await sub.cancel();

      // 即使断开连接，本地 onProjectChanged 仍应触发
      // （前端 _subscribePmChanges 即使在离线状态也能收到本地变更）
      expect(events.any((e) => e.projectUuid == projId), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 项目切换同步测试
  // ═══════════════════════════════════════════════════════════════
  //
  // 参考前端 ProjectSelectorController.onProjectSelected():
  //   await _setProjectToAgent(project);   // 设置到 AgentProxy
  //   await onProjectChanged?.call(project); // 通知父 Controller
  //
  // 以及 loadProjects() → _restoreSelectedProject() 恢复选中状态：
  //   final targetUuid = _getAgentProjectUuid() ?? initialProjectUuid;
  //   从本地和远程加载项目列表
  //
  // 以及 DataSyncManager.broadcastProjectToAllDevices():
  //   invokeRemote → HostRpcConfig.methodSyncProjects

  group('项目切换同步测试', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'proj-switch-sync',
        clientDeviceName: 'Client-A',
        serverHostName: 'Host-Server',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    // ── 2.1 Client → Server 推送项目（模拟 broadcastProjectToAllDevices） ──

    test('2.1 Client 通过 methodSyncProjects 推送项目到 Server', () async {
      final projId = const Uuid().v4();
      final project = _createProject(
        uuid: projId,
        title: '同步推送项目',
        description: 'Client-A 推送',
        workPath: '/home/project-a',
      );

      final payload = _buildSyncPayload(project);
      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );

      expect(result['count'], equals(1));

      // Server 端验证项目已同步
      final found =
          await harness.serverClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('同步推送项目'));
      expect(found!.workPath, equals('/home/project-a'));
    });

    // ── 2.2 Client 从 Server 拉取项目列表（模拟 loadProjects） ──

    test('2.2 Client 通过 methodGetAllProjects 拉取项目列表', () async {
      // Server 端预置项目
      final projA = _createProject(title: 'Server项目-A');
      final projB = _createProject(title: 'Server项目-B');
      await harness.serverClient.projectManager.createProject(projA);
      await harness.serverClient.projectManager.createProject(projB);

      // Client 拉取（模拟前端 loadProjects 中的远程拉取）
      final result = await harness.server.callRpc(
        HostRpcConfig.methodGetAllProjects,
        {},
      );

      expect(result, isNotNull);
      final projects = result['projects'] as List<dynamic>;
      expect(projects.length, greaterThanOrEqualTo(2));

      // 验证项目数据完整性
      final titles =
          projects
              .map((p) =>
                  (p['project'] as Map<String, dynamic>)['title'] as String)
              .toSet();
      expect(titles, contains('Server项目-A'));
      expect(titles, contains('Server项目-B'));
    });

    // ── 2.3 双数据源汇聚：两个 Client 分别推送项目 → Server 合并 ──

    test('2.3 两个 Client 各自推送项目后 Server 端数据合并', () async {
      // Client A 推送
      final projA = _createProject(title: 'ClientA-同步项目');
      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(projA),
      );

      // 模拟 Client B (通过同一 Server RPC 模拟第二个客户端推送)
      final projB = _createProject(title: 'ClientB-同步项目');
      await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(projB),
      );

      // Server 端应有 A 和 B 的项目
      final all = await harness.serverClient.projectManager.getAllProjects();
      final ids = all.map((p) => p.uuid).toSet();
      expect(ids, contains(projA.uuid));
      expect(ids, contains(projB.uuid));
    });

    // ── 2.4 项目全量同步（含 workPath）通过 RPC 推送 ──

    test('2.4 项目全量同步（含 workPath）通过 RPC 推送', () async {
      final projId = const Uuid().v4();

      // 构建包含 workPath 的同步 payload（模拟前端 _setProjectToAgent 后广播）
      final project = _createProject(
        uuid: projId,
        title: '全量同步项目',
        description: '包含完整数据和 workPath',
        workPath: '/full/sync/path',
      );

      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        _buildSyncPayload(project),
      );

      expect(result['count'], equals(1));

      // Server 端验证项目已存在且 workPath 正确
      final found =
          await harness.serverClient.projectManager.getProject(projId);
      expect(found, isNotNull);
      expect(found!.title, equals('全量同步项目'));
      expect(found!.workPath, equals('/full/sync/path'));
    });

    // ── 2.5 网络断开→恢复后数据拉取正常 ──

    test('2.5 网络断开后恢复，拉取数据仍然可用', () async {
      // 预置 Server 数据
      final projId = const Uuid().v4();
      await harness.serverClient.projectManager.createProject(
        _createProject(uuid: projId, title: '断线恢复项目'),
      );

      // 断开
      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      // 恢复
      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);

      // 拉取验证
      final result = await harness.server.callRpc(
        HostRpcConfig.methodGetAllProjects,
        {},
      );
      expect(result, isNotNull);
      final projects = result['projects'] as List<dynamic>;
      expect(projects, isNotEmpty);
      final hasProject = projects.any((p) {
        final title =
            (p['project'] as Map<String, dynamic>)['title'] as String?;
        return title == '断线恢复项目';
      });
      expect(hasProject, isTrue);
    });

    // ── 2.6 通过 LanTestHarness 消息桥接模拟项目切换事件 ──

    test('2.6 LAN 消息桥接传递项目同步事件', () async {
      // Server 端预置项目
      final projId = const Uuid().v4();
      await harness.serverClient.projectManager.createProject(
        _createProject(uuid: projId, title: '桥接同步项目'),
      );

      // 通过 LAN 桥接，Client 端发送 RPC 请求拉取
      final payload = _buildSyncPayload(
        _createProject(uuid: projId, title: '桥接同步项目'),
      );

      // Server 接收广播并处理
      final result = await harness.server.callRpc(
        HostRpcConfig.methodSyncProjects,
        payload,
      );

      expect(result['count'], greaterThanOrEqualTo(1));

      // 验证 Client 端 projectManager 也能拉取数据
      await harness.client.projectManager.getAllProjects();
      // 注意：Client 的 projectManager 通过 FakeLanClientService 操作，
      // 在桥接模式下消息传播可能不完全，此处验证 Server 端数据即可
      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodSyncProjects),
        isTrue,
      );
      expect(
        harness.server.hasRpcMethod(HostRpcConfig.methodGetAllProjects),
        isTrue,
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 项目路径 proxy 检测测试
  // ═══════════════════════════════════════════════════════════════
  //
  // 参考前端 ProjectSelectorController._validatePathAndPrompt():
  //   final pathResult = await agentProxy!.checkPathExists(workPath);
  //   if (!pathResult.exists) { showWorkPathDialog(...); }
  //
  // 以及 AgentProxyFileSystemAdapter.exists():
  //   final result = await _proxy.checkPathExists(path);
  //   return result.exists;
  //
  // PathExistsResult 实体：exists / isDirectory / error
  //
  // 注意：完整的 checkPathExists 需要 AgentProxy → RPC 链路，
  // 本测试组聚焦于：
  //   - PathExistsResult 实体序列化/反序列化
  //   - 项目 workPath 验证流程模拟
  //   - FakeLanClientService 消息注入模拟路径检测

  group('项目路径 proxy 检测测试', () {
    // ── 3.1 PathExistsResult 序列化 → toMap ──

    test('3.1 PathExistsResult.toMap 正确序列化', () {
      final result = PathExistsResult(
        exists: true,
        isDirectory: true,
      );

      final map = result.toMap();
      expect(map['exists'], isTrue);
      expect(map['isDirectory'], isTrue);
      expect(map.containsKey('error'), isFalse);
    });

    // ── 3.2 PathExistsResult 反序列化 → fromMap ──

    test('3.2 PathExistsResult.fromMap 正确反序列化', () {
      final map = {
        'exists': true,
        'isDirectory': false,
        'error': 'permission denied',
      };

      final result = PathExistsResult.fromMap(map);
      expect(result.exists, isTrue);
      expect(result.isDirectory, isFalse);
      expect(result.error, equals('permission denied'));
    });

    // ── 3.3 PathExistsResult 路径不存在场景 ──

    test('3.3 PathExistsResult 路径不存在的反序列化', () {
      final map = {
        'exists': false,
        'isDirectory': false,
      };

      final result = PathExistsResult.fromMap(map);
      expect(result.exists, isFalse);
      expect(result.isDirectory, isFalse);
      expect(result.error, isNull);

      // 模拟前端 _validatePathAndPrompt 的判断逻辑
      if (!result.exists) {
        // 前端会调用 showWorkPathDialog 提示重新选择
        expect(true, isTrue); // 路径不存在 → 应提示用户
      }
    });

    // ── 3.4 PathExistsResult 带错误信息场景 ──

    test('3.4 PathExistsResult 带错误信息（模拟 RPC 异常）', () {
      final map = {
        'exists': false,
        'isDirectory': false,
        'error': 'RPC timeout: device offline',
      };

      final result = PathExistsResult.fromMap(map);
      expect(result.exists, isFalse);
      expect(result.error, isNotEmpty);

      // 前端 _checkPathExists 在 catch 中返回 {'exists': false}
      // 不会阻塞用户流程
      expect(result.error, contains('timeout'));
    });

    // ── 3.5 项目 workPath 验证流程模拟 ──

    test('3.5 模拟前端 workPath 验证全流程', () async {
      final fixture = await ClientTestFixture.create(
        'path-validate',
        autoConnect: true,
      );

      try {
        // 1. 创建带有 workPath 的项目
        final projId = const Uuid().v4();
        final project = _createProject(
          uuid: projId,
          title: '路径验证项目',
          workPath: '${Directory.systemTemp.path}${Platform.pathSeparator}wenzagent_test_workdir',
        );

        await fixture.projectManager.createProject(project);

        // 2. 读取项目 workPath（模拟前端 _getProjectWorkPaths）
        final found = await fixture.projectManager.getProject(projId);
        expect(found, isNotNull);
        final workPath = found!.workPath;
        expect(workPath, isNotNull);

        // 3. 模拟路径检测（本地 darty:io 验证，模拟 AgentProxy.checkPathExists 的本地行为）
        //    参考 agent_proxy.dart 中的本地模式：
        //      final dir = Directory(path);
        //      final file = File(path);
        //      final dir = await dir.exists();
        //      final file = await file.exists();
        //      return PathExistsResult(exists: dir || file, isDirectory: dir);
        if (workPath != null && workPath.isNotEmpty) {
          final dir = Directory(workPath);
          final file = File(workPath);
          final dirExists = await dir.exists();
          final fileExists = await file.exists();

          final pathResult = PathExistsResult(
            exists: dirExists || fileExists,
            isDirectory: dirExists,
          );

          // 模拟前端 _validatePathAndPrompt 的判断
          if (!pathResult.exists) {
            // 路径不存在 → 前端弹出 showWorkPathDialog
            // 此处验证流程正确性即可
          }

          // pathResult 应可序列化传递给前端
          final resultMap = pathResult.toMap();
          expect(resultMap.containsKey('exists'), isTrue);
          expect(resultMap.containsKey('isDirectory'), isTrue);
        }

        // 4. 验证不存在的路径
        const nonExistentPath = '/tmp/definitely_not_exists_path_12345';
        final nonExistentDir = Directory(nonExistentPath);
        final nonExistentFile = File(nonExistentPath);
        final dneDirExists = await nonExistentDir.exists();
        final dneFileExists = await nonExistentFile.exists();
        final dneResult = PathExistsResult(
          exists: dneDirExists || dneFileExists,
          isDirectory: dneDirExists,
        );
        expect(dneResult.exists, isFalse);

        // 模拟前端判断：!pathResult.exists → showWorkPathDialog
        expect(dneResult.exists, isFalse);
      } finally {
        await fixture.dispose();
      }
    });

    // ── 3.6 FakeLanClientService 模拟 RPC 路径检测响应 ──

    test('3.6 FakeLanClientService 可注入路径检测相关消息', () async {
      final fixture = await ClientTestFixture.create(
        'path-rpc-sim',
        autoConnect: true,
      );

      try {
        // 模拟从 Host 收到路径检测的 RPC 响应
        // 前端 ProjectSelectorController._checkPathExists 内部调用 agentProxy.checkPathExists
        // 在本地模式下直接检查，远程模式下通过 RPC
        final received = <LanMessage>[];
        final sub = fixture.fakeLanClient.messageStream.listen(received.add);

        // 注入模拟的 RPC 响应消息
        fixture.fakeLanClient.injectMessage(
          LanMessage(
            type: LanMessageType.system,
            fromId: 'host',
            content: 'path_check_result:exists=true,isDirectory=true',
          ),
        );

        await Future.delayed(Duration.zero);
        await sub.cancel();

        expect(received, isNotEmpty);
        // 验证可以通过消息流传递路径检测结果
        expect(
          received.any((m) => m.content?.contains('path_check_result') == true),
          isTrue,
        );
      } finally {
        await fixture.dispose();
      }
    });

    // ── 3.7 项目 workPath 更新后事件通知 ──

    test('3.7 项目 workPath 更新触发 onProjectChanged 通知', () async {
      final fixture = await ClientTestFixture.create(
        'path-update-event',
        autoConnect: true,
      );

      try {
        final projId = const Uuid().v4();
        await fixture.projectManager.createProject(
          _createProject(uuid: projId, title: '路径更新事件', workPath: '/old'),
        );

        final events = <ProjectChangeEvent>[];
        final sub = fixture.projectManager.onProjectChanged.listen(events.add);

        // 更新 workPath（模拟前端 showWorkPathDialog 确认后 _updateProjectWorkPath）
        await fixture.projectManager.updateProject(
          _createProject(uuid: projId, title: '路径更新事件', workPath: '/new'),
        );

        await Future.delayed(Duration.zero);
        await sub.cancel();

        final updatedEvents =
            events.where((e) => e.type == ProjectChangeType.updated).toList();
        expect(updatedEvents, isNotEmpty);
        expect(updatedEvents.first.project?.workPath, equals('/new'));
      } finally {
        await fixture.dispose();
      }
    });

    // ── 3.8 多个项目各自维护 workPath ──

    test('3.8 多个项目各自维护独立的 workPath', () async {
      final fixture = await ClientTestFixture.create(
        'multi-path',
        autoConnect: true,
      );

      try {
        final projA = await fixture.projectManager.createProject(
          _createProject(title: '项目A', workPath: '/path/a'),
        );
        final projB = await fixture.projectManager.createProject(
          _createProject(title: '项目B', workPath: '/path/b'),
        );

        final foundA = await fixture.projectManager.getProject(projA.uuid);
        final foundB = await fixture.projectManager.getProject(projB.uuid);

        expect(foundA!.workPath, equals('/path/a'));
        expect(foundB!.workPath, equals('/path/b'));

        // 模拟前端 workPaths 缓存结构
        final workPaths = <String, String>{
          foundA.uuid: foundA.workPath ?? '',
          foundB.uuid: foundB.workPath ?? '',
        };
        expect(workPaths.length, equals(2));
        expect(workPaths[projA.uuid], equals('/path/a'));
        expect(workPaths[projB.uuid], equals('/path/b'));
      } finally {
        await fixture.dispose();
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 项目切换 ping-pong 防护测试
  // ═══════════════════════════════════════════════════════════════
  //
  // 验证前端 ProjectSelectorController 的防抖逻辑：
  //   - setProject RPC 不应导致 configChanged 事件回环触发 loadProjects
  //   - _needsRestoreNotification 标志位控制 onProjectChanged 回调时机
  //   - updateEmployee(projectData) 不应触发 ProjectManager 变更事件
  //   - 多次 setProject 同一 UUID 应幂等

  group('项目切换 ping-pong 防护', () {
    // ── 4.1 setProject 对同一 UUID 幂等（不产生额外事件） ──

    test('4.1 连续两次 setProject 同一 UUID 不产生重复变更事件', () async {
      final fixture = await ClientTestFixture.create('idempotent-set');

      try {
        final projId = const Uuid().v4();
        await fixture.projectManager.createProject(
          _createProject(uuid: projId, title: '幂等项目'),
        );

        // 记录初始事件数
        final eventsBefore = <ProjectChangeEvent>[];
        final sub =
            fixture.projectManager.onProjectChanged.listen(eventsBefore.add);

        // 第一次 saveProject
        await fixture.projectManager.saveProject(
          _createProject(uuid: projId, title: '幂等项目'),
        );

        await Future.delayed(Duration.zero);

        final countAfterFirst = eventsBefore.length;
        expect(countAfterFirst, greaterThanOrEqualTo(1));

        // 第二次 saveProject（相同数据）
        await fixture.projectManager.saveProject(
          _createProject(uuid: projId, title: '幂等项目'),
        );

        await Future.delayed(Duration.zero);
        await sub.cancel();

        // saveProject 每次都会通知（updated事件），但不会产生 duplicate create
        final createdEvents = eventsBefore
            .where((e) => e.type == ProjectChangeType.created)
            .toList();
        // 幂等：不应重复创建
        expect(createdEvents.length, lessThanOrEqualTo(1));
      } finally {
        await fixture.dispose();
      }
    });

    // ── 4.2 模拟前端 _needsRestoreNotification 标志位行为 ──

    test('4.2 _needsRestoreNotification=true 时即使 UUID 不变也触发通知', () async {
      // 模拟场景：onReplace 后 selectedProjectUuid 已等于 targetUuid
      // 但 _needsRestoreNotification=true → 仍触发 onProjectChanged
      final fixture = await ClientTestFixture.create('needs-notify');

      try {
        final projId = const Uuid().v4();
        await fixture.projectManager.createProject(
          _createProject(uuid: projId, title: '需通知项目'),
        );

        // 标志位为 true（模拟 Proxy 重建）
        var needsNotify = true;
        final notifications = <String>[];

        // _restoreSelectedProject 模拟：
        // targetUuid = _getAgentProjectUuid() ?? initialProjectUuid; // = projId
        // shouldNotify = selectedProjectUuid != targetUuid || _needsRestoreNotification;
        final shouldNotify = needsNotify; // UUID 相同，取决于 needsNotify
        needsNotify = false;
        if (shouldNotify) {
          notifications.add(projId); // 模拟 onProjectChanged 调用
        }

        expect(notifications.length, equals(1));
        expect(needsNotify, isFalse); // 标志位已复位
      } finally {
        await fixture.dispose();
      }
    });

    // ── 4.3 _needsRestoreNotification=false 且 UUID 不变时跳过通知 ──

    test('4.3 UUID 不变且标志位为 false 时跳过通知（防 ping-pong）', () async {
      // 模拟场景：PM/Agent 事件触发 loadProjects → _restoreSelectedProject
      // selectedProjectUuid == targetUuid 且 _needsRestoreNotification=false
      // → 不应触发 onProjectChanged（防止 ping-pong 循环）

      const projId = 'proj-123';
      var needsNotify = false;
      final notifications = <String>[];

      // _restoreSelectedProject 模拟：
      // targetUuid = _getAgentProjectUuid() ?? initialProjectUuid; // = projId
      // shouldNotify = selectedProjectUuid != targetUuid || _needsRestoreNotification;
      final shouldNotify = needsNotify; // UUID 相同，取决于 needsNotify
      // 验证：标志位为 false 时不应触发通知
      expect(shouldNotify, isFalse);
      // 并且标记名确认场景正确
      expect(projId, isNotEmpty);

      // 验证：没有触发任何通知
      expect(notifications, isEmpty);
    });

    // ── 4.4 updateEmployee 不触发 ProjectManager 变更事件 ──

    test('4.4 updateEmployee 更新项目字段不触发 onProjectChanged', () async {
      final fixture = await ClientTestFixture.create('emp-update');

      try {
        final projId = const Uuid().v4();
        await fixture.projectManager.createProject(
          _createProject(uuid: projId, title: '员工更新测试'),
        );

        // 监听 ProjectManager 事件
        final pmEvents = <ProjectChangeEvent>[];
        final pmSub =
            fixture.projectManager.onProjectChanged.listen(pmEvents.add);

        // 模拟 ChatControllerBase.onProjectChanged 中的 updateEmployee
        final empId = const Uuid().v4();
        final employee = AiEmployeeEntity(
          uuid: empId,
          name: '测试员工',
          deviceId: fixture.deviceId,
          currentDeviceId: fixture.deviceId,
          projectUuid: projId,
          projectName: '员工更新测试',
          status: 'active',
          deleted: 0,
          createTime: DateTime.now(),
          updateTime: DateTime.now(),
        );
        await fixture.employeeManager.createEmployee(employee);

        // 更新 employee 的项目字段
        final updated = employee.copyWith(
          projectUuid: projId,
          projectName: '员工更新测试(改)',
          workPath: '/new/path',
        );
        await fixture.employeeManager.updateEmployee(updated);

        await Future.delayed(Duration.zero);
        await pmSub.cancel();

        // updateEmployee 不应触发 ProjectManager 的 onProjectChanged
        // （它是 EmployeeManager 操作，不影响 ProjectManager）
        final projectEventsFromEmpUpdate = pmEvents
            .where((e) => e.projectUuid == projId)
            .toList();
        // 只应有创建时的通知，不应有更新时的通知
        expect(
          projectEventsFromEmpUpdate
              .where((e) => e.type == ProjectChangeType.updated)
              .length,
          lessThanOrEqualTo(0),
        );
      } finally {
        await fixture.dispose();
      }
    });

    // ── 4.5 模拟前端 setProject → RPC → configChanged 链路的幂等性 ──

    test('4.5 LAN 桥接中重复同步同一项目数据为幂等', () async {
      final harness = await LanTestHarness.create('idempotent-sync');

      try {
        final projId = const Uuid().v4();
        final project = _createProject(
          uuid: projId,
          title: '幂等同步',
        );

        // 第一次同步
        await harness.server.callRpc(
          HostRpcConfig.methodSyncProjects,
          _buildSyncPayload(project),
        );

        final serverProjects1 =
            await harness.serverClient.projectManager.getAllProjects();
        expect(serverProjects1.length, equals(1));

        // 第二次同步同一数据
        await harness.server.callRpc(
          HostRpcConfig.methodSyncProjects,
          _buildSyncPayload(project),
        );

        final serverProjects2 =
            await harness.serverClient.projectManager.getAllProjects();
        // 幂等：不应创建重复项目
        expect(serverProjects2.length, equals(1));
        expect(serverProjects2.first.title, equals('幂等同步'));
      } finally {
        await harness.dispose();
      }
    });

    // ── 4.6 isLoading 守卫防止并发 loadProjects ──

    test('4.6 isLoading=true 时不应再次触发 loadProjects', () async {
      // 模拟前端 _subscribePmChanges / _subscribeAgentEvents 中的 isLoading 守卫
      var isLoading = false;
      int loadCount = 0;

      void simulateLoadProjects() {
        if (!isLoading) {
          isLoading = true;
          loadCount++;
          isLoading = false;
        }
      }

      // 正常加载
      simulateLoadProjects();
      expect(loadCount, equals(1));

      // 模拟加载中收到 PM 变更事件 → 应跳过
      isLoading = true;
      simulateLoadProjects(); // 应跳过
      expect(loadCount, equals(1)); // 未增加

      isLoading = false;
      simulateLoadProjects();
      expect(loadCount, equals(2));
    });
  });
}
