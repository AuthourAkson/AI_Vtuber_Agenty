import 'dart:io';

import '../agent_tool.dart';

/// 文件信息工具
///
/// 获取文件或目录的元信息。
class FileInfoTool extends AgentTool {
  @override
  String get name => 'file_info';

  @override
  String get description =>
      '获取文件或目录的元信息，包括大小、最后修改时间、类型和权限。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '文件或目录的绝对路径。重要：始终使用绝对路径，不要使用相对路径。',
      },
    },
    'required': ['path'],
  };

  @override
  bool get requiresPermission => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('参数错误: path 不能为空');
    }

    try {
      final stat = await FileStat.stat(path);

      if (stat.type == FileSystemEntityType.notFound) {
        return ToolResult.error('路径不存在: $path');
      }

      final info = StringBuffer();
      info.writeln('路径: $path');
      info.writeln(
        '类型: ${stat.type == FileSystemEntityType.directory ? '目录' : '文件'}',
      );
      info.writeln('大小: ${stat.size} bytes');
      info.writeln('修改时间: ${stat.modified.toIso8601String()}');
      info.writeln('访问时间: ${stat.accessed.toIso8601String()}');
      info.writeln('权限模式: ${stat.modeString()}');

      return ToolResult.success(info.toString().trim());
    } catch (e) {
      return ToolResult.error('获取文件信息失败: $e');
    }
  }
}
