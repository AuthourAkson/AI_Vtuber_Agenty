import 'package:llm_dart/llm_dart.dart' as llm;

/// Token 用量记录
///
/// 记录一次或多次 LLM 调用的 token 消耗汇总。
class TokenUsageRecord {
  /// 输入 token 数
  final int promptTokens;

  /// 输出 token 数
  final int completionTokens;

  /// 总 token 数
  final int totalTokens;

  /// 推理 token 数（部分模型支持，如 DeepSeek-R1）
  final int reasoningTokens;

  const TokenUsageRecord({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.totalTokens = 0,
    this.reasoningTokens = 0,
  });

  /// 从 llm_dart UsageInfo 创建
  factory TokenUsageRecord.fromUsageInfo(llm.UsageInfo? usage) {
    if (usage == null) return const TokenUsageRecord();
    return TokenUsageRecord(
      promptTokens: usage.promptTokens ?? 0,
      completionTokens: usage.completionTokens ?? 0,
      totalTokens: usage.totalTokens ?? 0,
      reasoningTokens: usage.reasoningTokens ?? 0,
    );
  }

  /// 累加另一条记录
  TokenUsageRecord operator +(TokenUsageRecord other) {
    return TokenUsageRecord(
      promptTokens: promptTokens + other.promptTokens,
      completionTokens: completionTokens + other.completionTokens,
      totalTokens: totalTokens + other.totalTokens,
      reasoningTokens: reasoningTokens + other.reasoningTokens,
    );
  }

  /// 是否为空（无任何 token 消耗）
  bool get isEmpty =>
      promptTokens == 0 &&
      completionTokens == 0 &&
      totalTokens == 0 &&
      reasoningTokens == 0;

  /// 是否有数据
  bool get isNotEmpty => !isEmpty;

  /// 转为 Map（用于序列化 / 事件广播）
  Map<String, dynamic> toMap() {
    return {
      'promptTokens': promptTokens,
      'completionTokens': completionTokens,
      'totalTokens': totalTokens,
      'reasoningTokens': reasoningTokens,
    };
  }

  /// 从 Map 创建
  factory TokenUsageRecord.fromMap(Map<String, dynamic> map) {
    return TokenUsageRecord(
      promptTokens: map['promptTokens'] as int? ?? 0,
      completionTokens: map['completionTokens'] as int? ?? 0,
      totalTokens: map['totalTokens'] as int? ?? 0,
      reasoningTokens: map['reasoningTokens'] as int? ?? 0,
    );
  }

  @override
  String toString() =>
      'TokenUsageRecord(prompt: $promptTokens, completion: $completionTokens, '
      'total: $totalTokens, reasoning: $reasoningTokens)';
}

/// Token 用量统计器
///
/// 管理 Agent 会话级和消息级的 LLM token 消耗统计。
/// 纯内存实现，Agent 销毁时清除。
class TokenUsageTracker {
  /// 会话级累计用量（key: employeeId）
  final Map<String, TokenUsageRecord> _sessionUsage = {};

  /// 消息级累计用量（key: messageId）
  final Map<String, TokenUsageRecord> _messageUsage = {};

  /// 累加 token 用量
  ///
  /// [employeeId] 会话 ID
  /// [messageId] 当前处理的消息 ID
  /// [usage] LLM 返回的用量信息
  void accumulate(String employeeId, String? messageId, llm.UsageInfo? usage) {
    if (usage == null) return;

    final record = TokenUsageRecord.fromUsageInfo(usage);
    if (record.isEmpty) return;

    // 累加到会话级
    _sessionUsage[employeeId] =
        (_sessionUsage[employeeId] ?? const TokenUsageRecord()) + record;

    // 累加到消息级
    if (messageId != null) {
      _messageUsage[messageId] =
          (_messageUsage[messageId] ?? const TokenUsageRecord()) + record;
    }
  }

  /// 获取会话级累计用量
  TokenUsageRecord getSessionUsage(String employeeId) {
    return _sessionUsage[employeeId] ?? const TokenUsageRecord();
  }

  /// 获取消息级累计用量
  TokenUsageRecord? getMessageUsage(String? messageId) {
    return _messageUsage[messageId];
  }

  /// 清空指定会话的统计
  void clear(String employeeId) {
    _sessionUsage.remove(employeeId);
  }

  /// 清空所有统计
  void clearAll() {
    _sessionUsage.clear();
    _messageUsage.clear();
  }

  /// 释放资源
  void dispose() {
    clearAll();
  }
}
