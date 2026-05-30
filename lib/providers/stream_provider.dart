import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bilibili_chat_service.dart';

/// Setlist节点类型 (1:1对应LAV2的NodeRegistry)
enum StreamNodeType {
  systemPrompt,   // 设置系统提示词
  promptedResponse, // AI根据提示词回复
  chat,           // 聊天模式（持续N分钟读取弹幕并回复）
  sing,           // 唱歌模式（播放音频）
}

/// Setlist节点定义
class StreamNodeDefinition {
  final StreamNodeType type;
  final String name;
  final Map<String, dynamic> defaultSettings;
  final Map<String, Map<String, dynamic>> presets;

  const StreamNodeDefinition({
    required this.type,
    required this.name,
    required this.defaultSettings,
    this.presets = const {},
  });

  static final Map<StreamNodeType, StreamNodeDefinition> registry = {
    StreamNodeType.systemPrompt: StreamNodeDefinition(
      type: StreamNodeType.systemPrompt,
      name: '系统提示词',
      defaultSettings: {'systemPrompt': ''},
      presets: {
        '默认直播': {
          'systemPrompt': '你正在Bilibili进行直播，请用活泼热情的语气和观众互动。回复要简洁生动，适当使用语气词。'
        },
        '杂谈模式': {
          'systemPrompt': '你正在和观众闲聊。请放松自然地聊天，可以分享日常趣事，回答观众问题。'
        },
        '歌回模式': {
          'systemPrompt': '你正在进行唱歌直播。每唱完一首歌后和观众互动，感谢礼物，接受点歌。'
        },
      },
    ),
    StreamNodeType.promptedResponse: StreamNodeDefinition(
      type: StreamNodeType.promptedResponse,
      name: 'AI回复',
      defaultSettings: {'prompt': ''},
      presets: {
        '开场白': {'prompt': '请用热情的语气做一个直播开场白，欢迎观众进入直播间。'},
        '结束语': {'prompt': '请用温暖感性的语气做直播结束语，感谢观众陪伴。'},
        '自我介绍': {'prompt': '请用可爱的语气做一个简短的自我介绍。'},
        '感谢礼物': {'prompt': '刚才有观众送出了礼物，请表达感谢。'},
      },
    ),
    StreamNodeType.chat: StreamNodeDefinition(
      type: StreamNodeType.chat,
      name: '聊天互动',
      defaultSettings: {'duration': 5},
      presets: {
        '短互动': {'duration': 3},
        '长互动': {'duration': 10},
      },
    ),
    StreamNodeType.sing: StreamNodeDefinition(
      type: StreamNodeType.sing,
      name: '唱歌',
      defaultSettings: {'songName': '', 'songPath': ''},
      presets: {},
    ),
  };
}

/// Setlist中的一个节点实例
class StreamSetlistItem {
  StreamNodeType nodeType;
  Map<String, dynamic> settings;

  StreamSetlistItem({
    required this.nodeType,
    Map<String, dynamic>? settings,
  }) : settings = settings ?? Map<String, dynamic>.from(
            StreamNodeDefinition.registry[nodeType]?.defaultSettings ?? {});

  StreamNodeDefinition? get nodeDef => StreamNodeDefinition.registry[nodeType];

  Map<String, dynamic> toJson() => {
        'nodeType': nodeType.name,
        'settings': settings,
      };

  factory StreamSetlistItem.fromJson(Map<String, dynamic> json) {
    final type = StreamNodeType.values.firstWhere(
      (t) => t.name == json['nodeType'],
      orElse: () => StreamNodeType.chat,
    );
    return StreamSetlistItem(
      nodeType: type,
      settings: Map<String, dynamic>.from(json['settings'] ?? {}),
    );
  }
}

/// 直播状态管理Provider
/// 管理Bilibili连接、弹幕收集、Setlist执行、AI自动回复
class LiveStreamProvider extends ChangeNotifier {
  final BilibiliChatService _chatService = BilibiliChatService();

  // ── 连接状态 ──
  String _roomId = '';
  BilibiliLiveStatusType _status = BilibiliLiveStatusType.disconnected;
  String _statusMessage = '';
  int _popularity = 0;

  // ── 弹幕消息 ──
  final List<BilibiliDanmaku> _messages = [];
  static const int _maxMessages = 200;

  // ── AI自动回复 ──
  bool _autoReply = true;
  int _replyInterval = 10; // 收集N秒弹幕后再触发一次AI回复
  Timer? _replyTimer;
  final List<String> _pendingMessages = []; // 积累的弹幕文本

  // ── Setlist ──
  final List<StreamSetlistItem> _setlist = [];
  bool _isSetlistRunning = false;
  int _currentNodeIndex = -1;
  Timer? _setlistTimer;

  // ── 回调 ──
  void Function(String message)? onAIResponse; // 由外部注入

  // ── Stream subscriptions ──
  StreamSubscription<BilibiliDanmaku>? _msgSub;
  StreamSubscription<BilibiliLiveStatus>? _statusSub;

  LiveStreamProvider() {
    _statusSub = _chatService.status.listen((s) {
      _status = s.type;
      if (s.message != null) _statusMessage = s.message!;
      if (s.popularity != null) _popularity = s.popularity!;
      notifyListeners();
    });

    _msgSub = _chatService.messages.listen((msg) {
      _messages.insert(0, msg);
      if (_messages.length > _maxMessages) {
        _messages.removeRange(_maxMessages, _messages.length);
      }

      // 如果开启自动回复，收集弹幕
      if (_autoReply && _isConnected) {
        _pendingMessages.add(msg.toAIFormat());
      }

      notifyListeners();
    });
  }

  // ── Getters ──
  String get roomId => _roomId;
  BilibiliLiveStatusType get status => _status;
  String get statusMessage => _statusMessage;
  int get popularity => _popularity;
  bool get _isConnected => _status == BilibiliLiveStatusType.connected;
  bool get isConnected => _isConnected;
  List<BilibiliDanmaku> get messages => List.unmodifiable(_messages);
  bool get autoReply => _autoReply;
  int get replyInterval => _replyInterval;
  List<StreamSetlistItem> get setlist => List.unmodifiable(_setlist);
  bool get isSetlistRunning => _isSetlistRunning;
  int get currentNodeIndex => _currentNodeIndex;

  /// 获取当前正在执行的节点
  StreamSetlistItem? get currentNode {
    if (_currentNodeIndex >= 0 && _currentNodeIndex < _setlist.length) {
      return _setlist[_currentNodeIndex];
    }
    return null;
  }

  // ── Setters ──
  set autoReply(bool v) {
    _autoReply = v;
    if (!v) _pendingMessages.clear();
    notifyListeners();
  }

  set replyInterval(int v) {
    _replyInterval = v.clamp(5, 120);
    notifyListeners();
  }

  // ── 连接管理 ──

  /// 连接到Bilibili直播间
  Future<bool> connect(String roomId) async {
    if (roomId.trim().isEmpty) return false;
    final id = int.tryParse(roomId.trim());
    if (id == null) return false;

    _roomId = roomId.trim();
    await _chatService.connect(id);

    // 保存房间号
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stream_room_id', _roomId);

    // 启动自动回复定时器
    if (_autoReply) _startReplyTimer();

    notifyListeners();
    return true;
  }

  /// 断开直播间连接
  Future<void> disconnect() async {
    _stopReplyTimer();
    _stopSetlist();
    await _chatService.disconnect();
    _status = BilibiliLiveStatusType.disconnected;
    _pendingMessages.clear();
    notifyListeners();
  }

  /// 从SharedPreferences恢复上次的房间号
  Future<String> loadSavedRoomId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _roomId = prefs.getString('stream_room_id') ?? '';
      notifyListeners();
    } catch (_) {}
    return _roomId;
  }

  // ── 自动回复 ──

  void _startReplyTimer() {
    _stopReplyTimer();
    _replyTimer = Timer.periodic(Duration(seconds: _replyInterval), (_) {
      _flushPendingMessages();
    });
  }

  void _stopReplyTimer() {
    _replyTimer?.cancel();
    _replyTimer = null;
  }

  void _flushPendingMessages() {
    if (_pendingMessages.isEmpty || onAIResponse == null) return;
    final combined = _pendingMessages.take(10).join('\n');
    _pendingMessages.clear();

    // 组装直播上下文prompt
    final prompt =
        '你正在Bilibili进行直播。以下是观众的最新弹幕，请用自然活泼的语气回应他们（2-4句话即可）：\n\n$combined';
    onAIResponse!(prompt);
  }

  /// 手动触发AI回复（带自定义prompt）
  void triggerReply(String prompt) {
    if (onAIResponse != null) {
      onAIResponse!(prompt);
    }
  }

  // ── Setlist管理 ──

  /// 添加节点到setlist
  void addSetlistNode(StreamNodeType type) {
    _setlist.add(StreamSetlistItem(nodeType: type));
    notifyListeners();
  }

  /// 删除节点
  void removeSetlistNode(int index) {
    if (index >= 0 && index < _setlist.length) {
      _setlist.removeAt(index);
      notifyListeners();
    }
  }

  /// 移动节点位置
  void moveSetlistNode(int index, int direction) {
    final target = index + direction;
    if (target >= 0 && target < _setlist.length) {
      final item = _setlist.removeAt(index);
      _setlist.insert(target, item);
      notifyListeners();
    }
  }

  /// 更新节点设置
  void updateNodeSettings(int index, StreamSetlistItem updated) {
    if (index >= 0 && index < _setlist.length) {
      _setlist[index] = updated;
      notifyListeners();
    }
  }

  /// 加载setlist（从SharedPreferences）
  Future<void> loadSetlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('stream_setlist');
      if (json != null) {
        // 简单JSON存储（仅存nodeType名称列表）
        final types = json.split(',');
        _setlist.clear();
        for (final t in types) {
          final type = StreamNodeType.values.firstWhere(
            (e) => e.name == t,
            orElse: () => StreamNodeType.chat,
          );
          _setlist.add(StreamSetlistItem(nodeType: type));
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 保存setlist
  Future<void> saveSetlist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final types = _setlist.map((e) => e.nodeType.name).join(',');
      await prefs.setString('stream_setlist', types);
    } catch (_) {}
  }

  /// 启动setlist执行
  void startSetlist() {
    if (_setlist.isEmpty || _isSetlistRunning) return;
    _isSetlistRunning = true;
    _currentNodeIndex = 0;
    _executeCurrentNode();
    notifyListeners();
  }

  /// 停止setlist
  void stopSetlist() {
    _stopSetlist();
  }

  void _stopSetlist() {
    _isSetlistRunning = false;
    _currentNodeIndex = -1;
    _setlistTimer?.cancel();
    _setlistTimer = null;
    notifyListeners();
  }

  void _executeCurrentNode() {
    if (!_isSetlistRunning ||
        _currentNodeIndex < 0 ||
        _currentNodeIndex >= _setlist.length) {
      _stopSetlist();
      return;
    }

    final node = _setlist[_currentNodeIndex];
    final def = node.nodeDef;
    if (def == null) {
      _advanceToNextNode();
      return;
    }

    switch (def.type) {
      case StreamNodeType.systemPrompt:
        // 设置系统提示词 → 立即完成
        final prompt = node.settings['systemPrompt'] as String? ?? '';
        if (prompt.isNotEmpty && onAIResponse != null) {
          // 通过特殊的内部指令来设置system prompt
          onAIResponse!('__SYSTEM_PROMPT__:$prompt');
        }
        _advanceToNextNode();
        break;

      case StreamNodeType.promptedResponse:
        // AI回复指定提示词
        final prompt = node.settings['prompt'] as String? ?? '';
        if (prompt.isNotEmpty && onAIResponse != null) {
          onAIResponse!(prompt);
        }
        // 等待一会再继续下一个节点
        _setlistTimer = Timer(const Duration(seconds: 8), _advanceToNextNode);
        break;

      case StreamNodeType.chat:
        // 聊天模式：持续N分钟
        final duration =
            (node.settings['duration'] as num?)?.toInt() ?? 5;
        // 确保自动回复开启
        _autoReply = true;
        _startReplyTimer();
        // N分钟后继续下一个节点
        _setlistTimer = Timer(
            Duration(minutes: duration), _advanceToNextNode);
        break;

      case StreamNodeType.sing:
        // 唱歌模式 → 标记为等待（实际音频播放由外部处理）
        _advanceToNextNode();
        break;
    }

    notifyListeners();
  }

  void _advanceToNextNode() {
    _currentNodeIndex++;
    if (_currentNodeIndex >= _setlist.length) {
      _stopSetlist();
    } else {
      _executeCurrentNode();
    }
  }

  @override
  void dispose() {
    _stopReplyTimer();
    _stopSetlist();
    _msgSub?.cancel();
    _statusSub?.cancel();
    _chatService.dispose();
    super.dispose();
  }
}
