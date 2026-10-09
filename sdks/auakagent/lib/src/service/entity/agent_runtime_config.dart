/// Agent 运行时配置
///
/// 由定时任务执行器 [TaskExecutor] 通过 [getAgentConfig] 回调获取，
/// 包含执行任务所需的全部运行时信息。
class AgentRuntimeConfig {
  /// AI 模型提供者配置（ProviderConfig.toMap()）
  final Map<String, dynamic>? providerConfig;

  /// 系统 Prompt
  final String? systemPrompt;

  /// 项目上下文
  final Map<String, dynamic>? projectContext;

  /// 可用工具列表
  final List<dynamic>? tools;

  const AgentRuntimeConfig({
    this.providerConfig,
    this.systemPrompt,
    this.projectContext,
    this.tools,
  });

  factory AgentRuntimeConfig.fromMap(Map<String, dynamic> map) {
    return AgentRuntimeConfig(
      providerConfig: map['providerConfig'] as Map<String, dynamic>?,
      systemPrompt: map['systemPrompt'] as String?,
      projectContext: map['projectContext'] as Map<String, dynamic>?,
      tools: map['tools'] as List<dynamic>?,
    );
  }
}
