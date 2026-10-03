import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Work for [runInBackground]; it stops at [cancelled] with
/// [OperationCancelled].
typedef BackgroundJob<T> = T Function(CancellationCheck cancelled);

/// A running [BackgroundJob]. [result] completes with [OperationCancelled]
/// after [cancel].
abstract interface class BackgroundTask<T> {
  Future<T> get result;
  void cancel();
}

/// Starts [job] in its own isolate, killed at once when cancelled; under
/// `flutter test` on the test's thread, stopped at its next cancellation
/// check.
BackgroundTask<T> runInBackground<T>(BackgroundJob<T> job) =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? _InlineTask(job)
    : _IsolateTask(job);

final class _InlineTask<T> implements BackgroundTask<T> {
  _InlineTask(BackgroundJob<T> job) {
    result = Future(() {
      if (_cancelled) throw const OperationCancelled();
      return job(() => _cancelled);
    });
  }

  bool _cancelled = false;

  @override
  late final Future<T> result;

  @override
  void cancel() => _cancelled = true;
}

/// What the isolate sends back.
final class _Done<T> {
  const _Done(this.value);
  final T value;
}

final class _IsolateTask<T> implements BackgroundTask<T> {
  _IsolateTask(BackgroundJob<T> job) {
    _port.listen((message) {
      switch (message) {
        case _Done<T>(:final value):
          _finish(() => _done.complete(value));
        case [Object? error, Object? stack]:
          _finish(
            () => _done.completeError(
              error ?? 'The work stopped.',
              stack is String ? StackTrace.fromString(stack) : null,
            ),
          );
        default:
          _finish(
            () => _done.completeError(
              StateError('The work stopped unexpectedly.'),
            ),
          );
      }
    });
    Isolate.spawn(
      _entry<T>,
      (_port.sendPort, job),
      onError: _port.sendPort,
      onExit: _port.sendPort,
      debugName: 'background',
    ).then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object error, StackTrace stack) =>
          _finish(() => _done.completeError(error, stack)),
    );
  }

  final _port = ReceivePort();
  final _done = Completer<T>();
  Isolate? _isolate;
  bool _cancelled = false;

  @override
  Future<T> get result => _done.future;

  @override
  void cancel() {
    _cancelled = true;
    _isolate?.kill(priority: Isolate.immediate);
    _finish(() => _done.completeError(const OperationCancelled()));
  }

  void _finish(void Function() complete) {
    if (_done.isCompleted) return;
    _port.close();
    complete();
  }

  static void _entry<T>((SendPort, BackgroundJob<T>) message) {
    final (port, job) = message;
    Isolate.exit(port, _Done<T>(job(() => false)));
  }
}
