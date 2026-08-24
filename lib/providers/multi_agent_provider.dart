import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:wenzagent/wenzagent.dart';
import '../services/log_service.dart';
import '../services/storage_service.dart';
import '../services/tts_service.dart';
import '../services/wenzagent_service.dart';

/// Agent model for the contacts/employee list.
class AgentModel {
  final String uuid;
  final String name;
  final String? description;
  final String? deviceId;
  final String? provider;
  final String? model;
  final String status;

  const AgentModel({
    required this.uuid,
    required this.name,
    this.description,
    this.deviceId,
    this.provider,
    this.model,
    this.status = 'offline',
  });
}

/// A named AI provider configuration profile.
class ProviderProfile {
  String name;
  String baseUrl;
  String apiKey;
  String model;

  ProviderProfile({
    required this.name,
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory ProviderProfile.fromJson(Map<String, dynamic> json) =>
      ProviderProfile(
        name: json['name'] ?? '',
        baseUrl: json['baseUrl'] ?? 'https://api.openai.com/v1',
        apiKey: json['apiKey'] ?? '',
        model: json['model'] ?? 'gpt-4o',
      );
}

/// Which kind of avatar model is bound to an employee.
enum AgentAvatarType { none, live2d, vrm }

/// Visual + voice + personality binding for a WenzAgent employee.
/// Persisted locally, so each AI employee can put on a different face.
class AgentPersona {
  AgentAvatarType avatarType;
  String avatarPath; // Live2D: model3.json path; VRM: .vrm path
  String voice; // edge-tts ShortName, e.g. zh-CN-XiaoxiaoNeural
  String systemPrompt; // extra personality prompt injected into this employee
  bool voiceEnabled;

  AgentPersona({
    this.avatarType = AgentAvatarType.none,
    this.avatarPath = '',
    this.voice = 'zh-CN-XiaoxiaoNeural',
    this.systemPrompt = '',
    this.voiceEnabled = true,
  });

  Map<String, dynamic> toJson() => {
    'avatarType': avatarType.name,
    'avatarPath': avatarPath,
    'voice': voice,
    'systemPrompt': systemPrompt,
    'voiceEnabled': voiceEnabled,
  };

  factory AgentPersona.fromJson(Map<String, dynamic> json) => AgentPersona(
    avatarType: AgentAvatarType.values.firstWhere(
      (t) => t.name == json['avatarType'],
      orElse: () => AgentAvatarType.none,
    ),
    avatarPath: json['avatarPath'] as String? ?? '',
    voice: json['voice'] as String? ?? 'zh-CN-XiaoxiaoNeural',
    systemPrompt: json['systemPrompt'] as String? ?? '',
    voiceEnabled: json['voiceEnabled'] as bool? ?? true,
  );
}

/// Central state manager for Multi-Agent page (replaces old MultiAgentProvider).
///
/// Manages LAN connection, agent/employee lists, active chat, and employee creation.
class AgentManager extends ChangeNotifier {
  final WenzAgentService wenzagent = WenzAgentService();

  AgentManager() {
    // ⚠️ 服务商列表必须与应用启动同步加载，而不是等 MultiAgent 页面初始化：
    // MarkdownText 等其它页面直接读 providerProfiles，若只在 initIfEnabled()
    // 里 _loadProfiles()，用户没进过 MultiAgent 页时手动添加的服务商就不显示。
    _loadProfiles();
  }

  // ─── LAN Connection State ───────────────────

  bool _initialized = false;
  bool _connecting = false;
  bool _connected = false;
  String _statusMessage = 'Disconnected';
  String _host = '127.0.0.1';
  int _port = 9090;
  String _deviceName = 'AI VTuber';
  String _topic = '';

  // ─── Agent Persona (Direction 1: face + voice binding) ──

  final Map<String, AgentPersona> _personas = {};
  TTSService? _tts;
  String? _lastSpokenAssistantMsgId;
  String _lastAgentStatus = 'idle';
  bool _agentTaskRunning = false;

  /// Whether a viewer-initiated Agent task is currently running.
  bool get agentTaskRunning => _agentTaskRunning;

  // ─── Multi-Agent Data ───────────────────────

  List<ProviderProfile> _providerProfiles = [
    ProviderProfile(
      name: 'Default OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o',
    ),
  ];
  List<AgentModel> _employees = [];
  List<AgentModel> _agentSummaries = [];
  List<LanDeviceInfo> _onlineDevices = [];

  /// Skill entities for the skills panel (global skills).
  List<GlobalSkillEntity> _skills = [];

  /// Employee's currently loaded skills (for the active agent).
  List<AiEmployeeSkillEntity> _employeeSkills = [];

  /// Employee IDs of sessions the user has deleted (SDK doesn't clear summaries
  /// on session delete, so we filter them out ourselves). Persisted to profiles JSON.
  final Set<String> _hiddenSessionIds = {};

  // ─── Getters ────────────────────────────────

  String? _activeEmployeeId;
  String? _activeEmployeeName;
  List<Map<String, dynamic>> _activeMessages = [];

  // ─── Subscriptions ──────────────────────────

  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _connSub;

  // ─── Getters ────────────────────────────────

  bool get initialized => _initialized;
  bool get connecting => _connecting;
  bool get connected => _connected;
  String get statusMessage => _statusMessage;
  String get host => _host;
  int get port => _port;
  String get deviceName => _deviceName;
  String get topic => _topic;

  List<AgentModel> get employees => _employees;
  List<AgentModel> get agentSummaries => _agentSummaries;
  List<LanDeviceInfo> get onlineDevices => _onlineDevices;
  List<GlobalSkillEntity> get skills => _skills;
  List<AiEmployeeSkillEntity> get employeeSkills => _employeeSkills;
  List<ProviderProfile> get providerProfiles => _providerProfiles;

  AgentPersona? getPersona(String employeeId) => _personas[employeeId];

  void setPersona(String employeeId, AgentPersona persona) {
    _personas[employeeId] = persona;
    _saveProfiles();
    notifyListeners();
  }

  void removePersona(String employeeId) {
    _personas.remove(employeeId);
    _saveProfiles();
    notifyListeners();
  }

  String? get activeEmployeeId => _activeEmployeeId;
  String? get activeEmployeeName => _activeEmployeeName;
  AgentPersona? get activePersona {
    final id = _activeEmployeeId;
    if (id == null) return null;
    return _personas[id];
  }

  List<Map<String, dynamic>> get activeMessages => _activeMessages;
  String get activeAgentStatus => wenzagent.activeAgentStatus;

  bool get hasUnreadMessages =>
      _agentSummaries.any((a) => a.status == 'unread');

  // ─── Permission Config ──────────────────────

  /// Built-in tool permission presets matching WenzAgent tool names.
  static const List<Map<String, String>> builtinPermDefs = [
    {
      'id': 'file_read',
      'label': 'permFileRead',
      'desc': 'permFileReadDesc',
      'default': 'true',
    },
    {
      'id': 'file_write',
      'label': 'permFileWrite',
      'desc': 'permFileWriteDesc',
      'default': 'false',
    },
    {
      'id': 'file_delete',
      'label': 'permFileDelete',
      'desc': 'permFileDeleteDesc',
      'default': 'false',
    },
    {
      'id': 'file_patch',
      'label': 'permFilePatch',
      'desc': 'permFilePatchDesc',
      'default': 'false',
    },
    {
      'id': 'directory_create',
      'label': 'permDirCreate',
      'desc': 'permDirCreateDesc',
      'default': 'false',
    },
    {
      'id': 'command_execute',
      'label': 'permCmdExec',
      'desc': 'permCmdExecDesc',
      'default': 'false',
    },
    {
      'id': 'bg_command',
      'label': 'permBgCmd',
      'desc': 'permBgCmdDesc',
      'default': 'false',
    },
    {
      'id': 'git_operations',
      'label': 'permGitOps',
      'desc': 'permGitOpsDesc',
      'default': 'false',
    },
    {
      'id': 'doc_read',
      'label': 'permDocRead',
      'desc': 'permDocReadDesc',
      'default': 'true',
    },
    {
      'id': 'doc_write',
      'label': 'permDocWrite',
      'desc': 'permDocWriteDesc',
      'default': 'false',
    },
    {
      'id': 'todo_read',
      'label': 'permTaskRead',
      'desc': 'permTaskReadDesc',
      'default': 'true',
    },
    {
      'id': 'todo_write',
      'label': 'permTaskWrite',
      'desc': 'permTaskWriteDesc',
      'default': 'false',
    },
  ];

  final Map<String, bool> _permEnabled = {};

  /// Whether a tool permission is enabled.
  bool isPermEnabled(String toolId) => _permEnabled[toolId] ?? false;

  /// Toggle a tool permission.
  void togglePerm(String toolId) {
    _permEnabled[toolId] = !(_permEnabled[toolId] ?? false);
    _saveProfiles();
    notifyListeners();
  }

  /// Build a PermissionConfig JSON string from current toggle state.
  String buildPermissionConfigJson() {
    final whitelist = <Map<String, dynamic>>[];
    for (final def in builtinPermDefs) {
      final toolId = def['id']!;
      if (_permEnabled[toolId] == true) {
        whitelist.add({'tool': toolId, 'mode': 'all'});
      }
    }
    return jsonEncode({'whitelist': whitelist, 'blacklist': []});
  }

  void _loadPermState(Map<String, dynamic> saved) {
    final permMap = saved['permEnabled'] as Map<String, dynamic>?;
    if (permMap != null) {
      permMap.forEach((k, v) => _permEnabled[k] = v == true);
    }
    // Ensure all defs have a value
    for (final def in builtinPermDefs) {
      final id = def['id']!;
      _permEnabled.putIfAbsent(id, () => def['default'] == 'true');
    }
  }

  // ─── Lifecycle ──────────────────────────────

  Future<void> initIfEnabled({
    required String storagePath,
    required String host,
    required int port,
    required String deviceName,
    String? topic,
  }) async {
    _host = host;
    _port = port;
    _deviceName = deviceName;
    _topic = topic ?? '';

    _connecting = true;
    _statusMessage = 'Connecting...';
    notifyListeners();

    // Load saved profiles from disk
    _loadProfiles();

    final config = WenzAgentConfig(
      storagePath: storagePath,
      host: host,
      port: port,
      deviceName: deviceName,
      topic: topic,
    );

    final log = LogService();
    log.info(
      'AgentManager',
      'Initializing WenzAgent SDK — $host:$port as "$deviceName"',
    );
    final ok = await wenzagent.initialize(config);
    if (!ok) {
      _statusMessage = 'SDK init failed';
      _connecting = false;
      log.error('AgentManager', 'WenzAgent SDK initialization failed');
      notifyListeners();
      return;
    }

    log.info(
      'AgentManager',
      'WenzAgent SDK initialized — subscribing to events',
    );
    _msgSub = wenzagent.onMessage.listen(_onMessage);
    _statusSub = wenzagent.onStatusChange.listen(_onStatusChange);
    _connSub = wenzagent.onConnectionChange.listen(_onConnectionChange);

    _initialized = true;
    await joinLAN();
  }

  /// Join an existing LAN server.
  Future<void> joinLAN({String? host, int? port}) async {
    if (host != null) _host = host;
    if (port != null) _port = port;

    _connecting = true;
    _statusMessage = 'Connecting...';
    notifyListeners();

    final log = LogService();
    log.info('AgentManager', 'Connecting to WenzAgent LAN — $_host:$_port');
    final ok = await wenzagent.connect();
    _connected = ok;
    _connecting = false;
    _statusMessage = ok ? 'Connected' : 'Connection failed';
    if (ok) {
      log.info('AgentManager', 'WenzAgent LAN connected — $_host:$_port');
    } else {
      log.error(
        'AgentManager',
        'WenzAgent LAN connection failed — $_host:$_port',
      );
    }
    notifyListeners();

    if (ok) await refreshAll();
  }

  /// "Create LAN" — same as joinLAN since the server is separate.
  /// The user runs wenzagent_server.exe externally; this just connects.
  Future<void> createLAN({String? host, int? port, String? topic}) async {
    await joinLAN(host: host ?? '127.0.0.1', port: port ?? 9090);
  }

  Future<void> disconnect() async {
    LogService().info('AgentManager', 'Disconnecting from WenzAgent LAN');
    await wenzagent.disconnect();
    _connected = false;
    _statusMessage = 'Disconnected';
    _onlineDevices = [];
    _agentSummaries = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _stopStreamingPoll();
    _msgSub?.cancel();
    _statusSub?.cancel();
    _connSub?.cancel();
    wenzagent.dispose();
    super.dispose();
  }

  // ─── Refresh Data ───────────────────────────

  Future<void> refreshAll() async {
    // Must be sequential: refreshSummaries() reads _employees,
    // so refreshEmployees() must complete first.
    await refreshDevices();
    await refreshEmployees();
    await refreshSummaries();
  }

  Future<void> refreshDevices() async {
    _onlineDevices = await wenzagent.getOnlineDevices();
    notifyListeners();
  }

  Future<void> refreshEmployees() async {
    try {
      final emps = await wenzagent.getAllEmployees();
      _employees = emps
          .map(
            (e) => AgentModel(
              uuid: e.uuid,
              name: e.name,
              description: e.description,
              deviceId: e.currentDeviceId,
              provider: e.provider,
              model: e.model,
              status: e.status,
            ),
          )
          .toList();
      notifyListeners();
    } catch (_) {}
  }

  /// Ensure the employee list is available (used by live-stream routing).
  Future<List<AgentModel>> refreshEmployeesIfNeeded() async {
    if (_employees.isEmpty) {
      await refreshEmployees();
    }
    return _employees;
  }

  Future<void> refreshSummaries() async {
    _agentSummaries = (await wenzagent.getAgentSummaries())
        .where((a) {
          // Filter out orphaned sessions whose employee no longer exists.
          // This prevents "Employee not found" errors when the SDK tries to
          // restore agents for deleted employees during initialization.
          if (!_employees.any((e) => e.uuid == a.employeeId)) return false;
          // Filter out sessions the user explicitly deleted (SDK doesn't clear
          // the summary table on session delete, so we track them here).
          if (_hiddenSessionIds.contains(a.employeeId)) return false;
          return true;
        })
        .map((a) {
          // Resolve real name from employees list
          final emp = _employees.firstWhere((e) => e.uuid == a.employeeId);
          final lastMsg = a.lastMsgPreview;
          return AgentModel(
            uuid: a.employeeId,
            name: emp.name,
            deviceId: a.deviceId,
            description: lastMsg.isNotEmpty ? lastMsg : null,
            status: a.status,
          );
        })
        .toList();
    notifyListeners();
  }

  // ─── Profile Management ─────────────────────

  String get _profilesPath =>
      r'D:\AiVtuber_Agent_profile\wenzagent_profiles.json';

  void _loadProfiles() {
    try {
      final file = File(_profilesPath);
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync());
        if (raw is Map<String, dynamic>) {
          // New format: {"profiles": [...], "lastProfileIndex": {...}}
          final profiles =
              (raw['profiles'] as List?)
                  ?.map(
                    (e) => ProviderProfile.fromJson(e as Map<String, dynamic>),
                  )
                  .toList() ??
              [];
          if (profiles.isNotEmpty) _providerProfiles = profiles;
          final lastIdx = raw['lastProfileIndex'] as Map<String, dynamic>?;
          if (lastIdx != null) {
            _lastProfileIndex.clear();
            lastIdx.forEach(
              (k, v) => _lastProfileIndex[k] = (v as num).toInt(),
            );
          }
          final personas = raw['employeePersonas'] as Map<String, dynamic>?;
          if (personas != null) {
            _personas.clear();
            personas.forEach((k, v) {
              if (v is Map<String, dynamic>) {
                _personas[k] = AgentPersona.fromJson(v);
              }
            });
          }
        } else if (raw is List) {
          // Legacy format: plain list of profiles
          final profiles = raw
              .map((e) => ProviderProfile.fromJson(e as Map<String, dynamic>))
              .toList();
          if (profiles.isNotEmpty) _providerProfiles = profiles;
        }
        _loadPermState(raw is Map<String, dynamic> ? raw : {});
        // Load hidden session IDs
        final hidden = raw['hiddenSessionIds'];
        if (hidden is List) {
          _hiddenSessionIds.addAll(hidden.cast<String>());
        }
      }
    } catch (e) {
      print('[AgentManager] loadProfiles failed: $e');
    }
  }

  void _saveProfiles() {
    try {
      final file = File(_profilesPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        jsonEncode({
          'profiles': _providerProfiles.map((p) => p.toJson()).toList(),
          'lastProfileIndex': _lastProfileIndex,
          'permEnabled': _permEnabled,
          'hiddenSessionIds': _hiddenSessionIds.toList(),
          'employeePersonas': _personas.map((k, v) => MapEntry(k, v.toJson())),
        }),
      );
    } catch (e) {
      print('[AgentManager] saveProfiles failed: $e');
    }
  }

  void addProfile(ProviderProfile profile) {
    _providerProfiles.add(profile);
    _saveProfiles();
    notifyListeners();
  }

  void updateProfile(int index, ProviderProfile profile) {
    if (index >= 0 && index < _providerProfiles.length) {
      _providerProfiles[index] = profile;
      _saveProfiles();
      notifyListeners();
    }
  }

  void removeProfile(int index) {
    if (index >= 0 && index < _providerProfiles.length) {
      _providerProfiles.removeAt(index);
      _saveProfiles();
      notifyListeners();
    }
  }

  // ─── Employee CRUD ──────────────────────────

  /// Create a new AI employee and sync to contacts.
  Future<AgentModel?> createEmployee({
    required String name,
    String? description,
    String? deviceId,
    String? provider,
    String? model,
  }) async {
    try {
      final permJson = buildPermissionConfigJson();
      final entity = await wenzagent.createEmployee(
        name: name,
        description: description ?? '',
        deviceId: deviceId,
        provider: provider ?? 'openai',
        model: model ?? 'gpt-4o',
        permissionConfigJson: permJson,
      );
      if (entity != null) {
        await refreshEmployees();
        return AgentModel(
          uuid: entity.uuid,
          name: entity.name,
          description: entity.description,
          deviceId: entity.currentDeviceId,
          provider: entity.provider,
          model: entity.model,
          status: entity.status,
        );
      }
    } catch (e) {
      print('[AgentManager] createEmployee failed: $e');
    }
    return null;
  }

  /// Delete an employee.
  Future<void> deleteEmployee(String uuid) async {
    try {
      await wenzagent.deleteEmployee(uuid);
      _hiddenSessionIds.remove(
        uuid,
      ); // Employee gone, no need to track its session
      _personas.remove(uuid);
      _saveProfiles();
      await refreshEmployees();
      await refreshSummaries(); // Clean up orphaned agent session
      notifyListeners();
    } catch (_) {}
  }

  // ─── Global Skill CRUD ────────────────────────

  /// Refresh global skills list.
  Future<void> refreshGlobalSkills() async {
    try {
      _skills = await wenzagent.getGlobalSkills();
      notifyListeners();
    } catch (_) {}
  }

  /// Refresh employee skills for active agent.
  Future<void> refreshEmployeeSkills() async {
    if (_activeEmployeeId == null) {
      _employeeSkills = [];
      notifyListeners();
      return;
    }
    try {
      _employeeSkills = await wenzagent.getEmployeeSkills(_activeEmployeeId!);
      notifyListeners();
    } catch (_) {}
  }

  /// Create a global folder skill.
  Future<GlobalSkillEntity?> createSkill({
    required String name,
    String? description,
    required String folderPath,
  }) async {
    try {
      final entity = await wenzagent.createGlobalFolderSkill(
        name: name,
        description: description,
        folderPath: folderPath,
      );
      if (entity != null) await refreshGlobalSkills();
      return entity;
    } catch (e) {
      print('[AgentManager] createSkill failed: $e');
      return null;
    }
  }

  /// Create a global MCP skill.
  Future<GlobalSkillEntity?> createMcpSkill({
    required String name,
    String? description,
    required McpServerConfig serverConfig,
  }) async {
    try {
      final entity = await wenzagent.createGlobalMcpSkill(
        name: name,
        description: description,
        serverConfig: serverConfig,
      );
      if (entity != null) await refreshGlobalSkills();
      return entity;
    } catch (e) {
      print('[AgentManager] createMcpSkill failed: $e');
      return null;
    }
  }

  /// Delete a global skill.
  Future<void> deleteSkill(String uuid) async {
    try {
      await wenzagent.deleteGlobalSkill(uuid);
      await refreshGlobalSkills();
    } catch (_) {}
  }

  /// Toggle global skill enabled.
  Future<void> toggleSkillEnabled(String uuid) async {
    try {
      final skill = _skills.firstWhere((s) => s.uuid == uuid);
      final newEnabled = skill.enabled != 1;
      await wenzagent.setGlobalSkillEnabled(uuid, newEnabled);
      await refreshGlobalSkills();
    } catch (_) {}
  }

  /// Add global skill to active employee.
  Future<void> addSkillToEmployee(String globalSkillUuid) async {
    if (_activeEmployeeId == null) return;
    try {
      final gs = _skills.firstWhere((s) => s.uuid == globalSkillUuid);
      await wenzagent.addGlobalSkillToEmployee(
        employeeId: _activeEmployeeId!,
        globalSkill: gs,
      );
      await refreshEmployeeSkills();
    } catch (_) {}
  }

  /// Remove global skill from active employee.
  Future<void> removeSkillFromEmployee(String globalSkillUuid) async {
    if (_activeEmployeeId == null) return;
    try {
      await wenzagent.removeGlobalSkillFromEmployee(
        _activeEmployeeId!,
        globalSkillUuid,
      );
      await refreshEmployeeSkills();
    } catch (_) {}
  }

  /// Clear ALL MultiAgent cache: delete all employee sessions, messages,
  /// and employees. Full reset requiring re-setup afterwards.
  Future<void> clearAllCache() async {
    // First delete all agent sessions (messages + session records)
    for (final emp in List<AgentModel>.from(_employees)) {
      try {
        await wenzagent.deleteAgentSession(emp.uuid);
      } catch (_) {}
    }
    // Then delete all employees
    for (final emp in List<AgentModel>.from(_employees)) {
      try {
        await wenzagent.deleteEmployee(emp.uuid);
      } catch (_) {}
    }
    _employees = [];
    _agentSummaries = [];
    _hiddenSessionIds.clear();
    _personas.clear();
    _activeEmployeeId = null;
    _activeEmployeeName = null;
    _activeMessages = [];
    _saveProfiles();
    notifyListeners();
  }

  /// Delete an agent session without deleting the employee.
  Future<void> deleteAgentSession(String employeeId) async {
    try {
      await wenzagent.deleteAgentSession(employeeId);
      _hiddenSessionIds.add(
        employeeId,
      ); // SDK doesn't clear summary, we filter manually
      _saveProfiles();
      await refreshSummaries();
      notifyListeners();
    } catch (_) {}
  }

  // ─── Active Chat ────────────────────────────

  /// Last used profile index per employee.
  final Map<String, int> _lastProfileIndex = {};
  int? _activeProfileIndex;

  int? get activeProfileIndex => _activeProfileIndex;
  ProviderProfile? get activeProfile =>
      _activeProfileIndex != null &&
          _activeProfileIndex! < _providerProfiles.length
      ? _providerProfiles[_activeProfileIndex!]
      : (_providerProfiles.isNotEmpty ? _providerProfiles.first : null);

  /// Get the last-used profile index for an employee.
  int? getLastProfileIndex(String employeeId) => _lastProfileIndex[employeeId];

  /// Open agent with profile. Remembers the choice for next time.
  Future<void> openAgentWithProfile(
    String employeeId,
    String name,
    int profileIndex,
  ) async {
    _lastProfileIndex[employeeId] = profileIndex;
    _activeProfileIndex = profileIndex;
    _saveProfiles(); // includes _lastProfileIndex

    if (profileIndex < 0 || profileIndex >= _providerProfiles.length) return;
    final profile = _providerProfiles[profileIndex];

    try {
      await wenzagent.updateEmployeeProvider(
        employeeId: employeeId,
        provider: _parseProviderName(profile.baseUrl),
        model: profile.model,
        apiKey: profile.apiKey,
        baseUrl: profile.baseUrl,
      );
    } catch (e) {
      print('[AgentManager] updateEmployeeProvider failed: $e');
    }

    // Apply persona system prompt (Direction 1: personality lives with the face)
    final persona = _personas[employeeId];
    try {
      await wenzagent.updateEmployeeSystemPrompt(
        employeeId: employeeId,
        systemPrompt:
            (persona != null && persona.systemPrompt.trim().isNotEmpty)
            ? persona.systemPrompt.trim()
            : null,
      );
    } catch (e) {
      print('[AgentManager] updateEmployeeSystemPrompt failed: $e');
    }

    await openAgent(employeeId, name);
  }

  String _parseProviderName(String baseUrl) {
    if (baseUrl.contains('openai')) return 'openai';
    if (baseUrl.contains('anthropic')) return 'anthropic';
    if (baseUrl.contains('deepseek')) return 'deepseek';
    if (baseUrl.contains('ollama') || baseUrl.contains('11434'))
      return 'ollama';
    return 'openai';
  }

  Future<void> openAgent(String employeeId, String name) async {
    // If this employee's session was previously hidden (deleted), unhide it
    // so a fresh session can start. Messages were hard-deleted by deleteAgentSession.
    if (_hiddenSessionIds.remove(employeeId)) {
      _saveProfiles();
    }

    _activeEmployeeId = employeeId;
    _activeEmployeeName = name;
    _activeMessages = [];
    _lastSpokenAssistantMsgId = null;
    _lastAgentStatus = 'idle';
    notifyListeners();

    final proxy = await wenzagent.openAgent(employeeId);
    if (proxy != null) {
      final messages = await wenzagent.getActiveMessages();
      _activeMessages = messages;
      notifyListeners();
      // Refresh summaries so the new agent appears in AGENTS sidebar
      await refreshSummaries();
      // Load global skills + employee skills
      await refreshGlobalSkills();
      await refreshEmployeeSkills();
    } else {
      // Employee not found (likely deleted) — clean up orphaned session state
      print('[AgentManager] Employee not found: $employeeId, auto-cleaning');
      _activeEmployeeId = null;
      _activeEmployeeName = null;
      try {
        await wenzagent.deleteAgentSession(employeeId);
        await refreshSummaries();
      } catch (_) {}
      notifyListeners();
    }
  }

  /// Make sure the WenzAgent SDK is initialized and connected.
  /// Called by the live-stream side for viewer @Agent tasks even when the
  /// Multi-Agent page has never been opened.
  Future<bool> ensureReady() async {
    if (!_initialized) {
      await initIfEnabled(
        storagePath: r'D:\AiVtuber_Agent_profile\wenzagent',
        host: _host,
        port: _port,
        deviceName: _deviceName,
        topic: _topic,
      );
    }
    if (!_connected) {
      await joinLAN();
    }
    if (_connected && _employees.isEmpty) {
      await refreshAll();
    }
    return _connected;
  }

  /// Route a Bilibili danmaku task to an employee (Direction 2).
  /// Opens the employee's session if needed then sends the task text.
  Future<void> runStreamAgentTask(String employeeId, String task) async {
    if (employeeId.isEmpty || task.trim().isEmpty) return;
    if (_agentTaskRunning) return;

    _agentTaskRunning = true;
    notifyListeners();

    try {
      await ensureReady();
      if (!_connected) {
        LogService().warn('AgentManager', 'Stream agent task skipped: offline');
        return;
      }

      // Find employee (refresh if list is stale)
      if (!_employees.any((e) => e.uuid == employeeId)) {
        await refreshEmployees();
      }
      AgentModel? emp;
      for (final e in _employees) {
        if (e.uuid == employeeId) {
          emp = e;
          break;
        }
      }
      if (emp == null) {
        LogService().warn(
          'AgentManager',
          'Stream agent task: employee not found',
        );
        return;
      }

      if (_activeEmployeeId != employeeId) {
        final profileIndex = _lastProfileIndex[employeeId] ?? 0;
        await openAgentWithProfile(employeeId, emp.name, profileIndex);
      }
      await sendMessage(task);
    } finally {
      _agentTaskRunning = false;
      notifyListeners();
    }
  }

  /// Preview a persona voice in the persona editor.
  Future<void> previewPersonaVoice(AgentPersona persona, String text) async {
    final tts = _tts ??= TTSService(StorageService());
    tts.setVoice(
      persona.voice.isEmpty ? 'zh-CN-XiaoxiaoNeural' : persona.voice,
    );
    await tts.synthesizeAndPlay(text);
  }

  Future<void> sendMessage(String text) async {
    if (_activeEmployeeId == null || text.trim().isEmpty) return;

    final log = LogService();
    log.info(
      'AgentManager',
      'Sending message to "${_activeEmployeeName ?? _activeEmployeeId}"',
    );

    _activeMessages.add({
      'role': 'user',
      'content': text,
      'type': 'text',
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
    });
    notifyListeners();
    _scrollToBottom();

    await wenzagent.sendMessage(text);
    _startStreamingPoll(); // Start polling to show tool calls progressively
  }

  void _scrollToBottom() {
    // Will be called after build — the chat panel's ScrollController handles it
  }

  Future<void> _refreshActiveMessages() async {
    if (_activeEmployeeId == null) return;
    final messages = await wenzagent.getActiveMessages();
    _activeMessages = messages;
    notifyListeners();
  }

  Future<void> interruptAgent() async {
    _stopStreamingPoll();
    await wenzagent.interrupt();
    notifyListeners();
  }

  void closeAgent() {
    _stopStreamingPoll();
    _activeEmployeeId = null;
    _activeEmployeeName = null;
    _activeMessages = [];
    notifyListeners();
  }

  // ─── Event Handlers ─────────────────────────

  void _onMessage(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'message') {
      final msgData = event['message'] as Map<String, dynamic>?;
      final empId = event['employeeId'] as String?;
      if (msgData != null && empId != null && empId == _activeEmployeeId) {
        // Merge directly for real-time display (no DB round-trip)
        final msgId = msgData['id'] as String?;
        final existingIdx = _activeMessages.indexWhere((m) => m['id'] == msgId);
        if (existingIdx >= 0) {
          _activeMessages[existingIdx] = msgData;
        } else {
          // If this is the server's version of our optimistic local message
          // (different ID, same content), replace the local one to avoid duplication.
          final role = msgData['role'] as String?;
          if (role == 'user') {
            final content = msgData['content'] as String? ?? '';
            final localIdx = _activeMessages.indexWhere(
              (m) =>
                  m['role'] == 'user' &&
                  (m['id'] as String?)?.startsWith('local-') == true &&
                  (m['content'] as String?) == content,
            );
            if (localIdx >= 0) {
              _activeMessages[localIdx] = msgData;
            } else {
              _activeMessages.add(msgData);
            }
          } else {
            _activeMessages.add(msgData);
          }
        }
        notifyListeners();
      }
    }
    if (type == 'unread') {
      refreshSummaries();
    }
  }

  /// Speak the latest assistant reply with the employee's persona voice.
  Future<void> _speakLatestAssistantMessage() async {
    final employeeId = _activeEmployeeId;
    if (employeeId == null) return;
    final persona = _personas[employeeId];
    if (persona == null || !persona.voiceEnabled) return;

    String? content;
    String? msgId;
    for (var i = _activeMessages.length - 1; i >= 0; i--) {
      final m = _activeMessages[i];
      final role = m['role'] as String?;
      final type = m['type'] as String?;
      final text = (m['content'] as String? ?? '').trim();
      if (role == 'assistant' &&
          (type == null || type == 'text') &&
          text.isNotEmpty) {
        content = text;
        msgId = m['id'] as String?;
        break;
      }
    }
    if (content == null || content.isEmpty) return;
    if (msgId != null && msgId == _lastSpokenAssistantMsgId) return;
    _lastSpokenAssistantMsgId = msgId ?? content;

    final tts = _tts ??= TTSService(StorageService());
    tts.setVoice(
      persona.voice.isEmpty ? 'zh-CN-XiaoxiaoNeural' : persona.voice,
    );
    await tts.synthesizeAndPlay(content);
  }

  void _onStatusChange(Map<String, dynamic> event) {
    if (event['employeeId'] == _activeEmployeeId) {
      final status = event['status'] as String?;
      final name = _activeEmployeeName ?? event['employeeId'];
      final previousStatus = _lastAgentStatus;
      if (status == 'idle') {
        LogService().info('AgentManager', 'Agent "$name" is idle');
      } else if (status == 'processing' || status == 'streaming') {
        LogService().info('AgentManager', 'Agent "$name" started processing');
      }
      // Start/stop streaming poll
      if (status == 'streaming' || status == 'processing') {
        _startStreamingPoll();
      } else {
        _stopStreamingPoll();
        // Speak the reply after a processing→idle transition (Direction 1).
        _refreshActiveMessages().then((_) {
          if (previousStatus == 'processing' || previousStatus == 'streaming') {
            _speakLatestAssistantMessage();
          }
        });
      }
      _lastAgentStatus = status ?? previousStatus;
      notifyListeners();
    }
  }

  Timer? _streamingTimer;
  void _startStreamingPoll() {
    _stopStreamingPoll();
    _streamingTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _refreshActiveMessages();
    });
  }

  void _stopStreamingPoll() {
    _streamingTimer?.cancel();
    _streamingTimer = null;
  }

  void _onConnectionChange(bool connected) {
    _connected = connected;
    _statusMessage = connected ? 'Connected' : 'Disconnected';
    if (connected) {
      LogService().info('AgentManager', 'Connection state: online');
    } else {
      LogService().warn('AgentManager', 'Connection state: offline');
      _onlineDevices = [];
      _agentSummaries = [];
    }
    notifyListeners();
  }
}
