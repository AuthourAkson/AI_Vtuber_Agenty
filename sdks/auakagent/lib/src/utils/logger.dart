/// Structured logging for WenzAgent.
///
/// Usage:
/// ```dart
/// final log = Logger('MyClass');
/// log.info('connected');
/// log.warn('retry attempt $attempt');
/// log.error('failed', e, stackTrace);
/// ```
library;

enum LogLevel {
  debug(0),
  info(1),
  warn(2),
  error(3),
  none(4);

  const LogLevel(this.value);
  final int value;
}

class Logger {
  Logger(this.tag);

  final String tag;

  /// Global minimum log level. Messages below this level are suppressed.
  /// Defaults to [LogLevel.info] in release, [LogLevel.debug] otherwise.
  static LogLevel level = _isRelease ? LogLevel.info : LogLevel.debug;

  static bool get _isRelease =>
      const bool.fromEnvironment('dart.vm.product');

  void debug(String message) => _log(LogLevel.debug, message);

  void info(String message) => _log(LogLevel.info, message);

  void warn(String message) => _log(LogLevel.warn, message);

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      _log(LogLevel.error, '$message: $error');
    } else {
      _log(LogLevel.error, message);
    }
    if (stackTrace != null) {
      // ignore: avoid_print
      print(stackTrace);
    }
  }

  void _log(LogLevel level, String message) {
    if (level.value < Logger.level.value) return;

    final now = DateTime.now();
    final ts = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';

    final levelStr = switch (level) {
      LogLevel.debug => 'DBG',
      LogLevel.info => 'INF',
      LogLevel.warn => 'WRN',
      LogLevel.error => 'ERR',
      LogLevel.none => 'OFF',
    };

    // ignore: avoid_print
    print('[$ts][$levelStr][$tag] $message');
  }
}
