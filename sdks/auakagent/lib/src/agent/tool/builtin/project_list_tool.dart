import '../agent_tool.dart';

/// 项目列表查询工具
///
/// 让 AI 可以查询本设备上的所有可用项目，支持列出、搜索和查看详情。
/// 用于多项目协作场景，例如跨项目文件同步、对比、批量操作等。
///
/// 所有数据通过异步回调由 AgentImpl 注入，工具本身不直接依赖 ProjectManager。
class ProjectListTool extends AgentTool {
  // ===== 异步回调（由 AgentImpl 注入） =====

  /// 获取当前绑定的项目UUID
  String? Function()? getCurrentProjectUuid;

  /// 列出所有项目，返回序列化 Map 列表
  Future<List<Map<String, dynamic>>> Function()? listAllProjects;

  /// 按关键词搜索项目，返回序列化 Map 列表
  Future<List<Map<String, dynamic>>> Function(String keyword)? searchProjects;

  /// 获取单个项目详情，返回序列化 Map 或 null
  Future<Map<String, dynamic>?> Function(String uuid)? getProjectDetail;

  /// 当前员工 ID（由 AgentImpl 注入）
  String? employeeId;

  @override
  String get name => 'project_list';

  @override
  String get description =>
      '查询本设备上的项目列表。支持三种操作：\n\n'
      '- "list"：列出所有可用项目，返回项目名称、路径、描述等简要信息。\n'
      '- "search"：按关键词搜索项目（匹配名称或描述）。\n'
      '- "detail"：获取指定项目的详细信息（包含 Git URL、创建时间等）。\n\n'
      '用于多项目协作场景，了解可用的项目及其工作路径。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['list', 'search', 'detail'],
            'description':
                '操作类型："list" 列出所有项目；"search" 按关键词搜索；"detail" 获取单个项目详情。',
          },
          'keyword': {
            'type': 'string',
            'description': '搜索关键词（action 为 "search" 时使用），匹配项目名称或描述。',
          },
          'project_uuid': {
            'type': 'string',
            'description': '项目UUID（action 为 "detail" 时使用），获取指定项目的详细信息。',
          },
        },
        'required': ['action'],
      };

  @override
  bool get requiresPermission => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'] as String?;
    if (action == null || action.isEmpty) {
      return ToolResult.error('action is required');
    }

    switch (action) {
      case 'list':
        return await _handleList();
      case 'search':
        return await _handleSearch(arguments['keyword'] as String?);
      case 'detail':
        return await _handleDetail(arguments['project_uuid'] as String?);
      default:
        return ToolResult.error(
          'Unknown action: $action. Use "list", "search", or "detail".',
        );
    }
  }

  /// 列出所有项目
  Future<ToolResult> _handleList() async {
    if (listAllProjects == null) {
      return ToolResult.error('项目列表功能未初始化');
    }

    final projects = await listAllProjects!();
    if (projects.isEmpty) {
      return ToolResult.success('当前设备没有可用项目。');
    }

    final currentUuid = getCurrentProjectUuid?.call();
    final buffer = StringBuffer('## 项目列表（共 ${projects.length} 个）\n\n');

    for (var i = 0; i < projects.length; i++) {
      final p = projects[i];
      final uuid = p['uuid'] as String? ?? '';
      final title = p['title'] as String? ?? '未命名';
      final workPath = p['workPath'] as String? ?? '';
      final description = p['description'] as String? ?? '';
      final isCurrent = uuid == currentUuid;
      final marker = isCurrent ? ' ← 当前项目' : '';

      buffer.writeln(
        '${i + 1}. **$title**$marker',
      );
      buffer.writeln('   - UUID: $uuid');
      if (workPath.isNotEmpty) {
        buffer.writeln('   - 路径: $workPath');
      }
      if (description.isNotEmpty) {
        buffer.writeln('   - 描述: $description');
      }
    }

    return ToolResult.success(buffer.toString().trim());
  }

  /// 搜索项目
  Future<ToolResult> _handleSearch(String? keyword) async {
    if (keyword == null || keyword.isEmpty) {
      return ToolResult.error('search 操作需要提供 keyword 参数。');
    }

    if (searchProjects == null) {
      return ToolResult.error('项目搜索功能未初始化');
    }

    final projects = await searchProjects!(keyword);
    if (projects.isEmpty) {
      return ToolResult.success('未找到匹配 "$keyword" 的项目。');
    }

    final currentUuid = getCurrentProjectUuid?.call();
    final buffer =
        StringBuffer('## 搜索结果："$keyword"（共 ${projects.length} 个）\n\n');

    for (var i = 0; i < projects.length; i++) {
      final p = projects[i];
      final uuid = p['uuid'] as String? ?? '';
      final title = p['title'] as String? ?? '未命名';
      final workPath = p['workPath'] as String? ?? '';
      final description = p['description'] as String? ?? '';
      final isCurrent = uuid == currentUuid;
      final marker = isCurrent ? ' ← 当前项目' : '';

      buffer.writeln(
        '${i + 1}. **$title**$marker',
      );
      buffer.writeln('   - UUID: $uuid');
      if (workPath.isNotEmpty) {
        buffer.writeln('   - 路径: $workPath');
      }
      if (description.isNotEmpty) {
        buffer.writeln('   - 描述: $description');
      }
    }

    return ToolResult.success(buffer.toString().trim());
  }

  /// 获取项目详情
  Future<ToolResult> _handleDetail(String? projectUuid) async {
    if (projectUuid == null || projectUuid.isEmpty) {
      return ToolResult.error('detail 操作需要提供 project_uuid 参数。');
    }

    if (getProjectDetail == null) {
      return ToolResult.error('项目详情功能未初始化');
    }

    final project = await getProjectDetail!(projectUuid);
    if (project == null) {
      return ToolResult.error('未找到项目: $projectUuid');
    }

    final currentUuid = getCurrentProjectUuid?.call();
    final isCurrent = projectUuid == currentUuid;

    final buffer = StringBuffer('## 项目详情\n\n');

    buffer.writeln('- 名称: ${project['title'] ?? '未命名'}${isCurrent ? '（当前项目）' : ''}');
    buffer.writeln('- UUID: ${project['uuid']}');

    final description = project['description'] as String?;
    if (description != null && description.isNotEmpty) {
      buffer.writeln('- 描述: $description');
    }

    final workPath = project['workPath'] as String?;
    if (workPath != null && workPath.isNotEmpty) {
      buffer.writeln('- 工作路径: $workPath');
    }

    final gitUrl = project['gitUrl'] as String?;
    if (gitUrl != null && gitUrl.isNotEmpty) {
      buffer.writeln('- Git URL: $gitUrl');
    }

    final createTime = project['createTime'] as int?;
    if (createTime != null) {
      buffer.writeln('- 创建时间: ${_formatTimestamp(createTime)}');
    }

    final updateTime = project['updateTime'] as int?;
    if (updateTime != null) {
      buffer.writeln('- 更新时间: ${_formatTimestamp(updateTime)}');
    }

    return ToolResult.success(buffer.toString().trim());
  }

  /// 格式化时间戳
  String _formatTimestamp(int millisecondsSinceEpoch) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
