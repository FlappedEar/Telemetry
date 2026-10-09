// The Corner Analyzer of two laps of a day (analysis/corner_analyzer.dart,
// day/day_corner_analyzer.dart), after Overlays' TelemetryTests.cpp cases
// showsCornerAnalyzerSegmentMetricsForBothLaps, the heart rate of a
// comparison interval in calculatesOutingTheoreticalBestAcrossPopulation, and
// the segments a comparison opened from the theoretical best borrows.
import 'dart:math';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'a000000000000000000000000000000000000000000000000000000000000000';

// A lap at [straight] m/s, slowed to [slow] m/s over [from, to] metres.
double Function(double) _lap(double straight, [double from = 0, double to = 0, double slow = 0]) =>
    (d) => d >= from && d <= to ? slow : straight;

/// [session] with a heart rate channel at [level] bpm, or without its
/// [without] aliases.
TelemetrySession _with(TelemetrySession session, {double? level, Set<String> without = const {}}) {
  final times = session.channel('latitude')!.timestamps;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      ...session.channels,
      if (level != null)
        'heart_rate': TelemetryChannel(
          name: 'heart_rate',
          unit: 'bpm',
          timestamps: times,
          values: Float32List.fromList([for (final t in times) level + 2.0 * sin(t / 5.0)]),
        ),
    },
    aliases: {
      for (final MapEntry(:key, :value) in session.aliases.entries)
        if (!without.contains(key)) key: value,
      if (level != null) 'heartRate': 'heart_rate',
    },
    warnings: const [],
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

void main() {
  final runs = [
    _run(
      'run1',
      _with(
        rectangleSession([
          _lap(30, 50, 120, 20),
          _lap(31, 300, 400, 25),
          _lap(30, 550, 650, 22),
        ], pedals: true),
        level: 140,
      ),
    ),
    _run(
      'run2',
      _with(rectangleSession([_lap(29), _lap(30.5, 700, 780, 20)], pedals: true), level: 150),
    ),
  ];
  final outing = {for (final run in runs) run.runId: OutingRun(run.session, run.laps)};
  final analysis = analyzeDay(runs);
  final group = analysis.chosenGroup!;
  final rows = [
    for (final row in analysis.rows)
      if (group.ranking!.eligibleLaps.any((lap) => lap.reference == row.reference)) row,
  ];
  final best = group.ranking!.bestOfDay!;
  final segments = automaticTrackSegments(
    documentRuns: const [],
    groupId: group.id,
    storedSegments: null,
    session: outing[best.runId]!.session,
    laps: outing[best.runId]!.laps,
    lapNumber: best.lapNumber,
    startTime: best.start,
    endTime: best.end,
    random: Random(5),
  )!;
  // Approved on run1 only.
  final documentRuns = [
    {'id': 'run1', 'trackSegments': segments},
    {'id': 'run2'},
  ];

  LapComparison comparison(DayLapRow a, DayLapRow b) {
    ComparisonLap lap(DayLapRow row) => ComparisonLap(
      session: outing[row.runId]!.session,
      laps: outing[row.runId]!.laps,
      start: row.start,
      end: row.end,
      lapNumber: row.lapNumber,
    );
    return LapComparison(lap(a), lap(b));
  }

  final run1 = rows.where((row) => row.runId == 'run1').toList();
  final run2 = rows.where((row) => row.runId == 'run2').toList();

  test('stored segments no run uses are counted (FET-267)', () {
    expect(dayUnusedStoredSegments(analysis, documentRuns), 0);
    expect(dayUnusedStoredSegments(analysis, const []), 0);

    // Saved under a group the run no longer belongs to.
    final old = 'compatibility-v1:${'b' * 64}';
    final moved = [
      for (final segment in segments) {...segment, 'trackConfigurationReference': old},
    ];
    expect(
      dayUnusedStoredSegments(analysis, [
        {'id': 'run1', 'trackSegments': moved},
        {'id': 'run2'},
      ]),
      segments.length,
    );

    // Some under the current group, some not: only the others count.
    expect(
      dayUnusedStoredSegments(analysis, [
        {
          'id': 'run1',
          'trackSegments': [moved.first, ...segments.skip(1)],
        },
      ]),
      1,
    );

    // A run the day does not know, and stored segments that are not valid,
    // add nothing.
    expect(
      dayUnusedStoredSegments(analysis, [
        {'id': 'runX', 'trackSegments': moved},
        {'id': 'run2', 'trackSegments': 'not segments'},
      ]),
      0,
    );
  });

  test('two laps of one run share its approved segments', () {
    final segmentation = dayComparisonSegmentation(
      analysis,
      run1[0],
      run1[1],
      documentRuns: documentRuns,
    );
    expect(segmentation.shared, isNotNull);
    expect(segmentation.borrowed, isFalse);
    final analyzer = CornerAnalyzer.of(comparison(run1[0], run1[1]), segmentation);
    expect(analyzer.segments.map((segment) => segment.id), [
      for (final segment in segments) segment['id'],
    ]);

    // Every segment has a calculated sector time on both laps.
    for (final segment in analyzer.segments) {
      final metrics = analyzer.analyze(segment.id)!;
      expect(metrics.segmentId, segment.id);
      for (final side in [metrics.sectorTime!.a, metrics.sectorTime!.b]) {
        expect(side.value, greaterThan(0.0), reason: side.unavailableReason);
        expect(side.provenance, metricCalculated);
      }
      expect(metrics.sectorTime!.delta.value, isNotNull);
      expect(metrics.speeds.unit, isNotNull);
      // A segment across start/finish has no speeds within one lap.
      final wraps = segment.endMeters < segment.startMeters;
      expect(metrics.speeds.entry.a.provenance, wraps ? metricUnavailable : metricMeasured);
      if (wraps) expect(metrics.speeds.entry.a.unavailableReason, 'crossesGate');
    }

    // A corner: speeds, braking and pickup measured on both laps, the
    // geometric phases on the shared axis.
    final corner = analyzer.segments.firstWhere((segment) => segment.corner);
    final metrics = analyzer.analyze(corner.id)!;
    expect(metrics.phases!.valid, isTrue);
    expect(metrics.corner!.minimum.a.value, isNotNull);
    // Lap B holds one speed through this corner: no minimum, so no delta.
    expect(metrics.corner!.minimum.b.unavailableReason, cornerPhaseFlatSpeed);
    expect(metrics.corner!.minimum.delta.value, isNull);
    expect(
      metrics.corner!.entry.delta.value,
      closeTo(metrics.corner!.entry.a.value! - metrics.corner!.entry.b.value!, 1e-9),
    );
    // Lap A brakes for this corner and is back on the throttle only after
    // it; lap B neither brakes nor lifts. Each missing value says why.
    expect(metrics.braking!.point.a.provenance, metricMeasured);
    expect(metrics.braking!.point.a.value, isNotNull);
    expect(metrics.braking!.point.b.unavailableReason, brakingNoneDetected);
    expect(metrics.braking!.point.delta.value, isNull);
    expect(metrics.exitEffects!.pickup.a.unavailableReason, exitNoPickup);
    expect(metrics.exitEffects!.pickup.b.unavailableReason, exitNoLift);
    // A straight has no corner rows.
    final straight = analyzer.analyze(
      analyzer.segments.firstWhere((segment) => !segment.corner).id,
    )!;
    expect([
      straight.corner,
      straight.braking,
      straight.exitEffects,
      straight.phases,
    ], everyElement(isNull));

    // An unknown segment id is never fabricated into a result.
    expect(analyzer.analyze('not-a-real-id'), isNull);
    expect(analyzer.analyze(''), isNull);

    final losses = analyzer.timeLosses();
    expect(losses.valid, isTrue);
    expect(losses.observations!.windows, hasLength(segments.length));
  });

  test('missing channels are unavailable with their reason, never derived', () {
    final bare = _with(
      outing['run1']!.session,
      without: {'speed', 'brake', 'throttle', 'longitudinalAcceleration'},
    );
    final segmentation = dayComparisonSegmentation(
      analysis,
      run1[0],
      run1[1],
      documentRuns: documentRuns,
    );
    final lapComparison = comparison(run1[0], run1[1]);
    CornerAnalyzerLap lap(int slot) => CornerAnalyzerLap(
      session: bare,
      trace: lapComparison.trace(slot),
      start: lapComparison.lap(slot).start,
      end: lapComparison.lap(slot).end,
      reference: slot,
    );
    final analyzer = CornerAnalyzer(
      axis: lapComparison.axis,
      a: lap(0),
      b: lap(1),
      segmentation: segmentation,
    );
    final metrics = analyzer.analyze(analyzer.segments.firstWhere((segment) => segment.corner).id)!;
    expect(metrics.sectorTime!.a.value, isNotNull);
    for (final phase in [
      metrics.corner!.entry,
      metrics.corner!.apex,
      metrics.corner!.minimum,
      metrics.corner!.exit,
    ]) {
      for (final side in [phase.a, phase.b]) {
        expect(side.value, isNull);
        expect(side.unavailableReason, cornerPhaseSpeedChannelMissing);
        expect(side.provenance, metricUnavailable);
      }
    }
    expect(metrics.braking!.point.a.unavailableReason, brakingNoChannel);
    expect(metrics.exitEffects!.pickup.a.unavailableReason, exitNoChannel);
    expect(metrics.speeds.entry.a.value, isNull);
  });

  test(
    'laps of runs with different segments share none, unless opened from the theoretical best',
    () {
      final own = dayComparisonSegmentation(analysis, run1[0], run2[0], documentRuns: documentRuns);
      expect(own.shared, isNull);
      expect(CornerAnalyzer.of(comparison(run1[0], run2[0]), own).segments, isEmpty);

      final theoreticalBest = dayTheoreticalBest(analysis, outing, documentRuns: documentRuns);
      final borrowed = dayComparisonSegmentation(
        analysis,
        run1[0],
        run2[0],
        documentRuns: documentRuns,
        theoreticalBest: theoreticalBest,
      );
      expect(borrowed.shared!.revision, theoreticalBest.computed!.approved.revision);
      expect(borrowed.borrowed, isTrue);
      expect(
        CornerAnalyzer.of(comparison(run1[0], run2[0]), borrowed).segments,
        hasLength(segments.length),
      );

      // Both laps' own segments match: nothing is borrowed.
      final same = dayComparisonSegmentation(
        analysis,
        run1[0],
        run1[1],
        documentRuns: documentRuns,
        theoreticalBest: theoreticalBest,
      );
      expect(same.borrowed, isFalse);
    },
  );

  test('heart rate of an interval, also across start/finish', () {
    final theoreticalBest = dayTheoreticalBest(analysis, outing, documentRuns: documentRuns);
    final analyzer = CornerAnalyzer.of(
      comparison(run1[0], run2[0]),
      dayComparisonSegmentation(
        analysis,
        run1[0],
        run2[0],
        documentRuns: documentRuns,
        theoreticalBest: theoreticalBest,
      ),
    );
    final length = analyzer.axisLengthMeters;
    final pair = analyzer.heartRate(0.0, length / 2);
    expect(pair.valid, isTrue);
    expect(pair.laps, hasLength(2));
    expect(pair.laps[0].channel, 'heart_rate');
    expect(pair.laps[0].summary.mean, closeTo(140.0, 2.5));
    expect(pair.laps[1].summary.mean, closeTo(150.0, 2.5));
    expect(pair.laps[0].summary.coverage, greaterThan(0.9));
    expect(pair.crossesStartFinish, isFalse);

    final wrapped = analyzer.heartRate(length * 0.75, length * 0.25);
    expect(wrapped.crossesStartFinish, isTrue);
    expect(wrapped.laps[0].valid, isTrue);
    expect(wrapped.laps[0].summary.mean, closeTo(140.0, 2.5));
    expect(wrapped.laps[1].summary.mean, closeTo(150.0, 2.5));
    expect(wrapped.laps[0].summary.coverage, greaterThan(0.9));

    // Without a heart rate channel the reason is given.
    final none = CornerAnalyzer(
      axis: analyzer.axis,
      a: CornerAnalyzerLap(
        session: _with(outing['run1']!.session, without: {'heartRate'}),
        trace: analyzer.a.trace,
        start: analyzer.a.start,
        end: analyzer.a.end,
        reference: 0,
      ),
      b: analyzer.b,
      segmentation: analyzer.segmentation,
    ).heartRate(0.0, length / 2);
    expect(none.laps[0].valid, isFalse);
    expect(none.laps[0].summary.unavailableReason, isNotEmpty);
    expect(none.laps[1].valid, isTrue);
  });

  test('a theoretical-best sector opens its fastest lap against the best lap', () {
    final result = dayTheoreticalBest(analysis, outing, documentRuns: documentRuns);
    final bestRow = result.bestLap!;
    for (final sector in result.segments) {
      final (a, b) = dayTheoreticalBestSectorPair(result, sector.segmentId)!;
      if (sector.sourceLapReference != bestRow.reference) {
        expect(a.reference, sector.sourceLapReference);
        expect(b.reference, bestRow.reference);
      } else {
        // The best lap set this sector: compared with the next fastest.
        expect(a.reference, bestRow.reference);
        final next =
            [
              for (final lap in result.laps)
                if (lap.lap.reference != bestRow.reference) lap,
            ]..sort(
              (x, y) => x.times
                  .sector(sector.segmentId)!
                  .seconds!
                  .compareTo(y.times.sector(sector.segmentId)!.seconds!),
            );
        expect(b.reference, next.first.lap.reference);
      }
    }
    // From a lap's row: that lap against the best lap.
    final other = result.laps.firstWhere((lap) => !lap.bestOfDay).lap;
    final (a, b) = dayTheoreticalBestSectorPair(
      result,
      result.segments.first.segmentId,
      lap: other,
    )!;
    expect([a.reference, b.reference], [other.reference, bestRow.reference]);
    expect(dayTheoreticalBestSectorPair(result, 'not-a-real-id'), isNull);
  });
}
