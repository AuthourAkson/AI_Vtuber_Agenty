import '../services/backend_service.dart';
import '../models/message.dart';

/// Manages chat session lifecycle (CRUD via local BackendService).
class SessionManager {
  final BackendService _backend;
  
  // In-memory session list cache for synchronous access
  List<Map<String, dynamic>> _sessionsCache = [];

  SessionManager(this._backend);

  /// Return cached session list (updated after listSessions() calls)
  List<Map<String, dynamic>> getSessionsCache() => _sessionsCache;

  Future<String?> createNewSession() async {
    try {
      final id = await _backend.createSession();
      if (id != null) await _refreshCache();
      return id;
    } catch (e) {
      return null;
    }
  }

  Future<void> _refreshCache() async {
    try {
      _sessionsCache = await _backend.listSessions();
    } catch (_) {}
  }

  Future<void> updateSessionContent(String? sessionId, List<HistoryItem> history) async {
    if (sessionId == null) return;
    try {
      await _backend.updateSession(sessionId, history);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> fetchSessionContent(String sessionId) async {
    try {
      return await _backend.getSession(sessionId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    try {
      return await _backend.listSessions();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _backend.deleteSession(sessionId);
    } catch (_) {}
  }
}
