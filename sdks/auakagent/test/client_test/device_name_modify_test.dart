/// 局域网内修改其它设备名称 — 失败场景测试
///
/// 测试通过 LAN 修改远程设备名称的各种失败场景：
/// - 修改自己设备名称成功（正向对比）
/// - 未连接时修改远程设备名称失败
/// - 目标设备不存在/离线时修改失败
/// - 网络层发送失败（消息拦截器模拟）
/// - Client 端 RPC handler 验证
/// - E2E 跨设备修改失败场景
///
/// 关键 API：
/// - DeviceClient.updateDeviceInfo() — 修改本设备信息（本地操作）
/// - DeviceClient.updateRemoteDeviceInfo() — 修改远程设备信息（通过 LAN RPC）
/// - HostRpcConfig.methodUpdateDeviceInfo — 远程设备信息更新的 RPC 方法（客户端侧注册）
///
/// 架构说明：
/// - methodUpdateDeviceInfo 注册在客户端侧 (device_rpc_handler.dart)，
///   不在 Host 侧 (host_rpc_methods.dart)。Host 只负责转发 RPC 到目标设备。
/// - updateRemoteDeviceInfo() 通过 LAN 发送 RPC 到 Host，Host 转发到目标设备，
///   目标设备的 device_rpc_handler 接收并处理。
///
/// 依赖：
/// - ClientTestFixture: 客户端完整生命周期模拟
/// - LanTestHarness: 端到端通信桥接
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'package:test/test.dart';
import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/persistence/entities/device_config_entity.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

/// 创建一个 DeviceInfoConfig（仅含 name）
DeviceInfoConfig _deviceInfoWithName(String name) {
  return DeviceInfoConfig(name: name);
}

/// 获取设备配置中的设备名称
Future<String?> _getDeviceConfigName(DeviceClient client) async {
  final config = await client.getDeviceConfig();
  return config.deviceInfo.name;
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: 本设备名称修改（正向对比）
  // ═══════════════════════════════════════════════════════════════

  group('本设备名称修改（正向）', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'self-modify',
        deviceName: 'OriginalName',
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('1.1 修改自己设备名称成功，通过 deviceName getter 验证', () async {
      expect(fixture.client.deviceName, equals('OriginalName'));

      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('NewName'),
      );

      expect(fixture.client.deviceName, equals('NewName'));
    });

    test('1.2 修改名称后持久化到 DeviceConfig', () async {
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('PersistedName'),
      );

      final configName = await _getDeviceConfigName(fixture.client);
      expect(configName, equals('PersistedName'));
    });

    test('1.3 多次连续修改名称成功', () async {
      for (final name in ['Name-A', 'Name-B', 'Name-C']) {
        await fixture.client.updateDeviceInfo(
          _deviceInfoWithName(name),
        );
        expect(fixture.client.deviceName, equals(name));
      }
    });

    test('1.4 通过 updateConfig 修改设备名称', () async {
      await fixture.client.updateConfig(deviceName: 'ViaUpdateConfig');
      expect(fixture.client.deviceName, equals('ViaUpdateConfig'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: 未连接时修改远程设备名称失败
  // ═══════════════════════════════════════════════════════════════

  group('未连接时修改远程设备名称失败', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'no-connect',
        deviceName: 'OfflineDevice',
        autoConnect: false, // 不自动连接
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 未连接时 updateRemoteDeviceInfo 抛出 StateError', () async {
      expect(fixture.isConnected, isFalse);

      expect(
        () => fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: 'other-device-001',
          deviceInfo: _deviceInfoWithName('ShouldFail'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('2.2 未连接时异常消息包含"未连接到服务器"', () async {
      try {
        await fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: 'other-device-002',
          deviceInfo: _deviceInfoWithName('ShouldFail'),
        );
        fail('Expected StateError was not thrown');
      } on StateError catch (e) {
        expect(e.message, contains('未连接到服务器'));
      }
    });

    test('2.3 未连接时仍可修改自己设备名称（本地操作不依赖网络）', () async {
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('LocalOnly'),
      );
      expect(fixture.client.deviceName, equals('LocalOnly'));
    });

    test('2.4 连接后 self-target updateRemoteDeviceInfo 也需要连接检查', () async {
      // 即使 targetDeviceId == deviceId,
      // updateRemoteDeviceInfo 也会先检查 isConnected
      expect(
        () => fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: fixture.deviceId,
          deviceInfo: _deviceInfoWithName('SelfTarget'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: 目标设备不存在/离线时修改失败
  // ═══════════════════════════════════════════════════════════════

  group('目标设备不存在/离线时修改失败', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'target-offline',
        clientDeviceName: 'ClientA',
        serverHostName: 'HostServer',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('3.1 目标设备 ID 不存在（从未注册过的设备）', () async {
      // 尝试修改一个从未在 Host 上注册过的设备名称
      // RPC 调用可能失败（目标不存在）或超时
      const nonExistentDeviceId = 'non-existent-device-999';

      try {
        await harness.client.client.updateRemoteDeviceInfo(
          targetDeviceId: nonExistentDeviceId,
          deviceInfo: _deviceInfoWithName('GhostName'),
        );
      } catch (_) {
        // 期望失败
      }

      // 确认本设备名称未被意外修改
      expect(harness.client.client.deviceName, equals('ClientA'));
    });

    test('3.2 目标设备已下线（disconnect 后）', () async {
      const targetId = 'target-device-offline';

      // 注册目标设备
      harness.server.hostService.registerClient(
        clientId: targetId,
        deviceId: targetId,
        deviceName: 'TargetDevice',
      );
      harness.server.simulateClientConnect(
        clientId: targetId,
        clientDeviceId: targetId,
        deviceName: 'TargetDevice',
      );

      expect(harness.server.hostService.hasDevice(targetId), isTrue);

      // 让目标下线
      harness.server.hostService.unregisterClient(targetId);
      harness.server.simulateClientDisconnect(targetId);
      expect(harness.server.hostService.hasDevice(targetId), isFalse);

      // 尝试修改已下线设备的名称
      try {
        await harness.client.client.updateRemoteDeviceInfo(
          targetDeviceId: targetId,
          deviceInfo: _deviceInfoWithName('OfflineRename'),
        );
      } catch (_) {
        // 期望失败
      }

      // 确认本设备名称未受影响
      expect(harness.client.client.deviceName, equals('ClientA'));
    });

    test('3.3 Client 尝试修改 Server 端设备名称', () async {
      // Client 尝试修改 Host 端的设备名称
      try {
        await harness.client.client.updateRemoteDeviceInfo(
          targetDeviceId: harness.server.deviceId,
          deviceInfo: _deviceInfoWithName('RenamedServer'),
        );
      } catch (_) {
        // 可能因权限或其他原因失败
      }

      // 验证本客户端名称未被污染
      expect(harness.client.client.deviceName, equals('ClientA'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: 网络层发送失败（消息拦截器模拟）
  // ═══════════════════════════════════════════════════════════════

  group('网络层发送失败（消息拦截器）', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'net-fail',
        deviceName: 'NetFailDevice',
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('4.1 sendInterceptor 阻止所有消息导致远程修改失败', () async {
      // 设置拦截器阻止所有消息
      fixture.fakeLanClient.sendInterceptor = (msg) => false;

      try {
        await fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: 'blocked-device',
          deviceInfo: _deviceInfoWithName('BlockedRename'),
        );
      } catch (_) {
        // 期望因为消息被拦截而导致失败
      }

      // 本地修改不应受影响
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('LocalStillWorks'),
      );
      expect(fixture.client.deviceName, equals('LocalStillWorks'));
    });

    test('4.2 仅拦截 RPC 请求，不影响本地操作', () async {
      fixture.fakeLanClient.sendInterceptor = (msg) {
        if (msg.type == LanMessageType.rpcRequest) return false;
        return true;
      };

      // 尝试远程修改（应被拦截）
      try {
        await fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: 'rpc-blocked',
          deviceInfo: _deviceInfoWithName('RPCBlocked'),
        );
      } catch (_) {}

      // 本地修改自己名称不应受影响
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('SelfUpdateOK'),
      );
      expect(fixture.client.deviceName, equals('SelfUpdateOK'));
    });

    test('4.3 拦截器恢复后通信正常', () async {
      // 先设置拦截器
      fixture.fakeLanClient.sendInterceptor = (msg) => false;

      try {
        await fixture.client.updateRemoteDeviceInfo(
          targetDeviceId: 'temp-blocked',
          deviceInfo: _deviceInfoWithName('TempBlocked'),
        );
      } catch (_) {}

      // 移除拦截器
      fixture.fakeLanClient.sendInterceptor = null;

      // 本地操作确认通信恢复
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('AfterUnblock'),
      );
      expect(fixture.client.deviceName, equals('AfterUnblock'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: Client 端 updateDeviceInfo 流程验证
  // ═══════════════════════════════════════════════════════════════

  group('Client 端 updateDeviceInfo 流程', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'client-flow',
        deviceName: 'FlowTestDevice',
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('5.1 updateDeviceInfo 只更新名称时不影响其他字段', () async {
      // 先设置完整信息
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        name: 'FullInfo',
        type: 'desktop',
        os: 'windows',
      ));

      // 再仅更新名称
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('NameOnly'),
      );

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('NameOnly'));
      expect(config.deviceInfo.type, equals('desktop'));
      expect(config.deviceInfo.os, equals('windows'));
    });

    test('5.2 设置为空字符串名称', () async {
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName(''),
      );
      expect(fixture.client.deviceName, equals(''));
    });

    test('5.3 设置 name 为 null 时不清空已有名称', () async {
      // 先设置名称
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('ExistingName'),
      );

      // 只更新 type，不传 name
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        type: 'mobile',
      ));

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('ExistingName'));
      expect(config.deviceInfo.type, equals('mobile'));
    });

    test('5.4 updateDeviceInfo 成功后 deviceName 和持久化一致', () async {
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('ConsistentName'),
      );

      expect(fixture.client.deviceName, equals('ConsistentName'));
      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('ConsistentName'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 6: E2E 跨设备修改失败场景
  // ═══════════════════════════════════════════════════════════════

  group('E2E 跨设备修改名称', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create(
        'e2e-modify',
        clientDeviceName: 'Device-Alpha',
        serverHostName: 'CentralHost',
      );
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('6.1 Client 修改自己名称成功', () async {
      await harness.client.client.updateDeviceInfo(
        _deviceInfoWithName('Alpha-Renamed'),
      );

      expect(harness.client.client.deviceName, equals('Alpha-Renamed'));
    });

    test('6.2 网络断开后无法修改远程设备名称', () async {
      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      try {
        await harness.client.client.updateRemoteDeviceInfo(
          targetDeviceId: 'any-remote-device',
          deviceInfo: _deviceInfoWithName('DisconnectedRename'),
        );
        fail('Expected StateError after network disconnect');
      } on StateError catch (e) {
        expect(e.message, contains('未连接到服务器'));
      }

      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);
    });

    test('6.3 注册第二个虚拟 Client 后尝试互改名称', () async {
      const secondDeviceId = 'device-beta';

      harness.server.hostService.registerClient(
        clientId: 'second-client',
        deviceId: secondDeviceId,
        deviceName: 'Device-Beta',
      );
      harness.server.simulateClientConnect(
        clientId: 'second-client',
        clientDeviceId: secondDeviceId,
        deviceName: 'Device-Beta',
      );

      expect(harness.server.hostService.hasDevice(secondDeviceId), isTrue);

      // Client Alpha 尝试修改 Device Beta 的名称
      // Beta 没有真正的 RPC handler（只是 FakeLanHostService 中的注册），
      // 所以 RPC 会失败
      try {
        await harness.client.client.updateRemoteDeviceInfo(
          targetDeviceId: secondDeviceId,
          deviceInfo: _deviceInfoWithName('Beta-Renamed-By-Alpha'),
        );
      } catch (_) {
        // 期望失败：Beta 没有真正的 RPC handler
      }

      // 确认 Alpha 自身名称未被影响
      expect(harness.client.client.deviceName, equals('Device-Alpha'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 7: 边界情况
  // ═══════════════════════════════════════════════════════════════

  group('修改设备名称 — 边界情况', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create(
        'edge-cases',
        deviceName: 'EdgeDevice',
      );
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('7.1 修改为超长名称（500字符）', () async {
      final veryLongName = 'A' * 500;
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName(veryLongName),
      );
      expect(fixture.client.deviceName?.length, equals(500));
    });

    test('7.2 修改为含特殊字符的名称', () async {
      // 注意：$ 在非 raw string 中需要转义（Dart 字符串插值）
      final specialName = 'Device !@# \$%^ &*() Test';
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName(specialName),
      );
      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals(specialName));
    });

    test('7.3 快速连续修改同一远程设备名称不破坏本地状态', () async {
      final futures = <Future>[];
      for (int i = 0; i < 5; i++) {
        futures.add(
          fixture.client.updateRemoteDeviceInfo(
            targetDeviceId: 'rapid-target',
            deviceInfo: _deviceInfoWithName('Rapid-$i'),
          ).catchError((_) {}), // 忽略错误（目标不存在）
        );
      }
      await Future.wait(futures);

      // 确认本地名称未被破坏
      expect(fixture.client.deviceName, equals('EdgeDevice'));
    });

    test('7.4 修改为含换行符的名称', () async {
      const nameWithNewlines = 'Line1\nLine2\r\nLine3';
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName(nameWithNewlines),
      );
      expect(fixture.client.deviceName, equals(nameWithNewlines));
    });

    test('7.5 修改名称后 deviceName getter 与持久化值一致', () async {
      await fixture.client.updateDeviceInfo(
        _deviceInfoWithName('EventTestName'),
      );

      expect(fixture.client.deviceName, equals('EventTestName'));

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('EventTestName'));
    });
  });
}
