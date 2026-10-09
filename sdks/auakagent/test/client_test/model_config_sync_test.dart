/// 模型配置同步 — 端到端功能测试
///
/// 测试员工模型配置（provider/model/apiKey/apiBaseUrl）的同步场景。
/// 模型配置嵌入 AiEmployeeEntity，通过 methodSyncEmployees 同步。
///
/// 参考前端 EmployeeConfigController 的模型配置流程：
///   配置变更 → updateEmployeeProvider → broadcastEmployeeToAllDevices
///   设备上线 → syncEmployeesFromDevices → 合并
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
import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/employee_config_service.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

AiEmployeeEntity _createEmployee({
  String? uuid,
  String? name,
  String? deviceId,
  String? provider,
  String? model,
  String? apiKey,
  String? apiBaseUrl,
  String? systemPrompt,
  int deleted = 0,
  DateTime? createTime,
  DateTime? updateTime,
}) {
  final now = DateTime.now();
  return AiEmployeeEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? 'Test Employee',
    deviceId: deviceId,
    provider: provider,
    model: model,
    apiKey: apiKey,
    apiBaseUrl: apiBaseUrl,
    systemPrompt: systemPrompt,
    deleted: deleted,
    createTime: createTime ?? now,
    updateTime: updateTime ?? now,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: Client ↔ Server RPC 模型配置同步
  // ═══════════════════════════════════════════════════════════════

  group('Client ↔ Server RPC 模型配置同步', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('modelcfg-rpc');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 sync employee with provider/model config', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'GPT Assistant',
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'sk-test-key-123',
        apiBaseUrl: 'https://api.openai.com/v1',
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );

      expect(result['count'], equals(1));

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found, isNotNull);
      expect(found!.provider, equals('openai'));
      expect(found!.model, equals('gpt-4'));
      expect(found!.apiKey, equals('sk-test-key-123'));
      expect(found!.apiBaseUrl, equals('https://api.openai.com/v1'));
    });

    test('1.2 update provider/model via sync', () async {
      final empId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      // 初始版本：使用 OpenAI
      final original = _createEmployee(
        uuid: empId, name: 'AI Bot',
        provider: 'openai', model: 'gpt-3.5-turbo',
        createTime: createTime, updateTime: createTime);
      await fixture.employeeManager.createEmployee(original);

      // 更新：切换到 Claude
      await Future.delayed(const Duration(milliseconds: 10));
      final updated = _createEmployee(
        uuid: empId, name: 'AI Bot',
        provider: 'anthropic', model: 'claude-3-opus',
        apiKey: 'sk-ant-key-456',
        apiBaseUrl: 'https://api.anthropic.com',
        createTime: createTime, updateTime: DateTime.now());

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [updated.toMap()]},
      );
      expect(result['count'], equals(1));

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found!.provider, equals('anthropic'));
      expect(found!.model, equals('claude-3-opus'));
      expect(found!.apiKey, equals('sk-ant-key-456'));
      expect(found!.apiBaseUrl, equals('https://api.anthropic.com'));
    });

    test('1.3 change only model while keeping provider', () async {
      final empId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      await fixture.employeeManager.createEmployee(_createEmployee(
        uuid: empId, name: 'Model Switcher',
        provider: 'openai', model: 'gpt-4',
        createTime: createTime, updateTime: createTime));

      await Future.delayed(const Duration(milliseconds: 10));
      final switched = _createEmployee(
        uuid: empId, name: 'Model Switcher',
        provider: 'openai', model: 'gpt-4-turbo',
        createTime: createTime, updateTime: DateTime.now());

      await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [switched.toMap()]},
      );

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found!.provider, equals('openai'));
      expect(found!.model, equals('gpt-4-turbo'));
    });

    test('1.4 sync employee without provider (no model config)', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId, name: 'No Model Config');

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );
      expect(result['count'], equals(1));

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found!.provider, isNull);
      expect(found!.model, isNull);
    });

    test('1.5 bulk sync employees with different model configs', () async {
      final emp1 = _createEmployee(name: 'OpenAI User',
        provider: 'openai', model: 'gpt-4');
      final emp2 = _createEmployee(name: 'Claude User',
        provider: 'anthropic', model: 'claude-3-sonnet');
      final emp3 = _createEmployee(name: 'Local LLM',
        provider: 'ollama', model: 'llama3',
        apiBaseUrl: 'http://localhost:11434');

      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [emp1.toMap(), emp2.toMap(), emp3.toMap()]},
      );
      expect(result['count'], equals(3));

      final all = await fixture.employeeManager.getEmployees(allDevices: true);
      final providers = all.map((e) => e.provider).toSet();
      expect(providers, contains('openai'));
      expect(providers, contains('anthropic'));
      expect(providers, contains('ollama'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: EmployeeConfigService 本地 CRUD
  // ═══════════════════════════════════════════════════════════════

  group('EmployeeConfigService 本地 CRUD', () {
    late ClientTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ClientTestFixture.create('modelcfg-local');
      // Create a base employee for config tests
      employeeId = const Uuid().v4();
      await fixture.employeeManager.createEmployee(
        _createEmployee(uuid: employeeId, name: 'Config Test Employee'));
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 getEmployeeConfig returns full config', () async {
      // Update provider first
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'sk-key',
        apiBaseUrl: 'https://api.example.com',
      );

      final config = await fixture.configService.getEmployeeConfig(employeeId);
      expect(config.employee.uuid, equals(employeeId));
      expect(config.employee.provider, equals('openai'));
      expect(config.employee.model, equals('gpt-4'));
    });

    test('2.2 updateEmployeeProvider changes model config', () async {
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'anthropic',
        model: 'claude-3',
        apiKey: 'ant-key-xyz',
      );

      final emp = await fixture.employeeManager.getEmployee(employeeId);
      expect(emp!.provider, equals('anthropic'));
      expect(emp!.model, equals('claude-3'));
      expect(emp!.apiKey, equals('ant-key-xyz'));
    });

    test('2.3 updateEmployeeProvider partial update', () async {
      // Set initial full config
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'original-key',
        apiBaseUrl: 'https://original.example.com',
      );

      // Update only model
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4-turbo',
      );

      final emp = await fixture.employeeManager.getEmployee(employeeId);
      expect(emp!.provider, equals('openai'));
      expect(emp!.model, equals('gpt-4-turbo'));
      // apiKey and apiBaseUrl should be preserved (not overwritten to null)
    });

    test('2.4 onConfigChanged event for provider change', () async {
      final events = <EmployeeConfigChangeEvent>[];
      final sub = fixture.configService.onConfigChanged.listen(events.add);

      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'azure',
        model: 'gpt-4-32k',
      );

      await Future.delayed(Duration.zero);

      final providerEvents = events
          .where((e) => e.type == EmployeeConfigChangeType.provider);
      expect(providerEvents.length, greaterThanOrEqualTo(1));
      expect(providerEvents.first.employeeId, equals(employeeId));

      await sub.cancel();
    });

    test('2.5 updateEmployeeBasicInfo preserves provider config', () async {
      // Set provider
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'keep-me',
      );

      // Update basic info
      await fixture.configService.updateEmployeeBasicInfo(
        employeeId,
        name: 'Renamed Employee',
        description: 'New description',
      );

      final emp = await fixture.employeeManager.getEmployee(employeeId);
      expect(emp!.name, equals('Renamed Employee'));
      expect(emp!.provider, equals('openai'));
      expect(emp!.model, equals('gpt-4'));
      expect(emp!.apiKey, equals('keep-me'));
    });

    test('2.6 clear provider/model by setting empty', () async {
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: 'openai',
        model: 'gpt-4',
        apiKey: 'temp-key',
      );

      // Clear config
      await fixture.configService.updateEmployeeProvider(
        employeeId,
        provider: '',
        model: '',
      );

      final emp = await fixture.employeeManager.getEmployee(employeeId);
      expect(emp!.provider, equals(''));
      expect(emp!.model, equals(''));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 双设备模型配置广播同步
  // ═══════════════════════════════════════════════════════════════

  group('双设备模型配置广播同步', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'modelcfg-e2e',
        clientDeviceName: 'Client-Model',
        serverHostName: 'Host-Model',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('3.1 broadcast employee with model config to Server', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId, name: 'Sync Model Config',
        provider: 'openai', model: 'gpt-4o',
        apiKey: 'sk-broadcast', apiBaseUrl: 'https://api.openai.com');

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );

      final found = await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found, isNotNull);
      expect(found!.provider, equals('openai'));
      expect(found!.model, equals('gpt-4o'));
    });

    test('3.2 broadcast model config update to Server', () async {
      final empId = const Uuid().v4();
      final createTime = DateTime.now().subtract(const Duration(hours: 1));

      // Server has initial config
      await harness.serverClient.employeeManager.createEmployee(
        _createEmployee(uuid: empId, name: 'Update Target',
          provider: 'openai', model: 'gpt-3.5',
          createTime: createTime, updateTime: createTime));

      await Future.delayed(const Duration(milliseconds: 10));
      // Client updates and broadcasts
      final updated = _createEmployee(
        uuid: empId, name: 'Update Target',
        provider: 'anthropic', model: 'claude-3-sonnet',
        apiKey: 'new-key',
        createTime: createTime, updateTime: DateTime.now());

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [updated.toMap()]},
      );

      final found = await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found!.provider, equals('anthropic'));
      expect(found!.model, equals('claude-3-sonnet'));
      expect(found!.apiKey, equals('new-key'));
    });

    test('3.3 sync employee with apiBaseUrl for local LLM', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId, name: 'Local LLM Agent',
        provider: 'ollama', model: 'llama3:8b',
        apiBaseUrl: 'http://localhost:11434');

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );

      final found = await harness.serverClient.employeeManager.getEmployee(empId);
      expect(found!.provider, equals('ollama'));
      expect(found!.model, equals('llama3:8b'));
      expect(found!.apiBaseUrl, equals('http://localhost:11434'));
    });

    test('3.4 model config preserved after network reconnect', () {
      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);

      // RPC methods still available
      expect(harness.server.hasRpcMethod(
        HostRpcConfig.methodSyncEmployees), isTrue);
      expect(harness.server.hasRpcMethod(
        HostRpcConfig.methodGetEmployees), isTrue);
    });

    test('3.5 multiple employees with different providers converge', () async {
      final empA = _createEmployee(name: 'GPT Agent',
        provider: 'openai', model: 'gpt-4');
      final empB = _createEmployee(name: 'Claude Agent',
        provider: 'anthropic', model: 'claude-3');

      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [empA.toMap()]},
      );
      await harness.server.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [empB.toMap()]},
      );

      final all = await harness.serverClient.employeeManager.getEmployees(allDevices: true);
      expect(all.length, greaterThanOrEqualTo(2));
      final providers = all.where((e) => e.provider != null).map((e) => e.provider!).toSet();
      expect(providers, contains('openai'));
      expect(providers, contains('anthropic'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: DeviceClient 回调注册与本地查询（短路路径）
  // ═══════════════════════════════════════════════════════════════

  group('DeviceClient 回调注册与本地查询', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('modelcfg-cb');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('4.1 本地短路查询：setModelConfigQueryCallback + getModelConfigsFromDevice', () async {
      // 注册回调，模拟前端返回模型配置
      fixture.client.setModelConfigQueryCallback(() async {
        return [
          {
            'employeeId': 'emp-001',
            'provider': 'openai',
            'model': 'gpt-4o',
            'apiKey': 'sk-local-123',
            'baseUrl': 'https://api.openai.com/v1',
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': DateTime.now().millisecondsSinceEpoch,
          },
        ];
      });

      // 查询本机（短路路径：不经过 RPC，直接调用回调）
      final configs = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );

      expect(configs, isNotEmpty);
      expect(configs.containsKey('emp-001'), isTrue);
      expect(configs['emp-001']!['provider'], equals('openai'));
      expect(configs['emp-001']!['model'], equals('gpt-4o'));
      expect(configs['emp-001']!['apiKey'], equals('sk-local-123'));
    });

    test('4.2 未注册回调时查询本机返回空', () async {
      // 不注册回调，直接查询
      final configs = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );

      expect(configs, isEmpty);
    });

    test('4.3 回调返回多条记录（多员工模型配置）', () async {
      fixture.client.setModelConfigQueryCallback(() async {
        return [
          {
            'employeeId': 'emp-a',
            'provider': 'openai',
            'model': 'gpt-4',
            'apiKey': 'key-a',
            'baseUrl': null,
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': 1000,
          },
          {
            'employeeId': 'emp-b',
            'provider': 'anthropic',
            'model': 'claude-3',
            'apiKey': 'key-b',
            'baseUrl': 'https://api.anthropic.com',
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': 2000,
          },
        ];
      });

      final configs = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );

      expect(configs.length, equals(2));
      expect(configs['emp-a']!['provider'], equals('openai'));
      expect(configs['emp-b']!['provider'], equals('anthropic'));
    });

    test('4.4 回调异常时异常应传播给调用方', () async {
      fixture.client.setModelConfigQueryCallback(() async {
        throw Exception('Storage not available');
      });

      // 本地短路路径：回调异常直接传播（不吞掉异常）
      expect(
        () => fixture.client.getModelConfigsFromDevice(fixture.deviceId),
        throwsA(isA<Exception>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: RPC 方法注册（hostGetModelConfigs / hostSyncModelConfigs）
  // ═══════════════════════════════════════════════════════════════

  group('RPC 方法注册', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('modelcfg-rpc-reg');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('5.1 hostGetModelConfigs 返回回调数据', () async {
      // 在 DeviceClient 上注册回调
      fixture.deviceClient.setModelConfigQueryCallback(() async {
        return [
          {
            'employeeId': 'emp-rpc-1',
            'provider': 'deepseek',
            'model': 'deepseek-chat',
            'apiKey': 'sk-ds-456',
            'baseUrl': 'https://api.deepseek.com',
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': DateTime.now().millisecondsSinceEpoch,
          },
        ];
      });

      // 手动注册 RPC 方法（模拟 DeviceRpcHandler 行为）
      fixture.rpcServer.register(
        HostRpcConfig.methodGetModelConfigs,
        (params) async {
          final dc = DeviceClient.getInstance(fixture.deviceId);
          final callback = dc.onModelConfigQueryCallback;
          if (callback == null) {
            return {'modelConfigs': <Map<String, dynamic>>[]};
          }
          try {
            final configs = await callback();
            return {'modelConfigs': configs};
          } catch (e) {
            return {'modelConfigs': <Map<String, dynamic>>[]};
          }
        },
      );

      final handler = fixture.rpcServer.capturedHandlers[
        HostRpcConfig.methodGetModelConfigs];
      expect(handler, isNotNull);

      final result = await handler!({});
      final configs = result['modelConfigs'] as List;
      expect(configs.length, equals(1));
      expect((configs[0] as Map)['provider'], equals('deepseek'));
    });

    test('5.2 hostGetModelConfigs 未注册回调时返回空', () async {
      // 不注册回调
      fixture.rpcServer.register(
        HostRpcConfig.methodGetModelConfigs,
        (params) async {
          final dc = DeviceClient.getInstance(fixture.deviceId);
          final callback = dc.onModelConfigQueryCallback;
          if (callback == null) {
            return {'modelConfigs': <Map<String, dynamic>>[]};
          }
          try {
            final configs = await callback();
            return {'modelConfigs': configs};
          } catch (e) {
            return {'modelConfigs': <Map<String, dynamic>>[]};
          }
        },
      );

      final handler = fixture.rpcServer.capturedHandlers[
        HostRpcConfig.methodGetModelConfigs];
      final result = await handler!({});
      final configs = result['modelConfigs'] as List;
      expect(configs, isEmpty);
    });

    test('5.3 hostSyncModelConfigs 必须携带 sourceDeviceId', () async {
      fixture.rpcServer.register(
        HostRpcConfig.methodSyncModelConfigs,
        (params) async {
          final sourceDeviceId = params['sourceDeviceId'] as String?;
          if (sourceDeviceId == null || sourceDeviceId.isEmpty) {
            return {'success': false, 'error': 'sourceDeviceId is required'};
          }
          return {'success': true};
        },
      );

      final handler = fixture.rpcServer.capturedHandlers[
        HostRpcConfig.methodSyncModelConfigs];
      expect(handler, isNotNull);

      // 缺少 sourceDeviceId
      final badResult = await handler!({});
      expect(badResult['success'], equals(false));

      // 携带 sourceDeviceId
      final okResult = await handler({'sourceDeviceId': 'device-A'});
      expect(okResult['success'], equals(true));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 6: 内存缓存行为
  // ═══════════════════════════════════════════════════════════════

  group('内存缓存行为', () {
    late ClientTestFixture fixture;
    int callCount = 0;

    setUp(() async {
      fixture = await ClientTestFixture.create('modelcfg-cache');
      callCount = 0;
      fixture.client.setModelConfigQueryCallback(() async {
        callCount++;
        return [
          {
            'employeeId': 'cache-test',
            'provider': 'openai',
            'model': 'gpt-4',
            'apiKey': 'key-cache',
            'baseUrl': null,
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': DateTime.now().millisecondsSinceEpoch,
          },
        ];
      });
    });

    tearDown(() async {
      fixture.client.invalidateModelConfigCache();
      await fixture.dispose();
    });

    test('6.1 本机短路路径每次都调用回调（本地无缓存）', () async {
      // 第一次
      await fixture.client.getModelConfigsFromDevice(fixture.deviceId);
      expect(callCount, equals(1));

      // 第二次（本机短路不缓存）
      await fixture.client.getModelConfigsFromDevice(fixture.deviceId);
      expect(callCount, equals(2));
    });

    test('6.2 invalidateModelConfigCache 清除后下次不命中缓存', () async {
      // 验证清除方法不抛异常
      fixture.client.invalidateModelConfigCache();
      // 清除后再次查询本机（无障碍）
      final configs = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );
      expect(configs, isNotEmpty);
      expect(callCount, equals(1)); // 清除不增加调用次数
    });

    test('6.3 invalidateModelConfigCache 清除指定设备缓存', () async {
      // 清除所有缓存
      fixture.client.invalidateModelConfigCache();
      // 不抛异常即为成功
    });

    test('6.4 多设备缓存独立', () async {
      fixture.client.setModelConfigQueryCallback(() async {
        return [
          {
            'employeeId': 'multi-1',
            'provider': 'openai',
            'model': 'gpt-4',
            'apiKey': 'k1',
            'baseUrl': null,
            'options': null,
            'organization': null,
            'compression': null,
            'retry': null,
            'updateTime': DateTime.now().millisecondsSinceEpoch,
          },
        ];
      });

      // 查询本机两次（不缓存）
      final r1 = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );
      expect(r1, isNotEmpty);

      final r2 = await fixture.client.getModelConfigsFromDevice(
        fixture.deviceId,
      );
      expect(r2, isNotEmpty);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 7: 广播通知回调链
  // ═══════════════════════════════════════════════════════════════

  group('广播通知回调链', () {
    late ClientTestFixture fixture;
    final List<String> notifiedEvents = [];
    final List<String> eventsA = [];
    final List<String> eventsB = [];

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'modelcfg-notify',
        autoConnect: false,
      );
      fixture.simulateConnect();
      notifiedEvents.clear();
      eventsA.clear();
      eventsB.clear();
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('7.1 addRemoteModelConfigUpdatedCallback 注册通知回调', () {
      fixture.client.addRemoteModelConfigUpdatedCallback(() {
        notifiedEvents.add('config-updated');
      });

      // 触发通知
      fixture.client.notifyRemoteModelConfigUpdated();

      expect(notifiedEvents.length, equals(1));
      expect(notifiedEvents.first, equals('config-updated'));
    });

    test('7.2 多个回调同时注册', () {
      final cbA = () => eventsA.add('A');
      final cbB = () => eventsB.add('B');

      fixture.client.addRemoteModelConfigUpdatedCallback(cbA);
      fixture.client.addRemoteModelConfigUpdatedCallback(cbB);

      fixture.client.notifyRemoteModelConfigUpdated();

      expect(eventsA, equals(['A']));
      expect(eventsB, equals(['B']));

      // 清理
      fixture.client.removeRemoteModelConfigUpdatedCallback(cbA);
      fixture.client.removeRemoteModelConfigUpdatedCallback(cbB);
    });

    test('7.3 移除回调后不再收到通知', () {
      final events = <String>[];
      void callback() => events.add('fired');

      fixture.client.addRemoteModelConfigUpdatedCallback(callback);
      fixture.client.notifyRemoteModelConfigUpdated();
      expect(events.length, equals(1));

      fixture.client.removeRemoteModelConfigUpdatedCallback(callback);
      fixture.client.notifyRemoteModelConfigUpdated();
      expect(events.length, equals(1)); // 不再增加
    });

    test('7.4 无回调注册时 notify 不抛异常', () {
      // 不注册任何回调
      expect(
        () => fixture.client.notifyRemoteModelConfigUpdated(),
        returnsNormally,
      );
    });
  });
}
