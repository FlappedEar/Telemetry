// Interval summaries of recorded channels (analysis/channel_summary.dart,
// KAN-67/KAN-69), ported from FlappedEar Overlays
// native/tests/ChannelSummaryTests.cpp: time-weighted mean, extrema,
// coverage, gaps never bridged, artifacts excluded and counted.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

TelemetryChannel channel(
  String name,
  String unit,
  List<double> times,
  double Function(double time) value,
) => TelemetryChannel(
  name: name,
  unit: unit,
  timestamps: Float64List.fromList(times),
  values: Float32List.fromList([for (final time in times) value(time)]),
);

List<double> clock(double start, double end, double step) {
  final times = <double>[];
  for (var time = start; time <= end + 1e-9; time += step) {
    times.add(time);
  }
  return times;
}

TelemetrySession sessionWith(
  List<TelemetryChannel> channels, {
  Map<String, String> aliases = const {},
}) => TelemetrySession(
  duration: 0,
  startTime: 0,
  metadata: const {},
  channels: {for (final channel in channels) channel.name: channel},
  aliases: aliases,
  warnings: const [],
  timingGates: const [],
  sampleCount: 0,
);

void main() {
  test('computes the time-weighted mean and extrema', () {
    // Oil rises linearly from 100 to 120 °C over 10 s at 10 Hz: mean exactly 110.
    final session = sessionWith([
      channel('engine_oil_temp', 'C', clock(0, 10, 0.1), (t) => 100 + 2 * t),
    ]);
    final summary = summarizeChannel(session, 'engine_oil_temp', 0, 10, temperatureSummaryPolicy);
    expect(summary.valid, isTrue);
    expect(summary.unit, 'C');
    expect(summary.mean, closeTo(110.0, 1e-3));
    expect(summary.minimum, closeTo(100.0, 1e-4));
    expect(summary.maximum, closeTo(120.0, 1e-4));
    expect(summary.maximumTime, closeTo(10.0, 1e-6));
    expect(summary.coverage, closeTo(1.0, 1e-6));
    expect(summary.sampleCount, 101);
    // An interval inside the recording: samples 2.0..4.0.
    final part = summarizeChannel(session, 'engine_oil_temp', 1.95, 4.05, temperatureSummaryPolicy);
    expect(part.mean, closeTo(106.0, 1e-3));
  });

  test('never bridges a gap', () {
    // 60 °C for 0..4 s, a 4 s hole, 100 °C for 8..10 s. Bridging the hole
    // would pull the mean towards 80 and report full coverage.
    final session = sessionWith([
      channel('coolant_temp', 'C', [
        ...clock(0, 4, 0.1),
        ...clock(8, 10, 0.1),
      ], (t) => t < 5 ? 60 : 100),
    ]);
    final summary = summarizeChannel(session, 'coolant_temp', 0, 10, temperatureSummaryPolicy);
    expect(summary.valid, isTrue);
    expect(summary.coveredSeconds, closeTo(6.0, 1e-6));
    expect(summary.coverage, closeTo(0.6, 1e-6));
    expect(summary.mean, closeTo((60.0 * 4 + 100.0 * 2) / 6.0, 1e-3));
  });

  test('excludes placeholders and implausible values', () {
    // A 94 °C coolant channel with OBD placeholder zeros and one 900 °C glitch.
    final session = sessionWith([
      channel(
        'coolant_temp',
        '',
        clock(0, 10, 0.1),
        (t) => t < 0.35
            ? 0
            : (t - 5.0).abs() < 1e-6
            ? 900
            : 94,
      ),
    ]);
    final summary = summarizeChannel(session, 'coolant_temp', 0, 10, temperatureSummaryPolicy);
    expect(summary.valid, isTrue);
    expect(summary.excludedArtifacts, 5); // four leading zeros and the glitch
    expect(summary.minimum, closeTo(94.0, 1e-4));
    expect(summary.maximum, closeTo(94.0, 1e-4));
    expect(summary.unit, isEmpty); // undeclared, reported as such
    // A channel whose typical value is near zero keeps real zeros.
    final cold = sessionWith([
      channel('intake_temp', 'C', clock(0, 10, 0.1), (t) => t < 5 ? 0 : 2),
    ]);
    expect(
      summarizeChannel(cold, 'intake_temp', 0, 10, temperatureSummaryPolicy).excludedArtifacts,
      0,
    );
    // Heart rate outside 30..230 bpm is an artifact.
    final heart = sessionWith(
      [channel('heart_rate', 'bpm', clock(0, 10, 0.5), (t) => t < 1 ? 255 : 140)],
      aliases: {'heartRate': 'heart_rate'},
    );
    final hr = summarizeChannel(heart, 'heartRate', 0, 10, heartRateSummaryPolicy);
    expect(hr.channel, 'heart_rate');
    expect(hr.excludedArtifacts, 2);
    expect(hr.mean, closeTo(140.0, 1e-3));
  });

  test('reports missing sensors and lists temperatures', () {
    final session = sessionWith([
      for (final name in [
        'coolant_temp-obd',
        'engine_oil_temp-obd',
        'velocity',
        'gearbox_temp-obd',
      ])
        channel(name, '', clock(0, 1, 0.1), (_) => 90),
    ]);
    expect(recordedTemperatureChannels(session), [
      'coolant_temp-obd',
      'engine_oil_temp-obd',
      'gearbox_temp-obd',
    ]);
    final missing = summarizeChannel(session, 'brake_temp', 0, 1, temperatureSummaryPolicy);
    expect(missing.valid, isFalse);
    expect(missing.unavailableReason, channelSummaryMissing);
    expect(missing.mean, isNull);
    // No samples inside the interval.
    final outside = summarizeChannel(session, 'coolant_temp-obd', 5, 6, temperatureSummaryPolicy);
    expect(outside.valid, isFalse);
    expect(outside.unavailableReason, channelSummaryNoSamples);
  });

  test('finds continuously recorded cooling only', () {
    // Oil rises 80 -> 110 °C over 60 s, then cools to 90 °C over 120 s.
    double profile(double t) => t <= 60 ? 80 + t / 2 : math.max(90.0, 110 - (t - 60) / 6);
    final session = sessionWith([channel('engine_oil_temp', 'C', clock(0, 200, 0.5), profile)]);
    var intervals = findCoolingIntervals(session, 'engine_oil_temp', temperatureSummaryPolicy);
    expect(intervals, hasLength(1));
    expect(intervals[0].drop, closeTo(20.0, 1.0));
    expect(intervals[0].seconds, closeTo(120.0, 6.0));
    expect(intervals[0].startTime, closeTo(60.0, 3.0));

    // The same cooling interrupted by a 60 s recording gap: nothing may span
    // the break, and no cooling is invented across it.
    final gapped = sessionWith([
      channel('engine_oil_temp', 'C', [
        ...clock(0, 100, 0.5),
        ...clock(160, 260, 0.5),
      ], (t) => t <= 30 ? 80 + t : 110 - (t - 30) / 8),
    ]);
    intervals = findCoolingIntervals(gapped, 'engine_oil_temp', temperatureSummaryPolicy);
    expect(intervals, isNotEmpty);
    for (final interval in intervals) {
      expect(interval.endTime <= 100.0 + 1e-6 || interval.startTime >= 160.0 - 1e-6, isTrue);
    }

    // Sensor noise of ±0.5 °C around a steady 95 °C is not cooling.
    final steady = sessionWith([
      channel('coolant_temp', 'C', clock(0, 300, 0.5), (t) => 95 + 0.5 * math.sin(t)),
    ]);
    expect(findCoolingIntervals(steady, 'coolant_temp', temperatureSummaryPolicy), isEmpty);
    expect(findCoolingIntervals(steady, 'missing', temperatureSummaryPolicy), isEmpty);
  });

  test('combines disjoint intervals', () {
    // A segment across start/finish: the lap's last 10 s at 150 bpm and its
    // first 30 s at 130 bpm. Weighted by covered time: (150·10 + 130·30)/40.
    final session = sessionWith(
      [channel('heart_rate', 'bpm', clock(0, 100, 0.5), (t) => t < 50 ? 130 : 150)],
      aliases: {'heartRate': 'heart_rate'},
    );
    final end = summarizeChannel(session, 'heartRate', 90, 100, heartRateSummaryPolicy);
    final start = summarizeChannel(session, 'heartRate', 0, 30, heartRateSummaryPolicy);
    final combined = combineChannelSummaries([end, start]);
    expect(combined.valid, isTrue);
    expect(combined.mean, closeTo(135.0, 1e-3));
    expect(combined.minimum, closeTo(130.0, 1e-4));
    expect(combined.maximum, closeTo(150.0, 1e-4));
    expect(combined.sampleCount, end.sampleCount + start.sampleCount);
    expect(combined.coveredSeconds, closeTo(40.0, 1e-6));
    expect(combined.coverage, closeTo(1.0, 1e-6));
    // One part without samples lowers coverage; it does not invent values.
    final empty = summarizeChannel(session, 'heartRate', 200, 210, heartRateSummaryPolicy);
    final partial = combineChannelSummaries([start, empty]);
    expect(partial.valid, isTrue);
    expect(partial.mean, closeTo(130.0, 1e-3));
    expect(partial.coverage, closeTo(0.75, 1e-6));
    // A channel missing in every part stays missing.
    final missing = combineChannelSummaries([
      summarizeChannel(session, 'brake_temp', 0, 10, temperatureSummaryPolicy),
      summarizeChannel(session, 'brake_temp', 20, 30, temperatureSummaryPolicy),
    ]);
    expect(missing.valid, isFalse);
    expect(missing.unavailableReason, channelSummaryMissing);
  });

  test('a summarizer of one channel matches single summaries', () {
    final session = sessionWith([
      channel('coolant_temp', '', clock(0, 10, 0.1), (t) => t < 0.35 ? 0 : 90 + t),
    ]);
    final summarizer = ChannelSummarizer(session, 'coolant_temp', temperatureSummaryPolicy);
    for (final (from, to) in [(0.0, 10.0), (2.0, 3.0), (11.0, 12.0), (5.0, 5.0)]) {
      final single = summarizeChannel(session, 'coolant_temp', from, to, temperatureSummaryPolicy);
      final many = summarizer.summarize(from, to);
      expect(
        [many.valid, many.sampleCount, many.excludedArtifacts, many.mean, many.unavailableReason],
        [
          single.valid,
          single.sampleCount,
          single.excludedArtifacts,
          single.mean,
          single.unavailableReason,
        ],
      );
    }
    expect(
      ChannelSummarizer(
        session,
        'missing',
        temperatureSummaryPolicy,
      ).summarize(0, 1).unavailableReason,
      channelSummaryMissing,
    );
  });
}
