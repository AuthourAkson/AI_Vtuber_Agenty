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

  Future<String?> createNewSession({String? title}) async {
    try {
      final t = (title != null && title.trim().isNotEmpty) ? title.trim() : 'Chat Session';
      final id = t != 'Chat Session'
          ? await _backend.createSessionWithTitle(t)
          : await _backend.createSession();
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
      final list = await _backend.listSessions();
      _sessionsCache = list;
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _backend.deleteSession(sessionId);
      await _refreshCache(); // update cache after delete
    } catch (_) {}
  }

  /// Load initial session list into cache (call on screen init)
  Future<void> loadSessions() => _refreshCache();

  Future<void> renameSession(String id, String newTitle) async {
    await _backend.renameSession(id, newTitle);
    await _refreshCache();
  }
}
