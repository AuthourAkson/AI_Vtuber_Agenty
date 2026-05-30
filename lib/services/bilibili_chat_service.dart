import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Bilibili直播弹幕客户端 (HTTP轮询方式)
/// 不需要token，每3秒轮询一次弹幕API
class BilibiliChatService {
  Timer? _pollTimer;
  bool _running = false;
  int _roomId = 0;
  final HttpClient _client = HttpClient();
  final Set<String> _seenIds = {}; // 去重：已处理的弹幕ID

  final StreamController<BilibiliDanmaku> _messageController =
      StreamController<BilibiliDanmaku>.broadcast();
  final StreamController<BilibiliLiveStatus> _statusController =
      StreamController<BilibiliLiveStatus>.broadcast();

  Stream<BilibiliDanmaku> get messages => _messageController.stream;
  Stream<BilibiliLiveStatus> get status => _statusController.stream;
  bool get isRunning => _running;
  int get roomId => _roomId;

  static Future<int> getRealRoomId(int shortId) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          'https://api.live.bilibili.com/room/v1/Room/room_init?id=$shortId'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] == 0) {
        client.close();
        return data['data']['room_id'] as int;
      }
      client.close();
    } catch (_) {}
    return shortId;
  }

  Future<void> connect(int roomId) async {
    if (_running) await disconnect();
    _roomId = roomId;
    _statusController.add(BilibiliLiveStatus.connecting);

    try {
      final realId = roomId < 10000 ? await getRealRoomId(roomId) : roomId;
      _roomId = realId;
      _running = true;
      _statusController.add(BilibiliLiveStatus.connected);

      // 立即拉一次弹幕
      await _pollDanmaku();

      // 每3秒轮询一次
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _pollDanmaku();
      });
    } catch (e) {
      _statusController
          .add(BilibiliLiveStatus.error('连接失败: $e'));
      _cleanup();
    }
  }

  Future<void> _pollDanmaku() async {
    if (!_running) return;
    try {
      final uri = Uri.parse(
          'https://api.live.bilibili.com/xlive/web-room/v1/dM/gethistory?roomid=$_roomId');
      final request = await _client.getUrl(uri);
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
      request.headers.set('Referer', 'https://live.bilibili.com/');
      final response = await request.close();
      if (response.statusCode != 200) return;

      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      if (data['code'] != 0) return;

      // data.data.room 包含弹幕列表
      final roomData = data['data']?['room'] as List?;
      if (roomData == null) return;

      for (final msg in roomData) {
        if (msg is! Map<String, dynamic>) continue;

        // 去重：用id_str跳过已处理过的弹幕
        final msgId = msg['id_str']?.toString() ?? '';
        if (msgId.isNotEmpty && _seenIds.contains(msgId)) continue;
        if (msgId.isNotEmpty) {
          _seenIds.add(msgId);
          // 防止内存无限增长，保留最近1000条
          if (_seenIds.length > 1000) {
            _seenIds.remove(_seenIds.first);
          }
        }

        final text = msg['text']?.toString() ?? '';
        final uname = msg['nickname']?.toString() ?? '';
        final uid = msg['uid'] ?? 0;

        if (text.isEmpty) continue;

        _messageController.add(BilibiliDanmaku(
          type: BilibiliDanmakuType.chat,
          uid: uid is int ? uid : 0,
          uname: uname,
          content: text,
          timestamp: DateTime.now(),
        ));
      }
    } catch (e) {
      // 轮询失败静默跳过
    }
  }

  Future<void> disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    _running = false;
    _statusController.add(BilibiliLiveStatus.disconnected);
  }

  void dispose() {
    disconnect();
    _client.close();
    _messageController.close();
    _statusController.close();
  }

  void _cleanup() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _running = false;
  }
}

// ── Models ──

enum BilibiliDanmakuType { chat, gift, superChat, guard }

class BilibiliDanmaku {
  final BilibiliDanmakuType type;
  final int uid;
  final String uname;
  final String content;
  final DateTime timestamp;

  BilibiliDanmaku({
    required this.type,
    required this.uid,
    required this.uname,
    required this.content,
    required this.timestamp,
  });

  String get displayText {
    switch (type) {
      case BilibiliDanmakuType.gift:
        return '\u{1F381} $uname $content';
      case BilibiliDanmakuType.superChat:
        return '\u{1F31F} $uname: $content';
      case BilibiliDanmakuType.guard:
        return '\u{1F6E1} $uname $content';
      case BilibiliDanmakuType.chat:
        return '$uname: $content';
    }
  }

  String toAIFormat() => '\u3010\u89c2\u4f17 $uname\u3011$content';
}

class BilibiliLiveStatus {
  final BilibiliLiveStatusType type;
  final String? message;
  final int? popularity;

  BilibiliLiveStatus._(this.type, {this.message, this.popularity});

  static final connecting =
      BilibiliLiveStatus._(BilibiliLiveStatusType.connecting);
  static final connected =
      BilibiliLiveStatus._(BilibiliLiveStatusType.connected);
  static final disconnected =
      BilibiliLiveStatus._(BilibiliLiveStatusType.disconnected);
  static BilibiliLiveStatus error(String msg) =>
      BilibiliLiveStatus._(BilibiliLiveStatusType.error, message: msg);
  static BilibiliLiveStatus popularityUpdate(int pop) =>
      BilibiliLiveStatus._(BilibiliLiveStatusType.connected, popularity: pop);
}

enum BilibiliLiveStatusType { connecting, connected, disconnected, error }
