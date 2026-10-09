import '../../../utils/logger.dart';
import '../agent_tool.dart';

/// 定时任务工具
///
/// 让 Agent 可以自主创建、查询、取消定时任务。
/// 用户说"每天9点汇报工作"时，LLM 自动调用此工具设置定时。
///
/// 执行流程：
/// 1. LLM 分析用户意图 → 调用 schedule_task(action="create", ...)
/// 2. 权限审批（requiresPermission = true）
/// 3. 通过 onCreateTask 回调注册到 ScheduledTaskManager
/// 4. 到达触发时间 → TaskExecutor 执行 → 结果送达用户
class ScheduleTaskTool extends AgentTool {
  static final _log = Logger('ScheduleTaskTool');

  /// 创建任务回调（由 ScheduledTaskManager 注入）
  ///
  /// 参数: {name, message, schedule}
  /// 返回: {taskId, name, schedule, nextExecutionAt}
  Future<Map<String, dynamic>> Function(Map<String, dynamic> task)?
  onCreateTask;

  /// 取消任务回调
  Future<bool> Function(String taskId)? onCancelTask;

  /// 查询任务回调
  Future<List<Map<String, dynamic>>> Function({String? employeeId})?
  onListTasks;

  @override
  String get name => 'schedule_task';

  @override
  String get description =>
      '创建、查询或取消定时重复任务。'
      '重要：此工具仅注册/管理定时计划，不会立即执行任务内容。'
      '任务将在计划时间到达时自动执行。\n\n'
      '当用户要求按计划执行操作时使用，例如"每天早上 9 点提醒我"、"每周五汇报工作"、'
      '"每 4 小时检查日志"。\n\n'
      '任务类型（taskType 参数）：\n'
      '- "reminder"（默认）：简单通知。你写的消息将在触发时直接作为助手消息发送给用户，'
      '不会执行任何工具。适合：提醒、通知、闹钟。\n'
      '- "task"：自主执行任务。触发时，包含你指令的系统消息将通过队列注入主 Agent，'
      'Agent 将使用其工具执行任务。请编写详细、自包含的指令，包括使用哪些工具和产出什么。'
      '适合：日志检查、数据收集、文件操作、API 调用。\n\n'
      '"message" 参数是定时触发时使用的内容。不要尝试现在执行消息内容，直接将其传递给此工具即可。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['create', 'list', 'cancel', 'delete'],
        'description':
            '要执行的操作：创建新任务、列出现有任务、'
            '取消/删除任务（两者都会永久移除任务）。'
            '用户想移除/停止定时任务时使用 "delete"。',
      },
      'message': {
        'type': 'string',
        'description':
            '定时触发时要执行的任务指令。'
            '此内容不会立即执行，而是在未来的计划时间作为消息发送给你。'
            '请编写清晰、自包含的指令，让未来的你能理解并执行，'
            '包括使用哪些工具和期望什么产出。',
      },
      'schedule': {
        'type': 'string',
        'description':
            '定时表达式。\n'
            '- Cron："0 9 * * 1-5"（工作日 9 点），"*/30 * * * *"（每 30 分钟）\n'
            '- ISO 8601 时长："PT1H"（每小时），"P1D"（每天），"PT30M"（每 30 分钟）',
      },
      'name': {
        'type': 'string',
        'description': '任务简短名称，例如"每日工作汇报"。',
      },
      'taskId': {
        'type': 'string',
        'description': '任务 ID（action=cancel 或 action=delete 时必需）。',
      },
      'repeatType': {
        'type': 'string',
        'enum': ['once', 'recurring'],
        'description':
            '执行策略（仅 action=create）。'
            '重要：必须根据用户意图显式设置此字段。'
            '"once" = 仅执行一次然后自动禁用。'
            '"recurring" = 按计划无限重复。'
            '如果用户说"每隔 X"、"定期"、"每天"、"每周"或任何重复模式，使用 "recurring"。'
            '如果用户想要一次性提醒或操作，使用 "once"。',
      },
      'taskType': {
        'type': 'string',
        'enum': ['reminder', 'task'],
        'description':
            '任务类型（仅 action=create）。'
            '"reminder" = 提醒通知。你写的消息就是最终的提醒内容，触发时直接作为助手消息发送给用户。'
            '不调用 LLM API，不执行工具。'
            '"task" = 自主执行任务。触发时，你的指令（消息）将作为系统消息通过队列注入主 Agent，'
            'Agent 将使用可用工具执行任务。请为未来的自己编写详细指令。'
            '默认："reminder"。仅当定时操作需要使用工具时（如文件操作、API 调用、代码执行）才使用 "task"。',
      },
    },
    'required': ['action'],
  };

  @override
  bool get requiresPermission => false;

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'] as String?;
    _log.debug('execute called, arguments: $arguments');
    _log.debug(
      'action=$action, '
      'onCreateTask=${onCreateTask != null}, '
      'onCancelTask=${onCancelTask != null}, '
      'onListTasks=${onListTasks != null}',
    );

    if (action == null || action.isEmpty) {
      return ToolResult.error(
        'action is required. Use "create", "list", "cancel", or "delete".',
      );
    }

    switch (action) {
      case 'create':
        return await _create(arguments);
      case 'list':
        return await _list();
      case 'cancel':
      case 'delete':
        return await _cancel(arguments);
      default:
        return ToolResult.error(
          'Unknown action: $action. Use "create", "list", "cancel", or "delete".',
        );
    }
  }

  Future<ToolResult> _create(Map<String, dynamic> arguments) async {
    var message = arguments['message'] as String?;
    final schedule = arguments['schedule'] as String?;
    final name = arguments['name'] as String?;
    final taskType = arguments['taskType'] as String? ?? 'reminder';

    _log.debug(
      '_create: name=$name, '
      'message=${message != null
          ? message.length > 50
                ? "${message.substring(0, 50)}..."
                : message
          : null}, '
      'schedule=$schedule, taskType=$taskType',
    );

    if (message == null || message.isEmpty) {
      _log.error('_create failed: message is empty');
      // return ToolResult.error('message is required');
      message = name ?? 'Scheduled task';
    }
    if (schedule == null || schedule.isEmpty) {
      _log.error('_create failed: schedule is empty');
      return ToolResult.error('schedule is required');
    }
    if (onCreateTask == null) {
      _log.error(
        '_create failed: onCreateTask callback is NOT injected! '
        'ScheduledTaskManager may not be wired up.',
      );
      return ToolResult.error(
        'Scheduled task service is not available (onCreateTask is null)',
      );
    }

    try {
      final result = await onCreateTask!({
        'name': name ?? 'Scheduled task',
        'message': message,
        'schedule': schedule,
        'taskType': taskType,
      });
      _log.info('_create success: result=$result');
      return ToolResult.success(
        '✅ Scheduled task created successfully.\n'
        'Task ID: ${result['taskId']}\n'
        'Name: ${result['name']}\n'
        'Type: $taskType\n'
        'Schedule: ${result['schedule']}\n'
        'Next execution: ${result['nextExecutionAt']}\n\n'
        'The task is now registered. It will be executed automatically at the '
        'scheduled time — no further action needed now.',
        metadata: result,
      );
    } catch (e, st) {
      _log.error('_create exception: $e', e, st);
      return ToolResult.error('Failed to create task: $e');
    }
  }

  Future<ToolResult> _list() async {
    if (onListTasks == null) {
      return ToolResult.error('Scheduled task service is not available');
    }
    try {
      final tasks = await onListTasks!();
      if (tasks.isEmpty) {
        return ToolResult.success('No scheduled tasks found.');
      }
      final buffer = StringBuffer('📋 Scheduled tasks:\n');
      for (final t in tasks) {
        buffer.writeln(
          '  • [${t['taskId']}] ${t['name']} | '
          '${t['schedule']} | next: ${t['nextExecutionAt'] ?? 'N/A'} | '
          'enabled: ${t['enabled']}',
        );
      }
      return ToolResult.success(buffer.toString());
    } catch (e) {
      return ToolResult.error('Failed to list tasks: $e');
    }
  }

  Future<ToolResult> _cancel(Map<String, dynamic> arguments) async {
    final taskId = arguments['taskId'] as String?;
    if (taskId == null || taskId.isEmpty) {
      return ToolResult.error('taskId is required for cancel action');
    }
    if (onCancelTask == null) {
      return ToolResult.error('Scheduled task service is not available');
    }
    try {
      final success = await onCancelTask!(taskId);
      if (success) {
        return ToolResult.success('Task $taskId has been deleted.');
      } else {
        return ToolResult.error('Task $taskId not found.');
      }
    } catch (e) {
      return ToolResult.error('Failed to delete task: $e');
    }
  }
}
