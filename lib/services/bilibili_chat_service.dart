import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Bilibili直播弹幕WebSocket客户端
/// 
/// 协议说明：
/// - 连接 wss://broadcastlv.chat.bilibili.com/sub
/// - 发送 JOIN_ROOM (op=7) 握手包
/// - 每30秒发送 HEARTBEAT (op=2) 保活
/// - 收到 op=5 的消息 → zlib解压 → 解析DANMU_MSG等cmd
///
/// 参考：https://github.com/lovelyyoshino/Bilibili-Live-API
class BilibiliChatService {
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  bool _running = false;
  int _roomId = 0;

  final StreamController<BilibiliDanmaku> _messageController =
      StreamController<BilibiliDanmaku>.broadcast();
  final StreamController<BilibiliLiveStatus> _statusController =
      StreamController<BilibiliLiveStatus>.broadcast();

  /// 弹幕消息流
  Stream<BilibiliDanmaku> get messages => _messageController.stream;

  /// 连接状态流
  Stream<BilibiliLiveStatus> get status => _statusController.stream;

  bool get isRunning => _running;
  int get roomId => _roomId;

  // ── Bilibili Binary Protocol Constants ──
  static const int _opHeartbeat = 2;
  static const int _opHeartbeatReply = 3;
  static const int _opServerNotify = 5;
  static const int _opJoinRoom = 7;
  static const int _opJoinReply = 8;

  static const int _headerLen = 16;
  static const int _protoVerPlain = 0;
  static const int _protoVerHeartbeat = 1;
  static const int _protoVerZlib = 2;
  static const int _protoVerBrotli = 3;

  /// 通过短房间号获取真实房间号
  static Future<int> getRealRoomId(int shortId) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          'https://api.live.bilibili.com/room/v1/Room/room_init?id=$shortId'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] == 0) {
        return data['data']['room_id'] as int;
      }
    } catch (_) {}
    return shortId; // 如果失败，返回原ID（可能本身就是真实ID）
  }

  /// 获取直播间信息（标题、状态等）
  static Future<Map<String, dynamic>?> getRoomInfo(int roomId) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(
          'https://api.live.bilibili.com/xlive/web-room/v1/index/getInfoByRoom?room_id=$roomId'));
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final data = jsonDecode(body);
      if (data['code'] == 0) {
        final info = data['data']['room_info'];
        return {
          'title': info['title'] ?? '',
          'live_status': info['live_status'] ?? 0, // 0=未开播, 1=直播中, 2=轮播中
          'online': info['online'] ?? 0,
          'uid': info['uid'] ?? 0,
          'cover': info['cover'] ?? '',
        };
      }
    } catch (_) {}
    return null;
  }

  /// 连接到直播间并开始接收弹幕
  Future<void> connect(int roomId) async {
    if (_running) await disconnect();

    _roomId = roomId;
    _statusController.add(BilibiliLiveStatus.connecting);

    try {
      // 如果是短ID，先获取真实ID
      final realId = roomId < 10000 ? await getRealRoomId(roomId) : roomId;
      _roomId = realId;

      final wsUrl = Uri.parse('wss://broadcastlv.chat.bilibili.com:443/sub');
      _channel = WebSocketChannel.connect(wsUrl);
      await _channel!.ready;

      _running = true;
      _statusController.add(BilibiliLiveStatus.connected);

      // 发送JOIN_ROOM握手包
      _sendJoinRoom(realId);

      // 启动心跳定时器 (30秒间隔)
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _sendHeartbeat();
      });

      // 监听消息
      _channel!.stream.listen(
        (data) {
          _handleBinaryMessage(data as Uint8List);
        },
        onError: (error) {
          _statusController
              .add(BilibiliLiveStatus.error('WebSocket error: $error'));
          _cleanup();
        },
        onDone: () {
          _statusController.add(BilibiliLiveStatus.disconnected);
          _cleanup();
        },
      );
    } catch (e) {
      _statusController.add(BilibiliLiveStatus.error('Connection failed: $e'));
      _cleanup();
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _running = false;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _statusController.add(BilibiliLiveStatus.disconnected);
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _messageController.close();
    _statusController.close();
  }

  // ── Private: Binary Protocol ──

  /// 发送JOIN_ROOM包 (op=7)
  void _sendJoinRoom(int roomId) {
    final body = utf8.encode(jsonEncode({
      'uid': 0,
      'roomid': roomId,
      'protover': _protoVerBrotli, // 优先brotli，回退zlib
      'platform': 'web',
      'type': 2,
      'key': '', // 不需要key也能收到弹幕
    }));
    _sendPacket(_opJoinRoom, body);
  }

  /// 发送心跳包 (op=2)
  void _sendHeartbeat() {
    if (!_running || _channel == null) return;
    // 心跳包body: "[object Object]" (用于protover=1的心跳)
    _sendPacket(_opHeartbeat, utf8.encode('[object Object]'));
  }

  /// 发送二进制数据包
  void _sendPacket(int operation, List<int> body) {
    if (_channel == null) return;
    final totalLen = _headerLen + body.length;
    final packet = ByteData(totalLen)
      ..setUint32(0, totalLen, Endian.big) // total_len
      ..setUint16(4, _headerLen, Endian.big) // header_len
      ..setUint16(6, _protoVerHeartbeat, Endian.big) // proto_ver (1 for heartbeat)
      ..setUint32(8, operation, Endian.big) // op
      ..setUint32(12, 1, Endian.big); // seq

    final bytes = Uint8List(totalLen);
    bytes.setRange(0, _headerLen, packet.buffer.asUint8List());
    bytes.setRange(_headerLen, totalLen, body);
    _channel!.sink.add(bytes);
  }

  /// 处理收到的二进制消息
  void _handleBinaryMessage(Uint8List data) {
    if (data.length < _headerLen) return;

    final view = ByteData.sublistView(data);
    final totalLen = view.getUint32(0, Endian.big);
    final headerLen = view.getUint16(4, Endian.big);
    final protoVer = view.getUint16(6, Endian.big);
    final op = view.getUint32(8, Endian.big);
    // seq = view.getUint32(12, Endian.big);

    if (totalLen <= headerLen) return;

    switch (op) {
      case _opHeartbeatReply: // op=3: 心跳回复（人气值）
        final popularity = _readPopularity(data, headerLen);
        if (popularity != null) {
          _statusController
              .add(BilibiliLiveStatus.popularityUpdate(popularity));
        }
        break;

      case _opServerNotify: // op=5: 服务器消息
        _handleServerNotify(data, headerLen, totalLen, protoVer);
        break;

      case _opJoinReply: // op=8: 进房回复
        // 连接成功
        break;
    }
  }

  /// 读取人气值 (op=3)
  int? _readPopularity(Uint8List data, int headerLen) {
    try {
      final body = data.sublist(headerLen);
      // body是JSON: {"code":0} 或直接是一个数字
      final str = utf8.decode(body);
      final json = jsonDecode(str);
      if (json is Map && json.containsKey('count')) {
        return json['count'] as int;
      }
      if (json is int) return json;
    } catch (_) {
      // body可能是原始数字
      try {
        final view = ByteData.sublistView(data, headerLen);
        return view.getUint32(0, Endian.big);
      } catch (_) {}
    }
    return null;
  }

  /// 处理服务器推送消息 (op=5)
  void _handleServerNotify(
      Uint8List data, int headerLen, int totalLen, int protoVer) {
    List<int> body = data.sublist(headerLen, totalLen);

    if (protoVer == _protoVerZlib || protoVer == _protoVerBrotli) {
      // zlib/brotli解压
      List<int> decompressed;
      if (protoVer == _protoVerBrotli) {
        // Bilibili现在主要用brotli，但也可能降级到zlib
        // brotli需要额外的包，先尝试zlib，失败则跳过
        decompressed = _tryZlibDecompress(body);
      } else {
        decompressed = _tryZlibDecompress(body);
      }
      if (decompressed.isEmpty) return;

      // 解压后的数据可能包含多个包
      _parseMultiPackets(Uint8List.fromList(decompressed));
    } else {
      // 未压缩的单个JSON消息
      _parseSinglePacket(Uint8List.fromList(body));
    }
  }

  /// 尝试zlib解压 (brotli在Flutter中需要额外包，先做zlib)
  List<int> _tryZlibDecompress(List<int> data) {
    try {
      final zlib = ZLibDecoder();
      return zlib.convert(data);
    } catch (_) {
      // 可能不是zlib压缩的
      return data;
    }
  }

  /// 解析解压后可能包含的多个包
  void _parseMultiPackets(Uint8List data) {
    int offset = 0;
    while (offset + _headerLen <= data.length) {
      final view = ByteData.sublistView(data, offset);
      final packetLen = view.getUint32(0, Endian.big);
      if (packetLen <= 0 || offset + packetLen > data.length) break;

      final bodyStart = offset + _headerLen;
      final bodyEnd = offset + packetLen;
      if (bodyStart < bodyEnd) {
        final body = data.sublist(bodyStart, bodyEnd);
        _parseSinglePacket(Uint8List.fromList(body));
      }
      offset += packetLen;
    }
  }

  /// 解析单个消息包body → 提取弹幕/礼物/SC等
  void _parseSinglePacket(Uint8List body) {
    try {
      final str = utf8.decode(body);
      final json = jsonDecode(str) as Map<String, dynamic>;

      final cmd = json['cmd'] as String? ?? '';

      switch (cmd) {
        case 'DANMU_MSG':
          // 弹幕消息
          // 结构: {"cmd":"DANMU_MSG","info":[[...], "弹幕文本", [uid, uname, ...], ...]}
          final info = json['info'];
          if (info is List && info.length >= 3) {
            final content = info[1]?.toString() ?? '';
            final userInfo = info[2];
            String uname = '未知用户';
            int uid = 0;
            if (userInfo is List && userInfo.length >= 2) {
              uname = userInfo[1]?.toString() ?? uname;
              uid = int.tryParse(userInfo[0]?.toString() ?? '0') ?? 0;
            }
            if (content.isNotEmpty) {
              _messageController.add(BilibiliDanmaku(
                type: BilibiliDanmakuType.chat,
                uid: uid,
                uname: uname,
                content: content,
                timestamp: DateTime.now(),
              ));
            }
          }
          break;

        case 'SEND_GIFT':
          // 礼物消息
          final data = json['data'] as Map<String, dynamic>?;
          if (data != null) {
            final giftName = data['giftName']?.toString() ?? '礼物';
            final uname = data['uname']?.toString() ?? '未知用户';
            final num = data['num'] ?? 1;
            _messageController.add(BilibiliDanmaku(
              type: BilibiliDanmakuType.gift,
              uid: 0,
              uname: uname,
              content: '送出 $num 个$giftName',
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'SUPER_CHAT_MESSAGE':
          // SC醒目留言
          final data = json['data'] as Map<String, dynamic>?;
          if (data != null) {
            final message = data['message']?.toString() ?? '';
            final uname = data['user_info']?['uname']?.toString() ?? '未知用户';
            final price = data['price'] ?? 0;
            _messageController.add(BilibiliDanmaku(
              type: BilibiliDanmakuType.superChat,
              uid: 0,
              uname: uname,
              content: '[¥$price] $message',
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'SUPER_CHAT_MESSAGE_JPN':
          // SC留言（日文版，同SUPER_CHAT_MESSAGE处理）
          final data = json['data'] as Map<String, dynamic>?;
          if (data != null) {
            final message = data['message']?.toString() ?? '';
            final uname = data['user_info']?['uname']?.toString() ?? '未知用户';
            final price = data['price'] ?? 0;
            _messageController.add(BilibiliDanmaku(
              type: BilibiliDanmakuType.superChat,
              uid: 0,
              uname: uname,
              content: '[¥$price] $message',
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'GUARD_BUY':
          // 上舰消息
          final data = json['data'] as Map<String, dynamic>?;
          if (data != null) {
            final uname = data['username']?.toString() ?? '未知用户';
            final guardLevel = data['guard_level'] ?? 0;
            final guardNames = ['', '总督', '提督', '舰长'];
            final guardName = (guardLevel < guardNames.length)
                ? guardNames[guardLevel as int]
                : '舰长';
            _messageController.add(BilibiliDanmaku(
              type: BilibiliDanmakuType.superChat,
              uid: 0,
              uname: uname,
              content: '开通了$guardName',
              timestamp: DateTime.now(),
            ));
          }
          break;

        case 'WELCOME':
        case 'WELCOME_GUARD':
          // 欢迎/进入房间消息 - 可忽略（太频繁）
          break;

        case 'INTERACT_WORD':
          // 进入房间
          break;

        default:
          // 未知类型，忽略
          break;
      }
    } catch (_) {
      // 解析失败，跳过
    }
  }

  void _cleanup() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _running = false;
    _channel = null;
  }
}

// ── Data Models ──

/// 弹幕消息类型
enum BilibiliDanmakuType {
  chat, // 普通弹幕
  gift, // 礼物
  superChat, // SC醒目留言
  guard, // 上舰
}

/// 弹幕消息
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

  /// 转换为可展示的文本
  String get displayText {
    switch (type) {
      case BilibiliDanmakuType.gift:
        return '🎁 $uname $content';
      case BilibiliDanmakuType.superChat:
        return '🌟 $uname: $content';
      case BilibiliDanmakuType.guard:
        return '🛡️ $uname $content';
      case BilibiliDanmakuType.chat:
        return '$uname: $content';
    }
  }

  /// 转为传给AI的格式
  String toAIFormat() => '【观众 $uname】$content';
}

/// 直播连接状态
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
