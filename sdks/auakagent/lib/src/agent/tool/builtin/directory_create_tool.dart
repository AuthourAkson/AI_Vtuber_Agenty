import 'dart:io';

import '../agent_tool.dart';

/// 目录创建工具
///
/// 创建新目录，支持递归创建父目录。
class DirectoryCreateTool extends AgentTool {
  @override
  String get name => 'directory_create';

  @override
  String get description =>
      '在指定路径创建新目录。设置 recursive 为 true 可自动创建父目录。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '要创建的目录路径',
      },
      'recursive': {
        'type': 'boolean',
        'description':
            '如果为 true，当父目录不存在时自动创建。默认：true',
      },
    },
    'required': ['path'],
  };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'directory_create';

  @override
  String get permissionArgKey => 'path';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('参数错误: path 不能为空');
    }

    final recursive = arguments['recursive'] as bool? ?? true;

    try {
      final dir = Directory(path);

      if (await dir.exists()) {
        return ToolResult.success('目录已存在: $path');
      }

      await dir.create(recursive: recursive);
      return ToolResult.success('目录已创建: $path');
    } catch (e) {
      return ToolResult.error('创建目录失败: $e');
    }
  }
}
