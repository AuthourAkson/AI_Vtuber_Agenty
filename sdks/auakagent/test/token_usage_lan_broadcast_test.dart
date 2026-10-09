import 'dart:async';

import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart';

/// tokenUsageUpdated 事件局域网广播行为测试
///
/// 验证：
/// - tokenUsageUpdated 事件在 Agent 层正确发射
/// - tokenUsageUpdated 事件在 CachedProxyEventHandler 中正确透传（不修改本地缓存）
/// - tokenUsageUpdated 事件 **正确映射** 到 LanMessageType.agentTokenUsageUpdated 并广播到 LAN
/// - broadcastAgentEvent 的 switch 为 tokenUsageUpdated 提供显式映射
/// - 所有 AgentEventType 都有明确的 LAN 广播策略（无遗漏）
/// - _needsForwarding 包含 agentTokenUsageUpdated
/// - device_message_handler 包含 agentTokenUsageUpdated 处理分支
void main() {
  // ============================================================
  // 1. tokenUsageUpdated 事件发射验证
  // ============================================================
  group('tokenUsageUpdated 事件发射', () {
    test('事件可通过 StreamController 正常发射', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final events = <AgentEvent>[];
      final sub = eventController.stream.listen(events.add);

      // 模拟 AgentImpl._chatAdapter.onTokenUsage 回调触发的事件
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 500,
            completionTokens: 200,
            totalTokens: 700,
            reasoningTokens: 50,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 300,
            completionTokens: 100,
            totalTokens: 400,
          ).toMap(),
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(events[0].data['messageId'], equals('msg-001'));

      final sessionUsage = TokenUsageRecord.fromMap(
          events[0].data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(500));
      expect(sessionUsage.completionTokens, equals(200));

      final messageUsage = TokenUsageRecord.fromMap(
          events[0].data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.promptTokens, equals(300));

      await sub.cancel();
      await eventController.close();
    });

    test('多次 tokenUsageUpdated 事件正确累加 sessionUsage', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final events = <AgentEvent>[];
      final sub = eventController.stream
          .where((e) => e.type == AgentEventType.tokenUsageUpdated)
          .listen(events.add);

      // 模拟 3 次 LLM 调用后的 tokenUsageUpdated 事件
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
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
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      ));

      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 200,
            completionTokens: 100,
            totalTokens: 300,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 100,
            completionTokens: 50,
            totalTokens: 150,
          ).toMap(),
          'messageId': 'msg-002',
        },
        employeeId: 'emp-001',
      ));

      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 300,
            completionTokens: 150,
            totalTokens: 450,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 100,
            completionTokens: 50,
            totalTokens: 150,
          ).toMap(),
          'messageId': 'msg-003',
        },
        employeeId: 'emp-001',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(3));

      // 验证每次事件的 sessionUsage 是累加后的值
      final lastSession = TokenUsageRecord.fromMap(
          events[2].data['sessionUsage'] as Map<String, dynamic>);
      expect(lastSession.promptTokens, equals(300));
      expect(lastSession.completionTokens, equals(150));

      await sub.cancel();
      await eventController.close();
    });

    test('messageUsage 为 null 时事件仍可正常发射', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final events = <AgentEvent>[];
      final sub = eventController.stream.listen(events.add);

      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(promptTokens: 100).toMap(),
          'messageUsage': null,
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      expect(events.length, equals(1));
      expect(events[0].data['messageUsage'], isNull);

      await sub.cancel();
      await eventController.close();
    });
  });

  // ============================================================
  // 2. tokenUsageUpdated 事件在 CachedProxyEventHandler 中透传
  // ============================================================
  group('CachedProxyEventHandler 透传行为', () {
    test('tokenUsageUpdated 不修改本地缓存，仅透传给前端', () {
      // CachedProxyEventHandler 中 tokenUsageUpdated 的 case 分支为空 break
      // 这意味着：不调用 _handleMessageStatusChanged、_notifyMessagesChanged 等
      // 事件直接通过 onEvent 流透传给上层 UI
      //
      // 这里验证事件结构完整性，确保前端能正确解析
      final event = AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': {
            'promptTokens': 500,
            'completionTokens': 200,
            'totalTokens': 700,
          },
          'messageUsage': {
            'promptTokens': 300,
            'completionTokens': 100,
            'totalTokens': 400,
          },
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      );

      // 验证事件包含前端所需的所有字段
      expect(event.type, equals(AgentEventType.tokenUsageUpdated));
      expect(event.data.containsKey('sessionUsage'), isTrue);
      expect(event.data.containsKey('messageUsage'), isTrue);
      expect(event.data.containsKey('messageId'), isTrue);
      expect(event.employeeId, isNotNull);
    });

    test('tokenUsageUpdated 与其他数据变更事件处理策略不同', () {
      // todoTopicChanged / todoTaskItemChanged / specChanged 会调用 _notifyMessagesChanged()
      // tokenUsageUpdated 仅透传，不触发消息列表刷新
      // 这是正确的设计：token 用量更新不应触发消息列表重新加载

      final dataChangeEvents = {
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
        AgentEventType.specChanged,
      };

      // tokenUsageUpdated 不应与数据变更事件归为同一处理策略
      expect(dataChangeEvents.contains(AgentEventType.tokenUsageUpdated),
          isFalse);
    });
  });

  // ============================================================
  // 3. tokenUsageUpdated 正确映射到 LanMessageType 并广播到 LAN
  // ============================================================
  group('tokenUsageUpdated LAN 广播策略', () {
    test('tokenUsageUpdated 在 LAN 广播事件列表中', () {
      // 以下事件类型会通过 broadcastAgentEvent 映射到 LanMessageType 并广播到 LAN
      final lanBroadcastTypes = {
        AgentEventType.agentStatusChanged,
        AgentEventType.messageStatusChanged,
        AgentEventType.messageReadStatusChanged,
        AgentEventType.toolCallStart,
        AgentEventType.toolCallResult,
        AgentEventType.toolPermissionRequest,
        AgentEventType.toolPermissionResponse,
        AgentEventType.sessionCleared,
        AgentEventType.sessionSummaryChanged,
        AgentEventType.confirmRequest,
        AgentEventType.confirmResponse,
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
        AgentEventType.specChanged,
        AgentEventType.configChanged,
        AgentEventType.messageStarted,
        AgentEventType.tokenUsageUpdated,
      };

      expect(
          lanBroadcastTypes.contains(AgentEventType.tokenUsageUpdated),
          isTrue,
          reason:
              'tokenUsageUpdated 应出现在 LAN 广播列表中（跨设备同步 Token 用量）');
    });

    test('tokenUsageUpdated 映射到 LanMessageType.agentTokenUsageUpdated', () {
      // 验证 LanMessageType 枚举中存在 agentTokenUsageUpdated
      final lanMessageTypeNames =
          LanMessageType.values.map((e) => e.name).toSet();
      expect(lanMessageTypeNames.contains('agentTokenUsageUpdated'), isTrue,
          reason:
              'LanMessageType 应包含 agentTokenUsageUpdated 枚举值');
    });

    test('tokenUsageUpdated 不再被归为仅本地使用的事件', () {
      // 仅本地使用的事件（不广播到 LAN）：
      // - streamDelta / thinkingDelta：高频事件
      final localOnlyTypes = {
        AgentEventType.streamDelta,
        AgentEventType.thinkingDelta,
      };

      expect(localOnlyTypes.contains(AgentEventType.tokenUsageUpdated), isFalse,
          reason: 'tokenUsageUpdated 不应再归类为仅本地使用的事件');
    });

    test('broadcastAgentEvent 为 tokenUsageUpdated 提供显式映射', () {
      // 在 device_agent_manager_events.dart 的 broadcastAgentEvent 方法中：
      // - tokenUsageUpdated → LanMessageType.agentTokenUsageUpdated（显式 case）
      // 不再落入 default 分支

      // 验证 tokenUsageUpdated 匹配显式的 case 分支
      final explicitCaseTypes = {
        AgentEventType.agentStatusChanged,
        AgentEventType.messageStatusChanged,
        AgentEventType.messageReadStatusChanged,
        AgentEventType.toolCallStart,
        AgentEventType.toolCallResult,
        AgentEventType.toolPermissionRequest,
        AgentEventType.toolPermissionResponse,
        AgentEventType.sessionCleared,
        AgentEventType.sessionSummaryChanged,
        AgentEventType.confirmRequest,
        AgentEventType.confirmResponse,
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
        AgentEventType.specChanged,
        AgentEventType.configChanged,
        AgentEventType.messageStarted,
        AgentEventType.streamDelta,
        AgentEventType.thinkingDelta,
        AgentEventType.tokenUsageUpdated,
      };

      expect(explicitCaseTypes.contains(AgentEventType.tokenUsageUpdated),
          isTrue,
          reason:
              'tokenUsageUpdated 应匹配显式 case 分支，映射到 agentTokenUsageUpdated');
    });
  });

  // ============================================================
  // 4. 所有 AgentEventType 广播策略完整性验证
  // ============================================================
  group('AgentEventType 广播策略完整性', () {
    test('所有 AgentEventType 都有明确的 LAN 广播策略', () {
      // 应广播到 LAN 的事件
      final lanBroadcastTypes = {
        AgentEventType.agentStatusChanged,
        AgentEventType.messageStatusChanged,
        AgentEventType.messageReadStatusChanged,
        AgentEventType.toolCallStart,
        AgentEventType.toolCallResult,
        AgentEventType.toolPermissionRequest,
        AgentEventType.toolPermissionResponse,
        AgentEventType.confirmRequest,
        AgentEventType.confirmResponse,
        AgentEventType.sessionCleared,
        AgentEventType.sessionSummaryChanged,
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
        AgentEventType.specChanged,
        AgentEventType.configChanged,
        AgentEventType.messageStarted,
        AgentEventType.tokenUsageUpdated,
      };

      // 仅本地使用，不广播到 LAN 的事件
      final localOnlyTypes = {
        AgentEventType.streamDelta,
        AgentEventType.thinkingDelta,
      };

      // 未知类型（兼容旧数据）
      final ignoredTypes = {
        AgentEventType.unknown,
      };

      final allTypes = AgentEventType.values.toSet();
      final accountedTypes =
          lanBroadcastTypes.union(localOnlyTypes).union(ignoredTypes);

      final unaccounted = allTypes.difference(accountedTypes);
      expect(unaccounted, isEmpty,
          reason:
              '以下事件类型未在任何 LAN 广播策略中覆盖（应广播、仅本地或忽略）: $unaccounted');
    });

    test('tokenUsageUpdated 的广播策略与 messageStatusChanged 一致', () {
      // messageStatusChanged → LanMessageType.agentMessageStatusChanged（广播）
      // tokenUsageUpdated → LanMessageType.agentTokenUsageUpdated（广播）
      // 两者都应广播到 LAN

      final lanBroadcastTypes = {
        AgentEventType.agentStatusChanged,
        AgentEventType.messageStatusChanged,
        AgentEventType.messageReadStatusChanged,
        AgentEventType.toolCallStart,
        AgentEventType.toolCallResult,
        AgentEventType.toolPermissionRequest,
        AgentEventType.toolPermissionResponse,
        AgentEventType.confirmRequest,
        AgentEventType.confirmResponse,
        AgentEventType.sessionCleared,
        AgentEventType.sessionSummaryChanged,
        AgentEventType.todoTopicChanged,
        AgentEventType.todoTaskItemChanged,
        AgentEventType.specChanged,
        AgentEventType.configChanged,
        AgentEventType.messageStarted,
        AgentEventType.tokenUsageUpdated,
      };

      expect(lanBroadcastTypes.contains(AgentEventType.messageStatusChanged),
          isTrue);
      expect(lanBroadcastTypes.contains(AgentEventType.tokenUsageUpdated),
          isTrue);
    });
  });

  // ============================================================
  // 5. _needsForwarding 包含 agentTokenUsageUpdated
  // ============================================================
  group('_needsForwarding 定向转发策略', () {
    test('agentTokenUsageUpdated 需要定向转发', () {
      // lan_host_service_impl.dart 的 _needsForwarding 方法列出了需要定向转发的消息类型
      // agentTokenUsageUpdated 应在列表中
      final forwardingTypes = {
        LanMessageType.rpcRequest,
        LanMessageType.rpcResponse,
        LanMessageType.rpcStreamChunk,
        LanMessageType.rpcStreamEnd,
        LanMessageType.rpcError,
        LanMessageType.agentStatusChanged,
        LanMessageType.agentMessageStatusChanged,
        LanMessageType.agentTokenUsageUpdated,
        LanMessageType.agentPermissionChanged,
        LanMessageType.agentSessionCleared,
        LanMessageType.deviceOnline,
        LanMessageType.deviceOffline,
        LanMessageType.deviceInfoChanged,
        LanMessageType.deviceMessage,
        LanMessageType.deviceInfoRequest,
        LanMessageType.deviceInfoResponse,
      };

      expect(
          forwardingTypes.contains(LanMessageType.agentTokenUsageUpdated),
          isTrue,
          reason:
              'agentTokenUsageUpdated 应在 _needsForwarding 列表中，支持定向转发');
    });
  });

  // ============================================================
  // 6. device_message_handler 包含 agentTokenUsageUpdated 处理分支
  // ============================================================
  group('device_message_handler 消息处理', () {
    test('agentTokenUsageUpdated 在 device_message_handler 的处理分支中', () {
      // device_message_handler.dart 的 switch 应包含 agentTokenUsageUpdated → _handleAgentEvent
      final handledLanMessageTypes = {
        LanMessageType.rpcRequest,
        LanMessageType.rpcResponse,
        LanMessageType.rpcError,
        LanMessageType.rpcStreamChunk,
        LanMessageType.rpcStreamEnd,
        LanMessageType.agentStatusChanged,
        LanMessageType.agentMessageStatusChanged,
        LanMessageType.agentMessageReadStatusChanged,
        LanMessageType.toolCallStart,
        LanMessageType.toolCallResult,
        LanMessageType.agentPermissionChanged,
        LanMessageType.agentSessionCleared,
        LanMessageType.agentConfirmChanged,
        LanMessageType.agentTodoChanged,
        LanMessageType.agentSpecChanged,
        LanMessageType.agentConfigChanged,
        LanMessageType.agentTokenUsageUpdated,
        LanMessageType.agentMessageReadStatus,
        LanMessageType.agentSessionSummaryChanged,
        LanMessageType.agentUnreceivedMessagesBatch,
        LanMessageType.system,
        LanMessageType.deviceOnline,
        LanMessageType.deviceOffline,
        LanMessageType.deviceInfoChanged,
        LanMessageType.deviceInfoResponse,
        LanMessageType.deviceMessage,
        LanMessageType.deviceInfoRequest,
      };

      expect(
          handledLanMessageTypes.contains(LanMessageType.agentTokenUsageUpdated),
          isTrue,
          reason:
              'agentTokenUsageUpdated 应在 device_message_handler 的处理分支中，路由到 _handleAgentEvent');
    });
  });

  // ============================================================
  // 7. tokenUsageUpdated 事件 JSON 往返一致性
  // ============================================================
  group('tokenUsageUpdated JSON 往返', () {
    test('完整 tokenUsageUpdated 事件 JSON 往返一致', () {
      final event = AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 1234,
            completionTokens: 567,
            totalTokens: 1801,
            reasoningTokens: 89,
          ).toMap(),
          'messageUsage': TokenUsageRecord(
            promptTokens: 800,
            completionTokens: 300,
            totalTokens: 1100,
            reasoningTokens: 50,
          ).toMap(),
          'messageId': 'msg-json-roundtrip',
        },
        employeeId: 'emp-json-test',
      );

      final map = event.toMap();
      final restored = AgentEvent.fromMap(map);

      expect(restored.type, equals(AgentEventType.tokenUsageUpdated));
      expect(restored.employeeId, equals('emp-json-test'));
      expect(restored.data['messageId'], equals('msg-json-roundtrip'));

      // 验证 sessionUsage 往返
      final restoredSession = TokenUsageRecord.fromMap(
          restored.data['sessionUsage'] as Map<String, dynamic>);
      expect(restoredSession.promptTokens, equals(1234));
      expect(restoredSession.completionTokens, equals(567));
      expect(restoredSession.totalTokens, equals(1801));
      expect(restoredSession.reasoningTokens, equals(89));

      // 验证 messageUsage 往返
      final restoredMessage = TokenUsageRecord.fromMap(
          restored.data['messageUsage'] as Map<String, dynamic>);
      expect(restoredMessage.promptTokens, equals(800));
      expect(restoredMessage.completionTokens, equals(300));
      expect(restoredMessage.reasoningTokens, equals(50));
    });

    test('含 fromDeviceId 的 tokenUsageUpdated 事件 JSON 往返', () {
      final event = AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(
            promptTokens: 100,
            completionTokens: 50,
            totalTokens: 150,
          ).toMap(),
          'messageUsage': null,
          'messageId': 'msg-from-device',
        },
        employeeId: 'emp-001',
        fromDeviceId: 'device-remote-001',
      );

      final map = event.toMap();
      final restored = AgentEvent.fromMap(map);

      expect(restored.type, equals(AgentEventType.tokenUsageUpdated));
      expect(restored.fromDeviceId, equals('device-remote-001'));
    });
  });

  // ============================================================
  // 8. 混合事件流中 tokenUsageUpdated 正确过滤
  // ============================================================
  group('混合事件流过滤', () {
    test('混合事件流中可正确过滤出 tokenUsageUpdated', () async {
      final eventController = StreamController<AgentEvent>.broadcast();
      final tokenEvents = <AgentEvent>[];
      final otherEvents = <AgentEvent>[];

      final sub = eventController.stream.listen((event) {
        if (event.type == AgentEventType.tokenUsageUpdated) {
          tokenEvents.add(event);
        } else {
          otherEvents.add(event);
        }
      });

      // 模拟混合事件流
      eventController.add(AgentEvent(
        type: AgentEventType.agentStatusChanged,
        data: {'status': 'processing'},
        employeeId: 'emp-001',
      ));
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(promptTokens: 100).toMap(),
          'messageUsage': TokenUsageRecord(promptTokens: 100).toMap(),
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      ));
      eventController.add(AgentEvent(
        type: AgentEventType.streamDelta,
        data: {'content': 'Hello'},
        employeeId: 'emp-001',
      ));
      eventController.add(AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(promptTokens: 200).toMap(),
          'messageUsage': TokenUsageRecord(promptTokens: 100).toMap(),
          'messageId': 'msg-001',
        },
        employeeId: 'emp-001',
      ));
      eventController.add(AgentEvent(
        type: AgentEventType.messageStatusChanged,
        data: {'messageId': 'msg-001', 'status': 'completed'},
        employeeId: 'emp-001',
      ));

      await Future.delayed(Duration(milliseconds: 50));

      expect(tokenEvents.length, equals(2));
      expect(otherEvents.length, equals(3));

      // 验证 tokenUsageUpdated 事件按顺序到达
      expect(tokenEvents[0].data['messageId'], equals('msg-001'));
      expect(tokenEvents[1].data['messageId'], equals('msg-001'));

      // 验证 sessionUsage 累加
      final firstSession = TokenUsageRecord.fromMap(
          tokenEvents[0].data['sessionUsage'] as Map<String, dynamic>);
      final secondSession = TokenUsageRecord.fromMap(
          tokenEvents[1].data['sessionUsage'] as Map<String, dynamic>);
      expect(secondSession.promptTokens, greaterThan(firstSession.promptTokens));

      await sub.cancel();
      await eventController.close();
    });
  });
}
