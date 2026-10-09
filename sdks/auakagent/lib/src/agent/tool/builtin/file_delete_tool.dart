import 'dart:io';

import '../agent_tool.dart';

/// 文件删除工具
///
/// 删除文件或目录。
class FileDeleteTool extends AgentTool {
  @override
  String get name => 'file_delete';

  @override
  String get description =>
      '删除指定路径的文件或目录。对于目录，设置 recursive 为 true 可删除非空目录。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '要删除的文件或目录的绝对路径。重要：始终使用绝对路径，不要使用相对路径。',
      },
      'recursive': {
        'type': 'boolean',
        'description':
            '如果为 true，递归删除目录（包含内容）。默认：false',
      },
    },
    'required': ['path'],
  };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'file_delete';

  @override
  String get permissionArgKey => 'path';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('参数错误: path 不能为空');
    }

    final recursive = arguments['recursive'] as bool? ?? false;

    try {
      final type = await FileSystemEntity.type(path);

      if (type == FileSystemEntityType.notFound) {
        return ToolResult.error('路径不存在: $path');
      }

      if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: recursive);
        return ToolResult.success('目录已删除: $path');
      } else {
        await File(path).delete();
        return ToolResult.success('文件已删除: $path');
      }
    } catch (e) {
      return ToolResult.error('删除失败: $e');
    }
  }
}
