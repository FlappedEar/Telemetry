// Cross-format speed unit invariants (Arek's second audit, finding 1): the
// same physical driving recorded as a VBO in km/h, a VBO in mph, an RCZ in
// km/h or a VBO with no unit (and one assumed) gives the same analysis once
// its speeds carry their effective unit, and speeds in different units are
// never subtracted.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';
const _mph = 1.609344;

// A lap at 30 m/s, slowing to [slow] m/s at 70 m, in the first corner.
double Function(double) _lap(double slow) =>
    (d) => d >= 20 && d <= 120 ? slow + (30 - slow) * (d - 70).abs() / 50 : 30.0;

/// How a recording writes its speed.
enum _Format {
  /// VBO: no channel unit, `velocity kmh` on a `[header]` line.
  vboKmh,

  /// VBO: no channel unit, `velocity mph` on a `[header]` line.
  vboMph,

  /// RCZ: the channel's own unit, km/h.
  rczKmh,

  /// VBO with no unit anywhere, samples in km/h.
  unlabelledKmh,

  /// VBO with no unit anywhere, samples in mph.
  unlabelledMph,
}

/// [session] (speeds in km/h, no unit) as [format] records the same driving.
TelemetrySession _as(TelemetrySession session, _Format format) {
  final speed = session.channels['velocity']!;
  final inMph = format == _Format.vboMph || format == _Format.unlabelledMph;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: {
      ...session.metadata,
      if (format == _Format.vboKmh) 'header.0': 'velocity kmh',
      if (format == _Format.vboMph) 'header.0': 'velocity mph',
    },
    channels: {
      ...session.channels,
      'velocity': TelemetryChannel(
        name: 'velocity',
        unit: format == _Format.rczKmh ? 'km/h' : '',
        timestamps: speed.timestamps,
        values: inMph
            ? Float32List.fromList([for (final v in speed.values) v / _mph])
            : speed.values,
      ),
    },
    aliases: session.aliases,
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

DayRunInput _run(String id, TelemetrySession session) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
);

/// The coach of a day of two sessions recorded as [earlier] and [latest],
/// analysed with [assumed] for unlabelled speeds, as the app runs it.
DayCoach _coach(_Format earlier, _Format latest, {String assumed = ''}) {
  final (result, sessions) = _theoreticalBest(earlier, latest, assumed: assumed);
  return dayCoach(result, sessions, runId: 'run2');
}

/// The theoretical best of that day, and its sessions by run.
(DayTheoreticalBest, Map<String, TelemetrySession>) _theoreticalBest(
  _Format earlier,
  _Format latest, {
  String assumed = '',
}) {
  final runs = [
    _run(
      'run1',
      withEffectiveSpeedUnits(
        _as(
          rectangleSession([_lap(20), _lap(20.5)], firstTimestampMilliseconds: 1000, pedals: true),
          earlier,
        ),
        assumed: assumed,
      ),
    ),
    _run(
      'run2',
      withEffectiveSpeedUnits(
        _as(
          rectangleSession(
            [_lap(15), _lap(15.2), _lap(15.1)],
            firstTimestampMilliseconds: 4000000,
            pedals: true,
          ),
          latest,
        ),
        assumed: assumed,
      ),
    ),
  ];
  final analysis = analyzeDay(runs);
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final result = dayTheoreticalBest(analysis, outing, random: Random(1));
  expect(result.state, DayTheoreticalBestState.ready);
  return (result, {for (final run in runs) run.runId: run.session});
}

/// What the coach concluded, with its speeds in km/h, rounded.
List<Object> _findings(DayCoach coach) => [
  for (final finding in coach.findings)
    [
      finding.kind,
      finding.confidence.toStringAsFixed(2),
      for (final lap in finding.affectedLaps) lap.reference,
      for (final evidence in finding.evidence)
        if (evidence.unit == 'mph')
          '${evidence.metric} ${(evidence.observed * _mph).toStringAsFixed(1)} '
              '${(evidence.reference * _mph).toStringAsFixed(1)} km/h'
        else
          '${evidence.metric} ${evidence.observed.toStringAsFixed(1)} '
              '${evidence.reference.toStringAsFixed(1)} ${evidence.unit}',
    ],
];

/// The unit the coach reports speeds in.
Set<String> _speedUnits(DayCoach coach) => {
  for (final finding in coach.findings)
    for (final evidence in finding.evidence)
      if (evidence.unit == 'km/h' || evidence.unit == 'mph') evidence.unit,
};

void main() {
  group('effective speed units', () {
    final base = rectangleSession([_lap(20)]);

    test('a VBO header declares the unit; the recording stays as parsed', () {
      for (final (format, unit) in [(_Format.vboKmh, 'km/h'), (_Format.vboMph, 'mph')]) {
        final recorded = _as(base, format);
        final analysed = withEffectiveSpeedUnits(recorded, assumed: 'mph');
        expect(analysed.channel('speed')!.unit, unit, reason: '$format');
        // The parsed recording, which its fingerprint is taken from, is not
        // changed, and the samples are shared, not converted.
        expect(recorded.channel('speed')!.unit, '');
        expect(
          identical(analysed.channel('speed')!.values, recorded.channel('speed')!.values),
          isTrue,
        );
      }
    });

    test('an RCZ unit is kept and the setting never overrides it', () {
      final recorded = _as(base, _Format.rczKmh);
      expect(identical(withEffectiveSpeedUnits(recorded, assumed: 'mph'), recorded), isTrue);
      expect(withEffectiveSpeedUnits(recorded, assumed: 'mph').channel('speed')!.unit, 'km/h');
    });

    test('an unlabelled speed takes the assumed unit, or none', () {
      final recorded = _as(base, _Format.unlabelledKmh);
      expect(withEffectiveSpeedUnits(recorded, assumed: 'km/h').channel('speed')!.unit, 'km/h');
      expect(withEffectiveSpeedUnits(recorded, assumed: 'mph').channel('speed')!.unit, 'mph');
      expect(identical(withEffectiveSpeedUnits(recorded), recorded), isTrue);
    });

    test('a unit the app does not name is kept as written, never assumed over', () {
      final recorded = _as(base, _Format.unlabelledKmh);
      final inMetres = TelemetrySession(
        duration: recorded.duration,
        startTime: recorded.startTime,
        metadata: recorded.metadata,
        channels: {
          ...recorded.channels,
          'velocity': TelemetryChannel(
            name: 'velocity',
            unit: 'm/s',
            timestamps: recorded.channels['velocity']!.timestamps,
            values: recorded.channels['velocity']!.values,
          ),
        },
        aliases: recorded.aliases,
        warnings: recorded.warnings,
        timingGates: recorded.timingGates,
        sampleCount: recorded.sampleCount,
      );
      expect(declaredSpeedUnit(inMetres, 'velocity'), 'm/s');
      expect(withEffectiveSpeedUnits(inMetres, assumed: 'km/h').channel('speed')!.unit, 'm/s');
      expect(sameSpeedUnit('m/s', 'km/h'), isFalse);
    });

    test('only speeds are given a unit', () {
      final recorded = _as(rectangleSession([_lap(20)], pedals: true), _Format.unlabelledKmh);
      final analysed = withEffectiveSpeedUnits(recorded, assumed: 'mph');
      for (final name in ['throttle', 'brake', 'longacc', 'latitude']) {
        expect(identical(analysed.channels[name], recorded.channels[name]), isTrue, reason: name);
      }
    });

    test('speeds are subtracted only in one unit', () {
      expect(sameSpeedUnit('km/h', 'kmh'), isTrue);
      expect(sameSpeedUnit('', ''), isTrue);
      expect(sameSpeedUnit('mph', 'km/h'), isFalse);
      expect(sameSpeedUnit('', 'km/h'), isFalse);
      expect(speedInMetresPerSecond(36, 'km/h'), closeTo(10, 1e-12));
      expect(speedInMetresPerSecond(36, 'mph'), closeTo(16.09344, 1e-9));
      expect(speedInMetresPerSecond(36, 'furlongs'), isNull);
    });
  });

  group('the coach reads the same driving the same way', () {
    late final reference = _findings(_coach(_Format.vboKmh, _Format.vboKmh));

    test('the reference day has a speed finding', () {
      expect(reference, isNotEmpty);
      expect(reference.toString(), contains('Minimum speed'));
    });

    for (final (earlier, latest, assumed) in [
      (_Format.vboMph, _Format.vboMph, ''),
      (_Format.rczKmh, _Format.rczKmh, ''),
      (_Format.unlabelledKmh, _Format.unlabelledKmh, 'km/h'),
      (_Format.unlabelledMph, _Format.unlabelledMph, 'mph'),
      // Mixed recordings in one day.
      (_Format.vboMph, _Format.vboKmh, ''),
      (_Format.vboMph, _Format.rczKmh, ''),
      (_Format.rczKmh, _Format.unlabelledMph, 'mph'),
    ]) {
      test('$earlier then $latest${assumed.isEmpty ? '' : ', assuming $assumed'}', () {
        expect(_findings(_coach(earlier, latest, assumed: assumed)), reference);
      });
    }

    test('a declared unit is not compared with speeds that have none', () {
      // Nothing assumed: the unlabelled session could be in either unit.
      final coach = _coach(_Format.vboMph, _Format.unlabelledMph);
      expect(_speedUnits(coach), isEmpty);
      expect(coach.findings.where((f) => f.kind == CoachKind.lowMinimumSpeed), isEmpty);
    });

    test('a corner\'s speed spread is never pooled across units', () {
      bool spread(_Format earlier, _Format latest) => _theoreticalBest(
        earlier,
        latest,
      ).$1.segments.any((row) => row.variability?.minimumSpeed.available ?? false);
      expect(spread(_Format.vboKmh, _Format.rczKmh), isTrue);
      expect(spread(_Format.vboMph, _Format.rczKmh), isFalse);
    });

    test('speeds are reported in the day\'s own unit, km/h when it mixes units', () {
      expect(_speedUnits(_coach(_Format.vboKmh, _Format.vboKmh)), {'km/h'});
      expect(_speedUnits(_coach(_Format.vboMph, _Format.vboMph)), {'mph'});
      expect(_speedUnits(_coach(_Format.unlabelledMph, _Format.unlabelledMph, assumed: 'mph')), {
        'mph',
      });
      final mixed = _coach(_Format.vboMph, _Format.rczKmh);
      expect(_speedUnits(mixed), {'km/h'});
      expect(mixed.speedsConverted, isTrue);
      expect(_coach(_Format.vboMph, _Format.vboMph).speedsConverted, isFalse);
    });
  });

  group('Corner Analyzer', () {
    final runs = {
      for (final format in _Format.values)
        format: _run(
          'run${format.index + 1}',
          _as(rectangleSession([_lap(20), _lap(18)], pedals: true), format),
        ),
    };
    late final analysis = analyzeDay([runs[_Format.vboKmh]!]);
    late final best = analysis.chosenGroup!.ranking!.bestOfDay!;
    late final shared = approvedSegmentation(
      automaticTrackSegments(
        documentRuns: const [],
        groupId: analysis.chosenGroup!.id,
        storedSegments: null,
        session: runs[_Format.vboKmh]!.session,
        laps: runs[_Format.vboKmh]!.laps,
        lapNumber: best.lapNumber,
        startTime: best.start,
        endTime: best.end,
        random: Random(5),
      ),
      analysis.chosenGroup!.id,
    );

    // Lap 1 of [a] against lap 2 of [b], each analysed with [assumed].
    CornerAnalyzer analyzer(_Format a, _Format b, {String assumed = ''}) {
      ComparisonLap lap(_Format format, int number) {
        final run = runs[format]!;
        final timed = analyzeDay([run]).rows.firstWhere((row) => row.lapNumber == number);
        return ComparisonLap(
          session: withEffectiveSpeedUnits(run.session, assumed: assumed),
          laps: run.laps,
          start: timed.start,
          end: timed.end,
          lapNumber: number,
        );
      }

      return CornerAnalyzer.of(
        LapComparison(lap(a, 1), lap(b, 2)),
        ComparisonSegmentation(shared: shared),
      );
    }

    SegmentAnalysis corner(CornerAnalyzer analyzer) =>
        analyzer.analyze(analyzer.segments.firstWhere((segment) => segment.corner).id)!;

    test('one unit: speeds are subtracted', () {
      for (final (a, b, assumed) in [
        (_Format.vboKmh, _Format.rczKmh, ''),
        (_Format.vboMph, _Format.unlabelledMph, 'mph'),
      ]) {
        final metrics = corner(analyzer(a, b, assumed: assumed));
        expect(metrics.speeds.minimum.delta.value, isNotNull, reason: '$a $b');
        expect(metrics.corner!.entry.delta.value, isNotNull, reason: '$a $b');
      }
    });

    test('different units: speeds are never subtracted', () {
      for (final (a, b, assumed) in [
        (_Format.vboMph, _Format.vboKmh, ''),
        (_Format.vboMph, _Format.rczKmh, ''),
        (_Format.unlabelledMph, _Format.vboKmh, 'mph'),
        // A declared unit against a speed with none.
        (_Format.vboKmh, _Format.unlabelledKmh, ''),
      ]) {
        final metrics = corner(analyzer(a, b, assumed: assumed));
        for (final row in [metrics.speeds.entry, metrics.speeds.minimum, metrics.speeds.exit]) {
          expect(row.a.value, isNotNull, reason: '$a $b');
          expect(row.b.value, isNotNull, reason: '$a $b');
          expect(row.delta.value, isNull, reason: '$a $b');
          expect(row.delta.unavailableReason, cornerSpeedMixedProvenance, reason: '$a $b');
        }
        expect(metrics.corner!.entry.delta.value, isNull, reason: '$a $b');
        // No unit of one lap labels the other's speeds.
        expect(metrics.speeds.unit, '', reason: '$a $b');
        expect(metrics.corner!.unit, '', reason: '$a $b');
      }
    });
  });
}
