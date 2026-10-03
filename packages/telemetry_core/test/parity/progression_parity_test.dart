// Compares the Dart progression, consistency and time-loss presentation port
// (day/day_progression.dart and analysis/outing_results.dart) with FlappedEar
// Overlays' C++ implementation over the synthetic parity corpus and fixed
// cases.
//
// test/parity/progression_reference.json is the output of
// tool/cpp_progression_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Counts, ids, names, states,
// reasons and orders must match exactly; doubles to 1e-9 relative (1e-9
// absolute near zero), as in the other parity tests.
//
// FET_PROGRESSION_REFERENCE and FET_PROGRESSION_DIRS (colon-separated) run
// the same checks against another reference and its recordings, for local
// runs only.
@TestOn('vm')
library;

import 'dart:io';
import 'dart:math';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

var _maximumDifference = 0.0;

void main() {
  final referencePath =
      Platform.environment['FET_PROGRESSION_REFERENCE'] ?? 'test/parity/progression_reference.json';
  final directories =
      (Platform.environment['FET_PROGRESSION_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(
        ':',
      );
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List).cast<Map<String, Object?>>();
  final day = reference['day'] as Map<String, Object?>;
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
    'the reference covers files, a day of every group state and cases',
    skip: Platform.environment.containsKey('FET_PROGRESSION_REFERENCE')
        ? 'another reference'
        : false,
    () {
      expect(files.length, greaterThanOrEqualTo(8));
      final groups = (day['groups'] as List).cast<Map<String, Object?>>();
      expect(groups.length, 3);
      final states = {
        for (final group in groups)
          for (final run
              in ((group['progression'] as Map)['runs'] as List).cast<Map<String, Object?>>())
            run['state'],
      };
      expect(states, {'available', 'no-eligible-laps', 'no-recorded-laps'});
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
      final best = entry['actualBest'] as Map<String, Object?>;
      final order = _runInfo(entry['progressionRuns']);
      for (final variant in (entry['variants'] as List).cast<Map<String, Object?>>()) {
        final what = '$name ${variant['name']}';
        final segments = variant['segments'] as Map<String, Object?>;
        final canonical = canonicalSegmentation(
          population.map((lap) => lap.runId),
          (runId) => segments[runId],
          configuration,
        );
        expect(canonical?.runId ?? '', variant['canonicalRunId'], reason: what);
        if (canonical == null) continue;
        final computed = calculateOutingTheoreticalBest(
          population,
          runs,
          canonical.approved,
          canonical.runId,
          '${best['runId']}#${best['lapNumber']}',
        );
        expect(computed.error, variant['error'], reason: what);
        if (computed.error.isNotEmpty) continue;
        _expectSectionProgression(
          publishSectorProgression(computed, order),
          variant['sectorProgression'],
          what,
        );
        _expectTimeLosses(publishTimeLossRanking(computed), variant['timeLossRunBests'], what);
        _expectTimeLosses(
          publishTimeLossRanking(computed, allLaps: true),
          variant['timeLossAllLaps'],
          what,
        );
      }
    });
  }

  test('ranking, progression and lap consistency of a day of every file', () {
    final choices = day['choices'] as Map<String, Object?>;
    final rows = <DayLapRow>[];
    final runFiles = (choices['files'] as List).cast<Map<String, Object?>>();
    for (var i = 0; i < runFiles.length; ++i) {
      final session = parseVboFile(pathOf(runFiles[i]['file'] as String));
      rows.addAll(
        dayLapRows(
          session,
          deriveSourceLapSession(session),
          runId: runFiles[i]['runId'] as String,
          runName: 'Session ${i + 1}',
          sourceRevision: i.toRadixString(16).padLeft(64, '0'),
          sourceOrder: i,
        ),
      );
    }
    final sorted = sortDayLaps(rows);
    _expectRows(sorted, day['rows']);
    final configurations = {
      for (final MapEntry(:key, :value)
          in (choices['configurations'] as Map<String, Object?>).entries)
        key: _configuration(value),
    };
    final excluded = choices['excluded'] as Map<String, Object?>;
    final exclusions = {
      for (final row in sorted)
        if (row.type == LapSectionType.lap &&
            row.runId == excluded['runId'] &&
            row.lapNumber == excluded['lapNumber'])
          row.reference: excluded['reason'] as String,
    };
    expect(exclusions, hasLength(1));
    final stale = {for (final id in choices['stale'] as List) id as String};
    final metadata = (choices['metadata'] as List).cast<Map<String, Object?>>();
    for (final run in metadata) {
      expect(
        configurations[run['id']]?.compatibilityGroupId ?? '',
        run['groupId'],
        reason: '${run['id']}',
      );
    }
    final infos = _runInfo(metadata);
    for (final group in (day['groups'] as List).cast<Map<String, Object?>>()) {
      final id = group['groupId'] as String;
      final what = id.isEmpty ? 'no group' : id;
      final ranking = rankDayLaps(
        sorted,
        id.isEmpty ? null : id,
        configurations,
        exclusions: exclusions,
        staleRunIds: stale,
      );
      _expectRanking(ranking, group['ranking'], what);
      _expectProgression(
        summarizeDayProgression(sorted, ranking, infos, configurations),
        group['progression'],
        what,
      );
      _expectLapConsistency(
        summarizeLapConsistency(
          eligibleDayLaps(
            sorted,
            id.isEmpty ? null : id,
            configurations,
            exclusions: exclusions,
            staleRunIds: stale,
          ),
        ),
        group['lapConsistency'],
        what,
      );
    }
  });

  test('consistency of fixed values', () {
    for (final item in (cases['consistency'] as List).cast<Map<String, Object?>>()) {
      final values = [
        for (final value in item['values'] as List)
          value == 'nan'
              ? double.nan
              : value == 'inf'
              ? double.infinity
              : _double(value),
      ];
      _expectSummary(
        summarizeConsistency(values, minimumSamples: item['minimumSamples'] as int),
        item['summary'],
        '$values',
      );
    }
  });

  test('section progression and time losses of hand-made laps', () {
    final item = cases['population'] as Map<String, Object?>;
    final approved = approvedSegmentation(item['stored'], configuration);
    final other = approvedSegmentation(item['otherStored'], configuration);
    final population = <TimedLapSectors>[];
    final runIds = <String>[];
    for (final lap in (item['laps'] as List).cast<Map<String, Object?>>()) {
      final start = _double(lap['start']);
      population.add(
        TimedLapSectors(
          computeLapSectorTimes(
            lap['other'] == true ? other : approved,
            1000,
            _trace(lap['trace']),
            start,
            _double(lap['end']),
            '${lap['runId']}#${lap['lapNumber']}',
          ),
          start,
        ),
      );
      runIds.add(lap['runId'] as String);
    }
    final actual = population.firstWhere(
      (lap) => _label(lap.times.lapReference) == item['actualBest'],
    );
    final computed = OutingTheoreticalBest(
      best: computeTheoreticalBest(approved, [for (final lap in population) lap.times]),
      actualBest: actual.times,
      canonicalRunId: 'a',
      population: population,
      approved: approved,
      axisLengthMeters: 1000,
      runIds: runIds,
    );
    final order = _runInfo(item['progressionRuns']);
    _expectSectionProgression(
      publishSectorProgression(computed, order),
      item['sectorProgression'],
      'cases',
    );
    _expectTimeLosses(publishTimeLossRanking(computed), item['timeLossRunBests'], 'cases');
    _expectTimeLosses(
      publishTimeLossRanking(computed, allLaps: true),
      item['timeLossAllLaps'],
      'cases',
    );
    // The losses' comparison: the two laps through the segment.
    final losses = publishTimeLossRanking(computed, allLaps: true).losses;
    expect(losses, isNotEmpty);
    for (final loss in losses) {
      final comparison = compareTimeLoss(computed, loss);
      expect(comparison.differenceSeconds, closeTo(loss.lossSeconds, 1e-9));
    }
  });
}

List<ProgressionRunInfo> _runInfo(Object? value) => [
  for (final run in (value as List).cast<Map<String, Object?>>())
    ProgressionRunInfo(
      id: (run['id'] ?? run['runId']) as String,
      name: (run['name'] ?? run['runName']) as String,
      notes: run['notes'] as String?,
      conditions: run['conditions'] as String?,
      setupChanges: run['setupChanges'] as String?,
    ),
];

TrackConfiguration _configuration(Object? value) {
  final map = value as Map<String, Object?>;
  return TrackConfiguration(
    layoutId: map['layoutId'] as String?,
    direction: switch (map['direction']) {
      'clockwise' => TrackDirection.clockwise,
      'counterclockwise' => TrackDirection.counterclockwise,
      _ => null,
    },
    gateRevision: map['gateRevision'] as String?,
  );
}

String _label(Object? reference) {
  final parts = (reference as String).split('#');
  return '${parts[0]} · LAP ${parts[1]}';
}

void _expectRows(List<DayLapRow> rows, Object? expected) {
  final want = (expected as List).cast<Map<String, Object?>>();
  expect(rows.length, want.length);
  for (var i = 0; i < want.length; ++i) {
    final row = rows[i], other = want[i];
    expect(
      [row.runId, row.type.label, row.lapNumber, row.timestampMilliseconds?.toString()],
      [other['runId'], other['type'], other['lapNumber'], other['timestamp']],
      reason: 'row $i',
    );
    _close(row.start, other['start'], absolute: 1e-9);
    _close(row.end, other['end'], absolute: 1e-9);
  }
}

String _state(DayRankingState state) => switch (state) {
  DayRankingState.selectionRequired => 'selection-required',
  DayRankingState.noEligibleLaps => 'no-eligible-laps',
  DayRankingState.available => 'available',
};

void _expectLap(DayLapRow? lap, Object? expected, String what) {
  if (expected == null) {
    expect(lap, isNull, reason: what);
    return;
  }
  final want = expected as Map<String, Object?>;
  expect(lap, isNotNull, reason: what);
  expect(
    [lap!.runId, lap.runName, lap.lapNumber],
    [want['runId'], want['runName'], want['lapNumber']],
    reason: what,
  );
  _close(lap.durationSeconds, want['durationSeconds'], absolute: 1e-9);
}

void _expectExcluded(List<ExcludedLap> laps, Object? expected, String what) {
  final want = (expected as List).cast<Map<String, Object?>>();
  expect(laps.length, want.length, reason: what);
  for (var i = 0; i < want.length; ++i) {
    _expectLap(laps[i].row, want[i], what);
    expect([for (final issue in laps[i].issues) issue.code], want[i]['reasons'], reason: what);
    expect([for (final issue in laps[i].issues) issue.label], want[i]['reasonLabels']);
    expect(laps[i].userReason, want[i]['userReason'], reason: what);
  }
}

void _expectDistribution(LapDistribution? distribution, Object? expected) {
  if (expected == null) {
    expect(distribution, isNull);
    return;
  }
  final want = expected as Map<String, Object?>;
  _close(distribution!.minimum, want['minimum'], absolute: 1e-9);
  _close(distribution.q1, want['q1'], absolute: 1e-9);
  _close(distribution.median, want['median'], absolute: 1e-9);
  _close(distribution.q3, want['q3'], absolute: 1e-9);
  _close(distribution.maximum, want['maximum'], absolute: 1e-9);
}

void _expectRanking(DayRanking ranking, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(_state(ranking.state), want['state'], reason: what);
  expect(ranking.groupId ?? '', want['groupId'], reason: what);
  expect(ranking.lapCount, want['lapCount'], reason: what);
  expect(ranking.eligibleLapCount, want['eligibleLapCount'], reason: what);
  expect(ranking.tieCount, want['tieCount'], reason: what);
  _expectLap(ranking.bestOfDay, want['bestOfDay'], what);
  _expectExcluded(ranking.excludedLaps, want['excludedLaps'], what);
  final runs = (want['runs'] as List).cast<Map<String, Object?>>();
  expect([for (final run in ranking.runs) run.runId], [for (final run in runs) run['runId']]);
  for (var i = 0; i < runs.length; ++i) {
    final run = ranking.runs[i], other = runs[i];
    expect(
      [run.runName, run.available ? 'available' : 'no-eligible-laps'],
      [other['runName'], other['state']],
      reason: what,
    );
    expect(
      [run.lapCount, run.eligibleLapCount, run.tieCount],
      [other['lapCount'], other['eligibleLapCount'], other['tieCount']],
      reason: '$what ${run.runId}',
    );
    _expectLap(run.bestLap, other['bestLap'], what);
    _expectDistribution(run.distribution, other['distribution']);
  }
}

String _runState(ProgressionRunState state) => switch (state) {
  ProgressionRunState.available => 'available',
  ProgressionRunState.noEligibleLaps => 'no-eligible-laps',
  ProgressionRunState.noRecordedLaps => 'no-recorded-laps',
};

void _expectProgression(DayProgression progression, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(_state(progression.state), want['state'], reason: what);
  expect(progression.groupId ?? '', want['groupId'], reason: what);
  expect(progression.lapCount, want['lapCount'], reason: what);
  expect(progression.eligibleLapCount, want['eligibleLapCount'], reason: what);
  _closeOrNull(progression.minimumSeconds, want['minimumSeconds']);
  _closeOrNull(progression.maximumSeconds, want['maximumSeconds']);
  final runs = (want['runs'] as List).cast<Map<String, Object?>>();
  expect(
    [for (final run in progression.runs) run.runId],
    [for (final run in runs) run['runId']],
    reason: what,
  );
  for (var i = 0; i < runs.length; ++i) {
    final run = progression.runs[i], other = runs[i];
    final where = '$what ${run.runId}';
    expect(
      [
        run.runName,
        _runState(run.state),
        run.lapCount,
        run.eligibleLapCount,
        run.run.notes,
        run.run.conditions,
        run.run.setupChanges,
        run.chronologyKnown,
        run.firstSectionUtcMilliseconds?.toString(),
        run.previousListedRunName,
      ],
      [
        other['runName'],
        other['state'],
        other['lapCount'],
        other['eligibleLapCount'],
        other['notes'],
        other['conditions'],
        other['setupChanges'],
        other['chronologyKnown'],
        other['firstSectionUtcMilliseconds'],
        other['previousListedRunName'],
      ],
      reason: where,
    );
    if (other.containsKey('tieCount')) expect(run.tieCount, other['tieCount'], reason: where);
    _expectLap(run.bestLap, other['bestLap'], where);
    _expectDistribution(run.distribution, other['distribution']);
    _expectExcluded(run.excludedLaps, other['excludedLaps'], where);
    _closeOrNull(run.bestDeltaPreviousListedSeconds, other['bestDeltaPreviousListedSeconds']);
  }
}

void _expectLapConsistency(LapConsistency consistency, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(want['algorithm'], consistencyAlgorithm);
  expect(want['minimumSamples'], minimumConsistencySamples);
  _expectSummary(consistency.day, want['day'], what);
  final runs = (want['runs'] as List).cast<Map<String, Object?>>();
  expect([for (final run in consistency.runs) run.runId], [for (final run in runs) run['runId']]);
  for (var i = 0; i < runs.length; ++i) {
    expect(consistency.runs[i].runName, runs[i]['runName']);
    _expectSummary(consistency.runs[i].laps, runs[i]['laps'], what);
  }
}

void _expectSummary(ConsistencySummary summary, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(summary.count, want['count'], reason: what);
  expect(summary.available, want['available'], reason: what);
  if (!summary.available) {
    expect(summary.unavailableReason, want['unavailableReason'], reason: what);
    expect(summary.median, isNull);
    expect(summary.interquartileRange, isNull);
    return;
  }
  _closeOrNull(summary.minimum, want['minimum']);
  _closeOrNull(summary.q1, want['q1']);
  _closeOrNull(summary.median, want['median']);
  _closeOrNull(summary.q3, want['q3']);
  _closeOrNull(summary.maximum, want['maximum']);
  _closeOrNull(summary.interquartileRange, want['interquartileRange']);
}

void _expectSectionProgression(SectionProgression progression, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  expect(want['state'], 'ready');
  expect(want['algorithm'], consistencyAlgorithm);
  expect(want['minimumSamples'], minimumConsistencySamples);
  final sessions = (want['sessions'] as List).cast<Map<String, Object?>>();
  expect(
    [for (final session in progression.sessions) session.runId],
    [for (final session in sessions) session['runId']],
    reason: what,
  );
  for (var i = 0; i < sessions.length; ++i) {
    final session = progression.sessions[i], other = sessions[i];
    expect(
      [session.run.name, session.run.notes, session.run.conditions, session.run.setupChanges],
      [other['runName'], other['notes'], other['conditions'], other['setupChanges']],
      reason: what,
    );
    _expectSummary(session.laps, other['laps'], what);
  }
  final segments = (want['segments'] as List).cast<Map<String, Object?>>();
  expect(
    [for (final row in progression.segments) row.segmentId],
    [for (final row in segments) row['segmentId']],
    reason: what,
  );
  for (var i = 0; i < segments.length; ++i) {
    final row = progression.segments[i], other = segments[i];
    expect([row.name, row.type], [other['name'], other['type']], reason: what);
    _closeOrNull(row.fastestTypical, other['fastestTypical']);
    final cells = (other['cells'] as List).cast<Map<String, Object?>>();
    expect(row.cells.length, cells.length, reason: what);
    for (var c = 0; c < cells.length; ++c) {
      final cell = row.cells[c], want = cells[c];
      final where = '$what ${row.segmentId} ${cell.runId}';
      expect(cell.runId, want['runId'], reason: where);
      _expectSummary(cell.summary, want['summary'], where);
      final laps = (want['laps'] as List).cast<Map<String, Object?>>();
      expect(cell.laps.length, laps.length, reason: where);
      // Overlays sorts with std::sort: equal times may come in any order.
      for (var l = 0; l < laps.length; ++l) {
        _close(cell.laps[l].seconds, laps[l]['seconds'], absolute: 1e-9);
      }
      expect(
        {for (final lap in cell.laps) _label(lap.reference)},
        {for (final lap in laps) lap['label']},
        reason: where,
      );
    }
  }
}

void _expectTimeLosses(TimeLossSummary summary, Object? expected, String what) {
  final want = expected as Map<String, Object?>;
  if (want['state'] != 'ready') {
    expect(summary.available, isFalse, reason: what);
    expect(summary.message, want['message'], reason: what);
    return;
  }
  expect(summary.available, isTrue, reason: what);
  expect(want['algorithm'], timeLossAlgorithm);
  expect(_label(summary.referenceLap), want['referenceLabel'], reason: what);
  expect(summary.allLaps ? 'allLaps' : 'runBests', want['scope']);
  expect(
    [summary.observationCount, summary.comparedLapCount, summary.untimedWindowCount],
    [want['observationCount'], want['comparedLapCount'], want['untimedWindowCount']],
    reason: what,
  );
  expect(summary.revision, want['revision']);
  final losses = (want['losses'] as List).cast<Map<String, Object?>>();
  expect(summary.losses.length, losses.length, reason: what);
  for (var i = 0; i < losses.length; ++i) {
    final loss = summary.losses[i], other = losses[i];
    final window = loss.window;
    expect(
      [
        _label(loss.lapReference),
        window.segmentId,
        window.name,
        window.type,
        window.role,
        window.cornerSegmentId.isEmpty ? null : window.cornerSegmentId,
        loss.cornerName.isEmpty ? null : loss.cornerName,
      ],
      [
        other['lapLabel'],
        other['segmentId'],
        other['name'],
        other['type'],
        other['role'],
        other['cornerSegmentId'],
        other['cornerName'],
      ],
      reason: '$what loss $i',
    );
    _close(loss.lossSeconds, other['lossSeconds'], absolute: 1e-9);
    _close(window.startProgressMeters, other['startMeters'], absolute: 1e-9);
    _close(window.endProgressMeters, other['endMeters'], absolute: 1e-9);
    _close(loss.loss.coverageLap, other['coverageLap'], absolute: 1e-9);
    _close(loss.loss.coverageReference, other['coverageReference'], absolute: 1e-9);
    _closeOrNull(window.cumulativeAtStartSeconds, other['cumulativeAtStartSeconds']);
    _closeOrNull(window.cumulativeAtEndSeconds, other['cumulativeAtEndSeconds']);
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
