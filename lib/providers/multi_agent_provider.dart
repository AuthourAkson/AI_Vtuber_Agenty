import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/wenzagent_service.dart';

/// MultiAgentProvider — manages multi-agent network state for the UI.
///
/// Wraps WenzAgentService with ChangeNotifier so widgets can reactively
/// update to connection changes, new messages, and agent status updates.
class MultiAgentProvider extends ChangeNotifier {
  final WenzAgentService wenzagent = WenzAgentService();

  // State
  bool _enabled = false;
  bool _connected = false;
  bool _connecting = false;
  String _statusMessage = 'Not connected';

  // Data
  List<MultiAgentInfo> _agentSummaries = [];
  List<DeviceInfo> _onlineDevices = [];

  // Active agent chat
  String? _activeEmployeeId;
  List<Map<String, dynamic>> _activeMessages = [];
  String _activeAgentStatus = 'idle';

  // Subscriptions
  StreamSubscription? _msgSub;
  StreamSubscription? _statusSub;
  StreamSubscription? _connSub;

  // ─── Getters ─────────────────────────────────────────────

  bool get enabled => _enabled;
  bool get connected => _connected;
  bool get connecting => _connecting;
  String get statusMessage => _statusMessage;
  List<MultiAgentInfo> get agentSummaries => _agentSummaries;
  List<DeviceInfo> get onlineDevices => _onlineDevices;
  String? get activeEmployeeId => _activeEmployeeId;
  List<Map<String, dynamic>> get activeMessages => _activeMessages;
  String get activeAgentStatus => _activeAgentStatus;

  // ─── Lifecycle ───────────────────────────────────────────

  /// Initialize the WenzAgent client. Call once at startup if enabled.
  Future<void> initIfEnabled({
    required String storagePath,
    required String host,
    required int port,
    required String deviceName,
    String? topic,
  }) async {
    _enabled = true;
    _connecting = true;
    _statusMessage = 'Connecting...';
    notifyListeners();

    final config = WenzAgentConfig(
      storagePath: storagePath,
      host: host,
      port: port,
      deviceName: deviceName,
      topic: topic,
    );

    final ok = await wenzagent.initialize(config);
    if (!ok) {
      _statusMessage = 'Failed to initialize WenzAgent SDK';
      _connecting = false;
      notifyListeners();
      return;
    }

    // Subscribe to events
    _msgSub = wenzagent.onMessage.listen(_onMessage);
    _statusSub = wenzagent.onStatusChange.listen(_onStatusChange);
    _connSub = wenzagent.onConnectionChange.listen(_onConnectionChange);

    // Connect
    final connected = await wenzagent.connect();
    _connected = connected;
    _connecting = false;
    _statusMessage = connected ? 'Connected' : 'Connection failed';
    notifyListeners();

    if (connected) {
      await refreshDevices();
      await refreshSummaries();
    }
  }

  /// Connect to LAN server.
  Future<void> connect() async {
    if (!_enabled) return;
    _connecting = true;
    _statusMessage = 'Connecting...';
    notifyListeners();

    final ok = await wenzagent.connect();
    _connected = ok;
    _connecting = false;
    _statusMessage = ok ? 'Connected' : 'Connection failed';
    notifyListeners();

    if (ok) {
      await refreshDevices();
      await refreshSummaries();
    }
  }

  /// Disconnect from LAN.
  Future<void> disconnect() async {
    await wenzagent.disconnect();
    _connected = false;
    _statusMessage = 'Disconnected';
    _agentSummaries = [];
    _onlineDevices = [];
    notifyListeners();
  }

  /// Full cleanup.
  @override
  void dispose() {
    _msgSub?.cancel();
    _statusSub?.cancel();
    _connSub?.cancel();
    wenzagent.dispose();
    super.dispose();
  }

  // ─── Active Agent Chat ───────────────────────────────────

  /// Open an agent session.
  Future<void> openAgent(String employeeId) async {
    _activeEmployeeId = employeeId;
    _activeMessages = [];
    notifyListeners();

    final proxy = await wenzagent.openAgent(employeeId);
    if (proxy != null) {
      final messages = await wenzagent.getActiveMessages();
      _activeMessages = messages;
      _activeAgentStatus = wenzagent.activeAgentStatus;
      notifyListeners();
    }
  }

  /// Send a message to the active agent.
  Future<void> sendMessage(String text) async {
    if (_activeEmployeeId == null || text.trim().isEmpty) return;

    // Add user message locally
    _activeMessages.add({
      'role': 'user',
      'content': text,
      'type': 'text',
      'id': 'local-${DateTime.now().millisecondsSinceEpoch}',
    });
    notifyListeners();

    final messageId = await wenzagent.sendMessage(text);
    if (messageId != null) {
      // Refresh messages after a short delay to get the response
      await Future.delayed(const Duration(milliseconds: 500));
      await refreshActiveMessages();
    }
  }

  /// Refresh messages for the active agent.
  Future<void> refreshActiveMessages() async {
    if (_activeEmployeeId == null) return;
    final messages = await wenzagent.getActiveMessages();
    _activeMessages = messages;
    _activeAgentStatus = wenzagent.activeAgentStatus;
    notifyListeners();
  }

  /// Interrupt the active agent.
  Future<void> interruptAgent() async {
    await wenzagent.interrupt();
    _activeAgentStatus = 'idle';
    notifyListeners();
  }

  /// Clear the active session.
  Future<void> clearSession() async {
    await wenzagent.clearSession();
    _activeMessages = [];
    notifyListeners();
  }

  // ─── Device / Employee Queries ───────────────────────────

  /// Refresh the list of online devices.
  Future<void> refreshDevices() async {
    _onlineDevices = await wenzagent.getOnlineDevices();
    notifyListeners();
  }

  /// Refresh session summaries.
  Future<void> refreshSummaries() async {
    _agentSummaries = wenzagent.getSessionSummaries();
    notifyListeners();
  }

  /// Mark all messages as read for an employee.
  void markAllRead(String employeeId) {
    wenzagent.markAllRead(employeeId);
  }

  // ─── Event Handlers ──────────────────────────────────────

  void _onMessage(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    if (type == 'message' && event['employeeId'] == _activeEmployeeId) {
      refreshActiveMessages();
    }
    if (type == 'unread') {
      refreshSummaries();
    }
  }

  void _onStatusChange(Map<String, dynamic> event) {
    if (event['employeeId'] == _activeEmployeeId) {
      _activeAgentStatus = event['status'] as String? ?? 'idle';
      notifyListeners();
    }
  }

  void _onConnectionChange(bool connected) {
    _connected = connected;
    _statusMessage = connected ? 'Connected' : 'Disconnected';
    if (!connected) {
      _agentSummaries = [];
      _onlineDevices = [];
    }
    notifyListeners();
  }
}
