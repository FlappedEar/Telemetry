// What a day looks like to Telemetry, in the shape FlappedEar Overlays reports
// it (tool/cpp_project_roundtrip `inspect`), so the two can be compared, and
// the shared round-trip fixtures (FET-40).
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

/// The shared fixtures: synthetic recordings and a day Overlays built from
/// them with its own code.
const roundtripFixtures = '../fetproject/test/fixtures/roundtrip';

/// The folder Overlays built the committed day in (its absolute paths).
const overlaysFixtureFolder = '/tmp/flappedear-roundtrip';

/// Copies the shared fixtures into [directory], keeping their layout, so the
/// document's relative recording paths resolve there.
void copyRoundtripFixtures(String directory) {
  for (final entity in Directory(roundtripFixtures).listSync(recursive: true)) {
    if (entity is! File) continue;
    final target = File(p.join(directory, p.relative(entity.path, from: roundtripFixtures)));
    target.parent.createSync(recursive: true);
    entity.copySync(target.path);
  }
}

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

/// [day] as Overlays' `inspect` reports a day: identity, runs with their
/// metadata and approved segments, every lap section with its group and
/// exclusion, the group shown and the headline results.
Map<String, Object?> telemetryView(OpenedDay day) {
  final analysis = day.analysis!;
  final event = day.document['event']! as Map<String, Object?>;
  final documentRuns = [for (final run in event['runs']! as List) run as Map<String, Object?>];
  // Overlays names an unresolved run's group "unresolved:" and its id too.
  final groupOf = <String, String>{
    for (final group in analysis.groups)
      for (final runId in group.runIds) runId: group.id,
  };
  final ranking = analysis.ranking;
  final best = ranking?.bestOfDay;
  final theoretical = dayTheoreticalBest(
    analysis,
    outingRuns(day.runs),
    documentRuns: documentRuns,
  );
  return {
    'documentState': day.document['documentState'],
    'eventId': day.eventId,
    'eventName': day.name,
    'comparisonGroupId': analysis.chosenGroupId ?? '',
    'runs': [
      for (final run in documentRuns)
        {
          'id': run['id'],
          'name': run['name'],
          'notes': run['notes'],
          'conditions': run['conditions'],
          'setupChanges': run['setupChanges'],
          'trackSegments': segmentSummary(run['trackSegments']),
        },
    ],
    'laps': [
      for (final row in analysis.rows)
        {
          'runId': row.runId,
          'label': '${row.runName} · ${row.type.label} ${row.lapNumber}',
          'type': row.type.label,
          'lapNumber': row.lapNumber,
          'startTime': row.start,
          'endTime': row.end,
          'excluded': day.exclusions.containsKey(row.reference),
          'exclusionReason': day.exclusions[row.reference] ?? '',
          'groupId': groupOf[row.runId] ?? '',
        },
    ],
    'report': {
      'bestLap': {'label': best?.displayName ?? '', 'seconds': best?.durationSeconds ?? 0.0},
      'theoreticalBest': {'totalSeconds': theoretical.summary?.totalSeconds ?? 0.0},
      'eligibleLaps': ranking?.eligibleLapCount ?? 0,
    },
  };
}

/// A run's `trackSegments` as Overlays' `inspect` summarizes them.
Map<String, Object?> segmentSummary(Object? segments) {
  final list = segments is List ? segments : const <Object?>[];
  return {
    'valid': fet.validTrackSegments(segments),
    'count': list.length,
    'names': [for (final segment in list) _object(segment)?['name']],
    'revision': list.isEmpty ? '' : fet.trackSegmentSetRevision(list),
  };
}

/// Overlays' `inspect` report reduced to what [telemetryView] gives.
Map<String, Object?> overlaysView(Map<String, Object?> inspected) {
  final report = inspected['report']! as Map<String, Object?>;
  return {
    'documentState': inspected['documentState'],
    'eventId': inspected['eventId'],
    'eventName': inspected['eventName'],
    'comparisonGroupId': inspected['comparisonGroupId'],
    'runs': [
      for (final run in (inspected['runs']! as List).cast<Map<String, Object?>>())
        {
          for (final key in ['id', 'name', 'notes', 'conditions', 'setupChanges', 'trackSegments'])
            key: run[key],
        },
    ],
    'laps': [
      for (final lap in (inspected['laps']! as List).cast<Map<String, Object?>>())
        {
          for (final key in [
            'runId',
            'label',
            'type',
            'lapNumber',
            'startTime',
            'endTime',
            'excluded',
            'exclusionReason',
            'groupId',
          ])
            key: lap[key],
        },
    ],
    'report': {
      'bestLap': {
        'label': (report['bestLap']! as Map)['label'],
        'seconds': (report['bestLap']! as Map)['seconds'],
      },
      'theoreticalBest': {'totalSeconds': (report['theoreticalBest']! as Map)['totalSeconds']},
      'eligibleLaps': report['eligibleLaps'],
    },
  };
}

/// Where [a] and [b] differ, as JSON paths ("event.runs[1].name"). Numbers
/// are equal within [tolerance]; [unordered] names arrays compared as sets
/// of their compact JSON (by path, without indices).
List<String> jsonDifferences(
  Object? a,
  Object? b, {
  double tolerance = 0,
  Set<String> unordered = const {},
  String path = '',
}) {
  if (a is num && b is num) {
    return (a - b).abs() <= tolerance ? const [] : ['$path: $a != $b'];
  }
  if (a is Map && b is Map) {
    return [
      for (final key in {...a.keys, ...b.keys})
        if (!a.containsKey(key))
          '${path.isEmpty ? key : '$path.$key'}: only in the second'
        else if (!b.containsKey(key))
          '${path.isEmpty ? key : '$path.$key'}: only in the first'
        else
          ...jsonDifferences(
            a[key],
            b[key],
            tolerance: tolerance,
            unordered: unordered,
            path: path.isEmpty ? '$key' : '$path.$key',
          ),
    ];
  }
  if (a is List && b is List) {
    if (unordered.contains(path.replaceAll(RegExp(r'\[\d+\]'), ''))) {
      final left = [for (final item in a) fet.qtCompactJson(item)]..sort();
      final right = [for (final item in b) fet.qtCompactJson(item)]..sort();
      return jsonDifferences(left, right, path: path);
    }
    if (a.length != b.length) return ['$path: ${a.length} items != ${b.length} items'];
    return [
      for (var i = 0; i < a.length; ++i)
        ...jsonDifferences(
          a[i],
          b[i],
          tolerance: tolerance,
          unordered: unordered,
          path: '$path[$i]',
        ),
    ];
  }
  return a == b ? const [] : ['$path: $a != $b'];
}
