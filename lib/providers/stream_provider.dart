import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/bilibili_chat_service.dart';

/// AI回复模式
enum StreamReplyMode {
  /// 滑动窗口：3槽队列，一次处理一条，处理完从最新弹幕补位
  slidingWindow,

  /// 顺序回复：严格FIFO，一条一条按顺序回复
  sequential,
}

/// Setlist节点类型 (1:1对应LAV2的NodeRegistry)
enum StreamNodeType {
  systemPrompt, // 设置系统提示词
  promptedResponse, // AI根据提示词回复
  chat, // 聊天模式（持续N分钟读取弹幕并回复）
  sing, // 唱歌模式（播放音频）
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
          'systemPrompt': '你正在Bilibili进行直播，请用活泼热情的语气和观众互动。回复要简洁生动，适当使用语气词。',
        },
        '杂谈模式': {'systemPrompt': '你正在和观众闲聊。请放松自然地聊天，可以分享日常趣事，回答观众问题。'},
        '歌回模式': {'systemPrompt': '你正在进行唱歌直播。每唱完一首歌后和观众互动，感谢礼物，接受点歌。'},
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

  StreamSetlistItem({required this.nodeType, Map<String, dynamic>? settings})
    : settings =
          settings ??
          Map<String, dynamic>.from(
            StreamNodeDefinition.registry[nodeType]?.defaultSettings ?? {},
          );

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

  // ── AI忙碌锁 ──
  bool _isAiBusy = false;
  bool get isAiBusy => _isAiBusy;

  // ── 回复模式 ──
  StreamReplyMode _replyMode = StreamReplyMode.slidingWindow;
  static const int _maxWindowSize = 3;
  final List<String> _overflowMessages = [];

  StreamReplyMode get replyMode => _replyMode;

  set replyMode(StreamReplyMode v) {
    if (_replyMode == v) return;
    _replyMode = v;
    _pendingMessages.clear();
    _overflowMessages.clear();
    _saveReplyMode();
    notifyListeners();
  }

  // ── 编辑模式 ──
  bool _isEditMode = false;
  bool get isEditMode => _isEditMode;
  set isEditMode(bool v) {
    _isEditMode = v;
    notifyListeners();
  }

  // ── 回调 ──
  Future<void> Function(String message)? onAIResponse; // 由外部注入（异步，支持等待完成）

  /// 观众 @员工 / !agent 派活回调（Direction 2）。
  /// [targetName] 为从弹幕中解析出的员工名（可能为 null，表示用默认员工）。
  Future<void> Function(String? targetName, String taskText)? onAgentTask;

  /// Agent confirm 等待期间，普通弹幕会先交给此回调判断是否为选项答案。
  /// 返回 true 表示该弹幕被当作 confirm 答案消费掉，不再回复主页面 AI。
  Future<bool> Function(String message)? onConfirmChoice;

  bool _confirmWaitMode = false;
  bool get confirmWaitMode => _confirmWaitMode;
  set confirmWaitMode(bool v) {
    if (_confirmWaitMode == v) return;
    _confirmWaitMode = v;
    notifyListeners();
  }

  // ── Agent任务开关/默认员工 ──
  bool _agentTaskEnabled = true;
  String? _agentTaskDefaultEmployeeId;
  List<String> _agentTaskEmployeeNames = [];

  bool get agentTaskEnabled => _agentTaskEnabled;
  set agentTaskEnabled(bool v) {
    if (_agentTaskEnabled == v) return;
    _agentTaskEnabled = v;
    notifyListeners();
  }

  String? get agentTaskDefaultEmployeeId => _agentTaskDefaultEmployeeId;
  set agentTaskDefaultEmployeeId(String? id) {
    if (_agentTaskDefaultEmployeeId == id) return;
    _agentTaskDefaultEmployeeId = id;
    notifyListeners();
  }

  /// 员工名单（用于识别弹幕中的 `@员工名` 直接派活）。
  /// 由 StreamScreen 从 AgentManager 同步。
  List<String> get agentTaskEmployeeNames => _agentTaskEmployeeNames;
  set agentTaskEmployeeNames(List<String> names) {
    final normalized = names.map((n) => n.trim()).toList();
    if (identical(normalized, _agentTaskEmployeeNames)) return;
    if (_listEq(normalized, _agentTaskEmployeeNames)) return;
    _agentTaskEmployeeNames = normalized;
    notifyListeners();
  }

  bool _listEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].toLowerCase() != b[i].toLowerCase()) return false;
    }
    return true;
  }

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

      // 如果开启自动回复，按模式收集弹幕
      if (_autoReply && _isConnected) {
        final formatted = msg.toAIFormat();
        if (_replyMode == StreamReplyMode.slidingWindow) {
          if (_pendingMessages.length < _maxWindowSize) {
            _pendingMessages.add(formatted);
          } else {
            _overflowMessages.add(formatted);
          }
        } else {
          _pendingMessages.add(formatted);
        }
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
    _overflowMessages.clear();
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

  /// 加载保存的回复模式
  Future<void> loadReplyMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeName = prefs.getString('stream_reply_mode');
      if (modeName != null) {
        _replyMode = modeName == 'sequential'
            ? StreamReplyMode.sequential
            : StreamReplyMode.slidingWindow;
      }
    } catch (_) {}
  }

  Future<void> _saveReplyMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'stream_reply_mode',
        _replyMode == StreamReplyMode.sequential
            ? 'sequential'
            : 'slidingWindow',
      );
    } catch (_) {}
  }

  /// 发送测试弹幕
  void sendTestDanmaku() {
    addManualDanmaku('主播今天好可爱啊~', uname: '观众A');
    addManualDanmaku('能唱首歌吗？', uname: '观众B');
    addManualDanmaku('主播今天吃了什么好吃的', uname: '观众C');
    addManualDanmaku('哈哈哈这个表情绝了', uname: '观众D');
    addManualDanmaku('关注了关注了！', uname: '观众E');
    addManualDanmaku('主播会跳舞吗', uname: '观众F');
    addManualDanmaku('从首页推荐来的', uname: '观众G');
  }

  // ── 自动回复 ──

  void _startReplyTimer() {
    _stopReplyTimer();
    _replyTimer = Timer.periodic(Duration(seconds: _replyInterval), (_) {
      _tryFlushOne();
    });
  }

  void _stopReplyTimer() {
    _replyTimer?.cancel();
    _replyTimer = null;
  }

  /// 队列里有待处理消息时切换到快速轮询(1s)，处理完回到正常间隔
  void _startFastPoll() {
    _stopReplyTimer();
    _replyTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _tryFlushOne();
      if (_pendingMessages.isEmpty && _overflowMessages.isEmpty && !_isAiBusy) {
        _stopReplyTimer();
        _startReplyTimer(); // 队列空了，回到正常间隔
      }
    });
  }

  /// 尝试发送一条弹幕。有 _isAiBusy 保护，不会重复。
  /// 不递归、不 .then() 链、不在同一个函数里处理多条。
  void _tryFlushOne() {
    if (_pendingMessages.isEmpty) return;
    if (_isAiBusy) return;

    final msg = _pendingMessages.removeAt(0);
    final content = _danmakuContent(msg);
    final agentCmd = _parseAgentCommand(content);

    // Agent 指令类弹幕由 WenzAgent 管线消费，绝不透传给主页面聊天 AI，
    // 即使 Agent 任务开关关闭或桥接未就绪，也只丢弃而不落到主页面。
    if (agentCmd != null) {
      if (_agentTaskEnabled && onAgentTask != null) {
        _isAiBusy = true;
        notifyListeners();

        onAgentTask!(agentCmd.targetName, agentCmd.taskText)
            .then((_) => _afterAutoReplyHandled())
            .catchError((_) => _afterAutoReplyHandled());
      } else {
        print(
          '[Stream] Agent command dropped: enabled=$_agentTaskEnabled bridge=${onAgentTask != null}',
        );
        _afterAutoReplyHandled();
      }
      return;
    }

    // Agent confirm 等待期间，观众弹幕优先被当作选项答案。
    final confirmChoice = onConfirmChoice;
    if (_confirmWaitMode && confirmChoice != null) {
      _isAiBusy = true;
      notifyListeners();
      confirmChoice(content)
          .then((handled) {
            if (handled) {
              _afterAutoReplyHandled();
            } else {
              _isAiBusy = false;
              notifyListeners();
              _dispatchNormalAi(msg);
            }
          })
          .catchError((_) {
            _isAiBusy = false;
            notifyListeners();
            _dispatchNormalAi(msg);
          });
      return;
    }

    // 普通弹幕自动回复（走主页面聊天 AI）。
    _dispatchNormalAi(msg);
  }

  void _dispatchNormalAi(String msg) {
    if (onAIResponse == null) return;

    _isAiBusy = true;
    notifyListeners();

    final prompt = '你正在Bilibili进行直播。以下是观众的最新弹幕，请用自然活泼的语气回应（1-2句话即可）：\n\n$msg';

    onAIResponse!(prompt)
        .then((_) => _afterAutoReplyHandled())
        .catchError((_) => _afterAutoReplyHandled());
  }

  void _afterAutoReplyHandled() {
    _isAiBusy = false;
    if (_replyMode == StreamReplyMode.slidingWindow) {
      _refillSlidingWindow();
    }
    notifyListeners();
    if (_pendingMessages.isNotEmpty) {
      _startFastPoll();
    }
  }

  /// Strip the `【观众 xxx】` prefix from pending-message text.
  String _danmakuContent(String msg) {
    final idx = msg.lastIndexOf('】');
    if (idx >= 0 && idx + 1 < msg.length) return msg.substring(idx + 1).trim();
    return msg.trim();
  }

  /// Parse `@agent 任务` / `!agent @员工 任务` style danmaku commands.
  /// Returns null when the message is not an agent task command.
  ({String? targetName, String taskText})? _parseAgentCommand(String content) {
    String rest = '';
    if (content.startsWith('!agent') || content.startsWith('！agent')) {
      rest = content.substring(6).trim();
    }
    if (rest.isEmpty &&
        (content.startsWith('@agent') || content.startsWith('＠agent'))) {
      rest = content.substring(6).trim();
    }
    if (rest.isEmpty &&
        (content.startsWith('@员工') ||
            content.startsWith('!员工') ||
            content.startsWith('！员工'))) {
      rest = content.substring(3).trim();
      if (rest.isEmpty) return null;
    }

    // Direct mention: `@马甲其 任务内容`.
    // Only treated as an agent task when the name matches a WenzAgent employee,
    // otherwise it falls back to the normal live-chat reply pipeline.
    if (rest.isEmpty && (content.startsWith('@') || content.startsWith('＠'))) {
      final space = content.indexOf(RegExp(r'\s'));
      final name = space > 1
          ? content.substring(1, space).trim()
          : content.substring(1).trim();
      if (name.isNotEmpty && _employeeNameMatches(name)) {
        final taskText = space > 1 ? content.substring(space).trim() : '';
        return (
          targetName: name,
          taskText: taskText.isEmpty ? '请向观众做一个简短的自我介绍吧' : taskText,
        );
      }
      return null;
    }

    if (rest.isEmpty) return null;

    // Target employee: `!agent @员工名 任务内容`
    String? targetName;
    String taskText = rest;
    if (rest.startsWith('@') || rest.startsWith('＠')) {
      final space = rest.indexOf(RegExp(r'\s'));
      if (space > 1) {
        targetName = rest.substring(1, space);
        taskText = rest.substring(space).trim();
      } else {
        targetName = rest.substring(1);
        taskText = '';
      }
    }

    if (taskText.isEmpty) taskText = '请向观众做一个简短的自我介绍吧';
    return (targetName: targetName, taskText: taskText);
  }

  bool _employeeNameMatches(String name) {
    final target = name.trim().toLowerCase();
    return _agentTaskEmployeeNames.any((n) => n.toLowerCase() == target);
  }

  /// 滑动窗口补位：从溢出缓冲区取最新弹幕填充窗口
  void _refillSlidingWindow() {
    while (_pendingMessages.length < _maxWindowSize &&
        _overflowMessages.isNotEmpty) {
      _pendingMessages.add(_overflowMessages.removeLast());
    }
  }

  /// 手动触发AI回复（带自定义prompt）
  void triggerReply(String prompt) {
    if (onAIResponse == null) return;
    if (_isAiBusy) return; // AI正忙，请稍后再试
    _isAiBusy = true;
    notifyListeners();
    onAIResponse!(prompt).then((_) {
      _isAiBusy = false;
      notifyListeners();
    });
  }

  /// 编辑模式下手动添加弹幕（用于测试AI回复功能）
  /// [content] 弹幕内容，[uname] 可选自定义用户名
  void addManualDanmaku(String content, {String uname = '🧪 Test'}) {
    if (content.trim().isEmpty) return;
    final msg = BilibiliDanmaku(
      type: BilibiliDanmakuType.chat,
      uid: 0,
      uname: uname,
      content: content.trim(),
      timestamp: DateTime.now(),
    );
    _messages.insert(0, msg);
    if (_messages.length > _maxMessages) {
      _messages.removeRange(_maxMessages, _messages.length);
    }
    // 如果自动回复开启，按模式加入待处理队列
    if (_autoReply) {
      final formatted = msg.toAIFormat();
      if (_replyMode == StreamReplyMode.slidingWindow) {
        if (_pendingMessages.length < _maxWindowSize) {
          _pendingMessages.add(formatted);
        } else {
          _overflowMessages.add(formatted);
        }
      } else {
        _pendingMessages.add(formatted);
      }
      // Edit模式下可能没连接直播间，定时器未启动，手动启动
      if (_replyTimer == null) {
        _startReplyTimer();
      }
      // 编辑模式立即尝试触发回复（_tryFlushOne有_isAiBusy保护）
      _tryFlushOne();
    }
    notifyListeners();
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
        // 设置系统提示词 → 等待设置完成后再推进
        final prompt = node.settings['systemPrompt'] as String? ?? '';
        if (prompt.isNotEmpty && onAIResponse != null) {
          onAIResponse!('__SYSTEM_PROMPT__:$prompt').then((_) {
            _advanceToNextNode();
          });
        } else {
          _advanceToNextNode();
        }
        break;

      case StreamNodeType.promptedResponse:
        // AI回复指定提示词 — 等待AI完成后才推进下一个节点
        final prompt = node.settings['prompt'] as String? ?? '';
        if (prompt.isNotEmpty && onAIResponse != null && !_isAiBusy) {
          _isAiBusy = true;
          onAIResponse!(prompt).then((_) {
            _isAiBusy = false;
            _advanceToNextNode();
            notifyListeners();
          });
        } else {
          // AI正忙或无效prompt，延迟重试
          _setlistTimer = Timer(const Duration(seconds: 2), _advanceToNextNode);
        }
        break;

      case StreamNodeType.chat:
        // 聊天模式：持续N分钟
        final duration = (node.settings['duration'] as num?)?.toInt() ?? 5;
        // 确保自动回复开启
        _autoReply = true;
        _startReplyTimer();
        // N分钟后继续下一个节点
        _setlistTimer = Timer(Duration(minutes: duration), _advanceToNextNode);
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
