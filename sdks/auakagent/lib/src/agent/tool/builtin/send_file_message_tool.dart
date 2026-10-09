import '../agent_tool.dart';

/// 发送文件消息工具
///
/// 将指定路径的文件以助手文件消息的形式发送给用户。
/// 用户会在聊天界面中看到文件卡片（显示文件名、大小），并可以下载该文件。
///
/// 消息以 ChatMessage.file(role: assistant) 持久化到 DB，
/// 并通过 messageStatusChanged(completed) 事件广播，与 AI 循环返回助手消息的流程一致。
///
/// 注入流程：
/// AgentImpl.initialize() 中调用 _injectSendFileMessageCallbacks()，
/// 将文件校验、持久化、广播等回调注入到工具实例。
class SendFileMessageTool extends AgentTool {
  /// 发送文件消息的回调（由 AgentImpl 注入）
  ///
  /// 返回 messageId
  Future<String> Function({
    required String filePath,
    String? mimeType,
  })? sendFileMessage;

  @override
  String get name => 'send_file_message';

  @override
  String get description =>
      '将指定路径的文件以文件消息的形式发送给用户。'
      '\n\n'
      '用户会在聊天界面中看到文件卡片（显示文件名、大小），并可以下载该文件。'
      '\n\n'
      '适用场景：'
      '\n- 生成报告后发送给用户'
      '\n- 导出数据文件（CSV、Excel等）'
      '\n- 发送图片或截图'
      '\n- 分享任何本地文件'
      '\n\n'
      '注意：'
      '\n- 文件必须存在于本地磁盘'
      '\n- 发送的是文件元信息（名称、大小、哈希），实际文件通过后台传输'
      '\n- 用户端收到后可自动或手动下载';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'path': {
            'type': 'string',
            'description':
                '要发送的文件的绝对路径。重要：始终使用绝对路径，不要使用相对路径。',
          },
          'mime_type': {
            'type': 'string',
            'description':
                '可选的 MIME 类型（如 image/png, application/pdf）。默认根据文件扩展名自动推断。',
          },
        },
        'required': ['path'],
      };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'file_read';

  @override
  String? get permissionArgKey => 'path';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final path = arguments['path'] as String?;
    if (path == null || path.isEmpty) {
      return ToolResult.error('参数错误: path 不能为空');
    }

    if (sendFileMessage == null) {
      return ToolResult.error('sendFileMessage 回调未注入，无法发送文件消息');
    }

    final mimeType = arguments['mime_type'] as String?;

    try {
      final messageId = await sendFileMessage!(
        filePath: path,
        mimeType: mimeType,
      );

      return ToolResult.success(
        '文件消息已发送成功。\n'
        '- 文件路径: $path\n'
        '- 消息ID: $messageId\n'
        '用户可以在聊天界面中看到并下载该文件。',
      );
    } catch (e) {
      return ToolResult.error('发送文件消息失败: $e');
    }
  }
}
