// The day's corner-phase reference (FET-226) from the theoretical best's
// laps: the same idea as the raw theoretical best at a finer grain, ranked
// laps only, corners not split taken whole with the reason, and speeds in
// different units never compared as they are.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

// A lap at [straight] m/s, slowed to [slow] m/s over [from, to] metres.
double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => d >= from && d <= to ? slow : straight;

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

// [session] with its speed recorded in [unit], [perKmh] of it to a km/h.
TelemetrySession _inUnit(TelemetrySession session, String unit, double perKmh) {
  final speed = session.channels['velocity']!;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      ...session.channels,
      'velocity': TelemetryChannel(
        name: 'velocity',
        unit: unit,
        timestamps: speed.timestamps,
        values: Float32List.fromList([for (final value in speed.values) value * perKmh]),
      ),
    },
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

// Every lap loses time somewhere else, so pieces come from several laps.
final _speeds = [
  [_lap(30, 50, 120, 20), _lap(31, 300, 400, 25), _lap(30, 550, 650, 22)],
  [_lap(29, 0, 0, 0), _lap(30.5, 700, 780, 20)],
];

({DayTheoreticalBest result, Map<String, OutingRun> outing}) _day({
  String firstUnit = '',
  String secondUnit = '',
  double perKmh = 1,
  Map<DayLapReference, String> exclusions = const {},
}) {
  final runs = [
    _run('run1', _inUnit(rectangleSession(_speeds[0]), firstUnit, 1)),
    _run('run2', _inUnit(rectangleSession(_speeds[1]), secondUnit, perKmh)),
  ];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  return (
    result: dayTheoreticalBest(analyzeDay(runs, exclusions: exclusions), outing, random: Random(1)),
    outing: outing,
  );
}

// [corner] with [split] in place of its own, and without the laps'
// projections unless [traces].
DayCorner _withSplit(DayCorner corner, CornerPhaseSplit split, {bool traces = true}) => DayCorner(
  segmentIndex: corner.segmentIndex,
  segmentId: corner.segmentId,
  name: corner.name,
  startProgressMeters: corner.startProgressMeters,
  endProgressMeters: corner.endProgressMeters,
  laps: corner.laps,
  bestLap: corner.bestLap,
  phaseSplit: split,
  traces: traces ? corner.traces : const {},
  classification: corner.classification,
);
void main() {
  final day = _day();
  final result = day.result;
  final phases = result.bestPhases!;
  final sessions = {for (final MapEntry(:key, :value) in day.outing.entries) key: value.session};

  test('each split corner in three parts, each from the lap fastest there', () {
    expect(result.state, DayTheoreticalBestState.ready);
    final split = [
      for (final corner in result.corners)
        if (corner.phaseSplit.valid) corner,
    ];
    expect(split, isNotEmpty);
    expect(phases.pieces, hasLength(result.segments.length + 2 * split.length));
    for (final corner in split) {
      final parts = [
        for (final (i, piece) in phases.pieces.indexed)
          if (piece.piece.segmentIndex == corner.segmentIndex) (i, piece),
      ];
      expect(
        [for (final (_, part) in parts) part.piece.part],
        [PhasePart.entry, PhasePart.middle, PhasePart.exit],
      );
      final at = parts.first.$1;
      for (final lap in result.laps) {
        final times = corner.phaseTimes(lap.lap.reference);
        expect(times.valid, isTrue);
        expect(phases.lapSeconds[lap.lap.reference]!.sublist(at, at + 3), [
          times.entry,
          times.mid,
          times.exit,
        ]);
        // Its parts add up to its time through the corner.
        expect(times.total, closeTo(lap.seconds(corner.segmentIndex)!, 1e-6));
      }
      for (final (i, (_, part)) in parts.indexed) {
        final fastest = [
          for (final lap in result.laps)
            switch (corner.phaseTimes(lap.lap.reference)) {
              final times => [times.entry, times.mid, times.exit][i]!,
            },
        ].reduce(min);
        expect(part.seconds, fastest);
      }
      // Never slower than the whole corner's fastest time.
      expect(
        parts.fold(0.0, (sum, part) => sum + part.$2.seconds!),
        lessThanOrEqualTo(result.segments[corner.segmentIndex].seconds! + 1e-9),
      );
    }
    // A finer grain of the same idea: never slower than either best.
    expect(phases.totalSeconds, lessThanOrEqualTo(result.theoreticalBestSeconds! + 1e-9));
    expect(phases.joinedSeconds, lessThanOrEqualTo(result.realistic!.totalSeconds! + 1e-9));
    expect(phases.joinedSeconds, greaterThanOrEqualTo(phases.totalSeconds! - 1e-9));
    // The best lap's pieces add up to its lap.
    final best = result.bestLap!.reference;
    expect(phases.lapTotal(best), closeTo(result.bestLapSeconds!, 1e-6));
    // The speed declares no unit: read as km/h, and said to be assumed.
    expect(phases.speedUnit, 'km/h');
    expect(phases.speedUnitAssumed, isTrue);
    // The joins between laps follow the realistic best's rule.
    for (final piece in phases.pieces) {
      switch (piece.join) {
        case PhaseJoin.joins:
          expect(piece.joinMetresPerSecond, lessThanOrEqualTo(realisticJoinMetresPerSecond));
        case PhaseJoin.apart:
          expect(piece.joinMetresPerSecond, greaterThan(realisticJoinMetresPerSecond));
        case PhaseJoin.none || PhaseJoin.sameLap || PhaseJoin.unknown:
          expect(piece.joinMetresPerSecond, isNull);
      }
    }
  });

  test('with no corner split it is the theoretical best, raw and joined', () {
    final whole = dayPhaseReference(result.computed!, [
      for (final corner in result.corners)
        _withSplit(corner, const CornerPhaseSplit(unavailableReason: cornerPhaseMultipleApexes)),
    ], sessions);
    expect(whole.pieces, hasLength(result.segments.length));
    for (final (i, piece) in whole.pieces.indexed) {
      expect(piece.piece.part, PhasePart.whole);
      expect(piece.piece.segmentId, result.segments[i].segmentId);
      expect(piece.seconds, result.segments[i].seconds);
      expect(piece.lapReference, result.segments[i].sourceLapReference);
      // A corner says why it is not split; a straight is never split.
      final corner = result.cornerAt(i) != null;
      expect(piece.piece.corner, corner);
      expect(piece.piece.splitReason, corner ? cornerPhaseMultipleApexes : isEmpty);
    }
    expect(whole.totalSeconds, closeTo(result.theoreticalBestSeconds!, 1e-9));
    expect(whole.joinedSeconds, closeTo(result.realistic!.totalSeconds!, 1e-9));
    // The best lap loses what the theoretical best says is available.
    final losses = whole.lossesOf(result.bestLap!.reference);
    expect(losses.fold(0.0, (sum, loss) => sum + loss!), closeTo(result.availableSeconds!, 1e-9));
  });

  test('a split corner no lap is timed through is taken whole, and says so', () {
    final corner = result.corners.firstWhere((corner) => corner.phaseSplit.valid);
    final reference = dayPhaseReference(result.computed!, [
      for (final c in result.corners)
        if (c.segmentIndex == corner.segmentIndex)
          _withSplit(corner, corner.phaseSplit, traces: false)
        else
          c,
    ], const {});
    final piece = reference.pieces.firstWhere(
      (piece) => piece.piece.segmentIndex == corner.segmentIndex,
    );
    expect(piece.piece.part, PhasePart.whole);
    expect(piece.piece.splitReason, cornerPhaseTimesNotTimed);
    expect(piece.seconds, result.segments[corner.segmentIndex].seconds);
    // Without recordings no speed is known, so nothing is joined.
    expect(reference.joinedUnavailableReason, phaseReferenceNoSpeed);
  });

  test('a corner is taken whole when a lap timed through it has no parts', () {
    final corner = result.corners.firstWhere((corner) => corner.phaseSplit.valid);
    final whole = result.segments[corner.segmentIndex];
    // The lap fastest through the whole corner has no projection here: its
    // parts are not timed, so splitting would drop it and could be slower.
    final fastest = whole.sourceLapReference as DayLapReference;
    final dropped = DayCorner(
      segmentIndex: corner.segmentIndex,
      segmentId: corner.segmentId,
      name: corner.name,
      startProgressMeters: corner.startProgressMeters,
      endProgressMeters: corner.endProgressMeters,
      laps: corner.laps,
      bestLap: corner.bestLap,
      phaseSplit: corner.phaseSplit,
      traces: {
        for (final entry in corner.traces.entries)
          if (entry.key != fastest) entry.key: entry.value,
      },
      classification: corner.classification,
    );
    final reference = dayPhaseReference(result.computed!, [
      for (final c in result.corners)
        if (c.segmentIndex == corner.segmentIndex) dropped else c,
    ], sessions);
    final pieces = reference.pieces.where((p) => p.piece.segmentIndex == corner.segmentIndex);
    expect(pieces, hasLength(1));
    expect(pieces.single.piece.part, PhasePart.whole);
    expect(pieces.single.piece.splitReason, cornerPhaseTimesNotTimed);
    expect(pieces.single.seconds, whole.seconds);
    expect(pieces.single.lapReference, fastest);
    // So the claim holds: never slower than the raw best.
    expect(reference.totalSeconds, lessThanOrEqualTo(result.theoreticalBestSeconds! + 1e-6));
    expect(reference.joinedSeconds, lessThanOrEqualTo(result.realistic!.totalSeconds! + 1e-6));
    // A lap with no time through the corner at all does not stop the split.
    expect(phases.pieces.where((p) => p.piece.segmentIndex == corner.segmentIndex), hasLength(3));
  });

  test('a lap that is not ranked gives no piece', () {
    final fastest = phases.pieces.first.lapReference as DayLapReference;
    final excluded = _day(exclusions: {fastest: 'test'}).result.bestPhases!;
    expect(excluded.valid, isTrue);
    expect(phases.lapSeconds.keys, contains(fastest));
    expect(excluded.lapSeconds.keys, isNot(contains(fastest)));
    expect([for (final piece in excluded.pieces) piece.lapReference], isNot(contains(fastest)));
  });

  test('speeds in different units are compared as m/s, never as written', () {
    final kmh = _day(firstUnit: 'km/h', secondUnit: 'km/h').result.bestPhases!;
    final mph = _day(firstUnit: 'km/h', secondUnit: 'mph', perKmh: 1 / 1.609344).result.bestPhases!;
    expect(kmh.speedUnit, 'km/h');
    expect(kmh.speedUnitAssumed, isFalse, reason: 'declared');
    // One undeclared, one declared: read as km/h, said so, no one unit.
    final mixed = _day(firstUnit: 'mph', secondUnit: '', perKmh: 1 / 1.609344).result.bestPhases!;
    expect(mixed.speedUnit, isEmpty);
    expect(mixed.speedUnitAssumed, isTrue);
    // Mixed units: no one unit to show differences in.
    expect(mph.speedUnit, isEmpty);
    expect(
      [for (final piece in mph.pieces) piece.join],
      [for (final piece in kmh.pieces) piece.join],
    );
    for (var i = 0; i < mph.pieces.length; ++i) {
      if (kmh.pieces[i].joinMetresPerSecond case final expected?) {
        expect(mph.pieces[i].joinMetresPerSecond, closeTo(expected, 1e-3));
      }
    }
    expect(mph.joinedSeconds, closeTo(kmh.joinedSeconds!, 1e-9));
    // A unit that is not known is never compared: a join between laps of
    // the two sessions is not known.
    final unknown = _day(
      firstUnit: 'km/h',
      secondUnit: 'furlongs per fortnight',
    ).result.bestPhases!;
    expect(unknown.speedUnit, isEmpty);
    // Only laps of the first session, in km/h, are compared.
    for (final (i, piece) in unknown.pieces.indexed) {
      if (piece.join == PhaseJoin.joins || piece.join == PhaseJoin.apart) {
        final before = unknown.pieces[i == 0 ? unknown.pieces.length - 1 : i - 1];
        expect((piece.lapReference as DayLapReference).runId, 'run1');
        expect((before.lapReference as DayLapReference).runId, 'run1');
      }
    }
    final secondSession = [
      for (final (i, piece) in unknown.pieces.indexed)
        if (i > 0 &&
            piece.join != PhaseJoin.none &&
            piece.join != PhaseJoin.sameLap &&
            ((piece.lapReference as DayLapReference).runId == 'run2' ||
                (unknown.pieces[i - 1].lapReference as DayLapReference).runId == 'run2'))
          piece.join,
    ];
    expect(secondSession, isNotEmpty);
    expect(secondSession.toSet(), {PhaseJoin.unknown});
  });
}
