/// 设备信息同步 — 功能测试
///
/// 测试设备信息（DeviceInfoConfig）和在线设备列表的同步场景。
///
/// 关键 RPC 方法：
/// - methodGetOnlineDevices — 获取在线设备列表
/// - methodGetDeviceConfig — 获取设备配置（session 级别）
/// - methodUpdateDeviceConfig — 更新设备配置
/// - methodGetDeviceInfo — 获取设备信息
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - ServerTestFixture: 服务端完整生命周期模拟
/// - LanTestHarness: 端到端通信桥接
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';

import 'lan_test_harness.dart';
import 'server_test_fixture.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

AiEmployeeEntity _createEmployee({
  String? uuid,
  String? name,
  String? deviceId,
  String status = 'active',
}) {
  final now = DateTime.now();
  return AiEmployeeEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? 'Test Employee',
    deviceId: deviceId,
    status: status,
    createTime: now,
    updateTime: now,
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: Server 在线设备列表
  // ═══════════════════════════════════════════════════════════════

  group('Server 在线设备列表', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('device-list');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 getOnlineDevices returns device list', () async {
      // 注册一个模拟客户端
      fixture.simulateClientConnect(
        clientId: 'client-1',
        clientDeviceId: 'device-1',
        deviceName: 'TestDevice-A',
        topic: 'test-topic',
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodGetOnlineDevices,
        {},
      );

      expect(result['devices'], isNotNull);
      final devices = result['devices'] as List<dynamic>;
      expect(devices.length, greaterThanOrEqualTo(1));

      final deviceMap = devices.first as Map<String, dynamic>;
      expect(deviceMap['deviceId'], isNotNull);
    });

    test('1.2 multiple simulated clients', () {
      fixture.simulateClientConnect(
        clientId: 'c1', clientDeviceId: 'd1', deviceName: 'Device-One');
      fixture.simulateClientConnect(
        clientId: 'c2', clientDeviceId: 'd2', deviceName: 'Device-Two');
      fixture.simulateClientConnect(
        clientId: 'c3', clientDeviceId: 'd3', deviceName: 'Device-Three');

      expect(fixture.hostService.hasDevice('d1'), isTrue);
      expect(fixture.hostService.hasDevice('d2'), isTrue);
      expect(fixture.hostService.hasDevice('d3'), isTrue);
      expect(fixture.hostService.onlineDeviceCount, equals(3));
    });

    test('1.3 client disconnect removes device', () {
      fixture.simulateClientConnect(
        clientId: 'cx', clientDeviceId: 'dx', deviceName: 'TempDevice');

      expect(fixture.hostService.hasDevice('dx'), isTrue);
      expect(fixture.hostService.onlineDeviceCount, equals(1));

      fixture.simulateClientDisconnect('cx');

      expect(fixture.hostService.hasDevice('dx'), isFalse);
      expect(fixture.hostService.onlineDeviceCount, equals(0));
    });

    test('1.4 hasRpcMethod for device RPCs', () {
      expect(fixture.hasRpcMethod(
        HostRpcConfig.methodGetOnlineDevices), isTrue);
      expect(fixture.hasRpcMethod(
        HostRpcConfig.methodGetDeviceInfo), isTrue);
      expect(fixture.hasRpcMethod(
        HostRpcConfig.methodGetDeviceConfig), isTrue);
      expect(fixture.hasRpcMethod(
        HostRpcConfig.methodUpdateDeviceConfig), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: RPC 设备配置管理
  // ═══════════════════════════════════════════════════════════════

  group('RPC 设备配置管理', () {
    late ServerTestFixture fixture;
    late String employeeId;

    setUp(() async {
      fixture = await ServerTestFixture.create('devcfg-rpc');
      // Create an employee with a session
      employeeId = const Uuid().v4();
      await fixture.employeeManager.createEmployee(
        _createEmployee(uuid: employeeId, name: 'DeviceCfg Emp',
          deviceId: fixture.deviceId));
      await fixture.sessionManager.getOrCreateSession(employeeId);
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 updateDeviceConfig saves provider config', () async {
      final testDeviceId = 'test-device-config-1';

      final result = await fixture.callRpc(
        HostRpcConfig.methodUpdateDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': testDeviceId,
          'providerConfig': '{"provider":"openai","model":"gpt-4"}',
          'systemPromptOverride': 'You are a helpful assistant',
        },
      );
      expect(result['success'], isTrue);

      // Verify via methodGetDeviceConfig
      final getResult = await fixture.callRpc(
        HostRpcConfig.methodGetDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': testDeviceId,
        },
      );
      expect(getResult['deviceConfig'], isNotNull);
      final config = getResult['deviceConfig'] as Map<String, dynamic>;
      expect(config['providerConfig'], contains('openai'));
    });

    test('2.2 getDeviceConfig returns all configs without deviceId', () async {
      await fixture.callRpc(
        HostRpcConfig.methodUpdateDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': 'device-a',
          'providerConfig': '{}',
        },
      );
      await fixture.callRpc(
        HostRpcConfig.methodUpdateDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': 'device-b',
          'providerConfig': '{}',
        },
      );

      final result = await fixture.callRpc(
        HostRpcConfig.methodGetDeviceConfig,
        {'employeeId': employeeId},
      );

      expect(result['configs'], isNotNull);
      final configs = result['configs'] as Map<String, dynamic>;
      expect(configs.containsKey('device-a'), isTrue);
      expect(configs.containsKey('device-b'), isTrue);
    });

    test('2.3 updateDeviceConfig for systemPromptOverride only', () async {
      const testDeviceId = 'override-dev';

      await fixture.callRpc(
        HostRpcConfig.methodUpdateDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': testDeviceId,
          'systemPromptOverride': 'Custom system prompt for device',
        },
      );

      final getResult = await fixture.callRpc(
        HostRpcConfig.methodGetDeviceConfig,
        {
          'employeeId': employeeId,
          'deviceId': testDeviceId,
        },
      );

      final config = getResult['deviceConfig'] as Map<String, dynamic>;
      expect(config['systemPromptOverride'],
        equals('Custom system prompt for device'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 设备在线/离线事件模拟
  // ═══════════════════════════════════════════════════════════════

  group('设备在线/离线事件模拟', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'device-e2e',
        clientDeviceName: 'MyDevice',
        serverHostName: 'HostServer',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('3.1 client registered on host service', () {
      expect(harness.server.hostService
        .hasDevice(harness.client.deviceId), isTrue);
      expect(harness.server.hostService.onlineDeviceCount,
        greaterThanOrEqualTo(1));
    });

    test('3.2 client removed after disconnect', () {
      expect(harness.server.hostService
        .hasDevice(harness.client.deviceId), isTrue);

      harness.simulateNetworkDisconnect();

      expect(harness.server.hostService
        .hasDevice(harness.client.deviceId), isFalse);
    });

    test('3.3 client reappears after reconnect', () {
      harness.simulateNetworkDisconnect();
      harness.simulateNetworkRecover();

      expect(harness.client.isConnected, isTrue);
      expect(harness.server.hostService
        .hasDevice(harness.client.deviceId), isTrue);
    });

    test('3.4 hostService tracks online device count', () {
      final initialCount = harness.server.hostService.onlineDeviceCount;
      expect(initialCount, greaterThanOrEqualTo(1));

      harness.simulateNetworkDisconnect();
      expect(harness.server.hostService.onlineDeviceCount, equals(0));

      harness.simulateNetworkRecover();
      expect(harness.server.hostService.onlineDeviceCount, equals(1));
    });

    test('3.5 multiple client IDs for same deviceId', () {
      harness.server.hostService.registerClient(
        clientId: 'client-session-2',
        deviceId: harness.client.deviceId,
        deviceName: 'MyDevice-Session2',
      );

      expect(harness.server.hostService
        .hasDevice(harness.client.deviceId), isTrue);
      expect(harness.server.hostService.onlineDeviceCount,
        greaterThanOrEqualTo(1));
    });
  });
}
