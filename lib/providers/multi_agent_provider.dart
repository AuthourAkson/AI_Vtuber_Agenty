import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:wenzagent/wenzagent.dart';
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

  factory ProviderProfile.fromJson(Map<String, dynamic> json) => ProviderProfile(
    name: json['name'] ?? '',
    baseUrl: json['baseUrl'] ?? 'https://api.openai.com/v1',
    apiKey: json['apiKey'] ?? '',
    model: json['model'] ?? 'gpt-4o',
  );
}

/// Central state manager for Multi-Agent page (replaces old MultiAgentProvider).
///
/// Manages LAN connection, agent/employee lists, active chat, and employee creation.
class AgentManager extends ChangeNotifier {
  final WenzAgentService wenzagent = WenzAgentService();

  // ─── LAN Connection State ───────────────────

  bool _initialized = false;
  bool _connecting = false;
  bool _connected = false;
  String _statusMessage = 'Disconnected';
  String _host = '127.0.0.1';
  int _port = 9090;
  String _deviceName = 'AI VTuber';
  String _topic = '';

  // ─── Multi-Agent Data ───────────────────────

  List<ProviderProfile> _providerProfiles = [
    ProviderProfile(name: 'Default OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o'),
  ];
  List<AgentModel> _employees = [];
  List<AgentModel> _agentSummaries = [];
  List<DeviceInfo> _onlineDevices = [];

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
  List<DeviceInfo> get onlineDevices => _onlineDevices;
  List<ProviderProfile> get providerProfiles => _providerProfiles;

  String? get activeEmployeeId => _activeEmployeeId;
  String? get activeEmployeeName => _activeEmployeeName;
  List<Map<String, dynamic>> get activeMessages => _activeMessages;
  String get activeAgentStatus => wenzagent.activeAgentStatus;

  bool get hasUnreadMessages => _agentSummaries.any((a) => a.status == 'unread');

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

    final ok = await wenzagent.initialize(config);
    if (!ok) {
      _statusMessage = 'SDK init failed';
      _connecting = false;
      notifyListeners();
      return;
    }

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

    final ok = await wenzagent.connect();
    _connected = ok;
    _connecting = false;
    _statusMessage = ok ? 'Connected' : 'Connection failed';
    notifyListeners();

    if (ok) await refreshAll();
  }

  /// "Create LAN" — same as joinLAN since the server is separate.
  /// The user runs wenzagent_server.exe externally; this just connects.
  Future<void> createLAN({String? host, int? port, String? topic}) async {
    await joinLAN(host: host ?? '127.0.0.1', port: port ?? 9090);
  }

  Future<void> disconnect() async {
    await wenzagent.disconnect();
    _connected = false;
    _statusMessage = 'Disconnected';
    _onlineDevices = [];
    _agentSummaries = [];
    notifyListeners();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    _connSub?.cancel();
    wenzagent.dispose();
    super.dispose();
  }

  // ─── Refresh Data ───────────────────────────

  Future<void> refreshAll() async {
    await Future.wait([
      refreshDevices(),
      refreshEmployees(),
      refreshSummaries(),
    ]);
  }

  Future<void> refreshDevices() async {
    _onlineDevices = await wenzagent.getOnlineDevices();
    notifyListeners();
  }

  Future<void> refreshEmployees() async {
    try {
      final emps = await wenzagent.getAllEmployees();
      _employees = emps.map((e) => AgentModel(
        uuid: e.uuid,
        name: e.name,
        description: e.description,
        deviceId: e.currentDeviceId,
        provider: e.provider,
        model: e.model,
        status: e.status,
      )).toList();
      notifyListeners();
    } catch (_) {}
  }

  Future<void> refreshSummaries() async {
    _agentSummaries = wenzagent.getAgentSummaries().map((a) => AgentModel(
      uuid: a.employeeId,
      name: a.name,
      deviceId: a.deviceId,
    )).toList();
    notifyListeners();
  }

  // ─── Profile Management ─────────────────────

  String get _profilesPath => r'D:\AiVtuber_Agent_profile\wenzagent_profiles.json';

  void _loadProfiles() {
    try {
      final file = File(_profilesPath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as List;
        _providerProfiles = json
            .map((e) => ProviderProfile.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      print('[AgentManager] loadProfiles failed: $e');
    }
  }

  void _saveProfiles() {
    try {
      final file = File(_profilesPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(_providerProfiles.map((p) => p.toJson()).toList()));
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
      final entity = await wenzagent.createEmployee(
        name: name,
        description: description ?? '',
        deviceId: deviceId,
        provider: provider ?? 'openai',
        model: model ?? 'gpt-4o',
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
      await refreshEmployees();
    } catch (_) {}
  }

  // ─── Active Chat ────────────────────────────

  /// Open agent with provider profile.
  /// First updates the Employee entity with provider info, then opens the agent.
  Future<void> openAgentWithProfile(String employeeId, String name, ProviderProfile profile) async {
    // CRITICAL: Update Employee entity BEFORE creating agent proxy.
    // The local agent reads Employee.provider/model/apiKey during initialization.
    // setProvider after proxy creation happens too late.
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
    // Now open agent — it reads the updated Employee config
    await openAgent(employeeId, name);
  }

  String _parseProviderName(String baseUrl) {
    if (baseUrl.contains('openai')) return 'openai';
    if (baseUrl.contains('anthropic')) return 'anthropic';
    if (baseUrl.contains('deepseek')) return 'deepseek';
    if (baseUrl.contains('ollama') || baseUrl.contains('11434')) return 'ollama';
    return 'openai';
  }

  Future<void> openAgent(String employeeId, String name) async {
    _activeEmployeeId = employeeId;
    _activeEmployeeName = name;
    _activeMessages = [];
    notifyListeners();

    final proxy = await wenzagent.openAgent(employeeId);
    if (proxy != null) {
      final messages = await wenzagent.getActiveMessages();
      _activeMessages = messages;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text) async {
    if (_activeEmployeeId == null || text.trim().isEmpty) return;

    _activeMessages.add({
      'role': 'user',
      'content': text,
      'type': 'text',
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
    });
    notifyListeners();

    await wenzagent.sendMessage(text);
    await Future.delayed(const Duration(milliseconds: 500));
    await _refreshActiveMessages();
  }

  Future<void> _refreshActiveMessages() async {
    if (_activeEmployeeId == null) return;
    final messages = await wenzagent.getActiveMessages();
    _activeMessages = messages;
    notifyListeners();
  }

  Future<void> interruptAgent() async {
    await wenzagent.interrupt();
    notifyListeners();
  }

  void closeAgent() {
    _activeEmployeeId = null;
    _activeEmployeeName = null;
    _activeMessages = [];
    notifyListeners();
  }

  // ─── Event Handlers ─────────────────────────

  void _onMessage(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'message' && event['employeeId'] == _activeEmployeeId) {
      _refreshActiveMessages();
    }
    if (type == 'unread') {
      refreshSummaries();
    }
  }

  void _onStatusChange(Map<String, dynamic> event) {
    if (event['employeeId'] == _activeEmployeeId) {
      notifyListeners();
    }
  }

  void _onConnectionChange(bool connected) {
    _connected = connected;
    _statusMessage = connected ? 'Connected' : 'Disconnected';
    if (!connected) {
      _onlineDevices = [];
      _agentSummaries = [];
    }
    notifyListeners();
  }
}
