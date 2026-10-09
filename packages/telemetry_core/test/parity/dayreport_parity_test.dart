// Compares the Dart channel summaries, temperature associations, focus areas
// and day report port (analysis/channel_summary.dart,
// analysis/temperature_association.dart, analysis/focus_areas.dart,
// analysis/day_report.dart, day/day_channel_summaries.dart and
// day/day_report.dart) with FlappedEar Overlays' C++ implementation over the
// synthetic parity corpus and fixed cases.
//
// test/parity/dayreport_reference.json is the output of
// tool/cpp_dayreport_dump run over test/parity/corpus/*.vbo and
// test/fixtures/*.vbo (see tool/README.md). Documents are compared as a
// whole: keys, counts, ids, names, states, reasons, texts and orders must
// match exactly; doubles to 1e-9 relative (1e-9 absolute near zero), as in
// the other parity tests.
//
// FET_DAYREPORT_REFERENCE and FET_DAYREPORT_DIRS (colon-separated) run the
// same checks against another reference and its recordings, for local runs
// only.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

var _maximumDifference = 0.0;
var _numbers = 0;

void main() {
  final referencePath =
      Platform.environment['FET_DAYREPORT_REFERENCE'] ?? 'test/parity/dayreport_reference.json';
  final directories =
      (Platform.environment['FET_DAYREPORT_DIRS'] ?? 'test/parity/corpus:test/fixtures').split(':');
  final reference = qtJsonDecode(File(referencePath).readAsStringSync()) as Map<String, Object?>;
  final files = (reference['files'] as List).cast<Map<String, Object?>>();
  final cases = reference['cases'] as Map<String, Object?>;
  final eventId = cases['eventId'] as String;
  final groupLabel = cases['groupLabel'] as String;
  final decisionsKey = utf8.encode(cases['decisionsKey'] as String);

  tearDownAll(() {
    if (Platform.environment.containsKey('FET_PARITY_REPORT')) {
      stdout.writeln('numbers compared: $_numbers, largest difference: $_maximumDifference');
    }
  });

  String pathOf(String name) => directories
      .map((directory) => '$directory/$name')
      .firstWhere((path) => File(path).existsSync());

  test(
    'the reference covers files, every report state and cases',
    skip: Platform.environment.containsKey('FET_DAYREPORT_REFERENCE') ? 'another reference' : false,
    () {
      expect(files.length, greaterThanOrEqualTo(8));
      final states = (files.first['sets'] as List).cast<Map<String, Object?>>().first['states'];
      expect(
        [for (final state in (states as List).cast<Map<String, Object?>>()) state['name']],
        ['loading', 'idle', 'error', 'unavailable', 'stale', 'noFocus', 'allLaps', 'noGroup'],
      );
      final focus = (cases['focus'] as List).cast<Map<String, Object?>>();
      expect(focus.where((item) => (item['areas'] as List).length >= 3).length, greaterThan(5));
    },
  );

  for (final entry in files) {
    final name = entry['file'] as String;
    test(name, () {
      final session = parseVboFile(pathOf(name));
      final laps = deriveSourceLapSession(session);
      final rows = sortDayLaps([
        for (final (index, run) in [('run-a', 'Run A'), ('run-b', 'Run B')].indexed)
          ...dayLapRows(
            session,
            laps,
            runId: run.$1,
            runName: run.$2,
            sourceRevision: index.toRadixString(16).padLeft(64, '0'),
            sourceOrder: index,
          ),
      ]);
      final configuration = TrackConfiguration(
        layoutId: 'Test circuit',
        direction: TrackDirection.clockwise,
        gateRevision: 'gates-v1:${'a' * 64}',
      );
      final exclusions = {
        for (final row in rows)
          if (row.type == LapSectionType.lap && (row.runId == 'run-a') == row.lapNumber.isEven)
            row.reference: 'The other half of the laps',
      };
      final ranked = rerankDay(
        DayAnalysis(
          rows: rows,
          configurations: {'run-a': configuration, 'run-b': configuration},
          inferences: const {},
          groups: const [],
          chosenGroupId: null,
          messages: const [],
        ),
        exclusions: exclusions,
      );
      // The group as the app labels it is "Group 1 · ..."; the tool names it.
      final analysis = _withGroups(ranked, [
        for (final group in ranked.groups)
          DayGroup(
            id: group.id,
            resolved: group.resolved,
            label: groupLabel,
            configuration: group.configuration,
            runIds: group.runIds,
            lapCount: group.lapCount,
            eligibleLapCount: group.eligibleLapCount,
            ranking: group.ranking,
          ),
      ], ranked.chosenGroupId);
      final eligible = dayEligibleLaps(analysis);
      expect(
        [for (final row in eligible) '${row.runId}#${row.lapNumber}'],
        [
          for (final lap in (entry['eligible'] as List).cast<Map<String, Object?>>())
            '${lap['runId']}#${lap['lapNumber']}',
        ],
      );
      final best = entry['best'] as Map<String, Object?>;
      expect(
        '${analysis.ranking?.bestOfDay?.runId}#${analysis.ranking?.bestOfDay?.lapNumber}',
        '${best['runId']}#${best['lapNumber']}',
      );
      final runs = {'run-a': OutingRun(session, laps), 'run-b': OutingRun(session, laps)};
      final infos = const [
        ProgressionRunInfo(id: 'run-a', name: 'Run A'),
        ProgressionRunInfo(id: 'run-b', name: 'Run B'),
      ];
      final channels = summarizeDayChannels(rows, {'run-a': session, 'run-b': session});
      final labels = {
        for (final row in rows) row.reference: '${row.runName} · LAP ${row.lapNumber}',
      };
      String label(Object? reference) => labels[reference] ?? '';
      for (final set in (entry['sets'] as List).cast<Map<String, Object?>>()) {
        final what = '$name ${set['name']}';
        final segments = set['segments'] as Map<String, Object?>;
        final theoretical = dayTheoreticalBest(
          analysis,
          runs,
          documentRuns: [
            for (final MapEntry(:key, :value) in segments.entries)
              {'id': key, 'trackSegments': value},
          ],
        );
        expect(theoretical.message, set['error'], reason: what);
        expect(theoretical.state, DayTheoreticalBestState.ready, reason: what);
        DayReportSources sources({
          bool lapsLoading = false,
          DayTheoreticalBest? withTheoretical,
          bool theoreticalLoading = false,
          List<int>? theoreticalKey,
          bool allLaps = false,
          DayChannelSummaries? withChannels,
          bool channelsLoading = false,
          DayAnalysis? withAnalysis,
        }) => dayReportSources(
          analysis: withAnalysis ?? analysis,
          eventId: eventId,
          runs: infos,
          decisionsKey: decisionsKey,
          lapsLoading: lapsLoading,
          theoretical: withTheoretical,
          theoreticalLoading: theoreticalLoading,
          theoreticalKey: theoreticalKey ?? decisionsKey,
          allLaps: allLaps,
          channels: withChannels,
          channelsLoading: channelsLoading,
        );

        final base = sources(withTheoretical: theoretical, withChannels: channels);
        _deep(buildOutingDayReport(base), set['report'], '$what report');
        final inputs = dayFocusInputs(theoretical, label);
        expect(inputs != null, set['hasFocus'], reason: what);
        expect(inputs?.comparedLapCount, set['comparedLapCount'], reason: what);
        _deep(
          [for (final area in dayFocusAreas(theoretical, label)) _areaMap(area, _referenceJson)],
          set['focusAreas'],
          '$what focus areas',
        );
        _deep(
          [for (final run in channels.runs) _runMap(run)],
          (set['channelSummaries'] as Map<String, Object?>)['runs'],
          '$what channel summaries',
        );
        _deep(
          _associationsMap(
            dayTemperatureAssociations(channels, [for (final row in eligible) row.reference]),
          ),
          set['associations'],
          '$what associations',
        );
        final states = set['states'];
        if (states == null) continue;
        final noGroup = _withGroups(analysis, analysis.groups, null);
        final variants = <String, DayReportSources>{
          'loading': sources(lapsLoading: true, theoreticalLoading: true, channelsLoading: true),
          'idle': sources(),
          'error': sources(
            withTheoretical: DayTheoreticalBest(
              groupId: theoretical.groupId,
              state: DayTheoreticalBestState.error,
              message: 'The calculation failed.',
            ),
            withChannels: DayChannelSummaries(error: 'Channel summaries were cancelled.'),
          ),
          'unavailable': sources(
            withTheoretical: DayTheoreticalBest(
              groupId: theoretical.groupId,
              state: DayTheoreticalBestState.unavailable,
              message: 'No eligible laps in this group to calculate a theoretical best from.',
            ),
            withChannels: DayChannelSummaries(error: "Import the day's recordings first."),
          ),
          'stale': sources(
            withTheoretical: theoretical,
            withChannels: channels,
            theoreticalKey: utf8.encode('older decisions'),
          ),
          'noFocus': _withoutFocus(base),
          'allLaps': sources(withTheoretical: theoretical, withChannels: channels, allLaps: true),
          'noGroup': sources(withChannels: channels, withAnalysis: noGroup),
        };
        for (final state in (states as List).cast<Map<String, Object?>>()) {
          final variant = state['name'] as String;
          _deep(buildOutingDayReport(variants[variant]!), state['report'], '$what $variant report');
        }
      }
    });
  }

  test('channel summaries, placeholders and cooling of a hand-made session', () {
    final item = cases['channels'] as Map<String, Object?>;
    final session = _session(item['session'] as Map<String, Object?>);
    final policies = {
      for (final policy in (item['policies'] as List).cast<Map<String, Object?>>())
        policy['name'] as String: ChannelSummaryPolicy(
          minimumPlausible: _double(policy['minimumPlausible'], double.negativeInfinity),
          maximumPlausible: _double(policy['maximumPlausible'], double.infinity),
          zeroIsPlaceholder: policy['zeroIsPlaceholder'] as bool,
          placeholderTypicalAbove: _double(policy['placeholderTypicalAbove']),
        ),
    };
    expect(recordedTemperatureChannels(session), item['temperatureChannels']);
    final temperatureParts = <String, List<ChannelSummary>>{};
    final summaries = (item['summaries'] as List).cast<Map<String, Object?>>();
    expect(summaries, hasLength(greaterThan(400)));
    for (final summary in summaries) {
      final channel = summary['channel'] as String, policy = summary['policy'] as String;
      final result = summarizeChannel(
        session,
        channel,
        _double(summary['from']),
        _double(summary['to']),
        policies[policy]!,
      );
      _deep(_summaryJson(result), summary['summary'], '$channel $policy ${summary['from']}');
      if (policy == 'temperature') (temperatureParts[channel] ??= []).add(result);
    }
    for (final combined in (item['combined'] as List).cast<Map<String, Object?>>()) {
      final parts = temperatureParts[combined['channel']]!;
      _deep(
        _summaryJson(
          combineChannelSummaries([
            for (final index in combined['parts'] as List) parts[index as int],
          ]),
        ),
        combined['summary'],
        'combined ${combined['channel']} ${combined['parts']}',
      );
    }
    for (final placeholder in (item['placeholders'] as List).cast<Map<String, Object?>>()) {
      expect(
        zeroIsPlaceholder(
          session.channels[placeholder['channel']]!,
          policies[placeholder['policy']]!,
        ),
        placeholder['zeroIsPlaceholder'],
        reason: '${placeholder['channel']} ${placeholder['policy']}',
      );
    }
    for (final plausible in (item['plausible'] as List).cast<Map<String, Object?>>()) {
      expect(
        plausibleSample(
          _special(plausible['value']),
          temperatureSummaryPolicy,
          plausible['zeroPlaceholder'] as bool,
        ),
        plausible['plausible'],
        reason: '$plausible',
      );
    }
    final options = {
      for (final option in (item['coolingOptions'] as List).cast<Map<String, Object?>>())
        option['name'] as String: CoolingOptions(
          minimumDrop: _double(option['minimumDrop']),
          minimumSeconds: _double(option['minimumSeconds']),
          smoothingSeconds: _double(option['smoothingSeconds']),
        ),
    };
    var intervals = 0;
    for (final cooling in (item['cooling'] as List).cast<Map<String, Object?>>()) {
      final found = findCoolingIntervals(
        session,
        cooling['channel'] as String,
        temperatureSummaryPolicy,
        options: options[cooling['options']]!,
      );
      intervals += found.length;
      _deep(
        [
          for (final interval in found)
            {
              'startTime': interval.startTime,
              'endTime': interval.endTime,
              'startValue': interval.startValue,
              'endValue': interval.endValue,
            },
        ],
        cooling['intervals'],
        'cooling ${cooling['channel']} ${cooling['options']}',
      );
    }
    expect(intervals, greaterThan(3));
  });

  test('rank correlations, associations and strong acceleration', () {
    final item = cases['associations'] as Map<String, Object?>;
    for (final pair in (item['spearman'] as List).cast<Map<String, Object?>>()) {
      final x = [for (final value in pair['x'] as List) _special(value)];
      final y = [for (final value in pair['y'] as List) _special(value)];
      _deep(
        _correlationJson(spearmanCorrelation(x, y, pair['minimum'] as int)),
        pair['result'],
        'spearman $x $y',
      );
    }
    for (final strength in (item['strengths'] as List).cast<Map<String, Object?>>()) {
      expect(associationStrength(_double(strength['value'])), strength['strength']);
    }
    for (final association in (item['associations'] as List).cast<Map<String, Object?>>()) {
      final observations = [
        for (final observation in (association['observations'] as List).cast<List<Object?>>())
          AssociationObservation(
            _double(observation[0]),
            _double(observation[1]),
            _double(observation[2]),
          ),
      ];
      final result = associateTemperature(observations);
      _deep(
        {
          'withValue': _correlationJson(result.withValue),
          'withOrder': _correlationJson(result.withOrder),
          'confoundedByOrder': result.confoundedByOrder,
        },
        {
          'withValue': association['withValue'],
          'withOrder': association['withOrder'],
          'confoundedByOrder': association['confoundedByOrder'],
        },
        'association of ${observations.length}',
      );
    }
    for (final acceleration in (item['accelerations'] as List).cast<Map<String, Object?>>()) {
      final session = _session(acceleration['session'] as Map<String, Object?>);
      // Overlays gives a strong acceleration only in g or with no unit;
      // Telemetry also reads m/s² (FET-288, test/analysis/unit_equivalence_test.dart).
      final gPerUnit = accelerationGPerUnit(session.channels.values.first.unit);
      if (gPerUnit != null && gPerUnit != 1.0) continue;
      for (final result in (acceleration['results'] as List).cast<Map<String, Object?>>()) {
        final lap = lapStrongAcceleration(session, _double(result['from']), _double(result['to']));
        _deep(
          {
            'from': result['from'],
            'to': result['to'],
            'strongG': lap.strongG,
            'channel': lap.channel,
            'sampleCount': lap.sampleCount,
          },
          result,
          'acceleration ${session.channels.values.first.unit} ${result['from']}',
        );
      }
    }
  });

  test('focus areas of hand-made and generated inputs', () {
    for (final (index, item) in (cases['focus'] as List).cast<Map<String, Object?>>().indexed) {
      final inputs = _focusInputs(item['inputs'] as Map<String, Object?>);
      _deep(
        [
          for (final area in selectFocusAreas(inputs, maximum: item['maximum'] as int))
            _areaMap(area, (reference) => reference),
        ],
        item['areas'],
        'focus case $index',
      );
    }
  });

  test('day reports built and validated', () {
    final item = cases['dayReport'] as Map<String, Object?>;
    for (final build in (item['builds'] as List).cast<Map<String, Object?>>()) {
      final input = DayReportInput(
        eventId: build['eventId'] as String,
        groupId: build['groupId'] as String,
        groupLabel: build['groupLabel'] as String,
        decisionsKey: utf8.encode(build['decisionsKey'] as String),
        results: [
          for (final result in (build['results'] as List).cast<Map<String, Object?>>())
            DayReportResult(
              id: result['id'] as String,
              algorithm: result['algorithm'] as String,
              revision: result['revision'] as String,
              status: DayResultStatus.values.firstWhere(
                (status) => status.code == result['status'],
              ),
              reason: result['reason'] as String,
              range: Map.of(result['range'] as Map<String, Object?>),
              value: Map.of(result['value'] as Map<String, Object?>),
              evidence: (result['evidence'] as List).cast<Map<String, Object?>>().toList(),
              decisionsKey: utf8.encode(result['decisionsKey'] as String),
            ),
        ],
      );
      final what = build['name'] as String;
      if (build.containsKey('error')) {
        expect(
          () => buildDayReport(input),
          throwsA(isA<ArgumentError>().having((error) => error.message, 'message', build['error'])),
          reason: what,
        );
        continue;
      }
      final report = buildDayReport(input);
      _deep(report, build['report'], what);
      expect(validateDayReport(report), build['validation'], reason: what);
    }
    for (final document in (item['documents'] as List).cast<Map<String, Object?>>()) {
      expect(
        validateDayReport(document['document'] as Map<String, Object?>),
        document['validation'],
        reason: document['name'] as String,
      );
    }
  });

  test('a hand-made day of temperatures, heart rate and acceleration', () {
    final item = cases['outing'] as Map<String, Object?>;
    final rows = [
      for (final row in (item['rows'] as List).cast<Map<String, Object?>>())
        DayLapRow(
          runId: row['runId'] as String,
          runName: row['runName'] as String,
          type: LapSectionType.values.firstWhere((type) => type.label == row['type']),
          lapNumber: row['lapNumber'] as int,
          start: _double(row['start']),
          end: _double(row['end']),
          sourceRevision: '',
        ),
    ];
    final sessions = {
      for (final MapEntry(:key, :value) in (item['sessions'] as Map<String, Object?>).entries)
        key: _session(value as Map<String, Object?>),
    };
    final channels = summarizeDayChannels(rows, sessions);
    _deep(
      [for (final run in channels.runs) _runMap(run)],
      (item['channelSummaries'] as Map<String, Object?>)['runs'],
      'channel summaries',
    );
    final byKey = {
      for (final row in rows) jsonEncode(_referenceJson(row.reference)): row.reference,
    };
    final eligible = [
      for (final reference in (item['eligible'] as List).cast<Map<String, Object?>>())
        byKey[jsonEncode({
          'runId': reference['runId'],
          'sourceRevision': reference['sourceRevision'],
          'type': reference['type'],
          'startTime': _double(reference['startTime']),
          'endTime': _double(reference['endTime']),
        })]!,
    ];
    final associations = dayTemperatureAssociations(channels, eligible);
    expect(
      associations.channels.where((channel) => channel.lapTime.coefficient != null),
      isNotEmpty,
    );
    _deep(_associationsMap(associations), item['associations'], 'associations');
    final analysis = DayAnalysis(
      rows: rows,
      configurations: const {},
      inferences: const {},
      groups: const [],
      chosenGroupId: null,
      messages: const [],
    );
    Map<String, Object?> report(DayChannelSummaries channels) => dayReport(
      analysis: analysis,
      eventId: eventId,
      runs: const [],
      decisionsKey: decisionsKey,
      channels: channels,
    );
    _deep(report(channels), item['report'], 'report');
    _deep(
      report(
        DayChannelSummaries(
          runs: [
            for (final run in channels.runs)
              if (run.runId == 's3' || run.runId == 's4') run,
          ],
        ),
      ),
      item['reportWithoutChannels'],
      'report without channels',
    );
  });
}

DayAnalysis _withGroups(DayAnalysis analysis, List<DayGroup> groups, String? chosen) => DayAnalysis(
  rows: analysis.rows,
  configurations: analysis.configurations,
  inferences: analysis.inferences,
  groups: groups,
  chosenGroupId: chosen,
  messages: analysis.messages,
);

DayReportSources _withoutFocus(DayReportSources sources) => DayReportSources(
  eventId: sources.eventId,
  groupId: sources.groupId,
  groupLabel: sources.groupLabel,
  decisionsKey: sources.decisionsKey,
  theoreticalKey: sources.theoreticalKey,
  lapsLoading: sources.lapsLoading,
  ranking: sources.ranking,
  progression: sources.progression,
  consistency: sources.consistency,
  eligibleLaps: sources.eligibleLaps,
  theoreticalStatus: sources.theoreticalStatus,
  theoreticalMessage: sources.theoreticalMessage,
  theoretical: sources.theoretical,
  timeLosses: sources.timeLosses,
  sectionProgression: sources.sectionProgression,
  channelStatus: sources.channelStatus,
  channelMessage: sources.channelMessage,
  channels: sources.channels,
  lapLabel: sources.lapLabel,
  referenceJson: sources.referenceJson,
);

Object? _referenceJson(Object? reference) =>
    reference is DayLapReference ? dayLapReferenceJson(reference) : reference;

TelemetrySession _session(Map<String, Object?> spec) {
  final channels = <String, TelemetryChannel>{};
  for (final channel in (spec['channels'] as List).cast<Map<String, Object?>>()) {
    channels[channel['name'] as String] = TelemetryChannel(
      name: channel['name'] as String,
      unit: channel['unit'] as String,
      timestamps: Float64List.fromList([
        for (final time in channel['times'] as List) _double(time),
      ]),
      values: Float32List.fromList([
        for (final value in channel['values'] as List) value == null ? double.nan : _double(value),
      ]),
    );
  }
  return TelemetrySession(
    duration: _double(spec['duration']),
    startTime: 0,
    metadata: const {},
    channels: channels,
    aliases: (spec['aliases'] as Map<String, Object?>).cast<String, String>(),
    warnings: const [],
    timingGates: const [],
    sampleCount: 0,
  );
}

Map<String, Object?> _summaryJson(ChannelSummary summary) => {
  'channel': summary.channel,
  'unit': summary.unit,
  'startTime': summary.startTime,
  'endTime': summary.endTime,
  'sampleCount': summary.sampleCount,
  'excludedArtifacts': summary.excludedArtifacts,
  'minimum': summary.minimum,
  'maximum': summary.maximum,
  'mean': summary.mean,
  'minimumTime': summary.minimumTime,
  'maximumTime': summary.maximumTime,
  'coveredSeconds': summary.coveredSeconds,
  'coverage': summary.coverage,
  'unavailableReason': summary.unavailableReason,
  'valid': summary.valid,
};

Map<String, Object?> _section(DayLapRow row) => {
  'type': row.type.label,
  'lapNumber': row.lapNumber,
  'reference': dayLapReferenceJson(row.reference),
};

Map<String, Object?> _channelMap(RunChannel channel, {required bool cooling}) => {
  'channel': channel.channel,
  'unit': channel.unit,
  'run': channelSummaryMap(channel.run),
  'sections': [
    for (final section in channel.sections)
      {...channelSummaryMap(section.summary), ..._section(section.row)},
  ],
  'trace': [
    for (final point in channel.trace) point == null ? null : [point.time, point.mean],
  ],
  if (cooling)
    'cooling': [
      for (final item in channel.cooling)
        {
          'startTime': item.interval.startTime,
          'endTime': item.interval.endTime,
          'startValue': item.interval.startValue,
          'endValue': item.interval.endValue,
          'drop': item.interval.drop,
          'seconds': item.interval.seconds,
          if (item.section case final section?) ...{
            'type': section.type.label,
            'lapNumber': section.lapNumber,
          },
        },
    ],
};

Map<String, Object?> _runMap(RunChannelSummaries run) => {
  'runId': run.runId,
  'runName': run.runName,
  if (run.unavailableReason.isNotEmpty)
    'unavailableReason': run.unavailableReason
  else ...{
    'channels': [for (final channel in run.channels) _channelMap(channel, cooling: true)],
    'laps': [
      for (final lap in run.laps)
        {
          'type': lap.row.type.label,
          'lapNumber': lap.row.lapNumber,
          'startTime': lap.row.start,
          'endTime': lap.row.end,
          'reference': dayLapReferenceJson(lap.row.reference),
          'accelerationChannel': lap.acceleration.channel,
          'strongAccelerationG': ?lap.acceleration.strongG,
        },
    ],
    if (run.heartRate case final heartRate?) 'heartRate': _channelMap(heartRate, cooling: false),
  },
};

Map<String, Object?> _correlationMap(RankCorrelation correlation) => {
  'count': correlation.count,
  'available': correlation.coefficient != null,
  if (correlation.coefficient case final coefficient?) ...{
    'coefficient': coefficient,
    'strength': associationStrength(coefficient),
  } else
    'unavailableReason': correlation.unavailableReason,
};

Map<String, Object?> _correlationJson(RankCorrelation correlation) => {
  'count': correlation.count,
  'coefficient': correlation.coefficient,
  'unavailableReason': correlation.unavailableReason,
};

Map<String, Object?> _associationsMap(TemperatureAssociations associations) => {
  'algorithm': temperatureAssociationAlgorithm,
  'minimumLaps': minimumAssociationSamples,
  'minimumCoverage': minimumAssociationCoverage,
  'orderConfoundLevel': associationOrderConfoundLevel,
  'eligibleLaps': associations.eligibleLaps,
  'channels': [
    for (final channel in associations.channels)
      {
        'channel': channel.channel,
        'unit': channel.unit,
        'lapTime': _correlationMap(channel.lapTime),
        'acceleration': _correlationMap(channel.acceleration),
        'order': _correlationMap(channel.order),
        'confoundedByOrder': channel.confoundedByOrder,
        'lowCoverageLaps': channel.lowCoverageLaps,
        'notRecordedLaps': channel.notRecordedLaps,
        'observations': [
          for (final lap in channel.observations)
            {
              'runName': lap.row.runName,
              'lapNumber': lap.row.lapNumber,
              'temperature': lap.temperature,
              'lapTime': lap.lapTime,
              'coverage': lap.coverage,
              'reference': dayLapReferenceJson(lap.row.reference),
              'strongAccelerationG': ?lap.strongAccelerationG,
            },
        ],
      },
  ],
};

Map<String, Object?> _areaMap(FocusArea area, Object? Function(Object?) reference) => {
  'kind': area.kind.code,
  'segmentId': area.segmentId,
  'name': area.name,
  'observation': area.observation,
  'hypothesis': area.hypothesis,
  'metric': area.metric,
  'value': area.value,
  'unit': area.unit,
  'sampleCount': area.sampleCount,
  'lap': reference(area.lap),
  'against': reference(area.against),
  'score': area.score,
};

FocusInputs _focusInputs(Map<String, Object?> json) => FocusInputs(
  referenceLap: json['referenceLap'],
  referenceLabel: json['referenceLabel'] as String,
  comparedLapCount: json['comparedLapCount'] as int,
  speedUnit: json['speedUnit'] as String,
  gaps: [
    for (final gap in (json['gaps'] as List).cast<Map<String, Object?>>())
      FocusSectorGap(
        segmentId: gap['segmentId'] as String,
        name: gap['name'] as String,
        gapSeconds: _special(gap['gapSeconds']),
        bestLap: gap['bestLap'],
        bestLapLabel: gap['bestLapLabel'] as String,
        sourceLap: gap['sourceLap'],
        sourceLapLabel: gap['sourceLapLabel'] as String,
      ),
  ],
  losses: [
    for (final loss in (json['losses'] as List).cast<Map<String, Object?>>())
      FocusLoss(
        segmentId: loss['segmentId'] as String,
        name: loss['name'] as String,
        lossSeconds: _special(loss['lossSeconds']),
        lap: loss['lap'],
      ),
  ],
  corners: [
    for (final corner in (json['corners'] as List).cast<Map<String, Object?>>())
      FocusCorner(
        segmentId: corner['segmentId'] as String,
        name: corner['name'] as String,
        observations: [
          for (final observation in (corner['observations'] as List).cast<Map<String, Object?>>())
            CornerLapObservation(lapReference: observation['lap'])
              ..brakingPointMeters = _optional(observation['brakingPointMeters'])
              ..brakingProvenance = observation['brakingProvenance'] as String
              ..minimumSpeed = _optional(observation['minimumSpeed']),
        ],
      ),
  ],
);

double _double(Object? value, [double? whenNull]) =>
    value == null && whenNull != null ? whenNull : (value as num).toDouble();

double? _optional(Object? value) => value == null ? null : _double(value);

double _special(Object? value) => switch (value) {
  'nan' => double.nan,
  'inf' => double.infinity,
  '-inf' => double.negativeInfinity,
  _ => _double(value),
};

// [actual] (the Dart result as a JSON-like value) against [expected] (the
// C++ document): the same keys and lengths, the same strings and booleans,
// numbers to 1e-9 relative (1e-9 absolute near zero). A NaN or infinity
// matches null, which is how the C++ side writes it.
void _deep(Object? actual, Object? expected, String path) {
  if (expected is Map) {
    expect(actual, isA<Map<Object?, Object?>>(), reason: path);
    final map = actual as Map;
    expect(map.keys.toSet(), expected.keys.toSet(), reason: path);
    for (final key in expected.keys) {
      _deep(map[key], expected[key], '$path.$key');
    }
    return;
  }
  if (expected is List) {
    expect(actual, isA<List<Object?>>(), reason: path);
    final list = actual as List;
    expect(list.length, expected.length, reason: path);
    for (var i = 0; i < expected.length; ++i) {
      _deep(list[i], expected[i], '$path[$i]');
    }
    return;
  }
  if (expected == null && actual is double && !actual.isFinite) return;
  if (expected is num && actual is num) {
    ++_numbers;
    final value = expected.toDouble(), difference = (actual - value).abs();
    if (difference > _maximumDifference) _maximumDifference = difference;
    expect(actual.toDouble(), closeTo(value, max(1e-9, 1e-9 * value.abs())), reason: path);
    return;
  }
  expect(actual, expected, reason: path);
}
