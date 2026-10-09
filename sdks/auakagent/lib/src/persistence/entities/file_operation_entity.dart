/// 文件操作类型
enum FileOperationType {
  created,
  modified,
  deleted,
  read;

  static FileOperationType fromString(String value) {
    return FileOperationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => FileOperationType.modified,
    );
  }

  /// 数据库存储值
  String get dbValue => name;
}

/// 文件操作记录实体
class FileOperationEntity {
  /// UUID
  final String id;

  /// 员工 UUID
  final String employeeId;

  /// 触发该操作的用户消息ID
  final String? messageId;

  /// 工具调用ID
  final String? toolCallId;

  /// 工具名称 (file_write, file_delete, ...)
  final String toolName;

  /// 操作类型
  final FileOperationType operationType;

  /// 文件/目录绝对路径
  final String path;

  /// 操作后文件大小（字节）
  final int? fileSize;

  /// 额外信息（如 patchCount, append 等）
  final Map<String, dynamic>? extra;

  /// 操作是否成功
  final bool success;

  /// 失败时的错误信息
  final String? errorMessage;

  /// 操作时间
  final DateTime createdAt;

  FileOperationEntity({
    required this.id,
    required this.employeeId,
    this.messageId,
    this.toolCallId,
    required this.toolName,
    required this.operationType,
    required this.path,
    this.fileSize,
    this.extra,
    required this.success,
    this.errorMessage,
    required this.createdAt,
  });

  /// 从 Map 创建
  factory FileOperationEntity.fromMap(Map<String, dynamic> map) {
    return FileOperationEntity(
      id: map['id'] as String,
      employeeId: map['employeeId'] as String,
      messageId: map['messageId'] as String?,
      toolCallId: map['toolCallId'] as String?,
      toolName: map['toolName'] as String,
      operationType: FileOperationType.fromString(
          map['operationType'] as String? ?? 'modified'),
      path: map['path'] as String,
      fileSize: map['fileSize'] as int?,
      extra: map['extra'] as Map<String, dynamic>?,
      success: map['success'] as bool? ?? true,
      errorMessage: map['errorMessage'] as String?,
      createdAt: map['createdAt'] is DateTime
          ? map['createdAt'] as DateTime
          : DateTime.fromMillisecondsSinceEpoch(
              map['createdAt'] as int? ?? 0),
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'messageId': messageId,
      'toolCallId': toolCallId,
      'toolName': toolName,
      'operationType': operationType.name,
      'path': path,
      'fileSize': fileSize,
      'extra': extra,
      'success': success,
      'errorMessage': errorMessage,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }

  @override
  String toString() {
    return 'FileOperationEntity(id: $id, tool: $toolName, type: $operationType, path: $path, success: $success)';
  }
}
