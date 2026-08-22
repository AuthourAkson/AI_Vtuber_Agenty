import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

/// Sync backend types matching WenzFlow's design.
enum SyncBackend { webdav, localFolder }

/// Sync configuration persisted to SharedPreferences.
class SyncConfig {
  SyncBackend backend;
  String webdavUrl;
  String webdavUsername;
  String webdavPassword;
  String localFolderPath;
  bool autoSync;
  int intervalMinutes;

  SyncConfig({
    this.backend = SyncBackend.webdav,
    this.webdavUrl = '',
    this.webdavUsername = '',
    this.webdavPassword = '',
    this.localFolderPath = '',
    this.autoSync = false,
    this.intervalMinutes = 10,
  });

  static const _kBackend = 'sync_backend';
  static const _kWebdavUrl = 'sync_webdav_url';
  static const _kWebdavUser = 'sync_webdav_user';
  static const _kWebdavPass = 'sync_webdav_pass';
  static const _kLocalPath = 'sync_local_path';
  static const _kAutoSync = 'sync_auto';
  static const _kInterval = 'sync_interval';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    backend = SyncBackend.values[prefs.getInt(_kBackend) ?? 0];
    webdavUrl = prefs.getString(_kWebdavUrl) ?? '';
    webdavUsername = prefs.getString(_kWebdavUser) ?? '';
    webdavPassword = prefs.getString(_kWebdavPass) ?? '';
    localFolderPath = prefs.getString(_kLocalPath) ?? '';
    autoSync = prefs.getBool(_kAutoSync) ?? false;
    intervalMinutes = prefs.getInt(_kInterval) ?? 10;
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kBackend, backend.index);
    await prefs.setString(_kWebdavUrl, webdavUrl);
    await prefs.setString(_kWebdavUser, webdavUsername);
    await prefs.setString(_kWebdavPass, webdavPassword);
    await prefs.setString(_kLocalPath, localFolderPath);
    await prefs.setBool(_kAutoSync, autoSync);
    await prefs.setInt(_kInterval, intervalMinutes);
  }

  bool get isConfigured {
    return switch (backend) {
      SyncBackend.webdav => webdavUrl.isNotEmpty && webdavUsername.isNotEmpty,
      SyncBackend.localFolder => localFolderPath.isNotEmpty,
    };
  }
}

/// Result of a sync operation.
class SyncResult {
  final bool success;
  final String message;
  final int filesUploaded;
  final int filesDownloaded;
  final DateTime timestamp;

  SyncResult({
    required this.success,
    this.message = '',
    this.filesUploaded = 0,
    this.filesDownloaded = 0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Sync status for UI.
enum SyncStatus { idle, syncing, success, failed }

/// Service handling data synchronization for AiVtuber_Agent.
///
/// Supports two backends:
///   - WebDAV (compatible with Nutstore/坚果云, Nextcloud, ownCloud)
///   - Local Folder (copy to external drive / cloud sync folder)
///
/// Data source: D:\AiVtuber_Agent_profile\
class SyncService {
  static final SyncService _instance = SyncService._();
  factory SyncService() => _instance;
  SyncService._();

  final SyncConfig config = SyncConfig();
  SyncStatus status = SyncStatus.idle;
  SyncResult? lastResult;
  Timer? _autoSyncTimer;
  final HttpClient _client = HttpClient();

  /// Callback for UI updates.
  final List<void Function()> _listeners = [];
  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);
  void _notify() {
    for (final fn in List.from(_listeners)) {
      fn();
    }
  }

  String get _profilePath => r'D:\AiVtuber_Agent_profile';

  // ══════════════════════════════════════════════════════════
  // Configuration
  // ══════════════════════════════════════════════════════════

  Future<void> init() async {
    await config.load();
    if (config.autoSync && config.isConfigured) {
      startAutoSync();
    }
  }

  void startAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = Timer.periodic(
      Duration(minutes: config.intervalMinutes),
      (_) => syncNow(),
    );
  }

  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
  }

  // ══════════════════════════════════════════════════════════
  // Connection Test
  // ══════════════════════════════════════════════════════════

  Future<SyncResult> testConnection() async {
    SyncResult result;
    try {
      result = switch (config.backend) {
        SyncBackend.webdav => await _testWebdav(),
        SyncBackend.localFolder => await _testLocalFolder(),
      };
    } catch (e) {
      result = SyncResult(success: false, message: e.toString());
    }

    // Update status so the UI doesn't stay stuck on "Testing..." after
    // the connection test finishes.
    lastResult = result;
    status = result.success ? SyncStatus.success : SyncStatus.failed;
    _notify();
    return result;
  }

  Future<SyncResult> _testWebdav() async {
    try {
      final uri = Uri.parse(config.webdavUrl);
      final req = await _client
          .openUrl('PROPFIND', uri)
          .timeout(const Duration(seconds: 10));
      req.headers.set('Depth', '0');
      _setAuth(req);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return SyncResult(success: true, message: 'Connection successful');
      }
      return SyncResult(
        success: false,
        message: 'HTTP ${resp.statusCode}: ${resp.reasonPhrase}',
      );
    } on TimeoutException {
      return SyncResult(success: false, message: 'Connection timed out');
    } catch (e) {
      return SyncResult(success: false, message: e.toString());
    }
  }

  Future<SyncResult> _testLocalFolder() async {
    final dir = Directory(config.localFolderPath);
    if (await dir.exists()) {
      return SyncResult(success: true, message: 'Folder exists');
    }
    return SyncResult(success: false, message: 'Folder not found');
  }

  // ══════════════════════════════════════════════════════════
  // Sync Operations
  // ══════════════════════════════════════════════════════════

  Future<SyncResult> syncNow() async {
    if (!config.isConfigured) {
      return SyncResult(success: false, message: 'Not configured');
    }

    status = SyncStatus.syncing;
    _notify();

    try {
      final result = switch (config.backend) {
        SyncBackend.webdav => await _syncWebdav(),
        SyncBackend.localFolder => await _syncLocalFolder(),
      };

      lastResult = result;
      status = result.success ? SyncStatus.success : SyncStatus.failed;
      _notify();
      return result;
    } catch (e) {
      final result = SyncResult(success: false, message: e.toString());
      lastResult = result;
      status = SyncStatus.failed;
      _notify();
      return result;
    }
  }

  Future<SyncResult> syncReDownload() async {
    if (!config.isConfigured) {
      return SyncResult(success: false, message: 'Not configured');
    }

    status = SyncStatus.syncing;
    _notify();

    try {
      final result = switch (config.backend) {
        SyncBackend.webdav => await _webdavDownloadAll(),
        SyncBackend.localFolder => await _localDownloadAll(),
      };

      lastResult = result;
      status = result.success ? SyncStatus.success : SyncStatus.failed;
      _notify();
      return result;
    } catch (e) {
      final result = SyncResult(success: false, message: e.toString());
      lastResult = result;
      status = SyncStatus.failed;
      _notify();
      return result;
    }
  }

  // ══════════════════════════════════════════════════════════
  // WebDAV Implementation
  // ══════════════════════════════════════════════════════════

  void _setAuth(HttpClientRequest req) {
    final auth = base64.encode(
      utf8.encode('${config.webdavUsername}:${config.webdavPassword}'),
    );
    req.headers.set('Authorization', 'Basic $auth');
  }

  /// Join a base WebDAV URL and a relative path without mangling the
  /// `https://` part. Never call `replaceAll(RegExp(r'/+'), '/')` on the
  /// whole URL — it collapses `https://` to `https:/`.
  String _joinWebdavUrl(String baseUrl, String relPart) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final part = relPart.startsWith('/') ? relPart.substring(1) : relPart;
    return '$base$part';
  }

  static const _kWebdavStateKey = 'sync_webdav_file_state';

  /// Loads the last-known uploaded file states: relPath -> [size, modifiedMs].
  Future<Map<String, List<int>>> _loadWebdavState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kWebdavStateKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final state = <String, List<int>>{};
      decoded.forEach((key, value) {
        if (key is String && value is List && value.length == 2) {
          state[key] = [
            (value[0] as num).toInt(),
            (value[1] as num).toInt(),
          ];
        }
      });
      return state;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveWebdavState(Map<String, List<int>> state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kWebdavStateKey, jsonEncode(state));
  }

  /// Upload local files to WebDAV, skipping files whose size and modified
  /// time match the last successful upload state.
  Future<SyncResult> _syncWebdav() async {
    final localDir = Directory(_profilePath);
    if (!await localDir.exists()) {
      return SyncResult(success: false, message: 'Local profile folder not found');
    }

    final previousState = await _loadWebdavState();
    final nextState = <String, List<int>>{};
    final failedPaths = <String>[];

    int uploaded = 0;
    int failed = 0;
    int unchanged = 0;
    final files = await localDir
        .list(recursive: true)
        .where((e) => e is File && !e.path.contains('tts_cache'))
        .toList();

    for (final entity in files) {
      if (entity is! File) continue;

      final relPath = entity.path
          .substring(_profilePath.length)
          .replaceAll('\\', '/');

      try {
        final stat = await entity.stat();
        final current = [
          stat.size,
          stat.modified.millisecondsSinceEpoch,
        ];
        final previous = previousState[relPath];

        // A file is re-uploaded when it's new, its size changed, or its
        // modified time changed (covers session files updated after chat).
        final needsUpload = previous == null ||
            previous.length != 2 ||
            previous[0] != current[0] ||
            previous[1] != current[1];
        if (!needsUpload) {
          unchanged++;
          nextState[relPath] = previous;
          continue;
        }

        final relSegments = relPath
            .split('/')
            .where((s) => s.isNotEmpty)
            .toList();

        // Create every parent collection that doesn't exist yet, from the
        // WebDAV root down to the file's direct parent directory.
        var currentDir = config.webdavUrl;
        for (int i = 0; i < relSegments.length - 1; i++) {
          currentDir = _joinWebdavUrl(currentDir, relSegments[i]);
          await _webdavMkcol(currentDir);
        }

        // Upload
        final remoteUrl = relSegments.length == 1
            ? _joinWebdavUrl(config.webdavUrl, relSegments.first)
            : _joinWebdavUrl(currentDir, relSegments.last);
        final uri = Uri.parse(remoteUrl);
        print('[Sync] PUT $uri');
        final req = await _client.putUrl(uri).timeout(const Duration(seconds: 30));
        _setAuth(req);
        req.headers.set('Content-Type', 'application/octet-stream');
        req.add(await entity.readAsBytes());
        final resp = await req.close().timeout(const Duration(minutes: 10));
        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          uploaded++;
          nextState[relPath] = current;
          print('[Sync] OK ${resp.statusCode} $uri');
        } else {
          failed++;
          failedPaths.add('$relPath -> HTTP ${resp.statusCode}');
          print('[Sync] FAILED HTTP ${resp.statusCode} $uri');
        }
      } on TimeoutException catch (e) {
        failed++;
        failedPaths.add('$relPath -> timeout');
        print('[Sync] TIMEOUT $relPath: $e');
      } catch (e) {
        failed++;
        failedPaths.add('$relPath -> $e');
        print('[Sync] ERROR $relPath: $e');
      }
    }

    await _saveWebdavState(nextState);

    if (files.isEmpty) {
      return SyncResult(success: true, message: 'No files to upload');
    }

    if (failed == 0 && uploaded == 0) {
      return SyncResult(
        success: true,
        message: 'No changes: $unchanged files already in sync',
      );
    }

    return SyncResult(
      success: failed == 0,
      message: 'Uploaded $uploaded, $unchanged unchanged, $failed failed'
          '${failedPaths.isNotEmpty ? ' (${failedPaths.take(5).join('; ')})' : ''}',
      filesUploaded: uploaded,
    );
  }

  Future<void> _webdavMkcol(String url) async {
    try {
      final uri = Uri.parse(url);
      final req = await _client.openUrl('MKCOL', uri);
      _setAuth(req);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      // 405 Method Not Allowed = directory already exists, that's fine
    } on TimeoutException {
      // Silently ignore — directory probably exists
    } catch (_) {
      // Silently ignore
    }
  }

  /// Download all remote files (re-download).
  Future<SyncResult> _webdavDownloadAll() async {
    int downloaded = 0;

    try {
      await _webdavDownloadRecursive(config.webdavUrl, '', downloaded);
      return SyncResult(
        success: true,
        message: 'Downloaded $downloaded files',
        filesDownloaded: downloaded,
      );
    } catch (e) {
      return SyncResult(success: false, message: e.toString());
    }
  }

  Future<void> _webdavDownloadRecursive(
    String baseUrl, String relPath, int downloaded) async {
    final url = _joinWebdavUrl(baseUrl, relPath);
    final uri = Uri.parse(url);

    final req = await _client.openUrl('PROPFIND', uri);
    req.headers.set('Depth', '1');
    _setAuth(req);
    final resp = await req.close().timeout(const Duration(seconds: 30));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      final body = await resp.transform(utf8.decoder).join();
      // Simple XML parsing for WebDAV response
      final hrefs = _parseWebdavHrefs(body);
      for (final href in hrefs) {
        if (href == '/' || href == '/$relPath' || href.endsWith('/')) continue;
        final remoteUri = Uri.parse('$baseUrl$href');
        final localPath = '$_profilePath${href.replaceAll('/', '\\')}';

        // Download file
        try {
          final getReq = await _client.getUrl(remoteUri);
          _setAuth(getReq);
          final getResp = await getReq.close().timeout(const Duration(seconds: 30));
          if (getResp.statusCode >= 200 && getResp.statusCode < 300) {
            final bytes = await getResp.toList();
            final file = File(localPath);
            await file.parent.create(recursive: true);
            final sink = file.openWrite();
            for (final chunk in bytes) {
              sink.add(chunk);
            }
            await sink.close();
            downloaded++;
          }
        } catch (_) {}
      }
    }
  }

  List<String> _parseWebdavHrefs(String xml) {
    final hrefs = <String>[];
    final regex = RegExp(r'<[Dd]:?href>(.*?)</[Dd]:?href>');
    for (final match in regex.allMatches(xml)) {
      final href = match.group(1) ?? '';
      if (href.isNotEmpty) {
        // Decode XML entities
        hrefs.add(href
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'"));
      }
    }
    return hrefs;
  }

  // ══════════════════════════════════════════════════════════
  // Local Folder Implementation
  // ══════════════════════════════════════════════════════════

  Future<SyncResult> _syncLocalFolder() async {
    final src = Directory(_profilePath);
    final dst = Directory(config.localFolderPath);
    if (!await src.exists()) {
      return SyncResult(success: false, message: 'Source folder not found');
    }

    final files = await src.list(recursive: true).where((e) => e is File).toList();
    int copied = 0;
    for (final entity in files) {
      if (entity is! File) continue;
      try {
        final relPath = entity.path.substring(_profilePath.length);
        final destPath = '${config.localFolderPath}$relPath';
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await entity.copy(destPath);
        copied++;
      } catch (_) {}
    }

    return SyncResult(
      success: true,
      message: 'Copied $copied files',
      filesUploaded: copied,
    );
  }

  Future<SyncResult> _localDownloadAll() async {
    final src = Directory(config.localFolderPath);
    final dst = Directory(_profilePath);
    if (!await src.exists()) {
      return SyncResult(success: false, message: 'Remote folder not found');
    }

    final files = await src.list(recursive: true).where((e) => e is File).toList();
    int copied = 0;
    for (final entity in files) {
      if (entity is! File) continue;
      try {
        final relPath = entity.path.substring(config.localFolderPath.length);
        final destPath = '$_profilePath$relPath';
        final destFile = File(destPath);
        await destFile.parent.create(recursive: true);
        await entity.copy(destPath);
        copied++;
      } catch (_) {}
    }

    return SyncResult(
      success: true,
      message: 'Copied $copied files',
      filesDownloaded: copied,
    );
  }

  // ══════════════════════════════════════════════════════════
  // Cleanup
  // ══════════════════════════════════════════════════════════

  void dispose() {
    stopAutoSync();
    _client.close();
  }
}
