/// 客户端功能测试示例
///
/// 演示如何使用 client_test 基础类编写各类功能测试场景：
/// - 客户端生命周期
/// - 员工 CRUD
/// - 会话管理
/// - 服务端 RPC 调用
/// - 端到端通信
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/service.dart';

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
  String? currentDeviceId,
  String status = 'active',
  int deleted = 0,
}) {
  final now = DateTime.now();
  return AiEmployeeEntity(
    uuid: uuid ?? const Uuid().v4(),
    name: name ?? '测试员工',
    deviceId: deviceId,
    currentDeviceId: currentDeviceId,
    status: status,
    deleted: deleted,
    createTime: now,
    updateTime: now,
  );
}

// ═══════════════════════════════════════════════════════════════
// Group 1: ClientTestFixture 基础用法
// ═══════════════════════════════════════════════════════════════

void main() {
  group('ClientTestFixture 基础用法', () {
    late ClientTestFixture fixture;

    setUp(() async {
      fixture = await ClientTestFixture.create('basic');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('初始化后 DeviceClient 处于已连接状态', () {
      expect(fixture.client.isInitialized, isTrue);
      expect(fixture.isConnected, isTrue);
      expect(fixture.client.deviceId, isNotEmpty);
    });

    test('可以创建和查询员工', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'Alice',
        deviceId: fixture.deviceId,
      );

      await fixture.employeeManager.createEmployee(employee);

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found, isNotNull);
      expect(found!.name, equals('Alice'));
      expect(found.deviceId, equals(fixture.deviceId));
    });

    test('可以更新员工信息', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'Bob',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(employee);

      // 更新
      final updated = AiEmployeeEntity(
        uuid: empId,
        name: 'Bob Updated',
        deviceId: fixture.deviceId,
        currentDeviceId: fixture.deviceId,
        status: 'active',
        deleted: 0,
        createTime: employee.createTime,
        updateTime: DateTime.now(),
      );
      await fixture.employeeManager.updateEmployee(updated);

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found!.name, equals('Bob Updated'));
    });

    test('可以删除员工', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'Charlie',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(employee);

      await fixture.employeeManager.deleteEmployee(empId);

      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found, isNull);
    });

    test('可以查询员工列表', () async {
      for (int i = 0; i < 3; i++) {
        await fixture.employeeManager.createEmployee(
          _createEmployee(name: 'Employee-$i', deviceId: fixture.deviceId),
        );
      }

      final employees = await fixture.employeeManager.getEmployees();
      expect(employees.length, greaterThanOrEqualTo(3));
    });

    test('可以创建和查询会话', () async {
      final empId = const Uuid().v4();
      await fixture.employeeManager.createEmployee(
        _createEmployee(uuid: empId, name: 'SessionTest', deviceId: fixture.deviceId),
      );

      final session = await fixture.sessionManager.getOrCreateSession(empId);
      expect(session, isNotNull);
      expect(session.employeeId, equals(empId));

      final found = await fixture.sessionManager.getSession(empId);
      expect(found, isNotNull);
    });

    test('可以注入和接收 LAN 消息', () async {
      // 直接验证 FakeLanClientService 的消息流工作正常
      final received = <LanMessage>[];
      final sub = fixture.fakeLanClient.messageStream.listen((msg) {
        received.add(msg);
      });

      fixture.fakeLanClient.injectMessage(LanMessage(
        type: LanMessageType.pong,
        fromId: 'host',
        content: 'ping-response',
      ));

      // 等待广播流事件调度
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(received, isNotEmpty);
      expect(received.last.type, equals(LanMessageType.pong));
      expect(received.last.content, equals('ping-response'));
    });

    test('连接状态变更可被记录', () {
      // ClientTestFixture 在 autoConnect=true 时会模拟连接
      // 初始状态下 connectionStateHistory 可能有记录
      expect(fixture.connectionStateHistory, isNotNull);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 2: ServerTestFixture 基础用法
  // ═══════════════════════════════════════════════════════════════

  group('ServerTestFixture 基础用法', () {
    late ServerTestFixture fixture;

    setUp(() async {
      fixture = await ServerTestFixture.create('server-basic');
    });

    tearDown(() async {
      await fixture.dispose();
    });

    test('初始化后 Host 服务正在运行', () {
      expect(fixture.hostService.isRunning, isTrue);
      expect(fixture.hostService.port, equals(9090));
    });

    test('所有 Host RPC 方法已注册', () {
      expect(fixture.hasRpcMethod(HostRpcConfig.methodSyncEmployees), isTrue);
      expect(fixture.hasRpcMethod(HostRpcConfig.methodSyncSessions), isTrue);
      expect(fixture.hasRpcMethod(HostRpcConfig.methodGetEmployees), isTrue);
      expect(fixture.hasRpcMethod(HostRpcConfig.methodGetSessions), isTrue);
    });

    test('可以通过 callRpc 调用 Host RPC 方法', () async {
      // 创建员工
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'RPC-Test-Employee',
        deviceId: fixture.deviceId,
      );
      await fixture.employeeManager.createEmployee(employee);

      // 通过 RPC 查询
      final result = await fixture.callRpc(
        HostRpcConfig.methodGetEmployees,
        {},
      );

      expect(result, isNotNull);
      expect(result['employees'], isNotNull);
    });

    test('可以模拟客户端连接和断开', () {
      final clientId = 'test-client-1';
      final clientDeviceId = 'test-device-1';

      fixture.simulateClientConnect(
        clientId: clientId,
        clientDeviceId: clientDeviceId,
        deviceName: 'TestDevice',
      );

      expect(fixture.hostService.hasDevice(clientDeviceId), isTrue);
      expect(fixture.hostService.onlineDeviceCount, equals(1));

      fixture.simulateClientDisconnect(clientId);

      expect(fixture.hostService.hasDevice(clientDeviceId), isFalse);
      expect(fixture.hostService.onlineDeviceCount, equals(0));
    });

    test('可以模拟客户端发送消息', () async {
      final clientId = 'test-client-2';
      fixture.simulateClientConnect(
        clientId: clientId,
        clientDeviceId: 'device-2',
      );

      final message = LanMessage(
        type: LanMessageType.text,
        fromId: clientId,
        content: 'Hello from client',
      );

      fixture.simulateClientMessage(clientId: clientId, message: message);

      // 等待消息传播
      await Future.delayed(Duration(milliseconds: 50));

      expect(fixture.receivedMessages, isNotEmpty);
      expect(fixture.receivedMessages.last.content, equals('Hello from client'));
    });

    test('员工同步 RPC 方法正常工作', () async {
      final empId = const Uuid().v4();
      final employee = _createEmployee(
        uuid: empId,
        name: 'Sync-Test-Employee',
        deviceId: 'remote-device',
      );

      // 调用同步 RPC
      final result = await fixture.callRpc(
        HostRpcConfig.methodSyncEmployees,
        {'employees': [employee.toMap()]},
      );

      expect(result['count'], equals(1));

      // 验证同步后本地有该员工
      final found = await fixture.employeeManager.getEmployee(empId);
      expect(found, isNotNull);
      expect(found!.name, equals('Sync-Test-Employee'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 3: LanTestHarness 端到端通信
  // ═══════════════════════════════════════════════════════════════

  group('LanTestHarness 端到端通信', () {
    late LanTestHarness harness;

    setUp(() async {
      harness = await LanTestHarness.create('e2e');
    });

    tearDown(() async {
      await harness.dispose();
    });

    test('Client 和 Server 都已初始化', () {
      expect(harness.client.client.isInitialized, isTrue);
      expect(harness.server.hostService.isRunning, isTrue);
      expect(harness.client.isConnected, isTrue);
    });

    test('消息桥接已启用', () {
      expect(harness.client.isConnected, isTrue);
      expect(harness.isBridgeEnabled, isTrue);
    });

    test('Client → Server 消息转发', () async {
      final message = LanMessage(
        type: LanMessageType.text,
        fromId: harness.client.deviceId,
        toDeviceId: harness.server.deviceId,
        content: 'Hello Server',
      );

      // 模拟 Client 发送消息
      harness.client.fakeLanClient.injectMessage(message);

      // 等待桥接转发
      await Future.delayed(Duration(milliseconds: 100));

      expect(harness.clientToHostMessages, isNotEmpty);
    });

    test('模拟网络断开和恢复', () {
      expect(harness.client.isConnected, isTrue);

      harness.simulateNetworkDisconnect();
      expect(harness.client.isConnected, isFalse);

      harness.simulateNetworkRecover();
      expect(harness.client.isConnected, isTrue);
    });

    test('清理后资源已释放', () async {
      // 这个测试验证 dispose 不抛异常
      final tempHarness = await LanTestHarness.create('cleanup-test');
      await tempHarness.dispose();
      // 如果没有异常则通过
      expect(true, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 4: FakeLanClientService 高级用法
  // ═══════════════════════════════════════════════════════════════

  group('FakeLanClientService 高级用法', () {
    test('消息拦截器可以阻止发送', () async {
      final fixture = await ClientTestFixture.create(
        'interceptor',
        autoConnect: true,
      );

      // 设置拦截器，阻止所有 ping 消息
      fixture.fakeLanClient.sendInterceptor = (msg) {
        return msg.type != LanMessageType.ping;
      };

      // 发送 ping（应被拦截）
      final pingResult = await fixture.fakeLanClient.sendLanMessage(
        LanMessage(type: LanMessageType.ping, fromId: fixture.deviceId),
      );
      expect(pingResult, isFalse);

      // 发送 text（应通过）
      final textResult = await fixture.fakeLanClient.sendLanMessage(
        LanMessage(type: LanMessageType.text, fromId: fixture.deviceId, content: 'ok'),
      );
      expect(textResult, isTrue);

      await fixture.dispose();
    });

    test('可以按类型查找已发送的消息', () async {
      final fixture = await ClientTestFixture.create('find-msg', autoConnect: true);

      await fixture.fakeLanClient.sendLanMessage(
        LanMessage(type: LanMessageType.text, content: 'hello'),
      );
      await fixture.fakeLanClient.sendLanMessage(
        LanMessage(type: LanMessageType.ping),
      );
      await fixture.fakeLanClient.sendLanMessage(
        LanMessage(type: LanMessageType.text, content: 'world'),
      );

      final textMsgs = fixture.fakeLanClient.findSentMessages(LanMessageType.text);
      expect(textMsgs.length, equals(2));

      final pingMsgs = fixture.fakeLanClient.findSentMessages(LanMessageType.ping);
      expect(pingMsgs.length, equals(1));

      await fixture.dispose();
    });

    test('可以模拟上传和下载', () async {
      final fixture = await ClientTestFixture.create('file-ops', autoConnect: true);

      final fileId = await fixture.fakeLanClient.uploadFile('/test/file.txt');
      expect(fileId, isNotEmpty);
      expect(fixture.fakeLanClient.uploadedFiles, contains('/test/file.txt'));

      await fixture.fakeLanClient.downloadFile(fileId, '/test/download.txt');
      expect(fixture.fakeLanClient.downloadRequests.length, equals(1));
      expect(fixture.fakeLanClient.downloadRequests.first.fileId, equals(fileId));

      await fixture.dispose();
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // Group 5: FakeLanHostService 高级用法
  // ═══════════════════════════════════════════════════════════════

  group('FakeLanHostService 高级用法', () {
    test('广播消息发送到所有客户端', () async {
      final fixture = await ServerTestFixture.create('broadcast');
      fixture.simulateClientConnect(clientId: 'c1', clientDeviceId: 'd1');
      fixture.simulateClientConnect(clientId: 'c2', clientDeviceId: 'd2');

      fixture.hostService.broadcast(
        LanMessage.system('broadcast-test'),
      );

      final c1Msgs = fixture.getClientMessages('c1');
      final c2Msgs = fixture.getClientMessages('c2');

      expect(c1Msgs.length, equals(1));
      expect(c2Msgs.length, equals(1));
      expect(c1Msgs.first.content, equals('broadcast-test'));

      await fixture.dispose();
    });

    test('定向消息只发送到指定客户端', () async {
      final fixture = await ServerTestFixture.create('directed');
      fixture.simulateClientConnect(clientId: 'c1', clientDeviceId: 'd1');
      fixture.simulateClientConnect(clientId: 'c2', clientDeviceId: 'd2');

      fixture.hostService.sendToClient('c1', LanMessage.system('for-c1'));

      final c1Msgs = fixture.getClientMessages('c1');
      final c2Msgs = fixture.getClientMessages('c2');

      expect(c1Msgs.length, equals(1));
      expect(c2Msgs.length, equals(0));

      await fixture.dispose();
    });

    test('按 deviceId 发送消息', () async {
      final fixture = await ServerTestFixture.create('by-device-id');
      fixture.simulateClientConnect(clientId: 'c1', clientDeviceId: 'd1');

      fixture.hostService.sendToDeviceId('d1', LanMessage.system('for-d1'));

      final msgs = fixture.getClientMessages('c1');
      expect(msgs.length, equals(1));

      await fixture.dispose();
    });

    test('广播拦截器可以阻止消息', () async {
      final fixture = await ServerTestFixture.create('intercept');
      fixture.simulateClientConnect(clientId: 'c1', clientDeviceId: 'd1');

      fixture.hostService.broadcastInterceptor = (msg) {
        return msg.content != 'blocked';
      };

      fixture.hostService.broadcast(LanMessage.system('allowed'));
      fixture.hostService.broadcast(LanMessage.system('blocked'));

      final msgs = fixture.getClientMessages('c1');
      expect(msgs.length, equals(1));
      expect(msgs.first.content, equals('allowed'));

      await fixture.dispose();
    });

    test('文件保存和获取', () async {
      final fixture = await ServerTestFixture.create('files');

      final fileId = await fixture.hostService.saveFile(
        [1, 2, 3, 4, 5],
        'test.bin',
      );

      final data = await fixture.hostService.getFile(fileId);
      expect(data, equals([1, 2, 3, 4, 5]));

      await fixture.dispose();
    });
  });
}
