import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;

/// Local JSON-file storage at D:\AiVtuber_Agent_profile\
/// Mimics Steam-style local save + optional cloud sync.
class StorageService {
  static const _profileDir = r'D:\AiVtuber_Agent_profile';
  static String get profileDir => _profileDir;
  static const _settingsFile = 'settings.json';
  static const _sessionsDir = 'sessions';

  final _uuid = const Uuid();

  StorageService() {
    _ensureDirs();
  }

  String get profilePath => _profileDir;
  String get sessionsPath => p.join(_profileDir, _sessionsDir);

  void _ensureDirs() {
    final dir = Directory(_profileDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final sDir = Directory(sessionsPath);
    if (!sDir.existsSync()) sDir.createSync(recursive: true);
  }

  // ─── Settings ───

  Map<String, dynamic> loadSettings() {
    final file = File(p.join(_profileDir, _settingsFile));
    if (!file.existsSync()) return {};
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void saveSettings(Map<String, dynamic> settings) {
    final file = File(p.join(_profileDir, _settingsFile));
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(settings));
  }

  // ─── Sessions ───

  String createSession(String title) {
    final id = _uuid.v4();
    final session = {
      'id': id,
      'title': title,
      'created_at': DateTime.now().toIso8601String(),
      'history': <Map<String, dynamic>>[],
      'indexed': false,
    };
    _writeSession(id, session);
    return id;
  }

  Map<String, dynamic>? getSession(String id) {
    final file = File(p.join(sessionsPath, '$id.json'));
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  void updateSession(String id, Map<String, dynamic> data) {
    _writeSession(id, data);
  }

  void deleteSession(String id) {
    final file = File(p.join(sessionsPath, '$id.json'));
    if (file.existsSync()) file.deleteSync();
  }

  void renameSession(String id, String newTitle) {
    final session = getSession(id);
    if (session != null) {
      session['title'] = newTitle;
      _writeSession(id, session);
    }
  }

  List<Map<String, dynamic>> listSessions() {
    final dir = Directory(sessionsPath);
    if (!dir.existsSync()) return [];
    final sessions = <Map<String, dynamic>>[];
    for (final entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final data = jsonDecode(entity.readAsStringSync()) as Map<String, dynamic>;
          sessions.add({
            'id': data['id'],
            'title': data['title'] ?? 'Untitled',
            'created_at': data['created_at'] ?? '',
            'history_length': (data['history'] as List?)?.length ?? 0,
            'indexed': data['indexed'] ?? false,
          });
        } catch (_) {}
      }
    }
    // Sort by created_at descending
    sessions.sort((a, b) => '${b['created_at']}'.compareTo('${a['created_at']}'));
    return sessions;
  }

  Map<String, dynamic>? getSessionFull(String id) {
    return getSession(id);
  }

  void _writeSession(String id, Map<String, dynamic> data) {
    final file = File(p.join(sessionsPath, '$id.json'));
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(data));
  }
}
