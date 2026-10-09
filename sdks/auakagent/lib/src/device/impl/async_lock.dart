import 'dart:async';

/// 简单的异步锁实现，防止并发执行
class AsyncLock {
  bool _locked = false;
  final _completerQueue = <Completer<void>>[];

  Future<T> synchronized<T>(Future<T> Function() fn) async {
    if (_locked) {
      final completer = Completer<void>();
      _completerQueue.add(completer);
      await completer.future;
    }

    _locked = true;
    try {
      return await fn();
    } finally {
      if (_completerQueue.isNotEmpty) {
        final next = _completerQueue.removeAt(0);
        _locked = false;
        next.complete();
      } else {
        _locked = false;
      }
    }
  }
}
