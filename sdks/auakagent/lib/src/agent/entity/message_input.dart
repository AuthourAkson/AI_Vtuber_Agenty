/// 发送消息的输入数据
///
/// 用于 sendMessage 方法的参数，提供类型安全的消息构建
class MessageInput {
  /// 消息内容
  final String content;

  /// 消息类型（默认: text）
  final String type;

  /// 消息ID（可选，不提供则自动生成）
  final String? id;

  /// 目标员工ID（可选，用于多会话场景）
  final String? employeeId;

  /// 消息角色（可选，默认由系统设置为 user）
  final String? role;

  /// 创建时间（可选，默认由系统设置）
  final DateTime? createdAt;

  /// 工具调用ID（可选，用于工具结果响应）
  final String? toolCallId;

  /// 工具名称（可选）
  final String? toolName;

  /// 工具参数（可选）
  final Map<String, dynamic>? toolArguments;

  /// 工具结果（可选）
  final String? toolResult;

  /// 元数据（可选，用于存储自定义字段）
  final Map<String, dynamic>? metadata;

  const MessageInput({
    required this.content,
    this.type = 'text',
    this.id,
    this.employeeId,
    this.role,
    this.createdAt,
    this.toolCallId,
    this.toolName,
    this.toolArguments,
    this.toolResult,
    this.metadata,
  });

  /// 从 Map 创建（向后兼容）
  ///
  /// 兼容两种 metadata 格式：
  /// - 新格式：metadata 在 map['metadata'] 中（嵌套结构）
  /// - 旧格式：metadata 字段被展开到 map 顶层（toMap 旧行为：addAll）
  factory MessageInput.fromMap(Map<String, dynamic> map) {
    // 提取 metadata：优先取嵌套结构，兼容旧格式顶层展开
    Map<String, dynamic>? metadata;
    final explicitMeta = map['metadata'];
    if (explicitMeta is Map<String, dynamic>) {
      metadata = explicitMeta;
    } else {
      // 旧格式：metadata 字段被展开到 map 顶层，提取已知的 metadata 字段
      final knownMetaKeys = <String>{
        'fileId', 'fileName', 'filePath', 'fileSize', 'sha256', 'fileHash',
        'fromDeviceId', 'isLocalFile', 'mimeType', 'localOnly', 'updateTime',
        'trigger', 'scheduledSystemMessageId', 'taskName', 'taskId',
      };
      final extracted = <String, dynamic>{};
      for (final key in knownMetaKeys) {
        if (map.containsKey(key)) {
          extracted[key] = map[key];
        }
      }
      metadata = extracted.isNotEmpty ? extracted : null;
    }

    return MessageInput(
      content: map['content'] as String? ?? '',
      type: map['type'] as String? ?? 'text',
      id: map['id'] as String?,
      employeeId: map['employeeId'] as String?,
      role: map['role'] as String?,
      createdAt: map['createdAt'] != null
          ? _parseDateTime(map['createdAt'])
          : null,
      toolCallId: map['toolCallId'] as String?,
      toolName: map['toolName'] as String?,
      toolArguments: map['toolArguments'] as Map<String, dynamic>?,
      toolResult: map['toolResult'] as String?,
      metadata: metadata,
    );
  }

  /// 转换为 Map（用于与旧代码兼容或序列化）
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'content': content,
      'type': type,
    };

    if (id != null) map['id'] = id!;
    if (employeeId != null) map['employeeId'] = employeeId!;
    if (role != null) map['role'] = role!;
    if (createdAt != null) map['createdAt'] = createdAt!.toIso8601String();
    if (toolCallId != null) map['toolCallId'] = toolCallId!;
    if (toolName != null) map['toolName'] = toolName!;
    if (toolArguments != null) map['toolArguments'] = toolArguments!;
    if (toolResult != null) map['toolResult'] = toolResult!;
    if (metadata != null) {
      // 保留 metadata 为嵌套结构（修复 RPC 序列化后 metadata 丢失的问题）
      map['metadata'] = metadata!;
    }

    return map;
  }

  /// 复制并修改
  MessageInput copyWith({
    String? content,
    String? type,
    String? id,
    String? employeeId,
    String? role,
    DateTime? createdAt,
    String? toolCallId,
    String? toolName,
    Map<String, dynamic>? toolArguments,
    String? toolResult,
    Map<String, dynamic>? metadata,
  }) {
    return MessageInput(
      content: content ?? this.content,
      type: type ?? this.type,
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      role: role ?? this.role,
      createdAt: createdAt ?? this.createdAt,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      toolArguments: toolArguments ?? this.toolArguments,
      toolResult: toolResult ?? this.toolResult,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 解析 DateTime
  static DateTime _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.parse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }

  @override
  String toString() {
    final contentPreview = content.length > 50 
        ? '${content.substring(0, 50)}...' 
        : content;
    return 'MessageInput(content: $contentPreview, type: $type)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MessageInput && other.content == content;
  }

  @override
  int get hashCode => content.hashCode;
}

/// Map 扩展方法
extension MessageInputMapExtension on Map<String, dynamic> {
  /// 转换为 MessageInput
  MessageInput toMessageInput() => MessageInput.fromMap(this);
}
