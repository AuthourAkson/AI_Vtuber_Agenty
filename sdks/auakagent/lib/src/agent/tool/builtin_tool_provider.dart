import 'agent_tool.dart';
import 'builtin/builtin_tools.dart';

/// 内置工具提供者接口
///
/// SDK 用户可实现此接口以完全控制 Agent 加载哪些内置工具。
/// 默认实现 [DefaultBuiltinToolProvider] 支持白名单/黑名单过滤。
///
/// 使用示例：
/// ```dart
/// // 方式1：排除危险工具
/// final provider = DefaultBuiltinToolProvider(exclude: {'command_execute', 'bg_command'});
///
/// // 方式2：只保留安全工具
/// final provider = DefaultBuiltinToolProvider(only: {'file_read', 'file_write', 'web_search_prime'});
///
/// // 方式3：完全自定义
/// class MyToolProvider implements BuiltinToolProvider {
///   @override
///   List<AgentTool> provide() => [FileReadTool(), MyCustomTool()];
/// }
/// ```
abstract class BuiltinToolProvider {
  /// 提供内置工具列表
  ///
  /// 返回的工具将注册到 Agent 的 [ToolRegistry] 中。
  List<AgentTool> provide();
}

/// 默认内置工具提供者
///
/// 支持通过 [only]（白名单）或 [exclude]（黑名单）过滤 [BuiltinTools.all()]。
/// 两者互斥：如果同时设置，[only] 优先。
///
/// 不设置任何过滤时，返回所有内置工具（与 [BuiltinTools.all] 行为一致）。
class DefaultBuiltinToolProvider implements BuiltinToolProvider {
  /// 白名单：仅返回名称在此集合中的工具。
  ///
  /// 设置后 [exclude] 无效。
  final Set<String>? only;

  /// 黑名单：排除名称在此集合中的工具。
  ///
  /// 仅在 [only] 为 null 时生效。
  final Set<String>? exclude;

  DefaultBuiltinToolProvider({this.only, this.exclude});

  @override
  List<AgentTool> provide() {
    var tools = BuiltinTools.all();

    if (only != null) {
      tools = tools.where((t) => only!.contains(t.name)).toList();
    } else if (exclude != null) {
      tools = tools.where((t) => !exclude!.contains(t.name)).toList();
    }

    return tools;
  }
}
