import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/latest_job.dart';

/// A runner for a test that decides when and how the job's result comes:
/// [run] gets the job as a plain function, as the runners took it before
/// jobs became cancellable. Cancelling is noted in [AsyncTask.cancelled];
/// the job itself sees it through its cancellation check.
CancellableRunner<T> asyncRunner<T>(Future<T> Function(T Function() job) run) =>
    (job) {
      final task = AsyncTask<T>();
      task.start(run(() => job(() => task.cancelled)));
      return task;
    };

/// A [BackgroundTask] of a future a test controls.
final class AsyncTask<T> implements BackgroundTask<T> {
  bool cancelled = false;
  late final Future<T> _result;
  void start(Future<T> result) => _result = result;

  @override
  Future<T> get result => _result;

  @override
  void cancel() => cancelled = true;
}

/// A runner that uses a real isolate, also under `flutter test`.
BackgroundTask<T> isolateRunner<T>(CancellableJob<T> job) =>
    runInIsolate<CancellableJob<T>, T>(runCancellable<T>, job);
