/// 测试用 LanClientService 假实现
///
/// 提供消息记录、可控连接状态、二进制帧模拟等能力，
/// 供功能测试在不需要真实 WebSocket 的情况下验证业务逻辑。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:auakagent/src/entity/lan_message.dart';
import 'package:auakagent/src/lan/entity/client_info.dart';
import 'package:auakagent/src/lan/lan_client_service.dart';

/// 可控的 LanClientService 假实现
///
/// 功能：
/// - 记录所有发送的消息（sentMessages）
/// - 可编程的连接状态（isConnected / isConnecting）
/// - 可注入接收消息流（injectMessage）
/// - 支持消息拦截和自定义响应
/// - 支持二进制帧模拟
///
/// 使用示例：
/// ```dart
/// final fake = FakeLanClientService(deviceId: 'test-device');
///
/// // 注入一条接收消息
/// fake.injectMessage(LanMessage(type: LanMessageType.pong, fromId: 'host'));
///
/// // 验证发送的消息
/// expect(fake.sentMessages.length, 1);
/// ```
class FakeLanClientService implements LanClientService {
  final String _deviceId;

  /// 记录所有通过 sendLanMessage 发送的消息
  final List<LanMessage> sentMessages = [];

  /// 记录所有通过 sendMessage 发送的文本消息
  final List<String> sentTextMessages = [];

  /// 记录所有通过 sendBinaryMessage 发送二进制数据
  final List<Uint8List> sentBinaryMessages = [];

  /// 记录所有上传的文件路径
  final List<String> uploadedFiles = [];

  /// 记录所有下载请求 (fileId, savePath)
  final List<({String fileId, String savePath})> downloadRequests = [];

  // ── 可控状态 ──

  bool _isConnected = false;
  bool _isConnecting = false;
  String? _hostIp;
  int _hostPort = 9090;
  String? _topic;
  double _uploadProgress = 0.0;
  double _downloadProgress = 0.0;

  // ── 消息流控制 ──

  final StreamController<LanMessage> _messageController =
      StreamController<LanMessage>.broadcast();

  final StreamController<BinaryChunkEvent> _binaryChunkController =
      StreamController<BinaryChunkEvent>.broadcast();

  /// 消息发送拦截器
  ///
  /// 返回 true 表示发送成功，false 表示发送失败。
  /// 可用于模拟网络错误、消息过滤等场景。
  bool Function(LanMessage message)? sendInterceptor;

  /// 文本消息发送拦截器
  void Function(String content)? textMessageInterceptor;

  /// 连接回调
  Future<void> Function(String hostIp, {int port})? onConnect;

  /// 断开连接回调
  Future<void> Function()? onDisconnect;

  /// 重连回调
  Future<void> Function()? onReconnect;

  FakeLanClientService({
    String deviceId = 'fake-client',
    String? topic,
  })  : _deviceId = deviceId,
        _topic = topic;

  // ═══════════════════════════════════════════════════════════════
  // LanClientService 接口实现
  // ═══════════════════════════════════════════════════════════════

  @override
  bool get isConnected => _isConnected;

  @override
  bool get isConnecting => _isConnecting;

  @override
  String get deviceId => _deviceId;

  @override
  String? get topic => _topic;

  @override
  String? get hostIp => _hostIp;

  @override
  int get hostPort => _hostPort;

  @override
  double get uploadProgress => _uploadProgress;

  @override
  double get downloadProgress => _downloadProgress;

  @override
  Stream<LanMessage> get messageStream => _messageController.stream;

  @override
  Stream<BinaryChunkEvent> get binaryChunkStream =>
      _binaryChunkController.stream;

  @override
  Future<void> connect(String hostIp, {int port = 9090}) async {
    _hostIp = hostIp;
    _hostPort = port;
    _isConnecting = true;
    await onConnect?.call(hostIp, port: port);
    _isConnecting = false;
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    await onDisconnect?.call();
    _isConnected = false;
  }

  @override
  Future<void> reconnect() async {
    _isConnecting = true;
    await onReconnect?.call();
    _isConnecting = false;
    _isConnected = true;
  }

  @override
  void sendMessage(String content) {
    sentTextMessages.add(content);
    textMessageInterceptor?.call(content);
  }

  @override
  Future<bool> sendLanMessage(LanMessage message) async {
    if (sendInterceptor != null) {
      return sendInterceptor!(message);
    }
    sentMessages.add(message);
    return true;
  }

  @override
  void sendBinaryMessage(Uint8List data) {
    sentBinaryMessages.add(data);
  }

  @override
  Future<String> uploadFile(String filePath) async {
    uploadedFiles.add(filePath);
    return 'fake-file-${uploadedFiles.length}';
  }

  @override
  Future<void> downloadFile(String fileId, String savePath) async {
    downloadRequests.add((fileId: fileId, savePath: savePath));
  }

  @override
  Future<ClientInfo> getClientInfo() async {
    return ClientInfo(
      id: _deviceId,
      hostIp: _hostIp ?? '',
      hostPort: _hostPort,
      isConnected: _isConnected,
      deviceId: _deviceId,
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 测试辅助方法
  // ═══════════════════════════════════════════════════════════════

  /// 注入一条接收消息到 messageStream
  ///
  /// 模拟从 Host 接收到消息。
  void injectMessage(LanMessage message) {
    _messageController.add(message);
  }

  /// 注入一个二进制 chunk 事件
  void injectBinaryChunk(BinaryChunkEvent event) {
    _binaryChunkController.add(event);
  }

  /// 模拟连接成功
  void simulateConnected({String? hostIp, int? port}) {
    if (hostIp != null) _hostIp = hostIp;
    if (port != null) _hostPort = port;
    _isConnected = true;
    _isConnecting = false;
  }

  /// 模拟断开连接
  void simulateDisconnected() {
    _isConnected = false;
    _isConnecting = false;
  }

  /// 模拟正在连接中
  void simulateConnecting() {
    _isConnecting = true;
    _isConnected = false;
  }

  /// 模拟上传进度
  void simulateUploadProgress(double progress) {
    _uploadProgress = progress;
  }

  /// 模拟下载进度
  void simulateDownloadProgress(double progress) {
    _downloadProgress = progress;
  }

  /// 按类型查找已发送的消息
  List<LanMessage> findSentMessages(LanMessageType type) {
    return sentMessages.where((m) => m.type == type).toList();
  }

  /// 查找发送到指定设备的消息
  List<LanMessage> findSentToDevice(String toDeviceId) {
    return sentMessages
        .where((m) => m.toDeviceId == toDeviceId)
        .toList();
  }

  /// 查找包含指定内容的消息
  List<LanMessage> findSentContaining(String content) {
    return sentMessages
        .where((m) => m.content?.contains(content) ?? false)
        .toList();
  }

  /// 清空所有记录的消息
  void clearSentMessages() {
    sentMessages.clear();
    sentTextMessages.clear();
    sentBinaryMessages.clear();
    uploadedFiles.clear();
    downloadRequests.clear();
  }

  /// 释放资源
  Future<void> dispose() async {
    await _messageController.close();
    await _binaryChunkController.close();
  }
}
