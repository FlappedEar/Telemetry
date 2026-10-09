// Port of FlappedEar Overlays native/tests/MapLayersTests.cpp (revision
// d4d1039): a value sampled along a lap's progress and placed on its racing
// line, never bridged across a GPS gap, a channel gap or an implausible or
// placeholder sample.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _dt = 0.1; // 10 Hz
const _sampleCount = 101; // t = 0 .. 10 s
const _metersPerSecond = 20.0;

bool _always(double t) => true;

TelemetryChannel _channel(
  String name,
  String unit,
  double Function(double t) value, [
  bool Function(double t) present = _always,
]) {
  final times = <double>[], values = <double>[];
  for (var k = 0; k < _sampleCount; ++k) {
    final t = k * _dt;
    if (!present(t)) continue;
    times.add(t);
    values.add(value(t));
  }
  return TelemetryChannel(
    name: name,
    unit: unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
}

// A straight run east at 20 m/s: GPS, speed and a temperature channel.
TelemetrySession _straightRun(
  double Function(double t) temperature, {
  bool Function(double t) gpsPresent = _always,
  TelemetryChannel? speed,
  String temperatureUnit = 'C',
}) => TelemetrySession(
  duration: 10,
  startTime: 0,
  metadata: const {},
  channels: {
    'lat': _channel('lat', 'deg', (t) => 50.0, gpsPresent),
    'lon': _channel('lon', 'deg', (t) => 19.0 + t * _metersPerSecond / 71500.0, gpsPresent),
    'velocity': speed ?? _channel('velocity', 'km/h', (t) => 60.0 + t),
    'oil_temp': _channel('oil_temp', temperatureUnit, temperature),
  },
  aliases: const {'latitude': 'lat', 'longitude': 'lon', 'speed': 'velocity'},
  warnings: const [],
  timingGates: const [],
  sampleCount: _sampleCount,
);

// The lap's progress: 20 m per second, one segment per stretch of GPS.
List<ProgressSegment> _straightTrace([bool Function(double t) present = _always]) {
  final trace = [ProgressSegment()];
  for (var k = 0; k < _sampleCount; ++k) {
    final t = k * _dt;
    if (!present(t)) {
      if (trace.last.samples.isNotEmpty) trace.add(ProgressSegment());
      continue;
    }
    trace.last.samples.add(ProjectedSample(t, progressMeters: t * _metersPerSecond, valid: true));
  }
  if (trace.last.samples.isEmpty) trace.removeLast();
  return trace;
}

void main() {
  test('samples a channel along progress', () {
    final session = _straightRun((t) => 90.0);
    final segments = channelAlongProgress(session, 'speed', _straightTrace(), 200.0, 21);
    expect(segments, hasLength(1));
    expect(segments.first, hasLength(21));
    // 100 m is t = 5 s, where speed is 65 km/h.
    expect(segments.first[10].progress, 100.0);
    expect(segments.first[10].value, closeTo(65.0, 1e-4));
    expect(segments.first.last.value, closeTo(70.0, 1e-4));
  });

  test('never bridges channel or GPS gaps', () {
    // Speed missing from 4 to 6 s: the layer splits there.
    final session = _straightRun(
      (t) => 90.0,
      speed: _channel('velocity', 'km/h', (t) => 60.0 + t, (t) => t < 4.0 || t > 6.0),
    );
    final channelGap = channelAlongProgress(session, 'speed', _straightTrace(), 200.0, 41);
    expect(channelGap, hasLength(2));
    expect(channelGap[0].last.progress, lessThan(80.0));
    expect(channelGap[1].first.progress, greaterThan(120.0));

    // GPS (so progress) missing from 3 to 5 s: no time there, so no value.
    bool gpsPresent(double t) => t < 3.0 || t > 5.0;
    final trace = _straightTrace(gpsPresent);
    expect(trace, hasLength(2));
    final gpsGap = channelAlongProgress(
      _straightRun((t) => 90.0, gpsPresent: gpsPresent),
      'speed',
      trace,
      200.0,
      41,
    );
    expect(gpsGap, hasLength(2));
    for (final segment in gpsGap) {
      for (final point in segment) {
        expect(point.progress < 60.0 + 1e-9 || point.progress > 100.0 - 1e-9, isTrue);
      }
    }
  });

  test('excludes implausible and placeholder temperatures', () {
    // A 90 °C oil temperature with a logger placeholder zero at 3 s and an
    // implausible 900 °C spike at 7 s: both end the line, never drawn.
    final session = _straightRun((t) {
      if ((t - 3.0).abs() < 1e-6) return 0.0;
      if ((t - 7.0).abs() < 1e-6) return 900.0;
      return 90.0;
    });
    const policy = temperatureSummaryPolicy;
    final segments = channelAlongProgress(session, 'oil_temp', _straightTrace(), 200.0, 201);
    final filtered = channelAlongProgress(
      session,
      'oil_temp',
      _straightTrace(),
      200.0,
      201,
      policy,
    );
    expect(segments, hasLength(1)); // unfiltered: one line through the artifacts
    expect(filtered, hasLength(3));
    for (final segment in filtered) {
      for (final point in segment) {
        expect(point.value, 90.0);
      }
    }
    final channel = session.channels['oil_temp']!;
    expect(zeroIsPlaceholder(channel, policy), isTrue);
    expect(plausibleChannelValue(channel, 2.95, policy, true), isNull);
    expect(plausibleChannelValue(channel, 7.0, policy, true), isNull);
    expect(plausibleChannelValue(channel, 5.05, policy, true), 90.0);
    // A channel that is typically near zero keeps its zeros.
    final cold = _straightRun((t) => 0.0);
    expect(zeroIsPlaceholder(cold.channels['oil_temp']!, policy), isFalse);
    expect(
      channelAlongProgress(cold, 'oil_temp', _straightTrace(), 200.0, 11, policy),
      hasLength(1),
    );
  });

  test('the temperature limits are the same temperatures in °F and K, and unread in others', () {
    // 90 °C with a logger placeholder zero at 3 s and a 900 °C spike at 7 s,
    // as the sensor writes it in each unit (FET-288).
    for (final (unit, convert, shown) in [
      ('C', (double c) => c, 90.0),
      ('°F', (double c) => c * 1.8 + 32, 194.0),
      ('K', (double c) => c + 273.15, 363.15),
    ]) {
      final session = _straightRun((t) {
        if ((t - 3.0).abs() < 1e-6) return 0.0;
        if ((t - 7.0).abs() < 1e-6) return convert(900.0);
        return convert(90.0);
      }, temperatureUnit: unit);
      final filtered = channelAlongProgress(
        session,
        'oil_temp',
        _straightTrace(),
        200.0,
        201,
        temperatureSummaryPolicy,
      );
      expect(filtered, hasLength(3), reason: unit);
      for (final segment in filtered) {
        for (final point in segment) {
          expect(point.value, closeTo(shown, 1e-3), reason: unit);
        }
      }
    }
    final unread = _straightRun((t) => 90.0, temperatureUnit: 'rankine');
    expect(
      channelAlongProgress(
        unread,
        'oil_temp',
        _straightTrace(),
        200.0,
        21,
        temperatureSummaryPolicy,
      ),
      isEmpty,
    );
  });

  test('places values on the racing line', () {
    final session = _straightRun((t) => 90.0);
    final geometry = sessionMapGeometry(session);
    expect(geometry.valid, isTrue);
    final trace = _straightTrace();
    final layer = placeOnMap(
      session,
      trace,
      geometry,
      channelAlongProgress(session, 'speed', trace, 200.0, 21),
    );
    expect(layer.polylines, hasLength(1));
    expect(layer.polylines.first, hasLength(21));
    expect(layer.minimum, closeTo(60.0, 1e-4));
    expect(layer.maximum, closeTo(70.0, 1e-4));
    // Heading east: x grows with progress, at the lap's own position.
    final line = layer.polylines.first;
    for (var index = 1; index < line.length; ++index) {
      expect(line[index].x, greaterThan(line[index - 1].x));
    }
    final expected = mapPointAt(session, 5.0, geometry)!;
    expect(line[10].x, closeTo(expected.x, 1e-6));
    expect(line[10].y, closeTo(expected.y, 1e-6));
    // Non-finite values and positions the lap does not cover split the line.
    final values = [
      <ProgressValue>[
        (progress: 0.0, value: 1.0),
        (progress: 50.0, value: 2.0),
        (progress: 100.0, value: double.nan),
        (progress: 150.0, value: 3.0),
        (progress: 190.0, value: 4.0),
        (progress: 400.0, value: 5.0),
      ],
    ];
    final split = placeOnMap(session, trace, geometry, values);
    expect(split.polylines, hasLength(2));
    expect(split.maximum, 4.0);
  });

  test('rejects missing channels and bad input', () {
    final session = _straightRun((t) => 90.0);
    expect(channelAlongProgress(session, 'brake', _straightTrace(), 200.0, 21), isEmpty);
    expect(channelAlongProgress(session, 'speed', _straightTrace(), double.nan, 21), isEmpty);
    expect(channelAlongProgress(session, 'speed', _straightTrace(), 0.0, 21), isEmpty);
    expect(channelAlongProgress(session, 'speed', const [], 200.0, 21), isEmpty);
    // The point count is bounded.
    final many = channelAlongProgress(session, 'speed', _straightTrace(), 200.0, 1000000);
    expect(many.first, hasLength(4000));
    expect(
      placeOnMap(session, _straightTrace(), const MapGeometry(), [
        [(progress: 0.0, value: 1.0), (progress: 10.0, value: 2.0)],
      ]).polylines,
      isEmpty,
    );
    // A channel whose timestamps and values differ in length cannot be built
    // (FET-202).
    expect(
      () => TelemetryChannel(
        name: 'x',
        timestamps: Float64List.fromList([0.0, 1.0]),
        values: Float32List.fromList([1.0]),
      ),
      throwsArgumentError,
    );
  });

  test('normalizes two laps to one map, east-positive', () {
    final session = _straightRun((t) => 90.0);
    final shared = sharedMapGeometry(session, 0, 5, session, 5, 10);
    final whole = sessionMapGeometry(session);
    expect(shared.valid, isTrue);
    expect(shared.width, closeTo(whole.width, 1e-3));
    final first = mapTrace(session, 0, 5, shared);
    final second = mapTrace(session, 5, 10, shared);
    expect(first.single.first.x, closeTo(0.0, 1e-3));
    expect(second.single.last.x, closeTo(1.0, 1e-3));
    expect(first.single.first.y, closeTo(0.5, 1e-9));
    // A west-positive recording is drawn the same way round.
    final west = TelemetrySession(
      duration: 10,
      startTime: 0,
      metadata: const {'gpsLongitudeConvention': 'west-positive'},
      channels: {
        'lat': _channel('lat', 'deg', (t) => 50.0),
        'lon': _channel('lon', 'deg', (t) => 19.0 - t * _metersPerSecond / 71500.0),
      },
      aliases: const {'latitude': 'lat', 'longitude': 'lon'},
      warnings: const [],
      timingGates: const [],
      sampleCount: _sampleCount,
    );
    final mirrored = sessionMapGeometry(west);
    expect(mirrored.longitudeIsWestPositive, isTrue);
    expect(mapPointAt(west, 10, mirrored)!.x, closeTo(1.0, 1e-3));
    expect(mapPointAt(west, 11, mirrored), isNull);
  });

  test('maps a normalized position back to degrees, east-positive', () {
    final session = _straightRun((t) => 90.0);
    final geometry = sessionMapGeometry(session);
    for (final time in [0.0, 3.5, 10.0]) {
      final point = mapPointAt(session, time, geometry)!;
      final coordinate = mapPointCoordinate(point.x, point.y, geometry)!;
      expect(coordinate.latitudeDegrees, closeTo(session.valueAt('latitude', time)!, 1e-9));
      expect(coordinate.longitudeDegrees, closeTo(session.valueAt('longitude', time)!, 1e-9));
    }
    expect(mapPointCoordinate(0.5, 0.5, const MapGeometry()), isNull);
    expect(mapPointCoordinate(double.nan, 0.5, geometry), isNull);

    // A west-positive recording comes back with an east-positive longitude.
    final west = TelemetrySession(
      duration: 10,
      startTime: 0,
      metadata: const {'gpsLongitudeConvention': 'west-positive'},
      channels: {
        'lat': _channel('lat', 'deg', (t) => 50.0),
        'lon': _channel('lon', 'deg', (t) => 19.0 - t * _metersPerSecond / 71500.0),
      },
      aliases: const {'latitude': 'lat', 'longitude': 'lon'},
      warnings: const [],
      timingGates: const [],
      sampleCount: _sampleCount,
    );
    final mirrored = sessionMapGeometry(west);
    for (final time in [0.0, 6.0]) {
      final point = mapPointAt(west, time, mirrored)!;
      final coordinate = mapPointCoordinate(point.x, point.y, mirrored)!;
      expect(coordinate.latitudeDegrees, closeTo(50.0, 1e-9));
      expect(coordinate.longitudeDegrees, closeTo(-west.valueAt('longitude', time)!, 1e-9));
    }
  });
}
