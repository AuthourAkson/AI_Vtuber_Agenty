import 'dart:async';
import 'dart:convert';

import 'message_tracker.dart';

/// 打断决策
enum InterruptDecision { wait, interrupt }

/// 打断判断结果
class InterruptJudgeResult {
  final InterruptDecision decision;
  final String reason;
  final String? targetMessageId;

  InterruptJudgeResult({
    required this.decision,
    required this.reason,
    this.targetMessageId,
  });

  factory InterruptJudgeResult.wait(String reason) {
    return InterruptJudgeResult(
      decision: InterruptDecision.wait,
      reason: reason,
      targetMessageId: null,
    );
  }

  factory InterruptJudgeResult.interrupt(String reason, String targetMessageId) {
    return InterruptJudgeResult(
      decision: InterruptDecision.interrupt,
      reason: reason,
      targetMessageId: targetMessageId,
    );
  }

  @override
  String toString() {
    return 'InterruptJudgeResult(decision: $decision, reason: $reason, targetId: $targetMessageId)';
  }
}

/// 打断判断器
///
/// 通过 LLM 一次性调用来判断是否应打断当前正在处理的消息。
class InterruptJudge {
  final Future<String> Function(String prompt) _llmCall;

  InterruptJudge(this._llmCall);

  /// 判断是否应该打断当前处理的消息
  Future<InterruptJudgeResult> shouldInterrupt({
    required TrackedMessage currentProcessing,
    required List<TrackedMessage> queuedMessages,
  }) async {
    try {
      final prompt = _buildPrompt(currentProcessing, queuedMessages);
      final response = await _llmCall(prompt).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('LLM judgment timeout', const Duration(seconds: 15));
        },
      );
      return _parseResponse(response);
    } catch (e) {
      // 保守降级：任何异常都不打断
      return InterruptJudgeResult.wait('LLM judgment error: $e');
    }
  }

  /// 构建 prompt
  String _buildPrompt(TrackedMessage currentProcessing, List<TrackedMessage> queuedMessages) {
    final buffer = StringBuffer();

    buffer.writeln('You are a message queue manager. Decide whether any previously queued or processing message should be interrupted by newly queued messages.');
    buffer.writeln();
    buffer.writeln('Rules:');
    buffer.writeln('1. If a queued message CORRECTS or REPLACES a processing message (e.g., the user made a typo and resent) -> interrupt the processing message');
    buffer.writeln('2. If a queued message explicitly CANCELS a processing message (e.g., "stop", "cancel", "不要了", "算了", "取消") -> interrupt the processing message');
    buffer.writeln('3. If a queued message is a DIFFERENT TOPIC or task unrelated to the current one -> wait (let it queue)');
    buffer.writeln('4. If a queued message is a FOLLOW-UP or additional context for the current processing message -> wait');
    buffer.writeln('5. When in doubt, prefer "wait" (do not interrupt).');
    buffer.writeln();
    buffer.writeln('Messages (with IDs):');

    // 处理中的消息
    buffer.writeln('<processing> [ID: ${currentProcessing.messageId}] ${currentProcessing.content}</processing>');

    // 排队中的消息
    for (var i = 0; i < queuedMessages.length; i++) {
      final msg = queuedMessages[i];
      buffer.writeln('<queued> [ID: ${msg.messageId}] ${msg.content}</queued>');
    }

    buffer.writeln();
    buffer.writeln('Respond with ONLY a JSON object:');
    buffer.writeln('{"decision": "wait" or "interrupt", "reason": "brief explanation", "targetMessageId": "message_id_to_interrupt"}');
    buffer.writeln('- If decision is "wait": targetMessageId must be null');
    buffer.writeln('- If decision is "interrupt": targetMessageId must be the ID of the message to interrupt');

    return buffer.toString();
  }

  /// 解析 LLM 响应
  InterruptJudgeResult _parseResponse(String response) {
    try {
      // 提取 JSON（可能被 markdown 包裹）
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(response);
      if (jsonMatch == null) {
        return InterruptJudgeResult.wait('Failed to extract JSON from response');
      }

      final jsonStr = jsonMatch.group(0)!;
      final Map<String, dynamic> json = jsonDecode(jsonStr) as Map<String, dynamic>;

      final decisionStr = json['decision'] as String?;
      final reason = json['reason'] as String? ?? 'No reason provided';
      final targetMessageId = json['targetMessageId'];

      // 验证 decision
      if (decisionStr != 'interrupt' && decisionStr != 'wait') {
        return InterruptJudgeResult.wait('Invalid decision value: $decisionStr');
      }

      final decision = decisionStr == 'interrupt'
          ? InterruptDecision.interrupt
          : InterruptDecision.wait;

      // 验证 targetMessageId
      if (decision == InterruptDecision.interrupt) {
        if (targetMessageId == null || targetMessageId is! String || targetMessageId.isEmpty) {
          return InterruptJudgeResult.wait('decision=interrupt but targetMessageId is missing or invalid');
        }
        return InterruptJudgeResult.interrupt(reason, targetMessageId);
      } else {
        if (targetMessageId != null) {
          return InterruptJudgeResult.wait('decision=wait but targetMessageId is not null');
        }
        return InterruptJudgeResult.wait(reason);
      }
    } catch (e) {
      return InterruptJudgeResult.wait('Failed to parse response: $e');
    }
  }
}
