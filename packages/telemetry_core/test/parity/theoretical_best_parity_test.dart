// Compares the Dart sector timing, theoretical best, time loss and
// consistency port (analysis/sector_timing.dart, theoretical_best.dart,
// time_loss.dart, consistency.dart and outing_theoretical_best.dart) with
// FlappedEar Overlays' C++ implementation over the synthetic parity corpus
// and fixed cases.
//
// test/parity/theoretical_best_reference.json is the output of
// tool/cpp_theoretical_best_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Counts, ids, names, reasons and
// orders must match exactly; doubles to 1e-9 relative (1e-9 absolute near
// zero), as in the other parity tests.
//
// FET_TB_REFERENCE and FET_TB_DIRS (colon-separated) run the same checks
// against another reference and its recordings, for local runs only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// Must match tool/cpp_theoretical_best_dump/main.cpp.
const _outlineStride = 50;

var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_TB_REFERENCE'] ?? 'test/parity/theoretical_best_reference.json';
  final directories = (Platform.environment['FET_TB_DIRS'] ?? 'test/parity/corpus:test/fixtures')
      .split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;
  final configuration = cases['configuration'] as String;

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('largest difference: $_maximumDifference');
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  test(
    'the reference covers files with laps of every kind',
    skip: Platform.environment.containsKey('FET_TB_REFERENCE') ? 'another reference' : false,
    () {
      expect(files.length, greaterThanOrEqualTo(8));
      expect(
        files.expand((file) => file['variants'] as List).length,
        greaterThanOrEqualTo(3 * files.length - 2),
      );
    },
  );

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final session = parseVboFile(pathOf(name));
      final laps = deriveSourceLapSession(session);
      final runs = {'run-a': OutingRun(session, laps), 'run-b': OutingRun(session, laps)};
      final byNumber = {for (final lap in laps.timedLaps) lap.number: lap};
      final population = [
        for (final row in (entry['population'] as List).cast<Map<String, Object?>>())
          () {
            final lap = byNumber[row['lapNumber']]!;
            return OutingLap(
              runId: row['runId'] as String,
              lapNumber: lap.number,
              start: lap.startTelemetryTime,
              end: lap.endTelemetryTime,
              reference: '${row['runId']}#${lap.number}',
            );
          }(),
      ];
      for (final variant in (entry['variants'] as List).cast<Map<String, Object?>>()) {
        final segments = variant['segments'] as Map<String, Object?>;
        _expectDay(
          population,
          runs,
          segments,
          entry['actualBest'] as String,
          configuration,
          variant,
          '$name ${variant['name']}',
        );
      }
    });
  }

  test('sector times of hand-made projections', () {
    for (final item in (cases['sectorTimes'] as List).cast<Map<String, Object?>>()) {
      final approved = approvedSegmentation(item['stored'], configuration);
      final trace = _trace(item['trace']);
      final start = _double(item['start']);
      final index = (cases['sectorTimes'] as List).indexOf(item);
      final times = computeLapSectorTimes(
        approved,
        _double(item['lengthMeters']),
        trace,
        start,
        _double(item['end']),
        'case#$index',
      );
      _expectSectorTimes(times, item['result'], 'case $index');
      _close(
        projectedCoverageMeters(trace, 250.0, 520.0, _double(item['lengthMeters'])),
        item['coverage'],
        absolute: 1e-9,
      );
    }
  });

  test('theoretical best and time loss of a hand-made population', () {
    final item = cases['population'] as Map<String, Object?>;
    final approved = approvedSegmentation(item['stored'], configuration);
    final other = approvedSegmentation(item['otherStored'], configuration);
    final timed = <TimedLapSectors>[];
    final inputs = (item['laps'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < inputs.length; ++i) {
      final start = _double(inputs[i]['start']);
      timed.add(
        TimedLapSectors(
          computeLapSectorTimes(
            inputs[i]['other'] == true ? other : approved,
            1000,
            _trace(inputs[i]['trace']),
            start,
            _double(inputs[i]['end']),
            '${i.isOdd ? 'b' : 'a'}#$i',
          ),
          start,
        ),
      );
    }
    final population = [for (final lap in timed) lap.times];
    _expectBest(computeTheoreticalBest(approved, population), item['best']);
    _expectBest(
      computeTheoreticalBest(approvedSegmentation(<Object?>[], configuration), population),
      item['bestNone'],
    );
    final observations = (item['observations'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < timed.length; ++i) {
      _expectObservations(
        computeTimeLossObservations(
          approved,
          1000,
          timed[i].times,
          timed[i].startTime,
          timed[0].times,
          timed[0].startTime,
        ),
        observations[i],
      );
    }
    final ranking = rankTimeLosses(approved, 1000, timed, timed[0], maximumResults: 3);
    final want = item['ranking'] as Map<String, Object?>;
    expect(ranking.valid, want['valid']);
    expect(ranking.observationCount, want['observationCount']);
    expect(ranking.comparedLapCount, want['comparedLapCount']);
    expect(ranking.untimedWindowCount, want['untimedWindowCount']);
    final losses = (want['losses'] as List).cast<Map<String, Object?>>();
    expect(ranking.losses.length, losses.length);
    for (var i = 0; i < losses.length; ++i) {
      expect(ranking.losses[i].lapReference, losses[i]['lap']);
      expect(ranking.losses[i].window.segmentId, losses[i]['segmentId']);
      _close(ranking.losses[i].lossSeconds, losses[i]['loss'], absolute: 1e-9);
      _close(ranking.losses[i].coverageLap, losses[i]['coverageLap'], absolute: 1e-9);
      _close(ranking.losses[i].coverageReference, losses[i]['coverageReference'], absolute: 1e-9);
    }
  });
}

String _label(Object? reference) {
  final parts = (reference as String).split('#');
  return '${parts[0]} · LAP ${parts[1]}';
}

void _expectDay(
  List<OutingLap> population,
  Map<String, OutingRun> runs,
  Map<String, Object?> segments,
  String actualBest,
  String configuration,
  Map<String, Object?> want,
  String what,
) {
  final canonical = canonicalSegmentation(
    population.map((lap) => lap.runId),
    (runId) => segments[runId],
    configuration,
  );
  expect(canonical?.runId ?? '', want['canonicalRunId'], reason: what);
  if (canonical == null) return;
  expect(canonical.approved.revision, want['revision'], reason: what);
  final computed = calculateOutingTheoreticalBest(
    population,
    runs,
    canonical.approved,
    canonical.runId,
    actualBest,
  );
  expect(computed.error, want['error'], reason: what);
  if (computed.error.isNotEmpty) return;
  final axis = want['axis'] as Map<String, Object?>;
  expect(computed.axis.points.length, axis['pointCount'], reason: what);
  _close(computed.axisLengthMeters, axis['lengthMeters']);

  final laps = (want['laps'] as List).cast<Map<String, Object?>>();
  expect(computed.population.length, laps.length, reason: what);
  for (var i = 0; i < laps.length; ++i) {
    _expectSectorTimes(computed.population[i].times, laps[i], '$what lap $i');
  }
  _expectBest(computed.best, want['best']);
  expect(computed.actualBest?.lapReference, want['actualBest'], reason: what);
  _expectPublished(publishTheoreticalBest(computed), want['published'], what);
  _expectRanking(rankOutingTimeLosses(computed), want['timeLossRunBests'], computed, what);
  _expectRanking(
    rankOutingTimeLosses(computed, allLaps: true),
    want['timeLossAllLaps'],
    computed,
    what,
  );
  if (want['observations'] case final Map<String, Object?> observations) {
    final first = computed.population.first;
    var start = 0.0;
    for (final lap in computed.population) {
      if (lap.times.lapReference == actualBest) start = lap.startTime;
    }
    _expectObservations(
      computeTimeLossObservations(
        computed.approved,
        computed.axisLengthMeters,
        first.times,
        first.startTime,
        computed.actualBest!,
        start,
      ),
      observations,
    );
  }
  if (want['comparisons'] case final List<Object?> comparisons) {
    final a = computed.population[0].times, b = computed.population[1].times;
    for (final value in comparisons.cast<Map<String, Object?>>()) {
      final comparison = compareSectorTimes(a, b, value['segmentId'] as String);
      expect(comparison.valid, value['valid'], reason: what);
      _closeOrNull(comparison.secondsDelta, value['delta']);
      expect(comparison.unavailableReason, value['reason'], reason: what);
    }
  }
}

void _expectSectorTimes(LapSectorTimes times, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(times.lapReference, want['lap'], reason: what);
  expect(times.valid, want['valid'], reason: what);
  expect(times.stamp.revision, want['revision'], reason: what);
  expect(times.stamp.calculationAlgorithm, want['algorithm'], reason: what);
  expect(times.completePartition, want['completePartition'], reason: what);
  _close(times.lapSeconds, want['lapSeconds'], absolute: 1e-9);
  _closeOrNull(times.sumSeconds, want['sumSeconds']);
  _closeOrNull(times.partitionErrorSeconds, want['partitionErrorSeconds']);
  final sectors = (want['sectors'] as List).cast<Map<String, Object?>>();
  expect(times.sectors.length, sectors.length, reason: what);
  for (var i = 0; i < sectors.length; ++i) {
    final sector = times.sectors[i], other = sectors[i];
    expect(
      [sector.segmentId, sector.name, sector.type, sector.unavailableReason],
      [other['segmentId'], other['name'], other['type'], other['reason']],
      reason: what,
    );
    _close(sector.startProgressMeters, other['start'], absolute: 1e-9);
    _close(sector.endProgressMeters, other['end'], absolute: 1e-9);
    _close(sector.lengthMeters, other['lengthMeters'], absolute: 1e-9);
    _close(sector.coveredMeters, other['coveredMeters'], absolute: 1e-9);
    _closeOrNull(sector.startTime, other['startTime']);
    _closeOrNull(sector.endTime, other['endTime']);
    _closeOrNull(sector.seconds, other['seconds']);
  }
}

void _expectBest(TheoreticalBestLap best, Object? expected) {
  final want = expected as Map<String, Object?>;
  expect(best.valid, want['valid']);
  expect(best.stamp.revision, want['revision']);
  expect(best.stamp.calculationAlgorithm, want['algorithm']);
  expect(best.unavailableReason, want['reason']);
  _closeOrNull(best.totalSeconds, want['totalSeconds']);
  final sectors = (want['sectors'] as List).cast<Map<String, Object?>>();
  expect(best.sectors.length, sectors.length);
  for (var i = 0; i < sectors.length; ++i) {
    expect(best.sectors[i].segmentId, sectors[i]['segmentId']);
    expect(best.sectors[i].sourceLapReference ?? '', sectors[i]['source']);
    expect(best.sectors[i].unavailableReason, sectors[i]['reason']);
    _closeOrNull(best.sectors[i].seconds, sectors[i]['seconds']);
  }
}

void _expectSummary(ConsistencySummary summary, Object? expected) {
  final want = expected as Map<String, Object?>;
  expect(summary.count, want['count']);
  expect(summary.available, want['available']);
  if (!summary.available) {
    expect(summary.unavailableReason, want['unavailableReason']);
    return;
  }
  _closeOrNull(summary.minimum, want['minimum']);
  _closeOrNull(summary.q1, want['q1']);
  _closeOrNull(summary.median, want['median']);
  _closeOrNull(summary.q3, want['q3']);
  _closeOrNull(summary.maximum, want['maximum']);
  _closeOrNull(summary.interquartileRange, want['interquartileRange']);
}

void _expectRow(TheoreticalBestRow row, Map<String, Object?> want, String what) {
  expect([row.segmentId, row.name, row.type], [want['segmentId'], want['name'], want['type']]);
  _closeOrNull(row.seconds, want['seconds']);
  if (row.seconds != null) {
    expect(_label(row.sourceLapReference), want['sourceLapLabel'], reason: what);
  } else {
    expect(row.unavailableReason, want['unavailableReason'], reason: what);
  }
  _closeOrNull(row.actualSeconds, want['actualSeconds']);
  _closeOrNull(row.lossSeconds, want['lossSeconds']);
  _expectSummary(row.consistency, want['consistency']);
}

void _expectPoint(MapPoint point, Object? expected) {
  final want = expected as Map<String, Object?>;
  _close(point.x, want['x'], absolute: 1e-9);
  _close(point.y, want['y'], absolute: 1e-9);
}

void _expectPublished(TheoreticalBestSummary summary, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  _closeOrNull(summary.totalSeconds, want['totalSeconds']);
  _closeOrNull(summary.differenceSeconds, want['differenceSeconds']);
  expect(summary.revision, want['revision']);
  expect(summary.trackConfigurationReference, want['trackConfigurationReference']);
  final actual = want['actualBest'] as Map<String, Object?>?;
  expect(summary.actualBest == null, actual == null, reason: what);
  if (actual != null) {
    final best = summary.actualBest!;
    expect(_label(best.reference), actual['label']);
    _close(best.lapSeconds, actual['lapSeconds'], absolute: 1e-9);
    expect(best.coversWholeLap, actual['coversWholeLap']);
    _closeOrNull(best.sectorSumSeconds, actual['sectorSumSeconds']);
  }
  final sectors = (want['sectors'] as List).cast<Map<String, Object?>>();
  final gains = (want['gains'] as List).cast<Map<String, Object?>>();
  expect(summary.sectors.length, sectors.length, reason: what);
  expect(summary.gains.map((row) => row.segmentId).toList(), [
    for (final gain in gains) gain['segmentId'],
  ], reason: what);
  for (var i = 0; i < sectors.length; ++i) {
    _expectRow(summary.sectors[i], sectors[i], what);
    _expectRow(summary.gains[i], gains[i], what);
  }
  final map = want['map'] as Map<String, Object?>;
  expect(summary.outline.length, map['outlineSize'], reason: what);
  final outline = (map['outline'] as List).cast<Map<String, Object?>>();
  for (var i = 0, j = 0; i < summary.outline.length; i += _outlineStride, ++j) {
    _expectPoint(summary.outline[i], outline[j]);
  }
  final segments = (map['segments'] as List).cast<Map<String, Object?>>();
  for (var i = 0; i < segments.length; ++i) {
    expect(summary.sectors[i].segmentId, segments[i]['segmentId']);
    final parts = (segments[i]['parts'] as List).cast<Map<String, Object?>>();
    expect(summary.sectors[i].parts.length, parts.length, reason: what);
    for (var p = 0; p < parts.length; ++p) {
      final part = summary.sectors[i].parts[p];
      expect(part.length, parts[p]['size'], reason: what);
      if (part.isNotEmpty) {
        _expectPoint(part.first, parts[p]['first']);
        _expectPoint(part.last, parts[p]['last']);
      }
    }
  }
}

void _expectRanking(
  TimeLossRanking ranking,
  Object? expected,
  OutingTheoreticalBest computed,
  String what,
) {
  final want = expected as Map<String, Object?>;
  if (want['state'] != 'ready') {
    expect(ranking.valid, isFalse, reason: what);
    return;
  }
  expect(ranking.valid, isTrue, reason: what);
  expect(_label(ranking.referenceLap), want['referenceLabel']);
  expect(ranking.observationCount, want['observationCount'], reason: what);
  expect(ranking.comparedLapCount, want['comparedLapCount'], reason: what);
  expect(ranking.untimedWindowCount, want['untimedWindowCount'], reason: what);
  expect(ranking.stamp.revision, want['revision']);
  final losses = (want['losses'] as List).cast<Map<String, Object?>>();
  expect(ranking.losses.length, losses.length, reason: what);
  for (var i = 0; i < losses.length; ++i) {
    final loss = ranking.losses[i], other = losses[i];
    final window = loss.window;
    expect(
      [_label(loss.lapReference), window.segmentId, window.name, window.type, window.role],
      [other['lapLabel'], other['segmentId'], other['name'], other['type'], other['role']],
      reason: what,
    );
    expect(
      window.cornerSegmentId.isEmpty ? null : window.cornerSegmentId,
      other['cornerSegmentId'],
    );
    _close(loss.lossSeconds, other['lossSeconds'], absolute: 1e-9);
    _close(window.startProgressMeters, other['startMeters'], absolute: 1e-9);
    _close(window.endProgressMeters, other['endMeters'], absolute: 1e-9);
    _close(loss.coverageLap, other['coverageLap'], absolute: 1e-9);
    _close(loss.coverageReference, other['coverageReference'], absolute: 1e-9);
    _closeOrNull(window.cumulativeAtStartSeconds, other['cumulativeAtStartSeconds']);
    _closeOrNull(window.cumulativeAtEndSeconds, other['cumulativeAtEndSeconds']);
  }
}

void _expectObservations(TimeLossObservations observations, Object? expected) {
  final want = expected as Map<String, Object?>;
  expect(observations.valid, want['valid']);
  expect(observations.unavailableReason, want['reason']);
  expect(observations.allWindowsTimed, want['allWindowsTimed']);
  _close(observations.timedIncrementSumSeconds, want['timedIncrementSumSeconds'], absolute: 1e-9);
  final windows = (want['windows'] as List).cast<Map<String, Object?>>();
  expect(observations.windows.length, windows.length);
  for (var i = 0; i < windows.length; ++i) {
    final window = observations.windows[i], other = windows[i];
    expect(
      [window.segmentId, window.role, window.cornerSegmentId, window.unavailableReason],
      [other['segmentId'], other['role'], other['cornerSegmentId'], other['reason']],
    );
    _closeOrNull(window.incrementSeconds, other['increment']);
    _closeOrNull(window.cumulativeAtStartSeconds, other['atStart']);
    _closeOrNull(window.cumulativeAtEndSeconds, other['atEnd']);
  }
}

List<ProgressSegment> _trace(Object? value) => [
  for (final segment in (value as List).cast<List<Object?>>())
    ProgressSegment([
      for (final sample in segment.cast<List<Object?>>())
        ProjectedSample(_double(sample[0]), progressMeters: _double(sample[1]), valid: true),
    ]),
];

double _double(Object? value) => (value as num).toDouble();

void _closeOrNull(double? actual, Object? expected) {
  if (expected == null) {
    expect(actual, isNull);
    return;
  }
  expect(actual, isNotNull);
  _close(actual!, expected, absolute: 1e-9);
}

void _close(double actual, Object? expected, {double absolute = 0.0}) {
  final value = _double(expected);
  final difference = (actual - value).abs();
  if (difference > _maximumDifference) _maximumDifference = difference;
  final tolerance = max(absolute, 1e-9 * value.abs());
  if (tolerance == 0.0) {
    expect(actual, value);
  } else {
    expect(actual, closeTo(value, tolerance));
  }
}
