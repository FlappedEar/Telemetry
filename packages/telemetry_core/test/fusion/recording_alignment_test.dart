// Port of Overlays native/tests/RecordingAlignmentTests.cpp (d4d1039):
// deterministic offsets and drift are measured; periodic, featureless or
// short signals stay ambiguous or insufficient; a declared logger clock that
// disagrees with the measurement is a conflict, never silently resolved.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// A track day's speed on the absolute clock: a 110 s lap shape, slower
// changes across laps, a fixed wobble, and the events that make a session
// non-periodic: the pit-lane exit, a yellow-flag lap and the in-lap.
double _daySpeed(double t) {
  final lap = 2.0 * math.pi * t / 110.0;
  final racing =
      90.0 +
      35.0 * math.sin(lap) +
      15.0 * math.sin(3.0 * lap + 0.4) +
      10.0 * math.sin(0.013 * t) +
      6.0 * math.sin(0.0071 * t + 1.0) +
      2.0 * math.sin(1.7 * t) * math.sin(0.031 * t);
  if (t < 120.0) return math.min(racing, 60.0); // pit-lane limit
  if (t > 800.0 && t < 910.0) return racing * 0.6; // yellow flag
  if (t > 1650.0) return racing * 0.7; // in-lap
  return racing;
}

TelemetrySession _recording(
  double start,
  double end,
  double rateHz,
  double Function(double) speedAt, [
  int? startMilliseconds,
]) {
  final times = <double>[], values = <double>[];
  for (var time = start; time <= end + 1e-9; time += 1.0 / rateHz) {
    times.add(time);
    values.add(speedAt(time));
  }
  return TelemetrySession(
    duration: end - start,
    startTime: 0.0,
    metadata: {if (startMilliseconds != null) 'firstTimestampMilliseconds': '$startMilliseconds'},
    channels: {
      'velocity': TelemetryChannel(
        name: 'velocity',
        unit: 'km/h',
        timestamps: Float64List.fromList(times),
        values: Float32List.fromList(values),
      ),
    },
    aliases: const {'speed': 'velocity'},
    warnings: const [],
    timingGates: const [],
    sampleCount: values.length,
  );
}

// The alternative logger's clock:
// primaryTime = candidateTime + offset + drift * candidateTime.
TelemetrySession _candidateOf(
  double offset,
  double driftPpm, [
  double length = 1500.0,
  int? startMilliseconds,
]) => _recording(
  0.0,
  length,
  5.0,
  (c) => _daySpeed(c + offset + driftPpm * 1e-6 * c),
  startMilliseconds,
);

TelemetrySession _primaryDay([int? startMilliseconds]) =>
    _recording(0.0, 1800.0, 5.0, _daySpeed, startMilliseconds);

const _start = 1756450000000;

void main() {
  test('aligns a shifted recording', () {
    // Laps repeat, so the speed traces also match one lap away: measured
    // alone this is ambiguous, however well the offset is measured.
    final measuredOnly = alignRecordings(_primaryDay(), _candidateOf(123.4, 0.0));
    expect(measuredOnly.status, alignmentAmbiguous);
    expect(measuredOnly.reason, 'repeatedMatch');
    expect((measuredOnly.offset! - 123.4).abs(), lessThan(0.1));
    expect(measuredOnly.driftPpm, isNull); // identical clocks: none claimed
    expect(measuredOnly.uncertaintySeconds!, lessThanOrEqualTo(0.3));
    expect(measuredOnly.usedWindows, greaterThanOrEqualTo(3));
    expect(measuredOnly.correlation, greaterThan(0.95));
    expect(measuredOnly.overlapSeconds, greaterThan(1400.0));
    expect(measuredOnly.declaredOffset, isNull);

    // The loggers' clocks (RCZ always states one) choose the right lap.
    final declared = alignRecordings(
      _primaryDay(_start),
      _candidateOf(123.4, 0.0, 1500.0, _start + 123900),
    );
    expect(declared.status, alignmentAligned);
    expect(declared.resolvedByDeclaredClock, isTrue);
    expect(declared.declaredOffset, 123.9);
    expect((declared.offset! - 123.4).abs(), lessThan(0.1)); // measured, not declared

    // A session whose traces never repeat is decided by the match alone.
    double unique(double t) =>
        80.0 + 30.0 * math.sin(0.002 * t * t / 10.0) + 10.0 * math.sin(0.05 * t);
    final chirp = alignRecordings(
      _recording(0.0, 900.0, 10.0, unique),
      _recording(0.0, 700.0, 5.0, (c) => unique(c + 55.5)),
    );
    expect(chirp.status, alignmentAligned);
    expect(chirp.resolvedByDeclaredClock, isFalse);
    expect((chirp.offset! - 55.5).abs(), lessThan(0.1));
  });

  test('measures clock drift', () {
    // 400 ppm: the alternative clock gains 0.6 s over 25 minutes.
    final result = alignRecordings(
      _primaryDay(_start),
      _candidateOf(40.0, 400.0, 1500.0, _start + 40000),
    );
    expect(result.status, alignmentAligned);
    expect((result.driftPpm! - 400.0).abs(), lessThan(120.0), reason: '${result.driftPpm}');
    expect((result.offset! - 40.0).abs(), lessThan(0.15));
    // Beyond what a logger clock plausibly does: reviewed, not approved.
    final implausible = alignRecordings(
      _primaryDay(_start),
      _candidateOf(40.0, 400.0, 1500.0, _start + 40000),
      options: const RecordingAlignmentOptions(maximumPlausibleDriftPpm: 100.0),
    );
    expect(implausible.status, alignmentAmbiguous);
    expect(implausible.reason, 'implausibleDrift');
  });

  test('keeps periodic and featureless signals ambiguous', () {
    // Identical 20 s cycles: every cycle matches equally well.
    double periodic(double t) => 80.0 + 30.0 * math.sin(2.0 * math.pi * t / 20.0);
    final cyclic = alignRecordings(
      _recording(0.0, 600.0, 10.0, periodic),
      _recording(0.0, 500.0, 5.0, (c) => periodic(c + 37.0)),
    );
    expect(cyclic.status, alignmentAmbiguous);
    expect(cyclic.reason, 'repeatedMatch');
    expect(cyclic.peakUniqueness, lessThan(0.1));
    // A constant speed carries no timing evidence at all.
    final flat = alignRecordings(
      _recording(0.0, 600.0, 10.0, (_) => 100.0),
      _recording(0.0, 500.0, 5.0, (_) => 100.0),
    );
    expect(flat.status, anyOf(alignmentAmbiguous, alignmentInsufficient));
  });

  test('reports a declared clock conflict', () {
    // The loggers' clocks agree with the speed traces.
    final agreeing = alignRecordings(
      _primaryDay(_start),
      _candidateOf(123.4, 0.0, 1500.0, _start + 123400),
    );
    expect(agreeing.status, alignmentAligned);
    expect(agreeing.declaredOffset, 123.4);
    // The candidate logger's clock is a minute off: both are reported, the
    // alignment is not approved.
    final conflicting = alignRecordings(
      _primaryDay(_start),
      _candidateOf(123.4, 0.0, 1500.0, _start + 183400),
    );
    expect(conflicting.status, alignmentConflicting);
    expect(conflicting.reason, 'declaredClockDisagrees');
    expect(conflicting.declaredOffset, 183.4);
    expect((conflicting.offset! - 123.4).abs(), lessThan(0.1));
  });

  test('refuses insufficient evidence', () {
    final noSpeed = TelemetrySession(
      duration: 0,
      startTime: 0,
      metadata: const {},
      channels: const {},
      aliases: const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: 0,
    );
    final missing = alignRecordings(_primaryDay(), noSpeed);
    expect(missing.status, alignmentInsufficient);
    expect(missing.reason, 'noSpeed');
    expect(missing.offset, isNull);
    // Fifteen seconds of overlap is below the sync engine's minimum.
    final brief = alignRecordings(_primaryDay(), _candidateOf(200.0, 0.0, 15.0));
    expect(brief.status, isNot(alignmentAligned));
    // Too few samples for the engine: insufficient with its reason.
    final tiny = alignRecordings(_primaryDay(), _recording(0.0, 1.0, 5.0, _daySpeed));
    expect(tiny.status, alignmentInsufficient);
    expect(tiny.reason, isNotEmpty);
  });

  test('cancels', () {
    expect(
      () => alignRecordings(_primaryDay(), _candidateOf(10.0, 0.0), cancelled: () => true),
      throwsA(isA<OperationCancelled>()),
    );
  });

  test('sync confidence levels', () {
    expect(syncConfidenceLevel(0.75), SyncConfidenceLevel.high);
    expect(syncConfidenceLevel(0.5), SyncConfidenceLevel.medium);
    expect(syncConfidenceLevel(0.2), SyncConfidenceLevel.low);
    expect(syncConfidenceLevel(double.nan), SyncConfidenceLevel.low);
    expect(shouldAutoApplySyncCandidate(const SyncCandidate(confidence: 0.8)), isTrue);
    expect(shouldAutoApplySyncCandidate(const SyncCandidate(confidence: 0.74)), isFalse);
    expect(
      shouldAutoApplySyncCandidate(const SyncCandidate(confidence: 0.9, timeScale: 0.0)),
      isFalse,
    );
  });

  test('the sync engine refuses short signals and missing speed', () {
    final day = _primaryDay();
    expect(
      () => synchronizeTelemetry(_recording(0.0, 1.0, 5.0, _daySpeed), day),
      throwsA(isA<SyncError>()),
    );
    final noSpeed = TelemetrySession(
      duration: 0,
      startTime: 0,
      metadata: const {},
      channels: const {},
      aliases: const {},
      warnings: const [],
      timingGates: const [],
      sampleCount: 0,
    );
    expect(() => synchronizeTelemetry(noSpeed, day), throwsA(isA<SyncError>()));
  });
}
