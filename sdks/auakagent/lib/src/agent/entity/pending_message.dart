import '../../shared/chat_message.dart';
import 'agent_message.dart';

/// 待确认消息状态
enum PendingMessageStatus {
  pending, // 待确认
  confirmed, // 已确认
  failed, // 发送失败
}

/// 待确认消息
///
/// 存储在 AgentProxy 的待确认队列中
/// 包含完整的消息内容和前端渲染所需的所有字段
class PendingMessage extends AgentMessage {
  /// 发送时间（用于前端显示）
  final DateTime sentAt;

  /// 消息状态（待确认专用）
  final PendingMessageStatus pendingStatus;

  /// 设备ID（可选，用于多设备场景）
  final String? deviceId;

  /// 员工ID（可选，用于多员工场景）
  final String? employeeId;

  const PendingMessage({
    required super.id,
    super.role,
    super.type,
    super.content,
    required super.createdAt,
    super.toolCallId,
    super.toolName,
    super.toolArguments,
    super.toolResult,
    super.toolCalls,
    super.metadata,
    super.status,
    required this.sentAt,
    this.pendingStatus = PendingMessageStatus.pending,
    this.deviceId,
    this.employeeId,
  });

  /// 从 Map 创建（兼容旧格式）
  factory PendingMessage.fromMap(Map<String, dynamic> map) {
    // 解析 status（序列化后始终为String）
    PendingMessageStatus pendingStatus = PendingMessageStatus.pending;
    if (map['status'] is String) {
      pendingStatus = PendingMessageStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => PendingMessageStatus.pending,
      );
    }

    return PendingMessage(
      id: map['id'] as String,
      role: map['role'] as String? ?? 'user',
      type: map['type'] as String? ?? 'text',
      content: map['content'] as String?,
      createdAt: AgentMessage.parseDateTime(map['createdAt']),
      toolCallId: map['toolCallId'] as String?,
      toolName: map['toolName'] as String?,
      toolArguments: map['toolArguments'] as Map<String, dynamic>?,
      toolResult: map['toolResult'] as String?,
      toolCalls: map['toolCalls'] != null
          ? (map['toolCalls'] as List)
              .map((tc) => ToolCall.fromMap(tc as Map<String, dynamic>))
              .toList()
          : null,
      metadata: map['metadata'] as Map<String, dynamic>?,
      sentAt: AgentMessage.parseDateTime(map['sentAt'] ?? map['createdAt']),
      pendingStatus: pendingStatus,
      deviceId: map['deviceId'] as String?,
      employeeId: map['employeeId'] as String?,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    final map = super.toMap();
    return {
      ...map,
      'sentAt': sentAt.toIso8601String(),
      'status': pendingStatus.name,
      if (deviceId != null) 'deviceId': deviceId,
      if (employeeId != null) 'employeeId': employeeId,
    };
  }

  @override
  PendingMessage copyWith({
    String? id,
    String? role,
    String? type,
    String? content,
    DateTime? createdAt,
    String? toolCallId,
    String? toolName,
    Map<String, dynamic>? toolArguments,
    String? toolResult,
    List<ToolCall>? toolCalls,
    Map<String, dynamic>? metadata,
    String? status,
    DateTime? sentAt,
    PendingMessageStatus? pendingStatus,
    String? deviceId,
    String? employeeId,
  }) {
    return PendingMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      type: type ?? this.type,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      toolArguments: toolArguments ?? this.toolArguments,
      toolResult: toolResult ?? this.toolResult,
      toolCalls: toolCalls ?? this.toolCalls,
      metadata: metadata ?? this.metadata,
      sentAt: sentAt ?? this.sentAt,
      pendingStatus: pendingStatus ?? this.pendingStatus,
      deviceId: deviceId ?? this.deviceId,
      employeeId: employeeId ?? this.employeeId,
    );
  }

  /// 标记为已确认
  PendingMessage confirm() => copyWith(pendingStatus: PendingMessageStatus.confirmed);

  /// 标记为失败
  PendingMessage fail() => copyWith(pendingStatus: PendingMessageStatus.failed);

  /// 是否待确认
  bool get isPending => pendingStatus == PendingMessageStatus.pending;

  /// 是否已确认
  bool get isConfirmed => pendingStatus == PendingMessageStatus.confirmed;

  /// 是否失败
  bool get isFailed => pendingStatus == PendingMessageStatus.failed;

  @override
  String toString() {
    return 'PendingMessage(id: $id, status: $status, content: ${content?.substring(0, content!.length.clamp(0, 20))})';
  }
}

/// Map 扩展方法
extension PendingMessageMapExtension on Map<String, dynamic> {
  /// 转换为 PendingMessage
  PendingMessage toPendingMessage() => PendingMessage.fromMap(this);
}
