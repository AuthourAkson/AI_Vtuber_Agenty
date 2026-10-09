/// 项目数据实体
class ProjectData {
  /// 项目UUID
  final String? projectUuid;

  /// 项目名称
  final String? projectName;

  /// 项目上下文
  final String? projectContext;

  /// 项目工作路径（项目在设备上的本地目录路径）
  final String? workPath;

  /// 补充信息
  final String? additionalInfo;

  /// 项目元数据
  final Map<String, dynamic>? metadata;

  const ProjectData({
    this.projectUuid,
    this.projectName,
    this.projectContext,
    this.workPath,
    this.additionalInfo,
    this.metadata,
  });

  /// 从 Map 创建
  factory ProjectData.fromMap(Map<String, dynamic> map) {
    return ProjectData(
      projectUuid: map['projectUuid'] as String?,
      projectName: map['projectName'] as String?,
      projectContext: map['projectContext'] as String?,
      workPath: map['workPath'] as String?,
      additionalInfo: map['additionalInfo'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }

  /// 转换为 Map
  Map<String, dynamic> toMap() => {
        if (projectUuid != null) 'projectUuid': projectUuid,
        if (projectName != null) 'projectName': projectName,
        if (projectContext != null) 'projectContext': projectContext,
        if (workPath != null) 'workPath': workPath,
        if (additionalInfo != null) 'additionalInfo': additionalInfo,
        if (metadata != null) 'metadata': metadata,
      };

  @override
  String toString() {
    return 'ProjectData(projectUuid: $projectUuid, projectName: $projectName, workPath: $workPath)';
  }
}
