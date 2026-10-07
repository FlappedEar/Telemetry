import 'dart:async';
import 'dart:io';

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
///
/// A file the user picked is where it is on this computer; one restored
/// from the driver profile is its copy in the profile, and is named
/// [label] (the file's own name, which the copy's is not), with
/// [expectedBytes] its size when the profile copied it.
final class ReferenceFile extends ReferenceSource {
  const ReferenceFile(this.path, {this.label, this.expectedBytes});

  final String path;
  final String? label;
  final int? expectedBytes;

  @override
  String get name => label ?? p.basename(path);

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
///
/// A store keys the lap by [recordingId] (the run id of an earlier day's
/// session, or the file's name) and its [lapNumber] on today's line, never
/// by the recording's position in its source, which shifts when one of a
/// day's recordings is missing. It must not store absolute user paths
/// either: a [ReferenceFile]'s path is where the file was on this computer,
/// so a store keeps a copy instead (the driver profile's does, FET-276).
final class ReferenceChoice {
  const ReferenceChoice({
    required this.source,
    required this.recordingId,
    required this.lapNumber,
  });

  final ReferenceSource source;
  final String recordingId;
  final int lapNumber;
}

/// Keeps a day's reference choice between visits. The owner chose the
/// driver profile for it, not the day file (2026-10-07): see
/// `ProfileReferenceStore`. A storage layer implements this and is given
/// to [ReferenceLapHolder].
abstract interface class ReferenceStore {
  /// The choice kept for day [eventId]; null when none.
  Future<ReferenceChoice?> restore(String eventId);

  /// Keeps [choice] for day [eventId]; null forgets it. True when it is
  /// kept, false when this store keeps nothing for the day (the reference
  /// then lives in memory while the day is open). Throws when it could not
  /// be kept: the holder tells the user.
  Future<bool> keep(String eventId, ReferenceChoice? choice);
}

/// Keeps nothing: the reference lives in memory while the day is open.
final class UnsavedReferenceStore implements ReferenceStore {
  const UnsavedReferenceStore();

  @override
  Future<ReferenceChoice?> restore(String eventId) async => null;

  @override
  Future<bool> keep(String eventId, ReferenceChoice? choice) async => false;
}

/// Why a profile day gave no recording to time: none of the recordings it
/// names was found or read.
const referenceDayHasNoRecordings = 'referenceDayHasNoRecordings';

/// Why a reference restored from the driver profile gave nothing: the copy
/// of its recording is not in the profile, or is not the file that was
/// kept; the day it was taken from is not in the profile.
const referenceFileMissing = 'referenceFileMissing';
const referenceFileChanged = 'referenceFileChanged';
const referenceDayMissing = 'referenceDayMissing';

/// What [loadReference] reads: a source, timed on today's line and
/// checked against today's route ([ReferenceLine], with today's GPS
/// longitude convention).
typedef ReferenceRequest = ({ReferenceSource source, ReferenceLine line});

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
/// ([prepareTelemetryImport], or [openDay] for a profile day, with the laps
/// that day excluded) and times them on today's line ([timeReferenceLaps]).
/// Runs in the background; only the recordings with laps on today's line
/// come back, trimmed to those laps.
ReferenceLoaded loadReference(
  ReferenceRequest request,
  CancellationCheck cancelled,
) {
  final recordings = <ReferenceRecording>[];
  switch (request.source) {
    case ReferenceFile(:final path, :final expectedBytes):
      final file = File(path);
      if (!file.existsSync()) {
        return const ReferenceLoaded.failed(referenceFileMissing);
      }
      if (expectedBytes != null && file.lengthSync() != expectedBytes) {
        return const ReferenceLoaded.failed(referenceFileChanged);
      }
      final plan = prepareTelemetryImport([path], cancelled: cancelled);
      final run = plan.runs.firstOrNull;
      if (run == null) {
        return ReferenceLoaded.failed(plan.files.firstOrNull?.message ?? '');
      }
      recordings.add(
        ReferenceRecording(
          label: request.source.name,
          id: request.source.name,
          session: run.telemetry,
        ),
      );
    case ReferenceProfileDay(:final path):
      if (path.isEmpty || !File(path).existsSync()) {
        return const ReferenceLoaded.failed(referenceDayMissing);
      }
      final OpenedDay day;
      try {
        day = openDay(path, cancelled: cancelled);
      } on FetprojectError catch (error) {
        return ReferenceLoaded.failed(error.message);
      }
      for (final named in day.runs) {
        recordings.add(
          ReferenceRecording(
            label: named.name,
            id: named.run.id,
            session: named.run.telemetry,
            exclusions: [
              for (final MapEntry(key: lap, value: reason)
                  in day.exclusions.entries)
                if (lap.runId == named.run.id)
                  (start: lap.startTime, end: lap.endTime, reason: reason),
            ],
          ),
        );
      }
      if (recordings.isEmpty) {
        return const ReferenceLoaded.failed(referenceDayHasNoRecordings);
      }
  }
  return ReferenceLoaded(
    timeReferenceLaps(recordings, request.line, cancelled: cancelled),
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

/// Whether the reference is kept for the day's next visit.
enum ReferenceKeep {
  /// Nothing to keep yet.
  none,

  /// Being written to the store.
  saving,

  /// Kept: the day's next visit restores it.
  saved,

  /// The store keeps nothing for this day (it is not in the driver profile,
  /// or there is no profile): the reference lives while the day is open.
  unsaved,

  /// The store could not keep it ([ReferenceLapHolder.keepProblem]); the
  /// reference stays while the day is open.
  failed,
}

/// The reference lap of the open day (FET-175), kept apart from the day:
/// [DayResultsController] never sees it, so it is not ranked, not in the
/// theoretical best, progression or coach, and not saved in the day file.
/// The choice itself is kept by [store], in the driver profile (FET-276).
/// The day page holds one and gives it to the pages that compare with it.
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
  bool _restoreTried = false;
  ReferenceKeep _keepState = ReferenceKeep.none;
  ProfileReferenceProblem? _keepProblem;
  ReferenceChoice? _lastKept;
  ReferenceChoice? _failedChoice;
  bool _failedForget = false;
  int _keepGeneration = 0;

  ReferenceState get state => _state;

  /// Whether [restore] was called: it reads what the store kept once.
  bool get restoreTried => _restoreTried;

  /// Whether the reference is kept for the next visit.
  ReferenceKeep get keepState => _keepState;

  /// Why the store could not keep it, when [keepState] is failed; null for
  /// a failure that is none of [ProfileReferenceProblem]'s.
  ProfileReferenceProblem? get keepProblem => _keepProblem;

  /// Whether what failed was forgetting the reference, not keeping one.
  bool get keepFailedToForget => _failedForget;
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

  /// Reads [source] and times it on today's line [line]; its fastest lap
  /// becomes the reference ([choose] another). With [recordingId] and
  /// [lapNumber] (a kept choice, or the lap chosen before [reload]), that
  /// lap when it is still there.
  Future<void> load(
    ReferenceSource source,
    ReferenceLine line, {
    String? recordingId,
    int? lapNumber,
    ReferenceChoice? restored,
  }) async {
    _task?.cancel();
    final generation = ++_generation;
    ++_keepGeneration;
    _keepState = ReferenceKeep.none;
    _keepProblem = null;
    _failedChoice = null;
    _state = ReferenceState.loading;
    _source = source;
    _timing = null;
    _lap = null;
    _error = '';
    notifyListeners();
    final task = _task = _loader((source: source, line: line));
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
                      lap.recordingId == recordingId &&
                      lap.lapNumber == lapNumber,
                )
                .firstOrNull ??
            timing.fastest;
      }
    }
    if (restored != null) {
      // What the store holds already: written back only when changed.
      _lastKept = restored;
      _keepState = ReferenceKeep.saved;
    }
    notifyListeners();
    if (restored == null) _keep();
  }

  /// Whether the reference was timed on another line than [line] (today's
  /// line changed: another group, or a new best lap on another line), so
  /// its laps and lap times no longer apply until it is loaded again.
  bool timedOnAnotherLine(ReferenceLine? line) {
    final timing = _timing;
    return timing != null && !timing.line.sameLine(line);
  }

  /// Reads the same source again on today's line [line], keeping the chosen
  /// lap when it is still there.
  Future<void> reload(ReferenceLine line) async {
    final source = _source;
    if (source == null) return;
    final lap = _lap;
    await load(
      source,
      line,
      recordingId: lap?.recordingId,
      lapNumber: lap?.lapNumber,
    );
  }

  /// Reads the choice [store] kept for the day, if any, timed on [line]:
  /// once, so a reference cleared since stays cleared. A source that is
  /// not found shows as failed with its reason, and stays kept.
  Future<void> restore(ReferenceLine line) async {
    if (_restoreTried) return;
    _restoreTried = true;
    final generation = _generation;
    final ReferenceChoice? choice;
    try {
      choice = await store.restore(dayId);
    } on Object catch (error) {
      debugPrint('Reference not restored: $error');
      return;
    }
    if (choice == null || _disposed || generation != _generation) return;
    await load(
      choice.source,
      line,
      recordingId: choice.recordingId,
      lapNumber: choice.lapNumber,
      restored: choice,
    );
  }

  /// Makes [lap], one of the timing's candidates, the reference.
  /// A source whose only laps its day excluded is refused until one of
  /// them is chosen on purpose.
  void choose(ReferenceLapCandidate lap) {
    if ((_state != ReferenceState.ready && _state != ReferenceState.refused) ||
        !(_timing?.candidates.contains(lap) ?? false)) {
      return;
    }
    _state = ReferenceState.ready;
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
    _lastKept = null;
    notifyListeners();
    unawaited(_write(null));
  }

  /// Keeps the lap now chosen. Only a lap is kept: a source that could not
  /// be read or timed this time (a file moved, today's line changed) does
  /// not forget the choice kept before it.
  void _keep() {
    final source = _source, lap = _lap;
    if (source == null || lap == null) return;
    final choice = ReferenceChoice(
      source: source,
      recordingId: lap.recordingId,
      lapNumber: lap.lapNumber,
    );
    if (_lastKept case final kept?
        when kept.source == choice.source &&
            kept.recordingId == choice.recordingId &&
            kept.lapNumber == choice.lapNumber) {
      return;
    }
    unawaited(_write(choice));
  }

  /// Writes the choice again after it could not be kept.
  void retryKeep() {
    if (_keepState != ReferenceKeep.failed) return;
    unawaited(_write(_failedChoice));
  }

  Future<void> _write(ReferenceChoice? choice) async {
    final generation = ++_keepGeneration;
    if (choice != null) {
      _keepState = ReferenceKeep.saving;
      _keepProblem = null;
      notifyListeners();
    }
    ReferenceKeep outcome;
    ProfileReferenceProblem? problem;
    try {
      outcome = await store.keep(dayId, choice)
          ? ReferenceKeep.saved
          : ReferenceKeep.unsaved;
    } on ProfileReferenceError catch (error) {
      debugPrint('Reference not kept: ${error.message}');
      outcome = ReferenceKeep.failed;
      problem = error.problem;
    } on Object catch (error) {
      debugPrint('Reference not kept: $error');
      outcome = ReferenceKeep.failed;
    }
    if (_disposed || generation != _keepGeneration) return;
    _keepState = outcome;
    _keepProblem = problem;
    if (outcome == ReferenceKeep.failed) {
      _failedChoice = choice;
      _failedForget = choice == null;
    } else {
      _failedChoice = null;
      _failedForget = false;
      if (choice != null) _lastKept = choice;
    }
    notifyListeners();
  }

  bool get disposed => _disposed;

  @override
  void dispose() {
    _disposed = true;
    _task?.cancel();
    _task = null;
    super.dispose();
  }
}

final _holders = Expando<ReferenceLapHolder>('reference laps');

/// The reference lap of the open day [day] (its [DayResultsController]):
/// one holder per day, made on first use, kept while the day is kept (a
/// day the shell keeps open between visits keeps its reference), and
/// disposed with the day by [disposeReferenceLapOf].
ReferenceLapHolder referenceLapOf(
  Object day, {
  String dayId = '',
  ReferenceStore store = const UnsavedReferenceStore(),
}) {
  final held = _holders[day];
  if (held != null && !held.disposed) return held;
  return _holders[day] = ReferenceLapHolder(dayId: dayId, store: store);
}

/// Disposes [day]'s reference lap, if it has one, and stops a reference
/// still being read: called when the day itself is disposed.
void disposeReferenceLapOf(Object day) {
  _holders[day]?.dispose();
  _holders[day] = null;
}
