/// 消息序列诊断报告数据类
///
/// 用于 Debug 模式下分析消息序列的完整性和正确性。

/// 单个诊断问题
class MessageSequenceIssue {
  /// 问题类型
  final String type;

  /// 消息位置（在消息列表中的索引）
  final int index;

  /// 问题描述
  final String description;

  /// 相关的 toolCallId（可选）
  final String? toolCallId;

  const MessageSequenceIssue({
    required this.type,
    required this.index,
    required this.description,
    this.toolCallId,
  });
}

/// toolCall -> toolResult 配对关系
class ToolCallChain {
  /// 工具调用 ID
  final String toolCallId;

  /// 工具名称
  final String toolName;

  /// assistant 消息在列表中的位置（含此 toolCall 的 assistant 消息）
  final int? assistantIndex;

  /// toolResult 消息在列表中的位置
  final int? resultIndex;

  /// 是否有匹配的 result
  final bool matched;

  const ToolCallChain({
    required this.toolCallId,
    required this.toolName,
    this.assistantIndex,
    this.resultIndex,
    required this.matched,
  });
}

/// 单条消息的摘要信息
class MessageSummary {
  /// 消息在列表中的索引
  final int index;

  /// 角色
  final String role;

  /// 消息类型
  final String type;

  /// 相关的 toolCallId（可选）
  final String? toolCallId;

  /// 内容预览（截断到 80 字符）
  final String? contentPreview;

  const MessageSummary({
    required this.index,
    required this.role,
    required this.type,
    this.toolCallId,
    this.contentPreview,
  });
}

/// 消息序列诊断报告
class MessageSequenceReport {
  /// 检测到的问题列表
  final List<MessageSequenceIssue> issues;

  /// 每条消息的摘要
  final List<MessageSummary> messageSummaries;

  /// toolCall -> toolResult 配对关系
  final List<ToolCallChain> toolCallChains;

  const MessageSequenceReport({
    required this.issues,
    required this.messageSummaries,
    required this.toolCallChains,
  });

  /// 是否存在问题
  bool get hasIssues => issues.isNotEmpty;

  /// 格式化输出，用于 UI 展示或导出
  String toFormattedString() {
    final buffer = StringBuffer();

    // 1. 总览
    buffer.writeln('=== 消息序列分析报告 ===');
    buffer.writeln('消息总数: ${messageSummaries.length}');
    buffer.writeln('问题数量: ${issues.length}');
    buffer.writeln();

    // 2. 问题列表
    if (issues.isNotEmpty) {
      buffer.writeln('--- 问题列表 ---');
      for (var i = 0; i < issues.length; i++) {
        final issue = issues[i];
        buffer.writeln('[${i + 1}] ${issue.type} @ index ${issue.index}');
        buffer.writeln('    ${issue.description}');
        if (issue.toolCallId != null) {
          buffer.writeln('    toolCallId: ${issue.toolCallId}');
        }
      }
      buffer.writeln();
    } else {
      buffer.writeln('消息序列正常，未发现问题。');
      buffer.writeln();
    }

    // 3. ToolCall 配对表
    if (toolCallChains.isNotEmpty) {
      buffer.writeln('--- ToolCall 配对表 ---');
      for (final chain in toolCallChains) {
        final status = chain.matched ? 'MATCHED' : 'UNMATCHED';
        buffer.writeln(
          '  ${chain.toolName} (${chain.toolCallId}) '
          '[$status] '
          'assistant@${chain.assistantIndex} -> result@${chain.resultIndex}',
        );
      }
      buffer.writeln();
    }

    // 4. 消息摘要列表
    buffer.writeln('--- 消息摘要 ---');
    for (final summary in messageSummaries) {
      final toolCallStr = summary.toolCallId != null
          ? ' toolCallId=${summary.toolCallId}'
          : '';
      final preview = summary.contentPreview ?? '';
      buffer.writeln(
        '  [${summary.index}] ${summary.role}/${summary.type}$toolCallStr'
        ' ${preview.length > 60 ? '${preview.substring(0, 60)}...' : preview}',
      );
    }

    return buffer.toString();
  }
}
