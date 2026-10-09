import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart' hide ToolResult;
import 'package:auakagent/src/agent/tool/agent_tool.dart' show AgentTool, ToolResult;
import 'package:auakagent/src/agent/tool/builtin/builtin_tools.dart';
import 'package:auakagent/src/agent/tool/builtin_tool_provider.dart';

void main() {
  group('DefaultBuiltinToolProvider', () {
    test('默认构造返回全部内置工具', () {
      final provider = DefaultBuiltinToolProvider();
      final tools = provider.provide();

      expect(tools.length, equals(23));
      // 验证包含关键工具
      final names = tools.map((t) => t.name).toSet();
      expect(names.contains('end'), isTrue);
      expect(names.contains('file_read'), isTrue);
      expect(names.contains('file_write'), isTrue);
      expect(names.contains('command_execute'), isTrue);
      expect(names.contains('web_search_prime'), isTrue);
    });

    test('only 白名单过滤 - 只返回指定工具', () {
      final provider = DefaultBuiltinToolProvider(
        only: {'file_read', 'file_write', 'end'},
      );
      final tools = provider.provide();

      expect(tools.length, equals(3));
      final names = tools.map((t) => t.name).toSet();
      expect(names, equals({'file_read', 'file_write', 'end'}));
    });

    test('only 白名单过滤 - 空集合返回空列表', () {
      final provider = DefaultBuiltinToolProvider(only: {});
      final tools = provider.provide();

      expect(tools, isEmpty);
    });

    test('only 白名单过滤 - 不存在的名称被忽略', () {
      final provider = DefaultBuiltinToolProvider(
        only: {'file_read', 'non_existent_tool'},
      );
      final tools = provider.provide();

      expect(tools.length, equals(1));
      expect(tools.first.name, equals('file_read'));
    });

    test('exclude 黑名单过滤 - 排除指定工具', () {
      final provider = DefaultBuiltinToolProvider(
        exclude: {'command_execute', 'bg_command', 'git_operations'},
      );
      final tools = provider.provide();

      expect(tools.length, equals(20)); // 23 - 3
      final names = tools.map((t) => t.name).toSet();
      expect(names.contains('command_execute'), isFalse);
      expect(names.contains('bg_command'), isFalse);
      expect(names.contains('git_operations'), isFalse);
      expect(names.contains('file_read'), isTrue);
    });

    test('exclude 黑名单过滤 - 空集合返回全部', () {
      final provider = DefaultBuiltinToolProvider(exclude: {});
      final tools = provider.provide();

      expect(tools.length, equals(23));
    });

    test('only 优先于 exclude', () {
      final provider = DefaultBuiltinToolProvider(
        only: {'file_read', 'file_write'},
        exclude: {'file_read'}, // 应被忽略
      );
      final tools = provider.provide();

      // only 优先，exclude 被忽略
      expect(tools.length, equals(2));
      final names = tools.map((t) => t.name).toSet();
      expect(names, equals({'file_read', 'file_write'}));
    });

    test('返回的工具都是 AgentTool 实例', () {
      final provider = DefaultBuiltinToolProvider();
      final tools = provider.provide();

      for (final tool in tools) {
        expect(tool, isA<AgentTool>());
        expect(tool.name, isNotEmpty);
        expect(tool.description, isNotEmpty);
      }
    });

    test('多次调用返回独立的列表', () {
      final provider = DefaultBuiltinToolProvider();
      final tools1 = provider.provide();
      final tools2 = provider.provide();

      expect(tools1.length, equals(tools2.length));
      expect(identical(tools1, tools2), isFalse);
    });
  });

  group('BuiltinToolProvider 接口', () {
    test('自定义实现', () {
      final customProvider = _CustomBuiltinToolProvider([
        _DummyTool('custom_tool_1'),
        _DummyTool('custom_tool_2'),
      ]);

      final tools = customProvider.provide();
      expect(tools.length, equals(2));
      expect(tools[0].name, equals('custom_tool_1'));
      expect(tools[1].name, equals('custom_tool_2'));
    });
  });
}

/// 自定义 BuiltinToolProvider 测试实现
class _CustomBuiltinToolProvider implements BuiltinToolProvider {
  final List<AgentTool> _tools;
  _CustomBuiltinToolProvider(this._tools);

  @override
  List<AgentTool> provide() => _tools;
}

/// 测试用 dummy 工具
class _DummyTool extends AgentTool {
  @override
  final String name;

  _DummyTool(this.name);

  @override
  String get description => 'Dummy tool: $name';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {},
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    return ToolResult.success('dummy result from $name');
  }
}
