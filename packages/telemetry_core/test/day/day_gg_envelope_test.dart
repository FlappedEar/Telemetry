import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

/// A recording of G pairs at 10 Hz from 0 s: [pairs] are (longitudinal,
/// lateral) in [unit].
TelemetrySession _gSession(
  List<(double, double)> pairs, {
  String unit = 'g',
  bool lateral = true,
  String longitudinalName = 'long accel',
  String lateralName = 'lat accel',
}) {
  final times = Float64List.fromList([for (var i = 0; i < pairs.length; ++i) i / 10]);
  TelemetryChannel channel(String name, Iterable<double> values) => TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: times,
    values: Float32List.fromList(values.toList()),
  );
  return TelemetrySession(
    duration: times.isEmpty ? 0 : times.last,
    startTime: 0,
    metadata: const {},
    channels: {
      longitudinalName: channel(longitudinalName, [for (final pair in pairs) pair.$1]),
      if (lateral) lateralName: channel(lateralName, [for (final pair in pairs) pair.$2]),
    },
    aliases: {
      'longitudinalAcceleration': longitudinalName,
      if (lateral) 'lateralAcceleration': lateralName,
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: pairs.length,
  );
}

DayLapRow _row(
  String run,
  double start,
  double end, {
  LapSectionType type = LapSectionType.lap,
  int number = 1,
  int? clock,
}) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: type,
  lapNumber: type == LapSectionType.lap ? number : 0,
  start: start,
  end: end,
  sourceRevision: _revision,
  timestampMilliseconds: clock,
);

/// [count] pairs pointing to [direction] with combined G spread evenly
/// from [low] to [high].
List<(double, double)> _toward(GgDirection direction, int count, double low, double high) => [
  for (var i = 0; i < count; ++i)
    () {
      final magnitude = count == 1 ? high : low + (high - low) * i / (count - 1);
      return (magnitude * math.cos(direction.angle), magnitude * math.sin(direction.angle));
    }(),
];

/// 100 pairs in every direction, combined G from 0.2 to [peak] (or the
/// direction's own peak in [peaks]).
List<(double, double)> _allDirections(double peak, [Map<GgDirection, double> peaks = const {}]) => [
  for (final direction in GgDirection.values)
    ..._toward(direction, 100, 0.2, peaks[direction] ?? peak),
];

void main() {
  group('ggDirectionOf', () {
    test('reads accelerating up and the recording\'s positive lateral as left', () {
      expect(ggDirectionOf(0.5, 0), GgDirection.accelerating);
      expect(ggDirectionOf(-0.8, 0), GgDirection.braking);
      expect(ggDirectionOf(0, 0.9), GgDirection.left);
      expect(ggDirectionOf(0, -0.9), GgDirection.right);
      expect(ggDirectionOf(-0.5, 0.5), GgDirection.brakingLeft);
      expect(ggDirectionOf(-0.5, -0.5), GgDirection.brakingRight);
      expect(ggDirectionOf(0.3, 0.3), GgDirection.acceleratingLeft);
      expect(ggDirectionOf(0.3, -0.3), GgDirection.acceleratingRight);
      // Sectors are 45° wide around each direction.
      expect(ggDirectionOf(1, math.tan(0.38)), GgDirection.accelerating);
      expect(ggDirectionOf(1, math.tan(0.41)), GgDirection.acceleratingLeft);
      expect(ggDirectionOf(-1, -0.01), GgDirection.braking);
    });

    test('tells calculated channels from measured ones', () {
      expect(ggChannelCalculated('longacc-calc'), isTrue);
      expect(ggChannelCalculated('LatAcc-Calc'), isTrue);
      expect(ggChannelCalculated('long accel'), isFalse);
    });
  });

  group('dayGgEnvelope', () {
    test('is the 95th percentile of combined G in each direction', () {
      final session = _gSession(_allDirections(1.2));
      final day = dayGgEnvelope([_row('1', 0, 1000)], {'1': session});
      final envelope = day.sessions.single;
      expect(envelope.valid, isTrue);
      expect(envelope.lapCount, 1);
      expect(envelope.lapsWithG, 1);
      expect(envelope.sampleCount, 800);
      for (final direction in GgDirection.values) {
        expect(envelope.sectors[direction.index].sampleCount, 100);
        // The 95th of 100 evenly spread values from 0.2 to 1.2.
        expect(envelope.valueG(direction), closeTo(0.2 + 1.0 * 94 / 99, 1e-6));
      }
      expect(envelope.longitudinalChannel, 'long accel');
      expect(envelope.lateralChannel, 'lat accel');
      expect(envelope.unitsDeclared, isTrue);
      expect(envelope.calculated, isFalse);
    });

    test('a single strong sample does not set the envelope', () {
      final pairs = [..._toward(GgDirection.braking, 99, 0.5, 0.5), (-3.5, 0.0)];
      final day = dayGgEnvelope([_row('1', 0, 1000)], {'1': _gSession(pairs)});
      expect(day.sessions.single.valueG(GgDirection.braking), closeTo(0.5, 1e-6));
    });

    test('counts only the laps passed, never out or in laps', () {
      // 0–10 s braking hard (the out lap), 10–20 s a lap, 20–30 s
      // turning hard (the in lap).
      final pairs = [
        ..._toward(GgDirection.braking, 100, 1.5, 1.5),
        ..._toward(GgDirection.braking, 100, 0.6, 0.6),
        ..._toward(GgDirection.left, 100, 1.4, 1.4),
      ];
      final day = dayGgEnvelope(
        [
          _row('1', 0, 9.95, type: LapSectionType.outLap),
          _row('1', 10, 19.95),
          _row('1', 20, 29.9, type: LapSectionType.inLap),
        ],
        {'1': _gSession(pairs)},
      );
      final envelope = day.sessions.single;
      expect(envelope.lapCount, 1);
      expect(envelope.sampleCount, 100);
      expect(envelope.valueG(GgDirection.braking), closeTo(0.6, 1e-6));
      expect(envelope.valueG(GgDirection.left), isNull);
    });

    test('a direction with too few samples has no value', () {
      final pairs = [
        ..._toward(GgDirection.left, 100, 0.8, 0.8),
        ..._toward(GgDirection.braking, ggEnvelopeMinimumSamples - 1, 0.9, 0.9),
      ];
      final envelope = dayGgEnvelope([_row('1', 0, 1000)], {'1': _gSession(pairs)}).sessions.single;
      expect(envelope.valid, isTrue);
      expect(envelope.valueG(GgDirection.left), closeTo(0.8, 1e-6));
      expect(envelope.valueG(GgDirection.braking), isNull);
      expect(envelope.sectors[GgDirection.braking.index].sampleCount, 24);
    });

    test('says when a session has too little data in every direction', () {
      final pairs = [for (final direction in GgDirection.values) ..._toward(direction, 10, 1, 1)];
      final envelope = dayGgEnvelope([_row('1', 0, 1000)], {'1': _gSession(pairs)}).sessions.single;
      expect(envelope.valid, isFalse);
      expect(envelope.unavailableReason, ggEnvelopeTooFewSamples);
      expect(envelope.sectors, isEmpty);
      expect(envelope.sampleCount, 80);
    });

    test('leaves out samples too small to have a direction', () {
      final pairs = [
        ..._toward(GgDirection.accelerating, 200, 0.02, 0.09),
        ..._toward(GgDirection.accelerating, 50, 0.3, 0.3),
      ];
      final envelope = dayGgEnvelope([_row('1', 0, 1000)], {'1': _gSession(pairs)}).sessions.single;
      expect(envelope.neutralSamples, 200);
      expect(envelope.sectors[GgDirection.accelerating.index].sampleCount, 50);
      expect(envelope.valueG(GgDirection.accelerating), closeTo(0.3, 1e-6));
    });

    test('converts m/s² to g and keeps undeclared units as g, reported', () {
      final metric = _gSession(_toward(GgDirection.braking, 50, 9.80665, 9.80665), unit: 'm/s²');
      final undeclared = _gSession(_toward(GgDirection.braking, 50, 0.7, 0.7), unit: '');
      final day = dayGgEnvelope(
        [_row('1', 0, 1000), _row('2', 0, 1000)],
        {'1': metric, '2': undeclared},
      );
      expect(day.sessions[0].valueG(GgDirection.braking), closeTo(1.0, 1e-6));
      expect(day.sessions[1].valueG(GgDirection.braking), closeTo(0.7, 1e-6));
      expect(day.sessions[1].unitsDeclared, isFalse);
    });

    test('says why a session has no envelope', () {
      final day = dayGgEnvelope(
        [_row('1', 0, 1000), _row('2', 0, 1000), _row('3', 0, 1000), _row('4', 50, 60)],
        {
          '1': null,
          '2': _gSession(_allDirections(1), lateral: false),
          '3': _gSession(_allDirections(1), unit: 'ft/s2'),
          '4': _gSession(_toward(GgDirection.left, 10, 1, 1)),
        },
      );
      expect(
        [for (final session in day.sessions) session.unavailableReason],
        [channelRecordingUnavailable, ggMissingLateral, ggUnsupportedUnit, ggNoOverlap],
      );
      expect(day.any, isFalse);
      expect(day.best, everyElement(isNull));
      expect(day.unused, isEmpty);
    });

    test('marks calculated channels', () {
      final session = _gSession(
        _allDirections(1),
        longitudinalName: 'longacc-calc',
        lateralName: 'latacc-calc',
      );
      final envelope = dayGgEnvelope([_row('1', 0, 1000)], {'1': session}).sessions.single;
      expect(envelope.calculated, isTrue);
      // Only the G channels go to the background.
      final slim = ggEnvelopeSession(session);
      expect(slim.channels.keys, unorderedEquals(['longacc-calc', 'latacc-calc']));
      expect(
        dayGgEnvelope([_row('1', 0, 1000)], {'1': slim}).sessions.single.valueG(GgDirection.left),
        envelope.valueG(GgDirection.left),
      );
    });

    test('the best per direction and what the latest session leaves unused', () {
      const peak = 1.2;
      // The 95th percentile of a direction ramping 0.2 → p.
      double p95(double p) => 0.2 + (p - 0.2) * 94 / 99;
      final day = dayGgEnvelope(
        [
          // Recorded last, imported first.
          _row('c', 0, 1000, clock: 3000),
          _row('a', 0, 1000, clock: 1000),
          _row('b', 0, 1000, clock: 2000),
        ],
        {
          'a': _gSession(_allDirections(1.0, {GgDirection.braking: 1.4})),
          'b': _gSession(_allDirections(peak, {GgDirection.left: 1.1})),
          'c': _gSession(
            _allDirections(peak, {
              // 0.2 g short of session a's braking.
              GgDirection.braking: 1.2,
              // 0.1 g short of session b: unused.
              GgDirection.right: peak - 0.1 * 99 / 94,
              // Within the margin.
              GgDirection.accelerating: 1.15,
              // Better than the rest.
              GgDirection.left: 1.3,
            }),
          ),
        },
      );
      expect([for (final session in day.sessions) session.runId], ['a', 'b', 'c']);
      expect(day.latestRunId, 'c');
      expect(day.latest?.runName, 'Session c');
      final braking = day.best[GgDirection.braking.index]!;
      expect(braking.runId, 'a');
      expect(braking.valueG, closeTo(p95(1.4), 1e-6));
      expect(day.best[GgDirection.left.index]!.runId, 'c');
      expect(day.best[GgDirection.accelerating.index]!.runId, 'b');
      expect(day.unused.map((direction) => direction.direction), [
        GgDirection.braking,
        GgDirection.right,
      ]);
      expect(day.unused.first.shortfallG, closeTo(p95(1.4) - p95(1.2), 1e-6));
      expect(day.unused.first.best.runName, 'Session a');
      expect(day.unused.last.shortfallG, closeTo(0.1, 1e-3));
    });

    test('no unused envelope without an envelope for the latest session', () {
      final day = dayGgEnvelope(
        [_row('a', 0, 1000, clock: 1000), _row('b', 0, 1000, clock: 2000)],
        {'a': _gSession(_allDirections(1.2)), 'b': null},
      );
      expect(day.latestRunId, 'b');
      expect(day.latest?.valid, isFalse);
      expect(day.unused, isEmpty);
      expect(day.best, everyElement(isNotNull));
    });

    test('says when it was cancelled', () {
      final day = dayGgEnvelope(
        [_row('1', 0, 1000)],
        {'1': _gSession(_allDirections(1))},
        cancelled: () => true,
      );
      expect(day.error, isNotEmpty);
      expect(day.sessions, isEmpty);
    });
  });

  group('on a day', () {
    DayRunInput run(String id, TelemetrySession session) => DayRunInput(
      runId: id,
      name: 'Session ${id.substring(id.length - 1)}',
      contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
      session: session,
      laps: deriveSourceLapSession(session),
    );
    double Function(double) constant(double speed) =>
        (distance) => speed;

    test('uses the eligible laps of the shown group, without excluded ones', () {
      final runs = [
        run(
          'run1',
          rectangleSession(
            [constant(16), constant(17), constant(16)],
            firstTimestampMilliseconds: 1000,
            pedals: true,
            lateral: true,
          ),
        ),
        run(
          'run2',
          rectangleSession(
            [constant(18), constant(19), constant(18)],
            firstTimestampMilliseconds: 4000000,
            pedals: true,
            lateral: true,
          ),
        ),
      ];
      final first = analyzeDay(runs);
      final excluded = dayEligibleLaps(first).firstWhere((row) => row.runId == 'run2');
      final analysis = analyzeDay(runs, exclusions: {excluded.reference: 'Traffic'});
      final eligible = dayEligibleLaps(analysis);
      final day = dayGgEnvelope(eligible, {for (final run in runs) run.runId: run.session});
      expect([for (final session in day.sessions) session.runId], ['run1', 'run2']);
      expect(day.sessions[0].lapCount, eligible.where((row) => row.runId == 'run1').length);
      expect(day.sessions[1].lapCount, eligible.where((row) => row.runId == 'run2').length);
      expect(eligible.contains(excluded), isFalse);
      expect(
        analysis.rows.where((row) => row.runId == 'run2' && row.type == LapSectionType.lap).length,
        day.sessions[1].lapCount + 1,
      );
      // Constant speed round 30 m corners: v² / r to both sides.
      for (final (index, speed) in [(0, 17.0), (1, 19.0)]) {
        final envelope = day.sessions[index];
        expect(envelope.valid, isTrue);
        final left = envelope.valueG(GgDirection.left) ?? envelope.valueG(GgDirection.right)!;
        expect(left, lessThanOrEqualTo(speed * speed / 30 / standardGravity + 1e-3));
        expect(left, greaterThan(0.8));
      }
      // The latest session cornered harder in the day's turning direction.
      expect(day.latestRunId, 'run2');
      expect(day.unused, isEmpty);
    });
  });
}
