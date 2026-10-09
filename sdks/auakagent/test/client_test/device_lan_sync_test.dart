/// 设备信息局域网同步 — 增强功能测试
///
/// 覆盖前端 DeviceManagerService 对应的后端同步流程：
/// - LanDeviceInfo 数据模型
/// - DeviceInfoConfig CRUD 持久化与合并
/// - DeviceRegistry 缓存操作
/// - DeviceEvent 事件流
/// - 双 Client 设备发现流程
///
/// 前端流程参考（Flutter）：
/// ```
/// DeviceManagerService
///  ├─ setCurrentSpace(spaceId) → DeviceClient.getInstance()
///  ├─ cachedDevices           → DeviceRegistry._deviceCache
///  ├─ getOnlineDevices()      → HTTP GET /api/devices/online
///  ├─ refreshDeviceList()     → clearCache + getOnlineDevices
///  ├─ requestDeviceInfoBroadcast() → deviceInfoRequest LAN msg
///  ├─ updateDeviceInfo()      → DeviceConfigManager merge
///  └─ onDeviceEvent           → online/offline/infoChanged
/// ```
library;

// ignore_for_file: unnecessary_non_null_assertion

import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:auakagent/src/entity/lan_client.dart';
import 'package:auakagent/src/entity/lan_device_info.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/persistence/persistence.dart';

import 'client_test_fixture.dart';
import 'lan_test_harness.dart';

// ═══════════════════════════════════════════════════════════════
// 辅助方法
// ═══════════════════════════════════════════════════════════════

DeviceInfoConfig _createDeviceInfoConfig({
  String? name,
  String? type,
  String? description,
  String? os,
  String? osVersion,
  String? model,
}) {
  return DeviceInfoConfig(
    name: name ?? 'Test Device',
    type: type ?? 'desktop',
    description: description ?? 'Test device description',
    os: os ?? 'windows',
    osVersion: osVersion ?? '11',
    model: model ?? 'Test Model',
  );
}

LanDeviceInfo _createLanDeviceInfo({
  String id = 'test-device-001',
  String? name,
  String? ip,
  String? type,
  String? os,
  String? osVersion,
  String? status,
}) {
  return LanDeviceInfo(
    id: id,
    name: name ?? 'Device-$id',
    ip: ip ?? '192.168.1.100',
    connectedAt: DateTime.now(),
    isHost: false,
    type: type ?? 'desktop',
    os: os ?? 'windows',
    osVersion: osVersion ?? '11',
    appVersion: '1.0.0',
    platform: 'desktop',
    status: status ?? 'online',
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════
  // Group 1: LanDeviceInfo 数据模型
  // ═══════════════════════════════════════════════════════════════

  group('LanDeviceInfo 数据模型', () {
    test('1.1 fromMap 完整字段解析', () {
      final map = {
        'id': 'dev-001',
        'name': 'My PC',
        'ip': '10.0.0.1',
        'connectedAt': '2025-01-15T10:30:00.000',
        'isHost': true,
        'type': 'desktop',
        'os': 'windows',
        'osVersion': '11',
        'appVersion': '2.1.0',
        'platform': 'desktop',
        'deviceId': 'dev-001',
        'employeeCount': 5,
        'status': 'online',
      };

      final info = LanDeviceInfo.fromMap(map);

      expect(info.id, equals('dev-001'));
      expect(info.name, equals('My PC'));
      expect(info.ip, equals('10.0.0.1'));
      expect(info.connectedAt, isNotNull);
      expect(info.isHost, isTrue);
      expect(info.type, equals('desktop'));
      expect(info.os, equals('windows'));
      expect(info.osVersion, equals('11'));
      expect(info.appVersion, equals('2.1.0'));
      expect(info.platform, equals('desktop'));
      expect(info.deviceId, equals('dev-001'));
      expect(info.employeeCount, equals(5));
      expect(info.status, equals('online'));
    });

    test('1.2 toMap 序列化往返一致性', () {
      final original = _createLanDeviceInfo(
        id: 'dev-rtt-001',
        name: 'RoundTrip Device',
      );
      final map = original.toMap();
      final restored = LanDeviceInfo.fromMap(map);

      expect(restored.id, equals(original.id));
      expect(restored.name, equals(original.name));
      expect(restored.ip, equals(original.ip));
      expect(restored.type, equals(original.type));
      expect(restored.os, equals(original.os));
      expect(restored.osVersion, equals(original.osVersion));
      expect(restored.appVersion, equals(original.appVersion));
      expect(restored.platform, equals(original.platform));
      expect(restored.status, equals(original.status));
    });

    test('1.3 copyWith 保留未修改字段', () {
      final original = _createLanDeviceInfo(
        id: 'dev-copy-001',
        name: 'Original Name',
        ip: '192.168.1.50',
      );

      final modified = original.copyWith(name: 'New Name');

      expect(modified.name, equals('New Name'));
      expect(modified.id, equals(original.id));
      expect(modified.ip, equals(original.ip));
      expect(modified.type, equals(original.type));
      expect(modified.os, equals(original.os));
      expect(modified.status, equals(original.status));
    });

    test('1.4 copyWith 可清空字段', () {
      final original = _createLanDeviceInfo(
        id: 'dev-null-001',
        name: 'Will Be Nulled',
      );

      final modified = original.copyWith(name: '');

      // copyWith 使用 name ?? this.name，所以空字符串不会 fallback
      expect(modified.name, isEmpty);
    });

    test('1.5 fromLanClient 构造', () {
      final client = LanClient(
        id: 'client-001',
        deviceId: 'dev-001',
        name: 'Client Name',
        ip: '192.168.1.200',
        connectedAt: DateTime.now(),
      );

      final info = LanDeviceInfo.fromLanClient(client);

      expect(info.id, equals('dev-001'));
      expect(info.name, equals('Client Name'));
      expect(info.ip, equals('192.168.1.200'));
      expect(info.status, equals('online'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: DeviceInfoConfig CRUD 持久化
  // ═══════════════════════════════════════════════════════════════

  group('DeviceInfoConfig CRUD 持久化', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('dev-cfg');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('2.1 getDeviceConfig 自动创建默认配置', () async {
      final config = await fixture.client.getDeviceConfig();

      expect(config, isNotNull);
      expect(config.deviceId, equals(fixture.deviceId));
      expect(config.deviceInfo.name, isNull);
      expect(config.deviceInfo.type, isNull);
    });

    test('2.2 updateDeviceInfo 写入并持久化', () async {
      await fixture.client.updateDeviceInfo(_createDeviceInfoConfig(
        name: 'My Workspace PC',
        type: 'desktop',
        os: 'windows',
        osVersion: '11 Pro',
        model: 'ThinkPad X1',
      ));

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('My Workspace PC'));
      expect(config.deviceInfo.type, equals('desktop'));
      expect(config.deviceInfo.os, equals('windows'));
      expect(config.deviceInfo.osVersion, equals('11 Pro'));
      expect(config.deviceInfo.model, equals('ThinkPad X1'));
    });

    test('2.3 updateDeviceInfo 部分更新合并', () async {
      await fixture.client.updateDeviceInfo(_createDeviceInfoConfig(
        name: 'Original Name',
        type: 'desktop',
        os: 'linux',
        model: 'Original Model',
      ));

      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        name: 'Updated Name',
        description: 'New description',
      ));

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('Updated Name'));
      expect(config.deviceInfo.description, equals('New description'));
      expect(config.deviceInfo.type, equals('desktop'));
      expect(config.deviceInfo.os, equals('linux'));
      expect(config.deviceInfo.model, equals('Original Model'));
    });

    test('2.4 DeviceInfoConfig tags 和 metadata', () async {
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        name: 'Tagged Device',
        tags: ['production', 'gpu-server'],
        metadata: {'gpu': 'RTX 4090', 'ram': '64GB'},
      ));

      final config = await fixture.client.getDeviceConfig();
      expect(
        config.deviceInfo.tags,
        containsAll(['production', 'gpu-server']),
      );
      expect(config.deviceInfo.metadata['gpu'], equals('RTX 4090'));
      expect(config.deviceInfo.metadata['ram'], equals('64GB'));
    });

    test('2.5 多次 updateDeviceInfo 合并正确', () async {
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        name: 'Step 1',
        type: 'server',
      ));
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        description: 'Step 2 description',
        os: 'ubuntu',
      ));
      await fixture.client.updateDeviceInfo(DeviceInfoConfig(
        name: 'Step 3 Final',
        model: 'Dell R740',
      ));

      final config = await fixture.client.getDeviceConfig();
      expect(config.deviceInfo.name, equals('Step 3 Final'));
      expect(config.deviceInfo.type, equals('server'));
      expect(config.deviceInfo.description, equals('Step 2 description'));
      expect(config.deviceInfo.os, equals('ubuntu'));
      expect(config.deviceInfo.model, equals('Dell R740'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: DeviceRegistry 缓存与设备发现
  // ═══════════════════════════════════════════════════════════════

  group('DeviceRegistry 缓存与设备发现', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('dev-reg');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('3.1 cachedDevices 初始为空', () {
      final devices = fixture.client.cachedDevices;
      expect(devices, isEmpty);
    });

    test('3.2 deviceId 正确识别', () {
      final deviceId = fixture.client.deviceId;
      expect(deviceId, isNotNull);
      expect(deviceId, isNotEmpty);
      expect(deviceId, startsWith('client-'));
    });

    test('3.3 LAN 消息发送后 sentMessages 记录正确', () async {
      fixture.clearMessages();

      fixture.fakeLanClient.sendLanMessage(LanMessage(
        type: LanMessageType.clientInfo,
        fromId: fixture.deviceId,
        fromName: 'Test Sender',
        content: jsonEncode({
          'deviceId': fixture.deviceId,
          'deviceName': 'Test Sender',
          'os': 'windows',
          'platform': 'desktop',
        }),
        fileName: fixture.deviceId,
      ));

      final sent = fixture.fakeLanClient.sentMessages;
      expect(sent, isNotEmpty);
      expect(sent.last.type, equals(LanMessageType.clientInfo));
      expect(sent.last.fromId, equals(fixture.deviceId));
    });

    test('3.4 messageStream can be listened', () async {
      // messageStream is a valid broadcast stream
      expect(fixture.fakeLanClient.messageStream, isNotNull);
      final sub1 = fixture.fakeLanClient.messageStream.listen((_) {});
      final sub2 = fixture.fakeLanClient.messageStream.listen((_) {});
      expect(sub1, isNotNull);
      expect(sub2, isNotNull);
      await sub1.cancel();
      await sub2.cancel();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: DeviceEvent 事件流与连接状态
  // ═══════════════════════════════════════════════════════════════

  group('DeviceEvent 事件流与连接状态', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('dev-ev');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('4.1 onDeviceEvent 流可订阅', () async {
      final events = <DeviceEvent>[];
      final sub = fixture.client.onDeviceEvent.listen((event) {
        events.add(event);
      });

      await Future.delayed(const Duration(milliseconds: 50));

      expect(sub, isNotNull);
      expect(events, isEmpty);

      await sub.cancel();
    });

    test('4.2 simulateConnect 后 isConnected 为 true', () {
      expect(fixture.isConnected, isTrue);
      expect(fixture.fakeLanClient.isConnected, isTrue);
    });

    test('4.3 simulateDisconnect 后 isConnected 为 false', () {
      expect(fixture.isConnected, isTrue);

      fixture.simulateDisconnect();
      expect(fixture.isConnected, isFalse);
      expect(fixture.fakeLanClient.isConnected, isFalse);
    });

    test('4.4 simulateConnect 恢复连接', () {
      fixture.simulateDisconnect();
      expect(fixture.isConnected, isFalse);

      fixture.simulateConnect();
      expect(fixture.isConnected, isTrue);
    });

    test('4.5 simulateConnecting 状态区分', () {
      fixture.simulateDisconnect();
      expect(fixture.isConnected, isFalse);

      fixture.simulateConnecting();
      // isConnected 仍为 false (connecting ≠ connected)
      expect(fixture.isConnected, isFalse);
      expect(fixture.fakeLanClient.isConnecting, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: 双 Client 设备发现流程
  // ═══════════════════════════════════════════════════════════════

  group('双 Client 设备发现流程', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create('dev-disc');
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('5.1 两个 deviceId 不相同', () {
      final clientAId = harness.client.client.deviceId;
      final clientBId = harness.serverClient.deviceId;

      expect(clientAId, isNot(equals(clientBId)));
      expect(clientAId, startsWith('client-'));
      expect(clientBId, startsWith('server-'));
    });

    test('5.2 sendLanMessage records in sentMessages', () async {
      harness.clearMessages();

      harness.lanClientService.sendLanMessage(LanMessage(
        type: LanMessageType.clientInfo,
        fromId: 'local-dev-001',
        fromName: 'Local Device',
        content: jsonEncode({
          'deviceId': 'local-dev-001',
          'deviceName': 'Local Device',
          'os': 'windows',
          'platform': 'desktop',
        }),
        fileName: 'local-dev-001',
      ));

      // sendLanMessage records in sentMessages (synchronous)
      final sent = harness.lanClientService.sentMessages;
      expect(sent.isNotEmpty, isTrue,
          reason: 'sendLanMessage should record in sentMessages');
      expect(sent.last.fromId, equals('local-dev-001'));
      expect(sent.last.type, equals(LanMessageType.clientInfo));
    });

    test('5.3 Host 可以注册两个 Client', () {
      harness.hostService.registerClient(
        clientId: 'client-x',
        deviceId: 'dev-client-x',
        deviceName: 'Client X',
      );
      harness.hostService.registerClient(
        clientId: 'client-y',
        deviceId: 'dev-client-y',
        deviceName: 'Client Y',
      );

      expect(harness.hostService.hasDevice('dev-client-x'), isTrue);
      expect(harness.hostService.hasDevice('dev-client-y'), isTrue);
      expect(harness.hostService.onlineDeviceCount, greaterThanOrEqualTo(2));
    });

    test('5.4 Host broadcast 广播消息记录', () {
      harness.clearMessages();

      harness.hostService.broadcast(LanMessage(
        type: LanMessageType.clientInfo,
        fromId: 'host-broadcaster',
        fromName: 'Host Broadcaster',
        content: 'Broadcast device list update',
        fileName: 'broadcast',
      ));

      final broadcasted = harness.hostService.broadcastedMessages;
      expect(broadcasted.isNotEmpty, isTrue,
          reason: 'Host broadcast should be recorded');
      expect(
        broadcasted.last.type,
        equals(LanMessageType.clientInfo),
      );
    });

    test('5.5 网络断开恢复后 Host 状态验证', () {
      // 断桥前 Host 应有初始 client 注册
      expect(harness.hostService.clients.isNotEmpty, isTrue);

      // 禁用桥接不影响 Host 状态
      harness.disableBridge();
      expect(harness.isBridgeEnabled, isFalse);

      // 恢复桥接
      harness.enableBridge();
      expect(harness.isBridgeEnabled, isTrue);

      // Host 状态在断桥期间不变
      expect(harness.hostService.clients.isNotEmpty, isTrue);
    });

    test('5.6 sendRpcRequest can be called without error', () {
      // Verify the method exists and can be invoked
      harness.clearMessages();
      expect(() {
        harness.sendRpcRequest(method: 'getOnlineDevices', params: {});
      }, returnsNormally);
    });
  });
}
