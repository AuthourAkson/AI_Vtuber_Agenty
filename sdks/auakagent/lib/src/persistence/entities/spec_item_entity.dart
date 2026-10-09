/// Spec 项状态
enum SpecStatus {
  draft,
  pending,
  inProgress,
  completed;

  static SpecStatus fromString(String value) {
    return SpecStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SpecStatus.pending,
    );
  }

  /// 数据库存储值（与 Dart 枚举名一致）
  String get dbValue => name;
}

/// Spec 项优先级
enum SpecPriority {
  low,
  medium,
  high;

  static SpecPriority fromString(String value) {
    return SpecPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => SpecPriority.medium,
    );
  }

  String get dbValue => name;
}

/// Spec 项实体
class SpecItemEntity {
  /// UUID
  final String id;

  /// 员工 UUID
  String employeeId;

  /// 标题
  String title;

  /// 内容（详细描述）
  String content;

  /// 状态 (draft/pending/in_progress/completed)
  String status;

  /// 优先级 (low/medium/high)
  String priority;

  /// 标签（逗号分隔）
  String tags;

  /// 排序序号
  int sortOrder;

  /// 是否已删除（软删除）
  int deleted;

  /// 创建时间
  DateTime createTime;

  /// 更新时间
  DateTime updateTime;

  SpecItemEntity({
    required this.id,
    required this.employeeId,
    required this.title,
    this.content = '',
    this.status = 'pending',
    this.priority = 'medium',
    this.tags = '',
    this.sortOrder = 0,
    this.deleted = 0,
    required this.createTime,
    required this.updateTime,
  });

  /// 从 Map 创建
  factory SpecItemEntity.fromMap(Map<String, dynamic> map) {
    return SpecItemEntity(
      id: map['id'] as String,
      employeeId: map['employeeId'] as String,
      title: map['title'] as String,
      content: map['content'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      priority: map['priority'] as String? ?? 'medium',
      tags: map['tags'] as String? ?? '',
      sortOrder: map['sortOrder'] as int? ?? 0,
      deleted: map['deleted'] as int? ?? 0,
      createTime: map['createTime'] is DateTime
          ? map['createTime'] as DateTime
          : DateTime.fromMillisecondsSinceEpoch(
              map['createTime'] as int? ?? 0),
      updateTime: map['updateTime'] is DateTime
          ? map['updateTime'] as DateTime
          : DateTime.fromMillisecondsSinceEpoch(
              map['updateTime'] as int? ?? 0),
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'employeeId': employeeId,
      'title': title,
      'content': content,
      'status': status,
      'priority': priority,
      'tags': tags,
      'sortOrder': sortOrder,
      'deleted': deleted,
      'createTime': createTime.millisecondsSinceEpoch,
      'updateTime': updateTime.millisecondsSinceEpoch,
    };
  }

  /// 复制并修改
  SpecItemEntity copyWith({
    String? id,
    String? employeeId,
    String? title,
    String? content,
    String? status,
    String? priority,
    String? tags,
    int? sortOrder,
    int? deleted,
    DateTime? createTime,
    DateTime? updateTime,
  }) {
    return SpecItemEntity(
      id: id ?? this.id,
      employeeId: employeeId ?? this.employeeId,
      title: title ?? this.title,
      content: content ?? this.content,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      tags: tags ?? this.tags,
      sortOrder: sortOrder ?? this.sortOrder,
      deleted: deleted ?? this.deleted,
      createTime: createTime ?? this.createTime,
      updateTime: updateTime ?? this.updateTime,
    );
  }

  @override
  String toString() {
    return 'SpecItemEntity(id: $id, title: $title, status: $status)';
  }
}
