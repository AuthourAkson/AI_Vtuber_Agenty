/// MCP 工具定义（从服务器获取）
class McpToolDefinition {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpToolDefinition({
    required this.name,
    required this.description,
    this.inputSchema = const {},
  });
}

/// MCP 工具调用结果
class McpToolCallResult {
  final String content;
  final bool isError;

  const McpToolCallResult({required this.content, this.isError = false});
}

/// MCP 重连事件
class McpReconnectEvent {
  /// 事件类型：reconnecting | reconnected | reconnect_failed
  final String type;

  McpReconnectEvent(this.type);
}

/// MCP 客户端接口
///
/// 定义与 MCP 服务器交互的标准接口。
/// 具体实现（stdio、SSE、HTTP）通过 McpClientImpl 提供。
abstract class McpClient {
  /// 连接到 MCP 服务器
  Future<void> connect();

  /// 断开连接
  Future<void> disconnect();

  /// 获取服务器提供的工具列表
  ///
  /// 内置调用级重试：失败后最多重试 [McpRetryConfig.maxRetries] 次，
  /// 重试全部失败后触发重连并再试一次。
  Future<List<McpToolDefinition>> listTools();

  /// 调用指定工具
  ///
  /// 内置调用级重试：失败后最多重试 [McpRetryConfig.maxRetries] 次，
  /// 重试全部失败后触发重连并再试一次。
  Future<McpToolCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  );

  /// 健康检查（ping）
  Future<bool> ping();

  /// 是否正在重连
  bool get isReconnecting;

  /// 手动触发重连
  ///
  /// 如果当前正在重连中，会等待当前重连完成后再执行。
  Future<void> reconnect();

  /// 重连状态变更事件流
  ///
  /// 事件类型：
  /// - `reconnecting` — 开始尝试重连
  /// - `reconnected` — 重连成功
  /// - `reconnect_failed` — 所有重试耗尽，重连失败
  Stream<McpReconnectEvent> get onReconnect;
}
