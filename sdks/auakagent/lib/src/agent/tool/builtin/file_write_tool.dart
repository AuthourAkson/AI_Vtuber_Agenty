import 'dart:io';

import '../agent_tool.dart';

/// 文件写入工具
///
/// 将内容写入指定路径的文件，支持覆盖和追加模式。
class FileWriteTool extends AgentTool {
  @override
  String get name => 'file_write';

  @override
  String get description =>
      '将内容写入指定路径的文件。如果文件或父目录不存在则自动创建。默认覆盖写入，设置 append 为 true 则追加写入。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'path': {
        'type': 'string',
        'description': '要写入的文件的绝对路径。重要：始终使用绝对路径，不要使用相对路径。',
      },
      'content': {
        'type': 'string',
        'description': '要写入文件的内容',
      },
      'append': {
        'type': 'boolean',
        'description':
            '如果为 true，追加内容而非覆盖写入。默认：false',
      },
    },
    'required': ['path', 'content'],
  };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'file_write';

  @override
  String get permissionArgKey => 'path';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('参数错误: path 不能为空');
    }

    final content = arguments['content'] as String? ?? '';
    final append = arguments['append'] as bool? ?? false;

    try {
      final file = File(path);

      // 确保父目录存在
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      await file.writeAsString(
        content,
        mode: append ? FileMode.append : FileMode.write,
      );

      final stat = await file.stat();
      return ToolResult.success(
        '文件写入成功: $path (${stat.size} bytes)',
        metadata: {'path': path, 'size': stat.size, 'append': append},
      );
    } catch (e) {
      return ToolResult.error('写入文件失败: $e');
    }
  }
}
