import 'dart:async';

import '../processor/cancellation_token.dart';
import 'agent_tool.dart';

/// 支持取消的工具执行器
///
/// 包装工具执行过程，使其能够响应取消令牌。
/// 当取消令牌被触发时，正在执行的工具会被中断。
class CancellableToolExecutor {
  final AgentTool _tool;
  final CancellationToken _cancellationToken;

  CancellableToolExecutor(this._tool, this._cancellationToken);

  /// 执行工具，支持取消
  Future<ToolResult> execute(Map<String, dynamic> arguments) async {
    // 创建可取消的Completer
    final completer = Completer<ToolResult>();

    // 监听取消事件
    StreamSubscription? subscription;
    subscription = _cancellationToken.onCancel.listen((_) {
      if (!completer.isCompleted) {
        completer.completeError(
          ToolCancelledException('Tool execution cancelled'),
        );
      }
    });

    // 异步执行工具
    () async {
      try {
        final result = await _tool.execute(arguments);
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (e) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      } finally {
        await subscription?.cancel();
      }
    }();

    return completer.future;
  }
}

/// 工具取消异常
class ToolCancelledException implements Exception {
  final String message;

  ToolCancelledException(this.message);

  @override
  String toString() => message;
}
