// The day's channel summaries and day report (day/day_channel_summaries.dart,
// day/day_report.dart): statuses, staleness and a run without a recording.
// Figures are checked against Overlays in test/parity/dayreport_parity_test.dart.
import 'dart:convert';
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _track = TrackConfiguration(
  layoutId: 'Test circuit',
  direction: TrackDirection.clockwise,
  gateRevision: 'gates-v1:0000000000000000000000000000000000000000000000000000000000000000',
);

DayLapRow _lap(String run, int number, double start, double duration) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.lap,
  lapNumber: number,
  start: start,
  end: start + duration,
  sourceRevision: _revision,
  referenceEligible: true,
);

TelemetrySession _session(Map<String, double Function(double time)> channels) {
  final times = Float64List.fromList([for (var i = 0; i <= 400; ++i) i.toDouble()]);
  return TelemetrySession(
    duration: 400,
    startTime: 0,
    metadata: const {},
    channels: {
      for (final MapEntry(:key, :value) in channels.entries)
        key: TelemetryChannel(
          name: key,
          unit: key == 'heart_rate' ? 'bpm' : 'C',
          timestamps: times,
          values: Float32List.fromList([for (final time in times) value(time)]),
        ),
    },
    aliases: channels.containsKey('heart_rate') ? const {'heartRate': 'heart_rate'} : const {},
    warnings: const [],
    timingGates: const [],
    sampleCount: 0,
  );
}

Map<String, Object?> _result(Map<String, Object?> report, String id) => (report['results'] as List)
    .cast<Map<String, Object?>>()
    .firstWhere((result) => result['id'] == id);

void main() {
  final rows = [
    _lap('1', 1, 10, 92),
    _lap('1', 2, 102, 91),
    _lap('1', 3, 193, 93),
    _lap('2', 1, 10, 90),
    _lap('2', 2, 100, 95),
  ];
  final analysis = rerankDay(
    DayAnalysis(
      rows: rows,
      configurations: const {'1': _track, '2': _track},
      inferences: const {},
      groups: const [],
      chosenGroupId: null,
      messages: const [],
    ),
  );
  const runs = [
    ProgressionRunInfo(id: '1', name: 'Session 1'),
    ProgressionRunInfo(id: '2', name: 'Session 2'),
  ];

  test('the decisions key follows the exclusions and is stable', () {
    final key = dayDecisionsKey(analysis);
    expect(key, hasLength(32));
    expect(dayDecisionsKey(analysis), key);
    final excluded = {rows[1].reference: 'Yellow flag'};
    final other = dayDecisionsKey(rerankDay(analysis, exclusions: excluded), exclusions: excluded);
    expect(other, isNot(key));
  });

  test('a report before anything is calculated says so and validates', () {
    final key = utf8.encode('decisions');
    final report = dayReport(analysis: analysis, eventId: 'event', runs: runs, decisionsKey: key);
    expect(validateDayReport(report), '');
    expect(report['groupId'], _track.compatibilityGroupId);
    final best = _result(report, 'bestLap');
    expect(best['status'], 'available');
    expect((best['value'] as Map)['label'], 'Session 2 · LAP 1');
    expect((best['value'] as Map)['seconds'], closeTo(90, 1e-9));
    for (final id in ['theoreticalBest', 'timeLosses', 'temperatures', 'heartRate']) {
      final result = _result(report, id);
      expect(result['status'], 'notComputed', reason: id);
      expect(result['reason'], 'Not calculated yet.', reason: id);
      expect(
        result.containsKey('value') ? result['value'] : const <String, Object?>{},
        isEmpty,
        reason: id,
      );
    }
    // While they are calculated.
    final loading = dayReport(
      analysis: analysis,
      eventId: 'event',
      runs: runs,
      decisionsKey: key,
      theoreticalLoading: true,
      channelsLoading: true,
    );
    expect(_result(loading, 'theoreticalBest')['status'], 'computing');
    expect(_result(loading, 'temperatures')['status'], 'computing');
  });

  test('an unavailable theoretical best gives its reason, stale or not', () {
    final report = dayReport(
      analysis: analysis,
      eventId: 'event',
      runs: runs,
      decisionsKey: utf8.encode('now'),
      theoretical: DayTheoreticalBest(
        groupId: _track.compatibilityGroupId!,
        state: DayTheoreticalBestState.unavailable,
        message: 'No run in this group has an approved segment review yet.',
      ),
      theoreticalKey: utf8.encode('before'),
    );
    expect(validateDayReport(report), '');
    final result = _result(report, 'theoreticalBest');
    expect(result['status'], 'unavailable');
    expect(result['reason'], 'No run in this group has an approved segment review yet.');
  });

  test('channel summaries of every section, and a run without a recording', () {
    final channels = summarizeDayChannels(rows, {
      '1': _session({
        'engine_oil_temp': (time) => time < 5 ? 0 : 90 + time / 40,
        'heart_rate': (time) => 140,
      }),
    });
    expect(channels.error, '');
    expect(channels.runs.map((run) => run.runId), ['1', '2']);
    expect(channels.runs[1].unavailableReason, channelRecordingUnavailable);
    final oil = channels.runs[0].channel('engine_oil_temp')!;
    expect(oil.sections, hasLength(3));
    // Placeholder zeros at the start are left out, never averaged in.
    expect(oil.run.minimum, greaterThanOrEqualTo(90));
    expect(oil.run.excludedArtifacts, 5);
    expect(oil.trace, hasLength(channelTrendBins));
    expect(channels.runs[0].heartRate?.run.mean, closeTo(140, 1e-6));
    expect(channels.temperatureChannels, ['engine_oil_temp']);
    final report = dayReport(analysis: analysis, eventId: 'event', runs: runs, channels: channels);
    expect(validateDayReport(report), '');
    expect(_result(report, 'temperatures')['status'], 'available');
    expect(_result(report, 'heartRate')['status'], 'available');
    // Too few laps for an association: unavailable with a reason, no number.
    final associations = dayTemperatureAssociations(channels, [
      for (final row in rows) row.reference,
    ]);
    final association = associations.channel('engine_oil_temp')!;
    expect(association.lapTime.coefficient, isNull);
    expect(association.lapTime.unavailableReason, associationTooFewSamples);
    // Run 2's laps have no recording to count.
    expect(association.notRecordedLaps, 0);
  });
}
