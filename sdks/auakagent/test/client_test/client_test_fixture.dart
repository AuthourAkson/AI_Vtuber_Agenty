/// 客户端功能测试 Fixture
///
/// 模拟 [bin/auak_client.dart] 的完整生命周期：
/// 创建 DeviceClient → 初始化 → 连接 → 业务操作 → 断开 → 清理
///
/// 使用方式：
/// ```dart
/// // 在 setUp 中创建
/// final fixture = await ClientTestFixture.create('my-test');
///
/// // 执行业务操作
/// await fixture.client.employeeManager.createEmployee(employee);
///
/// // 清理（在 tearDown 中）
/// await fixture.dispose();
/// ```
library;

import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:auakagent/src/device/app_context.dart';
import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/service.dart';
import 'package:auakagent/src/utils/logger.dart';

import 'fake_lan_client_service.dart';

/// 全局测试计数器，确保每次生成的路径唯一
int _clientTestFixtureCounter = 0;

/// 客户端功能测试 Fixture
///
/// 封装了 [DeviceClient] 的完整初始化和清理流程，提供：
/// - 真实数据库和业务服务（EmployeeManager、SessionManager 等）
/// - 可控的 LAN 连接层（通过 [FakeLanClientService]）
/// - 便捷的消息注入和验证方法
/// - 自动清理临时资源
///
/// 设计参考 [bin/auak_client.dart] 的启动流程，但将 LAN 通信层
/// 替换为可编程的假实现，使测试不依赖真实网络。
class ClientTestFixture {
  /// 唯一标识
  final String id;

  /// 设备 ID
  final String deviceId;

  /// 临时数据库路径
  final String dbPath;

  /// 临时存储根路径
  final String storagePath;

  /// DeviceClient 实例
  final DeviceClient client;

  /// Fake LAN 客户端服务（可控）
  final FakeLanClientService fakeLanClient;

  /// 日志记录器
  final Logger log;

  /// 连接状态变更记录
  final List<DeviceConnectionState> connectionStateHistory = [];

  /// LAN 消息接收记录
  final List<LanMessage> receivedLanMessages = [];

  StreamSubscription<DeviceConnectionState>? _connStateSub;
  StreamSubscription<LanMessage>? _lanMsgSub;

  ClientTestFixture._({
    required this.id,
    required this.deviceId,
    required this.dbPath,
    required this.storagePath,
    required this.client,
    required this.fakeLanClient,
  }) : log = Logger('ClientTestFixture[$id]');

  /// 创建并初始化一个客户端测试 Fixture
  ///
  /// [name] 测试名称，用于生成唯一路径和设备 ID。
  /// [deviceName] 设备显示名称。
  /// [topic] 分组主题（可选）。
  /// [host] 服务器地址（默认 '127.0.0.1'）。
  /// [port] 服务器端口（默认 9090）。
  /// [autoConnect] 是否自动模拟连接（默认 true）。
  ///
  /// 初始化流程（参考 bin/auak_client.dart main 函数）：
  /// 1. 创建临时存储目录
  /// 2. 初始化 DeviceClient（含数据库）
  /// 3. 监听连接状态和 LAN 消息
  /// 4. （可选）模拟连接成功
  static Future<ClientTestFixture> create(
    String name, {
    String? deviceName,
    String? topic,
    String host = '127.0.0.1',
    int port = 9090,
    bool autoConnect = true,
  }) async {
    _clientTestFixtureCounter++;
    final id = '${name}_${_clientTestFixtureCounter}';
    final deviceId = 'client-$id-${const Uuid().v4().substring(0, 8)}';

    // 创建临时目录
    final storagePath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}auak_client_test_$id';
    final dbPath =
        '$storagePath${Platform.pathSeparator}db';
    await Directory(dbPath).create(recursive: true);

    // 创建 DeviceClient
    final client = DeviceClient.getInstance(deviceId);

    // 初始化（参考 bin client 的 initialize 步骤）
    await client.initialize(DeviceClientConfig(
      storagePath: storagePath,
      host: host,
      port: port,
      deviceName: deviceName ?? 'TestClient-$name',
      topic: topic,
    ));

    // 创建 FakeLanClientService
    final fakeLanClient = FakeLanClientService(
      deviceId: deviceId,
      topic: topic,
    );

    final fixture = ClientTestFixture._(
      id: id,
      deviceId: deviceId,
      dbPath: dbPath,
      storagePath: storagePath,
      client: client,
      fakeLanClient: fakeLanClient,
    );

    // 监听连接状态
    fixture._connStateSub = client.onConnectionStateChanged.listen((state) {
      fixture.connectionStateHistory.add(state);
      fixture.log.info('Connection state: ${state.name}');
    });

    // 监听 LAN 消息
    fixture._lanMsgSub = client.onLanMessage.listen((msg) {
      fixture.receivedLanMessages.add(msg);
    });

    // 模拟连接
    if (autoConnect) {
      await fixture.simulateConnect();
    }

    return fixture;
  }

  // ═══════════════════════════════════════════════════════════════
  // 业务服务快捷访问
  // ═══════════════════════════════════════════════════════════════

  EmployeeManager get employeeManager => client.employeeManager;

  SessionManager get sessionManager => client.sessionManager;

  SkillManager get skillManager => client.skillManager;

  MessageStoreService get messageStore => client.messageStore;

  EmployeeConfigService get configService => client.configService;

  GlobalSkillManager get globalSkillManager => client.globalSkillManager;

  ProjectManager get projectManager => client.projectManager;

  // ═══════════════════════════════════════════════════════════════
  // 连接模拟
  // ═══════════════════════════════════════════════════════════════

  /// 模拟连接成功
  ///
  /// 不经过真实 WebSocket，直接将 FakeLanClientService 设为已连接状态。
  Future<void> simulateConnect() async {
    fakeLanClient.simulateConnected();
  }

  /// 模拟断开连接
  void simulateDisconnect() {
    fakeLanClient.simulateDisconnected();
  }

  /// 模拟连接中状态
  void simulateConnecting() {
    fakeLanClient.simulateConnecting();
  }

  /// 获取当前连接状态
  bool get isConnected => fakeLanClient.isConnected;

  // ═══════════════════════════════════════════════════════════════
  // 消息注入与验证
  // ═══════════════════════════════════════════════════════════════

  /// 注入一条 LAN 消息到客户端
  ///
  /// 模拟从 Host 接收到消息。
  void injectLanMessage(LanMessage message) {
    fakeLanClient.injectMessage(message);
  }

  /// 查找客户端发送的指定类型消息
  List<LanMessage> findSentMessages(LanMessageType type) {
    return fakeLanClient.findSentMessages(type);
  }

  /// 查找客户端发送到指定设备的消息
  List<LanMessage> findSentToDevice(String toDeviceId) {
    return fakeLanClient.findSentToDevice(toDeviceId);
  }

  /// 获取客户端发送的所有消息
  List<LanMessage> get sentMessages => fakeLanClient.sentMessages;

  /// 清空消息记录
  void clearMessages() {
    fakeLanClient.clearSentMessages();
    receivedLanMessages.clear();
    connectionStateHistory.clear();
  }

  // ═══════════════════════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════════════════════

  /// 释放所有资源并清理临时文件
  ///
  /// 参考 bin client 的 shutdown 流程：
  /// 1. 取消订阅
  /// 2. 断开连接
  /// 3. 移除 DeviceClient 实例
  /// 4. 清理临时目录
  Future<void> dispose() async {
    await _connStateSub?.cancel();
    await _lanMsgSub?.cancel();

    // 断开连接
    try {
      await client.disconnect();
    } catch (_) {}

    // 移除 DeviceClient 实例（清理所有子模块）
    await DeviceClient.removeInstance(deviceId);

    // 释放 FakeLanClientService
    await fakeLanClient.dispose();

    // 清理临时目录
    try {
      final dir = Directory(storagePath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}

    log.info('Fixture disposed');
  }
}
