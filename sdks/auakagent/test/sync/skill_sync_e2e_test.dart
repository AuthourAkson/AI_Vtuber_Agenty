/// Skill 同步 E2E 测试
///
/// 启动真实的 WebSocket Server + 两个 Client，验证完整的 Skill 同步流程：
///   设备 A (操作方) → WebSocket → Server (中转) → 设备 B (接收方)
///
/// 测试覆盖：
///   1. 员工级技能（AiEmployeeSkillEntity）同步
///     - 创建同步：A 创建 → 广播 → B 收到
///     - 更新同步：A 更新 → 广播 → B 收到新版本
///     - 删除同步：A 删除 → 广播 → B 软删除
///     - 拉取同步：B 上线后从 A 拉取全量技能
///     - 冲突合并：A/B 同时更新 → 以 updateTime 更晚的为准
///     - Folder 技能同步
///     - MCP 技能同步
///     - 批量同步：混合类型
///
///   2. 全局技能（GlobalSkillEntity）同步
///     - 创建/删除同步
///     - 拉取同步
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/host/client_session_manager.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/lan/entity/client_info.dart';
import 'package:auakagent/src/lan/impl/lan_client_service_impl.dart';
import 'package:auakagent/src/lan/impl/lan_host_service_impl.dart';
import 'package:auakagent/src/lan/lan_client_service.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/persistence/store_merge_util.dart';
import 'package:auakagent/src/rpc/remote_call_manager.dart';
import 'package:auakagent/src/rpc/remote_call_server.dart';
import 'package:auakagent/src/service/global_skill_manager.dart';
import 'package:auakagent/src/service/service.dart';
import 'package:auakagent/src/utils/logger.dart';

int _testCounter = 0;

// ═══════════════════════════════════════════════════════════════
// 桥接 LanClientService
// ═══════════════════════════════════════════════════════════════

class _BridgeLanClientService implements LanClientService {
  final LanClientService _realClient;
  final String _overrideDeviceId;

  _BridgeLanClientService({
    required LanClientService realClient,
    required String overrideDeviceId,
  })  : _realClient = realClient,
        _overrideDeviceId = overrideDeviceId;

  @override
  bool get isConnected => _realClient.isConnected;
  @override
  bool get isConnecting => _realClient.isConnecting;
  @override
  String get deviceId => _overrideDeviceId;
  @override
  String? get topic => _realClient.topic;
  @override
  String? get hostIp => _realClient.hostIp;
  @override
  int get hostPort => _realClient.hostPort;
  @override
  double get uploadProgress => _realClient.uploadProgress;
  @override
  double get downloadProgress => _realClient.downloadProgress;
  @override
  Stream<LanMessage> get messageStream => _realClient.messageStream;
  @override
  Future<void> connect(String hostIp, {int port = 9090}) =>
      _realClient.connect(hostIp, port: port);
  @override
  Future<void> disconnect() => _realClient.disconnect();
  @override
  Future<void> reconnect() => _realClient.reconnect();
  @override
  void sendMessage(String content) => _realClient.sendMessage(content);
  @override
  Future<bool> sendLanMessage(LanMessage message) =>
      _realClient.sendLanMessage(message);
  @override
  Future<String> uploadFile(String filePath) => _realClient.uploadFile(filePath);
  @override
  Future<void> downloadFile(String fileId, String savePath) =>
      _realClient.downloadFile(fileId, savePath);
  @override
  Future<ClientInfo> getClientInfo() => _realClient.getClientInfo();
  @override
  void sendBinaryMessage(dynamic data) => _realClient.sendBinaryMessage(data);
  @override
  Stream<BinaryChunkEvent> get binaryChunkStream =>
      _realClient.binaryChunkStream;
}

// ═══════════════════════════════════════════════════════════════
// 测试辅助
// ═══════════════════════════════════════════════════════════════

/// 每个测试用例共享的上下文资源
class _TestContext {
  final String deviceIdA;
  final String deviceIdB;
  final String testDbPathA;
  final String testDbPathB;
  final LanClientServiceImpl clientA;
  final LanClientServiceImpl clientB;
  final RemoteCallManager rpcManagerA;
  final RemoteCallServer rpcServerA;
  final RemoteCallManager rpcManagerB;
  final RemoteCallServer rpcServerB;
  final SkillManager skillManagerA;
  final SkillManager skillManagerB;
  final StreamSubscription<LanMessage> subA;
  final StreamSubscription<LanMessage> subB;

  _TestContext({
    required this.deviceIdA,
    required this.deviceIdB,
    required this.testDbPathA,
    required this.testDbPathB,
    required this.clientA,
    required this.clientB,
    required this.rpcManagerA,
    required this.rpcServerA,
    required this.rpcManagerB,
    required this.rpcServerB,
    required this.skillManagerA,
    required this.skillManagerB,
    required this.subA,
    required this.subB,
  });

  Future<void> dispose() async {
    await subA.cancel();
    await subB.cancel();
    rpcManagerA.dispose();
    rpcManagerB.dispose();
    rpcServerA.dispose();
    rpcServerB.dispose();
    await clientA.disconnect();
    await clientB.disconnect();
    await LanClientServiceImpl.dispose(deviceIdA);
    await LanClientServiceImpl.dispose(deviceIdB);
    (skillManagerA as SkillManagerImpl).dispose();
    (skillManagerB as SkillManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceIdA).close();
    await DatabaseManager.getInstance(deviceIdB).close();
    DatabaseManager.removeInstance(deviceIdA);
    DatabaseManager.removeInstance(deviceIdB);
    SkillManager.removeInstance(deviceIdA);
    SkillManager.removeInstance(deviceIdB);
    EmployeeManager.removeInstance(deviceIdA);
    EmployeeManager.removeInstance(deviceIdB);
    SessionManager.removeInstance(deviceIdA);
    SessionManager.removeInstance(deviceIdB);
    try {
      await Directory(testDbPathA).delete(recursive: true);
    } catch (_) {}
    try {
      await Directory(testDbPathB).delete(recursive: true);
    } catch (_) {}
  }
}

/// 全局技能测试的上下文资源
class _GlobalTestContext {
  final String deviceIdA;
  final String deviceIdB;
  final String testDbPathA;
  final String testDbPathB;
  final LanClientServiceImpl clientA;
  final LanClientServiceImpl clientB;
  final RemoteCallManager rpcManagerA;
  final RemoteCallServer rpcServerA;
  final RemoteCallManager rpcManagerB;
  final RemoteCallServer rpcServerB;
  final GlobalSkillManager globalSkillManagerA;
  final GlobalSkillManager globalSkillManagerB;
  final StreamSubscription<LanMessage> subA;
  final StreamSubscription<LanMessage> subB;

  _GlobalTestContext({
    required this.deviceIdA,
    required this.deviceIdB,
    required this.testDbPathA,
    required this.testDbPathB,
    required this.clientA,
    required this.clientB,
    required this.rpcManagerA,
    required this.rpcServerA,
    required this.rpcManagerB,
    required this.rpcServerB,
    required this.globalSkillManagerA,
    required this.globalSkillManagerB,
    required this.subA,
    required this.subB,
  });

  Future<void> dispose() async {
    await subA.cancel();
    await subB.cancel();
    rpcManagerA.dispose();
    rpcManagerB.dispose();
    rpcServerA.dispose();
    rpcServerB.dispose();
    await clientA.disconnect();
    await clientB.disconnect();
    await LanClientServiceImpl.dispose(deviceIdA);
    await LanClientServiceImpl.dispose(deviceIdB);
    (globalSkillManagerA as GlobalSkillManagerImpl).dispose();
    (globalSkillManagerB as GlobalSkillManagerImpl).dispose();
    await DatabaseManager.getInstance(deviceIdA).close();
    await DatabaseManager.getInstance(deviceIdB).close();
    DatabaseManager.removeInstance(deviceIdA);
    DatabaseManager.removeInstance(deviceIdB);
    GlobalSkillManager.removeInstance(deviceIdA);
    GlobalSkillManager.removeInstance(deviceIdB);
    SkillManager.removeInstance(deviceIdA);
    SkillManager.removeInstance(deviceIdB);
    EmployeeManager.removeInstance(deviceIdA);
    EmployeeManager.removeInstance(deviceIdB);
    SessionManager.removeInstance(deviceIdA);
    SessionManager.removeInstance(deviceIdB);
    try {
      await Directory(testDbPathA).delete(recursive: true);
    } catch (_) {}
    try {
      await Directory(testDbPathB).delete(recursive: true);
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════
// 测试主体
// ═══════════════════════════════════════════════════════════════

void main() {
  Logger.level = LogLevel.warn;

  group('Skill 同步 E2E 测试', () {
    late LanHostServiceImpl server;
    late String tempDir;
    int groupCounter = 0;

    setUp(() async {
      groupCounter++;
      server = LanHostServiceImpl();
      tempDir =
          '${Directory.systemTemp.path}${p.separator}wenzagent_skill_e2e_$groupCounter';
      await Directory(tempDir).create(recursive: true);
      await server.start(port: 0, storageDir: tempDir);
    });

    tearDown(() async {
      await server.stop();
      try {
        await Directory(tempDir).delete(recursive: true);
      } catch (_) {}
    });

    // ── 辅助方法 ──

    Future<LanClientServiceImpl> createAndConnectClient(
      String deviceId,
      String topic,
      int serverPort,
    ) async {
      final client = LanClientServiceImpl(deviceId: deviceId, topic: topic);
      await client.connect('127.0.0.1', port: serverPort);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (true) {
        final registered = server.clients.any((c) => c.deviceId == deviceId);
        if (registered) break;
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException('等待 deviceId=$deviceId 注册超时');
        }
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return client;
    }

    Map<String, dynamic>? parsePayload(String? content) {
      if (content == null) return null;
      try {
        final contentData = jsonDecode(content) as Map<String, dynamic>;
        return contentData['payload'] as Map<String, dynamic>?;
      } catch (_) {
        return null;
      }
    }

    StreamSubscription<LanMessage> setupDispatch(
      LanClientServiceImpl client,
      RemoteCallManager rpcManager,
      RemoteCallServer rpcServer,
    ) {
      return client.messageStream.listen((msg) {
        if (msg.type == LanMessageType.rpcRequest) {
          // 收到 RPC 请求 → 转发给本地 rpcServer 处理
          final payload = parsePayload(msg.content);
          if (payload != null) {
            rpcServer.handleRequest(payload);
          }
        } else {
          // RPC 响应/错误/流 → 转发给 rpcManager
          final payload = parsePayload(msg.content);
          if (payload == null) return;
          switch (msg.type) {
            case LanMessageType.rpcResponse:
              rpcManager.handleResponse(payload);
            case LanMessageType.rpcStreamChunk:
              rpcManager.handleStreamChunk(payload);
            case LanMessageType.rpcStreamEnd:
              rpcManager.handleStreamEnd(payload);
            case LanMessageType.rpcError:
              rpcManager.handleError(payload);
            default:
              break;
          }
        }
      });
    }

    /// 创建员工级技能测试上下文（每个测试用例独立调用）
    Future<_TestContext> createEmployeeSkillContext() async {
      _testCounter++;
      final deviceIdA =
          'dev-skill-A-${const Uuid().v4().substring(0, 8)}';
      final deviceIdB =
          'dev-skill-B-${const Uuid().v4().substring(0, 8)}';
      final testDbPathA =
          '${Directory.systemTemp.path}/wenzagent_skill_e2e_a_$_testCounter';
      final testDbPathB =
          '${Directory.systemTemp.path}/wenzagent_skill_e2e_b_$_testCounter';
      await Directory(testDbPathA).create(recursive: true);
      await Directory(testDbPathB).create(recursive: true);

      await DatabaseManager.getInstance(deviceIdA).initialize(
        storagePath: testDbPathA,
      );
      await DatabaseManager.getInstance(deviceIdB).initialize(
        storagePath: testDbPathB,
      );

      final skillManagerA = SkillManager.getInstance(deviceIdA);
      final skillManagerB = SkillManager.getInstance(deviceIdB);

      final port = server.port!;
      final topic = 'skill-e2e-$_testCounter';
      final clientA = await createAndConnectClient(deviceIdA, topic, port);
      final clientB = await createAndConnectClient(deviceIdB, topic, port);

      final bridgeA = _BridgeLanClientService(
          realClient: clientA, overrideDeviceId: deviceIdA);
      final bridgeB = _BridgeLanClientService(
          realClient: clientB, overrideDeviceId: deviceIdB);

      final rpcManagerA = RemoteCallManager(
          clientService: bridgeA, localDeviceId: deviceIdA);
      final rpcServerA = RemoteCallServer(
          clientService: bridgeA, localDeviceId: deviceIdA);
      final rpcManagerB = RemoteCallManager(
          clientService: bridgeB, localDeviceId: deviceIdB);
      final rpcServerB = RemoteCallServer(
          clientService: bridgeB, localDeviceId: deviceIdB);

      // 注册 Host RPC 方法
      registerHostRpcMethods(
        rpcServer: rpcServerA,
        employeeManager: EmployeeManager.getInstance(deviceIdA),
        sessionManager: SessionManager.getInstance(deviceIdA),
        skillManager: skillManagerA,
        messageStore: MessageStoreService.getInstance(deviceIdA),
        clientSessionManager: ClientSessionManager(),
        projectManager: ProjectManager.getInstance(deviceIdA),
        globalSkillManager: GlobalSkillManager.getInstance(deviceIdA),
        deviceId: deviceIdA,
      );
      registerHostRpcMethods(
        rpcServer: rpcServerB,
        employeeManager: EmployeeManager.getInstance(deviceIdB),
        sessionManager: SessionManager.getInstance(deviceIdB),
        skillManager: skillManagerB,
        messageStore: MessageStoreService.getInstance(deviceIdB),
        clientSessionManager: ClientSessionManager(),
        projectManager: ProjectManager.getInstance(deviceIdB),
        globalSkillManager: GlobalSkillManager.getInstance(deviceIdB),
        deviceId: deviceIdB,
      );

      final subA = setupDispatch(clientA, rpcManagerA, rpcServerA);
      final subB = setupDispatch(clientB, rpcManagerB, rpcServerB);

      // 等待 RPC 注册完成和消息分发就绪
      await Future.delayed(const Duration(milliseconds: 200));

      return _TestContext(
        deviceIdA: deviceIdA,
        deviceIdB: deviceIdB,
        testDbPathA: testDbPathA,
        testDbPathB: testDbPathB,
        clientA: clientA,
        clientB: clientB,
        rpcManagerA: rpcManagerA,
        rpcServerA: rpcServerA,
        rpcManagerB: rpcManagerB,
        rpcServerB: rpcServerB,
        skillManagerA: skillManagerA,
        skillManagerB: skillManagerB,
        subA: subA,
        subB: subB,
      );
    }

    /// 创建全局技能测试上下文（每个测试用例独立调用）
    Future<_GlobalTestContext> createGlobalSkillContext() async {
      _testCounter++;
      final deviceIdA =
          'dev-gskill-A-${const Uuid().v4().substring(0, 8)}';
      final deviceIdB =
          'dev-gskill-B-${const Uuid().v4().substring(0, 8)}';
      final testDbPathA =
          '${Directory.systemTemp.path}/wenzagent_gskill_e2e_a_$_testCounter';
      final testDbPathB =
          '${Directory.systemTemp.path}/wenzagent_gskill_e2e_b_$_testCounter';
      await Directory(testDbPathA).create(recursive: true);
      await Directory(testDbPathB).create(recursive: true);

      await DatabaseManager.getInstance(deviceIdA).initialize(
        storagePath: testDbPathA,
      );
      await DatabaseManager.getInstance(deviceIdB).initialize(
        storagePath: testDbPathB,
      );

      final globalSkillManagerA = GlobalSkillManager.getInstance(deviceIdA);
      final globalSkillManagerB = GlobalSkillManager.getInstance(deviceIdB);

      final port = server.port!;
      final topic = 'gskill-e2e-$_testCounter';
      final clientA = await createAndConnectClient(deviceIdA, topic, port);
      final clientB = await createAndConnectClient(deviceIdB, topic, port);

      final bridgeA = _BridgeLanClientService(
          realClient: clientA, overrideDeviceId: deviceIdA);
      final bridgeB = _BridgeLanClientService(
          realClient: clientB, overrideDeviceId: deviceIdB);

      final rpcManagerA = RemoteCallManager(
          clientService: bridgeA, localDeviceId: deviceIdA);
      final rpcServerA = RemoteCallServer(
          clientService: bridgeA, localDeviceId: deviceIdA);
      final rpcManagerB = RemoteCallManager(
          clientService: bridgeB, localDeviceId: deviceIdB);
      final rpcServerB = RemoteCallServer(
          clientService: bridgeB, localDeviceId: deviceIdB);

      // 先注册完整 Host RPC（含员工级技能等）
      registerHostRpcMethods(
        rpcServer: rpcServerA,
        employeeManager: EmployeeManager.getInstance(deviceIdA),
        sessionManager: SessionManager.getInstance(deviceIdA),
        skillManager: SkillManager.getInstance(deviceIdA),
        messageStore: MessageStoreService.getInstance(deviceIdA),
        clientSessionManager: ClientSessionManager(),
        projectManager: ProjectManager.getInstance(deviceIdA),
        globalSkillManager: GlobalSkillManager.getInstance(deviceIdA),
        deviceId: deviceIdA,
      );
      registerHostRpcMethods(
        rpcServer: rpcServerB,
        employeeManager: EmployeeManager.getInstance(deviceIdB),
        sessionManager: SessionManager.getInstance(deviceIdB),
        skillManager: SkillManager.getInstance(deviceIdB),
        messageStore: MessageStoreService.getInstance(deviceIdB),
        clientSessionManager: ClientSessionManager(),
        projectManager: ProjectManager.getInstance(deviceIdB),
        globalSkillManager: GlobalSkillManager.getInstance(deviceIdB),
        deviceId: deviceIdB,
      );

      // 后注册全局技能 RPC（覆盖 registerHostRpcMethods 中的默认实例）
      _registerGlobalSkillRpc(rpcServerA, globalSkillManagerA);
      _registerGlobalSkillRpc(rpcServerB, globalSkillManagerB);

      final subA = setupDispatch(clientA, rpcManagerA, rpcServerA);
      final subB = setupDispatch(clientB, rpcManagerB, rpcServerB);

      // 等待 RPC 注册完成和消息分发就绪
      await Future.delayed(const Duration(milliseconds: 200));

      return _GlobalTestContext(
        deviceIdA: deviceIdA,
        deviceIdB: deviceIdB,
        testDbPathA: testDbPathA,
        testDbPathB: testDbPathB,
        clientA: clientA,
        clientB: clientB,
        rpcManagerA: rpcManagerA,
        rpcServerA: rpcServerA,
        rpcManagerB: rpcManagerB,
        rpcServerB: rpcServerB,
        globalSkillManagerA: globalSkillManagerA,
        globalSkillManagerB: globalSkillManagerB,
        subA: subA,
        subB: subB,
      );
    }

    AiEmployeeSkillEntity createSkill({
      String? uuid,
      String? employeeId,
      String? name,
      String skillType = 'config',
      String? config,
      int enabled = 1,
      int deleted = 0,
      DateTime? deleteTime,
      DateTime? createTime,
      DateTime? updateTime,
    }) {
      final now = DateTime.now();
      return AiEmployeeSkillEntity(
        uuid: uuid ?? const Uuid().v4(),
        employeeId: employeeId ?? 'emp-${const Uuid().v4().substring(0, 8)}',
        name: name ?? 'Test Skill',
        skillType: skillType,
        config: config,
        enabled: enabled,
        deleted: deleted,
        deleteTime: deleteTime,
        createTime: createTime ?? now,
        updateTime: updateTime ?? now,
      );
    }

    GlobalSkillEntity createGlobalSkill({
      String? uuid,
      String? name,
      String? description,
      String skillType = 'config',
      String? config,
      int enabled = 1,
      int deleted = 0,
      DateTime? deleteTime,
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
        deleted: deleted,
        deleteTime: deleteTime,
        createTime: createTime ?? now,
        updateTime: updateTime ?? now,
      );
    }

    // ══════════════════════════════════════════════════════════
    // 员工级技能同步测试
    // ══════════════════════════════════════════════════════════

    test('A 创建技能 → 广播(methodSyncSkills) → B 收到', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-create';
        final skillA = createSkill(
          employeeId: empId,
          name: 'E2E测试技能',
          skillType: 'config',
          config: jsonEncode({'prompt': '你好'}),
        );

        await ctx.skillManagerA.createSkill(skillA);
        final skillsA = await ctx.skillManagerA.getSkills(empId);
        final response = await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {'skills': skillsA.map((s) => s.toMap()).toList()},
          toDeviceId: ctx.deviceIdB,
        );

        final result = response['result'] as Map<String, dynamic>;
        expect(result['count'], equals(1));

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));
        expect(skillsB.first.name, equals('E2E测试技能'));
        expect(
            skillsB.first.config, equals(jsonEncode({'prompt': '你好'})));
      } finally {
        await ctx.dispose();
      }
    });

    test('A 更新技能 → 广播 → B 收到新版本', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-update';
        final now = DateTime.now();

        final skillA = createSkill(
          employeeId: empId,
          name: '原始技能',
          skillType: 'config',
          config: jsonEncode({'prompt': 'v1'}),
          updateTime: now.subtract(const Duration(hours: 1)),
        );
        await ctx.skillManagerA.createSkill(skillA);

        // 先同步到 B
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        // A 更新
        await ctx.skillManagerA.updateSkill(skillA.copyWith(
          name: '更新后技能',
          config: jsonEncode({'prompt': 'v2'}),
          updateTime: now,
        ));

        // 再次同步
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));
        expect(skillsB.first.name, equals('更新后技能'));
        expect(skillsB.first.config, equals(jsonEncode({'prompt': 'v2'})));
      } finally {
        await ctx.dispose();
      }
    });

    test('A 删除技能 → 广播带deleted=1 → B 软删除', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-delete';
        final now = DateTime.now();

        final skillA = createSkill(
          employeeId: empId,
          name: '待删除技能',
          skillType: 'config',
        );
        await ctx.skillManagerA.createSkill(skillA);

        // 先同步到 B
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        var skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));

        // A 软删除
        await ctx.skillManagerA.deleteSkill(skillA.uuid);

        // 从 A 拉取包含已删除的技能列表，模拟 _doSyncSkillsFromDevices
        final rawResult = await ctx.rpcManagerB.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodGetAllSkills,
          {'includeDeleted': true},
          toDeviceId: ctx.deviceIdA,
        );
        final remoteSkills = ((rawResult['result'] as Map<String, dynamic>)['skills'] as List)
            .map((s) => AiEmployeeSkillEntity.fromMap(s as Map<String, dynamic>))
            .toList();

        // B 本地合并（模拟 _doSyncSkillsFromDevices）
        for (final remote in remoteSkills) {
          final existing = await ctx.skillManagerB.getSkillIncludingDeleted(remote.uuid);
          if (existing != null) {
            final mergeResult = StoreMergeUtil.mergeDeleteState(
              localDeleteTime: existing.deleteTime,
              localDeleted: existing.deleted,
              remoteDeleteTime: remote.deleteTime,
              remoteDeleted: remote.deleted,
              localUpdateTime: existing.updateTime,
              remoteUpdateTime: remote.updateTime,
            );
            final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
                existing.updateTime, remote.updateTime);
            final shouldUpdateDelete =
                mergeResult.mergedDeleteTime != existing.deleteTime ||
                    mergeResult.mergedDeleted != existing.deleted;
            if (shouldUpdateData || shouldUpdateDelete) {
              final base = shouldUpdateData ? remote : existing;
              await ctx.skillManagerB.updateSkill(base.copyWith(
                deleted: mergeResult.mergedDeleted,
                deleteTime: mergeResult.mergedDeleteTime,
              ));
            }
          }
        }

        // 验证 B 已软删除
        final deletedB =
            await ctx.skillManagerB.getSkillIncludingDeleted(skillA.uuid);
        expect(deletedB, isNotNull);
        expect(deletedB!.deleted, equals(1));
      } finally {
        await ctx.dispose();
      }
    });

    test('B 从 A 拉取全量技能(methodGetAllSkills)', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-pull';
        final now = DateTime.now();

        // A 创建 3 个技能
        for (var i = 1; i <= 3; i++) {
          await ctx.skillManagerA.createSkill(createSkill(
            employeeId: empId,
            name: '技能$i',
            skillType: 'config',
            config: jsonEncode({'prompt': 'p$i'}),
            updateTime: now.subtract(Duration(minutes: i)),
          ));
        }

        // B 从 A 拉取
        final rawResult = await ctx.rpcManagerB.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodGetAllSkills,
          {'includeDeleted': true},
          toDeviceId: ctx.deviceIdA,
        );
        final result = rawResult['result'] as Map<String, dynamic>;
        final remoteSkills = (result['skills'] as List)
            .map((s) =>
                AiEmployeeSkillEntity.fromMap(s as Map<String, dynamic>))
            .toList();

        // B 本地合并（模拟 _doSyncSkillsFromDevices）
        for (final remote in remoteSkills) {
          final existing =
              await ctx.skillManagerB.getSkillIncludingDeleted(remote.uuid);
          if (existing == null) {
            if (remote.deleted != 1) {
              await ctx.skillManagerB.createSkill(remote);
            }
          } else {
            final mergeResult = StoreMergeUtil.mergeDeleteState(
              localDeleteTime: existing.deleteTime,
              localDeleted: existing.deleted,
              remoteDeleteTime: remote.deleteTime,
              remoteDeleted: remote.deleted,
              localUpdateTime: existing.updateTime,
              remoteUpdateTime: remote.updateTime,
            );
            final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
                existing.updateTime, remote.updateTime);
            final shouldUpdateDelete =
                mergeResult.mergedDeleteTime != existing.deleteTime ||
                    mergeResult.mergedDeleted != existing.deleted;
            if (shouldUpdateData || shouldUpdateDelete) {
              final base = shouldUpdateData ? remote : existing;
              await ctx.skillManagerB.updateSkill(base.copyWith(
                deleted: mergeResult.mergedDeleted,
                deleteTime: mergeResult.mergedDeleteTime,
              ));
            }
          }
        }

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(3));
        final names = skillsB.map((s) => s.name).toSet();
        expect(names, containsAll(['技能1', '技能2', '技能3']));
      } finally {
        await ctx.dispose();
      }
    });

    test('冲突合并：B 本地更新后，A 推送旧版本 → B 保留本地', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-conflict';
        final now = DateTime.now();

        final skillA = createSkill(
          uuid: 'conflict-skill-1',
          employeeId: empId,
          name: '原始',
          skillType: 'config',
          updateTime: now.subtract(const Duration(hours: 2)),
        );
        await ctx.skillManagerA.createSkill(skillA);

        // 先同步到 B
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {'skills': [skillA.toMap()]},
          toDeviceId: ctx.deviceIdB,
        );

        // B 本地更新（updateTime 更新）
        await ctx.skillManagerB.updateSkill(skillA.copyWith(
          name: 'B本地更新',
          updateTime: now,
        ));

        // A 广播旧版本（updateTime 更早）
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {'skills': [skillA.toMap()]},
          toDeviceId: ctx.deviceIdB,
        );

        // 验证 B 保留本地更新版本
        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));
        expect(skillsB.first.name, equals('B本地更新'));
      } finally {
        await ctx.dispose();
      }
    });

    test('Folder 技能同步：元数据正确传递', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-folder';

        final skillA = createSkill(
          employeeId: empId,
          name: '文件夹技能',
          skillType: 'folder',
          config: jsonEncode({'folder_path': r'D:\skills\translator'}),
        );
        await ctx.skillManagerA.createSkill(skillA);

        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));
        expect(skillsB.first.skillType, equals('folder'));
        expect(skillsB.first.name, equals('文件夹技能'));
        final config =
            jsonDecode(skillsB.first.config!) as Map<String, dynamic>;
        expect(config['folder_path'], equals(r'D:\skills\translator'));
      } finally {
        await ctx.dispose();
      }
    });

    test('MCP 技能同步：config JSON 正确传递', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-mcp';

        final skillA = createSkill(
          employeeId: empId,
          name: 'MCP技能',
          skillType: 'mcp',
          config: jsonEncode({
            'server': 'http://localhost:3000',
            'tools': ['tool1', 'tool2'],
          }),
        );
        await ctx.skillManagerA.createSkill(skillA);

        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(1));
        expect(skillsB.first.skillType, equals('mcp'));
        final config =
            jsonDecode(skillsB.first.config!) as Map<String, dynamic>;
        expect(config['server'], equals('http://localhost:3000'));
        expect(config['tools'], equals(['tool1', 'tool2']));
      } finally {
        await ctx.dispose();
      }
    });

    test('批量同步：混合类型技能正确传递', () async {
      final ctx = await createEmployeeSkillContext();
      try {
        const empId = 'emp-e2e-batch';

        await ctx.skillManagerA.createSkill(createSkill(
          employeeId: empId,
          name: 'Config技能',
          skillType: 'config',
          config: jsonEncode({'prompt': 'test'}),
        ));
        await ctx.skillManagerA.createSkill(createSkill(
          employeeId: empId,
          name: 'Folder技能',
          skillType: 'folder',
          config: jsonEncode({'folder_path': '/path/to/skill'}),
        ));
        await ctx.skillManagerA.createSkill(createSkill(
          employeeId: empId,
          name: 'MCP技能',
          skillType: 'mcp',
          config: jsonEncode({'server': 'http://localhost:3000'}),
        ));

        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncSkills,
          {
            'skills': (await ctx.skillManagerA.getSkills(empId))
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        final skillsB = await ctx.skillManagerB.getSkills(empId);
        expect(skillsB, hasLength(3));
        final types = skillsB.map((s) => s.skillType).toSet();
        expect(types, containsAll(['config', 'folder', 'mcp']));
      } finally {
        await ctx.dispose();
      }
    });

    // ══════════════════════════════════════════════════════════
    // 全局技能同步测试
    // ══════════════════════════════════════════════════════════

    test('A 创建全局技能 → 广播 → B 收到', () async {
      final ctx = await createGlobalSkillContext();
      try {
        final skillA = createGlobalSkill(
          name: '全局E2E技能',
          skillType: 'config',
          config: jsonEncode({'prompt': '全局提示词'}),
        );
        await ctx.globalSkillManagerA.createSkill(skillA);

        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncGlobalSkills,
          {
            'skills': (await ctx.globalSkillManagerA.getAllSkills())
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        final skillsB = await ctx.globalSkillManagerB.getAllSkills();
        expect(skillsB, hasLength(1));
        expect(skillsB.first.name, equals('全局E2E技能'));
      } finally {
        await ctx.dispose();
      }
    });

    test('A 删除全局技能 → 广播 → B 软删除', () async {
      final ctx = await createGlobalSkillContext();
      try {
        final skillA = createGlobalSkill(
          uuid: 'global-del-e2e',
          name: '全局待删除',
        );
        await ctx.globalSkillManagerA.createSkill(skillA);

        // 先同步到 B
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncGlobalSkills,
          {
            'skills': (await ctx.globalSkillManagerA.getAllSkills())
                .map((s) => s.toMap())
                .toList()
          },
          toDeviceId: ctx.deviceIdB,
        );

        var skillsB = await ctx.globalSkillManagerB.getAllSkills();
        expect(skillsB, hasLength(1));

        // A 软删除并广播
        await ctx.globalSkillManagerA.deleteSkill(skillA.uuid);
        final now = DateTime.now();
        final deletedSnapshot = skillA.copyWith(
          deleted: 1,
          deleteTime: now,
          updateTime: now,
        );
        await ctx.rpcManagerA.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodSyncGlobalSkills,
          {'skills': [deletedSnapshot.toMap()]},
          toDeviceId: ctx.deviceIdB,
        );

        skillsB = await ctx.globalSkillManagerB.getAllSkills();
        expect(skillsB, isEmpty);

        final deletedB =
            await ctx.globalSkillManagerB.getSkillIncludingDeleted(skillA.uuid);
        expect(deletedB, isNotNull);
        expect(deletedB!.deleted, equals(1));
      } finally {
        await ctx.dispose();
      }
    });

    test('B 从 A 拉取全局技能(methodGetGlobalSkills)', () async {
      final ctx = await createGlobalSkillContext();
      try {
        await ctx.globalSkillManagerA.createSkill(createGlobalSkill(
          name: '全局技能1',
          skillType: 'config',
        ));
        await ctx.globalSkillManagerA.createSkill(createGlobalSkill(
          name: '全局技能2',
          skillType: 'folder',
          config: jsonEncode({'folder_path': '/global/skill2'}),
        ));

        final rawResult = await ctx.rpcManagerB.invoke<Map<String, dynamic>>(
          HostRpcConfig.methodGetGlobalSkills,
          {'includeDeleted': true},
          toDeviceId: ctx.deviceIdA,
        );
        final result = rawResult['result'] as Map<String, dynamic>;

        final remoteSkills = (result['skills'] as List)
            .map((s) => GlobalSkillEntity.fromMap(s as Map<String, dynamic>))
            .toList();

        for (final remote in remoteSkills) {
          final existing = await ctx.globalSkillManagerB
              .getSkillIncludingDeleted(remote.uuid);
          if (existing == null) {
            if (remote.deleted != 1) {
              await ctx.globalSkillManagerB.createSkill(remote);
            }
          } else {
            final mergeResult = StoreMergeUtil.mergeDeleteState(
              localDeleteTime: existing.deleteTime,
              localDeleted: existing.deleted,
              remoteDeleteTime: remote.deleteTime,
              remoteDeleted: remote.deleted,
              localUpdateTime: existing.updateTime,
              remoteUpdateTime: remote.updateTime,
            );
            final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
                existing.updateTime, remote.updateTime);
            final shouldUpdateDelete =
                mergeResult.mergedDeleteTime != existing.deleteTime ||
                    mergeResult.mergedDeleted != existing.deleted;
            if (shouldUpdateData || shouldUpdateDelete) {
              final base = shouldUpdateData ? remote : existing;
              await ctx.globalSkillManagerB.updateSkill(base.copyWith(
                deleted: mergeResult.mergedDeleted,
                deleteTime: mergeResult.mergedDeleteTime,
              ));
            }
          }
        }

        final skillsB = await ctx.globalSkillManagerB.getAllSkills();
        expect(skillsB, hasLength(2));
        final names = skillsB.map((s) => s.name).toSet();
        expect(names, containsAll(['全局技能1', '全局技能2']));
      } finally {
        await ctx.dispose();
      }
    });
  });
}

/// 手动注册全局技能 RPC 方法（使用测试专用的 GlobalSkillManager 实例）
void _registerGlobalSkillRpc(
  RemoteCallServer rpcServer,
  GlobalSkillManager globalSkillManager,
) {
  rpcServer.register(HostRpcConfig.methodGetGlobalSkills, (params) async {
    final includeDeleted = params['includeDeleted'] as bool? ?? false;
    final skills = includeDeleted
        ? await globalSkillManager.getAllSkillsIncludingDeleted()
        : await globalSkillManager.getAllSkills();
    return {'skills': skills.map((s) => s.toMap()).toList()};
  });

  rpcServer.register(HostRpcConfig.methodSyncGlobalSkills, (params) async {
    final skillsData = params['skills'] as List;
    final skills = skillsData
        .map((s) => GlobalSkillEntity.fromMap(s as Map<String, dynamic>))
        .toList();

    for (final skill in skills) {
      final existing =
          await globalSkillManager.getSkillIncludingDeleted(skill.uuid);
      if (existing == null) {
        await globalSkillManager.createSkill(skill);
      } else {
        final mergeResult = StoreMergeUtil.mergeDeleteState(
          localDeleteTime: existing.deleteTime,
          localDeleted: existing.deleted,
          remoteDeleteTime: skill.deleteTime,
          remoteDeleted: skill.deleted,
          localUpdateTime: existing.updateTime,
          remoteUpdateTime: skill.updateTime,
        );
        final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
            existing.updateTime, skill.updateTime);
        final shouldUpdateDelete =
            mergeResult.mergedDeleteTime != existing.deleteTime ||
                mergeResult.mergedDeleted != existing.deleted;

        if (shouldUpdateData || shouldUpdateDelete) {
          final base = shouldUpdateData ? skill : existing;
          await globalSkillManager.updateSkill(base.copyWith(
            deleted: mergeResult.mergedDeleted,
            deleteTime: mergeResult.mergedDeleteTime,
          ));
        }
      }
    }
    return {'count': skills.length};
  });
}
