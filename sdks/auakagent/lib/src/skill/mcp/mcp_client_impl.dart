import 'dart:async';
import 'dart:io';

import 'package:mcp_dart/mcp_dart.dart' as mcp_sdk;

import '../../persistence/entities/mcp_server_config.dart';
import '../../utils/logger.dart';
import 'mcp_client.dart';

/// 基于 mcp_dart SDK 的 MCP 客户端实现
///
/// 支持 3 种传输类型：
/// - **stdio**：通过子进程标准输入输出通信（本地 MCP 服务器）
/// - **sse**：通过 Server-Sent Events 通信（远程 MCP 服务器，旧版协议）
/// - **http**：通过 Streamable HTTP 通信（远程 MCP 服务器，新版协议）
///
/// 内置重试和自动重连机制：
/// - `connect()` 支持指数退避重试（由 [McpRetryConfig] 控制）
/// - 传输层断开时自动触发后台重连
/// - `callTool()` / `listTools()` 在连接断开时尝试自动重连后重试一次
class McpClientImpl implements McpClient {
  static final _log = Logger('McpClientImpl');

  final McpServerConfig _config;
  mcp_sdk.McpClient? _client;
  mcp_sdk.Transport? _transport;
  bool _connected = false;
  bool _disposed = false;

  /// 重连锁，防止并发重连
  final _reconnectLock = _AsyncLock();

  /// 是否正在重连中
  bool _reconnecting = false;

  /// 重连事件控制器
  final _reconnectController = StreamController<McpReconnectEvent>.broadcast();

  /// 重连状态变更事件流
  @override
  Stream<McpReconnectEvent> get onReconnect => _reconnectController.stream;

  /// 是否正在重连
  @override
  bool get isReconnecting => _reconnecting;

  /// 服务器配置
  McpServerConfig get config => _config;

  McpClientImpl(this._config);

  McpRetryConfig get _retryConfig =>
      _config.retryConfig ?? const McpRetryConfig();

  @override
  Future<void> connect() async {
    await _connectWithRetry();
  }

  /// 带重试的连接
  Future<void> _connectWithRetry() async {
    // 参数校验在重试循环之前完成，校验错误直接抛出不重试
    _validateTransportConfig(_config);

    final retry = _retryConfig;
    Exception? lastError;

    for (int attempt = 0; attempt <= retry.maxRetries; attempt++) {
      if (attempt > 0) {
        final delay = retry.exponentialBackoff
            ? retry.retryDelay * (1 << (attempt - 1))
            : retry.retryDelay;
        _log.info(
          '连接重试 $attempt/${retry.maxRetries}，'
          '等待 ${delay}ms...',
        );
        await Future.delayed(Duration(milliseconds: delay));
      }

      try {
        await _connectOnce();
        return;
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        _log.warn(
          '连接失败 (尝试 $attempt/${retry.maxRetries}): $e',
        );
      }
    }

    throw lastError ?? Exception('MCP 连接失败');
  }

  /// 单次连接（无重试）
  Future<void> _connectOnce() async {
    await _disconnectInternal();

    _transport = _createTransport(_config);

    _client = mcp_sdk.McpClient(
      const mcp_sdk.Implementation(name: 'wenzagent', version: '1.0.0'),
    );

    _transport!.onclose = () {
      if (_connected && !_disposed) {
        _connected = false;
        _log.warn('传输层断开，触发自动重连');
        _scheduleReconnect();
      }
    };
    _transport!.onerror = (error) {
      _log.warn('transport error: $error');
    };

    await _client!.connect(_transport!);
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _disposed = true;
    await _disconnectInternal();
  }

  /// 内部断开（不修改 _disposed 状态）
  Future<void> _disconnectInternal() async {
    if (_client != null) {
      try {
        await _client!.close();
      } catch (e) {
        _log.debug('关闭客户端连接失败: $e');
      }
    }
    _client = null;
    _transport = null;
    _connected = false;
  }

  @override
  Future<List<McpToolDefinition>> listTools() async {
    return _withCallRetry(
      action: 'listTools',
      call: () => _doListTools(),
    );
  }

  /// 执行一次 listTools 调用（无重试）
  Future<List<McpToolDefinition>> _doListTools() async {
    if (_client == null || !_connected) {
      throw StateError('MCP 客户端未连接');
    }
    final result = await _client!.listTools();
    return result.tools.map((tool) => McpToolDefinition(
          name: tool.name,
          description: tool.description ?? '',
          inputSchema: tool.inputSchema.toJson(),
        )).toList();
  }

  @override
  Future<McpToolCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    return _withCallRetry(
      action: 'callTool($name)',
      call: () => _doCallTool(name, arguments),
    );
  }

  /// 执行一次 callTool 调用（无重试）
  Future<McpToolCallResult> _doCallTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (_client == null || !_connected) {
      throw StateError('MCP 客户端未连接');
    }
    final result = await _client!.callTool(
      mcp_sdk.CallToolRequest(name: name, arguments: arguments),
    );

    final buffer = StringBuffer();
    bool isError = result.isError;
    for (final content in result.content) {
      if (content is mcp_sdk.TextContent) {
        buffer.writeln(content.text);
      } else if (content is mcp_sdk.ImageContent) {
        buffer.writeln('[Image: ${content.mimeType}]');
      } else if (content is mcp_sdk.EmbeddedResource) {
        buffer.writeln('[Resource: ${content.resource.uri}]');
      }
    }
    return McpToolCallResult(
      content: buffer.toString().trimRight(),
      isError: isError,
    );
  }

  @override
  Future<bool> ping() async {
    if (_client == null || !_connected) return false;
    try {
      await _client!.ping();
      return true;
    } catch (e) {
      _log.debug('ping failed, using fallback: $e');
      return false;
    }
  }

  /// 确保连接可用，如果断开则尝试重连（重试一次）
  ///
  /// 用于 callTool/listTools 调用前的自动恢复。
  Future<void> _ensureConnected() async {
    if (_connected) return;

    _log.info('调用时检测到连接断开，尝试恢复...');
    try {
      await _connectWithRetry();
      _log.info('连接恢复成功');
    } catch (e) {
      _log.warn('连接恢复失败: $e');
      rethrow;
    }
  }

  /// 带重试 + 重连的调用包装
  ///
  /// 流程：
  /// 1. 尝试调用，失败则重试最多 [McpRetryConfig.maxRetries] 次
  /// 2. 重试全部失败后，标记连接断开并触发重连
  /// 3. 重连成功后再尝试调用一次
  Future<T> _withCallRetry<T>({
    required String action,
    required Future<T> Function() call,
  }) async {
    final retry = _retryConfig;
    Object? lastError;

    for (int attempt = 0; attempt <= retry.maxRetries; attempt++) {
      if (!_connected) {
        await _ensureConnected();
      }
      try {
        return await call();
      } catch (e) {
        lastError = e;
        if (attempt < retry.maxRetries) {
          final delay = retry.exponentialBackoff
              ? retry.retryDelay * (1 << attempt)
              : retry.retryDelay;
          _log.warn(
            '$action 调用失败 '
            '(尝试 ${attempt + 1}/${retry.maxRetries + 1})，'
            '${retry.maxRetries - attempt} 次重试后重连，等待 ${delay}ms...',
          );
          await Future.delayed(Duration(milliseconds: delay));
        } else {
          _log.warn(
            '$action 调用失败，'
            '所有重试已耗尽，尝试重连...',
          );
        }
      }
    }

    // 所有调用重试均失败，尝试重连后再调用一次
    _connected = false;
    try {
      await reconnect();
      _log.info('重连成功，重新调用 $action');
      return await call();
    } catch (reconnectError) {
      _log.error('重连后调用 $action 仍失败', reconnectError);
      throw lastError ?? reconnectError;
    }
  }

  /// 调度后台自动重连
  ///
  /// 由 transport onclose 触发，在后台以指数退避策略尝试重连。
  /// 重连成功或所有重试耗尽后停止。
  void _scheduleReconnect() {
    if (_disposed || _reconnecting) return;

    _doReconnectLoop();
  }

  Future<void> _doReconnectLoop() async {
    await _reconnectLock.synchronized(() async {
      if (_disposed || _connected || _reconnecting) return;

      _reconnecting = true;
      _reconnectController.add(McpReconnectEvent('reconnecting'));

      final retry = _retryConfig;

      for (int attempt = 1; attempt <= retry.maxRetries; attempt++) {
        if (_disposed || _connected) break;

        final delay = retry.exponentialBackoff
            ? retry.retryDelay * (1 << (attempt - 1))
            : retry.retryDelay;
        _log.info(
          '自动重连 $attempt/${retry.maxRetries}，'
          '等待 ${delay}ms...',
        );
        await Future.delayed(Duration(milliseconds: delay));

        if (_disposed || _connected) break;

        try {
          await _connectOnce();
          _reconnecting = false;
          _reconnectController.add(McpReconnectEvent('reconnected'));
          _log.info('自动重连成功');
          return;
        } catch (e) {
          _log.warn(
            '自动重连失败 (尝试 $attempt/${retry.maxRetries}): $e',
          );
        }
      }

      _reconnecting = false;
      if (!_connected) {
        _reconnectController.add(McpReconnectEvent('reconnect_failed'));
        _log.error('自动重连失败，所有重试已耗尽');
      }
    });
  }

  /// 手动触发重连
  @override
  Future<void> reconnect() async {
    if (_disposed) {
      throw StateError('MCP 客户端已释放');
    }

    _log.info('手动触发重连...');
    await _reconnectLock.synchronized(() async {
      _reconnecting = true;
      _reconnectController.add(McpReconnectEvent('reconnecting'));

      try {
        await _connectWithRetry();
        _reconnecting = false;
        _reconnectController.add(McpReconnectEvent('reconnected'));
        _log.info('手动重连成功');
      } catch (e) {
        _reconnecting = false;
        _reconnectController.add(McpReconnectEvent('reconnect_failed'));
        _log.error('手动重连失败', e);
        rethrow;
      }
    });
  }

  /// 解析 command 为完整可执行路径。
  ///
  /// 在 Windows 上，`Process.start(runInShell: false)` 使用 `CreateProcess` API，
  /// 该 API 无法通过 PATH 找到 `.bat`/`.cmd` 包装的命令（如 Flutter 自带的 `dart.bat`）。
  /// 此方法通过 `which`/`where` 命令将 command 解析为实际可执行文件的完整路径。
  ///
  /// 对于已经是绝对路径或包含路径分隔符的 command，不做处理。
  /// 对于 Windows 上的 `.bat`/`.cmd` 文件，尝试查找对应的 `.exe` 或直接使用完整路径。
  static String _resolveCommand(String command) {
    // 已经是绝对路径，直接返回
    if (Platform.isWindows) {
      if (command.contains('\\') || command.contains('/')) {
        return command;
      }
    } else {
      if (command.contains('/')) {
        return command;
      }
    }

    // 非 Windows 平台直接返回，Process.start 可以正常找到
    if (!Platform.isWindows) {
      return command;
    }

    // Windows 平台：使用 where 命令查找完整路径
    try {
      final result = Process.runSync(
        'where',
        [command],
        runInShell: true,
      );

      if (result.exitCode == 0) {
        final output = (result.stdout as String).trim();
        final lines = output.split(RegExp(r'\r?\n'));

        // where 可能返回多行（如 dart.bat 和 dart 都存在）
        // 优先选择 .exe，其次选择 .bat/.cmd 的完整路径
        String? exePath;
        String? batPath;

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final lower = trimmed.toLowerCase();
          if (lower.endsWith('.exe')) {
            exePath = trimmed;
            break;
          } else if (lower.endsWith('.bat') || lower.endsWith('.cmd')) {
            batPath ??= trimmed;
          }
        }

        final resolved = exePath ?? batPath;
        if (resolved != null && resolved.isNotEmpty) {
          _log.debug('Windows command 解析: "$command" -> "$resolved"');
          return resolved;
        }
      }
    } catch (e) {
      _log.debug('Windows where 命令查找失败: $e');
    }

    // 解析失败，返回原始 command（让 Process.start 自行处理）
    _log.debug('Windows command 解析失败，使用原始 command: "$command"');
    return command;
  }

  /// 根据 [McpServerConfig.transportType] 创建对应的传输层
  ///
  /// 支持三种类型：
  /// - `stdio`：本地子进程通信
  /// - `sse`：Server-Sent Events（旧版远程协议）
  /// - `http`：Streamable HTTP（新版远程协议，支持 SSE 流式响应）
  static void _validateTransportConfig(McpServerConfig config) {
    switch (config.transportType) {
      case 'stdio':
        if (config.command == null || config.command!.isEmpty) {
          throw ArgumentError('stdio 传输类型需要配置 command');
        }
      case 'sse':
        if (config.url == null || config.url!.isEmpty) {
          throw ArgumentError('SSE 传输类型需要配置 url');
        }
      case 'http':
        if (config.url == null || config.url!.isEmpty) {
          throw ArgumentError('HTTP 传输类型需要配置 url');
        }
      default:
        throw ArgumentError(
          '不支持的传输类型: ${config.transportType}，'
          '支持的类型: stdio, sse, http',
        );
    }
  }

  static mcp_sdk.Transport _createTransport(McpServerConfig config) {
    switch (config.transportType) {
      case 'stdio':
        if (config.command == null || config.command!.isEmpty) {
          throw ArgumentError('stdio 传输类型需要配置 command');
        }
        return mcp_sdk.StdioClientTransport(
          mcp_sdk.StdioServerParameters(
            command: _resolveCommand(config.command!),
            args: config.args ?? [],
            environment: config.env != null
                ? Map<String, String>.from(config.env!)
                : null,
            stderrMode: ProcessStartMode.normal,
          ),
        );

      case 'sse':
        if (config.url == null || config.url!.isEmpty) {
          throw ArgumentError('SSE 传输类型需要配置 url');
        }
        return mcp_sdk.StreamableHttpClientTransport(
          Uri.parse(config.url!),
          opts: _buildHttpTransportOptions(config),
        );

      case 'http':
        if (config.url == null || config.url!.isEmpty) {
          throw ArgumentError('HTTP 传输类型需要配置 url');
        }
        return mcp_sdk.StreamableHttpClientTransport(
          Uri.parse(config.url!),
          opts: _buildHttpTransportOptions(config),
        );

      default:
        throw ArgumentError('不支持的传输类型: ${config.transportType}，'
            '支持的类型: stdio, sse, http');
    }
  }

  /// 构建 HTTP 传输层选项（headers 等）
  static mcp_sdk.StreamableHttpClientTransportOptions? _buildHttpTransportOptions(
    McpServerConfig config,
  ) {
    if (config.headers == null || config.headers!.isEmpty) return null;
    return mcp_sdk.StreamableHttpClientTransportOptions(
      requestInit: {
        'headers': config.headers!,
      },
    );
  }
}

/// 简单的异步锁，防止并发执行同一段代码
class _AsyncLock {
  Completer<void>? _completer;

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    while (_completer != null) {
      await _completer!.future;
    }
    if (_completer != null) {
      return synchronized(fn);
    }
    _completer = Completer<void>();
    try {
      return await fn();
    } finally {
      final c = _completer!;
      _completer = null;
      c.complete();
    }
  }
}
