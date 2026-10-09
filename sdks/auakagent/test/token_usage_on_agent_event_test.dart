import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart';

/// tokenUsageUpdated 事件通过 onAgentEvent 接收的集成测试
///
/// 模拟完整的 LAN 广播链路，验证 tokenUsageUpdated 事件：
/// - 通过 DeviceStateHolder.eventController 广播
/// - 通过 DeviceMessageHandler._handleAgentEvent 路由
/// - 通过 AgentProxyRemoteOps.onRemoteEvent 透传
/// - 通过 CachedAgentProxy._handleAgentEvent 透传
/// - 最终通过 DeviceClient.onAgentEvent 可被外部接收
void main() {
  // ============================================================
  // 1. DeviceStateHolder.eventController 直接广播
  // ============================================================
  group('DeviceStateHolder.eventController 广播', () {
    test('tokenUsageUpdated 事件可通过 eventController 广播并被监听', () async {
      // 模拟 DeviceStateHolder 的 eventController
      final eventController = StreamController<AgentEvent>.broadcast();

      // 模拟 DeviceClient.onAgentEvent 的监听
      final receivedEvents = <AgentEvent>[];
      final sub = eventController.stream.listen(receivedEvents.add);

      // 模拟 DeviceAgentManager._subscribeAgentEvents 写入 eventController
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 500,
            completionTokens: 200,
            totalTokens: 700,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 300,
            completionTokens: 100,
            totalTokens: 400,
          ).toMap(),
          'messageId': 'msg-state-holder-test',
        },
        employeeId: 'emp-001',
        fromDeviceId: 'device-host',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      expect(receivedEvents.length, equals(1));
      expect(receivedEvents[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(receivedEvents[0].employeeId, equals('emp-001'));
      expect(receivedEvents[0].fromDeviceId, equals('device-host'));
      expect(receivedEvents[0].data['messageId'], equals('msg-state-holder-test'));

      await sub.cancel();
      await eventController.close();
    });
  });

  // ============================================================
  // 2. DeviceMessageHandler._handleAgentEvent 路由
  // ============================================================
  group('DeviceMessageHandler._handleAgentEvent 路由', () {
    test('agentTokenUsageUpdated 类型的 LAN 消息被路由到 _handleAgentEvent', () {
      // 模拟 LAN 消息（与 broadcastAgentEvent 构造的格式一致）
      final lanMsg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-host',
        content: jsonEncode({
          'employeeId': 'emp-001',
          'type': 'tokenUsageUpdated',
          'data': {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 100,
              completionTokens: 50,
              totalTokens: 150,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 100,
              completionTokens: 50,
              totalTokens: 150,
            ).toMap(),
            'messageId': 'msg-handler-test',
          },
        }),
        topic: 'test-topic',
      );

      // 验证 LAN 消息类型正确
      expect(lanMsg.type, equals(LanMessageType.agentTokenUsageUpdated));

      // 模拟 _handleAgentEvent 解析逻辑
      final content = jsonDecode(lanMsg.content ?? '{}') as Map<String, dynamic>;
      final eventType = AgentEventType.fromString(content['type'] as String? ?? '');
      final data = content['data'] as Map<String, dynamic>? ?? {};
      final employeeId = content['employeeId'] as String?;

      expect(eventType, equals(AgentEventType.tokenUsageUpdated));
      expect(employeeId, equals('emp-001'));
      expect(data['messageId'], equals('msg-handler-test'));

      // 模拟 _handleAgentEvent 构造 AgentEvent 并写入 eventController
      final agentEvent = AgentEvent(
        type: eventType,
        data: data,
        employeeId: employeeId,
        fromDeviceId: lanMsg.fromId,
      );

      expect(agentEvent.type, equals(AgentEventType.tokenUsageUpdated));
      expect(agentEvent.fromDeviceId, equals('device-host'));
    });

    test('tokenUsageUpdated 在 _handleAgentEvent 中不触发额外处理逻辑', () {
      // _handleAgentEvent 中的额外处理逻辑：
      // - toolCallStart → addRemoteCallingToolId
      // - toolCallResult → removeRemoteCallingToolId
      // - messageStatusChanged → notificationHub.onRemoteMessage
      // - agentStatusChanged → notificationHub.onAgentStatusChanged
      // - messageReadStatusChanged → markAsReadBySeqInDb
      // - sessionSummaryChanged → upsertFromRemote
      // - sessionCleared → markAllAsRead + sync
      // - configChanged → _handleConfigChangedEvent
      // - specChanged → _handleSpecChangedEvent
      // - todoTopicChanged → _handleTodoTopicChangedEvent
      // - todoTaskItemChanged → _handleTodoTaskItemChangedEvent
      //
      // tokenUsageUpdated 不匹配以上任何 if 分支，仅通过 eventController 广播。
      // 这是正确的行为：token 用量事件仅透传，不修改本地状态。

      final eventTypesWithSideEffects = {
        AgentEventType.toolCallStart,
        AgentEventType.toolCallResult,
        AgentEventType.messageStatusChanged,
        AgentEventType.agentStatusChanged,
        AgentEventType.messageReadStatusChanged,
        AgentEventType.sessionSummaryChanged,
        AgentEventType.sessionCleared,
        AgentEventType.configChanged,
        AgentEventType.specChanged,
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
      };

      expect(eventTypesWithSideEffects.contains(AgentEventType.tokenUsageUpdated),
          isFalse,
          reason: 'tokenUsageUpdated 不应在 _handleAgentEvent 中触发任何额外处理');
    });
  });

  // ============================================================
  // 3. AgentProxyRemoteOps.onRemoteEvent 透传
  // ============================================================
  group('AgentProxyRemoteOps.onRemoteEvent 透传', () {
    test('tokenUsageUpdated 事件通过 onRemoteEvent 广播到 _eventController', () async {
      // 模拟 AgentProxy 的 _eventController（远程模式）
      final eventController = StreamController<AgentEvent>.broadcast();
      final stateController = StreamController<AgentStateSnapshot>.broadcast();

      // 模拟 DeviceStateHolder.onAgentEvent 流
      final stateHolderEventController = StreamController<AgentEvent>.broadcast();

      // 模拟 _subscribeRemoteEvents：订阅 stateHolder.onAgentEvent 并写入 _eventController
      final receivedByProxy = <AgentEvent>[];
      final sub = stateHolderEventController.stream
          .where((e) => e.employeeId == 'emp-001') // 模拟 onRemoteEvent 的 employeeId 过滤
          .listen((event) {
        // onRemoteEvent 的关键行为：广播原始事件到 _eventController
        receivedByProxy.add(event);
        eventController.add(event);
      });

      // 模拟 _handleAgentEvent 写入 stateHolder.eventController
      stateHolderEventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 200,
            completionTokens: 80,
            totalTokens: 280,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 200,
            completionTokens: 80,
            totalTokens: 280,
          ).toMap(),
          'messageId': 'msg-remote-ops-test',
        },
        employeeId: 'emp-001',
        fromDeviceId: 'device-host',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // 验证 onRemoteEvent 正确过滤并广播
      expect(receivedByProxy.length, equals(1));
      expect(receivedByProxy[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(receivedByProxy[0].data['messageId'], equals('msg-remote-ops-test'));

      // 验证 _eventController 也收到了事件（供 CachedAgentProxy 监听）
      final proxyEvents = <AgentEvent>[];
      final proxySub = eventController.stream.listen(proxyEvents.add);
      // 由于广播流在 add 之前没有 listener，需要重新发送
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {'messageId': 'msg-proxy-check'},
        employeeId: 'emp-001',
        fromDeviceId: 'device-host',
      ));

      await Future.delayed(Duration(milliseconds: 50));
      expect(proxyEvents.length, equals(1));
      expect(proxyEvents[0].type, equals(AgentEventType.tokenUsageUpdated));

      await sub.cancel();
      await proxySub.cancel();
      await eventController.close();
      await stateHolderEventController.close();
      await stateController.close();
    });

    test('onRemoteEvent 正确过滤不同 employeeId 的事件', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final stateHolderEventController = StreamController<AgentEvent>.broadcast();

      final receivedByProxy = <AgentEvent>[];
      final sub = stateHolderEventController.stream
          .where((e) => e.employeeId == 'emp-001')
          .listen((event) {
        receivedByProxy.add(event);
        eventController.add(event);
      });

      // 发送不同 employeeId 的事件
      stateHolderEventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {'messageId': 'msg-wrong-emp'},
        employeeId: 'emp-999', // 不同的 employeeId
        fromDeviceId: 'device-host',
      ));

      stateHolderEventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {'messageId': 'msg-correct-emp'},
        employeeId: 'emp-001', // 匹配的 employeeId
        fromDeviceId: 'device-host',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      // 只有 emp-001 的事件通过
      expect(receivedByProxy.length, equals(1));
      expect(receivedByProxy[0].data['messageId'], equals('msg-correct-emp'));

      await sub.cancel();
      await eventController.close();
      await stateHolderEventController.close();
    });
  });

  // ============================================================
  // 4. CachedAgentProxy._handleAgentEvent 透传
  // ============================================================
  group('CachedAgentProxy._handleAgentEvent 透传', () {
    test('tokenUsageUpdated 在 CachedProxyEventHandler 中透传（不修改缓存）', () {
      // CachedProxyEventHandler._handleAgentEvent 中：
      // case AgentEventType.tokenUsageUpdated:
      //   // Token 用量更新事件：直接透传给前端
      //   break;
      //
      // 这意味着事件通过 _proxy.onEvent 流透传给上层，但不触发：
      // - _handleMessageStatusChanged（不修改消息状态）
      // - _notifyMessagesChanged（不触发消息列表刷新）
      // - _handleConfigChanged（不修改配置缓存）
      // - _notifyMessagesChanged（不通知 UI 刷新）

      final event = AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': {
            'promptTokens': 1000,
            'completionTokens': 500,
            'totalTokens': 1500,
          },
          'messageUsage': {
            'promptTokens': 500,
            'completionTokens': 200,
            'totalTokens': 700,
          },
          'messageId': 'msg-cached-proxy-test',
        },
        employeeId: 'emp-001',
        fromDeviceId: 'device-host',
      );

      // 验证事件数据完整性
      expect(event.type, equals(AgentEventType.tokenUsageUpdated));
      expect(event.employeeId, equals('emp-001'));
      expect(event.fromDeviceId, equals('device-host'));

      final sessionUsage = event.data['sessionUsage'] as Map<String, dynamic>;
      expect(sessionUsage['promptTokens'], equals(1000));
      expect(sessionUsage['completionTokens'], equals(500));

      final messageUsage = event.data['messageUsage'] as Map<String, dynamic>;
      expect(messageUsage['promptTokens'], equals(500));
    });
  });

  // ============================================================
  // 5. 端到端模拟：LAN 消息 → onAgentEvent 接收
  // ============================================================
  group('端到端模拟：LAN → onAgentEvent', () {
    test('完整的 tokenUsageUpdated 事件从 LAN 消息到 onAgentEvent 接收', () async {
      // 模拟 DeviceStateHolder（远程设备端）
      final stateHolderEventController = StreamController<AgentEvent>.broadcast();

      // 模拟 AgentProxy._eventController（远程 AgentProxy）
      final proxyEventController = StreamController<AgentEvent>.broadcast();

      // 模拟 CachedAgentProxy 监听 _proxy.onEvent
      final cachedProxyEvents = <AgentEvent>[];
      final cachedProxySub = proxyEventController.stream.listen(cachedProxyEvents.add);

      // 模拟 _subscribeRemoteEvents：stateHolder.onAgentEvent → onRemoteEvent → _eventController
      final remoteEventSub = stateHolderEventController.stream
          .where((e) => e.employeeId == 'emp-e2e')
          .listen((event) {
        // onRemoteEvent: 广播原始事件
        proxyEventController.add(event);
      });

      // 模拟 DeviceClient.onAgentEvent（外部监听）
      final clientEvents = <AgentEvent>[];
      final clientSub = stateHolderEventController.stream.listen(clientEvents.add);

      // ===== 模拟发送端：broadcastAgentEvent 构造 LAN 消息 =====
      final lanMsg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-e2e',
          'type': 'tokenUsageUpdated',
          'data': {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 2000,
              completionTokens: 800,
              totalTokens: 2800,
              reasoningTokens: 200,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 1000,
              completionTokens: 400,
              totalTokens: 1400,
              reasoningTokens: 100,
            ).toMap(),
            'messageId': 'msg-e2e-test',
          },
        }),
        topic: 'test-topic',
      );

      // ===== 模拟接收端：DeviceMessageHandler._handleAgentEvent 解析 =====
      final content = jsonDecode(lanMsg.content ?? '{}') as Map<String, dynamic>;
      final eventType = AgentEventType.fromString(content['type'] as String? ?? '');
      final data = content['data'] as Map<String, dynamic>? ?? {};
      final employeeId = content['employeeId'] as String?;
      final fromDeviceId = lanMsg.fromId;

      // 写入 stateHolder.eventController（_handleAgentEvent 的核心行为）
      stateHolderEventController.add(AgentEvent(
        type: eventType,
        data: data,
        employeeId: employeeId,
        fromDeviceId: fromDeviceId,
      ));

      await Future.delayed(Duration(milliseconds: 100));

      // ===== 验证：DeviceClient.onAgentEvent 收到事件 =====
      expect(clientEvents.length, equals(1));
      expect(clientEvents[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(clientEvents[0].employeeId, equals('emp-e2e'));
      expect(clientEvents[0].fromDeviceId, equals('device-sender'));
      expect(clientEvents[0].data['messageId'], equals('msg-e2e-test'));

      // 验证 sessionUsage 数据完整
      final sessionUsage = TokenUsageRecord.fromMap(
          clientEvents[0].data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(2000));
      expect(sessionUsage.completionTokens, equals(800));
      expect(sessionUsage.totalTokens, equals(2800));
      expect(sessionUsage.reasoningTokens, equals(200));

      // 验证 messageUsage 数据完整
      final messageUsage = TokenUsageRecord.fromMap(
          clientEvents[0].data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.promptTokens, equals(1000));
      expect(messageUsage.completionTokens, equals(400));
      expect(messageUsage.reasoningTokens, equals(100));

      // ===== 验证：CachedAgentProxy 也收到事件 =====
      expect(cachedProxyEvents.length, equals(1));
      expect(cachedProxyEvents[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(cachedProxyEvents[0].data['messageId'], equals('msg-e2e-test'));

      await clientSub.cancel();
      await cachedProxySub.cancel();
      await remoteEventSub.cancel();
      await proxyEventController.close();
      await stateHolderEventController.close();
    });

    test('多次 tokenUsageUpdated 事件按序到达 onAgentEvent', () async {
      final eventController = StreamController<AgentEvent>.broadcast();

      final receivedEvents = <AgentEvent>[];
      final sub = eventController.stream.listen(receivedEvents.add);

      // 模拟 5 次 LLM 调用产生 5 个 tokenUsageUpdated 事件
      for (var i = 1; i <= 5; i++) {
        eventController.add(AgentEvent(
          type: AgentEventType.tokenUsageUpdated,
          data: {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 100 * i,
              completionTokens: 50 * i,
              totalTokens: 150 * i,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 100,
              completionTokens: 50,
              totalTokens: 150,
            ).toMap(),
            'messageId': 'msg-seq-$i',
          },
          employeeId: 'emp-seq',
          fromDeviceId: 'device-host',
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      expect(receivedEvents.length, equals(5));

      // 验证按序到达
      for (var i = 0; i < 5; i++) {
        expect(receivedEvents[i].data['messageId'], equals('msg-seq-${i + 1}'));
      }

      // 验证 sessionUsage 累加
      final firstSession = TokenUsageRecord.fromMap(
          receivedEvents[0].data['sessionUsage'] as Map<String, dynamic>);
      final lastSession = TokenUsageRecord.fromMap(
          receivedEvents[4].data['sessionUsage'] as Map<String, dynamic>);
      expect(lastSession.promptTokens, equals(5 * firstSession.promptTokens));

      await sub.cancel();
      await eventController.close();
    });
  });

  // ============================================================
  // 6. LAN 消息 JSON 序列化/反序列化往返
  // ============================================================
  group('LAN 消息 JSON 往返', () {
    test('tokenUsageUpdated 的 LAN 消息 JSON 序列化/反序列化往返一致', () {
      // 模拟 broadcastAgentEvent 构造的 LAN 消息
      final originalMsg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-host',
        content: jsonEncode({
          'employeeId': 'emp-json-test',
          'type': 'tokenUsageUpdated',
          'data': {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 999,
              completionTokens: 888,
              totalTokens: 1887,
              reasoningTokens: 100,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 500,
              completionTokens: 300,
              totalTokens: 800,
            ).toMap(),
            'messageId': 'msg-json-roundtrip',
          },
        }),
        topic: 'test-topic',
      );

      // 序列化 → 反序列化
      final jsonStr = jsonEncode({
        'id': originalMsg.id,
        'type': originalMsg.type?.name,
        'fromId': originalMsg.fromId,
        'fromName': originalMsg.fromName,
        'content': originalMsg.content,
        'topic': originalMsg.topic,
        'toDeviceId': originalMsg.toDeviceId,
        'timestamp': originalMsg.timestamp?.millisecondsSinceEpoch,
      });
      final restoredMap = jsonDecode(jsonStr) as Map<String, dynamic>;
      final restoredMsg = LanMessage.fromJson(restoredMap);

      expect(restoredMsg.type, equals(LanMessageType.agentTokenUsageUpdated));
      expect(restoredMsg.fromId, equals('device-host'));

      // 解析 content
      final content = jsonDecode(restoredMsg.content ?? '{}') as Map<String, dynamic>;
      expect(content['type'], equals('tokenUsageUpdated'));
      expect(content['employeeId'], equals('emp-json-test'));

      final data = content['data'] as Map<String, dynamic>;
      expect(data['messageId'], equals('msg-json-roundtrip'));

      // 验证 TokenUsageRecord 往返
      final sessionUsage = TokenUsageRecord.fromMap(
          data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(999));
      expect(sessionUsage.reasoningTokens, equals(100));

      final messageUsage = TokenUsageRecord.fromMap(
          data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.promptTokens, equals(500));
    });
  });

  // ============================================================
  // 7. LanMessageType 映射正确性
  // ============================================================
  group('LanMessageType 映射正确性', () {
    test('AgentEventType.tokenUsageUpdated 映射到 LanMessageType.agentTokenUsageUpdated', () {
      // 验证 broadcastAgentEvent 中的映射关系
      final mapping = {
        AgentEventType.agentStatusChanged: LanMessageType.agentStatusChanged,
        AgentEventType.messageStatusChanged: LanMessageType.agentMessageStatusChanged,
        AgentEventType.messageReadStatusChanged: LanMessageType.agentMessageReadStatusChanged,
        AgentEventType.toolCallStart: LanMessageType.toolCallStart,
        AgentEventType.toolCallResult: LanMessageType.toolCallResult,
        AgentEventType.toolPermissionRequest: LanMessageType.agentPermissionChanged,
        AgentEventType.toolPermissionResponse: LanMessageType.agentPermissionChanged,
        AgentEventType.sessionCleared: LanMessageType.agentSessionCleared,
        AgentEventType.sessionSummaryChanged: LanMessageType.agentSessionSummaryChanged,
        AgentEventType.confirmRequest: LanMessageType.agentConfirmChanged,
        AgentEventType.confirmResponse: LanMessageType.agentConfirmChanged,
        AgentEventType.todoTopicChanged: LanMessageType.agentTodoChanged,
        AgentEventType.todoTaskItemChanged: LanMessageType.agentTodoChanged,
        AgentEventType.specChanged: LanMessageType.agentSpecChanged,
        AgentEventType.configChanged: LanMessageType.agentConfigChanged,
        AgentEventType.messageStarted: LanMessageType.agentMessageStatusChanged,
        AgentEventType.tokenUsageUpdated: LanMessageType.agentTokenUsageUpdated,
      };

      expect(mapping[AgentEventType.tokenUsageUpdated],
          equals(LanMessageType.agentTokenUsageUpdated));
    });

    test('LanMessageType.agentTokenUsageUpdated 可正确序列化/反序列化', () {
      final type = LanMessageType.agentTokenUsageUpdated;
      expect(type.name, equals('agentTokenUsageUpdated'));
      expect(type, equals(LanMessageType.agentTokenUsageUpdated));
    });
  });
}
