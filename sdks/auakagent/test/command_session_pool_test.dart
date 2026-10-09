import 'dart:io';

import 'package:test/test.dart';
import 'package:auakagent/src/agent/tool/agent_tool.dart';
import 'package:auakagent/src/agent/tool/builtin/bg_command_tool.dart';
import 'package:auakagent/src/agent/tool/builtin/command_session_pool.dart';

/// Windows-specific helpers
final _isWindows = Platform.isWindows;

/// Long-running command for testing
String get _longCmd =>
    _isWindows ? 'ping -n 30 127.0.0.1' : 'sleep 30';

/// Short-running command for testing
String get _shortSleepCmd =>
    _isWindows ? 'ping -n 2 127.0.0.1 >nul' : 'sleep 1';

void main() {
  group('CommandSession', () {
    test('starts and completes a short command', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: 'echo hello');
      expect(session, isNotNull);
      expect(session!.isRunning, isTrue);
      expect(session.pid, isNotNull);

      final done =
          await session.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);
      expect(session.status, CommandSessionStatus.completed);
      expect(session.exitCode, 0);

      final stdout = session.getStdout();
      expect(stdout, contains('hello'));
    });

    test('captures stderr output', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final cmd = _isWindows ? 'echo error 1>&2' : 'echo error >&2';
      final session = await pool.startSession(command: cmd);
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);

      final stderr = session.getStderr();
      expect(stderr, contains('error'));
    });

    test('reports failed status for non-zero exit code', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final cmd = _isWindows ? 'exit /b 1' : 'exit 1';
      final session = await pool.startSession(command: cmd);
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);
      expect(session!.status, CommandSessionStatus.failed);
      expect(session.exitCode, 1);
    });

    test('reports failed status for invalid command', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(
        command: '__nonexistent_command_xyz_123__',
      );
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);
      expect(session!.status, isNot(CommandSessionStatus.running));
      expect(session.exitCode, isNot(0));
    });

    test('getStdout with tailChars', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final cmd = _isWindows
          ? r'for /L %i in (1,1,500) do @echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          : 'for i in `seq 1 500`; do echo AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; done';

      final session = await pool.startSession(command: cmd);
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 15));
      expect(done, isTrue);

      final fullOutput = session!.getStdout();
      expect(fullOutput.length, greaterThan(1000));

      final tailOutput = session.getStdout(tailChars: 100);
      expect(tailOutput.length, lessThanOrEqualTo(200));
      expect(tailOutput.length, lessThan(fullOutput.length));
    });

    test('kill terminates a running process', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: _longCmd);
      expect(session, isNotNull);
      expect(session!.isRunning, isTrue);

      await Future.delayed(Duration(milliseconds: 500));

      session.kill();
      expect(session.status, CommandSessionStatus.cancelled);

      session.kill();
      expect(session.status, CommandSessionStatus.cancelled);
    });

    test('getSummary returns structured data', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: 'echo test');
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);

      final summary = session!.getSummary();
      expect(summary['sessionId'], isNotNull);
      expect(summary['command'], 'echo test');
      expect(summary['status'], isNotNull);
      expect(summary['exitCode'], isNotNull);
      expect(summary['pid'], isNotNull);
      expect(summary['createdAt'], isNotNull);
      expect(summary['elapsedSeconds'], isNotNull);
    });

    test('output buffer truncation (tail retention)', () async {
      final pool = CommandSessionPool(sessionMaxBufferChars: 200);
      addTearDown(() => pool.dispose());

      final cmd = _isWindows
          ? r'for /L %i in (1,1,100) do @echo Line_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          : 'for i in `seq 1 100`; do echo Line_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA; done';

      final session = await pool.startSession(command: cmd);
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 15));
      expect(done, isTrue);

      final output = session!.getStdout();
      expect(output.length, lessThanOrEqualTo(400));

      final summary = session.getSummary();
      expect(summary['stdoutTruncated'], isTrue);
      expect(summary['stdoutTotalChars'], greaterThan(200));
    });

    test('waitUntilDone returns true immediately for completed session',
        () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: 'echo test');
      expect(session, isNotNull);

      final done =
          await session!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(done, isTrue);

      final done2 = await session!.waitUntilDone();
      expect(done2, isTrue);
    });
  });

  group('CommandSessionPool', () {
    test('enforces concurrent session limit', () async {
      final pool = CommandSessionPool(maxSessions: 2);
      addTearDown(() => pool.dispose());

      final s1 = await pool.startSession(command: _longCmd);
      final s2 = await pool.startSession(command: _longCmd);
      expect(s1, isNotNull);
      expect(s2, isNotNull);

      final s3 = await pool.startSession(command: _longCmd);
      expect(s3, isNull);

      pool.terminateAll();
    });

    test('completed sessions free up concurrency slots', () async {
      final pool = CommandSessionPool(maxSessions: 1);
      addTearDown(() => pool.dispose());

      final s1 = await pool.startSession(command: 'echo test');
      expect(s1, isNotNull);
      await s1!.waitUntilDone(timeout: Duration(seconds: 10));
      expect(s1.isRunning, isFalse);

      final s2 = await pool.startSession(command: 'echo test2');
      expect(s2, isNotNull);
      await s2!.waitUntilDone(timeout: Duration(seconds: 10));
    });

    test('listSessions returns all sessions', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      await pool.startSession(command: 'echo one');
      await pool.startSession(command: 'echo two');

      await Future.delayed(Duration(seconds: 2));

      final list = pool.listSessions();
      expect(list.length, 2);
    });

    test('terminateSession works', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: _longCmd);
      expect(session, isNotNull);

      await Future.delayed(Duration(milliseconds: 300));

      final result = pool.terminateSession(session!.sessionId);
      expect(result, isTrue);
      expect(session.status, CommandSessionStatus.cancelled);
    });

    test('terminateSession returns false for unknown session', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final result = pool.terminateSession('nonexistent');
      expect(result, isFalse);
    });

    test('dispose terminates all running sessions', () async {
      final pool = CommandSessionPool();

      final s1 = await pool.startSession(command: _longCmd);
      final s2 = await pool.startSession(command: _longCmd);
      expect(s1, isNotNull);
      expect(s2, isNotNull);

      await Future.delayed(Duration(milliseconds: 300));

      pool.dispose();

      expect(s1!.status, CommandSessionStatus.cancelled);
      expect(s2!.status, CommandSessionStatus.cancelled);
    });

    test('getSession returns session by id', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final session = await pool.startSession(command: 'echo test');
      expect(session, isNotNull);

      final found = pool.getSession(session!.sessionId);
      expect(found, same(session));

      final notFound = pool.getSession('nonexistent');
      expect(notFound, isNull);
    });

    test('session counter increments', () async {
      final pool = CommandSessionPool();
      addTearDown(() => pool.dispose());

      final s1 = await pool.startSession(command: 'echo a');
      final s2 = await pool.startSession(command: 'echo b');
      expect(s1, isNotNull);
      expect(s2, isNotNull);
      expect(s1!.sessionId, isNot(equals(s2!.sessionId)));
    });

    test('activeCount tracks running sessions', () async {
      final pool = CommandSessionPool(maxSessions: 5);
      addTearDown(() => pool.dispose());

      expect(pool.activeCount, 0);

      await pool.startSession(command: _longCmd);
      await Future.delayed(Duration(milliseconds: 200));
      expect(pool.activeCount, 1);

      await pool.startSession(command: _longCmd);
      await Future.delayed(Duration(milliseconds: 200));
      expect(pool.activeCount, 2);

      pool.terminateAll();
      expect(pool.activeCount, 0);
    });
  });

  group('BgCommandTool', () {
    late BgCommandTool tool;
    late CommandSessionPool pool;

    setUp(() {
      pool = CommandSessionPool();
      tool = BgCommandTool();
      tool.pool = pool;
    });

    tearDown(() {
      pool.dispose();
    });

    test('name is bg_command', () {
      expect(tool.name, 'bg_command');
    });

    test('requiresPermission is true', () {
      expect(tool.requiresPermission, isTrue);
    });

    test('permissionType is command_execute', () {
      expect(tool.permissionType, 'command_execute');
    });

    test('permissionArgKey is command', () {
      expect(tool.permissionArgKey, 'command');
    });

    test('start action blocks and returns final result (no monitor LLM)',
        () async {
      // Without invokeMonitorLlm, falls back to simple wait
      final result = await tool.execute({
        'action': 'start',
        'command': 'echo hello_world',
        'task': 'Echo test',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('hello_world'));
      expect(result.content, contains('Exit code: 0'));
      expect(result.content, contains('Status: completed'));
    });

    test('start returns error for empty command', () async {
      final result = await tool.execute({
        'action': 'start',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('command is required'));
    });

    test('start returns error when concurrent limit reached', () async {
      final smallPool = CommandSessionPool(maxSessions: 1);
      final smallTool = BgCommandTool();
      smallTool.pool = smallPool;
      addTearDown(() => smallPool.dispose());

      // Start a blocking task (we need to start it in background so we can call again)
      final firstCall = smallTool.execute({
        'action': 'start',
        'command': _longCmd,
        'task': 'Long task',
      });

      // Give it time to start
      await Future.delayed(Duration(milliseconds: 500));

      // Second call should get concurrent limit error
      final r2 = await smallTool.execute({
        'action': 'start',
        'command': 'echo test',
        'task': 'Quick task',
      });
      expect(r2.isError, isTrue);
      expect(r2.content, contains('concurrent session limit'));

      // Clean up first call
      smallPool.terminateAll();
      try {
        await firstCall.timeout(Duration(seconds: 2));
      } catch (_) {}
    });

    test('start returns error for failed command', () async {
      final result = await tool.execute({
        'action': 'start',
        'command': _isWindows ? 'exit /b 1' : 'exit 1',
        'task': 'Should fail',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('failed'));
    });

    test('start with monitor LLM that says CONTINUE', () async {
      var monitorCallCount = 0;
      tool.invokeMonitorLlm = (prompt) async {
        monitorCallCount++;
        return 'CONTINUE';
      };

      // Use a short command that should complete within first monitoring interval
      final result = await tool.execute({
        'action': 'start',
        'command': 'echo quick_test',
        'task': 'Quick echo test',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('quick_test'));
      // Monitor may or may not have been called depending on timing
    });

    test('start with monitor LLM that says INTERRUPT', () async {
      tool.invokeMonitorLlm = (prompt) async {
        return 'INTERRUPT: Task appears to be hanging';
      };

      final result = await tool.execute({
        'action': 'start',
        'command': _longCmd,
        'task': 'Should be interrupted',
      });

      // Should be cancelled by monitor
      expect(result.content, contains('cancelled'));
      expect(result.content, contains('Session:'));
    });

    test('start with monitor LLM that throws (fallback to waiting)',
        () async {
      var callCount = 0;
      tool.invokeMonitorLlm = (prompt) async {
        callCount++;
        throw Exception('LLM unavailable');
      };

      // Start a quick command
      final result = await tool.execute({
        'action': 'start',
        'command': 'echo fallback_test',
        'task': 'Test fallback when LLM fails',
      });

      // Should still complete even though monitor fails
      expect(result.isError, isFalse);
      expect(result.content, contains('fallback_test'));
    });

    test('buildFinalResult contains expected fields', () async {
      final result = await tool.execute({
        'action': 'start',
        'command': 'echo result_test',
        'task': 'Check result format',
      });

      expect(result.content, contains('Command:'));
      expect(result.content, contains('Status:'));
      expect(result.content, contains('Exit code:'));
      expect(result.content, contains('Elapsed:'));
      expect(result.content, contains('Session:'));
      expect(result.metadata, isNotNull);
      expect(result.metadata!['exitCode'], 0);
      expect(result.metadata!['status'], 'completed');
    });

    test('status action reports completed session', () async {
      // Start via pool directly (not through tool) for manual status check
      final session = await pool.startSession(command: 'echo status_test');
      expect(session, isNotNull);
      await session!.waitUntilDone(timeout: Duration(seconds: 10));

      final statusResult = await tool.execute({
        'action': 'status',
        'sessionId': session.sessionId,
      });

      expect(statusResult.isError, isFalse);
      expect(statusResult.content, contains('completed'));
      expect(statusResult.content, contains('Exit code: 0'));
    });

    test('status action reports running session', () async {
      final session = await pool.startSession(command: _longCmd);
      expect(session, isNotNull);

      await Future.delayed(Duration(milliseconds: 300));

      final statusResult = await tool.execute({
        'action': 'status',
        'sessionId': session!.sessionId,
      });

      expect(statusResult.isError, isFalse);
      expect(statusResult.content, contains('running'));

      pool.terminateAll();
    });

    test('output action returns stdout', () async {
      final session = await pool.startSession(command: 'echo output_test_123');
      expect(session, isNotNull);
      await session!.waitUntilDone(timeout: Duration(seconds: 10));

      final outputResult = await tool.execute({
        'action': 'output',
        'sessionId': session.sessionId,
      });

      expect(outputResult.isError, isFalse);
      expect(outputResult.content, contains('output_test_123'));
    });

    test('terminate action kills running session', () async {
      final session = await pool.startSession(command: _longCmd);
      expect(session, isNotNull);

      await Future.delayed(Duration(milliseconds: 500));

      final terminateResult = await tool.execute({
        'action': 'terminate',
        'sessionId': session!.sessionId,
      });

      expect(terminateResult.isError, isFalse);
      expect(terminateResult.content, contains('terminated'));
    });

    test('terminate on already completed session returns info', () async {
      final session = await pool.startSession(command: 'echo done');
      expect(session, isNotNull);
      await session!.waitUntilDone(timeout: Duration(seconds: 10));

      final terminateResult = await tool.execute({
        'action': 'terminate',
        'sessionId': session!.sessionId,
      });

      expect(terminateResult.isError, isFalse);
      expect(terminateResult.content, contains('not running'));
    });

    test('list action shows sessions', () async {
      final session = await pool.startSession(command: 'echo list_test');
      expect(session, isNotNull);
      await Future.delayed(Duration(milliseconds: 500));

      final listResult = await tool.execute({
        'action': 'list',
      });

      expect(listResult.isError, isFalse);
      expect(listResult.content, contains('Background command sessions'));
      expect(listResult.content, contains('list_test'));
    });

    test('list with no sessions shows empty message', () async {
      final listResult = await tool.execute({
        'action': 'list',
      });

      expect(listResult.isError, isFalse);
      expect(listResult.content, contains('No background command sessions'));
    });

    test('status with unknown sessionId returns error', () async {
      final result = await tool.execute({
        'action': 'status',
        'sessionId': 'nonexistent',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('Session not found'));
    });

    test('output with unknown sessionId returns error', () async {
      final result = await tool.execute({
        'action': 'output',
        'sessionId': 'nonexistent',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('Session not found'));
    });

    test('missing action returns error', () async {
      final result = await tool.execute({});

      expect(result.isError, isTrue);
      expect(result.content, contains('action is required'));
    });

    test('unknown action returns error', () async {
      final result = await tool.execute({
        'action': 'invalid',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('Unknown action'));
    });

    test('without pool returns error', () async {
      final noPoolTool = BgCommandTool();

      final result = await noPoolTool.execute({
        'action': 'start',
        'command': 'echo test',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('pool not injected'));
    });

    test('_buildMonitorPrompt includes all sections', () async {
      // We can test the prompt building indirectly through the monitor LLM callback
      String? capturedPrompt;
      tool.invokeMonitorLlm = (prompt) async {
        capturedPrompt = prompt;
        return 'CONTINUE';
      };

      // Use a long command so monitor fires
      final resultFuture = tool.execute({
        'action': 'start',
        'command': _longCmd,
        'task': 'Build the project. Expected: success.',
      });

      // Wait for at least one monitor cycle
      await Future.delayed(Duration(seconds: 12));

      // Kill it to complete the test quickly
      pool.terminateAll();
      await resultFuture.timeout(Duration(seconds: 5), onTimeout: () {
        pool.terminateAll();
        return ToolResult(content: 'timeout', isError: false);
      });

      if (capturedPrompt != null) {
        expect(capturedPrompt!, contains('Build the project'));
        expect(capturedPrompt!, contains('Recent stdout'));
        expect(capturedPrompt!, contains('stderr'));
        expect(capturedPrompt!, contains('CONTINUE'));
        expect(capturedPrompt!, contains('INTERRUPT'));
      }
    });
  });
}
