import 'package:test/test.dart';
import 'package:auakagent/src/agent/adapter/llm_chat_adapter.dart';
import 'package:auakagent/src/agent/impl/agent_impl.dart';
import 'package:auakagent/src/agent/tool/agent_tool.dart' show AgentTool, ToolResult;
import 'package:auakagent/src/agent/tool/builtin_tool_provider.dart';
import 'package:auakagent/src/service/agent_factory.dart';
import 'package:auakagent/src/service/employee_manager.dart';
import 'package:auakagent/src/service/message_store_service.dart';
import 'package:auakagent/src/service/skill_manager.dart';

void main() {
  group('AgentImpl + BuiltinToolProvider', () {
    test('默认构造使用全部内置工具', () async {
      final chatAdapter = LlmChatAdapter();
      final agent = AgentImpl(
        employeeId: 'test-emp-1',
        deviceId: 'test-device-1',
        chatAdapter: chatAdapter,
      );

      await agent.initialize(employeeId: 'test-emp-1');

      // 默认应该注册了全部 23 个内置工具
      final tools = agent.getRegisteredTools();
      expect(tools.length, equals(23));

      final names = tools.map((t) => t['name'] as String).toSet();
      expect(names.contains('end'), isTrue);
      expect(names.contains('file_read'), isTrue);
      expect(names.contains('command_execute'), isTrue);

      await agent.dispose();
    });

    test('注入自定义 BuiltinToolProvider', () async {
      final chatAdapter = LlmChatAdapter();
      final provider = DefaultBuiltinToolProvider(
        only: {'file_read', 'file_write', 'end'},
      );

      final agent = AgentImpl(
        employeeId: 'test-emp-2',
        deviceId: 'test-device-2',
        chatAdapter: chatAdapter,
        builtinToolProvider: provider,
      );

      await agent.initialize(employeeId: 'test-emp-2');

      final tools = agent.getRegisteredTools();
      expect(tools.length, equals(3));

      final names = tools.map((t) => t['name'] as String).toSet();
      expect(names, equals({'file_read', 'file_write', 'end'}));

      await agent.dispose();
    });

    test('注入 exclude BuiltinToolProvider', () async {
      final chatAdapter = LlmChatAdapter();
      final provider = DefaultBuiltinToolProvider(
        exclude: {'command_execute', 'bg_command', 'git_operations'},
      );

      final agent = AgentImpl(
        employeeId: 'test-emp-3',
        deviceId: 'test-device-3',
        chatAdapter: chatAdapter,
        builtinToolProvider: provider,
      );

      await agent.initialize(employeeId: 'test-emp-3');

      final tools = agent.getRegisteredTools();
      expect(tools.length, equals(20)); // 23 - 3

      final names = tools.map((t) => t['name'] as String).toSet();
      expect(names.contains('command_execute'), isFalse);
      expect(names.contains('bg_command'), isFalse);
      expect(names.contains('git_operations'), isFalse);
      expect(names.contains('file_read'), isTrue);

      await agent.dispose();
    });

    test('enableBuiltinTools=false 不注册任何工具', () async {
      final chatAdapter = LlmChatAdapter();
      final agent = AgentImpl(
        employeeId: 'test-emp-4',
        deviceId: 'test-device-4',
        chatAdapter: chatAdapter,
      );

      await agent.initialize(
        employeeId: 'test-emp-4',
        enableBuiltinTools: false,
      );

      final tools = agent.getRegisteredTools();
      expect(tools, isEmpty);

      await agent.dispose();
    });

    test('registerTool 动态注册自定义工具', () async {
      final chatAdapter = LlmChatAdapter();
      final agent = AgentImpl(
        employeeId: 'test-emp-5',
        deviceId: 'test-device-5',
        chatAdapter: chatAdapter,
      );

      await agent.initialize(employeeId: 'test-emp-5');

      // 注册自定义工具
      agent.registerTool(_TestTool('my_custom_tool'));

      final tools = agent.getRegisteredTools();
      final names = tools.map((t) => t['name'] as String).toSet();
      expect(names.contains('my_custom_tool'), isTrue);
      // 原有工具仍在
      expect(names.contains('file_read'), isTrue);

      await agent.dispose();
    });

    test('unregisterTool 动态注销工具', () async {
      final chatAdapter = LlmChatAdapter();
      final agent = AgentImpl(
        employeeId: 'test-emp-6',
        deviceId: 'test-device-6',
        chatAdapter: chatAdapter,
      );

      await agent.initialize(employeeId: 'test-emp-6');

      // 注销工具
      agent.unregisterTool('command_execute');

      final tools = agent.getRegisteredTools();
      final names = tools.map((t) => t['name'] as String).toSet();
      expect(names.contains('command_execute'), isFalse);
      expect(tools.length, equals(22)); // 23 - 1

      await agent.dispose();
    });
  });

  group('AgentFactoryImpl SDK 配置注入', () {
    test('构造函数接受 SDK 配置参数', () {
      // 验证 AgentFactoryImpl 可以接受 SDK 配置
      final provider = DefaultBuiltinToolProvider(
        only: {'file_read', 'end'},
      );

      // 不实际创建（需要数据库），只验证构造不报错
      expect(
        () => AgentFactoryImpl(
          employeeManager: _MockEmployeeManager(),
          messageStore: _MockMessageStoreService(),
          skillManager: _MockSkillManager(),
          builtinToolProvider: provider,
          extraTools: [_TestTool('custom_1'), _TestTool('custom_2')],
          skillFactories: [],
          extraSkills: [],
        ),
        returnsNormally,
      );
    });
  });
}

// ===== 测试辅助类 =====

class _TestTool extends AgentTool {
  @override
  final String name;
  _TestTool(this.name);

  @override
  String get description => 'Test tool: $name';

  @override
  Map<String, dynamic> get inputJsonSchema =>
      {'type': 'object', 'properties': {}};

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async =>
      ToolResult.success('test: $name');
}

// Mock 类 — 仅用于构造函数签名测试，不实际调用方法
class _MockEmployeeManager implements EmployeeManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockMessageStoreService implements MessageStoreService {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MockSkillManager implements SkillManager {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
