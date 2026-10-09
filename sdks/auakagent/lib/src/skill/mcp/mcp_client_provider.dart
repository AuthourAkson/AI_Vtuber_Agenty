import 'mcp_client.dart';
import '../../persistence/entities/mcp_server_config.dart';

/// MCP 客户端提供者接口
///
/// SDK 用户可实现此接口以自定义 MCP 客户端的创建方式。
/// 例如：使用不同的传输层（自定义 stdio、HTTP SSE、WebSocket 等），
/// 或注入自定义的认证、日志、重试策略。
///
/// 使用示例：
/// ```dart
/// class CustomMcpClientProvider implements McpClientProvider {
///   @override
///   McpClient createClient(McpServerConfig config) {
///     return MyCustomMcpClient(config);
///   }
/// }
///
/// // 注册到 SDK
/// sdk.mcpClientProvider(CustomMcpClientProvider());
/// ```
abstract class McpClientProvider {
  /// 根据 MCP 服务器配置创建客户端实例
  ///
  /// [config] MCP 服务器连接配置（传输类型、命令、URL、参数等）
  /// 返回一个未连接的 [McpClient] 实例，由调用方负责 connect()。
  McpClient createClient(McpServerConfig config);
}
