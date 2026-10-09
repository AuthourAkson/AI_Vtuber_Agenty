import '../agent/adapter/provider_config.dart';
import '../agent/tool/agent_tool.dart';
import '../agent/tool/builtin_tool_provider.dart';
import '../skill/mcp/mcp_client_provider.dart';
import '../skill/skill.dart';
import '../skill/skill_factory.dart';

/// Agent 创建配置
///
/// 用于 [WenzAgentSdk.createAgent] 方法，指定 Agent 的基本参数。
class AgentConfig {
  /// 员工/Agent 唯一标识
  final String employeeId;

  /// LLM 提供商配置
  final ProviderConfig providerConfig;

  /// 系统提示词（可选）
  final String? systemPrompt;

  /// 所属设备ID（可选，用于数据隔离）
  final String? deviceId;

  /// 是否启用内置工具，默认 true
  final bool enableBuiltinTools;

  /// 是否启用技能系统，默认 true
  final bool enableSkills;

  const AgentConfig({
    required this.employeeId,
    required this.providerConfig,
    this.systemPrompt,
    this.deviceId,
    this.enableBuiltinTools = true,
    this.enableSkills = true,
  });
}

/// WenzAgent SDK 主入口
///
/// 通过 [WenzAgentSdk.builder()] 创建实例，支持自定义：
/// - 内置工具（过滤、替换、新增）
/// - Skill 工厂（自定义 Skill 类型）
/// - MCP 客户端提供者（自定义 MCP 传输层）
/// - 自定义 Skill 实例
///
/// 使用示例：
/// ```dart
/// final sdk = WenzAgentSdk.builder()
///   .excludeBuiltinTools(['command_execute', 'bg_command'])
///   .registerTool(MyWeatherTool())
///   .registerSkillFactory(HttpApiSkillFactory())
///   .mcpClientProvider(CustomMcpProvider())
///   .build();
///
/// final agent = await sdk.createAgent(AgentConfig(
///   employeeId: 'emp-001',
///   providerConfig: ProviderConfig(
///     provider: LLMProvider.openai,
///     model: 'gpt-4o',
///     apiKey: 'sk-...',
///   ),
/// ));
/// ```
class WenzAgentSdk {
  // ===== 配置组件 =====
  final BuiltinToolProvider _builtinToolProvider;
  final McpClientProvider? _mcpClientProvider;
  final List<SkillFactory> _skillFactories;
  final List<AgentTool> _extraTools;
  final List<Skill> _extraSkills;

  WenzAgentSdk._({
    required BuiltinToolProvider builtinToolProvider,
    McpClientProvider? mcpClientProvider,
    List<SkillFactory> skillFactories = const [],
    List<AgentTool> extraTools = const [],
    List<Skill> extraSkills = const [],
  })  : _builtinToolProvider = builtinToolProvider,
        _mcpClientProvider = mcpClientProvider,
        _skillFactories = List.unmodifiable(skillFactories),
        _extraTools = List.unmodifiable(extraTools),
        _extraSkills = List.unmodifiable(extraSkills);

  /// 创建 SDK Builder
  static WenzAgentSdkBuilder builder() => WenzAgentSdkBuilder();

  // ===== Getters =====

  /// 内置工具提供者
  BuiltinToolProvider get builtinToolProvider => _builtinToolProvider;

  /// MCP 客户端提供者（可能为 null，表示使用默认）
  McpClientProvider? get mcpClientProvider => _mcpClientProvider;

  /// 已注册的自定义 Skill 工厂列表
  List<SkillFactory> get skillFactories => _skillFactories;

  /// 已注册的额外工具列表
  List<AgentTool> get extraTools => _extraTools;

  /// 已注册的自定义 Skill 列表
  List<Skill> get extraSkills => _extraSkills;
}

/// WenzAgent SDK Builder
///
/// 流式配置 SDK 的各项组件，最终通过 [build] 生成 [WenzAgentSdk] 实例。
///
/// 所有配置方法返回 `this`，支持链式调用。
class WenzAgentSdkBuilder {
  BuiltinToolProvider? _builtinToolProvider;
  McpClientProvider? _mcpClientProvider;
  final List<SkillFactory> _skillFactories = [];
  final List<AgentTool> _extraTools = [];
  final List<Skill> _extraSkills = [];

  // ===== 内置工具配置 =====

  /// 设置自定义的内置工具提供者
  ///
  /// 完全替换默认的内置工具列表。
  /// 与 [excludeBuiltinTools] / [onlyBuiltinTools] 互斥，后设置的生效。
  WenzAgentSdkBuilder builtinToolProvider(BuiltinToolProvider provider) {
    _builtinToolProvider = provider;
    return this;
  }

  /// 排除指定名称的内置工具
  ///
  /// [names] 要排除的工具名称列表，如 `['command_execute', 'bg_command']`。
  /// 与 [builtinToolProvider] / [onlyBuiltinTools] 互斥，后设置的生效。
  WenzAgentSdkBuilder excludeBuiltinTools(List<String> names) {
    _builtinToolProvider = DefaultBuiltinToolProvider(exclude: names.toSet());
    return this;
  }

  /// 仅保留指定名称的内置工具
  ///
  /// [names] 要保留的工具名称列表，如 `['file_read', 'file_write']`。
  /// 与 [builtinToolProvider] / [excludeBuiltinTools] 互斥，后设置的生效。
  WenzAgentSdkBuilder onlyBuiltinTools(List<String> names) {
    _builtinToolProvider = DefaultBuiltinToolProvider(only: names.toSet());
    return this;
  }

  // ===== MCP 配置 =====

  /// 设置自定义 MCP 客户端提供者
  ///
  /// 替换默认的 MCP 客户端创建逻辑，允许使用自定义的传输层或认证方式。
  WenzAgentSdkBuilder mcpClientProvider(McpClientProvider provider) {
    _mcpClientProvider = provider;
    return this;
  }

  // ===== Skill 工厂配置 =====

  /// 注册自定义 Skill 工厂
  ///
  /// 工厂通过 [SkillFactory.typeKey] 标识，当遇到匹配类型的 Skill 配置时
  /// 会使用该工厂创建 Skill 实例。
  WenzAgentSdkBuilder registerSkillFactory(SkillFactory factory) {
    _skillFactories.add(factory);
    return this;
  }

  // ===== 自定义工具配置 =====

  /// 注册额外的自定义工具
  ///
  /// 这些工具会在内置工具之后注册到 Agent 的 ToolRegistry。
  /// 如果与内置工具同名，会覆盖内置工具。
  WenzAgentSdkBuilder registerTool(AgentTool tool) {
    _extraTools.add(tool);
    return this;
  }

  /// 批量注册额外的自定义工具
  WenzAgentSdkBuilder registerTools(List<AgentTool> tools) {
    _extraTools.addAll(tools);
    return this;
  }

  // ===== 自定义 Skill 配置 =====

  /// 注册自定义 Skill 实例
  ///
  /// 这些 Skill 会在 Agent 初始化时直接加载，
  /// 无需通过持久化配置或 SkillFactory。
  WenzAgentSdkBuilder registerSkill(Skill skill) {
    _extraSkills.add(skill);
    return this;
  }

  /// 批量注册自定义 Skill 实例
  WenzAgentSdkBuilder registerSkills(List<Skill> skills) {
    _extraSkills.addAll(skills);
    return this;
  }

  // ===== Build =====

  /// 构建 [WenzAgentSdk] 实例
  ///
  /// 未配置的组件使用默认值：
  /// - 内置工具：[DefaultBuiltinToolProvider]（返回全部内置工具）
  /// - MCP：使用 McpSkill 的静态 clientFactory
  /// - Skill 工厂/额外工具/额外 Skill：空列表
  WenzAgentSdk build() {
    return WenzAgentSdk._(
      builtinToolProvider:
          _builtinToolProvider ?? DefaultBuiltinToolProvider(),
      mcpClientProvider: _mcpClientProvider,
      skillFactories: List.from(_skillFactories),
      extraTools: List.from(_extraTools),
      extraSkills: List.from(_extraSkills),
    );
  }
}
