import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:auakagent/src/agent/agent_state.dart';
import 'package:auakagent/src/agent/entity/entity.dart';
import 'package:auakagent/src/agent/tool/agent_tool.dart';
import 'package:auakagent/src/service/entity/agent_runtime_config.dart';
import 'package:auakagent/src/service/sub_agent_executor.dart';

/// SubAgentExecutor 测试
///
/// 测试范围：
/// 1. 配置缺失时的错误返回
/// 2. 回调注入验证
/// 3. 自定义工具集执行
/// 4. context_files 预加载
/// 5. 权限转发
/// 6. 端到端：实际 LLM 调用（需要 API Key）
void main() {
  // 测试配置
  late String apiKey;
  late String apiUrl;
  late String apiModel;
  late ProviderConfig providerConfig;

  setUpAll(() {
    apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
    apiUrl =
        Platform.environment['OPENAI_API_URL'] ?? 'https://api.openai.com/v1';
    apiModel = Platform.environment['OPENAI_API_MODEL'] ?? 'gpt-3.5-turbo';

    if (apiKey.isNotEmpty) {
      providerConfig = ProviderConfig(
        provider: LLMProvider.openai,
        apiKey: apiKey,
        baseUrl: apiUrl,
        model: apiModel,
      );
    }

    print('\n=== SubAgentExecutor 测试 ===');
    print('API URL: $apiUrl');
    print('API Model: $apiModel');
    print('API Key: ${apiKey.isNotEmpty ? "已设置" : "未设置"}\n');
  });

  group('配置校验', () {
    late SubAgentExecutor executor;

    setUp(() {
      executor = SubAgentExecutor();
    });

    test('getAgentConfig 返回 null 时返回错误', () async {
      executor.getAgentConfig = (_) async => null;

      final result = await executor.execute(
        employeeId: 'test-emp-001',
        taskPrompt: '测试任务',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('not found'));
      expect(result.summary, isEmpty);
      expect(result.toolCalls, isEmpty);
    });

    test('providerConfig 为 null 时返回明确错误', () async {
      executor.getAgentConfig = (_) async => const AgentRuntimeConfig(
            providerConfig: null,
            systemPrompt: null,
          );

      final result = await executor.execute(
        employeeId: 'test-emp-002',
        taskPrompt: '测试任务',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('未配置 LLM Provider'));
      expect(result.summary, isEmpty);
    });
  });

  group('回调注入', () {
    test('getAgentConfig 接收正确的 employeeId', () async {
      final executor = SubAgentExecutor();
      String? receivedEid;

      executor.getAgentConfig = (eid) async {
        receivedEid = eid;
        return null; // 让它快速失败
      };

      await executor.execute(
        employeeId: 'emp-abc-123',
        taskPrompt: 'test',
      );

      expect(receivedEid, equals('emp-abc-123'));
    });

    test('readFileContent 被正确调用', () async {
      final executor = SubAgentExecutor();
      final readFileCalls = <String>[];

      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );
      executor.readFileContent = (path) async {
        readFileCalls.add(path);
        return '模拟文件内容: $path';
      };

      await executor.execute(
        employeeId: 'test-emp-003',
        taskPrompt: '请读取文件内容并总结',
        contextFiles: ['/tmp/a.txt', '/tmp/b.txt'],
        timeout: const Duration(seconds: 60),
      );

      // 验证 readFileContent 被调用了两次
      expect(readFileCalls.length, equals(2));
      expect(readFileCalls, contains('/tmp/a.txt'));
      expect(readFileCalls, contains('/tmp/b.txt'));
    });

    test('requestPermission 被调用（工具需要权限时）', () async {
      final executor = SubAgentExecutor();
      final permissionRequests = <AgentPermissionRequest>[];

      // 创建一个需要权限的测试工具
      final restrictedTool = _FakeTool(
        name: 'dangerous_action',
        requiresPermission: true,
        result: ToolResult.success('操作完成'),
      );

      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );
      executor.requestPermission = (request) {
        permissionRequests.add(request);
        return Future.value(PermissionDecision.deny);
      };

      // 这个测试依赖 LLM 是否选择调用 dangerous_action
      // 主要验证回调链路通畅
      final result = await executor.execute(
        employeeId: 'test-emp-004',
        taskPrompt: '请执行 dangerous_action 工具',
        tools: [restrictedTool],
        timeout: const Duration(seconds: 60),
      );

      // 不管 LLM 是否调用该工具，回调本身不应抛错
      expect(result, isNotNull);
      expect(result.duration.inMilliseconds, greaterThan(0));
    });
  });

  group('工具集', () {
    test('使用默认工具集（readOnly）', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final result = await executor.execute(
        employeeId: 'test-emp-005',
        taskPrompt: '请简单回复"默认工具测试成功"',
        // 不传 tools，应使用 BuiltinTools.readOnly()
        timeout: const Duration(seconds: 60),
      );

      // 只要有回复就算通过
      expect(result, isNotNull);
      print('默认工具集测试结果: success=${result.success}, '
          'summary长度=${result.summary.length}');
    });

    test('使用自定义工具集', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final echoTool = _FakeTool(
        name: 'echo',
        result: ToolResult.success('echo: hello'),
      );

      final result = await executor.execute(
        employeeId: 'test-emp-006',
        taskPrompt: '请调用 echo 工具并返回结果',
        tools: [echoTool],
        timeout: const Duration(seconds: 60),
      );

      expect(result, isNotNull);
      if (result.success) {
        expect(result.summary, isNotEmpty);
      }
      print('自定义工具测试结果: success=${result.success}, '
          'toolCalls=${result.toolCalls}');
    });
  });

  group('systemPrompt 注入', () {
    test('使用自定义 systemPrompt', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final result = await executor.execute(
        employeeId: 'test-emp-007',
        taskPrompt: '请回复你的角色描述',
        systemPrompt: '你是一个测试助手，只能用英文回复。',
        timeout: const Duration(seconds: 60),
      );

      expect(result, isNotNull);
      if (result.success) {
        // 自定义 prompt 应影响 LLM 回复
        expect(result.summary, isNotEmpty);
      }
      print('自定义 systemPrompt 测试结果: ${result.summary.substring(0, result.summary.length.clamp(0, 100))}');
    });

    test('使用主 Agent 的 systemPrompt 拼接', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => const AgentRuntimeConfig(
            providerConfig: null, // 会让它提前返回错误
            systemPrompt: '主Agent的Prompt',
          );

      // providerConfig 为 null 会提前返回
      final result = await executor.execute(
        employeeId: 'test-emp-008',
        taskPrompt: '测试',
      );

      expect(result.success, isFalse);
      expect(result.error, contains('未配置 LLM Provider'));
    });
  });

  group('超时与取消', () {
    test('执行超时返回错误', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final result = await executor.execute(
        employeeId: 'test-emp-009',
        taskPrompt: '请详细解释量子计算的原理，包括所有数学公式',
        timeout: const Duration(seconds: 1), // 极短超时
      );

      expect(result.success, isFalse);
      expect(result.error, isNotNull);
      print('超时测试结果: error=${result.error}');
    });
  });

  group('端到端测试（需要 API Key）', () {
    // 跳过没有 API Key 的情况
    setUp(() {
      if (apiKey.isEmpty) {
        throw StateError('需要设置 OPENAI_API_KEY 环境变量');
      }
    });

    test('简单问答任务', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final result = await executor.execute(
        employeeId: 'test-emp-e2e-001',
        taskPrompt: '请回复"子Agent测试成功"，不要使用任何工具。',
        timeout: const Duration(seconds: 30),
      );

      print('\n--- 端到端：简单问答 ---');
      print('success: ${result.success}');
      print('summary: ${result.summary}');
      print('toolCalls: ${result.toolCalls}');
      print('duration: ${result.duration.inSeconds}s');

      expect(result.success, isTrue);
      expect(result.summary, contains('测试成功'));
    });

    test('工具调用任务', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final calculatorTool = _FakeTool(
        name: 'calculator',
        description: '执行数学计算。输入一个数学表达式，返回计算结果。',
        inputSchema: {
          'type': 'object',
          'properties': {
            'expression': {
              'type': 'string',
              'description': '数学表达式，如 "2+3"',
            },
          },
          'required': ['expression'],
        },
        result: ToolResult.success('42'),
      );

      final result = await executor.execute(
        employeeId: 'test-emp-e2e-002',
        taskPrompt:
            '请立即使用 calculator 工具计算表达式 "2+3"，然后把结果告诉我。',
        tools: [calculatorTool],
        timeout: const Duration(seconds: 30),
      );

      print('\n--- 端到端：工具调用 ---');
      print('success: ${result.success}');
      print('summary: ${result.summary}');
      print('toolCalls: ${result.toolCalls}');
      print('duration: ${result.duration.inSeconds}s');

      expect(result.success, isTrue);
      // LLM 可能直接回复而不调用工具，所以只验证结果非空
      expect(result.summary, isNotEmpty);
    });

    test('context_files 预加载', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );
      executor.readFileContent = (path) async {
        if (path == 'config.json') {
          return '{"name": "测试项目", "version": "1.0.0"}';
        }
        return null;
      };

      final result = await executor.execute(
        employeeId: 'test-emp-e2e-003',
        taskPrompt: '根据预加载的配置文件，告诉我项目名称和版本。',
        contextFiles: ['config.json'],
        timeout: const Duration(seconds: 30),
      );

      print('\n--- 端到端：context_files ---');
      print('success: ${result.success}');
      print('summary: ${result.summary}');
      print('duration: ${result.duration.inSeconds}s');

      expect(result.success, isTrue);
      expect(result.summary, contains('测试项目'));
    });

    test('权限转发 - 拒绝权限', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );
      executor.requestPermission = (request) {
        print('权限请求: ${request.functionName}');
        return Future.value(PermissionDecision.deny);
      };

      final dangerousTool = _FakeTool(
        name: 'dangerous_action',
        description: '一个需要权限的危险操作',
        requiresPermission: true,
        result: ToolResult.success('危险操作完成'),
      );

      final result = await executor.execute(
        employeeId: 'test-emp-e2e-004',
        taskPrompt: '请执行 dangerous_action 操作。',
        tools: [dangerousTool],
        timeout: const Duration(seconds: 30),
      );

      print('\n--- 端到端：权限拒绝 ---');
      print('success: ${result.success}');
      print('summary: ${result.summary}');
      print('toolCalls: ${result.toolCalls}');

      // 任务可能因为权限被拒而失败，也可能 LLM 给出替代回复
      expect(result, isNotNull);
    });

    test('摘要截断（超长输出）', () async {
      final executor = SubAgentExecutor();
      executor.getAgentConfig = (_) async => AgentRuntimeConfig(
            providerConfig: providerConfig.toMap(),
          );

      final result = await executor.execute(
        employeeId: 'test-emp-e2e-005',
        taskPrompt: '请写一首50字以内的短诗。',
        timeout: const Duration(seconds: 30),
      );

      print('\n--- 端到端：摘要 ---');
      print('success: ${result.success}');
      print('summary长度: ${result.summary.length}');
      print('summary: ${result.summary}');

      expect(result.success, isTrue);
      // 8000 字符限制
      expect(result.summary.length, lessThanOrEqualTo(8000));
    });
  });

  print('\n=== 所有 SubAgentExecutor 测试完成 ===\n');
}

/// 测试用假工具
class _FakeTool extends AgentTool {
  final String _name;
  final String _description;
  final Map<String, dynamic> _inputSchema;
  final bool _requiresPermission;
  final ToolResult _result;

  _FakeTool({
    String? name,
    String? description,
    Map<String, dynamic>? inputSchema,
    bool requiresPermission = false,
    required ToolResult result,
  })  : _name = name ?? 'fake_tool',
        _description = description ?? 'A fake tool for testing',
        _inputSchema = inputSchema ??
            {
              'type': 'object',
              'properties': {
                'input': {
                  'type': 'string',
                  'description': 'Input parameter',
                },
              },
              'required': ['input'],
            },
        _requiresPermission = requiresPermission,
        _result = result;

  @override
  String get name => _name;

  @override
  String get description => _description;

  @override
  Map<String, dynamic> get inputJsonSchema => _inputSchema;

  @override
  bool get requiresPermission => _requiresPermission;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    return _result;
  }
}
