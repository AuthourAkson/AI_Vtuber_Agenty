import '../../../utils/logger.dart';
import '../agent_tool.dart';
import 'command_session_pool.dart';

/// 后台命令执行工具（带智能监控）
///
/// 启动后台命令后自动进入监控循环：
/// - 每 10 秒读取 stdout/stderr
/// - 通过内部 LLM 判断任务是否正常推进
/// - LLM 可决定中断异常任务
/// - 命令自然退出后直接返回结果
///
/// 支持的 action:
/// - start: 启动后台命令 + 自动监控，阻塞直到完成（核心用法）
/// - status: 查询指定会话的运行状态（手动查询）
/// - output: 查询指定会话的 stdout/stderr 输出（手动查询）
/// - terminate: 终止指定会话（手动终止）
/// - list: 列出所有会话（手动查看）
class BgCommandTool extends AgentTool {
  static final _log = Logger('BgCommandTool');

  /// 输出查询默认截取的尾部字符数
  static const int _defaultTailChars = 3000;

  /// 监控循环间隔（秒）
  static const int _monitorIntervalSeconds = 10;

  /// 监控时发送给 LLM 的 stdout 尾部字符数
  static const int _monitorStdoutTailChars = 1000;

  /// 监控 LLM 调用超时（秒）
  static const int _monitorLlmTimeoutSeconds = 30;

  /// 由 AgentImpl 注入的命令会话池
  CommandSessionPool? pool;

  /// 监控 LLM 回调（由 AgentImpl 通过 _chatAdapter.invokeOnce 注入）
  ///
  /// 接收监控 prompt，返回 LLM 的文本响应。
  Future<String?> Function(String prompt)? invokeMonitorLlm;

  @override
  String get name => 'bg_command';

  @override
  String get description =>
      '执行长时间运行的命令（编译、构建、测试、开发服务器、'
      '数据处理等），带自动 AI 监控。\n\n'
      '"start" 操作是阻塞的：启动命令后，每 10 秒通过内置 AI 监控器检查一次，'
      '命令完成或被中断时返回最终结果。\n\n'
      '监控器工作方式：\n'
      '- 每 10 秒读取最新的 stdout/stderr 输出\n'
      '- 将输出和任务描述发送给 AI 子 Agent\n'
      '- 子 Agent 判断是继续还是中断任务\n'
      '- 如果中断，终止进程并返回结果\n'
      '- 如果命令自行退出，立即返回结果\n\n'
      '重要：务必提供清晰的 "task" 参数描述命令的目的和预期结果，'
      '以帮助监控器判断进度。\n\n'
      '使用场景：\n'
      '- bg_command：编译、构建、测试、部署、开发服务器（预计 >30s）\n'
      '- command_execute：快速命令如 ls、cat、grep、git status（<30s）\n\n'
      '其他操作（status、output、terminate、list）用于手动管理'
      '子 Agent 启动的会话或边缘情况。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['start', 'status', 'output', 'terminate', 'list'],
            'description':
                '要执行的操作：\n'
                '- "start"：启动命令并自动监控（阻塞直到完成）\n'
                '- "status"：检查命令状态\n'
                '- "output"：查看 stdout/stderr 输出\n'
                '- "terminate"：终止运行中的命令\n'
                '- "list"：列出所有会话',
          },
          'command': {
            'type': 'string',
            'description':
                '要执行的 shell 命令（action="start" 时必需）。',
          },
          'task': {
            'type': 'string',
            'description':
                '任务描述（action="start" 时使用）。描述命令的目的和预期结果，'
                '内置 AI 监控器使用此信息判断任务是否正常推进。\n'
                '示例："以 release 模式构建 Flutter APK。预期：构建成功（退出码 0），'
                'APK 生成在 build/app/outputs/。"',
          },
          'sessionId': {
            'type': 'string',
            'description':
                '会话 ID（action="status"、"output"、"terminate" 时必需）。',
          },
          'workingDirectory': {
            'type': 'string',
            'description':
                '命令的工作目录（仅 action="start"）。'
                '默认：当前目录。',
          },
          'tailChars': {
            'type': 'integer',
            'description':
                '返回 stdout/stderr 的尾部字符数（仅 action="output"）。默认：3000。',
          },
        },
        'required': ['action'],
      };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'command_execute';

  @override
  String get permissionArgKey => 'command';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final action = arguments['action'] as String?;
    if (action == null || action.isEmpty) {
      return ToolResult.error(
        'action is required. Use "start", "status", "output", "terminate", or "list".',
      );
    }

    if (pool == null) {
      return ToolResult.error(
        'Background command service is not available (pool not injected).',
      );
    }

    switch (action) {
      case 'start':
        return await _start(arguments);
      case 'status':
        return _status(arguments);
      case 'output':
        return _output(arguments);
      case 'terminate':
        return _terminate(arguments);
      case 'list':
        return _list();
      default:
        return ToolResult.error(
          'Unknown action: "$action". Use "start", "status", "output", "terminate", or "list".',
        );
    }
  }

  // ============================================================
  // start: 启动命令 + 自动监控（阻塞）
  // ============================================================

  Future<ToolResult> _start(Map<String, dynamic> arguments) async {
    final command = arguments['command'] as String?;
    if (command == null || command.isEmpty) {
      return ToolResult.error('command is required for action="start".');
    }

    final taskDescription = arguments['task'] as String? ?? command;
    final workingDirectory = arguments['workingDirectory'] as String?;

    // 启动会话
    final session = await pool!.startSession(
      command: command,
      workingDirectory: workingDirectory,
    );

    if (session == null) {
      final running = pool!.activeCount;
      return ToolResult.error(
        'Cannot start: concurrent session limit reached '
        '($running/${pool!.maxSessions}). '
        'Terminate an existing session first.',
      );
    }

    // 启动立即失败
    if (session.status == CommandSessionStatus.error) {
      return ToolResult.error(
        'Failed to start command: $command\n'
        'The process could not be launched. Check the command syntax.',
      );
    }

    _log.info(
      'Session ${session.sessionId} started, entering monitor loop: $command',
    );

    // 进入监控循环（阻塞直到进程结束或被监控 LLM 中断）
    await _monitorLoop(session, taskDescription);

    // 构建最终结果
    return _buildFinalResult(session, taskDescription);
  }

  /// 监控循环：每 10 秒检查一次，通过 LLM 判断是否继续
  Future<void> _monitorLoop(
    CommandSession session,
    String taskDescription,
  ) async {
    // 如果没有注入监控 LLM，退化成纯等待
    if (invokeMonitorLlm == null) {
      _log.info('No monitor LLM, waiting for session ${session.sessionId}');
      await session.waitUntilDone();
      return;
    }

    while (true) {
      // 等待 10 秒或进程结束
      final completed = await session.waitUntilDone(
        timeout: Duration(seconds: _monitorIntervalSeconds),
      );

      if (completed) {
        // 进程自然退出
        _log.info(
          'Session ${session.sessionId} exited during monitoring: '
          'status=${session.status.name}, exitCode=${session.exitCode}',
        );
        return;
      }

      // 进程仍在运行，调用监控 LLM
      if (!session.isRunning) return;

      final stdout = session.getStdout(tailChars: _monitorStdoutTailChars);
      final stderr = session.getStderr(tailChars: _monitorStdoutTailChars);
      final elapsed = session.elapsed.inSeconds;

      final prompt = _buildMonitorPrompt(
        taskDescription: taskDescription,
        stdout: stdout,
        stderr: stderr,
        elapsedSeconds: elapsed,
        command: session.command,
      );

      try {
        final response = await invokeMonitorLlm!(prompt).timeout(
          Duration(seconds: _monitorLlmTimeoutSeconds),
        );

        if (response != null && _isInterruptDecision(response)) {
          final reason = _extractInterruptReason(response);
          _log.info(
            'Monitor LLM decided to INTERRUPT session ${session.sessionId}: $reason',
          );
          session.kill();
          return;
        }

        _log.debug(
          'Monitor LLM decided to CONTINUE session ${session.sessionId} '
          '(${elapsed}s elapsed)',
        );
      } catch (e) {
        // 监控 LLM 调用失败（超时/异常），不中断任务，继续等待
        _log.warn(
          'Monitor LLM call failed for session ${session.sessionId}: $e',
        );
      }
    }
  }

  /// 构建监控 prompt
  String _buildMonitorPrompt({
    required String taskDescription,
    required String stdout,
    required String stderr,
    required int elapsedSeconds,
    required String command,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('You are a task monitor. You are monitoring a long-running command.');
    buffer.writeln();
    buffer.writeln('## Task');
    buffer.writeln(taskDescription);
    buffer.writeln();
    buffer.writeln('## Command');
    buffer.writeln(command);
    buffer.writeln();
    buffer.writeln('## Elapsed Time');
    buffer.writeln('${elapsedSeconds}s');
    buffer.writeln();
    buffer.writeln('## Recent stdout (last $_monitorStdoutTailChars chars)');
    if (stdout.isNotEmpty) {
      buffer.writeln('```');
      buffer.writeln(stdout);
      buffer.writeln('```');
    } else {
      buffer.writeln('(no output yet)');
    }
    buffer.writeln();
    buffer.writeln('## stderr');
    if (stderr.isNotEmpty) {
      buffer.writeln('```');
      buffer.writeln(stderr);
      buffer.writeln('```');
    } else {
      buffer.writeln('(no errors)');
    }
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln('Based on the output above, decide whether to CONTINUE waiting or INTERRUPT the task.');
    buffer.writeln();
    buffer.writeln('Rules:');
    buffer.writeln('- If the output shows the task is progressing normally, respond: CONTINUE');
    buffer.writeln('- If the output shows unrecoverable errors (e.g., compilation failed, build aborted), respond: INTERRUPT: <brief reason>');
    buffer.writeln('- If the task appears stuck or hanging with no progress, respond: INTERRUPT: <brief reason>');
    buffer.writeln('- If the output looks normal (downloading, compiling, processing), respond: CONTINUE');
    buffer.writeln('- When in doubt, prefer CONTINUE');
    buffer.writeln();
    buffer.writeln('Respond with EXACTLY one of:');
    buffer.writeln('- CONTINUE');
    buffer.writeln('- INTERRUPT: <reason>');

    return buffer.toString();
  }

  /// 判断 LLM 响应是否为中断决策
  bool _isInterruptDecision(String response) {
    final trimmed = response.trim().toUpperCase();
    return trimmed.startsWith('INTERRUPT');
  }

  /// 从 LLM 响应中提取中断原因
  String _extractInterruptReason(String response) {
    final trimmed = response.trim();
    if (trimmed.toUpperCase().startsWith('INTERRUPT:')) {
      return trimmed.substring('INTERRUPT:'.length).trim();
    }
    if (trimmed.toUpperCase().startsWith('INTERRUPT')) {
      return trimmed.substring('INTERRUPT'.length).trim();
    }
    return trimmed;
  }

  /// 构建最终结果（进程结束后调用）
  ToolResult _buildFinalResult(
    CommandSession session,
    String taskDescription,
  ) {
    final summary = session.getSummary();
    final status = summary['status'] as String;
    final exitCode = summary['exitCode'];
    final elapsed = summary['elapsedSeconds'] as int;

    final stdout = session.getStdout(tailChars: _defaultTailChars);
    final stderr = session.getStderr(tailChars: _defaultTailChars);
    final stdoutTruncated = summary['stdoutTruncated'] as bool? ?? false;
    final stderrTruncated = summary['stderrTruncated'] as bool? ?? false;

    final buffer = StringBuffer();
    buffer.writeln('Command: ${session.command}');
    buffer.writeln('Status: $status');
    buffer.writeln('Exit code: ${exitCode ?? "N/A"}');
    buffer.writeln('Elapsed: ${elapsed}s');
    buffer.writeln('Session: ${session.sessionId}');
    buffer.writeln();

    if (stdout.isNotEmpty) {
      buffer.writeln('--- stdout ---');
      buffer.writeln(stdout);
      if (stdoutTruncated) {
        buffer.writeln(
          '\n[stdout truncated, showing last $_defaultTailChars chars of ${summary['stdoutTotalChars']} total]',
        );
      }
    }

    if (stderr.isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(stderr);
      if (stderrTruncated) {
        buffer.writeln(
          '\n[stderr truncated, showing last $_defaultTailChars chars of ${summary['stderrTotalChars']} total]',
        );
      }
    }

    if (stdout.isEmpty && stderr.isEmpty) {
      buffer.writeln('(no output)');
    }

    return ToolResult(
      content: buffer.toString().trim(),
      isError: exitCode != null && exitCode != 0,
      metadata: {
        'sessionId': session.sessionId,
        'exitCode': exitCode,
        'status': status,
        'elapsedSeconds': elapsed,
      },
    );
  }

  // ============================================================
  // 手动操作 actions
  // ============================================================

  ToolResult _status(Map<String, dynamic> arguments) {
    final sessionId = arguments['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      return ToolResult.error('sessionId is required for action="status".');
    }

    final session = pool!.getSession(sessionId);
    if (session == null) {
      return ToolResult.error('Session not found: $sessionId');
    }

    final summary = session.getSummary();
    final status = summary['status'] as String;
    final elapsed = summary['elapsedSeconds'] as int;
    final exitCode = summary['exitCode'];

    final buffer = StringBuffer();
    buffer.writeln('Session: $sessionId');
    buffer.writeln('Status: $status');
    buffer.writeln('Elapsed: ${elapsed}s');
    buffer.writeln('Command: ${summary['command']}');

    if (exitCode != null) {
      buffer.writeln('Exit code: $exitCode');
    }

    buffer.writeln();
    buffer.writeln('stdout: ${summary['stdoutTotalChars']} chars'
        '${summary['stdoutTruncated'] == true ? ' (truncated)' : ''}');
    buffer.writeln('stderr: ${summary['stderrTotalChars']} chars'
        '${summary['stderrTruncated'] == true ? ' (truncated)' : ''}');

    return ToolResult.success(buffer.toString().trim());
  }

  ToolResult _output(Map<String, dynamic> arguments) {
    final sessionId = arguments['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      return ToolResult.error('sessionId is required for action="output".');
    }

    final session = pool!.getSession(sessionId);
    if (session == null) {
      return ToolResult.error('Session not found: $sessionId');
    }

    final tailChars = arguments['tailChars'] as int? ?? _defaultTailChars;

    final stdout = session.getStdout(tailChars: tailChars);
    final stderr = session.getStderr(tailChars: tailChars);

    final buffer = StringBuffer();
    buffer.writeln('Session: $sessionId');
    buffer.writeln('Status: ${session.status.name}');
    buffer.writeln();

    if (stdout.isNotEmpty) {
      buffer.writeln('--- stdout ---');
      buffer.writeln(stdout);
      if (session.getSummary()['stdoutTruncated'] == true) {
        buffer.writeln(
          '\n[stdout truncated, showing last $tailChars chars of ${session.getSummary()['stdoutTotalChars']} total]',
        );
      }
    }

    if (stderr.isNotEmpty) {
      buffer.writeln('--- stderr ---');
      buffer.writeln(stderr);
      if (session.getSummary()['stderrTruncated'] == true) {
        buffer.writeln(
          '\n[stderr truncated, showing last $tailChars chars of ${session.getSummary()['stderrTotalChars']} total]',
        );
      }
    }

    if (stdout.isEmpty && stderr.isEmpty) {
      buffer.writeln('(no output yet)');
    }

    return ToolResult.success(buffer.toString().trim());
  }

  ToolResult _terminate(Map<String, dynamic> arguments) {
    final sessionId = arguments['sessionId'] as String?;
    if (sessionId == null || sessionId.isEmpty) {
      return ToolResult.error('sessionId is required for action="terminate".');
    }

    final session = pool!.getSession(sessionId);
    if (session == null) {
      return ToolResult.error('Session not found: $sessionId');
    }

    if (!session.isRunning) {
      return ToolResult.success(
        'Session $sessionId is not running (status: ${session.status.name}). '
        'No action needed.',
      );
    }

    final success = pool!.terminateSession(sessionId);
    if (success) {
      return ToolResult.success(
        'Session $sessionId terminated successfully.',
      );
    } else {
      return ToolResult.error('Failed to terminate session $sessionId.');
    }
  }

  ToolResult _list() {
    final sessions = pool!.listSessions();
    if (sessions.isEmpty) {
      return ToolResult.success('No background command sessions.');
    }

    final buffer = StringBuffer();
    buffer.writeln('Background command sessions (${sessions.length}):');
    buffer.writeln();

    for (final s in sessions) {
      final status = s['status'] as String;
      final elapsed = s['elapsedSeconds'] as int;
      final exitCode = s['exitCode'];

      buffer.writeln(
        '  [${s['sessionId']}] ${s['command']}\n'
        '    Status: $status | Elapsed: ${elapsed}s'
        '${exitCode != null ? ' | Exit: $exitCode' : ''}',
      );
    }

    return ToolResult.success(buffer.toString().trim());
  }
}
