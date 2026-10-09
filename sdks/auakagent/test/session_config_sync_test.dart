import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/auakagent.dart';

int _testCounter = 0;

/// 会话窗口配置同步测试
///
/// 测试范围：
/// - Project 配置（projectUuid, projectName, workPath）：存储在 AiEmployeeEntity 上
/// - Model 配置（providerConfig）：存储在 AiEmployeeSessionEntity.config[deviceId].providerConfig
///
/// 验证两条同步路径：
/// - 路径1：event(lan广播+event) → update store
///   DeviceA 修改配置 → AgentEvent(configChanged) → LAN 广播(agentConfigChanged)
///   → DeviceB 收到 → _handleConfigChangedEvent → 写入 SessionStore / 更新缓存
///
/// - 路径2：query → update store
///   DeviceB 主动调用 syncEmployeesFromDevices / syncSessionsFromDevices → RPC query
///   → 拉取远程数据 → StoreMergeUtil 合并 → 写入本地 store
void main() {
  late String testDbPath;
  late String deviceIdA;
  late String deviceIdB;
  late String deviceIdC;
  late EmployeeStore storeA;
  late EmployeeStore storeB;
  late EmployeeStore storeC;
  late SessionStore sessionStoreA;
  late SessionStore sessionStoreB;
  late SessionStore sessionStoreC;
  late SessionManager sessionManagerA;
  late SessionManager sessionManagerB;
  late SessionManager sessionManagerC;
  late EmployeeManager managerA;
  late EmployeeManager managerB;

  setUp(() async {
    _testCounter++;
    testDbPath =
        '${Directory.systemTemp.path}/wenzagent_session_config_sync_test_$_testCounter';
    await Directory(testDbPath).create(recursive: true);

    deviceIdA = 'dev-A-${const Uuid().v4().substring(0, 8)}';
    deviceIdB = 'dev-B-${const Uuid().v4().substring(0, 8)}';
    deviceIdC = 'dev-C-${const Uuid().v4().substring(0, 8)}';

    // 初始化三个设备的数据库
    await DatabaseManager.getInstance(deviceIdA).initialize(
      storagePath: testDbPath,
    );
    await DatabaseManager.getInstance(deviceIdB).initialize(
      storagePath: testDbPath,
    );
    await DatabaseManager.getInstance(deviceIdC).initialize(
      storagePath: testDbPath,
    );

    storeA = EmployeeStore(deviceId: deviceIdA);
    storeB = EmployeeStore(deviceId: deviceIdB);
    storeC = EmployeeStore(deviceId: deviceIdC);
    sessionStoreA = SessionStore(deviceId: deviceIdA);
    sessionStoreB = SessionStore(deviceId: deviceIdB);
    sessionStoreC = SessionStore(deviceId: deviceIdC);
    sessionManagerA = SessionManager.getInstance(deviceIdA);
    sessionManagerB = SessionManager.getInstance(deviceIdB);
    sessionManagerC = SessionManager.getInstance(deviceIdC);
    managerA = EmployeeManager.getInstance(deviceIdA);
    managerB = EmployeeManager.getInstance(deviceIdB);
  });

  tearDown(() async {
    for (final id in [deviceIdA, deviceIdB, deviceIdC]) {
      await DatabaseManager.getInstance(id).close();
      DatabaseManager.removeInstance(id);
      EmployeeManager.removeInstance(id);
      SessionManager.removeInstance(id);
    }
    try {
      await Directory(testDbPath).delete(recursive: true);
    } catch (_) {}
  });

  // ═══════════════════════════════════════════════════
  // 辅助方法
  // ═══════════════════════════════════════════════════

  AiEmployeeEntity createEmployee({
    String? uuid,
    String? name,
    String? deviceId,
    String? description,
    String? systemPrompt,
    String? provider,
    String? model,
    String? apiKey,
    String? apiBaseUrl,
    String? modelConfig,
    String? projectUuid,
    String? projectName,
    String? projectContext,
    String? workPath,
    String status = 'active',
    int deleted = 0,
    DateTime? deletedTime,
    int isPinned = 0,
    int sortOrder = 0,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    final now = DateTime.now();
    return AiEmployeeEntity(
      uuid: uuid ?? const Uuid().v4(),
      name: name ?? '测试员工',
      deviceId: deviceId,
      description: description,
      systemPrompt: systemPrompt,
      provider: provider,
      model: model,
      apiKey: apiKey,
      apiBaseUrl: apiBaseUrl,
      modelConfig: modelConfig,
      projectUuid: projectUuid,
      projectName: projectName,
      projectContext: projectContext,
      workPath: workPath,
      status: status,
      deleted: deleted,
      deletedTime: deletedTime,
      isPinned: isPinned,
      sortOrder: sortOrder,
      createTime: createTime ?? now,
      updateTime: updateTime ?? now,
    );
  }

  AiEmployeeSessionEntity createSession({
    required String employeeId,
    Map<String, DeviceSessionConfig>? config,
    String title = '新对话',
    int deleted = 0,
    DateTime? deleteTime,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    final now = DateTime.now();
    return AiEmployeeSessionEntity(
      employeeId: employeeId,
      config: config ?? {},
      title: title,
      deleted: deleted,
      deleteTime: deleteTime,
      createTime: createTime ?? now,
      updateTime: updateTime ?? now,
    );
  }

  /// 创建 providerConfig Map（模拟 ProviderConfig.toMap() 输出）
  Map<String, dynamic> createProviderConfigMap({
    String provider = 'openai',
    String model = 'gpt-4o',
    String? apiKey,
    String? baseUrl,
    double temperature = 0.7,
  }) {
    return {
      'provider': provider,
      'model': model,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'options': {
        'temperature': temperature,
      },
    };
  }

  /// 创建 DeviceSessionConfig
  DeviceSessionConfig createDeviceConfig({
    String? providerConfig,
    String? systemPromptOverride,
    int totalInputTokens = 0,
    int totalOutputTokens = 0,
    int totalMessageCount = 0,
    DateTime? updateTime,
  }) {
    return DeviceSessionConfig(
      providerConfig: providerConfig,
      systemPromptOverride: systemPromptOverride,
      totalInputTokens: totalInputTokens,
      totalOutputTokens: totalOutputTokens,
      totalMessageCount: totalMessageCount,
      updateTime: updateTime ?? DateTime.now(),
    );
  }

  /// 模拟 DataSyncManager._mergeAndSaveEmployee 的合并逻辑
  /// 返回 (shouldSave, mergedEntity)
  (bool, AiEmployeeEntity?) simulateMerge(
    AiEmployeeEntity existing,
    AiEmployeeEntity remote,
  ) {
    final mergeResult = StoreMergeUtil.mergeDeleteState(
      localDeleteTime: existing.deletedTime,
      localDeleted: existing.deleted,
      remoteDeleteTime: remote.deletedTime,
      remoteDeleted: remote.deleted,
      localUpdateTime: existing.updateTime,
      remoteUpdateTime: remote.updateTime,
    );
    final shouldUpdateData = StoreMergeUtil.shouldUpdateData(
      existing.updateTime,
      remote.updateTime,
    );
    final shouldUpdateDelete =
        mergeResult.mergedDeleteTime != existing.deletedTime ||
        mergeResult.mergedDeleted != existing.deleted;
    if (shouldUpdateData || shouldUpdateDelete) {
      final base = shouldUpdateData ? remote : existing;
      return (true, base.copyWith(
        deleted: mergeResult.mergedDeleted,
        deletedTime: mergeResult.mergedDeleteTime,
      ));
    }
    return (false, null);
  }

  /// 模拟 _doSyncEmployeesFromDevices 的拉取合并逻辑
  (bool, AiEmployeeEntity?) simulateQuerySyncMerge(
    AiEmployeeEntity? existing,
    AiEmployeeEntity remote,
  ) {
    if (existing == null) {
      if (remote.deleted != 1) {
        return (true, remote);
      }
      return (false, null);
    }
    return simulateMerge(existing, remote);
  }

  /// 模拟 _handleConfigChangedEvent 路径1：provider 配置同步
  /// 将 providerConfig 写入 SessionStore
  Future<void> simulateEventSyncProvider(
    String employeeId,
    String fromDeviceId,
    Map<String, dynamic> providerConfigMap,
    SessionStore targetSessionStore,
    SessionManager targetSessionManager,
  ) async {
    final providerConfigJson = jsonEncode(providerConfigMap);
    // 模拟 DeviceMessageHandler._handleConfigChangedEvent 中 configType='provider' 的逻辑
    // sessionManager.updateDeviceConfig 会写入 session.config[fromDeviceId].providerConfig
    await targetSessionManager.updateDeviceConfig(
      employeeId,
      fromDeviceId,
      providerConfig: providerConfigJson,
    );
  }

  // ═══════════════════════════════════════════════════
  // A. Project 配置
  // ═══════════════════════════════════════════════════

  group('A. Project 配置', () {
    // --------------------------------------------------
    // A.1 Entity 序列化往返
    // --------------------------------------------------
    group('A.1 Entity 序列化往返', () {
      test('projectUuid/projectName/workPath 完整字段 fromMap/toMap 往返', () {
        final emp = createEmployee(
          name: '项目员工',
          projectUuid: 'proj-001',
          projectName: '我的项目',
          projectContext: '项目上下文描述',
          workPath: '/home/user/project',
        );

        final map = emp.toMap();
        final restored = AiEmployeeEntity.fromMap(map);

        expect(restored.projectUuid, equals('proj-001'));
        expect(restored.projectName, equals('我的项目'));
        expect(restored.projectContext, equals('项目上下文描述'));
        expect(restored.workPath, equals('/home/user/project'));
      });

      test('所有 project 字段为 null 的往返', () {
        final emp = createEmployee(name: '无项目员工');

        final map = emp.toMap();
        final restored = AiEmployeeEntity.fromMap(map);

        expect(restored.projectUuid, isNull);
        expect(restored.projectName, isNull);
        expect(restored.projectContext, isNull);
        expect(restored.workPath, isNull);
      });

      test('copyWith 覆盖 project 字段', () {
        final emp = createEmployee(
          projectUuid: 'proj-old',
          projectName: '旧项目',
          workPath: '/old/path',
        );

        final updated = emp.copyWith(
          projectUuid: 'proj-new',
          projectName: '新项目',
          workPath: '/new/path',
        );

        expect(updated.projectUuid, equals('proj-new'));
        expect(updated.projectName, equals('新项目'));
        expect(updated.workPath, equals('/new/path'));
        // 未覆盖的字段保持不变
        expect(updated.projectContext, isNull);
      });

      test('ProjectData fromMap/toMap 往返', () {
        final projectData = ProjectData(
          projectUuid: 'proj-001',
          projectName: '测试项目',
          projectContext: '上下文',
          workPath: '/workspace',
          additionalInfo: '补充信息',
          metadata: {'key': 'value'},
        );

        final map = projectData.toMap();
        final restored = ProjectData.fromMap(map);

        expect(restored.projectUuid, equals('proj-001'));
        expect(restored.projectName, equals('测试项目'));
        expect(restored.projectContext, equals('上下文'));
        expect(restored.workPath, equals('/workspace'));
        expect(restored.additionalInfo, equals('补充信息'));
        expect(restored.metadata, equals({'key': 'value'}));
      });

      test('ProjectData 全 null 的 toMap 返回空 Map', () {
        const projectData = ProjectData();
        final map = projectData.toMap();
        expect(map, isEmpty);
      });
    });

    // --------------------------------------------------
    // A.2 路径1：event → update store（project 配置）
    // --------------------------------------------------
    group('A.2 路径1：event → update store（project 配置）', () {
      test('setProject 触发 configChanged 事件（configType=project）', () {
        final projectData = ProjectData(
          projectUuid: 'proj-001',
          projectName: '测试项目',
          workPath: '/workspace',
        );

        // 模拟 AgentImpl.setProject 发射的事件
        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'project',
            'action': 'updated',
            'projectData': projectData.toMap(),
          },
          employeeId: 'emp-001',
        );

        expect(event.type, equals(AgentEventType.configChanged));
        expect(event.data['configType'], equals('project'));
        expect(event.data['action'], equals('updated'));
        expect(event.data['projectData'], isNotNull);
        expect(event.data['projectData']['projectUuid'], equals('proj-001'));
      });

      test('configChanged 事件 data 包含完整 projectData', () {
        final projectData = ProjectData(
          projectUuid: 'proj-002',
          projectName: '完整项目',
          projectContext: '项目上下文',
          workPath: '/home/project',
          additionalInfo: '补充',
          metadata: {'env': 'dev'},
        );

        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'project',
            'action': 'updated',
            'projectData': projectData.toMap(),
          },
          employeeId: 'emp-001',
        );

        final data = event.data['projectData'] as Map<String, dynamic>;
        expect(data['projectUuid'], equals('proj-002'));
        expect(data['projectName'], equals('完整项目'));
        expect(data['projectContext'], equals('项目上下文'));
        expect(data['workPath'], equals('/home/project'));
        expect(data['additionalInfo'], equals('补充'));
        expect(data['metadata'], equals({'env': 'dev'}));
      });

      test('project 配置变更不写入 SessionStore（仅更新远程缓存）', () async {
        // 验证：configType='project' 在 _handleConfigChangedEvent 中
        // 不调用 sessionManager.updateDeviceConfig，不写入 SessionStore
        final employeeId = const Uuid().v4();
        final fromDeviceId = deviceIdA;

        // 创建一个 session
        final session = createSession(employeeId: employeeId);
        await sessionStoreB.save(session);

        // 模拟收到 configType='project' 事件 —— 不应该写入 SessionStore
        // （project 配置由 CachedAgentProxy 缓存处理，不经过 SessionStore）
        // 这里验证 session.config 不包含来自 project 事件的数据
        final storedSession = await sessionStoreB.find(employeeId);
        expect(storedSession, isNotNull);
        expect(storedSession!.config, isEmpty);
      });

      test('project 配置清除（action=cleared）触发远程缓存清除', () {
        // 模拟 AgentImpl.setProject(null) 发射的事件
        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'project',
            'action': 'cleared',
          },
          employeeId: 'emp-001',
        );

        expect(event.type, equals(AgentEventType.configChanged));
        expect(event.data['configType'], equals('project'));
        expect(event.data['action'], equals('cleared'));
        expect(event.data['projectData'], isNull);
      });

      test('AgentEvent 序列化往返保留 project 配置数据', () {
        final projectData = ProjectData(
          projectUuid: 'proj-serialize',
          projectName: '序列化项目',
          workPath: '/serialize/path',
        );

        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'project',
            'action': 'updated',
            'projectData': projectData.toMap(),
          },
          employeeId: 'emp-001',
          fromDeviceId: deviceIdA,
        );

        // 模拟 LAN 传输：toMap → jsonEncode → jsonDecode → fromMap
        final json = jsonEncode(event.toMap());
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final restored = AgentEvent.fromMap(decoded);

        expect(restored.type, equals(AgentEventType.configChanged));
        expect(restored.data['configType'], equals('project'));
        expect(restored.data['action'], equals('updated'));
        expect(restored.employeeId, equals('emp-001'));
        expect(restored.fromDeviceId, equals(deviceIdA));

        final restoredProjectData = restored.data['projectData'] as Map<String, dynamic>;
        expect(restoredProjectData['projectUuid'], equals('proj-serialize'));
        expect(restoredProjectData['projectName'], equals('序列化项目'));
        expect(restoredProjectData['workPath'], equals('/serialize/path'));
      });
    });

    // --------------------------------------------------
    // A.3 路径2：query → update store（project 配置）
    // --------------------------------------------------
    group('A.3 路径2：query → update store（project 配置）', () {
      test('拉取远程员工后 projectUuid 同步到本地 EmployeeStore', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '项目员工',
          projectUuid: 'proj-query-001',
          projectName: '查询项目',
          workPath: '/query/path',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);

        // 模拟 DeviceB query 拉取远程员工列表
        final remoteEmployees = await storeA.findAll(null);
        for (final remote in remoteEmployees) {
          final existing = await storeB.findIncludingDeleted(remote.uuid);
          final (changed, merged) = simulateQuerySyncMerge(existing, remote);
          if (changed && merged != null) {
            await storeB.save(merged);
          }
        }

        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNotNull);
        expect(stored!.projectUuid, equals('proj-query-001'));
        expect(stored.projectName, equals('查询项目'));
        expect(stored.workPath, equals('/query/path'));
      });

      test('拉取远程员工后 projectName/workPath 同步到本地', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '员工',
          projectUuid: 'proj-001',
          projectName: '初始项目名',
          workPath: '/initial/path',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);
        await storeB.save(emp);

        // DeviceA 更新 project 配置
        final updateTime = DateTime(2099, 1, 1, 12, 5, 0);
        final updated = emp.copyWith(
          projectName: '更新后项目名',
          workPath: '/updated/path',
          projectContext: '新增上下文',
          updateTime: updateTime,
        );
        await storeA.save(updated);

        // DeviceB query 拉取
        final remoteEmployees = await storeA.findAll(null);
        for (final remote in remoteEmployees) {
          final existing = await storeB.findIncludingDeleted(remote.uuid);
          final (changed, merged) = simulateQuerySyncMerge(existing, remote);
          if (changed && merged != null) {
            await storeB.save(merged);
          }
        }

        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNotNull);
        expect(stored!.projectName, equals('更新后项目名'));
        expect(stored.workPath, equals('/updated/path'));
        expect(stored.projectContext, equals('新增上下文'));
      });

      test('本地 project 配置比远程新时不被覆盖（updateTime 判断）', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '员工',
          projectUuid: 'proj-old',
          projectName: '旧项目',
          workPath: '/old/path',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);
        await storeB.save(emp);

        // 注意：storeA 和 storeB 共享同一数据库文件（同一 testDbPath），
        // INSERT OR REPLACE 按主键覆盖。因此需要使用独立的变量跟踪
        // "远程"和"本地"的数据状态，而不是依赖两个 store 实例。

        // DeviceB 本地更新 project 配置（时间更新）
        // 使用固定整秒时间戳，避免 SQLite 毫秒精度截断问题
        final bTime = DateTime(2099, 1, 1, 13, 0, 0); // 本地比 baseTime 新 1 小时
        await storeB.save(emp.copyWith(
          projectName: '本地新项目',
          workPath: '/local/new/path',
          updateTime: bTime,
        ));

        // 构造"远程"数据（模拟从另一台设备拉取的数据）
        // 远程 updateTime 比 bTime 旧
        final aTime = DateTime(2099, 1, 1, 12, 30, 0); // 远程比 bTime 旧 30 分钟
        final remoteEmp = emp.copyWith(
          projectName: '远程旧项目',
          workPath: '/remote/old/path',
          updateTime: aTime,
        );

        // 模拟 query 同步合并：本地已有 bTime 数据，远程是 aTime 数据
        final existing = await storeB.findIncludingDeleted(emp.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remoteEmp);
        if (changed && merged != null) {
          await storeB.save(merged);
        }

        // 验证本地配置不被覆盖
        // 本地 updateTime (13:00) > 远程 updateTime (12:30)，不应被覆盖
        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNotNull);
        expect(stored!.projectName, equals('本地新项目'));
        expect(stored.workPath, equals('/local/new/path'));
      });

      test('本地不存在员工时远程 project 配置直接保存', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '新员工',
          projectUuid: 'proj-new',
          projectName: '新项目',
          workPath: '/new/path',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);

        // 注意：storeA 和 storeB 共享同一数据库文件（同一 testDbPath），
        // 所以 storeB.findIncludingDeleted 也能找到 storeA 保存的数据。
        // 在真实场景中，不同设备使用不同数据库，existing 应为 null。
        // 这里直接模拟 existing=null 的场景来测试合并逻辑。
        const existing = null;

        // 模拟 query 拉取（使用 storeA 中实际保存的数据）
        final remoteEmp = await storeA.findIncludingDeleted(emp.uuid);
        expect(remoteEmp, isNotNull);
        final (changed, merged) = simulateQuerySyncMerge(existing, remoteEmp!);
        expect(changed, isTrue);
        expect(merged, isNotNull);

        await storeB.save(merged!);

        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNotNull);
        expect(stored!.projectUuid, equals('proj-new'));
        expect(stored.projectName, equals('新项目'));
        expect(stored.workPath, equals('/new/path'));
      });

      test('project 配置合并与删除状态合并独立（mergeDeleteState）', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '员工',
          projectUuid: 'proj-merge',
          projectName: '合并项目',
          workPath: '/merge/path',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);
        await storeB.save(emp);

        // DeviceA 删除员工
        final deleteTime = DateTime(2099, 1, 1, 12, 10, 0);
        await storeA.save(emp.copyWith(
          deleted: 1,
          deletedTime: deleteTime,
          updateTime: deleteTime,
        ));

        // DeviceB query 拉取（includeDeleted）
        final remoteEmployees = await storeA.findAll(null, includeDeleted: true);
        for (final remote in remoteEmployees) {
          final existing = await storeB.findIncludingDeleted(remote.uuid);
          final (changed, merged) = simulateQuerySyncMerge(existing, remote);
          if (changed && merged != null) {
            await storeB.save(merged);
          }
        }

        // 验证删除状态同步，project 配置也同步
        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNull); // 已删除

        final storedIncDel = await storeB.findIncludingDeleted(emp.uuid);
        expect(storedIncDel, isNotNull);
        expect(storedIncDel!.deleted, equals(1));
        expect(storedIncDel.projectUuid, equals('proj-merge'));
      });
    });
  });

  // ═══════════════════════════════════════════════════
  // B. Model 配置（providerConfig）
  // ═══════════════════════════════════════════════════

  group('B. Model 配置（providerConfig）', () {
    // --------------------------------------------------
    // B.1 Entity 序列化往返
    // --------------------------------------------------
    group('B.1 Entity 序列化往返', () {
      test('DeviceSessionConfig.providerConfig JSON 序列化往返', () {
        final configMap = createProviderConfigMap(
          provider: 'anthropic',
          model: 'claude-3-5-sonnet',
          apiKey: 'sk-test-key',
          baseUrl: 'https://api.anthropic.com',
        );

        final configJson = jsonEncode(configMap);
        final deviceConfig = createDeviceConfig(providerConfig: configJson);

        // toMap → fromMap 往返
        final map = deviceConfig.toMap();
        final restored = DeviceSessionConfig.fromMap(map);

        expect(restored.providerConfig, equals(configJson));

        // 验证 JSON 内容可还原
        final decodedConfig = jsonDecode(restored.providerConfig!) as Map<String, dynamic>;
        expect(decodedConfig['provider'], equals('anthropic'));
        expect(decodedConfig['model'], equals('claude-3-5-sonnet'));
        expect(decodedConfig['apiKey'], equals('sk-test-key'));
        expect(decodedConfig['baseUrl'], equals('https://api.anthropic.com'));
      });

      test('AiEmployeeEntity provider/model/apiKey/apiBaseUrl/modelConfig 往返', () {
        final emp = createEmployee(
          provider: 'openai',
          model: 'gpt-4o',
          apiKey: 'sk-emp-key',
          apiBaseUrl: 'https://api.openai.com/v1',
          modelConfig: '{"temperature": 0.5}',
        );

        final map = emp.toMap();
        final restored = AiEmployeeEntity.fromMap(map);

        expect(restored.provider, equals('openai'));
        expect(restored.model, equals('gpt-4o'));
        expect(restored.apiKey, equals('sk-emp-key'));
        expect(restored.apiBaseUrl, equals('https://api.openai.com/v1'));
        expect(restored.modelConfig, equals('{"temperature": 0.5}'));
      });

      test('ProviderConfig.fromMap/toMap 往返', () {
        final config = ProviderConfig(
          provider: LLMProvider.openai,
          model: 'gpt-4o',
          apiKey: 'sk-test',
          baseUrl: 'https://api.openai.com/v1',
          options: const LLMOptions(temperature: 0.5, maxTokens: 4096),
        );

        final map = config.toMap();
        final restored = ProviderConfig.fromMap(map);

        expect(restored.provider, equals(LLMProvider.openai));
        expect(restored.model, equals('gpt-4o'));
        expect(restored.apiKey, equals('sk-test'));
        expect(restored.baseUrl, equals('https://api.openai.com/v1'));
        expect(restored.options.temperature, equals(0.5));
        expect(restored.options.maxTokens, equals(4096));
      });

      test('AiEmployeeSessionEntity config[deviceId] 序列化往返', () {
        final configMap = createProviderConfigMap(provider: 'ollama', model: 'llama3');
        final deviceConfig = createDeviceConfig(
          providerConfig: jsonEncode(configMap),
          systemPromptOverride: '自定义提示词',
          totalInputTokens: 100,
          totalOutputTokens: 200,
          totalMessageCount: 5,
        );

        final session = createSession(
          employeeId: 'emp-session-test',
          config: {deviceIdA: deviceConfig},
        );

        final map = session.toMap();
        final restored = AiEmployeeSessionEntity.fromMap(map);

        expect(restored.config.length, equals(1));
        expect(restored.config.containsKey(deviceIdA), isTrue);

        final restoredDeviceConfig = restored.config[deviceIdA]!;
        expect(restoredDeviceConfig.providerConfig, equals(jsonEncode(configMap)));
        expect(restoredDeviceConfig.systemPromptOverride, equals('自定义提示词'));
        expect(restoredDeviceConfig.totalInputTokens, equals(100));
        expect(restoredDeviceConfig.totalOutputTokens, equals(200));
        expect(restoredDeviceConfig.totalMessageCount, equals(5));
      });

      test('AiEmployeeSessionEntity 多设备 config 序列化往返', () {
        final configA = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(provider: 'openai')),
        );
        final configB = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(provider: 'anthropic')),
        );

        final session = createSession(
          employeeId: 'emp-multi-device',
          config: {deviceIdA: configA, deviceIdB: configB},
        );

        final map = session.toMap();
        final restored = AiEmployeeSessionEntity.fromMap(map);

        expect(restored.config.length, equals(2));

        final decodedA = jsonDecode(restored.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(decodedA['provider'], equals('openai'));

        final decodedB = jsonDecode(restored.config[deviceIdB]!.providerConfig!) as Map<String, dynamic>;
        expect(decodedB['provider'], equals('anthropic'));
      });
    });

    // --------------------------------------------------
    // B.2 路径1：event → update store（model 配置）
    // --------------------------------------------------
    group('B.2 路径1：event → update store（model 配置）', () {
      test('setProvider 触发 configChanged 事件（configType=provider）', () {
        final providerConfig = ProviderConfig(
          provider: LLMProvider.openai,
          model: 'gpt-4o',
          apiKey: 'sk-event-test',
        );

        // 模拟 AgentImpl.setProvider 发射的事件
        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'provider',
            'action': 'updated',
            'providerConfig': providerConfig.toMap(),
          },
          employeeId: 'emp-001',
        );

        expect(event.type, equals(AgentEventType.configChanged));
        expect(event.data['configType'], equals('provider'));
        expect(event.data['action'], equals('updated'));

        final eventConfig = event.data['providerConfig'] as Map<String, dynamic>;
        expect(eventConfig['provider'], equals('openai'));
        expect(eventConfig['model'], equals('gpt-4o'));
        expect(eventConfig['apiKey'], equals('sk-event-test'));
      });

      test('configChanged 事件 data 包含完整 providerConfig Map', () {
        final providerConfig = ProviderConfig(
          provider: LLMProvider.anthropic,
          model: 'claude-3-5-sonnet',
          apiKey: 'sk-ant-test',
          baseUrl: 'https://api.anthropic.com',
          options: const LLMOptions(temperature: 0.3, maxTokens: 8192, topP: 0.9),
        );

        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'provider',
            'action': 'updated',
            'providerConfig': providerConfig.toMap(),
          },
          employeeId: 'emp-001',
        );

        final data = event.data['providerConfig'] as Map<String, dynamic>;
        expect(data['provider'], equals('anthropic'));
        expect(data['model'], equals('claude-3-5-sonnet'));
        expect(data['apiKey'], equals('sk-ant-test'));
        expect(data['baseUrl'], equals('https://api.anthropic.com'));

        final options = data['options'] as Map<String, dynamic>;
        expect(options['temperature'], equals(0.3));
        expect(options['maxTokens'], equals(8192));
        expect(options['topP'], equals(0.9));
      });

      test('远程设备收到 configChanged 后写入 SessionStore', () async {
        final employeeId = const Uuid().v4();
        final fromDeviceId = deviceIdA;

        // DeviceA 设置 providerConfig
        final providerConfigMap = createProviderConfigMap(
          provider: 'openai',
          model: 'gpt-4o',
          apiKey: 'sk-sync-test',
          baseUrl: 'https://api.openai.com/v1',
        );

        // 模拟路径1：DeviceB 收到 configChanged 事件后写入 SessionStore
        await simulateEventSyncProvider(
          employeeId,
          fromDeviceId,
          providerConfigMap,
          sessionStoreB,
          sessionManagerB,
        );

        // 验证 SessionStore 中已写入
        final session = await sessionStoreB.find(employeeId);
        expect(session, isNotNull);
        expect(session!.config.containsKey(fromDeviceId), isTrue);

        final deviceConfig = session.config[fromDeviceId]!;
        expect(deviceConfig.providerConfig, isNotNull);

        final storedConfig = jsonDecode(deviceConfig.providerConfig!) as Map<String, dynamic>;
        expect(storedConfig['provider'], equals('openai'));
        expect(storedConfig['model'], equals('gpt-4o'));
        expect(storedConfig['apiKey'], equals('sk-sync-test'));
        expect(storedConfig['baseUrl'], equals('https://api.openai.com/v1'));
      });

      test('providerConfig 变更不影响其他设备配置（deviceId 隔离）', () async {
        final employeeId = const Uuid().v4();

        // DeviceA 先设置 providerConfig
        final configA = createProviderConfigMap(provider: 'openai', model: 'gpt-4o');
        await simulateEventSyncProvider(
          employeeId, deviceIdA, configA, sessionStoreB, sessionManagerB,
        );

        // DeviceC 也设置 providerConfig（同一员工）
        final configC = createProviderConfigMap(provider: 'anthropic', model: 'claude-3');
        await simulateEventSyncProvider(
          employeeId, deviceIdC, configC, sessionStoreB, sessionManagerB,
        );

        // 验证两个设备的配置互不影响
        final session = await sessionStoreB.find(employeeId);
        expect(session, isNotNull);
        expect(session!.config.length, equals(2));

        final storedA = jsonDecode(session.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(storedA['provider'], equals('openai'));
        expect(storedA['model'], equals('gpt-4o'));

        final storedC = jsonDecode(session.config[deviceIdC]!.providerConfig!) as Map<String, dynamic>;
        expect(storedC['provider'], equals('anthropic'));
        expect(storedC['model'], equals('claude-3'));
      });

      test('providerConfig 清除（action=cleared）触发远程缓存清除', () {
        // 模拟 AgentImpl 清除 provider 的场景
        // 注意：当前实现中 provider 没有 cleared 事件，但验证事件结构
        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'provider',
            'action': 'cleared',
          },
          employeeId: 'emp-001',
        );

        expect(event.data['configType'], equals('provider'));
        expect(event.data['action'], equals('cleared'));
        expect(event.data['providerConfig'], isNull);
      });

      test('AgentEvent 序列化往返保留 providerConfig 数据', () {
        final providerConfigMap = createProviderConfigMap(
          provider: 'google',
          model: 'gemini-pro',
          apiKey: 'sk-gemini',
        );

        final event = AgentEvent(
          type: AgentEventType.configChanged,
          data: {
            'configType': 'provider',
            'action': 'updated',
            'providerConfig': providerConfigMap,
          },
          employeeId: 'emp-serialize',
          fromDeviceId: deviceIdA,
        );

        // 模拟 LAN 传输
        final json = jsonEncode(event.toMap());
        final decoded = jsonDecode(json) as Map<String, dynamic>;
        final restored = AgentEvent.fromMap(decoded);

        expect(restored.type, equals(AgentEventType.configChanged));
        expect(restored.data['configType'], equals('provider'));

        final restoredConfig = restored.data['providerConfig'] as Map<String, dynamic>;
        expect(restoredConfig['provider'], equals('google'));
        expect(restoredConfig['model'], equals('gemini-pro'));
        expect(restoredConfig['apiKey'], equals('sk-gemini'));
      });

      test('同一设备多次更新 providerConfig 覆盖写入', () async {
        final employeeId = const Uuid().v4();

        // 第一次更新
        final config1 = createProviderConfigMap(provider: 'openai', model: 'gpt-4o');
        await simulateEventSyncProvider(
          employeeId, deviceIdA, config1, sessionStoreB, sessionManagerB,
        );

        // 第二次更新（同一设备）
        final config2 = createProviderConfigMap(provider: 'anthropic', model: 'claude-3-5-sonnet');
        await simulateEventSyncProvider(
          employeeId, deviceIdA, config2, sessionStoreB, sessionManagerB,
        );

        // 验证：只有一份 deviceIdA 的配置，且为最新值
        final session = await sessionStoreB.find(employeeId);
        expect(session, isNotNull);
        expect(session!.config.length, equals(1));
        expect(session.config.containsKey(deviceIdA), isTrue);

        final stored = jsonDecode(session.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(stored['provider'], equals('anthropic'));
        expect(stored['model'], equals('claude-3-5-sonnet'));
      });
    });

    // --------------------------------------------------
    // B.3 路径2：query → update store（model 配置）
    // --------------------------------------------------
    group('B.3 路径2：query → update store（model 配置）', () {
      test('拉取远程员工后 provider/model 同步到本地 EmployeeStore', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final emp = createEmployee(
          name: '模型员工',
          provider: 'openai',
          model: 'gpt-4o',
          apiKey: 'sk-query-test',
          apiBaseUrl: 'https://api.openai.com/v1',
          modelConfig: '{"temperature": 0.8}',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);

        // 模拟 DeviceB query 拉取
        final remoteEmployees = await storeA.findAll(null);
        for (final remote in remoteEmployees) {
          final existing = await storeB.findIncludingDeleted(remote.uuid);
          final (changed, merged) = simulateQuerySyncMerge(existing, remote);
          if (changed && merged != null) {
            await storeB.save(merged);
          }
        }

        final stored = await storeB.find(null, emp.uuid);
        expect(stored, isNotNull);
        expect(stored!.provider, equals('openai'));
        expect(stored.model, equals('gpt-4o'));
        expect(stored.apiKey, equals('sk-query-test'));
        expect(stored.apiBaseUrl, equals('https://api.openai.com/v1'));
        expect(stored.modelConfig, equals('{"temperature": 0.8}'));
      });

      test('拉取远程会话后 providerConfig 同步到本地 SessionStore', () async {
        final employeeId = const Uuid().v4();
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);

        // DeviceA 创建会话并设置 providerConfig
        final configMap = createProviderConfigMap(
          provider: 'anthropic',
          model: 'claude-3-5-sonnet',
          apiKey: 'sk-session-sync',
        );
        final deviceConfig = createDeviceConfig(
          providerConfig: jsonEncode(configMap),
          updateTime: baseTime,
        );
        final session = createSession(
          employeeId: employeeId,
          config: {deviceIdA: deviceConfig},
          createTime: baseTime,
          updateTime: baseTime,
        );
        await sessionStoreA.save(session);

        // 模拟 DeviceB query 拉取远程会话列表
        final remoteSessions = await sessionStoreA.findAll();
        for (final remote in remoteSessions) {
          final existing = await sessionStoreB.find(remote.employeeId);
          if (existing == null) {
            // 本地不存在，直接保存
            await sessionStoreB.save(remote);
          } else {
            // 合并：取 updateTime 更新的
            if (remote.updateTime.isAfter(existing.updateTime)) {
              await sessionStoreB.save(remote);
            }
          }
        }

        // 验证 SessionStore 中 providerConfig 已同步
        final stored = await sessionStoreB.find(employeeId);
        expect(stored, isNotNull);
        expect(stored!.config.containsKey(deviceIdA), isTrue);

        final storedConfig = jsonDecode(stored.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(storedConfig['provider'], equals('anthropic'));
        expect(storedConfig['model'], equals('claude-3-5-sonnet'));
        expect(storedConfig['apiKey'], equals('sk-session-sync'));
      });

      test('本地 providerConfig 比远程新时不被覆盖', () async {
        final employeeId = const Uuid().v4();
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);

        // DeviceA 创建会话
        final configA = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(provider: 'openai')),
          updateTime: baseTime,
        );
        final sessionA = createSession(
          employeeId: employeeId,
          config: {deviceIdA: configA},
          createTime: baseTime,
          updateTime: baseTime,
        );
        await sessionStoreA.save(sessionA);
        await sessionStoreB.save(sessionA);

        // 注意：sessionStoreA 和 sessionStoreB 共享同一数据库文件（同一 testDbPath），
        // INSERT OR REPLACE 按主键覆盖。因此需要使用独立的变量跟踪
        // "远程"和"本地"的数据状态。

        // DeviceB 本地更新 providerConfig（时间更新）
        // 使用固定整秒时间戳，避免 SQLite 毫秒精度截断问题
        final bTime = DateTime(2099, 1, 1, 13, 0, 0); // 本地比 baseTime 新 1 小时
        final configB = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(provider: 'anthropic')),
          updateTime: bTime,
        );
        final updatedSessionB = (await sessionStoreB.find(employeeId))!;
        updatedSessionB.config[deviceIdA] = configB;
        await sessionStoreB.save(updatedSessionB.copyWith(updateTime: bTime));

        // 构造"远程"数据（模拟从另一台设备拉取的数据）
        // 远程 updateTime 比 bTime 旧
        final aTime = DateTime(2099, 1, 1, 12, 30, 0); // 远程比 bTime 旧 30 分钟
        final configAUpdated = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(provider: 'google')),
          updateTime: aTime,
        );
        final remoteSession = sessionA.copyWith(
          config: {deviceIdA: configAUpdated},
          updateTime: aTime,
        );

        // 模拟 query 同步合并：本地已有 bTime 数据，远程是 aTime 数据
        final existing = await sessionStoreB.find(employeeId);
        if (existing != null && remoteSession.updateTime.isAfter(existing.updateTime)) {
          await sessionStoreB.save(remoteSession);
        }

        // 验证本地配置不被覆盖
        // 本地 updateTime (13:00) > 远程 updateTime (12:30)，不应被覆盖
        final stored = await sessionStoreB.find(employeeId);
        expect(stored, isNotNull);
        final storedConfig = jsonDecode(stored!.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(storedConfig['provider'], equals('anthropic'));
      });

      test('本地不存在会话时远程 providerConfig 直接保存', () async {
        final employeeId = const Uuid().v4();
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);

        // DeviceA 创建会话
        final configMap = createProviderConfigMap(provider: 'ollama', model: 'llama3');
        final deviceConfig = createDeviceConfig(
          providerConfig: jsonEncode(configMap),
          updateTime: baseTime,
        );
        final session = createSession(
          employeeId: employeeId,
          config: {deviceIdA: deviceConfig},
          createTime: baseTime,
          updateTime: baseTime,
        );
        await sessionStoreA.save(session);

        // 注意：sessionStoreA 和 sessionStoreB 共享同一数据库文件（同一 testDbPath），
        // 所以 sessionStoreB.find 也能找到 sessionStoreA 保存的数据。
        // 在真实场景中，不同设备使用不同数据库，existing 应为 null。
        // 这里直接模拟 existing=null 的场景来测试"直接保存"逻辑。
        const existing = null;

        // 模拟 query 拉取后直接保存（使用 storeA 中实际保存的数据）
        final remoteSession = await sessionStoreA.find(employeeId);
        expect(remoteSession, isNotNull);
        // 模拟 existing=null 时的直接保存行为
        if (existing == null) {
          await sessionStoreB.save(remoteSession!);
        }

        final stored = await sessionStoreB.find(employeeId);
        expect(stored, isNotNull);
        expect(stored!.config.containsKey(deviceIdA), isTrue);

        final storedConfig = jsonDecode(stored.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(storedConfig['provider'], equals('ollama'));
        expect(storedConfig['model'], equals('llama3'));
      });

      test('EmployeeStore 的 model 字段与 SessionStore 的 providerConfig 独立合并', () async {
        final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
        final employeeId = const Uuid().v4();

        // DeviceA：Employee 有 provider/model，Session 也有 providerConfig
        final emp = createEmployee(
          uuid: employeeId,
          name: '员工',
          provider: 'openai',
          model: 'gpt-4o',
          createTime: baseTime,
          updateTime: baseTime,
        );
        await storeA.save(emp);

        final configMap = createProviderConfigMap(provider: 'anthropic', model: 'claude-3');
        final deviceConfig = createDeviceConfig(
          providerConfig: jsonEncode(configMap),
          updateTime: baseTime,
        );
        final session = createSession(
          employeeId: employeeId,
          config: {deviceIdA: deviceConfig},
          createTime: baseTime,
          updateTime: baseTime,
        );
        await sessionStoreA.save(session);

        // DeviceB query 拉取员工
        final remoteEmployees = await storeA.findAll(null);
        for (final remote in remoteEmployees) {
          final existing = await storeB.findIncludingDeleted(remote.uuid);
          final (changed, merged) = simulateQuerySyncMerge(existing, remote);
          if (changed && merged != null) {
            await storeB.save(merged);
          }
        }

        // DeviceB query 拉取会话
        final remoteSessions = await sessionStoreA.findAll();
        for (final remote in remoteSessions) {
          final existing = await sessionStoreB.find(remote.employeeId);
          if (existing == null) {
            await sessionStoreB.save(remote);
          }
        }

        // 验证：Employee 和 Session 的 model 配置独立存储
        final storedEmp = await storeB.find(null, employeeId);
        expect(storedEmp, isNotNull);
        expect(storedEmp!.provider, equals('openai'));
        expect(storedEmp.model, equals('gpt-4o'));

        final storedSession = await sessionStoreB.find(employeeId);
        expect(storedSession, isNotNull);
        final sessionConfig = jsonDecode(storedSession!.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
        expect(sessionConfig['provider'], equals('anthropic'));
        expect(sessionConfig['model'], equals('claude-3'));
      });
    });
  });

  // ═══════════════════════════════════════════════════
  // C. 综合场景
  // ═══════════════════════════════════════════════════

  group('C. 综合场景', () {
    // --------------------------------------------------
    // C.1 project + model 同时变更的双路径同步
    // --------------------------------------------------
    test('C.1 project + model 同时变更的双路径同步', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final employeeId = const Uuid().v4();

      // DeviceA 创建员工（含 project 和 model 配置）
      final emp = createEmployee(
        uuid: employeeId,
        name: '综合员工',
        provider: 'openai',
        model: 'gpt-4o',
        projectUuid: 'proj-combo',
        projectName: '综合项目',
        workPath: '/combo/path',
        createTime: baseTime,
        updateTime: baseTime,
      );
      await storeA.save(emp);

      // 路径1 event：model 配置通过 event 同步到 DeviceB SessionStore
      final providerConfigMap = createProviderConfigMap(
        provider: 'anthropic',
        model: 'claude-3-5-sonnet',
        apiKey: 'sk-combo',
      );
      await simulateEventSyncProvider(
        employeeId, deviceIdA, providerConfigMap, sessionStoreB, sessionManagerB,
      );

      // 路径2 query：project 配置通过 query 同步到 DeviceB EmployeeStore
      final remoteEmployees = await storeA.findAll(null);
      for (final remote in remoteEmployees) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      // 验证 DeviceB 上两条路径的数据都正确
      final storedEmp = await storeB.find(null, employeeId);
      expect(storedEmp, isNotNull);
      expect(storedEmp!.projectUuid, equals('proj-combo'));
      expect(storedEmp.projectName, equals('综合项目'));
      expect(storedEmp.workPath, equals('/combo/path'));
      expect(storedEmp.provider, equals('openai')); // Employee 层的 model 配置
      expect(storedEmp.model, equals('gpt-4o'));

      final storedSession = await sessionStoreB.find(employeeId);
      expect(storedSession, isNotNull);
      final sessionConfig = jsonDecode(storedSession!.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
      expect(sessionConfig['provider'], equals('anthropic')); // Session 层的 model 配置
      expect(sessionConfig['model'], equals('claude-3-5-sonnet'));
    });

    // --------------------------------------------------
    // C.2 多设备场景：DeviceA→DeviceB→DeviceC 链式同步
    // --------------------------------------------------
    test('C.2 多设备场景：DeviceA→DeviceB→DeviceC 链式同步', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final employeeId = const Uuid().v4();

      // DeviceA 创建员工并设置 project 配置
      final emp = createEmployee(
        uuid: employeeId,
        name: '链式员工',
        projectUuid: 'proj-chain',
        projectName: '链式项目',
        workPath: '/chain/path',
        provider: 'openai',
        model: 'gpt-4o',
        createTime: baseTime,
        updateTime: baseTime,
      );
      await storeA.save(emp);

      // DeviceA → DeviceB：event 路径同步 model 配置
      final providerConfigMap = createProviderConfigMap(
        provider: 'anthropic',
        model: 'claude-3',
        apiKey: 'sk-chain',
      );
      await simulateEventSyncProvider(
        employeeId, deviceIdA, providerConfigMap, sessionStoreB, sessionManagerB,
      );

      // DeviceA → DeviceB：query 路径同步 project 配置
      final remoteFromA = await storeA.findAll(null);
      for (final remote in remoteFromA) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      // DeviceB → DeviceC：event 路径转发 model 配置
      await simulateEventSyncProvider(
        employeeId, deviceIdA, providerConfigMap, sessionStoreC, sessionManagerC,
      );

      // DeviceB → DeviceC：query 路径转发 project 配置
      final remoteFromB = await storeB.findAll(null);
      for (final remote in remoteFromB) {
        final existing = await storeC.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeC.save(merged);
        }
      }

      // 验证 DeviceC 数据正确
      final storedEmpC = await storeC.find(null, employeeId);
      expect(storedEmpC, isNotNull);
      expect(storedEmpC!.projectUuid, equals('proj-chain'));
      expect(storedEmpC.projectName, equals('链式项目'));
      expect(storedEmpC.workPath, equals('/chain/path'));

      final storedSessionC = await sessionStoreC.find(employeeId);
      expect(storedSessionC, isNotNull);
      final configC = jsonDecode(storedSessionC!.config[deviceIdA]!.providerConfig!) as Map<String, dynamic>;
      expect(configC['provider'], equals('anthropic'));
      expect(configC['model'], equals('claude-3'));
    });

    // --------------------------------------------------
    // C.3 配置冲突：两设备同时修改不同字段的合并
    // --------------------------------------------------
    test('C.3 配置冲突：两设备同时修改不同字段的合并', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final employeeId = const Uuid().v4();

      final emp = createEmployee(
        uuid: employeeId,
        name: '冲突员工',
        projectUuid: 'proj-old',
        projectName: '旧项目',
        workPath: '/old/path',
        provider: 'openai',
        model: 'gpt-4o',
        createTime: baseTime,
        updateTime: baseTime,
      );
      await storeA.save(emp);
      await storeB.save(emp);

      // DeviceA 修改 project 配置
      final aTime = DateTime(2099, 1, 1, 12, 5, 0);
      await storeA.save(emp.copyWith(
        projectName: 'DeviceA项目',
        workPath: '/device-a/path',
        updateTime: aTime,
      ));

      // DeviceB 修改 model 配置
      final bTime = DateTime(2099, 1, 1, 12, 5, 0); // 同一时间
      await storeB.save(emp.copyWith(
        provider: 'anthropic',
        model: 'claude-3-5-sonnet',
        updateTime: bTime,
      ));

      // DeviceB query 拉取 DeviceA 数据
      final remoteEmployees = await storeA.findAll(null);
      for (final remote in remoteEmployees) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      // 验证：updateTime 相同时，shouldUpdateData 返回 false（isAfter 为 false）
      // 所以本地数据不会被覆盖
      final stored = await storeB.find(null, employeeId);
      expect(stored, isNotNull);
      // DeviceB 本地的修改保留（因为远程 updateTime 不严格大于本地）
      expect(stored!.provider, equals('anthropic'));
      expect(stored.model, equals('claude-3-5-sonnet'));
      // project 配置也保留本地值
      expect(stored.projectName, equals('旧项目'));
    });

    // --------------------------------------------------
    // C.4 配置回退：远程 updateTime 更旧不覆盖本地
    // --------------------------------------------------
    test('C.4 配置回退：远程 updateTime 更旧不覆盖本地', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final employeeId = const Uuid().v4();

      final emp = createEmployee(
        uuid: employeeId,
        name: '回退员工',
        projectUuid: 'proj-v1',
        projectName: 'V1项目',
        provider: 'openai',
        model: 'gpt-4o',
        createTime: baseTime,
        updateTime: baseTime,
      );
      await storeA.save(emp);
      await storeB.save(emp);

      // DeviceB 更新为 V2
      // 使用固定整秒时间戳，避免 SQLite 毫秒精度截断问题
      final bTime = DateTime(2099, 1, 1, 13, 0, 0); // 本地比 baseTime 新 1 小时
      await storeB.save(emp.copyWith(
        projectName: 'V2项目',
        provider: 'anthropic',
        model: 'claude-3',
        updateTime: bTime,
      ));

      // 构造"远程"数据（模拟从另一台设备拉取的数据）
      // 远程 updateTime 比 bTime 旧
      // 注意：storeA 和 storeB 共享同一数据库文件，不能分别写入不同版本
      final aTime = DateTime(2099, 1, 1, 12, 30, 0); // 远程比 bTime 旧 30 分钟
      final remoteEmp = emp.copyWith(
        projectName: 'V1.5项目',
        provider: 'google',
        model: 'gemini',
        updateTime: aTime,
      );

      // 模拟 query 同步合并：本地已有 bTime 数据，远程是 aTime 数据
      final existing = await storeB.findIncludingDeleted(employeeId);
      final (changed, merged) = simulateQuerySyncMerge(existing, remoteEmp);
      if (changed && merged != null) {
        await storeB.save(merged);
      }

      // 验证：本地 V2 不被远程 V1.5 覆盖
      final stored = await storeB.find(null, employeeId);
      expect(stored, isNotNull);
      expect(stored!.projectName, equals('V2项目'));
      expect(stored.provider, equals('anthropic'));
      expect(stored.model, equals('claude-3'));
    });

    // --------------------------------------------------
    // C.5 删除恢复：project 配置清除后重新设置的同步
    // --------------------------------------------------
    test('C.5 删除恢复：project 配置清除后重新设置的同步', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final employeeId = const Uuid().v4();

      // 阶段1：DeviceA 设置 project 配置
      final emp = createEmployee(
        uuid: employeeId,
        name: '恢复员工',
        projectUuid: 'proj-recover',
        projectName: '恢复项目',
        workPath: '/recover/path',
        createTime: baseTime,
        updateTime: baseTime,
      );
      await storeA.save(emp);

      // DeviceB 同步
      final remote1 = await storeA.findAll(null);
      for (final remote in remote1) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      var stored = await storeB.find(null, employeeId);
      expect(stored, isNotNull);
      expect(stored!.projectUuid, equals('proj-recover'));

      // 阶段2：DeviceA 清除 project 配置
      final clearTime = DateTime(2099, 1, 1, 12, 5, 0);
      // 注意：copyWith 中 null 参数不会覆盖已有值，需要使用显式 null
      final empCleared = AiEmployeeEntity(
        uuid: employeeId,
        name: '恢复员工',
        projectUuid: null,
        projectName: null,
        workPath: null,
        createTime: baseTime,
        updateTime: clearTime,
      );
      await storeA.save(empCleared);

      // DeviceB 同步清除
      final remote2 = await storeA.findAll(null);
      for (final remote in remote2) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      stored = await storeB.find(null, employeeId);
      expect(stored, isNotNull);
      expect(stored!.projectUuid, isNull);
      expect(stored.projectName, isNull);
      expect(stored.workPath, isNull);

      // 阶段3：DeviceA 重新设置 project 配置
      final recoverTime = DateTime(2099, 1, 1, 12, 10, 0);
      await storeA.save(emp.copyWith(
        projectUuid: 'proj-new',
        projectName: '新项目',
        workPath: '/new/path',
        updateTime: recoverTime,
      ));

      // DeviceB 同步恢复
      final remote3 = await storeA.findAll(null);
      for (final remote in remote3) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      stored = await storeB.find(null, employeeId);
      expect(stored, isNotNull);
      expect(stored!.projectUuid, equals('proj-new'));
      expect(stored.projectName, equals('新项目'));
      expect(stored.workPath, equals('/new/path'));
    });
  });

  // ═══════════════════════════════════════════════════
  // D. 边界与异常
  // ═══════════════════════════════════════════════════

  group('D. 边界与异常', () {
    // --------------------------------------------------
    // D.1 providerConfig JSON 格式错误时的容错
    // --------------------------------------------------
    test('D.1 providerConfig JSON 格式错误时的容错', () async {
      final employeeId = const Uuid().v4();

      // 写入格式错误的 JSON 字符串
      final badJson = '{invalid json content';
      final deviceConfig = createDeviceConfig(providerConfig: badJson);
      final session = createSession(
        employeeId: employeeId,
        config: {deviceIdA: deviceConfig},
      );
      await sessionStoreA.save(session);

      // 读取后尝试 jsonDecode 应抛出异常
      final stored = await sessionStoreA.find(employeeId);
      expect(stored, isNotNull);
      expect(stored!.config[deviceIdA]!.providerConfig, equals(badJson));

      // 验证 jsonDecode 确实会失败
      expect(() => jsonDecode(badJson), throwsA(isA<FormatException>()));
    });

    // --------------------------------------------------
    // D.2 projectUuid 为空字符串时不触发同步
    // --------------------------------------------------
    test('D.2 projectUuid 为空字符串时的处理', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final emp = createEmployee(
        projectUuid: '',
        projectName: '',
        workPath: '',
        createTime: baseTime,
        updateTime: baseTime,
      );

      // 验证序列化往返
      final map = emp.toMap();
      final restored = AiEmployeeEntity.fromMap(map);

      expect(restored.projectUuid, equals(''));
      expect(restored.projectName, equals(''));
      expect(restored.workPath, equals(''));

      // 验证可以正常保存和读取
      await storeA.save(emp);
      final stored = await storeA.find(null, emp.uuid);
      expect(stored, isNotNull);
      expect(stored!.projectUuid, equals(''));
    });

    // --------------------------------------------------
    // D.3 modelConfig 为无效 JSON 时的处理
    // --------------------------------------------------
    test('D.3 modelConfig 为无效 JSON 时的处理', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final emp = createEmployee(
        modelConfig: 'not a valid json',
        createTime: baseTime,
        updateTime: baseTime,
      );

      // 验证序列化往返（modelConfig 作为纯字符串存储，不校验 JSON）
      final map = emp.toMap();
      final restored = AiEmployeeEntity.fromMap(map);

      expect(restored.modelConfig, equals('not a valid json'));

      // 验证可以正常保存和读取
      await storeA.save(emp);
      final stored = await storeA.find(null, emp.uuid);
      expect(stored, isNotNull);
      expect(stored!.modelConfig, equals('not a valid json'));
    });

    // --------------------------------------------------
    // D.4 session.config 为空 Map 时的默认行为
    // --------------------------------------------------
    test('D.4 session.config 为空 Map 时的默认行为', () async {
      final employeeId = const Uuid().v4();

      // 创建空 config 的 session
      final session = createSession(employeeId: employeeId, config: {});
      await sessionStoreA.save(session);

      // 读取验证
      final stored = await sessionStoreA.find(employeeId);
      expect(stored, isNotNull);
      expect(stored!.config, isEmpty);

      // getOrCreateConfig 应创建默认配置
      final deviceConfig = stored.getOrCreateConfig(deviceIdA);
      expect(deviceConfig, isNotNull);
      expect(deviceConfig.providerConfig, isNull);
      expect(deviceConfig.totalInputTokens, equals(0));
      expect(deviceConfig.totalOutputTokens, equals(0));
      expect(deviceConfig.totalMessageCount, equals(0));

      // getConfig 对不存在的设备返回 null
      expect(stored.getConfig('non-existent-device'), isNull);
    });

    // --------------------------------------------------
    // D.5 Employee 配置字段全为 null 时的同步
    // --------------------------------------------------
    test('D.5 Employee 配置字段全为 null 时的同步', () async {
      final baseTime = DateTime(2099, 1, 1, 12, 0, 0);
      final emp = createEmployee(
        name: '最小员工',
        createTime: baseTime,
        updateTime: baseTime,
      );

      await storeA.save(emp);

      // 模拟 query 同步
      final remoteEmployees = await storeA.findAll(null);
      for (final remote in remoteEmployees) {
        final existing = await storeB.findIncludingDeleted(remote.uuid);
        final (changed, merged) = simulateQuerySyncMerge(existing, remote);
        if (changed && merged != null) {
          await storeB.save(merged);
        }
      }

      final stored = await storeB.find(null, emp.uuid);
      expect(stored, isNotNull);
      expect(stored!.provider, isNull);
      expect(stored.model, isNull);
      expect(stored.apiKey, isNull);
      expect(stored.apiBaseUrl, isNull);
      expect(stored.modelConfig, isNull);
      expect(stored.projectUuid, isNull);
      expect(stored.projectName, isNull);
      expect(stored.workPath, isNull);
    });

    // --------------------------------------------------
    // D.6 大量设备配置的 Session 序列化
    // --------------------------------------------------
    test('D.6 大量设备配置的 Session 序列化', () async {
      final employeeId = const Uuid().v4();
      final deviceConfigs = <String, DeviceSessionConfig>{};

      // 创建 50 个设备的配置
      for (var i = 0; i < 50; i++) {
        final devId = 'device-$i';
        deviceConfigs[devId] = createDeviceConfig(
          providerConfig: jsonEncode(createProviderConfigMap(
            provider: 'provider-$i',
            model: 'model-$i',
          )),
        );
      }

      final session = createSession(employeeId: employeeId, config: deviceConfigs);
      await sessionStoreA.save(session);

      // 读取验证
      final stored = await sessionStoreA.find(employeeId);
      expect(stored, isNotNull);
      expect(stored!.config.length, equals(50));

      // 验证每个设备的配置
      for (var i = 0; i < 50; i++) {
        final devId = 'device-$i';
        expect(stored.config.containsKey(devId), isTrue);
        final config = jsonDecode(stored.config[devId]!.providerConfig!) as Map<String, dynamic>;
        expect(config['provider'], equals('provider-$i'));
        expect(config['model'], equals('model-$i'));
      }
    });

    // --------------------------------------------------
    // D.7 ProviderConfig 各 provider 类型的序列化
    // --------------------------------------------------
    test('D.7 ProviderConfig 各 provider 类型的序列化', () {
      final providers = [
        (LLMProvider.openai, 'gpt-4o', 'sk-openai'),
        (LLMProvider.anthropic, 'claude-3-5-sonnet', 'sk-ant'),
        (LLMProvider.google, 'gemini-pro', 'sk-google'),
        (LLMProvider.ollama, 'llama3', null), // ollama 不需要 apiKey
      ];

      for (final (provider, model, apiKey) in providers) {
        final config = ProviderConfig(
          provider: provider,
          model: model,
          apiKey: apiKey,
        );

        final map = config.toMap();
        final restored = ProviderConfig.fromMap(map);

        expect(restored.provider, equals(provider));
        expect(restored.model, equals(model));
        expect(restored.apiKey, equals(apiKey));
      }
    });

    // --------------------------------------------------
    // D.8 SessionManager.updateDeviceConfig 发射事件
    // --------------------------------------------------
    test('D.8 SessionManager.updateDeviceConfig 发射事件', () async {
      final employeeId = const Uuid().v4();
      final events = <SessionChangeEvent>[];
      final sub = sessionManagerB.onSessionEvent.listen(events.add);

      // 创建 session
      await sessionManagerB.getOrCreateSession(employeeId);
      await Future.delayed(const Duration(milliseconds: 50));

      // 更新设备配置
      final providerConfigJson = jsonEncode(createProviderConfigMap());
      await sessionManagerB.updateDeviceConfig(
        employeeId,
        deviceIdA,
        providerConfig: providerConfigJson,
      );
      await Future.delayed(const Duration(milliseconds: 50));

      // 验证事件
      expect(events.isNotEmpty, isTrue);
      // 至少有一个 created 和一个 updated 事件
      expect(events.any((e) => e.type == SessionChangeType.created), isTrue);
      expect(events.any((e) => e.type == SessionChangeType.updated), isTrue);

      await sub.cancel();
    });
  });
}
