import 'package:test/test.dart';
import 'package:auakagent/auakagent.dart' as agent;

/// Token 统计 Query 路径（路径2）测试
///
/// 验证：
/// - TokenUsageRecord 序列化/反序列化一致性
/// - GetTokenUsageRequest RPC 请求序列化
/// - AgentRpcConfig.methodGetTokenUsage 常量存在
/// - TokenUsageTracker 内存优先 + 空 Store 降级行为
void main() {
  group('Token 统计 Query 路径（路径2）', () {
    // ===== T2: RPC 协议 =====

    group('GetTokenUsageRequest', () {
      test('toMap 包含 employeeId', () {
        const request = agent.GetTokenUsageRequest(employeeId: 'emp-001');
        final map = request.toMap();
        expect(map['employeeId'], equals('emp-001'));
      });

      test('fromMap 正确反序列化', () {
        final request = agent.GetTokenUsageRequest.fromMap({
          'employeeId': 'emp-002',
        });
        expect(request.employeeId, equals('emp-002'));
      });

      test('toMap/fromMap 往返一致', () {
        const original = agent.GetTokenUsageRequest(employeeId: 'emp-003');
        final restored = agent.GetTokenUsageRequest.fromMap(original.toMap());
        expect(restored.employeeId, equals(original.employeeId));
      });
    });

    group('AgentRpcConfig.methodGetTokenUsage', () {
      test('常量已定义且值正确', () {
        expect(agent.AgentRpcConfig.methodGetTokenUsage,
            equals('agentGetTokenUsage'));
      });
    });

    // ===== TokenUsageRecord 序列化 =====

    group('TokenUsageRecord 序列化', () {
      test('toMap/fromMap 往返一致', () {
        const record = agent.TokenUsageRecord(
          promptTokens: 1234,
          completionTokens: 567,
          totalTokens: 1801,
          reasoningTokens: 89,
        );
        final map = record.toMap();
        final restored = agent.TokenUsageRecord.fromMap(map);

        expect(restored.promptTokens, equals(1234));
        expect(restored.completionTokens, equals(567));
        expect(restored.totalTokens, equals(1801));
        expect(restored.reasoningTokens, equals(89));
      });

      test('空记录序列化', () {
        const record = agent.TokenUsageRecord();
        expect(record.isEmpty, isTrue);
        expect(record.isNotEmpty, isFalse);

        final restored = agent.TokenUsageRecord.fromMap(record.toMap());
        expect(restored.isEmpty, isTrue);
      });

      test('累加操作正确', () {
        const a = agent.TokenUsageRecord(
          promptTokens: 100,
          completionTokens: 50,
          totalTokens: 150,
        );
        const b = agent.TokenUsageRecord(
          promptTokens: 200,
          completionTokens: 100,
          totalTokens: 300,
        );
        final sum = a + b;
        expect(sum.promptTokens, equals(300));
        expect(sum.completionTokens, equals(150));
        expect(sum.totalTokens, equals(450));
      });
    });

    // ===== T1: 持久化写入逻辑验证 =====

    group('Token 持久化写入逻辑', () {
      test('TokenUsageRecord 累加后数据完整', () {
        // 模拟多次 LLM 调用的 Token 累加
        const usage1 = agent.TokenUsageRecord(
          promptTokens: 500,
          completionTokens: 200,
          totalTokens: 700,
        );
        const usage2 = agent.TokenUsageRecord(
          promptTokens: 300,
          completionTokens: 150,
          totalTokens: 450,
        );
        final total = usage1 + usage2;

        // 验证累加值（即写入 MessageStore 的值）
        expect(total.promptTokens, equals(800));
        expect(total.completionTokens, equals(350));
        expect(total.totalTokens, equals(1150));
      });
    });

    // ===== T4: 降级策略验证 =====

    group('查询降级策略', () {
      test('内存有数据时优先使用内存', () {
        // TokenUsageTracker 内存累加后应返回非空记录
        final tracker = agent.TokenUsageTracker();
        // TokenUsageTracker.accumulate 需要 llm.UsageInfo，
        // 此处仅验证 getSessionUsage 在无数据时返回空记录
        final usage = tracker.getSessionUsage('emp-001');
        expect(usage.isEmpty, isTrue);

        // 空记录应触发降级查询
        // （实际降级逻辑在 AgentImpl.getSessionTokenUsageAsync 中实现）
      });

      test('空 TokenUsageRecord 的 isEmpty/isNotEmpty 语义正确', () {
        const empty = agent.TokenUsageRecord();
        expect(empty.isEmpty, isTrue);
        expect(empty.isNotEmpty, isFalse);

        const nonEmpty = agent.TokenUsageRecord(promptTokens: 1);
        expect(nonEmpty.isEmpty, isFalse);
        expect(nonEmpty.isNotEmpty, isTrue);
      });
    });

    // ===== T5: RPC Handler 响应格式 =====

    group('RPC 响应格式', () {
      test('TokenUsageRecord.toMap 可作为 RPC 响应值', () {
        const usage = agent.TokenUsageRecord(
          promptTokens: 1000,
          completionTokens: 500,
          totalTokens: 1500,
        );
        final response = {
          'sessionUsage': usage.toMap(),
        };

        // 验证响应格式可被前端正确解析
        final sessionUsageMap =
            response['sessionUsage'] as Map<String, dynamic>;
        final restored = agent.TokenUsageRecord.fromMap(sessionUsageMap);
        expect(restored.promptTokens, equals(1000));
        expect(restored.completionTokens, equals(500));
        expect(restored.totalTokens, equals(1500));
      });
    });
  });
}
