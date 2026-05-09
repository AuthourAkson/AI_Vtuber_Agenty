import 'api_client.dart';
import '../models/message.dart';

/// Manages chat session lifecycle (CRUD operations via backend API)
class SessionManager {
  final ApiClient _api;

  SessionManager(this._api);

  Future<String?> createNewSession() async {
    try {
      return await _api.createSession();
    } catch (e) {
      return null;
    }
  }

  Future<void> updateSessionContent(String? sessionId, List<HistoryItem> history) async {
    if (sessionId == null) return;
    try {
      await _api.updateSession(sessionId, history);
    } catch (_) {}
  }

  Future<Map<String, dynamic>?> fetchSessionContent(String sessionId) async {
    try {
      return await _api.getSession(sessionId);
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listSessions() async {
    try {
      return await _api.listSessions();
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteSession(String sessionId) async {
    try {
      await _api.deleteSession(sessionId);
    } catch (_) {}
  }
}
