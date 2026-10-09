/// 服务端功能测试 Fixture
///
/// 模拟 [bin/auak_server.dart] 的完整生命周期：
/// 创建 DeviceClient → 初始化数据库 → 注册 RPC 方法 → 启动 Host 服务 → 业务操作 → 停止 → 清理
///
/// 使用方式：
/// ```dart
/// // 在 setUp 中创建
/// final fixture = await ServerTestFixture.create('my-server-test');
///
/// // 通过 RPC handler 直接调用
/// final handler = fixture.getHandler(HostRpcConfig.methodSyncEmployees);
/// await handler({'employees': [emp.toMap()]});
///
/// // 清理（在 tearDown 中）
/// await fixture.dispose();
/// ```
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';
import 'package:auakagent/src/device/app_context.dart';
import 'package:auakagent/src/device/device_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/host/client_session_manager.dart';
import 'package:auakagent/src/host/host_rpc_methods.dart';
import 'package:auakagent/src/lan/entity/client_info.dart';
import 'package:auakagent/src/lan/lan_client_service.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/rpc/remote_call_server.dart';
import 'package:auakagent/src/rpc/rpc_protocol.dart';
import 'package:auakagent/src/service/service.dart';
import 'package:auakagent/src/utils/logger.dart';

import 'fake_lan_host_service.dart';

/// 全局测试计数器
int _serverTestFixtureCounter = 0;

/// 捕获注册的 RPC Handler 的 RemoteCallServer 子类
///
/// 通过覆写 [register] 方法，将所有注册的 handler 记录到 [capturedHandlers] 中，
/// 便于测试直接调用特定方法而不需要经过消息传递。
class CapturingRpcServer extends RemoteCallServer {
  /// 已注册的同步方法 handler
  final Map<String, Future<Map<String, dynamic>> Function(Map<String, dynamic>)>
      capturedHandlers = {};

  /// 已注册的流式方法 handler
  final Map<String, Stream<RpcStreamEvent> Function(Map<String, dynamic>)>
      capturedStreamHandlers = {};

  CapturingRpcServer({
    required super.clientService,
    required super.localDeviceId,
  });

  @override
  void register(
    String method,
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) handler,
  ) {
    capturedHandlers[method] = handler;
    super.register(method, handler);
  }

  @override
  void registerStream(
    String method,
    Stream<RpcStreamEvent> Function(Map<String, dynamic>) handler,
  ) {
    capturedStreamHandlers[method] = handler;
    super.registerStream(method, handler);
  }
}

/// Host 端 LAN 客户端服务适配器
///
/// 参考 [bin/auak_server.dart] 中的 _HostLanClientServiceAdapter，
/// 将 FakeLanHostService 适配为 LanClientService 接口，
/// 使 RemoteCallServer 可以通过 Host 发送 RPC 响应。
class HostLanClientServiceAdapter implements LanClientService {
  final FakeLanHostService _hostService;

  HostLanClientServiceAdapter(this._hostService);

  @override
  bool get isConnected => _hostService.isRunning;

  @override
  bool get isConnecting => false;

  @override
  String get deviceId => '__host__';

  @override
  String? get topic => null;

  @override
  String? get hostIp => _hostService.localIp;

  @override
  int get hostPort => _hostService.port;

  @override
  Stream<LanMessage> get messageStream => const Stream.empty();

  @override
  double get uploadProgress => 0.0;

  @override
  double get downloadProgress => 0.0;

  @override
  Stream<BinaryChunkEvent> get binaryChunkStream => const Stream.empty();

  @override
  Future<void> connect(String hostIp, {int port = 9090}) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> reconnect() async {}

  @override
  void sendMessage(String content) {}

  @override
  Future<bool> sendLanMessage(LanMessage message) async {
    final toDeviceId = message.toDeviceId;
    if (toDeviceId != null && toDeviceId.isNotEmpty) {
      _hostService.sendToDeviceId(toDeviceId, message);
    } else {
      _hostService.broadcast(message);
    }
    return true;
  }

  @override
  void sendBinaryMessage(data) {}

  @override
  Future<String> uploadFile(String filePath) async => '';

  @override
  Future<void> downloadFile(String fileId, String savePath) async {}

  @override
  Future<ClientInfo> getClientInfo() async {
    return ClientInfo(
      id: '__host__',
      hostIp: _hostService.localIp ?? '',
      hostPort: _hostService.port,
      isConnected: _hostService.isRunning,
      deviceId: '__host__',
    );
  }
}

/// 服务端功能测试 Fixture
///
/// 封装了 [bin/auak_server.dart] 的完整初始化和清理流程，提供：
/// - 真实数据库和业务服务
/// - FakeLanHostService（可编程的 Host 服务）
/// - CapturingRpcServer（可直接调用已注册的 RPC handler）
/// - ClientSessionManager（客户端会话管理）
/// - 便捷的客户端模拟方法
///
/// 设计参考 bin server 的启动流程：
/// 1. 初始化 DeviceClient 和数据库
/// 2. 创建 FakeLanHostService 和适配器
/// 3. 创建 RemoteCallServer 并注册所有 Host RPC 方法
/// 4. 启动 Host 服务
/// 5. 监听消息流并转发 RPC 请求
class ServerTestFixture {
  /// 唯一标识
  final String id;

  /// 设备 ID
  final String deviceId;

  /// 临时数据库路径
  final String dbPath;

  /// 临时存储根路径
  final String storagePath;

  /// DeviceClient 实例
  final DeviceClient deviceClient;

  /// Fake Host 服务
  final FakeLanHostService hostService;

  /// CapturingRpcServer（可获取已注册的 handler）
  final CapturingRpcServer rpcServer;

  /// 客户端会话管理器
  final ClientSessionManager clientSessionManager;

  /// 日志记录器
  final Logger log;

  /// Host 接收到的消息记录
  final List<LanMessage> receivedMessages = [];

  StreamSubscription<LanMessage>? _messageSub;

  ServerTestFixture._({
    required this.id,
    required this.deviceId,
    required this.dbPath,
    required this.storagePath,
    required this.deviceClient,
    required this.hostService,
    required this.rpcServer,
    required this.clientSessionManager,
  }) : log = Logger('ServerTestFixture[$id]');

  /// 创建并初始化一个服务端测试 Fixture
  ///
  /// [name] 测试名称。
  /// [hostName] 服务器显示名称。
  /// [port] 服务端口（默认 9090）。
  ///
  /// 初始化流程（参考 bin/auak_server.dart main 函数）：
  /// 1. 创建临时存储目录
  /// 2. 初始化 DeviceClient 和数据库
  /// 3. 获取业务服务实例
  /// 4. 创建 ClientSessionManager
  /// 5. 创建 FakeLanHostService 和适配器
  /// 6. 创建 CapturingRpcServer 并注册所有 Host RPC 方法
  /// 7. 启动 Host 服务
  /// 8. 监听消息流，转发 RPC 请求
  static Future<ServerTestFixture> create(
    String name, {
    String? hostName,
    int port = 9090,
  }) async {
    _serverTestFixtureCounter++;
    final id = '${name}_${_serverTestFixtureCounter}';
    final deviceId = 'server-$id-${const Uuid().v4().substring(0, 8)}';

    // 创建临时目录
    final storagePath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}auak_server_test_$id';
    final dbPath =
        '$storagePath${Platform.pathSeparator}db';
    await Directory(dbPath).create(recursive: true);

    // 初始化 DeviceClient（参考 bin server 步骤 6）
    final deviceClient = DeviceClient.getInstance(deviceId);
    await deviceClient.initialize(DeviceClientConfig(
      storagePath: storagePath,
      host: '',
      port: port,
      deviceName: hostName ?? 'TestServer-$name',
    ));

    // 获取业务服务实例（参考 bin server 步骤 7）
    final employeeManager = deviceClient.employeeManager;
    final sessionManager = deviceClient.sessionManager;
    final skillManager = deviceClient.skillManager;
    final messageStore = deviceClient.messageStore;

    // 创建 ClientSessionManager（参考 bin server 步骤 8）
    final clientSessionManager = ClientSessionManager();

    // 创建 FakeLanHostService 和适配器（参考 bin server 步骤 9）
    final hostService = FakeLanHostService(localIp: '127.0.0.1');
    final adapter = HostLanClientServiceAdapter(hostService);

    // 创建 CapturingRpcServer 并注册所有 Host RPC 方法（参考 bin server 步骤 10）
    final rpcServer = CapturingRpcServer(
      clientService: adapter,
      localDeviceId: deviceId,
    );
    registerHostRpcMethods(
      rpcServer: rpcServer,
      employeeManager: employeeManager,
      sessionManager: sessionManager,
      skillManager: skillManager,
      messageStore: messageStore,
      clientSessionManager: clientSessionManager,
      projectManager: deviceClient.projectManager,
      globalSkillManager: deviceClient.globalSkillManager,
      deviceId: deviceId,
    );

    // 启动 Host 服务（参考 bin server 步骤 11）
    await hostService.start(port: port, storageDir: storagePath);

    final fixture = ServerTestFixture._(
      id: id,
      deviceId: deviceId,
      dbPath: dbPath,
      storagePath: storagePath,
      deviceClient: deviceClient,
      hostService: hostService,
      rpcServer: rpcServer,
      clientSessionManager: clientSessionManager,
    );

    // 监听消息流，转发 RPC 请求（参考 bin server 步骤 12）
    fixture._messageSub = hostService.messageStream.listen((msg) {
      fixture.receivedMessages.add(msg);
      if (msg.type == LanMessageType.rpcRequest && msg.content != null) {
        try {
          final contentData =
              jsonDecode(msg.content!) as Map<String, dynamic>;
          final payload = contentData['payload'] as Map<String, dynamic>?;
          if (payload != null) {
            rpcServer.handleRequest(payload);
          }
        } catch (e) {
          fixture.log.warn('Failed to parse rpcRequest payload: $e');
        }
      }
    });

    return fixture;
  }

  // ═══════════════════════════════════════════════════════════════
  // 业务服务快捷访问
  // ═══════════════════════════════════════════════════════════════

  EmployeeManager get employeeManager => deviceClient.employeeManager;

  SessionManager get sessionManager => deviceClient.sessionManager;

  SkillManager get skillManager => deviceClient.skillManager;

  MessageStoreService get messageStore => deviceClient.messageStore;

  // ═══════════════════════════════════════════════════════════════
  // RPC 便捷方法
  // ═══════════════════════════════════════════════════════════════

  /// 获取指定方法的 RPC handler
  ///
  /// 直接调用 handler，跳过消息传递层，用于测试单个 RPC 方法的逻辑。
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) getHandler(
    String method,
  ) {
    final handler = rpcServer.capturedHandlers[method];
    if (handler == null) {
      throw StateError('RPC method "$method" not registered');
    }
    return handler;
  }

  /// 直接调用指定 RPC 方法
  ///
  /// 等价于 `getHandler(method)(params)`，提供更简洁的调用方式。
  Future<Map<String, dynamic>> callRpc(
    String method,
    Map<String, dynamic> params,
  ) {
    return getHandler(method)(params);
  }

  /// 检查指定 RPC 方法是否已注册
  bool hasRpcMethod(String method) =>
      rpcServer.capturedHandlers.containsKey(method);

  /// 获取所有已注册的 RPC 方法名
  List<String> get registeredMethods =>
      rpcServer.capturedHandlers.keys.toList();

  // ═══════════════════════════════════════════════════════════════
  // 客户端模拟
  // ═══════════════════════════════════════════════════════════════

  /// 模拟一个客户端连接到 Host
  ///
  /// [clientId] 客户端连接 ID。
  /// [clientDeviceId] 客户端设备 ID。
  /// [deviceName] 客户端设备名称。
  /// [topic] 分组主题。
  void simulateClientConnect({
    required String clientId,
    required String clientDeviceId,
    String? deviceName,
    String? topic,
  }) {
    hostService.registerClient(
      clientId: clientId,
      deviceId: clientDeviceId,
      deviceName: deviceName,
      topic: topic,
    );
    clientSessionManager.registerClient(
      ClientSession(
        clientId: clientId,
        deviceId: clientDeviceId,
        deviceName: deviceName,
        topic: topic,
        connectedAt: DateTime.now(),
      ),
    );
  }

  /// 模拟客户端断开连接
  void simulateClientDisconnect(String clientId) {
    final session = clientSessionManager.unregisterClient(clientId);
    if (session != null) {
      hostService.unregisterClient(clientId);
    }
  }

  /// 模拟客户端发送消息到 Host
  void simulateClientMessage({
    required String clientId,
    required LanMessage message,
  }) {
    hostService.simulateClientMessage(clientId: clientId, message: message);
  }

  /// 获取指定客户端接收到的消息
  List<LanMessage> getClientMessages(String clientId) {
    return hostService.getClientMessages(clientId);
  }

  // ═══════════════════════════════════════════════════════════════
  // 清理
  // ═══════════════════════════════════════════════════════════════

  /// 释放所有资源并清理临时文件
  ///
  /// 参考 bin server 的 shutdown 流程：
  /// 1. 取消消息订阅
  /// 2. 停止 Host 服务
  /// 3. 释放 RPC Server
  /// 4. 关闭数据库
  /// 5. 移除 DeviceClient 实例
  /// 6. 清理临时目录
  Future<void> dispose() async {
    await _messageSub?.cancel();

    // 停止 Host 服务
    await hostService.stop();

    // 释放 RPC Server
    rpcServer.dispose();

    // 关闭数据库并移除实例
    await DatabaseManager.getInstance(deviceId).close();
    await DeviceClient.removeInstance(deviceId);

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
