/// 端到端通信测试线束
///
/// 将 [ClientTestFixture] 和 [ServerTestFixture] 组合在一起，
/// 提供完整的 Client ↔ Host 通信模拟。
///
/// 核心设计：
/// - FakeLanHostService 作为消息中转枢纽
/// - Client 的 FakeLanClientService 发送的消息被转发到 Host
/// - Host 的广播/定向消息被转发到对应 Client
/// - 消息流通过 StreamController 桥接，无需真实 WebSocket
///
/// 使用方式：
/// ```dart
/// final harness = await LanTestHarness.create('e2e-test');
///
/// // Client 创建员工 → 通过 LAN 同步到 Server
/// await harness.clientFixture.employeeManager.createEmployee(employee);
///
/// // 验证 Server 端收到了同步消息
/// expect(harness.serverFixture.receivedMessages, isNotEmpty);
///
/// await harness.dispose();
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/utils/logger.dart';

import 'client_test_fixture.dart';
import 'fake_lan_client_service.dart';
import 'fake_lan_host_service.dart';
import 'server_test_fixture.dart';

/// 端到端通信测试线束
///
/// 模拟 [bin/auak_client.dart] + [bin/auak_server.dart] 的完整通信场景：
/// - Server 启动并监听
/// - Client 连接到 Server
/// - 双向消息传递（通过 Fake 桥接）
/// - RPC 请求/响应
///
/// 消息桥接机制：
/// ```
/// Client (FakeLanClientService)
///   ↓ sendLanMessage → _clientToHostBridge
/// Server (FakeLanHostService)
///   ↓ broadcast/sendToClient → _hostToClientBridge
/// Client (FakeLanClientService.injectMessage)
/// ```
class LanTestHarness {
  /// 服务端 Fixture
  final ServerTestFixture server;

  /// 客户端 Fixture
  final ClientTestFixture client;

  /// 日志记录器
  final Logger log;

  /// 桥接订阅列表
  final List<StreamSubscription> _bridgeSubs = [];

  /// 消息转发记录（Client → Host）
  final List<LanMessage> clientToHostMessages = [];

  /// 消息转发记录（Host → Client）
  final List<LanMessage> hostToClientMessages = [];

  /// 是否启用消息桥接
  bool _bridgeEnabled = false;

  LanTestHarness._({
    required this.server,
    required this.client,
  }) : log = Logger('LanTestHarness');

  /// 创建端到端测试线束
  ///
  /// [name] 测试名称。
  /// [serverPort] 服务端端口。
  /// [enableBridge] 是否自动启用消息桥接（默认 true）。
  /// [clientDeviceName] 客户端设备名称。
  /// [serverHostName] 服务端主机名称。
  /// [topic] 分组主题（Client 和 Server 需要一致）。
  ///
  /// 创建流程：
  /// 1. 创建 ServerTestFixture（启动 Host 服务）
  /// 2. 创建 ClientTestFixture（初始化 DeviceClient）
  /// 3. 在 FakeLanHostService 上注册客户端
  /// 4. （可选）启用双向消息桥接
  static Future<LanTestHarness> create(
    String name, {
    int serverPort = 9090,
    bool enableBridge = true,
    String? clientDeviceName,
    String? serverHostName,
    String? topic,
  }) async {
    // 1. 创建 Server
    final server = await ServerTestFixture.create(
      name,
      hostName: serverHostName,
      port: serverPort,
    );

    // 2. 创建 Client
    final client = await ClientTestFixture.create(
      name,
      host: '127.0.0.1',
      port: serverPort,
      deviceName: clientDeviceName,
      topic: topic,
      autoConnect: false, // 稍后手动连接
    );

    final harness = LanTestHarness._(server: server, client: client);

    // 3. 在 Host 上注册客户端
    server.hostService.registerClient(
      clientId: client.deviceId,
      deviceId: client.deviceId,
      deviceName: clientDeviceName ?? 'TestClient',
      topic: topic,
    );

    // 4. 模拟连接成功
    client.simulateConnect();

    // 5. 启用消息桥接
    if (enableBridge) {
      harness.enableBridge();
    }

    return harness;
  }

  // ═══════════════════════════════════════════════════════════════
  // 消息桥接
  // ═══════════════════════════════════════════════════════════════

  /// 启用双向消息桥接
  ///
  /// 将 Client 的 FakeLanClientService 发送的消息转发到 Host 的 messageStream，
  /// 将 Host 的广播/定向消息转发到 Client 的 messageStream。
  void enableBridge() {
    if (_bridgeEnabled) return;
    _bridgeEnabled = true;

    // Client → Host 桥接
    final clientToHost = client.fakeLanClient.messageStream.listen((msg) {
      clientToHostMessages.add(msg);
      // 将 Client 发送的消息注入到 Host 的 messageStream
      server.hostService.simulateClientMessage(
        clientId: client.deviceId,
        message: msg,
      );
    });
    _bridgeSubs.add(clientToHost);

    // Host → Client 桥接
    final hostToClient = server.hostService.messageStream.listen((msg) {
      // 只转发目标为本客户端的消息（或广播消息）
      if (msg.toDeviceId == null ||
          msg.toDeviceId == client.deviceId ||
          msg.toDeviceId!.isEmpty) {
        hostToClientMessages.add(msg);
        client.fakeLanClient.injectMessage(msg);
      }
    });
    _bridgeSubs.add(hostToClient);

    log.info('Message bridge enabled');
  }

  /// 禁用消息桥接
  void disableBridge() {
    if (!_bridgeEnabled) return;
    _bridgeEnabled = false;
    for (final sub in _bridgeSubs) {
      sub.cancel();
    }
    _bridgeSubs.clear();
    log.info('Message bridge disabled');
  }

  /// 是否已启用桥接
  bool get isBridgeEnabled => _bridgeEnabled;

  // ═══════════════════════════════════════════════════════════════
  // 快捷访问
  // ═══════════════════════════════════════════════════════════════

  /// 服务端 DeviceClient
  DeviceClient get serverClient => server.deviceClient;

  /// 客户端 DeviceClient
  DeviceClient get clientDevice => client.client;

  /// 服务端 FakeLanHostService
  FakeLanHostService get hostService => server.hostService;

  /// 客户端 FakeLanClientService
  FakeLanClientService get lanClientService => client.fakeLanClient;

  // ═══════════════════════════════════════════════════════════════
  // 场景模拟
  // ═══════════════════════════════════════════════════════════════

  /// 模拟网络断开
  ///
  /// Client 端模拟断开，同时在 Host 端注销客户端。
  void simulateNetworkDisconnect() {
    client.simulateDisconnect();
    server.hostService.unregisterClient(client.deviceId);
    log.info('Network disconnected');
  }

  /// 模拟网络恢复
  ///
  /// 重新注册客户端并模拟连接成功。
  void simulateNetworkRecover() {
    server.hostService.registerClient(
      clientId: client.deviceId,
      deviceId: client.deviceId,
    );
    client.simulateConnect();
    log.info('Network recovered');
  }

  /// 模拟 Client 发送 RPC 请求到 Server
  ///
  /// 通过桥接机制，将 RPC 请求从 Client 转发到 Server 的 RPC Server 处理。
  void sendRpcRequest({
    required String method,
    required Map<String, dynamic> params,
    String? requestId,
  }) {
    final id = requestId ?? DateTime.now().millisecondsSinceEpoch.toString();
    final payload = {
      'requestId': id,
      'method': method,
      'params': params,
      'fromDeviceId': client.deviceId,
      'toDeviceId': server.deviceId,
    };

    final message = LanMessage(
      id: id,
      type: LanMessageType.rpcRequest,
      fromId: client.deviceId,
      toDeviceId: server.deviceId,
      content: '{"payload": ${_encodeJson(payload)}}',
    );

    client.fakeLanClient.injectMessage(
      LanMessage.rpcRequest(
        id: id,
        fromId: client.deviceId,
        toDeviceId: server.deviceId,
        content: '{"payload": ${_encodeJson(payload)}}',
      ),
    );
  }

  /// 清空所有消息记录
  void clearMessages() {
    clientToHostMessages.clear();
    hostToClientMessages.clear();
    client.clearMessages();
    server.hostService.clearMessages();
    server.receivedMessages.clear();
  }

  // ═══════════════════════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════════════════════

  /// 释放所有资源
  ///
  /// 按顺序清理：禁用桥接 → 清理 Client → 清理 Server → 清理临时文件
  Future<void> dispose() async {
    disableBridge();
    await client.dispose();
    await server.dispose();
    log.info('Harness disposed');
  }

  // ═══════════════════════════════════════════════════════════════
  // 内部方法
  // ═══════════════════════════════════════════════════════════════

  String _encodeJson(Map<String, dynamic> data) {
    // 简单 JSON 编码（避免 import dart:convert 的额外开销）
    final parts = <String>[];
    data.forEach((key, value) {
      final v = value is String ? '"$value"' : value.toString();
      parts.add('"$key": $v');
    });
    return '{${parts.join(', ')}}';
  }
}
