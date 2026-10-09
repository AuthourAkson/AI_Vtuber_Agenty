/// 测试用 LanHostService 假实现
///
/// 模拟 LAN 服务端行为，支持消息广播、定向发送、客户端管理等，
/// 供功能测试在不需要真实 WebSocket Server 的情况下验证服务端逻辑。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:auakagent/src/entity/lan_client.dart';
import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/lan/entity/host_info.dart';
import 'package:auakagent/src/lan/lan_client_service.dart';
import 'package:auakagent/src/lan/lan_host_service.dart';

/// 客户端连接记录
///
/// 记录每个连接到 FakeLanHostService 的客户端信息及其接收到的消息。
class FakeConnectedClient {
  final String clientId;
  final String deviceId;
  final String? deviceName;
  final String? topic;
  final DateTime connectedAt;

  /// 该客户端接收到的所有消息
  final List<LanMessage> receivedMessages = [];

  /// 该客户端接收到的所有二进制数据
  final List<Uint8List> receivedBinaryData = [];

  FakeConnectedClient({
    required this.clientId,
    required this.deviceId,
    this.deviceName,
    this.topic,
    DateTime? connectedAt,
  }) : connectedAt = connectedAt ?? DateTime.now();
}

/// 可控的 LanHostService 假实现
///
/// 功能：
/// - 管理虚拟客户端连接（registerClient / unregisterClient）
/// - 记录所有广播和定向消息
/// - 可注入从客户端接收到的消息（simulateClientMessage）
/// - 支持文件存储模拟
///
/// 使用示例：
/// ```dart
/// final fakeHost = FakeLanHostService();
/// await fakeHost.start(port: 9090);
///
/// // 注册一个虚拟客户端
/// fakeHost.registerClient(clientId: 'c1', deviceId: 'device-1');
///
/// // 模拟客户端发送消息
/// fakeHost.simulateClientMessage(
///   clientId: 'c1',
///   message: LanMessage(type: LanMessageType.text, content: 'hello'),
/// );
///
/// // 向客户端发送消息
/// fakeHost.sendToClient('c1', LanMessage.system('welcome'));
/// ```
class FakeLanHostService implements LanHostService {
  bool _isRunning = false;
  int _port = 9090;
  String? _localIp;
  String? _storageDir;

  /// 已连接的客户端 (clientId -> FakeConnectedClient)
  final Map<String, FakeConnectedClient> _clients = {};

  /// deviceId -> clientId 映射（支持按 deviceId 发送）
  final Map<String, String> _deviceToClientId = {};

  /// 消息流控制器
  final StreamController<LanMessage> _messageController =
      StreamController<LanMessage>.broadcast();

  /// 记录所有广播的消息
  final List<LanMessage> broadcastedMessages = [];

  /// 记录所有保存的文件 (fileId -> data)
  final Map<String, List<int>> _savedFiles = {};

  int _fileCounter = 0;

  /// 广播拦截器
  ///
  /// 返回 false 可阻止广播。
  bool Function(LanMessage message)? broadcastInterceptor;

  /// 定向发送拦截器
  ///
  /// 返回 false 可阻止发送。
  bool Function(String clientId, LanMessage message)? sendInterceptor;

  FakeLanHostService({String? localIp}) : _localIp = localIp;

  // ═══════════════════════════════════════════════════════════════
  // LanHostService 接口实现
  // ═══════════════════════════════════════════════════════════════

  @override
  bool get isRunning => _isRunning;

  @override
  String? get localIp => _localIp;

  @override
  int get port => _port;

  @override
  List<LanClient> get clients {
    return _clients.entries.map<LanClient>((e) {
      return LanClient(
        id: e.key,
        deviceId: e.value.deviceId,
        name: e.value.deviceName,
        topic: e.value.topic,
        connectedAt: e.value.connectedAt,
      );
    }).toList();
  }

  @override
  Stream<LanMessage> get messageStream => _messageController.stream;

  @override
  Future<void> start({int port = 9090, String? storageDir}) async {
    _port = port;
    _storageDir = storageDir;
    _isRunning = true;
    _localIp ??= '127.0.0.1';
  }

  @override
  Future<void> stop() async {
    _isRunning = false;
    _clients.clear();
    _deviceToClientId.clear();
  }

  @override
  void broadcast(LanMessage message) {
    if (broadcastInterceptor != null && !broadcastInterceptor!(message)) {
      return;
    }
    broadcastedMessages.add(message);
    for (final client in _clients.values) {
      client.receivedMessages.add(message);
    }
  }

  @override
  void sendToClient(String clientId, LanMessage message) {
    if (sendInterceptor != null && !sendInterceptor!(clientId, message)) {
      return;
    }
    final client = _clients[clientId];
    if (client != null) {
      client.receivedMessages.add(message);
    }
  }

  @override
  void sendToDeviceId(String deviceId, LanMessage message) {
    final clientId = _deviceToClientId[deviceId];
    if (clientId != null) {
      sendToClient(clientId, message);
    }
  }

  @override
  void disconnectClient(String clientId) {
    final client = _clients.remove(clientId);
    if (client != null) {
      _deviceToClientId.remove(client.deviceId);
    }
  }

  @override
  Future<String> saveFile(List<int> data, String fileName) async {
    _fileCounter++;
    final fileId = 'fake-file-$_fileCounter';
    _savedFiles[fileId] = data;
    return fileId;
  }

  @override
  Future<List<int>?> getFile(String fileId) async {
    return _savedFiles[fileId];
  }

  @override
  Future<HostInfo> getHostInfo() async {
    return HostInfo(
      isRunning: _isRunning,
      ip: _localIp ?? '127.0.0.1',
      port: _port,
      clients: _clients.entries.map((e) => {
        'clientId': e.key,
        'deviceId': e.value.deviceId,
        'deviceName': e.value.deviceName,
      }).toList(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试辅助方法
  // ═══════════════════════════════════════════════════════════════

  /// 注册一个虚拟客户端
  void registerClient({
    required String clientId,
    required String deviceId,
    String? deviceName,
    String? topic,
  }) {
    _clients[clientId] = FakeConnectedClient(
      clientId: clientId,
      deviceId: deviceId,
      deviceName: deviceName,
      topic: topic,
    );
    _deviceToClientId[deviceId] = clientId;
  }

  /// 注销一个虚拟客户端
  void unregisterClient(String clientId) {
    final client = _clients.remove(clientId);
    if (client != null) {
      _deviceToClientId.remove(client.deviceId);
    }
  }

  /// 模拟客户端发送消息到 Host
  ///
  /// 将消息注入到 messageStream，模拟真实客户端通过 WebSocket 发送消息。
  void simulateClientMessage({
    required String clientId,
    required LanMessage message,
  }) {
    // 自动填充 fromId（如果未设置）
    final enrichedMessage = LanMessage(
      id: message.id,
      type: message.type,
      fromId: message.fromId ?? clientId,
      fromName: message.fromName ?? _clients[clientId]?.deviceName,
      content: message.content,
      fileName: message.fileName,
      fileSize: message.fileSize,
      fileId: message.fileId,
      fileHash: message.fileHash,
      topic: message.topic ?? _clients[clientId]?.topic,
      toDeviceId: message.toDeviceId,
      timestamp: message.timestamp,
    );
    _messageController.add(enrichedMessage);
  }

  /// 获取指定客户端接收到的所有消息
  List<LanMessage> getClientMessages(String clientId) {
    return _clients[clientId]?.receivedMessages.toList() ?? [];
  }

  /// 获取指定客户端接收到的特定类型消息
  List<LanMessage> getClientMessagesByType(
    String clientId,
    LanMessageType type,
  ) {
    return _clients[clientId]
            ?.receivedMessages
            .where((m) => m.type == type)
            .toList() ??
        [];
  }

  /// 检查指定设备是否已连接
  bool hasDevice(String deviceId) => _deviceToClientId.containsKey(deviceId);

  /// 获取在线设备数量
  int get onlineDeviceCount => _deviceToClientId.length;

  /// 清空所有记录的消息
  void clearMessages() {
    broadcastedMessages.clear();
    for (final client in _clients.values) {
      client.receivedMessages.clear();
      client.receivedBinaryData.clear();
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    await _messageController.close();
  }
}
