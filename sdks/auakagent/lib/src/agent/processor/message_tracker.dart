import '../entity/entity.dart';

/// 带状态追踪的消息记录
class TrackedMessage {
  QueuedMessage message;

  TrackedMessage({
    required this.message,
  });

  /// 消息ID
  String get messageId => message.id;

  /// 消息数据（向后兼容）
  Map<String, dynamic> get messageData => message.toMap();

  /// 消息状态
  MessageProcessingStatus get status => message.processingStatus;
  set status(MessageProcessingStatus value) {
    message = message.updateStatus(value);
  }

  /// 消息内容（快捷访问）
  String get content => message.content ?? '';

  /// 创建时间
  DateTime get createdAt => message.createdAt;

  @override
  String toString() {
    return 'TrackedMessage(id: $messageId, status: $status, content: ${content.substring(0, content.length.clamp(0, 20))}...)';
  }
}

/// 消息追踪器 - 维护所有用户消息的完整列表
class MessageTracker {
  final List<TrackedMessage> _messages = [];

  /// 追踪新消息
  void track(String messageId, Map<String, dynamic> messageData) {
    // 创建 QueuedMessage
    final queuedMessage = QueuedMessage.fromMap({
      ...messageData,
      'id': messageId,
      'processingStatus': MessageProcessingStatus.queued.name,
      'enqueuedAt': DateTime.now().toIso8601String(),
    });

    _messages.add(TrackedMessage(message: queuedMessage));
  }

  /// 更新消息状态
  void updateStatus(String messageId, MessageProcessingStatus status) {
    final msg = _messages.where((m) => m.messageId == messageId).firstOrNull;
    if (msg != null) {
      msg.status = status;
    }
  }

  /// 获取当前处理中的消息
  TrackedMessage? getProcessingMessage() {
    return _messages
        .where((m) => m.status == MessageProcessingStatus.processing)
        .firstOrNull;
  }

  /// 获取所有排队中的消息
  List<TrackedMessage> getQueuedMessages() {
    return _messages
        .where((m) => m.status == MessageProcessingStatus.queued)
        .toList();
  }

  /// 获取全部消息（只读副本）
  List<TrackedMessage> get allMessages => List.unmodifiable(_messages);

  /// 清空追踪
  void clear() => _messages.clear();

  /// 释放资源
  void dispose() => _messages.clear();
}
