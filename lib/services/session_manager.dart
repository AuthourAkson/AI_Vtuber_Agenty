import '../services/backend_service.dart';
import '../models/message.dart';

/// Manages chat session lifecycle (CRUD via local BackendService).
class SessionManager {
  final BackendService _backend;

  SessionManager(this._backend);

  Future<String?> createNewSession() async {
    try {
      return await _backend.createSession();
    } catch (e) {
      return null;
    }
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
