import 'dart:async';
import 'dart:io';

import 'package:llm_dart/llm_dart.dart' as llm;
import 'package:test/test.dart';
import 'package:auakagent/src/agent/adapter/llm_chat_adapter.dart';
import 'package:auakagent/src/agent/agent_state.dart';
import 'package:auakagent/src/agent/client/agent_proxy.dart';
import 'package:auakagent/src/agent/client/cached_agent_proxy.dart';
import 'package:auakagent/src/agent/entity/entity.dart';
import 'package:auakagent/src/agent/impl/agent_impl.dart';
import 'package:auakagent/src/persistence/persistence.dart';
import 'package:auakagent/src/service/message_store_service.dart';

/// LLM 工具调用测试
///
/// 环境变量（两套配置，按 TOOL_CALL_LLM 选择）：
///
/// 默认 (TOOL_CALL_LLM=openai):
///   OPENAI_API_KEY, OPENAI_API_URL, OPENAI_API_MODEL
///
/// Anthropic/DeepSeek (TOOL_CALL_LLM=anthropic):
///   anthropic_api_key, anthropic_api_url, anthropic_api_model
void main() {
  // 测试配置
  late String apiKey;
  late String apiUrl;
  late String apiModel;
  late LLMProvider apiProvider;
  late ProviderConfig providerConfig;
  late String? customSystemPrompt;

  // 测试组件
  late AgentImpl agent;
  late AgentProxy localProxy;
  late CachedAgentProxy cachedProxy;
  late MessageStoreService messageStore;
  late String employeeId;
  late String deviceId;

  setUpAll(() async {
    // 选择使用哪套环境变量配置
    final llmChoice = Platform.environment['TOOL_CALL_LLM'] ?? 'openai';

    if (llmChoice == 'anthropic') {
      apiKey = Platform.environment['anthropic_api_key'] ?? '';
      apiUrl = Platform.environment['anthropic_api_url'] ?? 'https://api.anthropic.com';
      apiModel = Platform.environment['anthropic_api_model'] ?? 'claude-sonnet-4-20250514';
      apiProvider = LLMProvider.anthropic;
    } else {
      apiKey = Platform.environment['OPENAI_API_KEY'] ?? '';
      apiUrl = Platform.environment['OPENAI_API_URL'] ?? 'https://api.openai.com/v1';
      apiModel = Platform.environment['OPENAI_API_MODEL'] ?? 'gpt-4o';
      apiProvider = LLMProvider.openai;
    }

    customSystemPrompt = Platform.environment['TOOL_CALL_TEST_PROMPT'];

    if (apiKey.isEmpty) {
      throw Exception('请设置环境变量（OPENAI_API_KEY 或 anthropic_api_key）');
    }

    // 生成测试 ID
    deviceId = 'tool-test-${DateTime.now().millisecondsSinceEpoch}';
    employeeId = 'emp-${DateTime.now().millisecondsSinceEpoch}';

    print('\n=== 工具调用测试配置 ===');
    print('LLM 配置: $llmChoice');
    print('Provider: ${apiProvider.name}');
    print('API URL: $apiUrl');
    print('API Model: $apiModel');
    print('Device ID: $deviceId');
    print('Employee ID: $employeeId');

    // 预先验证 LLM 连接（快速失败）
    print('\n--- 预检：验证 LLM 连接 ---');
    try {
      final builder = llm.ai();
      switch (apiProvider) {
        case LLMProvider.openai:
          builder.openai();
        case LLMProvider.anthropic:
          builder.anthropic();
        case LLMProvider.google:
          builder.google();
        case LLMProvider.ollama:
          builder.ollama();
        case LLMProvider.deepseek:
          builder.deepseek();
      }
      builder.model(apiModel);
      builder.apiKey(apiKey);
      builder.baseUrl(apiUrl);
      builder.enableLogging(true);
      final capability = await builder.build();
      final response = await capability.chat([
        llm.ChatMessage.user('请回复"连接成功"'),
      ]);
      print('LLM 连接验证: ${response.text}');
      expect(response.text, isNotEmpty, reason: 'LLM 应该有回复');
      print('✅ LLM 连接正常\n');
    } catch (e) {
      print('❌ LLM 连接失败: $e');
      rethrow;
    }

    // 配置 Provider
    providerConfig = ProviderConfig(
      provider: apiProvider,
      apiKey: apiKey,
      baseUrl: apiUrl,
      model: apiModel,
    );

    // 初始化数据库 —— 使用 deviceId 作为 DatabaseManager 实例名
    await DatabaseManager.getInstance(deviceId).initialize(
      storagePath: 'D:\\project\\GitHub\\wenzagent\\test_db',
    );

    print('');
  });

  setUp(() async {
    // 每个测试前创建新的 Agent 实例
    messageStore = MessageStoreServiceImpl(deviceId: deviceId);

    // 创建适配器并配置持久化
    final adapter = LlmChatAdapter();
    adapter.configurePersistence(
      messageStore: messageStore,
      deviceId: deviceId,
    );
    // 必须显式设置 deviceId（DeviceAgentManager._setupAdapter 也会做这一步）
    adapter.deviceId = deviceId;

    // 创建 Agent
    agent = AgentImpl(
      employeeId: employeeId,
      deviceId: deviceId,
      chatAdapter: adapter,
    );

    // 启用内置工具
    await agent.initialize(enableBuiltinTools: true);

    // 设置 Provider（内部调用 updateProvider → _buildChatCapability）
    await agent.setProvider(providerConfig);

    // 设置上下文（含自定义系统提示词）
    final context = <String, dynamic>{
      'systemPrompt': customSystemPrompt ?? _defaultSystemPrompt(),
      'projectName': 'wenzagent-tool-test',
      'workPath': Directory.current.path,
    };
    await agent.setContext(context);

    // 创建 AgentProxy (本地模式)
    localProxy = AgentProxy.local(
      employeeId: employeeId,
      deviceId: deviceId,
      localAgent: agent,
    );

    // 创建 CachedAgentProxy
    cachedProxy = CachedAgentProxy(
      proxy: localProxy,
      messageStore: messageStore,
      deviceId: deviceId,
      employeeId: employeeId,
    );

    await cachedProxy.initialize();
  });

  tearDown(() async {
    await cachedProxy.dispose();
    await localProxy.dispose();
    await agent.dispose();
    await messageStore.deleteMessages(deviceId, employeeId);
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance(deviceId).close();
  });

  // ============================================================
  // 辅助方法：从消息列表中提取所有被调用的工具名
  // ============================================================

  /// 从消息列表中提取所有 assistant 消息中的 toolCalls 名称
  List<String> _extractToolCallNames(List<AgentMessage> messages) {
    final names = <String>[];
    for (final msg in messages) {
      if (msg.role == 'assistant' && msg.toolCalls != null) {
        for (final tc in msg.toolCalls!) {
          if (tc.name.isNotEmpty) {
            names.add(tc.name);
          }
        }
      }
      // 兼容单工具调用格式
      if (msg.role == 'assistant' && msg.toolName != null && msg.toolName!.isNotEmpty) {
        if (!names.contains(msg.toolName)) {
          names.add(msg.toolName!);
        }
      }
    }
    return names;
  }

  /// 从消息列表中找到最后一条有文本内容的 assistant 消息
  AgentMessage? _findLastTextAssistant(List<AgentMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m.role == 'assistant' && m.content != null && m.content!.trim().isNotEmpty) {
        return m;
      }
    }
    return null;
  }

  /// 发送消息并等待完成，返回消息列表
  Future<List<AgentMessage>> _sendAndWait(
    String content, {
    Duration timeout = const Duration(seconds: 120),
  }) async {
    final messageId = await cachedProxy.sendMessage(MessageInput(content: content));
    print('  发送消息ID: $messageId');
    await _waitForIdle(cachedProxy, timeout: timeout);
    final messages = await cachedProxy.getMessages();
    return messages;
  }

  group('工具调用基础测试', () {
    test('✅ LLM 调用 env_info 工具获取环境信息', () async {
      print('\n--- 测试：LLM 调用 env_info 工具 ---');

      final messages = await _sendAndWait(
        '请使用 env_info 工具查询当前系统环境信息（info_type 设为 "system"），然后把结果告诉我。',
      );

      print('  消息数量: ${messages.length}');
      for (final msg in messages) {
        final content = msg.content ?? '';
        final preview = content.length > 150 ? '${content.substring(0, 150)}...' : content;
        print('  [${msg.role}] $preview');
      }

      // 从消息中提取工具调用
      final toolNames = _extractToolCallNames(messages);
      print('  工具调用列表: $toolNames');

      // 验证调用了 env_info
      expect(toolNames.contains('env_info'), isTrue,
          reason: '应该调用了 env_info 工具');

      // 验证有助手回复
      final lastReply = _findLastTextAssistant(messages);
      expect(lastReply, isNotNull, reason: '应该有助手文本回复');
      expect(lastReply!.content, isNotEmpty);

      print('  助手回复: ${lastReply.content}');
      print('  ✅ 通过\n');
    });

    test('✅ LLM 调用 file_read 工具读取文件', () async {
      print('\n--- 测试：LLM 调用 file_read 工具 ---');

      final messages = await _sendAndWait(
        '请使用 file_read 工具读取文件 D:\\\\project\\\\GitHub\\\\wenzagent\\\\pubspec.yaml 的内容，然后告诉我项目名称和版本号。',
      );

      final toolNames = _extractToolCallNames(messages);
      print('  工具调用列表: $toolNames');

      expect(toolNames.contains('file_read'), isTrue,
          reason: '应该调用了 file_read 工具');

      final lastReply = _findLastTextAssistant(messages);
      expect(lastReply, isNotNull);
      expect(lastReply!.content, isNotEmpty);

      print('  助手回复: ${lastReply.content}');
      print('  ✅ 通过\n');
    });

    test('✅ LLM 调用 file_list 工具列出目录', () async {
      print('\n--- 测试：LLM 调用 file_list 工具 ---');

      final messages = await _sendAndWait(
        '请使用 file_list 工具列出 D:\\\\project\\\\GitHub\\\\wenzagent\\\\lib 目录下的文件，然后告诉我有哪些文件和子目录。',
      );

      final toolNames = _extractToolCallNames(messages);
      print('  工具调用列表: $toolNames');

      expect(toolNames.contains('file_list'), isTrue,
          reason: '应该调用了 file_list 工具');

      final lastReply = _findLastTextAssistant(messages);
      expect(lastReply, isNotNull);
      expect(lastReply!.content, isNotEmpty);

      print('  助手回复: ${lastReply.content}');
      print('  ✅ 通过\n');
    });
  });

  group('项目分析场景测试', () {
    test('✅ 分析项目结构并汇报', () async {
      print('\n--- 测试：分析 wenzagent 项目结构 ---');

      final messages = await _sendAndWait(
        '请分析项目 D:\\\\project\\\\GitHub\\\\wenzagent 的结构：\n'
            '1. 先用 file_list 列出项目根目录\n'
            '2. 再用 file_list 列出 lib/src 目录\n'
            '3. 用 file_read 读取 pubspec.yaml\n'
            '然后简要汇报这是什么项目、用了哪些主要依赖。',
        timeout: const Duration(seconds: 180),
      );

      final toolNames = _extractToolCallNames(messages);
      final uniqueTools = toolNames.toSet();
      print('  调用的工具: $uniqueTools');

      // 验证调用了多个不同的工具
      expect(uniqueTools.length, greaterThanOrEqualTo(2),
          reason: '分析项目应该调用至少 2 个工具');

      // 验证有 file_list 和 file_read
      expect(uniqueTools.contains('file_list') || uniqueTools.contains('file_read'), isTrue,
          reason: '分析项目应该调用 file_list 或 file_read');

      final lastReply = _findLastTextAssistant(messages);
      expect(lastReply, isNotNull);
      final content = lastReply!.content ?? '';
      final preview = content.length > 300 ? '${content.substring(0, 300)}...' : content;
      print('  助手回复: $preview');
      print('  ✅ 通过\n');
    });
  });

  group('自定义提示词测试', () {
    test('✅ 使用自定义提示词引导工具调用', () async {
      print('\n--- 测试：自定义提示词引导工具调用 ---');

      // 重新设置上下文，使用自定义提示词
      final customContext = <String, dynamic>{
        'systemPrompt': _customToolTestPrompt(),
        'projectName': 'wenzagent-tool-test',
        'workPath': Directory.current.path,
      };
      await agent.setContext(customContext);

      final messages = await _sendAndWait(
        '请帮我查看 D:\\\\project\\\\GitHub\\\\wenzagent 目录下有哪些文件和目录。',
      );

      expect(messages.length, greaterThanOrEqualTo(2));

      final toolNames = _extractToolCallNames(messages);
      print('  工具调用列表: $toolNames');

      // 在自定义提示词引导下，LLM 应该会调用工具
      expect(toolNames.isNotEmpty, isTrue,
          reason: '自定义提示词引导下应该调用工具');

      print('  ✅ 通过\n');
    });
  });

  group('工具调用结果验证', () {
    test('✅ 验证工具调用消息结构完整性', () async {
      print('\n--- 测试：工具调用消息结构 ---');

      final messageId = await cachedProxy.sendMessage(MessageInput(
        content: '请使用 env_info 工具查询系统环境信息（info_type 设为 "system"），简要汇报。',
      ));
      print('  发送消息ID: $messageId');

      await _waitForIdle(cachedProxy, timeout: const Duration(seconds: 120));

      final messages = await cachedProxy.getMessages();
      print('  消息数量: ${messages.length}');

      // 验证消息结构: user → assistant(toolCalls) → ... → assistant(text)
      expect(messages.length, greaterThanOrEqualTo(3),
          reason: '应该有用户消息、工具调用消息和助手回复');

      // 检查用户消息
      final userMsg = messages.firstWhere((m) => m.role == 'user');
      expect(userMsg.id, equals(messageId));
      expect(userMsg.content, isNotEmpty);
      print('  用户消息: OK');

      // 检查是否有带 toolCalls 的 assistant 消息
      final toolCallMsg = messages.where((m) =>
        m.role == 'assistant' && m.toolCalls != null && m.toolCalls!.isNotEmpty
      ).firstOrNull;
      expect(toolCallMsg, isNotNull, reason: '应该有带 toolCalls 的 assistant 消息');
      expect(toolCallMsg!.toolCalls!.isNotEmpty, isTrue);
      print('  工具调用消息: OK (${toolCallMsg.toolCalls!.length} calls)');
      for (final tc in toolCallMsg.toolCalls!) {
        print('    - ${tc.name}(${tc.arguments})');
      }

      // 检查至少有一条 assistant 消息有文本内容
      final hasTextContent = messages
          .where((m) => m.role == 'assistant')
          .any((m) => m.content != null && m.content!.trim().isNotEmpty);
      expect(hasTextContent, isTrue, reason: '至少有一条 assistant 消息有非空 content');
      print('  最终回复: OK');

      print('  ✅ 通过\n');
    });

    test('✅ 验证状态变化包含 processing 状态', () async {
      print('\n--- 测试：工具调用时的状态变化 ---');

      final states = <AgentStateSnapshot>[];
      final completer = Completer<void>();

      cachedProxy.onStateChanged.listen((state) {
        states.add(state);
        print('  状态: ${state.status}');

        if (state.status == AgentStatus.idle && states.length > 1) {
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      });

      await cachedProxy.sendMessage(MessageInput(
        content: '请使用 env_info 查询系统信息然后告诉我。',
      ));

      await completer.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw TimeoutException('等待状态变化超时'),
      );

      expect(states.isNotEmpty, isTrue);

      final hasProcessing = states.any((s) =>
        s.status == AgentStatus.processing ||
        s.status == AgentStatus.streaming
      );
      expect(hasProcessing, isTrue, reason: '应该包含处理中状态');

      expect(states.last.status, equals(AgentStatus.idle));

      print('  状态序列: ${states.map((s) => s.status.name).join(' -> ')}');
      print('  ✅ 通过\n');
    });
  });

  print('\n=== 所有工具调用测试完成 ===\n');
}

/// 默认系统提示词
String _defaultSystemPrompt() {
  return '你是一个工具调用测试助手。你的任务是正确调用工具来完成任务。'
      '当用户要求你使用某个工具时，你必须调用该工具而不是直接回答。'
      '完成任务后，调用 end 工具结束。';
}

/// 自定义工具测试提示词（模拟更严格的工具使用场景）
String _customToolTestPrompt() {
  return '你是一个高效的文件系统分析助手。你必须使用工具来获取信息，不要凭记忆回答。'
      '当用户询问文件或目录信息时，你总是先调用 file_list 或 file_read 工具获取最新数据。'
      '完成任务后，简洁地汇报结果并调用 end 工具结束。';
}

/// 等待 Agent 进入 idle 状态
Future<void> _waitForIdle(CachedAgentProxy proxy, {required Duration timeout}) async {
  final completer = Completer<void>();

  if (proxy.status == AgentStatus.idle) {
    completer.complete();
    return completer.future;
  }

  StreamSubscription? subscription;
  Timer? timer;

  subscription = proxy.onStateChanged.listen((state) {
    if (state.status == AgentStatus.idle) {
      timer?.cancel();
      subscription?.cancel();
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
  });

  timer = Timer(timeout, () {
    subscription?.cancel();
    if (!completer.isCompleted) {
      completer.completeError(TimeoutException('等待 idle 状态超时'));
    }
  });

  return completer.future;
}
