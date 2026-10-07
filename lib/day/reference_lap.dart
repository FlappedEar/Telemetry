import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import 'background_task.dart';

/// Where a reference lap comes from (FET-175): what a storage layer would
/// keep of it, never the recording itself.
sealed class ReferenceSource {
  const ReferenceSource();

  /// The file's or the day's name, as the reference's label says it.
  String get name;
}

/// A recording file: a friend's or an instructor's VBO or RCZ.
final class ReferenceFile extends ReferenceSource {
  const ReferenceFile(this.path);

  final String path;

  @override
  String get name => p.basename(path);

  @override
  bool operator ==(Object other) =>
      other is ReferenceFile && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// An earlier day of the driver profile, read from its saved document and
/// the recordings it names.
final class ReferenceProfileDay extends ReferenceSource {
  const ReferenceProfileDay({
    required this.path,
    required this.eventId,
    required this.dayName,
  });

  /// The day's `.fetproject` in the profile.
  final String path;
  final String eventId;
  final String dayName;

  @override
  String get name => dayName;

  @override
  bool operator ==(Object other) =>
      other is ReferenceProfileDay &&
      other.path == path &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(path, eventId);
}

/// The reference a day uses: its source and which of its laps.
final class ReferenceChoice {
  const ReferenceChoice({
    required this.source,
    required this.recordingIndex,
    required this.lapNumber,
  });

  final ReferenceSource source;
  final int recordingIndex;
  final int lapNumber;
}

/// Keeps a day's reference choice between visits. Where it is kept (the
/// driver profile, the day file, or nowhere) is the owner's decision still
/// to make (FET-175); a storage layer implements this and is given to
/// [ReferenceLapHolder].
abstract interface class ReferenceStore {
  /// The choice kept for day [eventId]; null when none.
  Future<ReferenceChoice?> restore(String eventId);

  /// Keeps [choice] for day [eventId]; null forgets it.
  Future<void> keep(String eventId, ReferenceChoice? choice);
}

/// Keeps nothing: the reference lives in memory while the day is open.
final class UnsavedReferenceStore implements ReferenceStore {
  const UnsavedReferenceStore();

  @override
  Future<ReferenceChoice?> restore(String eventId) async => null;

  @override
  Future<void> keep(String eventId, ReferenceChoice? choice) async {}
}

/// Why a profile day gave no recording to time: none of the recordings it
/// names was found or read.
const referenceDayHasNoRecordings = 'referenceDayHasNoRecordings';

/// What [loadReference] reads: a source, timed on today's line [gate].
typedef ReferenceRequest = ({ReferenceSource source, TimingGate gate});

/// A reference read and timed, or why it could not be read.
final class ReferenceLoaded {
  const ReferenceLoaded(ReferenceTiming this.timing) : error = '';
  const ReferenceLoaded.failed(this.error) : timing = null;

  final ReferenceTiming? timing;

  /// An error from `telemetry_core` or [referenceDayHasNoRecordings];
  /// empty with [timing].
  final String error;
}

/// Reads [request]'s recordings with the import's own reader
/// ([prepareTelemetryImport], or [openDay] for a profile day) and times them
/// on today's line ([timeReferenceLaps]). Runs in the background.
ReferenceLoaded loadReference(
  ReferenceRequest request,
  CancellationCheck cancelled,
) {
  final recordings = <ReferenceRecording>[];
  switch (request.source) {
    case ReferenceFile(:final path):
      final plan = prepareTelemetryImport([path], cancelled: cancelled);
      final run = plan.runs.firstOrNull;
      if (run == null) {
        return ReferenceLoaded.failed(plan.files.firstOrNull?.message ?? '');
      }
      recordings.add(
        ReferenceRecording(label: p.basename(path), session: run.telemetry),
      );
    case ReferenceProfileDay(:final path):
      final OpenedDay day;
      try {
        day = openDay(path, cancelled: cancelled);
      } on FetprojectError catch (error) {
        return ReferenceLoaded.failed(error.message);
      }
      for (final named in day.runs) {
        recordings.add(
          ReferenceRecording(label: named.name, session: named.run.telemetry),
        );
      }
      if (recordings.isEmpty) {
        return const ReferenceLoaded.failed(referenceDayHasNoRecordings);
      }
  }
  return ReferenceLoaded(
    timeReferenceLaps(recordings, request.gate, cancelled: cancelled),
  );
}

/// Starts a [loadReference]; replaced in tests.
typedef ReferenceLoader = BackgroundTask<ReferenceLoaded> Function(
  ReferenceRequest request,
);

BackgroundTask<ReferenceLoaded> _backgroundLoader(ReferenceRequest request) =>
    runInBackground(loadReference, request);

/// Where a reference lap stands.
enum ReferenceState {
  /// None chosen.
  none,

  /// Being read and timed on today's line.
  loading,

  /// Timed: [ReferenceLapHolder.lap] is the reference.
  ready,

  /// Read, but it cannot be timed on today's line
  /// ([ReferenceTiming.refusal]).
  refused,

  /// It could not be read ([ReferenceLapHolder.error]).
  failed,
}

/// The reference lap of the open day (FET-175), kept apart from the day:
/// [DayResultsController] never sees it, so it is not ranked, not in the
/// theoretical best, progression or coach, and not saved with the day. The
/// day page holds one and gives it to the pages that compare with it.
///
/// Reading and timing run in the background; a newer load or [clear]
/// makes an older result stale, and a stale result is dropped.
class ReferenceLapHolder extends ChangeNotifier {
  ReferenceLapHolder({
    this.dayId = '',
    this.store = const UnsavedReferenceStore(),
    ReferenceLoader? loader,
  }) : _loader = loader ?? _backgroundLoader;

  /// The day's event id, which [store] keeps the choice under.
  final String dayId;
  final ReferenceStore store;
  final ReferenceLoader _loader;

  ReferenceState _state = ReferenceState.none;
  ReferenceSource? _source;
  ReferenceTiming? _timing;
  ReferenceLapCandidate? _lap;
  String _error = '';
  int _generation = 0;
  BackgroundTask<ReferenceLoaded>? _task;
  bool _disposed = false;

  ReferenceState get state => _state;
  ReferenceSource? get source => _source;

  /// The source's recordings timed on today's line; null until read.
  ReferenceTiming? get timing => _timing;

  /// The reference lap; null unless [state] is ready.
  ReferenceLapCandidate? get lap => _lap;

  /// The reference lap's recording as parsed; null without a lap.
  TelemetrySession? get session {
    final lap = _lap, timing = _timing;
    if (lap == null || timing == null) return null;
    return timing.recordings[lap.recordingIndex].session;
  }

  /// Why the source could not be read, when [state] is failed.
  String get error => _error;

  /// Reads [source] and times it on today's line [gate]; its fastest lap
  /// becomes the reference ([choose] another). With [lapNumber] and
  /// [recordingIndex] (a kept choice), that lap when it is still there.
  Future<void> load(
    ReferenceSource source,
    TimingGate gate, {
    int? recordingIndex,
    int? lapNumber,
  }) async {
    _task?.cancel();
    final generation = ++_generation;
    _state = ReferenceState.loading;
    _source = source;
    _timing = null;
    _lap = null;
    _error = '';
    notifyListeners();
    final task = _task = _loader((source: source, gate: gate));
    ReferenceLoaded loaded;
    try {
      loaded = await task.result;
    } on OperationCancelled {
      return;
    } on BackgroundTaskFailed catch (failure) {
      loaded = ReferenceLoaded.failed(failure.message);
    }
    if (_disposed || generation != _generation) return;
    _task = null;
    final timing = loaded.timing;
    if (timing == null) {
      _state = ReferenceState.failed;
      _error = loaded.error;
    } else {
      _timing = timing;
      if (!timing.usable) {
        _state = ReferenceState.refused;
      } else {
        _state = ReferenceState.ready;
        _lap =
            timing.candidates
                .where(
                  (lap) =>
                      lap.recordingIndex == recordingIndex &&
                      lap.lapNumber == lapNumber,
                )
                .firstOrNull ??
            timing.fastest;
      }
    }
    notifyListeners();
    _keep();
  }

  /// Reads the choice [store] kept for the day, if any, timed on [gate].
  Future<void> restore(TimingGate gate) async {
    final generation = _generation;
    final choice = await store.restore(dayId);
    if (choice == null || _disposed || generation != _generation) return;
    await load(
      choice.source,
      gate,
      recordingIndex: choice.recordingIndex,
      lapNumber: choice.lapNumber,
    );
  }

  /// Makes [lap], one of the timing's candidates, the reference.
  void choose(ReferenceLapCandidate lap) {
    if (_state != ReferenceState.ready ||
        !(_timing?.candidates.contains(lap) ?? false)) {
      return;
    }
    _lap = lap;
    notifyListeners();
    _keep();
  }

  /// Drops the reference, and stops one still being read.
  void clear() {
    _task?.cancel();
    _task = null;
    ++_generation;
    _state = ReferenceState.none;
    _source = null;
    _timing = null;
    _lap = null;
    _error = '';
    notifyListeners();
    unawaited(store.keep(dayId, null));
  }

  void _keep() {
    final source = _source, lap = _lap;
    unawaited(
      store.keep(
        dayId,
        source == null || lap == null
            ? null
            : ReferenceChoice(
                source: source,
                recordingIndex: lap.recordingIndex,
                lapNumber: lap.lapNumber,
              ),
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _task?.cancel();
    super.dispose();
  }
}
