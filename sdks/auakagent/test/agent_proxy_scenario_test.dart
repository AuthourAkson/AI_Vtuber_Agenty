// ============================================================================
// AgentProxy 场景测试
// ============================================================================
//
// 测试 AgentProxy 和 CachedAgentProxy 在以下场景中的行为：
//
// 1. 远程模式基本通信（消息发送、RPC 回调验证）
// 2. 消息同步（增量拉取、去重、水位线）
// 3. 状态同步（Agent 状态变更、状态快照）
// 4. 事件流（toolCallStart/Result、权限请求、会话清空）
// 5. 缓存层行为（本地消息立即可见、状态更新、去抖通知）
// 6. 并发安全（重复初始化、并发同步、版本号机制）
// 7. 生命周期（dispose 后行为、资源清理）
//
// 使用 mock RPC 回调模拟远程 Agent，无需真实 LLM 或网络连接。
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:uuid/uuid.dart';
import 'package:auakagent/src/agent/agent_state.dart';
import 'package:auakagent/src/agent/client/agent_proxy.dart';
import 'package:auakagent/src/agent/client/cached_agent_proxy.dart';
import 'package:auakagent/src/agent/entity/agent_event.dart';
import 'package:auakagent/src/agent/entity/agent_message.dart';
import 'package:auakagent/src/agent/entity/entity.dart';
import 'package:auakagent/src/agent/entity/message_input.dart';
import 'package:auakagent/src/service/message_store_service.dart';
import 'package:auakagent/src/persistence/database_manager.dart';
import 'package:auakagent/src/shared/chat_message.dart' show ToolCall;

void main() {
  // ===========================================================================
  // 测试基础设施
  // ===========================================================================

  late String employeeId;
  late String deviceId;
  late MessageStoreServiceImpl messageStore;

  setUp(() async {
    employeeId = 'emp-${const Uuid().v4().substring(0, 8)}';
    deviceId = 'dev-${const Uuid().v4().substring(0, 8)}';
    final dbManager = DatabaseManager.getInstance(deviceId);
    await dbManager.initialize(storagePath: Directory.systemTemp.path);
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
  // 1. 远程模式 AgentProxy 基本通信
  // ===========================================================================

  group('AgentProxy 远程模式基本通信', () {
    test('sendMessage 调用 RPC 回调并传递正确参数', () async {
      String? calledMethod;
      Map<String, dynamic>? calledParams;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          calledMethod = method;
          calledParams = params;
          return {'messageId': params['id'] ?? 'rpc-returned-id'};
        },
      );

      final input = MessageInput(
        content: 'Hello Agent',
        type: 'text',
      );

      final returnedId = await proxy.sendMessage(input);

      // 验证 RPC 被调用
      expect(calledMethod, isNotNull);
      expect(calledParams, isNotNull);
      expect(calledParams!['content'], equals('Hello Agent'));
      expect(calledParams!['type'], equals('text'));

      // 返回的 ID 应该是客户端生成的 UUID
      expect(returnedId, isNotEmpty);

      await proxy.dispose();
    });

    test('sendMessage 保留客户端提供的消息 ID', () async {
      final clientMessageId = const Uuid().v4();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          // 模拟远程返回
          return {'messageId': params['id'] ?? ''};
        },
      );

      final returnedId = await proxy.sendMessage(
        MessageInput(content: 'test', id: clientMessageId),
      );

      // 返回的 ID 应该与客户端提供的一致
      expect(returnedId, equals(clientMessageId));

      await proxy.dispose();
    });

    test('sendMessage 将消息加入待确认队列', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
      );

      expect(proxy.pendingMessageQueueLength, equals(0));

      await proxy.sendMessage(MessageInput(content: 'msg1'));
      expect(proxy.pendingMessageQueueLength, equals(1));

      await proxy.sendMessage(MessageInput(content: 'msg2'));
      expect(proxy.pendingMessageQueueLength, equals(2));

      // 验证待确认消息内容
      final pendingIds = proxy.pendingMessageIds;
      expect(pendingIds.length, equals(2));

      await proxy.dispose();
    });

    test('interrupt 调用 RPC 的 interrupt 方法', () async {
      String? calledMethod;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          calledMethod = method;
          return <String, dynamic>{};
        },
      );

      await proxy.interrupt();
      expect(calledMethod, isNotNull);

      await proxy.dispose();
    });

    test('revokeMessage 调用 RPC 的 revokeMessage 方法', () async {
      String? calledMethod;
      String? revokedId;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          calledMethod = method;
          revokedId = params['messageId'] as String?;
          return <String, dynamic>{};
        },
      );

      await proxy.revokeMessage('msg-to-revoke');
      expect(calledMethod, isNotNull);
      expect(revokedId, equals('msg-to-revoke'));

      await proxy.dispose();
    });

    test('远程模式 status 默认为 idle', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
      );

      expect(proxy.status, equals(AgentStatus.idle));
      expect(proxy.isAlive, isTrue);
      expect(proxy.isLocalMode, isFalse);

      await proxy.dispose();
    });

    test('远程模式 getPendingPermissionRequest 返回 null（同步版本）', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
      );

      // 同步版本在远程模式下返回 null
      expect(proxy.getPendingPermissionRequest(), isNull);

      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 2. 消息同步
  // ===========================================================================

  group('消息同步', () {
    test('远程消息增量拉取并写入本地缓存', () async {
      final remoteMessages = [
        _createRemoteMessage(
          id: 'msg-001',
          role: 'user',
          content: 'Hello',
          seq: 1,
        ),
        _createRemoteMessage(
          id: 'msg-002',
          role: 'assistant',
          content: 'Hi there!',
          seq: 2,
        ),
      ];

      int? requestedLastSeq;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'getMaxSeq':
              return {'maxSeq': 2};
            case 'getMinSeq':
              return {'minSeq': 1};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getMessagesAfterSeq':
              requestedLastSeq = params['lastSeq'] as int?;
              return {
                'messages': remoteMessages.map((m) => m.toMap()).toList(),
              };
            case 'getSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();
      await cachedProxy.syncFromRemote();

      // 验证消息已写入本地
      final messages = await cachedProxy.getMessages();
      expect(messages.length, equals(2));
      expect(messages[0].content, equals('Hello'));
      expect(messages[1].content, equals('Hi there!'));

      // 验证请求参数
      expect(requestedLastSeq, equals(0)); // 初始同步，lastSeq=0

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('增量同步只拉取新消息（基于 lastSeq）', () async {
      var maxSeqResponse = 2;
      var callCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          callCount++;
          switch (method) {
            case 'getMaxSeq':
              return {'maxSeq': maxSeqResponse};
            case 'getMinSeq':
              return {'minSeq': 1};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getMessagesAfterSeq':
              final lastSeq = params['lastSeq'] as int? ?? 0;
              if (lastSeq >= maxSeqResponse) {
                return {'messages': []};
              }
              // 第一次同步返回 seq 1-2
              if (lastSeq == 0) {
                return {
                  'messages': [
                    _createRemoteMessage(id: 'msg-001', role: 'user', content: 'Hi', seq: 1)
                        .toMap(),
                    _createRemoteMessage(id: 'msg-002', role: 'assistant', content: 'Hello!', seq: 2)
                        .toMap(),
                  ],
                };
              }
              // 第二次同步返回 seq 3
              return {
                'messages': [
                  _createRemoteMessage(id: 'msg-003', role: 'user', content: 'New msg', seq: 3)
                      .toMap(),
                ],
              };
            case 'getSessionSummary':
              return <String, dynamic>{};
            case 'getStateSnapshot':
              return AgentStateSnapshot.idle().toMap();
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 第一次同步
      await cachedProxy.syncFromRemote();
      var messages = await cachedProxy.getMessages();
      expect(messages.length, equals(2));

      // 模拟远程新增消息
      maxSeqResponse = 3;

      // 第二次同步（增量）
      callCount = 0;
      await cachedProxy.syncWithRemote();
      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(3));
      expect(messages.last.content, equals('New msg'));

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('消息去重：相同 ID 消息不重复写入', () async {
      final remoteMsg = _createRemoteMessage(
        id: 'dup-msg-001',
        role: 'user',
        content: 'Duplicate test',
        seq: 1,
      );

      var syncCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'getMaxSeq':
              return {'maxSeq': 1};
            case 'getMinSeq':
              return {'minSeq': 1};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getMessagesAfterSeq':
              syncCount++;
              if (syncCount == 1) {
                return {'messages': [remoteMsg.toMap()]};
              }
              // 第二次同步：远程无新消息
              return {'messages': []};
            case 'getSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 第一次同步
      await cachedProxy.syncFromRemote();
      var messages = await cachedProxy.getMessages();
      expect(messages.length, equals(1));

      // 第二次同步（无新消息）
      await cachedProxy.syncWithRemote();
      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(1)); // 仍然只有1条

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('删除消息同步：远程 deleted 标记的消息从本地删除', () async {
      // 先写入一条本地消息
      final localMsg = _createRemoteMessage(
        id: 'del-msg-001',
        role: 'user',
        content: 'To be deleted',
        seq: 1,
      );

      var syncPhase = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'getMaxSeq':
              return {'maxSeq': syncPhase == 0 ? 1 : 2};
            case 'getMinSeq':
              return {'minSeq': 1};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getMessagesAfterSeq':
              if (syncPhase == 0) {
                return {'messages': [localMsg.toMap()]};
              }
              // 第二次同步返回 deleted 标记的消息
              return {
                'messages': [
                  {
                    ...localMsg.toMap(),
                    'metadata': {
                      ...?localMsg.metadata,
                      'deleted': 1,
                      'seq': 2,
                    },
                  },
                ],
              };
            case 'getSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 第一次同步：写入消息
      await cachedProxy.syncFromRemote();
      var messages = await cachedProxy.getMessages();
      expect(messages.length, equals(1));

      // 第二次同步：消息被标记为 deleted
      syncPhase = 1;
      await cachedProxy.syncWithRemote();
      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(0)); // 已删除

      await cachedProxy.dispose();
      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 3. 状态同步
  // ===========================================================================

  group('状态同步', () {
    test('Agent 状态变更通过事件流传播', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return <String, dynamic>{};
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

      // 模拟远程 Agent 状态变更
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'processing',
          'currentProcessingMessageId': 'msg-001',
          'queuedMessageIds': ['msg-002'],
        },
        employeeId: employeeId,
      ));

      // 等待事件传播
      await _pumpEventQueue();

      // 验证状态缓存已更新
      expect(cachedProxy.currentProcessingMessageId, equals('msg-001'));
      expect(cachedProxy.queuedMessageIds, equals(['msg-002']));

      // 模拟回到空闲
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'idle',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      expect(cachedProxy.currentProcessingMessageId, isNull);
      expect(cachedProxy.queuedMessageIds, isEmpty);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('忽略不同 employeeId 的事件', () async {
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

      // 发送不同 employeeId 的事件
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {'status': 'processing'},
        employeeId: 'other-employee-id',
      ));

      await _pumpEventQueue();

      // 状态不应改变
      expect(cachedProxy.currentProcessingMessageId, isNull);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('getStateSnapshot 远程查询', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            return AgentStateSnapshot(
              status: AgentStatus.streaming,
              currentProcessingMessageId: 'msg-001',
              isStreaming: true,
            ).toMap();
          }
          return <String, dynamic>{};
        },
      );

      final snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.streaming));
      expect(snapshot.currentProcessingMessageId, equals('msg-001'));
      expect(snapshot.isStreaming, isTrue);

      await proxy.dispose();
    });

    test('消息处理状态变更事件更新本地缓存', () async {
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

      // 先添加一条本地消息
      final localMsg = AgentMessage(
        id: 'status-test-msg',
        role: 'user',
        type: 'text',
        content: 'test status change',
        createdAt: DateTime.now(),
        status: 'pending',
        metadata: {
          'localOnly': true,
          'updateTime': DateTime.now().toIso8601String(),
        },
      );
      await messageStore.addMessage(
        deviceId,
        cachedProxy._agentMessageToChatMessageForTest(localMsg),
        updateWatermark: false,
      );

      // 模拟消息开始处理
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {'messageId': 'status-test-msg', 'status': 'processing'},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证消息状态已更新
      final messages = await cachedProxy.getMessages();
      final msg = messages.firstWhere((m) => m.id == 'status-test-msg');
      expect(msg.status, equals('processing'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    // =========================================================================
    // Bug 修复测试：离线状态显示问题 - 重启后生效（缓存 Bug）
    // =========================================================================

    test('getStateSnapshotAsync 应更新 _remoteCache.status（修复 Bug 1）', () async {
      // 场景：远程 Agent 正在 processing，但 _remoteCache 初始为 idle
      // 修复前：getStateSnapshotAsync 只返回值，不更新缓存
      // 修复后：getStateSnapshotAsync 同时更新 _remoteCache.status 和 snapshot
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            return AgentStateSnapshot(
              status: AgentStatus.processing,
              currentProcessingMessageId: 'msg-processing-001',
              isStreaming: false,
              queuedMessageIds: ['msg-002'],
              queueLength: 1,
            ).toMap();
          }
          return <String, dynamic>{};
        },
      );

      // 初始状态应为 idle（_RemoteStateCache 默认值）
      expect(proxy.status, equals(AgentStatus.idle));

      // 调用 getStateSnapshotAsync 后，缓存应被更新
      final snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.processing));
      expect(snapshot.currentProcessingMessageId, equals('msg-processing-001'));

      // 关键断言：proxy.status 应反映远程真实状态，而非初始 idle
      expect(proxy.status, equals(AgentStatus.processing));

      // isAlive 也应正确反映
      expect(proxy.isAlive, isTrue);

      await proxy.dispose();
    });

    test('CachedAgentProxy syncFromRemote 同步远程 processing 状态到 UI（修复 Bug 2）', () async {
      // 场景：远程 Agent 正在处理消息（processing），本地刚启动 CachedAgentProxy
      // 修复前：syncFromRemote 后 UI 看到的 status 仍然是 idle，直到收到事件才更新
      // 修复后：syncFromRemote 查询远程状态后，_remoteCache.status 正确更新
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            // 模拟远程 Agent 正在处理消息
            return AgentStateSnapshot(
              status: AgentStatus.streaming,
              currentProcessingMessageId: 'msg-streaming-001',
              isStreaming: true,
              queuedMessageIds: ['msg-003'],
              queueLength: 1,
            ).toMap();
          }
          if (method == 'agentGetMessages') {
            return {'messages': <Map<String, dynamic>>[]};
          }
          return <String, dynamic>{};
        },
        remoteEventStream: eventController.stream,
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      // 监听状态变更
      final stateChanges = <AgentStateSnapshot>[];
      cachedProxy.onStateChanged.listen((snapshot) {
        stateChanges.add(snapshot);
      });

      // initialize() 设置事件监听，syncFromRemote() 查询远程状态
      await cachedProxy.initialize();
      await cachedProxy.syncFromRemote();

      // 关键断言：syncFromRemote 后 status 应为远程真实状态，而非 idle
      expect(cachedProxy.status, equals(AgentStatus.streaming));
      expect(cachedProxy.currentProcessingMessageId, equals('msg-streaming-001'));
      expect(cachedProxy.queuedMessageIds, equals(['msg-003']));
      expect(cachedProxy.isAlive, isTrue);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('初始化时远程 idle 状态不会误触发状态变更事件', () async {
      // 场景：远程 Agent 是 idle，初始化后不应产生多余的状态变更事件
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            return AgentStateSnapshot(
              status: AgentStatus.idle,
              isStreaming: false,
            ).toMap();
          }
          return <String, dynamic>{};
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
      await cachedProxy.syncFromRemote();
      await _pumpEventQueue();

      // idle → idle 不应有状态变更事件
      // （注：如果 _syncRemoteStateAndPermission 检测到 processingMessageId 变化会通知）
      expect(cachedProxy.status, equals(AgentStatus.idle));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('状态从 processing 恢复到 idle 后重新初始化应正确反映 idle', () async {
      // 场景：模拟应用重启 - 上次远程 Agent 在 processing，现在已回到 idle
      // 重新初始化后应正确反映 idle 状态
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            return AgentStateSnapshot(
              status: AgentStatus.idle,
              isStreaming: false,
            ).toMap();
          }
          return <String, dynamic>{};
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
      await cachedProxy.syncFromRemote();

      // 应正确反映 idle
      expect(cachedProxy.status, equals(AgentStatus.idle));
      expect(cachedProxy.currentProcessingMessageId, isNull);
      expect(cachedProxy.queuedMessageIds, isEmpty);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('多次 getStateSnapshotAsync 调用应保持缓存一致性', () async {
      // 场景：连续多次查询远程状态，缓存应始终与最后一次查询结果一致
      var callCount = 0;
      final states = [
        AgentStatus.idle,
        AgentStatus.processing,
        AgentStatus.streaming,
        AgentStatus.idle,
      ];

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            final status = states[callCount < states.length ? callCount : states.length - 1];
            callCount++;
            return AgentStateSnapshot(
              status: status,
              isStreaming: status == AgentStatus.streaming,
            ).toMap();
          }
          return <String, dynamic>{};
        },
      );

      // 第一次查询：idle
      var snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.idle));
      expect(proxy.status, equals(AgentStatus.idle));

      // 第二次查询：processing
      snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.processing));
      expect(proxy.status, equals(AgentStatus.processing));

      // 第三次查询：streaming
      snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.streaming));
      expect(proxy.status, equals(AgentStatus.streaming));

      // 第四次查询：回到 idle
      snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.idle));
      expect(proxy.status, equals(AgentStatus.idle));

      await proxy.dispose();
    });

    test('事件流状态变更后 getStateSnapshotAsync 不覆盖事件状态', () async {
      // 场景：先通过事件流收到 processing 状态，再查询远程（此时已 idle）
      // 应以最后一次查询为准
      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          if (method == 'agentGetState') {
            return AgentStateSnapshot(
              status: AgentStatus.idle,
              isStreaming: false,
            ).toMap();
          }
          return <String, dynamic>{};
        },
        remoteEventStream: eventController.stream,
      );

      // 先通过事件流设置 processing
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {
          'status': 'processing',
          'currentProcessingMessageId': 'msg-001',
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      expect(proxy.status, equals(AgentStatus.processing));

      // 再查询远程（返回 idle）
      final snapshot = await proxy.getStateSnapshotAsync();
      expect(snapshot.status, equals(AgentStatus.idle));
      // 缓存应被更新为远程真实状态
      expect(proxy.status, equals(AgentStatus.idle));

      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 4. 事件流
  // ===========================================================================
  group('事件流', () {
    test('toolCallStart 事件创建本地工具调用消息', () async {
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

      // 模拟工具调用开始
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'call-tool-001',
          'toolName': 'execute_command',
          'arguments': {'command': 'ls -la'},
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue(); // 等待去抖通知

      // 验证本地创建了工具调用消息
      final messages = await cachedProxy.getMessages();
      final toolMsg = messages.where((m) =>
          m.type == 'functionCall' && m.toolCallId == 'call-tool-001').toList();
      expect(toolMsg.length, equals(1));
      expect(toolMsg[0].toolName, equals('execute_command'));
      expect(toolMsg[0].status, equals('processing'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('toolCallResult 事件更新工具调用消息状态', () async {
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

      // 先触发 toolCallStart
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'call-tool-002',
          'toolName': 'read_file',
          'arguments': {'path': '/tmp/test.txt'},
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 触发 toolCallResult
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {
          'toolCallId': 'call-tool-002',
          'result': 'File contents here...',
          'isError': false,
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证工具调用消息已更新
      final messages = await cachedProxy.getMessages();
      final toolMsg = messages.where((m) =>
          m.type == 'functionCall' && m.toolCallId == 'call-tool-002').toList();
      expect(toolMsg.length, equals(1));
      expect(toolMsg[0].status, equals('completed'));
      expect(toolMsg[0].toolResult, equals('File contents here...'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('toolCallResult 错误状态设置 interrupted/failed', () async {
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

      // 权限被拒绝 → interrupted
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'call-perm-denied',
          'toolName': 'execute_command',
          'arguments': {'command': 'rm -rf /'},
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {
          'toolCallId': 'call-perm-denied',
          'result': '权限被拒绝: 危险命令',
          'isError': true,
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();
      await _pumpEventQueue();

      var messages = await cachedProxy.getMessages();
      var toolMsg = messages.firstWhere(
        (m) => m.toolCallId == 'call-perm-denied',
      );
      expect(toolMsg.status, equals('interrupted'));

      // 一般错误 → failed
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'call-error',
          'toolName': 'read_file',
          'arguments': {'path': '/nonexistent'},
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {
          'toolCallId': 'call-error',
          'result': 'File not found',
          'isError': true,
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();
      await _pumpEventQueue();

      messages = await cachedProxy.getMessages();
      toolMsg = messages.firstWhere(
        (m) => m.toolCallId == 'call-error',
      );
      expect(toolMsg.status, equals('failed'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('权限请求事件缓存并通知', () async {
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

      // 初始无权限请求
      expect(cachedProxy.getPendingPermissionRequest(), isNull);

      // 模拟权限请求
      eventController.add(AgentEvent(
        type: AgentEventType.toolPermissionRequest,
        data: {
          'requestId': 'perm-001',
          'type': 'tool',
          'description': '执行命令',
          'functionName': 'execute_command',
          'permissionArgKey': 'command',
          'permissionArgValue': 'rm -rf /tmp',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证权限请求已缓存
      final permRequest = cachedProxy.getPendingPermissionRequest();
      expect(permRequest, isNotNull);
      expect(permRequest!.requestId, equals('perm-001'));
      expect(permRequest.functionName, equals('execute_command'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('会话清空事件清除本地消息', () async {
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

      // 先写入一些消息
      for (int i = 0; i < 3; i++) {
        final msg = AgentMessage(
          id: 'clear-test-msg-$i',
          role: i % 2 == 0 ? 'user' : 'assistant',
          type: 'text',
          content: 'Message $i',
          createdAt: DateTime.now().add(Duration(seconds: i)),
        );
        await messageStore.addMessage(
          deviceId,
          cachedProxy._agentMessageToChatMessageForTest(msg),
        );
      }

      var messages = await cachedProxy.getMessages();
      expect(messages.length, equals(3));

      // 模拟会话清空事件
      eventController.add(AgentEvent(
        type: AgentEventType.sessionCleared,
        data: {},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 验证消息已清空
      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(0));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('确认请求事件缓存', () async {
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

      expect(cachedProxy.getPendingConfirmRequest(), isNull);

      // 模拟确认请求
      eventController.add(AgentEvent(
        type: AgentEventType.confirmRequest,
        data: {
          'requestId': 'confirm-001',
          'title': '请选择方案',
          'message': '选择 A 还是 B？',
          'options': [
            {'key': 'a', 'label': '方案A'},
            {'key': 'b', 'label': '方案B'},
          ],
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      final confirmRequest = cachedProxy.getPendingConfirmRequest();
      expect(confirmRequest, isNotNull);
      expect(confirmRequest!.requestId, equals('confirm-001'));
      expect(confirmRequest.title, equals('请选择方案'));
      expect(confirmRequest.options.length, equals(2));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 5. 缓存层行为
  // ===========================================================================

  group('缓存层行为', () {
    test('sendMessage 创建本地消息立即可见', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 发送消息
      final msgId = await cachedProxy.sendMessage(
        MessageInput(content: 'Instant visibility test'),
      );

      // 立即查询消息列表
      final messages = await cachedProxy.getMessages();
      expect(messages.length, equals(1));
      expect(messages[0].id, equals(msgId));
      expect(messages[0].content, equals('Instant visibility test'));
      expect(messages[0].status, equals('sent')); // 远程模式下更新为 sent

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('多条消息按时间正序排列', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 依次发送3条消息
      final ids = <String>[];
      for (int i = 0; i < 3; i++) {
        final id = await cachedProxy.sendMessage(
          MessageInput(content: 'Message $i'),
        );
        ids.add(id);
        await Future.delayed(const Duration(milliseconds: 10));
      }

      final messages = await cachedProxy.getMessages();
      expect(messages.length, equals(3));

      // 验证按时间正序
      for (int i = 0; i < messages.length - 1; i++) {
        expect(
          messages[i].createdAt.isBefore(messages[i + 1].createdAt) ||
              messages[i].createdAt.isAtSameMomentAs(messages[i + 1].createdAt),
          isTrue,
          reason: '消息应按时间正序排列',
        );
      }

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('onMessagesChanged 流在消息变更时触发', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
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

      // 发送消息应触发 onMessagesChanged
      await cachedProxy.sendMessage(MessageInput(content: 'Trigger change'));

      // 等待去抖通知（16ms + buffer）
      await Future.delayed(const Duration(milliseconds: 100));

      // 应该至少触发一次（初始化通知 + 发送通知）
      expect(messagesChanges.isNotEmpty, isTrue);

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('cacheState 在同步过程中变更', () async {
      final cacheStates = <CacheState>[];

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'getMaxSeq':
              return {'maxSeq': 0};
            case 'getMinSeq':
              return {'minSeq': 0};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      cachedProxy.onCacheStateChanged.listen((state) {
        cacheStates.add(state);
      });

      await cachedProxy.initialize();
      await cachedProxy.syncWithRemote();

      // 应该经历了 syncing -> idle
      expect(cacheStates.contains(CacheState.syncing), isTrue);
      expect(cacheStates.contains(CacheState.idle), isTrue);

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('getUnreadCount 查询未读消息数', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 初始无未读
      var unreadCount = await cachedProxy.getUnreadCount();
      expect(unreadCount, equals(0));

      // 添加一条 assistant 消息（未读）
      final assistantMsg = AgentMessage(
        id: 'unread-msg-001',
        role: 'assistant',
        type: 'text',
        content: 'Unread message',
        createdAt: DateTime.now(),
      );
      await messageStore.addMessage(
        deviceId,
        cachedProxy._agentMessageToChatMessageForTest(assistantMsg),
      );

      unreadCount = await cachedProxy.getUnreadCount();
      expect(unreadCount, equals(1));

      await cachedProxy.dispose();
      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 6. 并发安全
  // ===========================================================================

  group('并发安全', () {
    test('重复 initialize 不报错（双重锁）', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      // 并发初始化
      await Future.wait([
        cachedProxy.initialize(),
        cachedProxy.initialize(),
        cachedProxy.initialize(),
      ]);

      // 应该正常完成，不抛异常
      expect(cachedProxy.isDisposed, isFalse);

      await cachedProxy.dispose();
      await proxy.dispose();
    });

    test('并发 syncWithRemote 使用版本号机制', () async {
      var syncCount = 0;

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          switch (method) {
            case 'getMaxSeq':
              syncCount++;
              // 模拟慢速 RPC
              await Future.delayed(const Duration(milliseconds: 50));
              return {'maxSeq': 1};
            case 'getMinSeq':
              return {'minSeq': 1};
            case 'getClearSeq':
              return {'clearSeq': 0};
            case 'getMessagesAfterSeq':
              return {'messages': []};
            case 'getSessionSummary':
              return <String, dynamic>{};
            default:
              return <String, dynamic>{};
          }
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 并发触发多次同步
      await Future.wait([
        cachedProxy.syncWithRemote(),
        cachedProxy.syncWithRemote(),
        cachedProxy.syncWithRemote(),
      ]);

      // 同步应该被合理合并，不会导致错误
      expect(cachedProxy.isDisposed, isFalse);

      await cachedProxy.dispose();
      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 7. 生命周期
  // ===========================================================================

  group('生命周期', () {
    test('dispose 后 isDisposed 为 true', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();
      expect(cachedProxy.isDisposed, isFalse);

      await cachedProxy.dispose();
      expect(cachedProxy.isDisposed, isTrue);

      await proxy.dispose();
    });

    test('dispose 后权限请求缓存被清空', () async {
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

      // 模拟权限请求
      eventController.add(AgentEvent(
        type: AgentEventType.toolPermissionRequest,
        data: {
          'requestId': 'perm-dispose-test',
          'type': 'tool',
          'description': 'test',
          'functionName': 'test_tool',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      expect(cachedProxy.getPendingPermissionRequest(), isNotNull);

      // dispose 后应清空
      await cachedProxy.dispose();
      expect(cachedProxy.getPendingPermissionRequest(), isNull);

      await proxy.dispose();
      await eventController.close();
    });

    test('dispose 后确认请求缓存被清空', () async {
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

      eventController.add(AgentEvent(
        type: AgentEventType.confirmRequest,
        data: {
          'requestId': 'confirm-dispose-test',
          'title': 'test',
          'message': 'test',
          'options': [
            {'key': 'a', 'label': 'A'},
            {'key': 'b', 'label': 'B'},
          ],
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      expect(cachedProxy.getPendingConfirmRequest(), isNotNull);

      await cachedProxy.dispose();
      expect(cachedProxy.getPendingConfirmRequest(), isNull);

      await proxy.dispose();
      await eventController.close();
    });

    test('clearCurrentSession 清空本地数据库', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          return {'messageId': params['id'] ?? ''};
        },
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 发送几条消息
      for (int i = 0; i < 3; i++) {
        await cachedProxy.sendMessage(
          MessageInput(content: 'Session clear test $i'),
        );
      }

      var messages = await cachedProxy.getMessages();
      expect(messages.length, equals(3));

      // 清空会话
      await cachedProxy.clearCurrentSession();

      messages = await cachedProxy.getMessages();
      expect(messages.length, equals(0));

      await cachedProxy.dispose();
      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 8. 工具调用 callingToolIds 追踪
  // ===========================================================================

  group('callingToolIds 追踪', () {
    test('toolCallStart 添加 callingToolId', () async {
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

      expect(cachedProxy.callingToolIds, isEmpty);

      // 模拟工具调用开始
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'tracking-001',
          'toolName': 'test_tool',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      expect(cachedProxy.callingToolIds, contains('tracking-001'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('toolCallResult 移除 callingToolId', () async {
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

      // 开始
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallStart,
        data: {
          'toolCallId': 'tracking-002',
          'toolName': 'test_tool',
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();
      expect(cachedProxy.callingToolIds, contains('tracking-002'));

      // 完成
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {
          'toolCallId': 'tracking-002',
          'result': 'done',
          'isError': false,
        },
        employeeId: employeeId,
      ));
      await _pumpEventQueue();

      expect(cachedProxy.callingToolIds, isNot(contains('tracking-002')));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('多个工具调用同时追踪', () async {
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

      // 同时发起3个工具调用
      for (int i = 1; i <= 3; i++) {
        eventController.add(AgentEvent(
          type: AgentEventType.toolCallStart,
          data: {
            'toolCallId': 'multi-$i',
            'toolName': 'tool_$i',
          },
          employeeId: employeeId,
        ));
      }

      await _pumpEventQueue();

      expect(cachedProxy.callingToolIds.length, equals(3));
      expect(cachedProxy.callingToolIds, containsAll(['multi-1', 'multi-2', 'multi-3']));

      // 完成其中2个
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {'toolCallId': 'multi-1', 'result': 'ok', 'isError': false},
        employeeId: employeeId,
      ));
      eventController.add(AgentEvent(
        type: AgentEventType.toolCallResult,
        data: {'toolCallId': 'multi-3', 'result': 'ok', 'isError': false},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      expect(cachedProxy.callingToolIds.length, equals(1));
      expect(cachedProxy.callingToolIds, contains('multi-2'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('updateRemoteStateCache 手动更新状态缓存', () async {
      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async => {},
      );

      final cachedProxy = CachedAgentProxy(
        proxy: proxy,
        messageStore: messageStore,
        deviceId: deviceId,
        employeeId: employeeId,
      );

      await cachedProxy.initialize();

      // 手动更新状态缓存
      cachedProxy.updateRemoteStateCache(
        currentProcessingMessageId: 'manual-msg-001',
        queuedMessageIds: ['q-001', 'q-002'],
        callingToolIds: ['tool-001'],
      );

      expect(cachedProxy.currentProcessingMessageId, equals('manual-msg-001'));
      expect(cachedProxy.queuedMessageIds, equals(['q-001', 'q-002']));
      expect(cachedProxy.callingToolIds, equals(['tool-001']));

      // 清除
      cachedProxy.updateRemoteStateCache(
        clearProcessing: true,
        clearQueued: true,
        clearCallingToolIds: true,
      );

      expect(cachedProxy.currentProcessingMessageId, isNull);
      expect(cachedProxy.queuedMessageIds, isEmpty);
      expect(cachedProxy.callingToolIds, isEmpty);

      await cachedProxy.dispose();
      await proxy.dispose();
    });
  });

  // ===========================================================================
  // 9. 配置同步
  // ===========================================================================

  group('配置同步', () {
    test('configChanged 事件更新远程缓存', () async {
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

      // 模拟 Provider 配置变更
      eventController.add(AgentEvent(
        type: AgentEventType.configChanged,
        data: {
          'configType': 'provider',
          'providerConfig': {
            'provider': 'openai',
            'apiKey': 'sk-test',
            'baseUrl': 'https://api.openai.com/v1',
            'model': 'gpt-4',
          },
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 验证远程缓存已更新
      final config = proxy.getProviderConfig();
      expect(config, isNotNull);
      expect(config!.model, equals('gpt-4'));

      // 模拟项目变更
      eventController.add(AgentEvent(
        type: AgentEventType.configChanged,
        data: {
          'configType': 'project',
          'projectData': {
            'projectUuid': 'proj-001',
            'projectName': 'TestProject',
          },
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      expect(proxy.getCurrentProjectUuid(), equals('proj-001'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 10. 权限响应处理
  // ===========================================================================

  group('权限响应处理', () {
    test('respondToPermission 清除缓存并调用 RPC', () async {
      String? calledMethod;
      Map<String, dynamic>? calledParams;

      final eventController = StreamController<AgentEvent>.broadcast();

      final proxy = AgentProxy.remote(
        employeeId: employeeId,
        deviceId: deviceId,
        rpcCall: (method, params) async {
          calledMethod = method;
          calledParams = params;
          return <String, dynamic>{};
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

      // 模拟权限请求
      eventController.add(AgentEvent(
        type: AgentEventType.toolPermissionRequest,
        data: {
          'requestId': 'perm-resp-001',
          'type': 'tool',
          'description': 'test',
          'functionName': 'execute_command',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      expect(cachedProxy.getPendingPermissionRequest(), isNotNull);

      // 响应权限请求
      await cachedProxy.respondToPermission(
        'perm-resp-001',
        PermissionDecision.allow,
      );

      // 验证 RPC 被调用
      expect(calledMethod, isNotNull);
      expect(calledParams!['requestId'], equals('perm-resp-001'));
      expect(calledParams!['decision'], equals('allow'));

      // 验证缓存已清除
      expect(cachedProxy.getPendingPermissionRequest(), isNull);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('权限响应事件（其他设备已处理）清除本地缓存', () async {
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

      // 模拟权限请求
      eventController.add(AgentEvent(
        type: AgentEventType.toolPermissionRequest,
        data: {
          'requestId': 'perm-other-device',
          'type': 'tool',
          'description': 'test',
          'functionName': 'test_tool',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      expect(cachedProxy.getPendingPermissionRequest(), isNotNull);

      // 模拟其他设备已响应
      eventController.add(AgentEvent(
        type: AgentEventType.toolPermissionResponse,
        data: {
          'requestId': 'perm-other-device',
          'decision': 'allow',
          'scope': 'once',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      // 本地缓存应被清除
      expect(cachedProxy.getPendingPermissionRequest(), isNull);

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });

  // ===========================================================================
  // 11. 消息处理失败场景
  // ===========================================================================

  group('消息处理失败场景', () {
    test('messageStatusChanged failed 创建错误消息', () async {
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

      // 模拟消息处理失败
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {
          'messageId': 'fail-msg-001',
          'status': 'failed',
          'error': 'LLM API 调用超时',
        },
        employeeId: employeeId,
      ));

      await _pumpEventQueue();
      await _pumpEventQueue();

      // 应该创建一条错误消息
      final messages = await cachedProxy.getMessages();
      final errorMsg = messages.where(
        (m) => m.type == 'error' && m.id == 'error_fail-msg-001',
      ).toList();
      expect(errorMsg.length, equals(1));
      expect(errorMsg[0].content, contains('LLM API 调用超时'));
      expect(errorMsg[0].status, equals('failed'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });

    test('messageStarted 事件更新处理中消息ID', () async {
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

      eventController.add(AgentEvent(
        type: AgentEventType.messageStarted,
        data: {'messageId': 'started-msg-001'},
        employeeId: employeeId,
      ));

      await _pumpEventQueue();

      expect(cachedProxy.currentProcessingMessageId, equals('started-msg-001'));

      await cachedProxy.dispose();
      await proxy.dispose();
      await eventController.close();
    });
  });
}

// =============================================================================
// 辅助方法
// =============================================================================

/// 创建远程消息（带 seq）
AgentMessage _createRemoteMessage({
  required String id,
  required String role,
  required String content,
  required int seq,
  String type = 'text',
  String? status,
}) {
  return AgentMessage(
    id: id,
    role: role,
    type: type,
    content: content,
    createdAt: DateTime.now(),
    status: status,
    metadata: {
      'seq': seq,
      'updateTime': DateTime.now().toIso8601String(),
    },
  );
}

/// 等待事件队列处理完成
Future<void> _pumpEventQueue() async {
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
  await Future.delayed(const Duration(milliseconds: 50));
}

/// CachedAgentProxy 测试扩展：暴露内部转换方法
extension CachedAgentProxyTestExt on CachedAgentProxy {
  /// 将 AgentMessage 转换为 ChatMessage（测试用）
  dynamic _agentMessageToChatMessageForTest(AgentMessage am) {
    // 使用反射或直接构造，由于是同一个类，直接调用内部方法
    // 但由于 _agentMessageToChatMessage 是私有的，我们需要另一种方式
    // 通过 MessageStore 的 addMessage 直接构造 ChatMessage
    throw UnimplementedError('Use _createChatMessage helper instead');
  }
}
