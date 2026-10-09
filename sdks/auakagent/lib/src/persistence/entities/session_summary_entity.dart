/// 会话摘要实体
///
/// 存储在 session_summary 表中，作为未读计数和最新消息的权威数据源。
/// 由 SessionSummaryStore 管理，DeviceNotificationManager 和 AgentNotificationHub 读取。
class SessionSummaryEntity {
  final String employeeId;
  final String deviceId;
  int unreadCount;

  String? lastMsgId;
  String? lastMsgRole;
  String? lastMsgContent;
  int? lastMsgTime;
  int? lastMsgSeq;

  /// 待处理的权限请求（JSON 序列化的 AgentPermissionRequest）
  String? pendingPermission;

  /// 待处理的确认请求（JSON 序列化的 AgentConfirmRequest）
  String? pendingConfirm;

  /// 权限请求时间
  int? pendingPermissionTime;

  /// 确认请求时间
  int? pendingConfirmTime;

  int updateTime;

  SessionSummaryEntity({
    required this.employeeId,
    required this.deviceId,
    this.unreadCount = 0,
    this.lastMsgId,
    this.lastMsgRole,
    this.lastMsgContent,
    this.lastMsgTime,
    this.lastMsgSeq,
    this.pendingPermission,
    this.pendingConfirm,
    this.pendingPermissionTime,
    this.pendingConfirmTime,
    required this.updateTime,
  });

  bool get hasLatestMessage =>
      lastMsgId != null && lastMsgId!.isNotEmpty;

  /// 是否有待处理的权限请求
  bool get hasPendingPermission =>
      pendingPermission != null && pendingPermission!.isNotEmpty;

  /// 是否有待处理的确认请求
  bool get hasPendingConfirm =>
      pendingConfirm != null && pendingConfirm!.isNotEmpty;

  /// 是否有任何待处理请求
  bool get hasPendingRequest => hasPendingPermission || hasPendingConfirm;

  String get previewText {
    if (lastMsgContent == null) return '';
    return lastMsgContent!.length <= 100
        ? lastMsgContent!
        : '${lastMsgContent!.substring(0, 100)}...';
  }

  Map<String, dynamic> toMap() => {
    'employee_id': employeeId,
    'device_id': deviceId,
    'unread_count': unreadCount,
    'last_msg_id': lastMsgId,
    'last_msg_role': lastMsgRole,
    'last_msg_content': lastMsgContent,
    'last_msg_time': lastMsgTime,
    'last_msg_seq': lastMsgSeq,
    'pending_permission': pendingPermission,
    'pending_confirm': pendingConfirm,
    'pending_permission_time': pendingPermissionTime,
    'pending_confirm_time': pendingConfirmTime,
    'update_time': updateTime,
  };

  factory SessionSummaryEntity.fromMap(Map<String, dynamic> map) {
    return SessionSummaryEntity(
      employeeId: (map['employee_id'] ?? '') as String,
      deviceId: (map['device_id'] ?? '') as String,
      unreadCount: (map['unread_count'] ?? 0) as int,
      lastMsgId: _nullableString(map['last_msg_id']),
      lastMsgRole: _nullableString(map['last_msg_role']),
      lastMsgContent: _nullableString(map['last_msg_content']),
      lastMsgTime: _nullableInt(map['last_msg_time']),
      lastMsgSeq: _nullableInt(map['last_msg_seq']),
      pendingPermission: _nullableString(map['pending_permission']),
      pendingConfirm: _nullableString(map['pending_confirm']),
      pendingPermissionTime: _nullableInt(map['pending_permission_time']),
      pendingConfirmTime: _nullableInt(map['pending_confirm_time']),
      updateTime: (map['update_time'] ?? 0) as int,
    );
  }

  /// 安全地将动态值转换为可空 String，避免 Null is not a subtype of String 错误
  static String? _nullableString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return null;
  }

  /// 安全地将动态值转换为可空 int，避免 Null is not a subtype of int 错误
  static int? _nullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return null;
  }
}
