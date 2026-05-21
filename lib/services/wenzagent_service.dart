import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:wenzagent/wenzagent.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Configuration for initializing the WenzAgent service.
class WenzAgentConfig {
  final String storagePath;
  final String host;
  final int port;
  final String deviceName;
  final String? topic;

  const WenzAgentConfig({
    required this.storagePath,
    required this.host,
    this.port = 9090,
    this.deviceName = 'AI VTuber',
    this.topic,
  });
}

/// Lightweight wrapper for agent info displayed in UI lists.
class MultiAgentInfo {
  final String employeeId;
  final String name;
  final String? deviceId;
  final String? latestMessage;
  final String status;
  final int unreadCount;
  final bool hasPendingPermission;
  final bool hasPendingConfirm;

  const MultiAgentInfo({
    required this.employeeId,
    required this.name,
    this.deviceId,
    this.latestMessage,
    this.status = 'idle',
    this.unreadCount = 0,
    this.hasPendingPermission = false,
    this.hasPendingConfirm = false,
  });

  String get lastMsgPreview =>
      latestMessage != null && latestMessage!.length > 40
          ? '${latestMessage!.substring(0, 40)}...'
          : (latestMessage ?? '');
}

/// Lightweight wrapper for a LAN device node.
class DeviceInfo {
  final String deviceId;
  final String deviceName;

  const DeviceInfo({
    required this.deviceId,
    required this.deviceName,
  });
}

/// Bridge service between AiVtuber_Agent and the wenzagent multi-agent SDK.
class WenzAgentService {
  DeviceClient? _client;
  CachedAgentProxy? _activeProxy;
  AgentNotificationSubscription? _notificationSub;
  StreamSubscription<DeviceConnectionState>? _connectionSub;

  bool _initialized = false;
  bool _connected = false;
  String _deviceId = '';
  String _activeEmployeeId = '';

  // UI update streams
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;
  Stream<Map<String, dynamic>> get onStatusChange => _statusController.stream;
  Stream<bool> get onConnectionChange => _connectionController.stream;

  bool get isConnected => _connected;
  bool get isInitialized => _initialized;
  String get deviceId => _deviceId;
  String get activeEmployeeId => _activeEmployeeId;

  // ─── Lifecycle ───────────────────────────────────────────

  Future<bool> initialize(WenzAgentConfig config) async {
    if (_initialized) return true;

    try {
      // Use persistent device ID (stored in SharedPreferences)
      // so data survives across app restarts.
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('wenzagent_device_id') ?? '';
      if (_deviceId.isEmpty) {
        _deviceId = 'ai-vtuber-${DateTime.now().millisecondsSinceEpoch}';
        await prefs.setString('wenzagent_device_id', _deviceId);
      }

      _client = DeviceClient.getInstance(_deviceId);

      await _client!.initialize(DeviceClientConfig(
        storagePath: config.storagePath,
        host: config.host,
        port: config.port,
        deviceName: config.deviceName,
        topic: config.topic,
      ));

      _notificationSub = _client!.notificationHub.subscribe(
        _onNotificationEvent,
      );

      _connectionSub = _client!.onConnectionStateChanged.listen((state) {
        final wasConnected = _connected;
        _connected = state == DeviceConnectionState.connected;
        if (wasConnected != _connected) {
          _connectionController.add(_connected);
        }
      });

      _initialized = true;
      return true;
    } catch (e) {
      print('[WenzAgentService] Initialize failed: $e');
      return false;
    }
  }

  Future<bool> connect() async {
    if (!_initialized || _client == null) return false;
    try {
      await _client!.connect();
      _client!.restorePendingRequests();
      await _client!.restoreUnreadStatus();
      _connected = _client!.isConnected;
      _connectionController.add(_connected);
      return _connected;
    } catch (e) {
      print('[WenzAgentService] Connect failed: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_client == null) return;
    try {
      await _client!.disconnect();
    } catch (_) {}
    _connected = false;
    _connectionController.add(false);
  }

  Future<void> dispose() async {
    _connectionSub?.cancel();
    _notificationSub?.cancel();
    try {
      await _client?.dispose();
    } catch (_) {}
    _client = null;
    _activeProxy = null;
    _initialized = false;
    _connected = false;
    await _messageController.close();
    await _statusController.close();
    await _connectionController.close();
  }

  // ─── Agent Proxy ─────────────────────────────────────────

  Future<CachedAgentProxy?> openAgent(String employeeId) async {
    if (_client == null) return null;
    try {
      _activeEmployeeId = employeeId;

      final proxy = await _client!.getOrCreateAgentProxy(
        employeeId: employeeId,
      );
      await proxy.initialize();
      await proxy.syncFromRemote();

      await _client!.setCurrentOpenSession(employeeId: employeeId);

      // Mark all messages as read via DeviceClient API
      try {
        await _client!.markAllMessagesAsRead(employeeId: employeeId);
      } catch (_) {}

      _activeProxy = proxy;
      return proxy;
    } catch (e) {
      print('[WenzAgentService] openAgent failed: $e');
      return null;
    }
  }

  Future<String?> sendMessage(String text) async {
    if (_activeProxy == null) return null;
    try {
      final messageId = await _activeProxy!.sendMessage(
        MessageInput(role: 'user', type: 'text', content: text),
      );
      return messageId;
    } catch (e) {
      print('[WenzAgentService] sendMessage failed: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getActiveMessages() async {
    if (_activeProxy == null) return [];
    try {
      final messages = await _activeProxy!.getMessages();
      return messages.map(_msgToMap).toList();
    } catch (e) {
      print('[WenzAgentService] getMessages failed: $e');
      return [];
    }
  }

  String get activeAgentStatus {
    if (_activeProxy == null) return 'idle';
    return _activeProxy!.status.name;
  }

  Future<void> interrupt() async {
    try {
      await _activeProxy?.interrupt();
    } catch (_) {}
  }

  Future<void> clearSession() async {
    try {
      await _activeProxy?.clearCurrentSession();
    } catch (_) {}
  }

  // ─── Device / Employee Queries ───────────────────────────

  Future<List<DeviceInfo>> getOnlineDevices() async {
    if (_client == null || !_connected) return [];
    try {
      final devices = await _client!.getOnlineDevices();
      return devices
          .map((d) => DeviceInfo(
                deviceId: d.id,
                deviceName: d.name ?? 'Unknown',
              ))
          .toList();
    } catch (e) {
      return [];
    }
  }

  List<MultiAgentInfo> getSessionSummaries() {
    if (_client == null) return [];
    try {
      final summaries = _client!.getSessionSummaries();
      return summaries.map((s) {
        return MultiAgentInfo(
          employeeId: s.employeeId,
          name: s.employeeId, // Will be resolved by AgentManager using employee name map
          deviceId: s.deviceId,
          latestMessage: s.lastMsgContent,
          status: 'idle',
          unreadCount: s.unreadCount,
          hasPendingPermission: s.hasPendingPermission,
          hasPendingConfirm: s.hasPendingConfirm,
        );
      }).toList();
    } catch (e) {
      return [];
    }
  }

  void markAllRead(String employeeId) {
    try {
      _client?.markAllMessagesAsRead(employeeId: employeeId);
    } catch (_) {}
  }

  // ─── Employee CRUD ────────────────────────────────────────

  /// Create a new AI employee on this device.
  Future<AiEmployeeEntity?> createEmployee({
    required String name,
    String description = '',
    String? deviceId,
    String provider = 'openai',
    String model = 'gpt-4o',
    String? permissionConfigJson,
  }) async {
    if (_client == null) return null;
    try {
      // Use a UUID-like ID for the employee
      final uuid = 'emp-${DateTime.now().millisecondsSinceEpoch}';
      final entity = AiEmployeeEntity(
        uuid: uuid,
        name: name,
        role: 'agent',
        status: 'offline',
        description: description.isNotEmpty ? description : null,
        provider: provider,
        model: model,
        currentDeviceId: deviceId ?? _deviceId,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
        sortOrder: 0,
        enableTools: 1,
        enableMcp: 0,
        autoApprove: 1,           // Auto-approve tool calls to avoid "Cancelled"
        isPinned: 0,
        deleted: 0,
        permissionConfig: permissionConfigJson,  // Inject global permission rules
      );
      await _client!.employeeManager.createEmployee(entity);
      return entity;
    } catch (e) {
      print('[WenzAgentService] createEmployee failed: $e');
      return null;
    }
  }

  /// Get all employees across devices.
  Future<List<AiEmployeeEntity>> getAllEmployees() async {
    if (_client == null) return [];
    try {
      return await _client!.employeeManager.getEmployees(allDevices: true);
    } catch (e) {
      return [];
    }
  }

  /// Update an employee's provider/model/apiKey/baseUrl.
  /// Must be called BEFORE creating the agent proxy — the local agent
  /// reads these fields from the Employee entity during initialization.
  Future<void> updateEmployeeProvider({
    required String employeeId,
    required String provider,
    required String model,
    String? apiKey,
    String? baseUrl,
  }) async {
    if (_client == null) return;
    try {
      final emp = await _client!.employeeManager.getEmployee(employeeId);
      if (emp != null) {
        emp.provider = provider;
        emp.model = model;
        emp.apiKey = apiKey;
        emp.apiBaseUrl = baseUrl;
        emp.updateTime = DateTime.now();
        await _client!.employeeManager.updateEmployee(emp);
      }
    } catch (e) {
      print('[WenzAgentService] updateEmployeeProvider failed: $e');
    }
  }

  /// Delete an employee.
  Future<void> deleteEmployee(String uuid) async {
    if (_client == null) return;
    try {
      await _client!.deleteEmployee(uuid);
    } catch (_) {}
  }

  // ─── Agent Summaries (for AgentManager) ───────────────────

  /// Get agent summaries as AgentModel-compatible list.
  List<MultiAgentInfo> getAgentSummaries() {
    return getSessionSummaries();
  }

  // ─── Internal ─────────────────────────────────────────────

  Map<String, dynamic> _msgToMap(AgentMessage msg) {
    return {
      'id': msg.id,
      'role': msg.role,
      'type': msg.type,
      'content': msg.content ?? '',
      'status': msg.status,
      'createdAt': msg.createdAt.toIso8601String(),
      'toolName': msg.toolName,
      'toolResult': msg.toolResult,
      'toolCalls': msg.toolCalls?.map((t) => {
        'id': t.id,
        'name': t.name,
        'arguments': t.arguments,
      }).toList(),
    };
  }

  void _onNotificationEvent(AgentNotificationEvent event) {
    switch (event) {
      case AgentMessageArrivedEvent(
          :final message,
          :final employeeId,
          :final isRemote):
        _messageController.add({
          'type': 'message',
          'employeeId': employeeId,
          'content': message.content ?? '',
          'role': message.role,
          'msgType': message.type,
          'isRemote': isRemote,
          'messageId': message.id,
        });
        break;

      case AgentStatusNotifyEvent(:final employeeId, :final status):
        _statusController.add({
          'type': 'status',
          'employeeId': employeeId,
          'status': status,
        });
        break;

      case AgentUnreadCountChangedEvent(
          :final employeeId,
          :final unreadCount):
        _messageController.add({
          'type': 'unread',
          'employeeId': employeeId,
          'count': unreadCount,
        });
        break;

      default:
        break;
    }
  }
}
