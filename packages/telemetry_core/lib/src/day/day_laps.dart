// Port of VBOOverlay native/src/telemetry/OutingLaps.{h,cpp} (FET-21): the
// lap sections of every run of a day, and how they are identified.
import '../laps/lap_session.dart';
import '../operation.dart';
import '../telemetry_session.dart';

/// Most lap sections (OUT, laps, IN) one day may hold.
const int maximumDayLapRows = 20000;

/// What part of a run a lap section is.
enum LapSectionType {
  /// From the start of the recording to the first gate pass.
  outLap('OUT'),

  /// A timed lap, gate to gate.
  lap('LAP'),

  /// From the last gate pass to the end of the recording.
  inLap('IN'),

  /// The whole recording, when it has no accepted gate pass.
  unknown('UNKNOWN');

  const LapSectionType(this.label);

  /// The name shown in the lap list and stored in lap references.
  final String label;
}

/// A lap section's identity: its exact bounds in one recording's content.
/// Never a lap number or a row index, so it survives renaming and reordering.
final class DayLapReference {
  const DayLapReference({
    required this.runId,
    required this.sourceRevision,
    required this.type,
    required this.startTime,
    required this.endTime,
  });

  final String runId;

  /// The recording's content SHA-256, lowercase hex.
  final String sourceRevision;
  final LapSectionType type;
  final double startTime;
  final double endTime;

  @override
  bool operator ==(Object other) =>
      other is DayLapReference &&
      other.runId == runId &&
      other.sourceRevision == sourceRevision &&
      other.type == type &&
      other.startTime == startTime &&
      other.endTime == endTime;

  @override
  int get hashCode => Object.hash(runId, sourceRevision, type, startTime, endTime);

  @override
  String toString() => '${type.label} $runId [$startTime, $endTime]';
}

/// One row of a day's lap list.
final class DayLapRow {
  const DayLapRow({
    required this.runId,
    required this.runName,
    required this.type,
    required this.lapNumber,
    required this.start,
    required this.end,
    required this.sourceRevision,
    this.timestampMilliseconds,
    this.sourceOrder = 0,
    this.referenceEligible = false,
    this.referenceIssue = LapReferenceIssue.none,
    this.bestOfRun = false,
    this.offRoute = false,
  });

  final String runId;
  final String runName;
  final LapSectionType type;

  /// The lap's number within its run; 0 for OUT, IN and UNKNOWN.
  final int lapNumber;

  /// Recording time in seconds.
  final double start;
  final double end;
  final String sourceRevision;

  /// The section's start in Unix milliseconds, when the recording has a clock.
  final int? timestampMilliseconds;

  /// The run's position in the day as imported; orders undated runs.
  final int sourceOrder;

  /// The recording's own lap eligibility (GPS), before day-level reasons.
  final bool referenceEligible;
  final LapReferenceIssue referenceIssue;

  /// The fastest eligible lap of its recording, before day-level reasons.
  final bool bestOfRun;

  /// The lap leaves the route the run's other laps took (off track, a detour
  /// or the pit lane). Set by track inference.
  final bool offRoute;

  double get durationSeconds => end - start;

  DayLapReference get reference => DayLapReference(
    runId: runId,
    sourceRevision: sourceRevision,
    type: type,
    startTime: start,
    endTime: end,
  );

  /// "Session 3 · LAP 2", "Session 3 · OUT".
  String get displayName =>
      type == LapSectionType.lap ? '$runName · LAP $lapNumber' : '$runName · ${type.label}';

  DayLapRow copyWith({String? runName, int? sourceOrder, bool? offRoute}) => DayLapRow(
    runId: runId,
    runName: runName ?? this.runName,
    type: type,
    lapNumber: lapNumber,
    start: start,
    end: end,
    sourceRevision: sourceRevision,
    timestampMilliseconds: timestampMilliseconds,
    sourceOrder: sourceOrder ?? this.sourceOrder,
    referenceEligible: referenceEligible,
    referenceIssue: referenceIssue,
    bestOfRun: bestOfRun,
    offRoute: offRoute ?? this.offRoute,
  );
}

const int _maximumSafeMilliseconds = 8640000000000000;

/// The OUT, LAP and IN sections of one run, or a single UNKNOWN section when
/// the recording has no accepted gate pass. Sections with non-finite, negative
/// or empty bounds are left out.
List<DayLapRow> dayLapRows(
  TelemetrySession session,
  LapSession laps, {
  required String runId,
  required String runName,
  required String sourceRevision,
  int sourceOrder = 0,
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  final rows = <DayLapRow>[];
  if (!session.duration.isFinite || session.duration <= 0.0) return rows;
  if (laps.timedLaps.length > maximumDayLapRows - 2) {
    throw const ResourceLimitError('Too many lap sections in this recording.');
  }
  final origin = int.tryParse(session.metadata['firstTimestampMilliseconds'] ?? '');
  final fastest = laps.fastestLapIndex;
  final fastestNumber = fastest != null && fastest >= 0 && fastest < laps.timedLaps.length
      ? laps.timedLaps[fastest].number
      : null;

  void append(LapSectionType type, int number, double start, double end, [TimedLap? lap]) {
    throwIfCancelled(cancelled);
    if (!start.isFinite || !end.isFinite || start < 0.0 || end > session.duration || end <= start) {
      return;
    }
    int? timestamp;
    if (origin != null) {
      final delta = (start * 1000.0).round();
      if (origin <= _maximumSafeMilliseconds - delta) timestamp = origin + delta;
    }
    rows.add(
      DayLapRow(
        runId: runId,
        runName: runName,
        type: type,
        lapNumber: number,
        start: start,
        end: end,
        sourceRevision: sourceRevision,
        timestampMilliseconds: timestamp,
        sourceOrder: sourceOrder,
        referenceEligible: lap?.referenceEligible ?? false,
        referenceIssue: lap?.referenceIssue ?? LapReferenceIssue.none,
        bestOfRun: lap != null && lap.referenceEligible && lap.number == fastestNumber,
      ),
    );
  }

  if (laps.acceptedPasses.isEmpty) {
    append(LapSectionType.unknown, 0, 0.0, session.duration);
    return rows;
  }
  append(LapSectionType.outLap, 0, 0.0, laps.acceptedPasses.first.telemetryTime);
  for (final lap in laps.timedLaps) {
    append(LapSectionType.lap, lap.number, lap.startTelemetryTime, lap.endTelemetryTime, lap);
  }
  append(LapSectionType.inLap, 0, laps.acceptedPasses.last.telemetryTime, session.duration);
  return rows;
}

/// [rows] in recording-time order. Sections without a clock follow the dated
/// ones, in import order and then by start. Stable.
List<DayLapRow> sortDayLaps(List<DayLapRow> rows) {
  if (rows.length > maximumDayLapRows) {
    throw const ResourceLimitError('Too many lap sections in this day.');
  }
  final order = List<int>.generate(rows.length, (index) => index);
  order.sort((left, right) {
    final a = rows[left], b = rows[right];
    final clockA = a.timestampMilliseconds, clockB = b.timestampMilliseconds;
    if ((clockA == null) != (clockB == null)) return clockA != null ? -1 : 1;
    if (clockA != null && clockB != null && clockA != clockB) return clockA.compareTo(clockB);
    if (a.sourceOrder != b.sourceOrder) return a.sourceOrder.compareTo(b.sourceOrder);
    if (a.start != b.start) return a.start.compareTo(b.start);
    return left.compareTo(right);
  });
  return [for (final index in order) rows[index]];
}
