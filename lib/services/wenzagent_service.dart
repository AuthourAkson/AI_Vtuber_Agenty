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

      await _client!.initialize(
        DeviceClientConfig(
          storagePath: config.storagePath,
          host: config.host,
          port: config.port,
          deviceName: config.deviceName,
          topic: config.topic,
        ),
      );

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

  Future<List<LanDeviceInfo>> getOnlineDevices() async {
    if (_client == null || !_connected) return [];
    try {
      return await _client!.getOnlineDevices();
    } catch (e) {
      return [];
    }
  }

  Future<List<MultiAgentInfo>> getSessionSummaries() async {
    if (_client == null) return [];
    try {
      final summaries = await _client!.getSessionSummaries();
      return summaries.map((s) {
        return MultiAgentInfo(
          employeeId: s.employeeId,
          name: s
              .employeeId, // Will be resolved by AgentManager using employee name map
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
        autoApprove: 1, // Auto-approve tool calls to avoid "Cancelled"
        isPinned: 0,
        deleted: 0,
        permissionConfig:
            permissionConfigJson, // Inject global permission rules
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

  /// Update an employee's system prompt (personality prompt).
  Future<void> updateEmployeeSystemPrompt({
    required String employeeId,
    String? systemPrompt,
  }) async {
    if (_client == null) return;
    try {
      final emp = await _client!.employeeManager.getEmployee(employeeId);
      if (emp != null) {
        emp.systemPrompt = systemPrompt;
        emp.updateTime = DateTime.now();
        await _client!.employeeManager.updateEmployee(emp);
      }
    } catch (e) {
      print('[WenzAgentService] updateEmployeeSystemPrompt failed: $e');
    }
  }

  /// Delete an employee.
  Future<void> deleteEmployee(String uuid) async {
    if (_client == null) return;
    try {
      await _client!.deleteEmployee(uuid);
    } catch (_) {}
  }

  /// Delete an agent session (keeps the employee, just clears chat history).
  Future<void> deleteAgentSession(String employeeId) async {
    if (_client == null) return;
    try {
      // Hard-delete messages + summary (SDK's deleteSession is soft-delete only)
      await _client!.messageStore.deleteMessages(_deviceId, employeeId);
      await _client!.deleteSession(employeeId);
    } catch (_) {}
  }

  // ─── Agent Summaries (for AgentManager) ───────────────────

  /// Get agent summaries as AgentModel-compatible list.
  Future<List<MultiAgentInfo>> getAgentSummaries() async {
    return await getSessionSummaries();
  }

  // ─── Global Skill Management ──────────────────

  /// Get all global skills.
  Future<List<GlobalSkillEntity>> getGlobalSkills() async {
    try {
      final gsm = GlobalSkillManager.getInstance(_deviceId);
      return await gsm.getAllSkills();
    } catch (e) {
      print('[WenzAgentService] getGlobalSkills failed: $e');
      return [];
    }
  }

  /// Create a global folder skill.
  ///
  /// Copies the source folder to {skillsDir}/{name} so that the WenzAgent
  /// SDK can discover and load it at agent warmup time.  The SDK's
  /// _resolveFolderSkillPath() always points to skillsDir/<name>, never
  /// to an arbitrary path, so the copy step is mandatory.
  Future<GlobalSkillEntity?> createGlobalFolderSkill({
    required String name,
    String? description,
    required String folderPath,
  }) async {
    try {
      // 1. Resolve the SDK's expected skill folder location
      final skillsDir = _client?.skillsDir;
      if (skillsDir == null || skillsDir.isEmpty) {
        print(
          '[WenzAgentService] createGlobalFolderSkill: skillsDir not set, device not initialized?',
        );
        return null;
      }
      final targetPath = p.join(skillsDir, name);

      // 2. Validate source folder exists
      final sourceDir = Directory(folderPath);
      if (!await sourceDir.exists()) {
        print(
          '[WenzAgentService] createGlobalFolderSkill: source folder not found: $folderPath',
        );
        return null;
      }

      // 3. Copy folder to skillsDir/<name> (skip if already at target)
      final normalizedSource = p.normalize(p.absolute(folderPath));
      final normalizedTarget = p.normalize(p.absolute(targetPath));
      if (normalizedSource != normalizedTarget) {
        try {
          await _copyDirectory(folderPath, targetPath);
          print(
            '[WenzAgentService] createGlobalFolderSkill: copied $folderPath -> $targetPath',
          );
        } catch (e) {
          print('[WenzAgentService] createGlobalFolderSkill: copy failed: $e');
          return null;
        }
      }

      // 4. Save to global skill library
      final gsm = GlobalSkillManager.getInstance(_deviceId);
      final entity = GlobalSkillEntity(
        uuid: 'gskill-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: description,
        skillType: 'folder',
        config: folderPath,
        enabled: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      await gsm.createSkill(entity);
      return entity;
    } catch (e) {
      print('[WenzAgentService] createGlobalFolderSkill failed: $e');
      return null;
    }
  }

  /// Recursively copy a directory.
  Future<void> _copyDirectory(String source, String target) async {
    final sourceDir = Directory(source);
    final targetDir = Directory(target);
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    await for (final entity in sourceDir.list(recursive: true)) {
      final relativePath = p.relative(entity.path, from: source);
      final destPath = p.join(target, relativePath);
      if (entity is Directory) {
        await Directory(destPath).create(recursive: true);
      } else if (entity is File) {
        await Directory(p.dirname(destPath)).create(recursive: true);
        await entity.copy(destPath);
      }
    }
  }

  /// Create a global MCP skill.
  Future<GlobalSkillEntity?> createGlobalMcpSkill({
    required String name,
    String? description,
    required McpServerConfig serverConfig,
  }) async {
    try {
      final gsm = GlobalSkillManager.getInstance(_deviceId);
      final configJson = McpServerConfig.toJsonString([serverConfig]);
      final entity = GlobalSkillEntity(
        uuid: 'gskill-mcp-${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: description,
        skillType: 'mcp',
        config: configJson,
        enabled: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      await gsm.createSkill(entity);
      return entity;
    } catch (e) {
      print('[WenzAgentService] createGlobalMcpSkill failed: $e');
      return null;
    }
  }

  /// Test MCP server connection.
  Future<void> deleteGlobalSkill(String uuid) async {
    try {
      final gsm = GlobalSkillManager.getInstance(_deviceId);
      await gsm.deleteSkill(uuid);
    } catch (e) {
      print('[WenzAgentService] deleteGlobalSkill failed: $e');
    }
  }

  /// Toggle global skill enabled.
  Future<void> setGlobalSkillEnabled(String uuid, bool enabled) async {
    try {
      final gsm = GlobalSkillManager.getInstance(_deviceId);
      await gsm.setSkillEnabled(uuid, enabled);
    } catch (e) {
      print('[WenzAgentService] setGlobalSkillEnabled failed: $e');
    }
  }

  /// Add a global skill to an employee (creates AiEmployeeSkillEntity with globalSkillId).
  Future<AiEmployeeSkillEntity?> addGlobalSkillToEmployee({
    required String employeeId,
    required GlobalSkillEntity globalSkill,
  }) async {
    try {
      final skillMgr = SkillManager.getInstance(_deviceId);
      // Check if already exists
      final existing = await skillMgr.getSkills(employeeId);
      final already = existing.any((s) => s.globalSkillId == globalSkill.uuid);
      if (already) return null;

      final entity = AiEmployeeSkillEntity(
        uuid: 'eskill-${DateTime.now().millisecondsSinceEpoch}',
        employeeId: employeeId,
        name: globalSkill.name,
        description: globalSkill.description,
        skillType: globalSkill.skillType,
        config: globalSkill.config,
        globalSkillId: globalSkill.uuid,
        enabled: 1,
        createTime: DateTime.now(),
        updateTime: DateTime.now(),
      );
      await skillMgr.createSkill(entity);

      // Push to agent runtime
      final proxy = await _client!.getOrCreateAgentProxy(
        employeeId: employeeId,
      );
      await proxy.initialize();
      final skills = await skillMgr.getSkills(employeeId);
      await proxy.setSkills(skills.map((e) => e.toMap()).toList());

      return entity;
    } catch (e) {
      print('[WenzAgentService] addGlobalSkillToEmployee failed: $e');
      return null;
    }
  }

  /// Remove a global skill from an employee.
  Future<void> removeGlobalSkillFromEmployee(
    String employeeId,
    String globalSkillId,
  ) async {
    try {
      final skillMgr = SkillManager.getInstance(_deviceId);
      final skills = await skillMgr.getSkills(employeeId);
      for (final s in skills) {
        if (s.globalSkillId == globalSkillId) {
          await skillMgr.deleteSkill(s.uuid);
        }
      }
      // Push to agent runtime
      final proxy = await _client!.getOrCreateAgentProxy(
        employeeId: employeeId,
      );
      await proxy.initialize();
      final updated = await skillMgr.getSkills(employeeId);
      await proxy.setSkills(updated.map((e) => e.toMap()).toList());
    } catch (e) {
      print('[WenzAgentService] removeGlobalSkillFromEmployee failed: $e');
    }
  }

  /// Get skills for an employee.
  Future<List<AiEmployeeSkillEntity>> getEmployeeSkills(
    String employeeId,
  ) async {
    try {
      final skillMgr = SkillManager.getInstance(_deviceId);
      return await skillMgr.getSkills(employeeId);
    } catch (e) {
      return [];
    }
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
      'toolCalls': msg.toolCalls
          ?.map((t) => {'id': t.id, 'name': t.name, 'arguments': t.arguments})
          .toList(),
    };
  }

  void _onNotificationEvent(AgentNotificationEvent event) {
    switch (event) {
      case AgentMessageArrivedEvent(
        :final message,
        :final employeeId,
        :final isRemote,
      ):
        _messageController.add({
          'type': 'message',
          'employeeId': employeeId,
          'message': _msgToMap(message), // Full message data for real-time UI
          'isRemote': isRemote,
        });
        break;

      case AgentStatusNotifyEvent(:final employeeId, :final status):
        _statusController.add({
          'type': 'status',
          'employeeId': employeeId,
          'status': status,
        });
        break;

      case AgentUnreadCountChangedEvent(:final employeeId, :final unreadCount):
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
