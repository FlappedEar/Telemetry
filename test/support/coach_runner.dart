import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// A [CoachRunner] that runs [run] on the test's thread. The job [run]
/// calls stops at its next cancellation check once its task is cancelled.
CoachRunner testCoachRunner(
  Future<DayCoach> Function(DayCoach Function() job) run,
) =>
    (job) => _TestCoachTask(run, job);

final class _TestCoachTask implements BackgroundTask<DayCoach> {
  _TestCoachTask(
    Future<DayCoach> Function(DayCoach Function() job) run,
    CoachJob job,
  ) {
    result = run(() => job(() => cancelled));
  }

  bool cancelled = false;

  @override
  late final Future<DayCoach> result;

  @override
  void cancel() => cancelled = true;
}
