import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart';

/// Agent 项目分析场景测试
///
/// 测试场景：
/// 1. 配置项目 (name=wenzagent, path=D:\project\GitHub\wenzagent)
/// 2. 启用内置工具
/// 3. 发送消息"分析项目"
/// 4. 自动同意所有权限请求
/// 5. 自动同意所有确认请求（选择第一个选项）
/// 6. 等待 Agent 完成分析
void main() {
  // 测试配置
  late String apiKey;
  late String apiUrl;
  late String apiModel;
  late ProviderConfig providerConfig;

  // 测试组件
  late AgentImpl agent;
  late AgentProxy localProxy;
  late CachedAgentProxy cachedProxy;
  late MessageStoreService messageStore;
  late String employeeId;
  late String deviceId;

  // 权限/确认自动响应的订阅
  StreamSubscription<AgentStateSnapshot>? _stateSubscription;
  StreamSubscription<AgentEvent>? _eventSubscription;

  setUpAll(() async {
    // 读取环境变量
    apiKey = Platform.environment['deepseek_api_key'] ?? Platform.environment['anthropic_api_key'] ?? '';
    apiUrl = Platform.environment['deepseek_api_url'] ?? 'https://api.deepseek.com';
    apiModel = Platform.environment['deepseek_api_model'] ?? Platform.environment['anthropic_api_model'] ?? 'deepseek-chat';
    if (apiKey.isEmpty) {
      throw Exception('请设置环境变量 deepseek_api_key 或 anthropic_api_key');
    }
    apiModel = 'deepseek-v4-flash';
    print('\n=== 测试配置 ===');
    print('API URL: $apiUrl');
    print('API Model: $apiModel');

    // 配置 Provider
    providerConfig = ProviderConfig(
      provider: LLMProvider.deepseek,
      apiKey: apiKey,
      baseUrl: apiUrl,
      model: apiModel,
    );

    // 初始化数据库（指定存储路径）
    await DatabaseManager.getInstance('test').initialize(
      storagePath: 'D:\\project\\GitHub\\wenzagent\\test_db',
    );

    // 生成测试 ID
    employeeId = 'test-${DateTime.now().millisecondsSinceEpoch}';
    deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';

    print('Employee ID: $employeeId');
    print('Device ID: $deviceId\n');
  });

  setUp(() async {
    // 每个测试前创建新的 Agent 实例
    // 使用已初始化的 'test' DatabaseManager 单例
    final dbManager = DatabaseManager.getInstance('test');
    final msgStore = MessageStore(dbManager: dbManager);
    final summaryStore = SessionSummaryStore(dbManager: dbManager);
    messageStore = MessageStoreServiceImpl(
      store: msgStore,
      summaryStore: summaryStore,
      deviceId: deviceId,
    );

    // 创建适配器并配置持久化
    final adapter = LlmChatAdapter();
    adapter.configurePersistence(
      messageStore: messageStore,
      deviceId: deviceId,
    );

    // 创建 Agent
    agent = AgentImpl(
      employeeId: employeeId,
      deviceId: deviceId,
      chatAdapter: adapter,
    );

    await agent.initialize(enableBuiltinTools: true); // 启用内置工具
    await agent.setProvider(providerConfig);

    // 配置项目
    await agent.setProject(ProjectData(
      projectName: 'wenzagent',
      workPath: 'D:\\project\\GitHub\\wenzagent',
    ));
    print('项目已配置: name=wenzagent, path=D:\\project\\GitHub\\wenzagent');

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

    // 监听事件流，自动响应权限请求和确认请求
    _eventSubscription = agent.onEvent.listen((event) {
      switch (event.type) {
        case AgentEventType.toolPermissionRequest:
          // 自动同意所有权限请求
          final data = event.data;
          final requestId = data['requestId'] as String?;
          if (requestId != null) {
            print('  🔓 自动同意权限请求: $requestId');
            agent.respondToPermission(
              requestId,
              PermissionDecision.allow,
              scope: PermissionApprovalScope.all,
            );
          }
          break;

        case AgentEventType.confirmRequest:
          // 自动同意确认请求（选择第一个选项）
          final data = event.data;
          final requestId = data['requestId'] as String?;
          final options = data['options'] as List<dynamic>?;
          if (requestId != null && options != null && options.isNotEmpty) {
            final firstOption = options.first;
            final optionKey = firstOption['key'] as String? ?? '';
            print('  ✅ 自动确认请求: $requestId → 选择: $optionKey');
            agent.respondToConfirm(requestId, optionKey);
          }
          break;

        default:
          break;
      }
    });
  });

  tearDown(() async {
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    _eventSubscription = null;
    _stateSubscription = null;
 try {
    await cachedProxy.dispose();
 } catch (_) {}
 try {
    await localProxy.dispose();
 } catch (_) {}
 try {
    await agent.dispose();
 } catch (_) {}
 try {
    await messageStore.deleteMessages(deviceId, employeeId);
 } catch (_) {}
  });

  tearDownAll(() async {
    await DatabaseManager.getInstance('test').close();
  });

  group('项目分析场景测试', () {
    test('✅ 分析项目 - 自动同意权限', () async {
      print('\n--- 测试：分析项目 ---');
      print('发送消息: "分析项目"');

      // 发送消息
      final messageId = await cachedProxy.sendMessage(MessageInput(
        content: '分析项目，思考一下',
      ));

      print('发送消息ID: $messageId');
      expect(messageId, isNotEmpty);

      // 等待处理完成（分析项目可能需要较长时间，设置 5 分钟超时）
      print('等待 Agent 完成分析（最长 5 分钟）...');
      await _waitForIdle(cachedProxy, timeout: const Duration(minutes: 5));

      // 获取消息列表
      final messages = await cachedProxy.getMessages();
      print('\n=== 最终消息列表 ===');
      print('消息数量: ${messages.length}');

      for (int i = 0; i < messages.length; i++) {
        final m = messages[i];
        final content = m.content ?? '';
        final contentPreview = content.length > 200
            ? '${content.substring(0, 200)}...'
            : content;
        print('[$i] role=${m.role}, content=$contentPreview');
      }

      // 验证有用户消息和助手消息
      expect(messages.length, greaterThanOrEqualTo(2));

      final userMsg = messages.firstWhere((m) => m.role == 'user');
      final assistantMsg = messages.firstWhere((m) => m.role == 'assistant');

      expect(userMsg.id, equals(messageId));
      expect(assistantMsg.content, isNotEmpty);

      print('\n✅ 测试通过 - 项目分析完成\n');
    }, timeout: const Timeout(Duration(minutes: 6)));
  });

  print('\n=== 所有测试完成 ===\n');
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
    print('  📊 状态变化: ${state.status}');
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
