import 'dart:async';

import '../../agent_state.dart';
import '../agent_tool.dart';

/// 确认工具
///
/// Agent 主动调用此工具向前端发送确认消息（支持多个选项），
/// 等待用户选择后返回选择结果。
///
/// 与 permission 的区别：
/// - Permission：系统级安全机制，工具执行前由框架自动拦截
/// - Confirm：业务级交互工具，由 Agent 主动调用
class ConfirmTool extends AgentTool {
  /// 确认请求回调（由 AgentImpl 注入）
  ///
  /// 返回用户选择的选项 key
  Future<String> Function(AgentConfirmRequest request)? onConfirmRequest;

  @override
  String get name => 'confirm';

  @override
  String get description => '''向用户发送确认消息，等待用户选择后继续执行。

当需要用户在多个选项中做出选择时使用此工具。
支持自定义标题、描述和多个选项。

使用场景：
- 让用户选择执行方案
- 确认重要操作
- 在多个候选结果中让用户选择

参数说明：
- title: 确认标题（简短描述要确认的内容）
- message: 详细说明信息
- options: 选项列表，每个选项包含 key（标识符）和 label（显示文本）
- defaultOption: 默认选项的 key（可选）''';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'title': {
        'type': 'string',
        'description': '确认标题（简短描述要确认的内容）',
      },
      'message': {
        'type': 'string',
        'description': '详细说明信息',
      },
      'options': {
        'type': 'array',
        'items': {
          'type': 'object',
          'properties': {
            'key': {
              'type': 'string',
              'description': '选项标识符（如 "plan_a", "plan_b"）',
            },
            'label': {
              'type': 'string',
              'description': '选项显示文本（如 "方案A：使用Docker部署"）',
            },
            'description': {
              'type': 'string',
              'description': '选项详细描述（可选）',
            },
          },
          'required': ['key', 'label'],
        },
        'description': '选项列表（至少2个）',
      },
      'defaultOption': {
        'type': 'string',
        'description': '默认选项的 key（可选）',
      },
    },
    'required': ['title', 'message', 'options'],
  };

  @override
  bool get requiresPermission => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final title = arguments['title'] as String? ?? '';
    final message = arguments['message'] as String? ?? '';
    final optionsRaw = arguments['options'] as List? ?? [];
    final defaultOption = arguments['defaultOption'] as String?;

    // 验证参数
    if (title.isEmpty) {
      return ToolResult.error('title 不能为空');
    }

    if (optionsRaw.length < 2) {
      return ToolResult.error('options 至少需要2个选项');
    }

    // 解析选项
    final List<ConfirmOption> options;
    try {
      options = optionsRaw.map((o) {
        final map = o as Map<String, dynamic>;
        return ConfirmOption(
          key: map['key'] as String,
          label: map['label'] as String,
          description: map['description'] as String?,
        );
      }).toList();
    } catch (e) {
      return ToolResult.error('options 格式错误: $e');
    }

    // 验证选项 key 唯一
    final keys = options.map((o) => o.key).toSet();
    if (keys.length != options.length) {
      return ToolResult.error('options 中的 key 不能重复');
    }

    // 验证 defaultOption 存在
    if (defaultOption != null && !keys.contains(defaultOption)) {
      return ToolResult.error('defaultOption "$defaultOption" 不在 options 中');
    }

    // 检查回调是否已注入
    if (onConfirmRequest == null) {
      return ToolResult.error('confirm 工具未初始化（回调未注入）');
    }

    // 构建确认请求
    final request = AgentConfirmRequest(
      requestId: 'confirm_${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      message: message,
      options: options,
      defaultOption: defaultOption,
    );

    try {
      // 调用回调等待用户选择
      final selectedOption = await onConfirmRequest!(request);

      // 查找选中的选项
      final selected = options.where((o) => o.key == selectedOption).firstOrNull;

      if (selected != null) {
        return ToolResult.success(
          '用户选择了: ${selected.label} (key: ${selected.key})',
          metadata: {
            'selectedOption': selectedOption,
            'selectedLabel': selected.label,
            'requestId': request.requestId,
          },
        );
      } else {
        return ToolResult.success(
          '用户选择了未知选项: $selectedOption',
          metadata: {
            'selectedOption': selectedOption,
            'requestId': request.requestId,
          },
        );
      }
    } catch (e) {
      return ToolResult.error('等待用户确认时出错: $e');
    }
  }
}
