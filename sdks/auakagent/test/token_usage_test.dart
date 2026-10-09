import 'package:llm_dart/llm_dart.dart' as llm;
import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart';

/// Token 用量统计单元测试
///
/// 覆盖：
/// - TokenUsageRecord 数据类（构造、累加、序列化、空值判断）
/// - TokenUsageTracker 统计器（会话级累加、消息级累加、查询、清空、dispose）
/// - 边界情况（null usage、空 usage、null messageId）
void main() {
  // ============================================================
  // 1. TokenUsageRecord 数据类测试
  // ============================================================
  group('TokenUsageRecord', () {
    test('默认构造函数所有字段为零', () {
      const record = TokenUsageRecord();
      expect(record.promptTokens, equals(0));
      expect(record.completionTokens, equals(0));
      expect(record.totalTokens, equals(0));
      expect(record.reasoningTokens, equals(0));
    });

    test('自定义构造函数正确赋值', () {
      const record = TokenUsageRecord(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        reasoningTokens: 20,
      );
      expect(record.promptTokens, equals(100));
      expect(record.completionTokens, equals(50));
      expect(record.totalTokens, equals(150));
      expect(record.reasoningTokens, equals(20));
    });

    test('fromUsageInfo 正常解析 UsageInfo', () {
      final usage = llm.UsageInfo(
        promptTokens: 200,
        completionTokens: 80,
        totalTokens: 280,
        reasoningTokens: 10,
      );
      final record = TokenUsageRecord.fromUsageInfo(usage);
      expect(record.promptTokens, equals(200));
      expect(record.completionTokens, equals(80));
      expect(record.totalTokens, equals(280));
      expect(record.reasoningTokens, equals(10));
    });

    test('fromUsageInfo null 返回零记录', () {
      final record = TokenUsageRecord.fromUsageInfo(null);
      expect(record.isEmpty, isTrue);
    });

    test('fromUsageInfo 部分字段为 null 时默认为零', () {
      final usage = llm.UsageInfo(
        promptTokens: 100,
        completionTokens: null,
        totalTokens: null,
        reasoningTokens: null,
      );
      final record = TokenUsageRecord.fromUsageInfo(usage);
      expect(record.promptTokens, equals(100));
      expect(record.completionTokens, equals(0));
      expect(record.totalTokens, equals(0));
      expect(record.reasoningTokens, equals(0));
    });

    test('operator + 正确累加两条记录', () {
      const a = TokenUsageRecord(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        reasoningTokens: 10,
      );
      const b = TokenUsageRecord(
        promptTokens: 200,
        completionTokens: 80,
        totalTokens: 280,
        reasoningTokens: 20,
      );
      final sum = a + b;
      expect(sum.promptTokens, equals(300));
      expect(sum.completionTokens, equals(130));
      expect(sum.totalTokens, equals(430));
      expect(sum.reasoningTokens, equals(30));
    });

    test('operator + 多次链式累加', () {
      const records = [
        TokenUsageRecord(promptTokens: 10, completionTokens: 5, totalTokens: 15),
        TokenUsageRecord(promptTokens: 20, completionTokens: 10, totalTokens: 30),
        TokenUsageRecord(promptTokens: 30, completionTokens: 15, totalTokens: 45),
      ];
      final total = records.reduce((a, b) => a + b);
      expect(total.promptTokens, equals(60));
      expect(total.completionTokens, equals(30));
      expect(total.totalTokens, equals(90));
    });

    test('isEmpty / isNotEmpty 正确判断', () {
      const empty = TokenUsageRecord();
      const nonEmpty = TokenUsageRecord(promptTokens: 1);
      expect(empty.isEmpty, isTrue);
      expect(empty.isNotEmpty, isFalse);
      expect(nonEmpty.isEmpty, isFalse);
      expect(nonEmpty.isNotEmpty, isTrue);
    });

    test('toMap 序列化完整', () {
      const record = TokenUsageRecord(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        reasoningTokens: 10,
      );
      final map = record.toMap();
      expect(map['promptTokens'], equals(100));
      expect(map['completionTokens'], equals(50));
      expect(map['totalTokens'], equals(150));
      expect(map['reasoningTokens'], equals(10));
    });

    test('fromMap 反序列化完整', () {
      final map = {
        'promptTokens': 200,
        'completionTokens': 80,
        'totalTokens': 280,
        'reasoningTokens': 20,
      };
      final record = TokenUsageRecord.fromMap(map);
      expect(record.promptTokens, equals(200));
      expect(record.completionTokens, equals(80));
      expect(record.totalTokens, equals(280));
      expect(record.reasoningTokens, equals(20));
    });

    test('fromMap 缺失字段默认为零', () {
      final record = TokenUsageRecord.fromMap({});
      expect(record.isEmpty, isTrue);
    });

    test('toMap → fromMap 往返一致', () {
      const original = TokenUsageRecord(
        promptTokens: 123,
        completionTokens: 456,
        totalTokens: 579,
        reasoningTokens: 77,
      );
      final roundTrip = TokenUsageRecord.fromMap(original.toMap());
      expect(roundTrip.promptTokens, equals(original.promptTokens));
      expect(roundTrip.completionTokens, equals(original.completionTokens));
      expect(roundTrip.totalTokens, equals(original.totalTokens));
      expect(roundTrip.reasoningTokens, equals(original.reasoningTokens));
    });

    test('toString 包含关键信息', () {
      const record = TokenUsageRecord(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
        reasoningTokens: 10,
      );
      final str = record.toString();
      expect(str, contains('100'));
      expect(str, contains('50'));
      expect(str, contains('150'));
      expect(str, contains('10'));
    });
  });

  // ============================================================
  // 2. TokenUsageTracker 统计器测试
  // ============================================================
  group('TokenUsageTracker', () {
    late TokenUsageTracker tracker;

    setUp(() {
      tracker = TokenUsageTracker();
    });

    // --- 基础累加 ---

    test('单次累加正确记录会话和消息级用量', () {
      final usage = llm.UsageInfo(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      );
      tracker.accumulate('emp-1', 'msg-1', usage);

      final session = tracker.getSessionUsage('emp-1');
      expect(session.promptTokens, equals(100));
      expect(session.completionTokens, equals(50));
      expect(session.totalTokens, equals(150));

      final message = tracker.getMessageUsage('msg-1');
      expect(message, isNotNull);
      expect(message!.promptTokens, equals(100));
    });

    test('多次累加同一会话叠加用量', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-1', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      final session = tracker.getSessionUsage('emp-1');
      expect(session.promptTokens, equals(300));
      expect(session.completionTokens, equals(130));
      expect(session.totalTokens, equals(430));
    });

    test('多次累加同一消息叠加用量（模拟多轮工具调用）', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 50, completionTokens: 30, totalTokens: 80));

      final message = tracker.getMessageUsage('msg-1');
      expect(message, isNotNull);
      expect(message!.promptTokens, equals(350));
      expect(message.completionTokens, equals(160));
      expect(message.totalTokens, equals(510));
    });

    // --- 多会话隔离 ---

    test('不同会话的统计互不干扰', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-2', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      expect(tracker.getSessionUsage('emp-1').promptTokens, equals(100));
      expect(tracker.getSessionUsage('emp-2').promptTokens, equals(200));
    });

    test('不同消息的统计互不干扰', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-1', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      expect(tracker.getMessageUsage('msg-1')!.promptTokens, equals(100));
      expect(tracker.getMessageUsage('msg-2')!.promptTokens, equals(200));
    });

    // --- 查询 ---

    test('查询不存在的会话返回零记录', () {
      final session = tracker.getSessionUsage('non-existent');
      expect(session.isEmpty, isTrue);
    });

    test('查询不存在的消息返回 null', () {
      final message = tracker.getMessageUsage('non-existent');
      expect(message, isNull);
    });

    // --- 边界情况 ---

    test('accumulate 传入 null usage 不做任何记录', () {
      tracker.accumulate('emp-1', 'msg-1', null);
      expect(tracker.getSessionUsage('emp-1').isEmpty, isTrue);
      expect(tracker.getMessageUsage('msg-1'), isNull);
    });

    test('accumulate 传入全零 UsageInfo 不做记录', () {
      // UsageInfo 所有字段为 null → fromUsageInfo 返回全零 → isEmpty 为 true
      final usage = llm.UsageInfo(
        promptTokens: null,
        completionTokens: null,
        totalTokens: null,
        reasoningTokens: null,
      );
      tracker.accumulate('emp-1', 'msg-1', usage);
      expect(tracker.getSessionUsage('emp-1').isEmpty, isTrue);
    });

    test('accumulate 传入 null messageId 只记录会话级', () {
      tracker.accumulate('emp-1', null,
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));

      // 会话级有数据
      expect(tracker.getSessionUsage('emp-1').promptTokens, equals(100));
      // 消息级为 null
      expect(tracker.getMessageUsage(null), isNull);
    });

    test('reasoningTokens 正确累加', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, totalTokens: 100, reasoningTokens: 30));
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 50, totalTokens: 50, reasoningTokens: 20));

      final session = tracker.getSessionUsage('emp-1');
      expect(session.reasoningTokens, equals(50));

      final message = tracker.getMessageUsage('msg-1');
      expect(message!.reasoningTokens, equals(50));
    });

    // --- 清空 ---

    test('clear 清空指定会话的统计', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-2', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      tracker.clear('emp-1');

      expect(tracker.getSessionUsage('emp-1').isEmpty, isTrue);
      // emp-2 不受影响
      expect(tracker.getSessionUsage('emp-2').promptTokens, equals(200));
    });

    test('clearAll 清空所有会话和消息统计', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));
      tracker.accumulate('emp-2', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      tracker.clearAll();

      expect(tracker.getSessionUsage('emp-1').isEmpty, isTrue);
      expect(tracker.getSessionUsage('emp-2').isEmpty, isTrue);
      expect(tracker.getMessageUsage('msg-1'), isNull);
      expect(tracker.getMessageUsage('msg-2'), isNull);
    });

    test('dispose 清空所有数据', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));

      tracker.dispose();

      expect(tracker.getSessionUsage('emp-1').isEmpty, isTrue);
      expect(tracker.getMessageUsage('msg-1'), isNull);
    });

    // --- 清空后可重新累加 ---

    test('clear 后可重新累加', () {
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));

      tracker.clear('emp-1');

      // 重新累加
      tracker.accumulate('emp-1', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      final session = tracker.getSessionUsage('emp-1');
      expect(session.promptTokens, equals(200));
      expect(session.completionTokens, equals(80));
    });
  });

  // ============================================================
  // 3. 集成场景测试
  // ============================================================
  group('Token 统计集成场景', () {
    test('模拟一次完整对话（多轮工具调用）', () {
      final tracker = TokenUsageTracker();
      const empId = 'emp-1';
      const msgId = 'msg-1';

      // 第 1 轮：用户消息 → LLM 返回工具调用
      tracker.accumulate(empId, msgId,
          llm.UsageInfo(promptTokens: 500, completionTokens: 100, totalTokens: 600));

      // 第 2 轮：工具结果 + LLM 继续调用工具
      tracker.accumulate(empId, msgId,
          llm.UsageInfo(promptTokens: 800, completionTokens: 120, totalTokens: 920));

      // 第 3 轮：工具结果 + LLM 最终回复
      tracker.accumulate(empId, msgId,
          llm.UsageInfo(promptTokens: 700, completionTokens: 300, totalTokens: 1000));

      // 验证消息级：3 轮总和
      final msgUsage = tracker.getMessageUsage(msgId)!;
      expect(msgUsage.promptTokens, equals(2000));
      expect(msgUsage.completionTokens, equals(520));
      expect(msgUsage.totalTokens, equals(2520));

      // 验证会话级：与消息级一致（只有一个消息）
      final sessionUsage = tracker.getSessionUsage(empId);
      expect(sessionUsage.promptTokens, equals(msgUsage.promptTokens));
      expect(sessionUsage.totalTokens, equals(msgUsage.totalTokens));
    });

    test('模拟多消息多会话场景', () {
      final tracker = TokenUsageTracker();

      // emp-1: msg-1 (简单对话)
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));

      // emp-1: msg-2 (带工具调用，2 轮)
      tracker.accumulate('emp-1', 'msg-2',
          llm.UsageInfo(promptTokens: 300, completionTokens: 80, totalTokens: 380));
      tracker.accumulate('emp-1', 'msg-2',
          llm.UsageInfo(promptTokens: 200, completionTokens: 120, totalTokens: 320));

      // emp-2: msg-3
      tracker.accumulate('emp-2', 'msg-3',
          llm.UsageInfo(promptTokens: 400, completionTokens: 200, totalTokens: 600));

      // 验证各消息级
      expect(tracker.getMessageUsage('msg-1')!.totalTokens, equals(150));
      expect(tracker.getMessageUsage('msg-2')!.totalTokens, equals(700));
      expect(tracker.getMessageUsage('msg-3')!.totalTokens, equals(600));

      // 验证会话级
      final emp1 = tracker.getSessionUsage('emp-1');
      expect(emp1.totalTokens, equals(850)); // 150 + 700

      final emp2 = tracker.getSessionUsage('emp-2');
      expect(emp2.totalTokens, equals(600));
    });

    test('模拟部分提供商不返回 usage', () {
      final tracker = TokenUsageTracker();

      // 第一次调用有 usage
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 100, completionTokens: 50, totalTokens: 150));

      // 第二次调用无 usage（模拟 Ollama 不返回）
      tracker.accumulate('emp-1', 'msg-1', null);

      // 第三次调用有 usage
      tracker.accumulate('emp-1', 'msg-1',
          llm.UsageInfo(promptTokens: 200, completionTokens: 80, totalTokens: 280));

      // 只有第 1、3 次被统计
      final session = tracker.getSessionUsage('emp-1');
      expect(session.promptTokens, equals(300));
      expect(session.completionTokens, equals(130));
    });
  });

  // ============================================================
  // 4. AgentEventType.tokenUsageUpdated 事件类型测试
  // ============================================================
  group('tokenUsageUpdated 事件类型', () {
    test('枚举值存在且可序列化', () {
      expect(AgentEventType.tokenUsageUpdated.value,
          equals('tokenUsageUpdated'));
    });

    test('fromString 可反序列化', () {
      expect(AgentEventType.fromString('tokenUsageUpdated'),
          equals(AgentEventType.tokenUsageUpdated));
    });

    test('事件 data 包含正确的 token 用量结构', () {
      final event = AgentEvent(
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
          'messageId': 'msg-1',
        },
        employeeId: 'emp-1',
      );

      // 序列化 / 反序列化往返
      final map = event.toMap();
      final restored = AgentEvent.fromMap(map);

      expect(restored.type, equals(AgentEventType.tokenUsageUpdated));
      expect(restored.data['messageId'], equals('msg-1'));

      final sessionUsage = TokenUsageRecord.fromMap(
          restored.data['sessionUsage'] as Map<String, dynamic>);
      expect(sessionUsage.promptTokens, equals(500));
      expect(sessionUsage.reasoningTokens, equals(50));

      final messageUsage = TokenUsageRecord.fromMap(
          restored.data['messageUsage'] as Map<String, dynamic>);
      expect(messageUsage.completionTokens, equals(100));
    });

    test('messageUsage 为 null 时事件仍可正常处理', () {
      final event = AgentEvent(
        type: AgentEventType.tokenUsageUpdated,
        data: {
          'sessionUsage': TokenUsageRecord(promptTokens: 100).toMap(),
          'messageUsage': null,
          'messageId': 'msg-1',
        },
        employeeId: 'emp-1',
      );

      final map = event.toMap();
      final restored = AgentEvent.fromMap(map);
      expect(restored.data['messageUsage'], isNull);
    });
  });
}
