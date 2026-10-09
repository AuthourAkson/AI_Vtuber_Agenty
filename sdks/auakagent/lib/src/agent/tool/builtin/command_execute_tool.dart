import 'dart:async';
import 'dart:io';

import '../agent_tool.dart';
import '../../../utils/logger.dart';

/// 命令执行工具
///
/// 执行 shell 命令并返回输出。
/// 支持中断正在执行的命令。
///
/// 优化点：
/// - 流式读取 stdout/stderr，避免管道缓冲区满导致进程阻塞
/// - 超时/取消后强制关闭管道，确保后台 Future 能正常结束
/// - 取消机制从 100ms 轮询改为直接触发 Completer
/// - 输出截断，防止大输出撑爆 LLM context
/// - Windows 上通过 taskkill 杀死整个进程树
class CommandExecuteTool extends AgentTool {
  static final _log = Logger('CommandExecuteTool');

  /// 默认超时时间（秒）
  static const int _defaultTimeout = 30;

  /// 单个流（stdout/stderr）最大收集字节数
  static const int _maxStreamBytes = 100 * 1024; // 100KB

  /// 当前正在执行的进程
  Process? _currentProcess;

  /// 取消 Completer（由 cancel() 直接触发，无需轮询）
  Completer<Map<String, dynamic>>? _cancellationCompleter;

  /// 当前执行中持有 stdout 的 StreamSubscription，用于超时后主动取消
  StreamSubscription<List<int>>? _stdoutSubscription;

  /// 当前执行中持有 stderr 的 StreamSubscription，用于超时后主动取消
  StreamSubscription<List<int>>? _stderrSubscription;

  @override
  String get name => 'command_execute';

  @override
  String get description =>
      '执行 shell 命令并返回输出（stdout 和 stderr）。请谨慎使用，命令在系统 shell 中运行。';

  @override
  Map<String, dynamic> get inputJsonSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': '要执行的 shell 命令',
          },
          'workingDirectory': {
            'type': 'string',
            'description':
                '命令的工作目录。默认：当前目录',
          },
          'timeout': {
            'type': 'integer',
            'description':
                '超时时间（秒）。超过此时间命令将被终止。默认：$_defaultTimeout',
          },
          'maxOutputBytes': {
            'type': 'integer',
            'description':
                '每个输出流（stdout/stderr）的最大收集字节数。超出时截断输出。默认：${_maxStreamBytes ~/ 1024}KB',
          },
        },
        'required': ['command'],
      };

  @override
  bool get requiresPermission => true;

  @override
  String get permissionType => 'command_execute';

  @override
  String get permissionArgKey => 'command';

  @override
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    final command = arguments['command'] as String?;
    if (command == null || command.isEmpty) {
      return ToolResult.error('参数错误: command 不能为空');
    }

    final workingDirectory = arguments['workingDirectory'] as String?;
    final timeout = arguments['timeout'] as int? ?? _defaultTimeout;
    final maxOutputBytes =
        arguments['maxOutputBytes'] as int? ?? _maxStreamBytes;

    _currentProcess = null;
    _cancellationCompleter = null;

    try {
      // 根据平台启动进程
      if (Platform.isWindows) {
        _currentProcess = await Process.start(
          'cmd',
          ['/c', command],
          workingDirectory: workingDirectory,
          runInShell: false,
        );
      } else {
        _currentProcess = await Process.start(
          'sh',
          ['-c', command],
          workingDirectory: workingDirectory,
          runInShell: false,
        );
      }

      // 创建取消 Completer（cancel() 会直接 complete 它）
      final cancellationCompleter =
          Completer<Map<String, dynamic>>();
      _cancellationCompleter = cancellationCompleter;

      // 创建输出 Completer
      final outputCompleter = Completer<Map<String, dynamic>>();

      // 流式监听进程输出（边读边收集，不等进程退出）
      _monitorProcessOutput(
        _currentProcess!,
        outputCompleter,
        maxOutputBytes: maxOutputBytes,
      );

      // 设置超时
      final timeoutFuture = Future.delayed(
        Duration(seconds: timeout),
        () => {'timeout': true},
      );

      // 等待：进程完成、超时或取消
      final result = await Future.any([
        outputCompleter.future,
        timeoutFuture,
        cancellationCompleter.future,
      ]);

      // 处理取消
      if (result['cancelled'] == true) {
        _forceKillAndCleanup();
        return ToolResult.error('命令执行被取消: $command');
      }

      // 处理超时
      if (result['timeout'] == true) {
        _forceKillAndCleanup();
        return ToolResult.error('命令执行超时 (${timeout}s): $command');
      }

      // 正常完成
      final exitCode = result['exitCode'] as int;
      final stdout = result['stdout'] as String;
      final stderr = result['stderr'] as String;
      final stdoutTruncated = result['stdoutTruncated'] as bool? ?? false;
      final stderrTruncated = result['stderrTruncated'] as bool? ?? false;

      final output = StringBuffer();
      output.writeln('Exit code: $exitCode');
      if (stdout.isNotEmpty) {
        output.writeln('--- stdout ---');
        output.writeln(stdout);
        if (stdoutTruncated) {
          output.writeln(
            '\n[stdout 已截断，共 ${stdout.length} 字符]',
          );
        }
      }
      if (stderr.isNotEmpty) {
        output.writeln('--- stderr ---');
        output.writeln(stderr);
        if (stderrTruncated) {
          output.writeln(
            '\n[stderr 已截断，共 ${stderr.length} 字符]',
          );
        }
      }

      return ToolResult(
        content: output.toString().trim(),
        isError: exitCode != 0,
        metadata: {'exitCode': exitCode, 'command': command},
      );
    } on ProcessException catch (e) {
      return ToolResult.error('执行命令失败: ${e.message}');
    } catch (e) {
      return ToolResult.error('执行命令失败: $e');
    } finally {
      _cleanupSubscriptions();
      _currentProcess = null;
      _cancellationCompleter = null;
    }
  }

  /// 流式监听进程输出
  ///
  /// 与旧实现的关键区别：
  /// - 不再先等 `process.exitCode` 再读 stdout/stderr
  /// - 而是 stdout、stderr、exitCode 三个 Future 并行等待
  /// - 这样即使进程产生大量输出，管道不会被阻塞
  Future<void> _monitorProcessOutput(
    Process process,
    Completer<Map<String, dynamic>> completer, {
    required int maxOutputBytes,
  }) async {
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    var stdoutTruncated = false;
    var stderrTruncated = false;

    // 流式读取 stdout（边读边收集，不阻塞进程写入）
    // 使用 StreamSubscription 而非 listen().asFuture()，
    // 以便在超时/取消时能主动 cancel() 中断流
    final stdoutCompleter = Completer<void>();
    _stdoutSubscription = process.stdout.listen(
      (chunk) {
        final text = systemEncoding.decode(chunk);
        if (!stdoutTruncated) {
          if (stdoutBuffer.length + text.length > maxOutputBytes) {
            final remaining = maxOutputBytes - stdoutBuffer.length;
            if (remaining > 0) {
              stdoutBuffer.write(text.substring(0, remaining));
            }
            stdoutTruncated = true;
          } else {
            stdoutBuffer.write(text);
          }
        }
      },
      onDone: () {
        if (!stdoutCompleter.isCompleted) stdoutCompleter.complete();
      },
      onError: (e) {
        if (!stdoutCompleter.isCompleted) stdoutCompleter.complete();
      },
      cancelOnError: false,
    );

    // 流式读取 stderr
    final stderrCompleter = Completer<void>();
    _stderrSubscription = process.stderr.listen(
      (chunk) {
        final text = systemEncoding.decode(chunk);
        if (!stderrTruncated) {
          if (stderrBuffer.length + text.length > maxOutputBytes) {
            final remaining = maxOutputBytes - stderrBuffer.length;
            if (remaining > 0) {
              stderrBuffer.write(text.substring(0, remaining));
            }
            stderrTruncated = true;
          } else {
            stderrBuffer.write(text);
          }
        }
      },
      onDone: () {
        if (!stderrCompleter.isCompleted) stderrCompleter.complete();
      },
      onError: (e) {
        if (!stderrCompleter.isCompleted) stderrCompleter.complete();
      },
      cancelOnError: false,
    );

    try {
      // 并行等待：exitCode + stdout读完 + stderr读完
      final results = await Future.wait([
        process.exitCode,
        stdoutCompleter.future,
        stderrCompleter.future,
      ]);

      if (!completer.isCompleted) {
        completer.complete({
          'exitCode': results[0] as int,
          'stdout': stdoutBuffer.toString().trim(),
          'stderr': stderrBuffer.toString().trim(),
          'stdoutTruncated': stdoutTruncated,
          'stderrTruncated': stderrTruncated,
        });
      }
    } catch (e) {
      if (!completer.isCompleted) {
        completer.completeError(e);
      }
    }
  }

  /// 强制杀死进程并清理管道
  ///
  /// 解决超时后后台 Future 永远不结束的问题：
  /// 1. 杀死进程（包括子进程树）
  /// 2. 关闭 stdin
  /// 3. 取消 stdout/stderr 的 StreamSubscription（触发 onDone → Completer 完成）
  void _forceKillAndCleanup() {
    _killProcess();
    _cleanupSubscriptions();
  }

  /// 清理 stdout/stderr 的 StreamSubscription 并关闭 stdin
  ///
  /// cancel() 会触发 onDone 回调，让 _monitorProcessOutput 中的
  /// Completer 正常完成，避免后台 Future 永远挂起。
  void _cleanupSubscriptions() {
    try {
      _stdoutSubscription?.cancel();
    } catch (_) {}
    _stdoutSubscription = null;

    try {
      _stderrSubscription?.cancel();
    } catch (_) {}
    _stderrSubscription = null;

    try {
      _currentProcess?.stdin.close();
    } catch (_) {}
  }

  /// 取消正在执行的命令
  @override
  void cancel() {
    // 直接触发 Completer，无需 100ms 轮询
    if (_cancellationCompleter != null &&
        !_cancellationCompleter!.isCompleted) {
      _cancellationCompleter!.complete({'cancelled': true});
    }
    _forceKillAndCleanup();
  }

  /// 杀死进程（包括子进程树）
  void _killProcess() {
    if (_currentProcess == null) return;

    try {
      if (Platform.isWindows) {
        // Windows: 使用 taskkill /T /F 杀死进程树
        // /T — 杀死由指定进程启动的所有子进程
        // /F — 强制终止
        _killProcessTreeWindows(_currentProcess!.pid);
      } else {
        // Unix: 发送 SIGKILL 到整个进程组
        // Process.start 默认不创建新 session，
        // 所以进程组 ID 等于进程自身 PID
        _killProcessGroupUnix(_currentProcess!.pid);
      }
    } catch (e) {
      _log.warn('failed to kill process: $e');
      // 降级：尝试普通 kill
      try {
        _currentProcess?.kill();
      } catch (_) {}
    }
  }

  /// Windows 上通过 taskkill 杀死进程树
  void _killProcessTreeWindows(int pid) {
    try {
      // taskkill /T /F /PID <pid>
      Process.runSync('taskkill', ['/T', '/F', '/PID', '$pid'],
          runInShell: true);
      _log.debug('killed process tree (Windows): pid=$pid');
    } catch (e) {
      _log.warn('taskkill failed for pid=$pid: $e');
    }
  }

  /// Unix 上通过 kill 发送 SIGKILL 到进程组
  ///
  /// Process.start 在非 Windows 平台上默认不调用 setSid，
  /// 所以子进程的进程组 ID (PGID) 等于父进程的 PID。
  /// 使用 `kill(-pid, SIGKILL)` 可以杀死整个进程组。
  void _killProcessGroupUnix(int pid) {
    try {
      // 负 PID 表示发送信号给进程组
      Process.killPid(-pid, ProcessSignal.sigkill);
      _log.debug('killed process group (Unix): pgid=$pid');
    } catch (e) {
      _log.warn('kill process group failed for pgid=$pid: $e');
      // 降级：只杀单个进程
      try {
        _currentProcess?.kill(ProcessSignal.sigkill);
      } catch (_) {}
    }
  }
}
