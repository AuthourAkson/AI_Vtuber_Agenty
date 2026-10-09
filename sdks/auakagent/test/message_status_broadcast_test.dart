import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/agent/agent_state.dart';
import 'package:auakagent/src/agent/client/agent_proxy.dart';
import 'package:auakagent/src/agent/client/cached_agent_proxy.dart';
import 'package:auakagent/src/agent/entity/entity.dart';
import 'package:auakagent/src/persistence/database_manager.dart';
import 'package:auakagent/src/service/message_store_service.dart';

/// 消息状态广播场景测试
///
/// 验证 AgentProxy 远程模式下消息状态广播的完整链路：
/// 1. 远程 Agent 产生事件 → AgentProxy._eventController → CachedAgentProxy 监听
/// 2. CachedAgentProxy 处理事件 → 更新本地 DB → 触发 onMessagesChanged
/// 3. 消息列表正确同步最新消息
///
/// 核心链路：
/// remoteEventStream → _RemoteOps.onRemoteEvent → _eventController.add(event)
/// → CachedAgentProxy._eventSubscription → _handleAgentEvent
/// → _handleMessageStatusChanged → _syncMessagesFromRemote / _notifyMessagesChanged
void main() {
  late String employeeId;
  late String deviceId;
  late MessageStoreServiceImpl messageStore;

  late String tempDir;

  setUp(() async {
    employeeId = 'emp-${const Uuid().v4().substring(0, 8)}';
    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';
    tempDir = Directory.systemTemp.path;
    // 初始化 DatabaseManager（MessageStore 依赖它）
    final dbManager = DatabaseManager.getInstance(deviceId);
    await dbManager.initialize(storagePath: tempDir);
    messageStore = MessageStoreServiceImpl(deviceId: deviceId);
  });

  tearDown(() async {
    try {
      await messageStore.deleteMessages(deviceId, employeeId);
    } catch (_) {}
    messageStore.dispose();
    DatabaseManager.removeInstance(deviceId);
  });

  // ===========================================================================
  // 1. 完整消息生命周期广播
  // ===========================================================================

  group('完整消息生命周期广播', () {
    test('queued → processing → completed 事件链路完整传播', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final receivedEvents = <AgentEvent>[];

      // 创建远程 AgentProxy，注入事件流
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          // 模拟 RPC 响应（使用正确的 RPC 方法名）
          switch (method) {
            case 'agentSendMessage':
              return {'messageId': params['id'] ?? ''};
            case 'agentGetMaxSeq':
              return {'maxSeq': 2};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              // 模拟远程返回的消息
              return {
                'messages': [
                  {
                    'id': 'msg-lifecycle-001',
                    'role': 'user',
                    'type': 'text',
                    'content': '你好',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                  {
                    'id': 'msg-lifecycle-002',
                    'role': 'assistant',
                    'type': 'text',
                    'content': '你好！有什么可以帮助你的吗？',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 2,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      // 监听 AgentProxy 的事件流（模拟 CachedAgentProxy 的监听）
      proxy.onEvent.listen((event) {
        receivedEvents.add(event);
      });

      // 创建 CachedAgentProxy
      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 模拟完整消息生命周期事件广播
      // 1. 消息入队
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'msg-lifecycle-001',
          'status': 'queued',
          'role': 'user',
          'type': 'text',
          'content': '你好',
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      // 2. Agent 状态变为 processing
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'processing',
          'currentProcessingMessageId': 'msg-lifecycle-001',
          'queuedMessageIds': [],
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      // 3. 消息开始处理
      eventController.add(AgentEvent(
        type: AgentEventType.messageStarted,
        data: {'messageId': 'msg-lifecycle-001'},
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      // 4. 消息处理完成
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'msg-lifecycle-001',
          'status': 'completed',
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();
      await _pumpEventQueue(); // 等待同步完成

      // 5. Agent 状态变为 idle
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {'status': 'idle'},
        employeeId: employeeId,
      ));
      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：AgentProxy 的事件流收到了所有事件
      expect(receivedEvents.length, greaterThanOrEqualTo(5));

      final statusChanges = receivedEvents
          .where((e) => e.type == AgentEventType.messageStatusChanged)
          .map((e) => e.data['status'] as String)
          .toList();
      expect(statusChanges, containsAll(['queued', 'completed']));

      // 验证：CachedAgentProxy 的状态已更新
      expect(cachedProxy.currentProcessingMessageId, isNull);

      // 验证：onMessagesChanged 至少触发了一次
      expect(messagesChanges.isNotEmpty, isTrue,
          reason: '消息列表应该至少刷新一次');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 2. onMessagesChanged 流在消息状态变更时触发
  // ===========================================================================

  group('onMessagesChanged 流触发', () {
    test('messageStatusChanged completed 触发消息列表刷新', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 1};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              return {
                'messages': [
                  {
                    'id': 'msg-refresh-001',
                    'role': 'assistant',
                    'type': 'text',
                    'content': '这是回复消息',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 广播 completed 事件
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'msg-refresh-001',
          'status': 'completed',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：onMessagesChanged 至少触发了一次
      expect(messagesChanges.isNotEmpty, isTrue,
          reason: 'completed 事件应触发消息列表刷新');

      // 验证：消息列表中包含了同步回来的消息
      final messages = await cachedProxy.getMessages();
      expect(messages.any((m) => m.id == 'msg-refresh-001'), isTrue,
          reason: '消息列表应包含同步回来的消息');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('messageStatusChanged failed 触发消息列表刷新并创建错误消息', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 广播 failed 事件
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'msg-fail-001',
          'status': 'failed',
          'error': 'API 调用超时',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：onMessagesChanged 触发了
      expect(messagesChanges.isNotEmpty, isTrue,
          reason: 'failed 事件应触发消息列表刷新');

      // 验证：创建了错误消息
      final messages = await cachedProxy.getMessages();
      final errorMsg = messages.where(
        (m) => m.type == 'error' && m.id == 'error_msg-fail-001',
      ).toList();
      expect(errorMsg.length, equals(1),
          reason: '应创建一条错误消息');
      expect(errorMsg[0].content, contains('API 调用超时'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('messageStatusChanged interrupted 触发消息列表刷新', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 广播 interrupted 事件
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'msg-interrupt-001',
          'status': 'interrupted',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      expect(messagesChanges.isNotEmpty, isTrue,
          reason: 'interrupted 事件应触发消息列表刷新');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 3. 消息列表正确同步最新消息
  // ===========================================================================

  group('消息列表同步', () {
    test('completed 事件后同步远程消息到本地列表', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      var syncCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              syncCount++;
              return {'maxSeq': 2};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              final lastSeq = params['lastSeq'] as int? ?? 0;
              if (lastSeq < 2) {
                return {
                  'messages': [
                    {
                      'id': 'sync-msg-user',
                      'role': 'user',
                      'type': 'text',
                      'content': '同步测试消息',
                      'status': 'completed',
                      'createdAt': DateTime.now().toIso8601String(),
                      'metadata': {
                        'seq': 1,
                        'updateTime': DateTime.now().toIso8601String(),
                      },
                    },
                    {
                      'id': 'sync-msg-assistant',
                      'role': 'assistant',
                      'type': 'text',
                      'content': '这是同步回来的回复',
                      'status': 'completed',
                      'createdAt': DateTime.now().toIso8601String(),
                      'metadata': {
                        'seq': 2,
                        'updateTime': DateTime.now().toIso8601String(),
                      },
                    },
                  ],
                };
              }
              return {'messages': []};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 初始消息列表为空
      var messages = await cachedProxy.getMessages();
      expect(messages.isEmpty, isTrue);

      // 广播 completed 事件
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'sync-msg-user',
          'status': 'completed',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：消息列表已同步
      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(2),
          reason: '应同步到 2 条消息');
      expect(messages.any((m) => m.id == 'sync-msg-user'), isTrue);
      expect(messages.any((m) => m.id == 'sync-msg-assistant'), isTrue);

      // 验证：同步被调用了
      expect(syncCount, greaterThan(0),
          reason: 'completed 事件应触发远程同步');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('idle 状态触发 debounced 同步', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      var syncCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              syncCount++;
              return {'maxSeq': 1};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              return {
                'messages': [
                  {
                    'id': 'idle-sync-msg',
                    'role': 'assistant',
                    'type': 'text',
                    'content': 'idle 后同步的消息',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 广播 idle 事件
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {'status': 'idle'},
        employeeId: employeeId,
      ));

      // 等待 debounce（200ms + buffer）
      await Future.delayed(const Duration(milliseconds: 400));

      // 验证：同步被触发
      expect(syncCount, greaterThan(0),
          reason: 'idle 状态应触发 debounced 同步');

      // 验证：消息已同步到本地
      final messages = await cachedProxy.getMessages();
      expect(messages.any((m) => m.id == 'idle-sync-msg'), isTrue,
          reason: 'idle 后应同步到最新消息');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 4. 多设备广播场景（模拟 DeviceStateHolder 事件流）
  // ===========================================================================

  group('多设备广播场景', () {
    test('通过 DeviceStateHolder 广播事件到多个 AgentProxy', () async {
      // 模拟 DeviceStateHolder 的广播事件流
      final deviceEventController =
          StreamController<AgentEvent>.broadcast();

      final employee1 = 'emp-${const Uuid().v4().substring(0, 8)}';
      final employee2 = 'emp-${const Uuid().v4().substring(0, 8)}';

      // 创建两个远程 AgentProxy，共享同一个事件流
      final proxy1 = AgentProxy.remote(
        employeeId: employee1,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 1};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              return {
                'messages': [
                  {
                    'id': 'multi-msg-1',
                    'role': 'assistant',
                    'type': 'text',
                    'content': '员工1的回复',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: deviceEventController.stream,
      );

      final proxy2 = AgentProxy.remote(
        employeeId: employee2,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 1};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              return {
                'messages': [
                  {
                    'id': 'multi-msg-2',
                    'role': 'assistant',
                    'type': 'text',
                    'content': '员工2的回复',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: deviceEventController.stream,
      );

      final cachedProxy1 = CachedAgentProxy(
        proxy: proxy1,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employee1,
      );

      final cachedProxy2 = CachedAgentProxy(
        proxy: proxy2,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employee2,
      );

      await cachedProxy1.initialize();
      await cachedProxy2.initialize();

      // 广播事件到 deviceEventController（模拟 LAN 广播到达 DeviceStateHolder）
      // employee1 的消息完成
      deviceEventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'multi-msg-1',
          'status': 'completed',
        },
        employeeId: employee1,
      ));

      // employee2 的消息完成
      deviceEventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'multi-msg-2',
          'status': 'completed',
        },
        employeeId: employee2,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：两个 proxy 各自只处理自己的事件
      final messages1 = await cachedProxy1.getMessages();
      final messages2 = await cachedProxy2.getMessages();

      expect(messages1.any((m) => m.id == 'multi-msg-1'), isTrue,
          reason: 'proxy1 应同步到 employee1 的消息');
      expect(messages1.every((m) => m.id != 'multi-msg-2'), isTrue,
          reason: 'proxy1 不应包含 employee2 的消息');

      expect(messages2.any((m) => m.id == 'multi-msg-2'), isTrue,
          reason: 'proxy2 应同步到 employee2 的消息');
      expect(messages2.every((m) => m.id != 'multi-msg-1'), isTrue,
          reason: 'proxy2 不应包含 employee1 的消息');

      await cachedProxy1.dispose();
      await cachedProxy2.dispose();
      await proxy1.dispose();
      await proxy2.dispose();
      await deviceEventController.close();
    });

    test('忽略不同 employeeId 的事件不触发同步', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      var syncCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              syncCount++;
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();
      final initialSyncCount = syncCount;

      // 广播不匹配的 employeeId 事件
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'other-msg',
          'status': 'completed',
        },
        employeeId: 'other-employee-id',
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：没有触发同步（syncCount 不变）
      expect(syncCount, equals(initialSyncCount),
          reason: '不匹配的 employeeId 不应触发同步');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 5. 发送消息 + 状态广播 + 列表刷新 完整流程
  // ===========================================================================

  group('发送消息 + 状态广播完整流程', () {
    test('发送消息后收到广播事件，消息列表正确更新', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentSendMessage':
              // SendMessageRequest.toMap() 包含 messageData 字段
              final messageData = params['messageData'] as Map<String, dynamic>?;
              return {'messageId': messageData?['id'] ?? ''};
            case 'agentGetMaxSeq':
              return {'maxSeq': 2};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetMessagesAfterSeq':
              return {
                'messages': [
                  {
                    'id': 'flow-msg-user',
                    'role': 'user',
                    'type': 'text',
                    'content': '完整流程测试',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 1,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                  {
                    'id': 'flow-msg-assistant',
                    'role': 'assistant',
                    'type': 'text',
                    'content': '完整流程回复',
                    'status': 'completed',
                    'createdAt': DateTime.now().toIso8601String(),
                    'metadata': {
                      'seq': 2,
                      'updateTime': DateTime.now().toIso8601String(),
                    },
                  },
                ],
              };
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 1. 用户发送消息
      final msgId = await cachedProxy.sendMessage(
        MessageInput(content: '完整流程测试'),
      );
      expect(msgId, isNotEmpty);

      await _pumpEventQueue();

      // 验证：本地消息列表包含发送的消息（pending 状态）
      var messages = await cachedProxy.getMessages();
      expect(messages.any((m) => m.content == '完整流程测试'), isTrue);

      // 2. 模拟远程广播：消息处理完成
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': msgId,
          'status': 'completed',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 3. 验证：消息列表已刷新，包含同步回来的消息
      messages = await cachedProxy.getMessages();

      // 应包含用户消息和助手回复
      final userMsg = messages.where((m) => m.role == 'user').toList();
      final assistantMsg = messages.where((m) => m.role == 'assistant').toList();

      expect(userMsg.isNotEmpty, isTrue, reason: '应包含用户消息');
      expect(assistantMsg.isNotEmpty, isTrue, reason: '应包含助手回复');

      // 4. 验证：onMessagesChanged 多次触发
      expect(messagesChanges.length, greaterThanOrEqualTo(2),
          reason: 'onMessagesChanged 应至少触发 2 次（初始化 + 发送 + 同步）');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 6. 工具调用事件广播
  // ===========================================================================

  group('工具调用事件广播', () {
    test('toolCallStart + toolCallResult 事件正确传播', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 工具调用开始
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'broadcast-tool-001',
          'toolName': 'file_read',
          'arguments': {'path': '/tmp/test.txt'},
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：创建了本地工具调用消息
      var messages = await cachedProxy.getMessages();
      var toolMsg = messages.where(
          (m) => m.type == 'functionCall' && m.toolCallId == 'broadcast-tool-001').toList();
      expect(toolMsg.length, equals(1));
      expect(toolMsg[0].status, equals('processing'));
      expect(toolMsg[0].toolName, equals('file_read'));

      // 工具调用完成
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {
          'toolCallId': 'broadcast-tool-001',
          'result': '文件内容...',
          'isError': false,
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：工具调用消息状态已更新
      messages = await cachedProxy.getMessages();
      toolMsg = messages.where(
          (m) => m.type == 'functionCall' && m.toolCallId == 'broadcast-tool-001').toList();
      expect(toolMsg[0].status, equals('completed'));
      expect(toolMsg[0].toolResult, equals('文件内容...'));

      // 验证：callingToolIds 正确追踪
      expect(cachedProxy.callingToolIds, isNot(contains('broadcast-tool-001')));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 7. Agent 状态变更广播
  // ===========================================================================

  group('Agent 状态变更广播', () {
    test('agentStatusChanged 更新 CachedAgentProxy 状态缓存', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final stateChanges = <AgentStateSnapshot>[];
      cachedProxy.onStateChanged.listen((snapshot) {
        stateChanges.add(snapshot);
      });

      await cachedProxy.initialize();

      // 广播 processing 状态
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'processing',
          'currentProcessingMessageId': 'state-msg-001',
          'queuedMessageIds': ['state-msg-002'],
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证：状态缓存已更新
      expect(cachedProxy.currentProcessingMessageId, equals('state-msg-001'));
      expect(cachedProxy.queuedMessageIds, equals(['state-msg-002']));

      // 验证：onStateChanged 触发了
      expect(stateChanges.isNotEmpty, isTrue);
      expect(stateChanges.last.status, equals(AgentStatus.processing));

      // 广播 idle 状态
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {'status': 'idle'},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证：状态已清除
      expect(cachedProxy.currentProcessingMessageId, isNull);
      expect(cachedProxy.queuedMessageIds, isEmpty);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('waitingPermission 状态触发权限查询', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      var queriedPermission = false;
      var queriedConfirm = false;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetPendingPermission':
              queriedPermission = true;
              return <String, dynamic>{};
            case 'agentGetPendingConfirm':
              queriedConfirm = true;
              return <String, dynamic>{};
            case 'agentGetMaxSeq':
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 广播 waitingPermission 状态
      // _RemoteOps.onRemoteEvent 将此事件转发到 _stateController
      // _CachedProxyEventHandler._handleStateChange 监听 onStateChanged，
      // 当 status == waitingPermission 时查询权限
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'waitingPermission',
          'requestId': 'perm-001',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证：权限查询被触发
      expect(queriedPermission, isTrue,
          reason: 'waitingPermission 状态应触发权限查询');
      expect(queriedConfirm, isTrue,
          reason: 'waitingPermission 状态应触发确认查询');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 8. 配置变更事件广播
  // ===========================================================================

  group('配置变更事件广播', () {
    test('configChanged 事件更新远程缓存并通知', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 广播 Provider 配置变更
      eventController.add(AgentEvent(
        type: AgentEventType.configChanged,
        data: {
          'configType': 'provider',
          'action': 'updated',
          'providerConfig': {
            'provider': 'anthropic',
            'apiKey': 'sk-ant-test',
            'baseUrl': 'https://api.anthropic.com',
            'model': 'claude-3-opus',
          },
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证：远程缓存已更新
      final config = proxy.getProviderConfig();
      expect(config, isNotNull);
      expect(config!.model, equals('claude-3-opus'));
      // ProviderConfig.provider 是 LLMProvider 枚举，比较其 name
      expect(config.provider.name, equals('anthropic'));

      // 验证：onMessagesChanged 触发了（configChanged 也会通知 UI）
      expect(messagesChanges.isNotEmpty, isTrue);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('configChanged project 更新项目 UUID', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 广播项目变更
      eventController.add(AgentEvent(
        type: AgentEventType.configChanged,
        data: {
          'configType': 'project',
          'action': 'updated',
          'projectData': {
            'projectUuid': 'proj-broadcast-001',
            'projectName': 'BroadcastTest',
          },
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证
      expect(proxy.getCurrentProjectUuid(), equals('proj-broadcast-001'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 9. 会话清空事件广播
  // ===========================================================================

  group('会话清空事件广播', () {
    test('sessionCleared 事件清空本地消息并触发通知', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'agentGetMaxSeq':
              return {'maxSeq': 0};
            case 'agentGetClearSeq':
              return {'clearSeq': 0};
            case 'agentGetSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 先添加一些消息
      await cachedProxy.sendMessage(MessageInput(content: '将被清空的消息1'));
      await cachedProxy.sendMessage(MessageInput(content: '将被清空的消息2'));

      await _pumpEventQueue();

      var messages = await cachedProxy.getMessages();
      expect(messages.length, greaterThanOrEqualTo(2));

      // 广播 sessionCleared 事件
      eventController.add(AgentEvent(
        type: AgentEventType.sessionCleared,
        data: {},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：本地消息已清空
      messages = await cachedProxy.getMessages();
      expect(messages.isEmpty, isTrue,
          reason: 'sessionCleared 后本地消息应被清空');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 10. 高频事件过滤
  // ===========================================================================

  group('高频事件过滤', () {
    test('streamDelta 和 thinkingDelta 不触发消息列表刷新', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      final messagesChanges = <List<AgentMessage>>[];
      cachedProxy.onMessagesChanged.listen((messages) {
        messagesChanges.add(messages);
      });

      await cachedProxy.initialize();

      // 等待初始化期间的 16ms 去抖通知完成
      await Future.delayed(const Duration(milliseconds: 50));
      // 清除初始化通知
      messagesChanges.clear();

      // 发送大量 streamDelta 事件
      for (var i = 0; i < 10; i++) {
        eventController.add(AgentEvent(
          type: AgentEventType.streamDelta,
          data: {'content': 'chunk $i'},
          employeeId: employeeId,
        ));
      }

      // 发送 thinkingDelta 事件
      for (var i = 0; i < 5; i++) {
        eventController.add(AgentEvent(
          type: AgentEventType.thinkingDelta,
          data: {'content': 'think $i'},
          employeeId: employeeId,
        ));
      }

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证：高频事件不触发消息列表刷新
      // streamDelta 和 thinkingDelta 在 _handleAgentEvent 中是 no-op
      expect(messagesChanges.isEmpty, isTrue,
          reason: 'streamDelta/thinkingDelta 不应触发消息列表刷新');

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });
}

/// 等待事件队列处理完成
Future<void> _pumpEventQueue() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
  await Future.delayed(const Duration(milliseconds: 50));
}
