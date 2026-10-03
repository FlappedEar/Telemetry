import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// Work for [runInBackground]: [argument] in, the result out; it stops at
/// [cancelled] with [OperationCancelled].
///
/// It runs in another isolate, so it must be a top-level or static
/// function: a closure made inside a widget's method also carries the
/// widget's state, which cannot be sent.
typedef BackgroundJob<A, T> = T Function(
  A argument,
  CancellationCheck cancelled,
);

/// A running [BackgroundJob]. [result] completes with [OperationCancelled]
/// after [cancel], and with [BackgroundTaskFailed] when the job fails.
abstract interface class BackgroundTask<T> {
  Future<T> get result;
  void cancel();
}

/// Why a [BackgroundJob] failed: what it threw, as text, since the error
/// itself stays in the isolate that ran it.
final class BackgroundTaskFailed implements Exception {
  const BackgroundTaskFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Starts [job] on [argument] in its own isolate, killed at once when
/// cancelled; under `flutter test` on the test's thread, stopped at its
/// next cancellation check. Either way the job's failures come back as
/// [BackgroundTaskFailed].
BackgroundTask<T> runInBackground<A, T>(BackgroundJob<A, T> job, A argument) =>
    !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')
    ? _InlineTask(job, argument)
    : runInIsolate(job, argument);

/// [runInBackground] in its own isolate, also under `flutter test`.
@visibleForTesting
BackgroundTask<T> runInIsolate<A, T>(BackgroundJob<A, T> job, A argument) =>
    _IsolateTask(job, argument);

/// [error] as a [BackgroundTaskFailed]; a cancellation stays one.
Object _failure(Object error) => switch (error) {
  OperationCancelled() || BackgroundTaskFailed() => error,
  _ => BackgroundTaskFailed('$error'),
};

final class _InlineTask<A, T> implements BackgroundTask<T> {
  _InlineTask(BackgroundJob<A, T> job, A argument) {
    result = Future(() {
      if (_cancelled) throw const OperationCancelled();
      try {
        return job(argument, () => _cancelled);
      } on Object catch (error, stack) {
        Error.throwWithStackTrace(_failure(error), stack);
      }
    });
  }

  bool _cancelled = false;

  @override
  late final Future<T> result;

  @override
  void cancel() => _cancelled = true;
}

/// What the isolate runs: [job] on [argument], the outcome sent to [port].
final class _Request<A, T> {
  const _Request(this.port, this.job, this.argument);

  final SendPort port;
  final BackgroundJob<A, T> job;
  final A argument;

  void run() {
    final Object? outcome;
    try {
      outcome = _Done<T>(job(argument, () => false));
    } on Object catch (error, stack) {
      port.send(_Failed('$error', '$stack'));
      return;
    }
    Isolate.exit(port, outcome);
  }
}

/// What the isolate sends back when the job returns.
final class _Done<T> {
  const _Done(this.value);
  final T value;
}

/// What the isolate sends back when the job throws.
final class _Failed {
  const _Failed(this.message, this.stack);
  final String message;
  final String stack;
}

final class _IsolateTask<A, T> implements BackgroundTask<T> {
  _IsolateTask(BackgroundJob<A, T> job, A argument) {
    _port.listen((message) {
      switch (message) {
        case _Done<T>(:final value):
          _finish(() => _done.complete(value));
        case _Failed(:final message, :final stack):
          _fail(BackgroundTaskFailed(message), StackTrace.fromString(stack));
        // An error the job left uncaught, as Isolate.spawn's onError
        // sends it.
        case [final Object? error, final Object? stack]:
          _fail(
            BackgroundTaskFailed('${error ?? 'The work stopped.'}'),
            stack is String ? StackTrace.fromString(stack) : null,
          );
        default:
          _fail(const BackgroundTaskFailed('The work stopped unexpectedly.'));
      }
    });
    final Future<Isolate> spawned;
    try {
      spawned = Isolate.spawn(
        _entry,
        _Request<A, T>(_port.sendPort, job, argument),
        onError: _port.sendPort,
        onExit: _port.sendPort,
        debugName: 'background',
      );
    } on Object catch (error, stack) {
      // A job that cannot be sent to another isolate.
      _fail(_failure(error), stack);
      return;
    }
    spawned.then(
      (isolate) {
        _isolate = isolate;
        if (_cancelled) isolate.kill(priority: Isolate.immediate);
      },
      onError: (Object error, StackTrace stack) =>
          _fail(_failure(error), stack),
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
    _fail(const OperationCancelled());
  }

  void _fail(Object error, [StackTrace? stack]) =>
      _finish(() => _done.completeError(error, stack));

  void _finish(void Function() complete) {
    if (_done.isCompleted) return;
    _port.close();
    complete();
  }

  static void _entry(_Request<Object?, Object?> request) => request.run();
}
