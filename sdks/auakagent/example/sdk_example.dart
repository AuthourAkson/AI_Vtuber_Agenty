// ignore_for_file: avoid_print

/// WenzAgent SDK 使用示例
///
/// 展示如何通过 SDK Builder 自定义 Agent 的工具、Skill、MCP 等组件。
library;

import 'package:auakagent/auakagent.dart' hide ToolResult;
import 'package:auakagent/src/agent/tool/agent_tool.dart' show AgentTool, ToolResult;

void main() async {
  // ============================================================
  // 示例 1：最简用法 — 使用默认配置创建 SDK
  // ============================================================
  final sdk1 = WenzAgentSdk.builder().build();
  print('SDK 1: 内置工具数量 = ${sdk1.builtinToolProvider.provide().length}');
  print('SDK 1: MCP Provider = ${sdk1.mcpClientProvider}');
  print('');

  // ============================================================
  // 示例 2：排除危险工具
  // ============================================================
  final sdk2 = WenzAgentSdk.builder()
      .excludeBuiltinTools(['command_execute', 'bg_command', 'git_operations'])
      .build();
  final tools2 = sdk2.builtinToolProvider.provide();
  final toolNames2 = tools2.map((t) => t.name).toList();
  print('SDK 2: 工具列表 = $toolNames2');
  assert(!toolNames2.contains('command_execute'));
  assert(!toolNames2.contains('bg_command'));
  assert(!toolNames2.contains('git_operations'));
  print('');

  // ============================================================
  // 示例 3：仅保留指定工具 + 注册自定义工具
  // ============================================================
  final sdk3 = WenzAgentSdk.builder()
      .onlyBuiltinTools(['file_read', 'file_write', 'end'])
      .registerTool(_MyWeatherTool())
      .registerTools([_MyTranslateTool()])
      .build();
  final tools3 = sdk3.builtinToolProvider.provide();
  final extraTools3 = sdk3.extraTools;
  print('SDK 3: 内置工具 = ${tools3.map((t) => t.name).toList()}');
  print('SDK 3: 额外工具 = ${extraTools3.map((t) => t.name).toList()}');
  print('');

  // ============================================================
  // 示例 4：注册自定义 SkillFactory
  // ============================================================
  final sdk4 = WenzAgentSdk.builder()
      .registerSkillFactory(_HttpApiSkillFactory())
      .build();
  print('SDK 4: Skill 工厂 = ${sdk4.skillFactories.map((f) => f.typeKey).toList()}');
  print('');

  // ============================================================
  // 示例 5：注册自定义 Skill 实例
  // ============================================================
  final sdk5 = WenzAgentSdk.builder()
      .registerSkill(_MyEchoSkill(id: 'echo-1', name: 'Echo Skill'))
      .registerSkills([
        _MyEchoSkill(id: 'echo-2', name: 'Echo Skill 2'),
      ])
      .build();
  print('SDK 5: 自定义 Skill = ${sdk5.extraSkills.map((s) => s.name).toList()}');
  print('');

  // ============================================================
  // 示例 6：完整配置
  // ============================================================
  final sdk6 = WenzAgentSdk.builder()
      .excludeBuiltinTools(['bg_command'])
      .registerTool(_MyWeatherTool())
      .registerSkillFactory(_HttpApiSkillFactory())
      .registerSkill(_MyEchoSkill(id: 'echo-1', name: 'Echo'))
      .build();
  print('SDK 6 (完整配置):');
  print('  内置工具数: ${sdk6.builtinToolProvider.provide().length}');
  print('  额外工具: ${sdk6.extraTools.map((t) => t.name).toList()}');
  print('  Skill 工厂: ${sdk6.skillFactories.map((f) => f.typeKey).toList()}');
  print('  自定义 Skill: ${sdk6.extraSkills.map((s) => s.name).toList()}');

  print('\n所有示例运行完成!');
}

// ============================================================
// 自定义工具示例
// ============================================================

/// 自定义天气查询工具
class _MyWeatherTool extends AgentTool {
  @override
  String get name => 'weather_query';

  @override
  String get description => '查询指定城市的天气信息';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'city': {
            'type': 'string',
            'description': '城市名称',
          },
        },
        'required': ['city'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final city = arguments['city'] as String? ?? '未知';
    return ToolResult.success('$city: 晴, 25°C (模拟数据)');
  }
}

/// 自定义翻译工具
class _MyTranslateTool extends AgentTool {
  @override
  String get name => 'translate';

  @override
  String get description => '翻译文本到指定语言';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'text': {'type': 'string', 'description': '要翻译的文本'},
          'target_lang': {'type': 'string', 'description': '目标语言'},
        },
        'required': ['text', 'target_lang'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final text = arguments['text'] as String? ?? '';
    final lang = arguments['target_lang'] as String? ?? 'en';
    return ToolResult.success('[$lang] $text (翻译模拟)');
  }
}

// ============================================================
// 自定义 SkillFactory 示例
// ============================================================

class _HttpApiSkillFactory implements SkillFactory {
  @override
  String get typeKey => 'http_api';

  @override
  Skill create(Map<String, dynamic> config) {
    return _HttpApiSkill(
      id: config['id'] as String? ?? 'unknown',
      name: config['name'] as String? ?? 'HTTP API Skill',
      baseUrl: config['baseUrl'] as String? ?? 'http://localhost',
    );
  }
}

class _HttpApiSkill implements Skill {
  final String _id;
  final String _name;
  final String _baseUrl;

  _HttpApiSkill({
    required String id,
    required String name,
    required String baseUrl,
  })  : _id = id,
        _name = name,
        _baseUrl = baseUrl;

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  String get description => 'HTTP API Skill: $_baseUrl';

  @override
  SkillType get type => SkillType.custom;

  @override
  SkillStatus get status => SkillStatus.uninitialized;

  @override
  List<AgentTool> get tools => [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> healthCheck() async => true;
}

// ============================================================
// 自定义 Skill 示例
// ============================================================

class _MyEchoSkill implements Skill {
  final String _id;
  final String _name;

  _MyEchoSkill({required String id, required String name})
      : _id = id,
        _name = name;

  @override
  String get id => _id;

  @override
  String get name => _name;

  @override
  String get description => 'Echo Skill - 回显用户输入';

  @override
  SkillType get type => SkillType.custom;

  @override
  SkillStatus get status => SkillStatus.active;

  @override
  List<AgentTool> get tools => [_EchoTool(_name)];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> healthCheck() async => true;
}

class _EchoTool extends AgentTool {
  final String _skillName;

  _EchoTool(this._skillName);

  @override
  String get name => 'echo_$_skillName'.toLowerCase().replaceAll(' ', '_');

  @override
  String get description => 'Echo tool from $_skillName';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'message': {'type': 'string', 'description': '要回显的消息'},
        },
        'required': ['message'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final msg = arguments['message'] as String? ?? '';
    return ToolResult.success('Echo from $_skillName: $msg');
  }
}
