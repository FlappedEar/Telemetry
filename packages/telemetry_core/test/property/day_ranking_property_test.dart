// Property tests for the day's lap ranking (FET-216): the order the runs
// were imported in (their source order and the order of the rows) never
// changes the best lap of the day, the order of the ranked laps, each run's
// result or the laps left out, even when laps tie to the millisecond.
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'generators.dart';

const _seed = 216301;
const _cases = 100;
const _gates = 'gates-v1:0000000000000000000000000000000000000000000000000000000000000000';
const _track = TrackConfiguration(
  layoutId: 'Synthetic',
  direction: TrackDirection.counterclockwise,
  gateRevision: _gates,
);
const _otherTrack = TrackConfiguration(
  layoutId: 'Synthetic',
  direction: TrackDirection.clockwise,
  gateRevision: _gates,
);

TelemetrySession _dated(TelemetrySession session, int? milliseconds) => TelemetrySession(
  duration: session.duration,
  startTime: session.startTime,
  metadata: {
    ...session.metadata,
    if (milliseconds != null) 'firstTimestampMilliseconds': '$milliseconds',
  },
  channels: session.channels,
  aliases: session.aliases,
  warnings: session.warnings,
  timingGates: session.timingGates,
  sampleCount: session.sampleCount,
);

/// A day of 2–5 runs from generated recordings; some runs are a copy of an
/// earlier one (another file of the same drive), so their laps tie exactly.
({
  List<List<DayLapRow>> runs,
  Map<String, TrackConfiguration> configurations,
  Map<DayLapReference, String> exclusions,
  Set<String> stale,
})
_day(math.Random random, String label) {
  final count = 2 + random.nextInt(4);
  final sessions = <TelemetrySession>[];
  final runs = <List<DayLapRow>>[];
  final configurations = <String, TrackConfiguration>{};
  final exclusions = <DayLapReference, String>{};
  final stale = <String>{};
  for (var index = 0; index < count; ++index) {
    final TelemetrySession session;
    if (index > 0 && random.nextDouble() < 0.3) {
      session = sessions[random.nextInt(sessions.length)];
    } else {
      session = generateLapCase(random, '$label run $index').session;
    }
    sessions.add(session);
    final dated = random.nextDouble() < 0.6;
    // Dated runs sometimes share a start time, so the clock cannot break
    // their tie either.
    final start = dated ? 1756454400000 + random.nextInt(3) * 3600000 : null;
    final runId = 'run:${String.fromCharCode(97 + random.nextInt(26))}$index';
    final rows = dayLapRows(
      _dated(session, start),
      deriveSourceLapSession(session),
      runId: runId,
      runName: 'Session ${index + 1}',
      sourceRevision: (index % 10).toString() * 64,
    );
    configurations[runId] = random.nextDouble() < 0.85 ? _track : _otherTrack;
    if (random.nextDouble() < 0.15) stale.add(runId);
    for (final row in rows) {
      if (row.type == LapSectionType.lap && random.nextDouble() < 0.1) {
        exclusions[row.reference] = 'Traffic';
      }
    }
    runs.add(rows);
  }
  return (runs: runs, configurations: configurations, exclusions: exclusions, stale: stale);
}

/// The rows of [runs] imported in [order]: each run's source order is its
/// place in it, and the rows come in a shuffled order.
List<DayLapRow> _imported(math.Random random, List<List<DayLapRow>> runs, List<int> order) => [
  for (var place = 0; place < order.length; ++place)
    for (final row in runs[order[place]]) row.copyWith(sourceOrder: place),
]..shuffle(random);

String _row(DayLapRow? row) => row == null
    ? 'none'
    : '${row.runId} ${row.type.label} ${row.start} ${row.end} ${row.timestampMilliseconds}';

String _ranking(DayRanking ranking) => [
  ranking.state,
  'best ${_row(ranking.bestOfDay)}',
  'laps ${ranking.lapCount} ties ${ranking.tieCount}',
  for (final row in ranking.eligibleLaps) 'eligible ${_row(row)}',
  for (final run in ranking.runs)
    'run ${run.runId} ${run.runName} ${run.lapCount} ${run.eligibleLapCount} ${run.tieCount} '
        '${_row(run.bestLap)} ${run.distribution?.median} ${run.distribution?.q1} '
        '${run.distribution?.q3}',
  ...([
    for (final excluded in ranking.excludedLaps)
      'excluded ${_row(excluded.row)} ${excluded.issues} ${excluded.userReason}',
  ]..sort()),
].join('\n');

void main() {
  test('the ranking does not depend on the order runs were imported in', () {
    final random = math.Random(_seed);
    var ranked = 0, crossRunTies = 0;
    for (var index = 0; index < _cases; ++index) {
      final label = 'seed $_seed case $index';
      final day = _day(random, label);
      final groupId = _track.compatibilityGroupId;
      DayRanking rank(List<int> order) => rankDayLaps(
        _imported(random, day.runs, order),
        groupId,
        day.configurations,
        exclusions: day.exclusions,
        staleRunIds: day.stale,
      );
      final identity = [for (var i = 0; i < day.runs.length; ++i) i];
      final reference = rank(identity);
      if (reference.state == DayRankingState.available) ++ranked;

      // The ranking's own invariants.
      final eligible = reference.eligibleLaps;
      expect(reference.bestOfDay, eligible.isEmpty ? isNull : same(eligible.first), reason: label);
      for (var i = 1; i < eligible.length; ++i) {
        expect(
          eligible[i].durationSeconds,
          greaterThanOrEqualTo(eligible[i - 1].durationSeconds),
          reason: label,
        );
      }
      for (final run in reference.runs) {
        final best = run.bestLap;
        if (best == null) continue;
        for (final row in eligible.where((row) => row.runId == run.runId)) {
          expect(best.durationSeconds, lessThanOrEqualTo(row.durationSeconds), reason: label);
        }
      }

      for (var i = 1; i < eligible.length; ++i) {
        if (eligible[i].durationSeconds == eligible[i - 1].durationSeconds &&
            eligible[i].runId != eligible[i - 1].runId) {
          ++crossRunTies;
        }
      }

      final expected = _ranking(reference);
      for (var attempt = 0; attempt < 4; ++attempt) {
        final order = [...identity]..shuffle(random);
        expect(_ranking(rank(order)), expected, reason: '$label order $order');
      }
    }
    expect(ranked, greaterThan(_cases ~/ 2));
    // Laps of different runs tied exactly, so the tie-break was exercised.
    expect(crossRunTies, greaterThan(10));
  });
}
