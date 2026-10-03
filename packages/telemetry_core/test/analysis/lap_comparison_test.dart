// The A/B lap comparison and lap charts, after the comparison and lap-detail
// cases of FlappedEar Overlays native/tests/TelemetryTests.cpp (revision
// d4d1039): overlaysComparisonLapsOnASharedProgressAxis,
// excludesChannelMissingFromOneComparisonSlot,
// comparesKnownDeltaThroughFullComparisonPipeline,
// coloursTheComparisonMapByAChannel and the lap series of
// opensOutingLapDetail.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

double Function(double) _constant(double speed) =>
    (d) => speed;

/// [session] with [extra] channels (same clock) and aliases added, or
/// [without] removed.
TelemetrySession _with(
  TelemetrySession session, {
  Map<String, (String, double Function(double t))> extra = const {},
  Map<String, String> aliases = const {},
  Set<String> without = const {},
}) {
  final times = session.channel('latitude')!.timestamps;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: {
      for (final MapEntry(:key, :value) in session.channels.entries)
        if (!without.contains(key)) key: value,
      for (final MapEntry(:key, value: (unit, value)) in extra.entries)
        key: TelemetryChannel(
          name: key,
          unit: unit,
          timestamps: times,
          values: Float32List.fromList([for (final t in times) value(t)]),
        ),
    },
    aliases: {
      for (final MapEntry(:key, :value) in session.aliases.entries)
        if (!without.contains(value)) key: value,
      ...aliases,
    },
    warnings: const [],
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

ComparisonLap _lap(TelemetrySession session, LapSession laps, int index) => ComparisonLap(
  session: session,
  laps: laps,
  start: laps.timedLaps[index].startTelemetryTime,
  end: laps.timedLaps[index].endTelemetryTime,
  lapNumber: laps.timedLaps[index].number,
);

void main() {
  group('two laps of one recording', () {
    final session = rectangleSession([_constant(30), _constant(28), _constant(31)], pedals: true);
    final laps = deriveSourceLapSession(session);
    final comparison = LapComparison(_lap(session, laps, 0), _lap(session, laps, 1));

    test('are overlaid on a shared progress axis', () {
      expect(comparison.availableChannels, session.channelNames());
      expect(comparison.axisLengthMeters, closeTo(848.6, 1));
      for (final slot in [0, 1]) {
        final track = comparison.overlayTrack(slot);
        expect(track, isNotEmpty);
        for (final run in track) {
          for (final point in run) {
            expect(point.x.isFinite && point.y.isFinite, isTrue);
            expect(point.x, inInclusiveRange(-0.01, 1.01));
            expect(point.y, inInclusiveRange(-0.01, 1.01));
          }
        }
      }
      final length = comparison.axisLengthMeters;
      for (final slot in [0, 1]) {
        expect(comparison.channelSeries(slot, 'latitude', 0, length, 100).hasData, isTrue);
        expect(comparison.positionAt(slot, length / 2), isNotNull);
      }
      // Both laps are on the same line: their markers meet.
      final a = comparison.positionAt(0, length / 2)!, b = comparison.positionAt(1, length / 2)!;
      expect((a.x - b.x).abs() + (a.y - b.y).abs(), lessThan(0.01));
      expect(comparison.positionAt(0, length * 2), isNull);
      expect(comparison.positionAt(2, 10), isNull);
    });

    test('Δ time is A − B: positive when A is behind', () {
      final length = comparison.axisLengthMeters;
      final delta = comparison.deltaSeries(0, length, 50);
      expect(delta.unit, 's');
      expect(delta.segments.first.first.y.abs(), lessThan(1.0));
      // Lap A at 30 m/s against lap B at 28 m/s: A is ahead, more and more.
      final last = delta.segments.last.last;
      expect(last.y, lessThan(-1.0));
      expect(
        last.y,
        closeTo(laps.timedLaps[0].durationSeconds - laps.timedLaps[1].durationSeconds, 0.3),
      );
      final swapped = LapComparison(comparison.b, comparison.a).deltaSeries(0, length, 50);
      expect(swapped.segments.last.last.y, greaterThan(1.0));
      expect(comparison.deltaSeries(10, 5, 50).reason, chartReasonInvalidRange);
      expect(comparison.deltaSeries(0, length, 1).hasData, isFalse);
      // A zoomed range is the same delta, on the range's own x.
      final zoomed = comparison.deltaSeries(length / 4, length / 2, 50);
      expect(zoomed.segments.first.first.x, closeTo(0, 0.05));
      expect(zoomed.segments.last.last.x, closeTo(1, 0.05));
      expect(zoomed.maximum, lessThanOrEqualTo(delta.maximum + 1e-9));
    });

    test('channels: brake upward, defaults, gear held', () {
      final length = comparison.axisLengthMeters;
      expect(
        comparison.channelSeries(0, 'longitudinalAcceleration', 0, length, 50).brakingUp,
        isTrue,
      );
      expect(comparison.channelSeries(0, 'velocity', 0, length, 50).brakingUp, isFalse);
      expect(comparison.channelSeries(0, 'velocity', 0, length, 50).unit, '');
      expect(comparison.preferredChannels, ['velocity', 'throttle', 'brake']);
      expect(comparison.defaultChartChannels, [deltaTimeChannel, 'velocity', 'throttle', 'brake']);
      expect(comparison.chartChannels.first, deltaTimeChannel);
      expect(comparison.channelSeries(0, 'velocity', 10, 5, 50).reason, chartReasonInvalidRange);
      expect(
        comparison.channelSeries(0, 'nothing', 0, length, 50).reason,
        chartReasonChannelMissing,
      );
      final speed = comparison.channelSeries(1, 'speed', 0, length, 50);
      expect(speed.minimum, closeTo(28 * 3.6, 1e-3));
      expect(nearestChartValue(speed, 0.5), closeTo(28 * 3.6, 1e-3));
      expect(nearestChartValue(ChartSeries.empty, 0.5), isNull);

      final geared = LapComparison(
        _lap(_with(session, extra: {'gear': ('', (t) => (t * 0.37).floorToDouble())}), laps, 0),
        _lap(_with(session, extra: {'gear': ('', (t) => (t * 0.37).floorToDouble())}), laps, 1),
      );
      for (final segment in geared.channelSeries(0, 'gear', 0, length, 400).segments) {
        for (final point in segment) {
          expect(point.y, point.y.roundToDouble());
        }
      }
    });

    test('colours the overlay map by recorded channels and the delta', () {
      final options = {for (final option in comparison.mapLayerOptions) option.id: option};
      expect(options.keys, [
        'speed',
        'delta',
        'lateralG',
        'longitudinalG',
        'throttle',
        'brake',
        'temperature',
      ]);
      expect(options['speed']!.available, isTrue);
      expect(options['delta']!.available, isTrue);
      expect(options['lateralG']!.available, isFalse);
      expect(options['temperature']!.available, isFalse);

      final speed = comparison.mapLayer('speed', 1);
      expect(speed.valid, isTrue);
      expect(speed.scale, 'sequential');
      expect(speed.provenance, 'measured');
      expect(speed.algorithm, mapLayerAlgorithm);
      expect(speed.trace.minimum, closeTo(28 * 3.6, 1e-3));
      final delta = comparison.mapLayer('delta', 0);
      expect(delta.valid, isTrue);
      expect(delta.diverging, isTrue);
      expect(delta.unit, 's');
      expect(delta.provenance, 'calculated');
      expect(delta.negativeLabel, 'A ahead');
      expect(delta.trace.minimum, lessThan(-1.0));
      expect(comparison.mapLayer('lateralG', 0).reason, 'channelMissing');
      expect(comparison.mapLayer('nonsense', 0).reason, 'unknownLayer');
      expect(comparison.mapLayer('speed', 2).valid, isFalse);
      expect(comparison.mapLayer('speed', 2).reason, 'pairNotReady');
    });
  });

  test('a channel one recording lacks is not shared and never borrowed', () {
    final full = rectangleSession([_constant(30), _constant(29)], pedals: true);
    final lacking = _with(
      rectangleSession([_constant(28), _constant(29)]),
      extra: {'oil_temp': ('C', (t) => 90 + t / 100), 'latacc-calc': ('G', (t) => t % 2 - 1)},
      aliases: {'lateralAcceleration': 'latacc-calc'},
      without: {'velocity'},
    );
    final comparison = LapComparison(
      _lap(full, deriveSourceLapSession(full), 0),
      _lap(lacking, deriveSourceLapSession(lacking), 0),
    );
    expect(comparison.availableChannels, contains('latitude'));
    expect(comparison.availableChannels, isNot(contains('velocity')));
    final length = comparison.axisLengthMeters;
    expect(length, greaterThan(0));
    expect(comparison.channelSeries(0, 'velocity', 0, length, 50).hasData, isTrue);
    final missing = comparison.channelSeries(1, 'velocity', 0, length, 50);
    expect(missing.reason, chartReasonChannelMissing);
    expect(missing.hasData, isFalse);
    expect(comparison.preferredChannels, isEmpty);
    expect(comparison.defaultChartChannels, [deltaTimeChannel]);

    final options = {for (final option in comparison.mapLayerOptions) option.id: option};
    expect(options['temperature:oil_temp']!.available, isTrue);
    expect(options.containsKey('temperature'), isFalse);
    expect(options['lateralG']!.available, isTrue);
    expect(comparison.mapLayer('lateralG', 0).reason, 'channelMissing');
    final lateral = comparison.mapLayer('lateralG', 1);
    expect(lateral.valid, isTrue);
    expect(lateral.provenance, 'calculated');
    expect(lateral.trace.minimum, lessThan(0));
    final temperature = comparison.mapLayer('temperature:oil_temp', 1);
    expect(temperature.valid, isTrue);
    expect(temperature.unit, 'C');
    expect(temperature.trace.minimum, greaterThanOrEqualTo(90));
    expect(comparison.mapLayer('temperature:oil_temp', 0).reason, 'channelMissing');
    expect(comparison.mapLayer('speed', 1).reason, 'channelMissing');
  });

  test('without lap A trace there is no axis, and nothing is invented', () {
    final session = rectangleSession([_constant(30), _constant(29)]);
    final laps = deriveSourceLapSession(session);
    final comparison = LapComparison(
      ComparisonLap(session: session, laps: laps, start: 1, end: 20, lapNumber: 99),
      _lap(session, laps, 0),
    );
    expect(comparison.axisLengthMeters, 0);
    expect(comparison.deltaSeries(0, 100, 50).hasData, isFalse);
    expect(comparison.channelSeries(0, 'speed', 0, 100, 50).reason, chartReasonChannelMissing);
    expect(comparison.positionAt(0, 10), isNull);
    expect(comparison.mapLayer('speed', 0).reason, 'noProgressAxis');
    expect(
      comparison.mapLayerOptions.firstWhere((option) => option.id == 'delta').available,
      isFalse,
    );
  });

  group('lap charts on a time axis', () {
    final session = rectangleSession([_constant(30), _constant(28)], pedals: true);
    final lap = deriveSourceLapSession(session).timedLaps.first;

    test('keep the range, unit, braking direction and reasons', () {
      final series = timeSeries(
        session,
        'speed',
        lap.startTelemetryTime,
        lap.endTelemetryTime,
        200,
      );
      expect(series.hasData, isTrue);
      expect(series.segments.first.first.x, greaterThanOrEqualTo(0));
      expect(series.segments.last.last.x, lessThanOrEqualTo(1));
      expect(series.minimum, closeTo(108, 1e-3));
      expect(series.brakingUp, isFalse);
      expect(
        timeSeries(session, 'longacc', lap.startTelemetryTime, lap.endTelemetryTime, 200).brakingUp,
        isTrue,
      );
      expect(timeSeries(session, 'nothing', 0, 10, 200).reason, chartReasonChannelMissing);
      expect(timeSeries(session, 'speed', double.nan, 10, 200).reason, chartReasonInvalidRange);
      final outside = timeSeries(session, 'speed', 10000, 10001, 200);
      expect(outside.hasData, isFalse);
      expect(outside.reason, isEmpty);
    });

    test('show speed, G and a pedal first, or the remembered choice', () {
      final withG = _with(
        session,
        extra: {'latacc': ('G', (t) => 0.0)},
        aliases: {'lateralAcceleration': 'latacc'},
      );
      expect(lapChartChannels(withG), ['velocity', 'latacc', 'longacc', 'throttle']);
      expect(lapChartChannels(withG, includePedals: false), ['velocity', 'latacc', 'longacc']);
      expect(lapChartChannels(_with(session, without: {'throttle'})), [
        'velocity',
        'longacc',
        'brake',
      ]);
      expect(lapChartChannels(withG, remembered: ['brake', 'nothing', 'brake', 'velocity']), [
        'brake',
        'velocity',
      ]);
      expect(lapChartChannels(withG, pending: 'brake'), ['brake', 'velocity', 'latacc', 'longacc']);
    });
  });
}
