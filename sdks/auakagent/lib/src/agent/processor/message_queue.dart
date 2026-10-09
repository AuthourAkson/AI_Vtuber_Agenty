import 'dart:async';

import '../entity/entity.dart';

/// 消息队列项
class MessageQueueItem {
  final QueuedMessage message;
  final Completer<void>? completer;

  MessageQueueItem({
    required this.message,
    this.completer,
  });

  /// 消息ID（便捷访问）
  String get messageId => message.id;

  /// 消息数据（向后兼容）
  Map<String, dynamic> get messageData => message.toMap();
}

/// 消息队列
///
/// 管理待处理的消息，支持优先级和撤回。
class MessageQueue {
  final List<MessageQueueItem> _queue = [];

  /// 添加消息到队列
  void enqueue(MessageQueueItem item) {
    _queue.add(item);
  }

  /// 取出队首消息
  MessageQueueItem? dequeue() {
    if (_queue.isEmpty) return null;
    return _queue.removeAt(0);
  }

  /// 查看队首消息（不移除）
  MessageQueueItem? peek() {
    if (_queue.isEmpty) return null;
    return _queue.first;
  }

  /// 撤回消息
  bool revoke(String messageId) {
    final index = _queue.indexWhere((item) => item.messageId == messageId);
    if (index == -1) return false;

    final item = _queue.removeAt(index);
    item.completer?.completeError('消息已撤回');
    return true;
  }

  /// 清空队列
  void clear() {
    for (final item in _queue) {
      item.completer?.completeError('队列已清空');
    }
    _queue.clear();
  }

  /// 队列长度
  int get length => _queue.length;

  /// 是否为空
  bool get isEmpty => _queue.isEmpty;

  /// 是否包含指定消息
  bool contains(String messageId) {
    return _queue.any((item) => item.messageId == messageId);
  }

  /// 获取所有消息ID
  List<String> get messageIds => _queue.map((item) => item.messageId).toList();

  /// 获取队列中所有项的只读副本
  List<MessageQueueItem> get items => List.unmodifiable(_queue);
}
