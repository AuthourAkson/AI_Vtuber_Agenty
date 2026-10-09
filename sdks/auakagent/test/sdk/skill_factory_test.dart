import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart' hide ToolResult;
import 'package:auakagent/src/agent/tool/agent_tool.dart' show AgentTool, ToolResult;
import 'package:auakagent/src/agent/tool/tool_registry.dart';
import 'package:auakagent/src/skill/skill.dart';
import 'package:auakagent/src/skill/skill_factory.dart';
import 'package:auakagent/src/skill/skill_manager.dart';
import 'package:auakagent/src/skill/skill_context.dart';

void main() {
  group('SkillType', () {
    test('custom 枚举值存在', () {
      expect(SkillType.values, contains(SkillType.custom));
      expect(SkillType.custom.name, equals('custom'));
    });

    test('包含所有原有类型', () {
      expect(SkillType.values, containsAll([
        SkillType.mcp,
        SkillType.folder,
        SkillType.config,
        SkillType.custom,
      ]));
    });
  });

  group('SkillFactory', () {
    test('typeKey 返回正确的标识', () {
      final factory = _DummySkillFactory('http_api');
      expect(factory.typeKey, equals('http_api'));
    });

    test('create 返回正确的 Skill 实例', () {
      final factory = _DummySkillFactory('http_api');
      final skill = factory.create({'id': 'test-1', 'name': 'Test Skill'});

      expect(skill, isA<Skill>());
      expect(skill.id, equals('test-1'));
      expect(skill.name, equals('Test Skill'));
      expect(skill.type, equals(SkillType.custom));
    });
  });

  group('SkillLifecycleManager', () {
    late SkillLifecycleManager manager;
    late ToolRegistry toolRegistry;

    setUp(() {
      toolRegistry = ToolRegistry();
      final context = SkillContext(
        toolRegistry: toolRegistry,
        employeeId: 'test-employee',
        invokeLlm: (prompt) async => 'mock response: $prompt',
        logger: (level, message) {},
      );
      manager = SkillLifecycleManager(context);
    });

    tearDown(() async {
      await manager.dispose();
    });

    test('registerSkillFactory 注册工厂', () {
      final factory = _DummySkillFactory('http_api');
      manager.registerSkillFactory(factory);

      expect(manager.getSkillFactory('http_api'), same(factory));
    });

    test('registerSkillFactory 多个不同 typeKey', () {
      final factory1 = _DummySkillFactory('http_api');
      final factory2 = _DummySkillFactory('graphql');
      manager.registerSkillFactory(factory1);
      manager.registerSkillFactory(factory2);

      expect(manager.skillFactories.length, equals(2));
      expect(manager.getSkillFactory('http_api'), same(factory1));
      expect(manager.getSkillFactory('graphql'), same(factory2));
    });

    test('registerSkillFactory 相同 typeKey 覆盖', () {
      final factory1 = _DummySkillFactory('http_api');
      final factory2 = _DummySkillFactory('http_api');
      manager.registerSkillFactory(factory1);
      manager.registerSkillFactory(factory2);

      expect(manager.skillFactories.length, equals(1));
      expect(manager.getSkillFactory('http_api'), same(factory2));
    });

    test('unregisterSkillFactory 注销工厂', () {
      final factory = _DummySkillFactory('http_api');
      manager.registerSkillFactory(factory);
      expect(manager.getSkillFactory('http_api'), isNotNull);

      manager.unregisterSkillFactory('http_api');
      expect(manager.getSkillFactory('http_api'), isNull);
    });

    test('unregisterSkillFactory 不存在的 key 不报错', () {
      expect(() => manager.unregisterSkillFactory('non_existent'), returnsNormally);
    });

    test('getSkillFactory 未注册返回 null', () {
      expect(manager.getSkillFactory('non_existent'), isNull);
    });

    test('loadSkillFromFactory 创建并加载 Skill', () async {
      final factory = _AlwaysInitSkillFactory('test_type');
      manager.registerSkillFactory(factory);

      await manager.loadSkillFromFactory('test_type', {
        'id': 'skill-1',
        'name': 'Test Skill',
      });

      final skills = manager.skills;
      expect(skills.length, equals(1));
      expect(skills[0].id, equals('skill-1'));
      expect(skills[0].name, equals('Test Skill'));
    });

    test('loadSkillFromFactory 工具注册到 ToolRegistry', () async {
      final factory = _ToolProducingSkillFactory('calculator');
      manager.registerSkillFactory(factory);

      await manager.loadSkillFromFactory('calculator', {
        'id': 'calc-1',
        'name': 'Calculator',
      });

      expect(toolRegistry.contains('calc_add'), isTrue);
      expect(toolRegistry.contains('calc_subtract'), isTrue);
    });

    test('loadSkillFromFactory 未注册工厂抛异常', () async {
      expect(
        () => manager.loadSkillFromFactory('non_existent', {}),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('loadSkillFromFactory 异常包含有用信息', () async {
      try {
        await manager.loadSkillFromFactory('missing_type', {});
        fail('应该抛出 ArgumentError');
      } catch (e) {
        expect(e, isA<ArgumentError>());
        expect(e.toString(), contains('missing_type'));
        expect(e.toString(), contains('SkillFactory'));
      }
    });

    test('skillFactories 返回所有已注册工厂', () {
      manager.registerSkillFactory(_DummySkillFactory('a'));
      manager.registerSkillFactory(_DummySkillFactory('b'));
      manager.registerSkillFactory(_DummySkillFactory('c'));

      final factories = manager.skillFactories;
      expect(factories.length, equals(3));
      expect(factories.map((f) => f.typeKey).toList(), equals(['a', 'b', 'c']));
    });

    test('dispose 清理工厂', () async {
      manager.registerSkillFactory(_DummySkillFactory('a'));
      manager.registerSkillFactory(_DummySkillFactory('b'));
      await manager.dispose();

      expect(manager.skillFactories, isEmpty);
      expect(manager.getSkillFactory('a'), isNull);
    });
  });
}

// ===== 测试辅助类 =====

class _DummySkillFactory implements SkillFactory {
  @override
  final String typeKey;
  _DummySkillFactory(this.typeKey);

  @override
  Skill create(Map<String, dynamic> config) => _DummySkill(
        id: config['id'] as String? ?? 'unknown',
        name: config['name'] as String? ?? 'Unnamed',
      );
}

/// 总是能成功 initialize 的 Skill 工厂
class _AlwaysInitSkillFactory implements SkillFactory {
  @override
  final String typeKey;
  _AlwaysInitSkillFactory(this.typeKey);

  @override
  Skill create(Map<String, dynamic> config) => _AlwaysInitSkill(
        id: config['id'] as String? ?? 'unknown',
        name: config['name'] as String? ?? 'Unnamed',
      );
}

class _AlwaysInitSkill implements Skill {
  final String _id;
  final String _name;
  _AlwaysInitSkill({required String id, required String name})
      : _id = id, _name = name;

  @override String get id => _id;
  @override String get name => _name;
  @override String get description => 'Test skill: $_name';
  @override SkillType get type => SkillType.custom;
  @override SkillStatus get status => SkillStatus.active;
  @override List<AgentTool> get tools => [];
  @override Future<void> initialize() async {}
  @override Future<void> activate() async {}
  @override Future<void> deactivate() async {}
  @override Future<void> dispose() async {}
  @override Future<bool> healthCheck() async => true;
}

/// 产生工具的 Skill 工厂
class _ToolProducingSkillFactory implements SkillFactory {
  @override
  final String typeKey;
  _ToolProducingSkillFactory(this.typeKey);

  @override
  Skill create(Map<String, dynamic> config) => _ToolProducingSkill(
        id: config['id'] as String? ?? 'unknown',
        name: config['name'] as String? ?? 'Unnamed',
      );
}

class _ToolProducingSkill implements Skill {
  final String _id;
  final String _name;
  _ToolProducingSkill({required String id, required String name})
      : _id = id, _name = name;

  @override String get id => _id;
  @override String get name => _name;
  @override String get description => 'Tool producing skill: $_name';
  @override SkillType get type => SkillType.custom;
  @override SkillStatus get status => SkillStatus.active;

  @override
  List<AgentTool> get tools => [
        _SimpleTool('calc_add', '加法运算'),
        _SimpleTool('calc_subtract', '减法运算'),
      ];

  @override Future<void> initialize() async {}
  @override Future<void> activate() async {}
  @override Future<void> deactivate() async {}
  @override Future<void> dispose() async {}
  @override Future<bool> healthCheck() async => true;
}

class _SimpleTool extends AgentTool {
  @override
  final String name;
  final String _desc;
  _SimpleTool(this.name, this._desc);

  @override
  String get description => _desc;

  @override
  Map<String, dynamic> get inputJsonSchema =>
      {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.success('$name result');
}

class _DummySkill implements Skill {
  final String _id;
  final String _name;
  _DummySkill({required String id, required String name})
      : _id = id, _name = name;

  @override String get id => _id;
  @override String get name => _name;
  @override String get description => 'Dummy: $_name';
  @override SkillType get type => SkillType.custom;
  @override SkillStatus get status => SkillStatus.uninitialized;
  @override List<AgentTool> get tools => [];
  @override Future<void> initialize() async {}
  @override Future<void> activate() async {}
  @override Future<void> deactivate() async {}
  @override Future<void> dispose() async {}
  @override Future<bool> healthCheck() async => true;
}
