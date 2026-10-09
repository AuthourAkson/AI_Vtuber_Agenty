import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart' hide ToolResult;
import 'package:auakagent/src/agent/tool/agent_tool.dart' show AgentTool, ToolResult;
import 'package:auakagent/src/skill/mcp/mcp_client_provider.dart';
import 'package:auakagent/src/skill/skill_factory.dart';
import 'package:auakagent/src/skill/skill.dart';
import 'package:auakagent/src/sdk/wenzagent_sdk.dart';

void main() {
  group('WenzAgentSdkBuilder', () {
    test('默认 build 返回默认配置', () {
      final sdk = WenzAgentSdk.builder().build();

      // 默认 BuiltinToolProvider 返回全部工具
      expect(sdk.builtinToolProvider.provide().length, equals(23));
      // 默认无 MCP Provider
      expect(sdk.mcpClientProvider, isNull);
      // 默认无额外组件
      expect(sdk.skillFactories, isEmpty);
      expect(sdk.extraTools, isEmpty);
      expect(sdk.extraSkills, isEmpty);
    });

    test('excludeBuiltinTools 过滤工具', () {
      final sdk = WenzAgentSdk.builder()
          .excludeBuiltinTools(['command_execute', 'bg_command'])
          .build();

      final tools = sdk.builtinToolProvider.provide();
      final names = tools.map((t) => t.name).toSet();
      expect(names.contains('command_execute'), isFalse);
      expect(names.contains('bg_command'), isFalse);
      expect(names.contains('file_read'), isTrue);
    });

    test('onlyBuiltinTools 只保留指定工具', () {
      final sdk = WenzAgentSdk.builder()
          .onlyBuiltinTools(['file_read', 'file_write', 'end'])
          .build();

      final tools = sdk.builtinToolProvider.provide();
      expect(tools.length, equals(3));
      final names = tools.map((t) => t.name).toSet();
      expect(names, equals({'file_read', 'file_write', 'end'}));
    });

    test('builtinToolProvider 完全替换', () {
      final customProvider = _CustomBuiltinToolProvider();
      final sdk = WenzAgentSdk.builder()
          .builtinToolProvider(customProvider)
          .build();

      final tools = sdk.builtinToolProvider.provide();
      expect(tools.length, equals(2));
      expect(tools[0].name, equals('custom_a'));
      expect(tools[1].name, equals('custom_b'));
    });

    test('registerTool 注册自定义工具', () {
      final sdk = WenzAgentSdk.builder()
          .registerTool(_DummyTool('tool_1'))
          .build();

      expect(sdk.extraTools.length, equals(1));
      expect(sdk.extraTools[0].name, equals('tool_1'));
    });

    test('registerTools 批量注册自定义工具', () {
      final sdk = WenzAgentSdk.builder()
          .registerTools([
            _DummyTool('tool_a'),
            _DummyTool('tool_b'),
            _DummyTool('tool_c'),
          ])
          .build();

      expect(sdk.extraTools.length, equals(3));
      expect(sdk.extraTools.map((t) => t.name).toList(),
          equals(['tool_a', 'tool_b', 'tool_c']));
    });

    test('registerTool 多次调用累加', () {
      final sdk = WenzAgentSdk.builder()
          .registerTool(_DummyTool('tool_1'))
          .registerTool(_DummyTool('tool_2'))
          .registerTool(_DummyTool('tool_3'))
          .build();

      expect(sdk.extraTools.length, equals(3));
    });

    test('registerSkillFactory 注册工厂', () {
      final sdk = WenzAgentSdk.builder()
          .registerSkillFactory(_DummySkillFactory('type_a'))
          .registerSkillFactory(_DummySkillFactory('type_b'))
          .build();

      expect(sdk.skillFactories.length, equals(2));
      expect(sdk.skillFactories[0].typeKey, equals('type_a'));
      expect(sdk.skillFactories[1].typeKey, equals('type_b'));
    });

    test('registerSkill 注册自定义 Skill', () {
      final skill1 = _DummySkill(id: 's1', name: 'Skill 1');
      final sdk = WenzAgentSdk.builder()
          .registerSkill(skill1)
          .build();

      expect(sdk.extraSkills.length, equals(1));
      expect(sdk.extraSkills[0].name, equals('Skill 1'));
    });

    test('registerSkills 批量注册自定义 Skill', () {
      final sdk = WenzAgentSdk.builder()
          .registerSkills([
            _DummySkill(id: 's1', name: 'Skill 1'),
            _DummySkill(id: 's2', name: 'Skill 2'),
          ])
          .build();

      expect(sdk.extraSkills.length, equals(2));
    });

    test('mcpClientProvider 设置', () {
      final provider = _DummyMcpClientProvider();
      final sdk = WenzAgentSdk.builder()
          .mcpClientProvider(provider)
          .build();

      expect(sdk.mcpClientProvider, same(provider));
    });

    test('链式调用 - 完整配置', () {
      final sdk = WenzAgentSdk.builder()
          .excludeBuiltinTools(['bg_command'])
          .registerTool(_DummyTool('my_tool'))
          .registerSkillFactory(_DummySkillFactory('http_api'))
          .registerSkill(_DummySkill(id: 'echo', name: 'Echo'))
          .mcpClientProvider(_DummyMcpClientProvider())
          .build();

      expect(sdk.builtinToolProvider.provide().length, equals(22)); // 23 - 1
      expect(sdk.extraTools.length, equals(1));
      expect(sdk.skillFactories.length, equals(1));
      expect(sdk.extraSkills.length, equals(1));
      expect(sdk.mcpClientProvider, isNotNull);
    });

    test('builder 互斥覆盖 - 后设置的生效', () {
      final sdk = WenzAgentSdk.builder()
          .excludeBuiltinTools(['command_execute']) // 先设置 exclude
          .onlyBuiltinTools(['file_read', 'end'])   // 后设置 only，覆盖
          .build();

      final tools = sdk.builtinToolProvider.provide();
      expect(tools.length, equals(2));
      final names = tools.map((t) => t.name).toSet();
      expect(names, equals({'file_read', 'end'}));
    });

    test('返回的列表是不可变的', () {
      final sdk = WenzAgentSdk.builder()
          .registerTool(_DummyTool('tool_1'))
          .registerSkillFactory(_DummySkillFactory('type_a'))
          .build();

      // 列表应该是 unmodifiable
      expect(() => sdk.extraTools.add(_DummyTool('tool_2')), throwsA(anything));
      expect(() => sdk.skillFactories.add(_DummySkillFactory('type_b')), throwsA(anything));
      expect(() => sdk.extraSkills.add(_DummySkill(id: 'x', name: 'X')), throwsA(anything));
    });

    test('多次 build 互不影响', () {
      final builder = WenzAgentSdk.builder()
          .registerTool(_DummyTool('shared_tool'));

      final sdk1 = builder.build();
      final sdk2 = builder
          .registerTool(_DummyTool('extra_tool'))
          .build();

      expect(sdk1.extraTools.length, equals(1));
      expect(sdk2.extraTools.length, equals(2));
    });
  });

  group('WenzAgentSdk', () {
    test('getter 返回正确的值', () {
      final customProvider = _CustomBuiltinToolProvider();
      final mcpProvider = _DummyMcpClientProvider();
      final factory = _DummySkillFactory('test_type');
      final tool = _DummyTool('test_tool');
      final skill = _DummySkill(id: 'test_skill', name: 'Test');

      final sdk = WenzAgentSdk.builder()
          .builtinToolProvider(customProvider)
          .mcpClientProvider(mcpProvider)
          .registerSkillFactory(factory)
          .registerTool(tool)
          .registerSkill(skill)
          .build();

      expect(sdk.builtinToolProvider, same(customProvider));
      expect(sdk.mcpClientProvider, same(mcpProvider));
      expect(sdk.skillFactories, contains(factory));
      expect(sdk.extraTools, contains(tool));
      expect(sdk.extraSkills, contains(skill));
    });
  });
}

// ===== 测试辅助类 =====

class _DummyTool extends AgentTool {
  @override
  final String name;
  _DummyTool(this.name);

  @override
  String get description => 'Dummy: $name';

  @override
  Map<String, dynamic> get inputJsonSchema => {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.success('dummy: $name');
}

class _CustomBuiltinToolProvider implements BuiltinToolProvider {
  @override
  List<AgentTool> provide() => [_DummyTool('custom_a'), _DummyTool('custom_b')];
}

class _DummySkillFactory implements SkillFactory {
  @override
  final String typeKey;
  _DummySkillFactory(this.typeKey);

  @override
  Skill create(Map<String, dynamic> config) =>
      _DummySkill(id: config['id'] as String? ?? 'unknown', name: typeKey);
}

class _DummySkill implements Skill {
  final String _id;
  final String _name;
  _DummySkill({required String id, required String name}) : _id = id, _name = name;

  @override String get id => _id;
  @override String get name => _name;
  @override String get description => 'Dummy skill: $_name';
  @override SkillType get type => SkillType.custom;
  @override SkillStatus get status => SkillStatus.active;
  @override List<AgentTool> get tools => [];
  @override Future<void> initialize() async {}
  @override Future<void> activate() async {}
  @override Future<void> deactivate() async {}
  @override Future<void> dispose() async {}
  @override Future<bool> healthCheck() async => true;
}

class _DummyMcpClientProvider implements McpClientProvider {
  @override
  McpClient createClient(McpServerConfig config) =>
      throw UnimplementedError('Dummy provider');
}
