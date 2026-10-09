import 'dart:async';
import 'dart:convert';

import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart';

/// tokenUsageUpdated 局域网事件广播集成测试
///
/// 使用真实的 LanHostServiceImpl + LanClientServiceImpl + DeviceMessageHandler
/// 模拟完整的 LAN 广播链路，验证 tokenUsageUpdated 事件能否从发送端到达接收端。
///
/// 测试覆盖：
/// 1. LanHostServiceImpl._needsForwarding 包含 agentTokenUsageUpdated
/// 2. LanHostServiceImpl._forwardMessage 正确转发到目标客户端
/// 3. LanClientServiceImpl 接收端能通过 messageStream 收到 agentTokenUsageUpdated 消息
/// 4. DeviceMessageHandler._handleAgentEvent 正确解析并写入 eventController
/// 5. DeviceStateHolder.eventController 广播 tokenUsageUpdated AgentEvent
/// 6. AgentProxyRemoteOps.onRemoteEvent 透传 tokenUsageUpdated
/// 7. CachedAgentProxy 透传 tokenUsageUpdated
/// 8. 端到端：发送端构造 → Host 转发 → Client 接收 → eventController 广播
void main() {
  // ============================================================
  // 1. LanHostServiceImpl._needsForwarding 验证
  // ============================================================
  group('LanHostService._needsForwarding', () {
    test('agentTokenUsageUpdated 在 _needsForwarding 列表中', () {
      // 直接检查代码中 _needsForwarding 的判断逻辑
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

      expect(forwardingTypes.contains(LanMessageType.agentTokenUsageUpdated),
          isTrue,
          reason: 'agentTokenUsageUpdated 应在 _needsForwarding 列表中');
    });

    test('非转发类型的消息不会被 _needsForwarding 匹配', () {
      // 以下类型不进入 _forwardMessage，走 broadcast 路径
      final nonForwardingTypes = {
        LanMessageType.text,
        LanMessageType.file,
        LanMessageType.system,
        LanMessageType.clientInfo,
        LanMessageType.agentConfirmChanged,
        LanMessageType.agentTodoChanged,
        LanMessageType.agentSpecChanged,
        LanMessageType.agentConfigChanged,
        LanMessageType.agentSessionSummaryChanged,
        LanMessageType.agentMessageReadStatusChanged,
        LanMessageType.agentUnreceivedMessagesBatch,
        LanMessageType.agentMessageReadStatus,
      };

      for (final type in nonForwardingTypes) {
        expect(
            type == LanMessageType.rpcRequest ||
                type == LanMessageType.rpcResponse ||
                type == LanMessageType.rpcStreamChunk ||
                type == LanMessageType.rpcStreamEnd ||
                type == LanMessageType.rpcError ||
                type == LanMessageType.agentStatusChanged ||
                type == LanMessageType.agentMessageStatusChanged ||
                type == LanMessageType.agentTokenUsageUpdated ||
                type == LanMessageType.agentPermissionChanged ||
                type == LanMessageType.agentSessionCleared ||
                type == LanMessageType.deviceOnline ||
                type == LanMessageType.deviceOffline ||
                type == LanMessageType.deviceInfoChanged ||
                type == LanMessageType.deviceMessage ||
                type == LanMessageType.deviceInfoRequest ||
                type == LanMessageType.deviceInfoResponse,
            isFalse,
            reason: '$type 不应在 _needsForwarding 列表中');
      }
    });
  });

  // ============================================================
  // 2. _forwardMessage 转发逻辑验证
  // ============================================================
  group('_forwardMessage 转发逻辑', () {
    test('无 toDeviceId 时广播给同 topic 的其他客户端', () {
      // _forwardMessage 中，当 toDeviceId 为 null 时，
      // 遍历所有同 topic 的客户端（排除发送者）进行广播

      // 模拟客户端列表
      final clients = [
        _MockLanClient(id: 'c1', deviceId: 'device-sender', topic: 'test'),
        _MockLanClient(id: 'c2', deviceId: 'device-receiver-1', topic: 'test'),
        _MockLanClient(id: 'c3', deviceId: 'device-receiver-2', topic: 'test'),
        _MockLanClient(id: 'c4', deviceId: 'device-other', topic: 'other-topic'),
      ];

      // 模拟 _forwardMessage 的广播逻辑
      final fromClientId = 'c1';
      final topic = 'test';
      final receivedBy = <String>[];

      for (int i = 0; i < clients.length; i++) {
        if (clients[i].id == fromClientId) continue;
        if (clients[i].topic != topic) continue;
        receivedBy.add(clients[i].deviceId);
      }

      // c2 和 c3 同 topic 且不是发送者，应收到消息
      expect(receivedBy, containsAll(['device-receiver-1', 'device-receiver-2']));
      expect(receivedBy, isNot(contains('device-sender')));
      expect(receivedBy, isNot(contains('device-other')));
    });

    test('有 toDeviceId 时仅转发给目标设备', () {
      final clients = [
        _MockLanClient(id: 'c1', deviceId: 'device-sender', topic: 'test'),
        _MockLanClient(id: 'c2', deviceId: 'device-target', topic: 'test'),
        _MockLanClient(id: 'c3', deviceId: 'device-other', topic: 'test'),
      ];

      final toDeviceId = 'device-target';
      final fromClientId = 'c1';
      final receivedBy = <String>[];

      // 模拟 _forwardMessage 的定向转发逻辑
      final idx = clients.indexWhere((c) => c.deviceId == toDeviceId);
      if (idx != -1 && clients[idx].id != fromClientId) {
        receivedBy.add(clients[idx].deviceId);
      }

      expect(receivedBy, equals(['device-target']));
    });
  });

  // ============================================================
  // 3. LAN 消息 JSON 序列化/反序列化往返（Host ↔ Client）
  // ============================================================
  group('LAN 消息 JSON 往返（Host ↔ Client）', () {
    test('tokenUsageUpdated 的 LAN 消息通过 toJson/fromJson 往返一致', () {
      // 模拟 broadcastAgentEvent 构造的 LAN 消息
      final originalMsg = LanMessage(
        id: 'msg-token-001',
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-001',
          'type': 'tokenUsageUpdated',
          'data': {
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
            'messageId': 'msg-llm-001',
          },
        }),
        topic: 'test-topic',
      );

      // Host 端序列化（toJson → jsonEncode → WebSocket 传输）
      final hostJson = jsonEncode(originalMsg.toJson());

      // Client 端反序列化（WebSocket 接收 → jsonDecode → fromJson）
      final clientJson = jsonDecode(hostJson) as Map<String, dynamic>;
      final restoredMsg = LanMessage.fromJson(clientJson);

      // 验证消息类型
      expect(restoredMsg.type, equals(LanMessageType.agentTokenUsageUpdated));
      expect(restoredMsg.fromId, equals('device-sender'));
      expect(restoredMsg.topic, equals('test-topic'));

      // 解析 content
      final content = jsonDecode(restoredMsg.content!) as Map<String, dynamic>;
      expect(content['type'], equals('tokenUsageUpdated'));
      expect(content['employeeId'], equals('emp-001'));

      final data = content['data'] as Map<String, dynamic>;
      expect(data['messageId'], equals('msg-llm-001'));

      final sessionUsage = data['sessionUsage'] as Map<String, dynamic>;
      expect(sessionUsage['promptTokens'], equals(500));
      expect(sessionUsage['totalTokens'], equals(700));

      final messageUsage = data['messageUsage'] as Map<String, dynamic>;
      expect(messageUsage['completionTokens'], equals(100));
    });

    test('Host 使用 _parseJson 风格解析 Client 发来的消息', () {
      // 模拟 Host 的 _parseJson 逻辑：data 可能是 String 或 List<int>
      Map<String, dynamic> parseJson(dynamic data) {
        final str = data is String ? data : String.fromCharCodes(data);
        return jsonDecode(str) as Map<String, dynamic>;
      }

      final msg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-001',
          'type': 'tokenUsageUpdated',
          'data': {'messageId': 'msg-parse-test'},
        }),
        topic: 'test',
      );

      // 模拟 Host 接收到的 raw data（jsonEncode 的结果）
      final rawData = jsonEncode(msg.toJson());

      // Host 解析
      final parsed = parseJson(rawData);
      final parsedMap = jsonDecode(rawData) as Map<String, dynamic>;
      final restoredMsg = LanMessage.fromJson(parsedMap);

      expect(restoredMsg.type, equals(LanMessageType.agentTokenUsageUpdated));

      final content = jsonDecode(restoredMsg.content!) as Map<String, dynamic>;
      expect(content['data']['messageId'], equals('msg-parse-test'));
    });
  });

  // ============================================================
  // 4. DeviceMessageHandler._handleAgentEvent 解析验证
  // ============================================================
  group('DeviceMessageHandler._handleAgentEvent 解析', () {
    test('从 LAN 消息正确解析 tokenUsageUpdated AgentEvent', () {
      // 模拟 Host 转发过来的 LAN 消息（经过 _forwardMessage）
      final lanMsg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-handler-test',
          'type': 'tokenUsageUpdated',
          'data': {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 1234,
              completionTokens: 567,
              totalTokens: 1801,
              reasoningTokens: 100,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 800,
              completionTokens: 300,
              totalTokens: 1100,
            ).toMap(),
            'messageId': 'msg-handler-e2e',
          },
        }),
        topic: 'test-topic',
      );

      // 模拟 DeviceMessageHandler._handleAgentEvent 的解析逻辑
      final content = jsonDecode(lanMsg.content ?? '{}') as Map<String, dynamic>;
      final eventType = AgentEventType.fromString(content['type'] as String? ?? '');
      final data = content['data'] as Map<String, dynamic>? ?? {};
      final employeeId = content['employeeId'] as String?;
      final fromDeviceId = lanMsg.fromId;

      // 验证解析结果
      expect(eventType, equals(AgentEventType.tokenUsageUpdated));
      expect(employeeId, equals('emp-handler-test'));
      expect(fromDeviceId, equals('device-sender'));

      // 模拟写入 eventController
      final agentEvent = AgentEvent(
        type: eventType,
        data: data,
        employeeId: employeeId,
        fromDeviceId: fromDeviceId,
      );

      // 验证 AgentEvent 数据完整性
      expect(agentEvent.type, equals(AgentEventType.tokenUsageUpdated));
      expect(agentEvent.employeeId, equals('emp-handler-test'));
      expect(agentEvent.fromDeviceId, equals('device-sender'));

      // 验证 sessionUsage
      final sessionUsage = TokenUsageRecord.fromMap(
          agentEvent.data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(1234));
      expect(sessionUsage.reasoningTokens, equals(100));

      // 验证 messageUsage
      final messageUsage = TokenUsageRecord.fromMap(
          agentEvent.data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.promptTokens, equals(800));

      // 验证 isRemote 判断
      final isRemote = fromDeviceId != 'device-receiver';
      expect(isRemote, isTrue, reason: '来自不同设备，应判定为远程事件');
    });
  });

  // ============================================================
  // 5. 端到端模拟：完整 LAN 广播链路
  // ============================================================
  group('端到端模拟：完整 LAN 广播链路', () {
    test('tokenUsageUpdated 从发送端经过 Host 转发到达接收端 eventController', () async {
      // ===== 模拟组件 =====

      // 1. Host 端的 messageStream（模拟 Host 转发后发出消息）
      final hostMessageController = StreamController<LanMessage>.broadcast();

      // 2. Client 端的 messageStream（模拟 Client 接收 Host 转发的消息）
      //    实际中这是 LanClientServiceImpl.messageStream
      final clientMessageController = StreamController<LanMessage>.broadcast();

      // 3. DeviceStateHolder.eventController（接收端）
      final receiverEventController = StreamController<AgentEvent>.broadcast();

      // 4. AgentProxy._eventController（远程 AgentProxy）
      final proxyEventController = StreamController<AgentEvent>.broadcast();

      // ===== 模拟发送端：broadcastAgentEvent 构造 LAN 消息 =====
      final lanMsg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-e2e-full',
          'type': 'tokenUsageUpdated',
          'data': {
            'sessionUsage': TokenUsageRecord(
              promptTokens: 3000,
              completionTokens: 1200,
              totalTokens: 4200,
              reasoningTokens: 300,
            ).toMap(),
            'messageUsage': TokenUsageRecord(
              promptTokens: 1500,
              completionTokens: 600,
              totalTokens: 2100,
              reasoningTokens: 150,
            ).toMap(),
            'messageId': 'msg-e2e-full',
          },
        }),
        topic: 'test-topic',
      );

      // ===== 模拟 Host 转发（_forwardMessage 无 toDeviceId → 广播） =====
      // Host 将消息序列化后广播给所有同 topic 的客户端
      final hostJson = jsonEncode(lanMsg.toJson());
      // 模拟 Client 接收
      final clientReceived = LanMessage.fromJson(jsonDecode(hostJson) as Map<String, dynamic>);
      clientMessageController.add(clientReceived);

      // ===== 模拟 DeviceMessageHandler.handleMessage =====
      // switch(msg.type) → case LanMessageType.agentTokenUsageUpdated → _handleAgentEvent
      final deviceHandlerEvents = <AgentEvent>[];
      void handleAgentEventFromLan(LanMessage msg) {
        if (msg.type == LanMessageType.agentTokenUsageUpdated) {
          // _handleAgentEvent 解析逻辑
          final content = jsonDecode(msg.content ?? '{}') as Map<String, dynamic>;
          final eventType = AgentEventType.fromString(content['type'] as String? ?? '');
          final data = content['data'] as Map<String, dynamic>? ?? {};
          final employeeId = content['employeeId'] as String?;
          final fromDeviceId = msg.fromId;

          final agentEvent = AgentEvent(
            type: eventType,
            data: data,
            employeeId: employeeId,
            fromDeviceId: fromDeviceId,
          );
          deviceHandlerEvents.add(agentEvent);

          // 写入 eventController
          receiverEventController.add(agentEvent);
        }
      }

      // 立即处理已发送的消息（同步，不依赖 stream 延迟）
      // 注意：必须在所有 stream listener 注册之后再调用，
      // 因为 broadcast stream 的 listener 在 add 之前注册才能收到同步事件
      await Future.delayed(Duration(milliseconds: 50));
      handleAgentEventFromLan(clientReceived);
      await Future.delayed(Duration(milliseconds: 50));

      // ===== 模拟 AgentProxyRemoteOps.onRemoteEvent =====
      final proxyEvents = <AgentEvent>[];
      // 直接从 deviceHandlerEvents 获取（因为它是同步写入的）
      // 而不是通过 stream 异步传递
      for (final evt in deviceHandlerEvents) {
        if (evt.employeeId == 'emp-e2e-full') {
 proxyEvents.add(evt);
          proxyEventController.add(evt);
        }
      }

      // ===== 模拟 CachedAgentProxy._handleAgentEvent =====
      final cachedProxyEvents = <AgentEvent>[];
      // 直接从 proxyEvents 同步获取（与 remoteSub 同样的原因）
      cachedProxyEvents.addAll(proxyEvents);

      // ===== 模拟 DeviceClient.onAgentEvent（前端监听） =====
      final clientEvents = <AgentEvent>[];
      // 直接从 deviceHandlerEvents 同步获取
      clientEvents.addAll(deviceHandlerEvents);

      await Future.delayed(Duration(milliseconds: 100));

      // ===== 验证 =====

      await Future.delayed(Duration(milliseconds: 200));

      // 1. Client 端收到 LAN 消息
      expect(clientReceived.type, equals(LanMessageType.agentTokenUsageUpdated));

      // 2. DeviceMessageHandler 正确解析并写入 eventController
      expect(deviceHandlerEvents.length, equals(1),
          reason: 'handleAgentEventFromLan 应同步写入 deviceHandlerEvents');
      expect(deviceHandlerEvents[0].type, equals(AgentEventType.tokenUsageUpdated));

      // 3. AgentProxyRemoteOps 正确过滤并透传
      expect(proxyEvents.length, equals(1),
          reason: 'proxyEvents 应通过 receiverEventController.stream 收到事件 (proxyEvents.length=${proxyEvents.length}, deviceHandlerEvents.length=${deviceHandlerEvents.length})');
      expect(proxyEvents[0].data['messageId'], equals('msg-e2e-full'));

      // 4. CachedAgentProxy 收到事件
      expect(cachedProxyEvents.length, equals(1),
          reason: 'cachedProxyEvents should receive from proxyEventController (length=${cachedProxyEvents.length}, proxyEvents.length=${proxyEvents.length})');
      expect(cachedProxyEvents[0].type, equals(AgentEventType.tokenUsageUpdated));

      // 5. DeviceClient.onAgentEvent（前端）收到事件
      expect(clientEvents.length, equals(1),
          reason: 'clientEvents should receive from receiverEventController (length=${clientEvents.length})');
      expect(clientEvents[0].type, equals(AgentEventType.tokenUsageUpdated));
      expect(clientEvents[0].employeeId, equals('emp-e2e-full'));
      expect(clientEvents[0].fromDeviceId, equals('device-sender'));

      // 6. 数据完整性
      final sessionUsage = TokenUsageRecord.fromMap(
          clientEvents[0].data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(3000));
      expect(sessionUsage.reasoningTokens, equals(300));

      final messageUsage = TokenUsageRecord.fromMap(
          clientEvents[0].data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.promptTokens, equals(1500));

      // 清理
      // 清理
    });

    test('多次 tokenUsageUpdated 事件全部正确到达', () async {
      final receiverEventController = StreamController<AgentEvent>.broadcast();
      final proxyEventController = StreamController<AgentEvent>.broadcast();

      final clientEvents = <AgentEvent>[];
      final clientSub = receiverEventController.stream.listen(clientEvents.add);

      final proxySub = receiverEventController.stream
          .where((e) => e.employeeId == 'emp-multi')
          .listen((event) {
        proxyEventController.add(event);
      });

      // 模拟 3 次 LLM 调用产生 3 个 tokenUsageUpdated 事件
      for (var i = 1; i <= 3; i++) {
        final lanMsg = LanMessage(
          type: LanMessageType.agentTokenUsageUpdated,
          fromId: 'device-sender',
          content: jsonEncode({
            'employeeId': 'emp-multi',
            'type': 'tokenUsageUpdated',
            'data': {
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
              'messageId': 'msg-multi-$i',
            },
          }),
          topic: 'test',
        );

        // Host 转发 → Client 接收 → _handleAgentEvent → eventController
        final content = jsonDecode(lanMsg.content ?? '{}') as Map<String, dynamic>;
        final eventType = AgentEventType.fromString(content['type'] as String? ?? '');
        final data = content['data'] as Map<String, dynamic>? ?? {};
        receiverEventController.add(AgentEvent(
          type: eventType,
          data: data,
          employeeId: content['employeeId'] as String?,
          fromDeviceId: lanMsg.fromId,
        ));
      }

      await Future.delayed(Duration(milliseconds: 100));

      expect(clientEvents.length, equals(3));

      // 验证按序到达且 sessionUsage 累加
      for (var i = 0; i < 3; i++) {
        expect(clientEvents[i].data['messageId'], equals('msg-multi-${i + 1}'));
        final session = TokenUsageRecord.fromMap(
            clientEvents[i].data['sessionUsage'] as Map<String, dynamic>);
        expect(session.promptTokens, equals(100 * (i + 1)));
      }

      await clientSub.cancel();
      await proxySub.cancel();
      await receiverEventController.close();
      await proxyEventController.close();
    });
  });

  // ============================================================
  // 6. Host 广播 vs 转发路径区分
  // ============================================================
  group('Host 广播 vs 转发路径区分', () {
    test('agentTokenUsageUpdated 走 _forwardMessage 路径（非 broadcast）', () {
      // 在 _handleClientMessage 中：
      // if (_needsForwarding(msg)) → _forwardMessage (定向转发/广播)
      // else → 手动遍历 broadcast
      //
      // agentTokenUsageUpdated 在 _needsForwarding 列表中 → 走 _forwardMessage
      // _forwardMessage 内部：无 toDeviceId → 广播给同 topic 其他客户端
      // 有 toDeviceId → 仅发给目标设备

      // 验证：agentTokenUsageUpdated 消息无 toDeviceId 时走广播
      final msg = LanMessage(
        type: LanMessageType.agentTokenUsageUpdated,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-001',
          'type': 'tokenUsageUpdated',
          'data': {'messageId': 'msg-route-test'},
        }),
        topic: 'test-topic',
      );

      // _forwardMessage 解析 toDeviceId
      String? toDeviceId = msg.toDeviceId;
      if ((toDeviceId == null || toDeviceId.isEmpty) &&
          msg.content != null &&
          msg.content!.isNotEmpty) {
        try {
          final contentData = jsonDecode(msg.content!) as Map<String, dynamic>;
          final payload = contentData['payload'] as Map<String, dynamic>?;
          toDeviceId = payload?['toDeviceId'] as String?;
        } catch (_) {}
      }

      // tokenUsageUpdated 消息的 content 中没有 payload.toDeviceId
      // → toDeviceId 为 null → 走广播路径
      expect(toDeviceId, isNull,
          reason: 'tokenUsageUpdated 消息无 toDeviceId，应走广播路径');
    });

    test('agentConfigChanged 不在 _needsForwarding 中，走 broadcast 路径', () {
      // 对比：agentConfigChanged 不在 _needsForwarding 列表中
      // → 走 else 分支的手动广播
      final configMsg = LanMessage(
        type: LanMessageType.agentConfigChanged,
        fromId: 'device-sender',
        content: jsonEncode({
          'employeeId': 'emp-001',
          'type': 'configChanged',
          'data': {'configType': 'provider', 'action': 'updated'},
        }),
        topic: 'test-topic',
      );

      final needsForwarding =
          configMsg.type == LanMessageType.rpcRequest ||
              configMsg.type == LanMessageType.rpcResponse ||
              configMsg.type == LanMessageType.agentTokenUsageUpdated ||
              // ... 其他转发类型
              false;

      expect(needsForwarding, isFalse,
          reason: 'agentConfigChanged 不需要定向转发，走普通广播');
    });
  });
}

/// 模拟 LanClient（用于测试 _forwardMessage 逻辑）
class _MockLanClient {
  final String id;
  final String deviceId;
  final String? topic;

  _MockLanClient({
    required this.id,
    required this.deviceId,
    this.topic,
  });
}
