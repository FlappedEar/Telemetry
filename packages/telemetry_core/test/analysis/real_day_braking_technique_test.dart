// Braking technique on a real day (FET-219), from its VBO files (10 Hz
// longitudinal G, OBD pedals drawn with straight lines at 10 Hz) and from its
// RaceChrono RCZ files (no G channel: deceleration from speed; OBD pedals at
// their own rate). Set FLAPPEDEAR_REAL_DAY to a folder of one day's
// recordings, each session as both; nothing from them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

DayTheoreticalBest _theoreticalBest(String folder, String extension) {
  final files =
      Directory(folder)
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith(extension))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  expect(files.length, greaterThanOrEqualTo(2));
  final runs = [
    for (final (index, file) in files.indexed)
      () {
        final session = withEffectiveSpeedUnits(loadRecording(file.path));
        return DayRunInput(
          runId: 'run${index + 1}',
          name: 'Session ${index + 1}',
          contentSha256: '${index + 1}'.padLeft(64, '0'),
          session: session,
          laps: deriveSourceLapSession(session),
        );
      }(),
  ];
  return dayTheoreticalBest(analyzeDay(runs), {
    for (final run in runs) run.runId: OutingRun(run.session, run.laps),
  }, random: Random(1));
}

String _value(BrakingTechniqueTypical typical, int digits, String unit) => typical.median == null
    ? 'not known (${typical.reason})'
    : '${typical.median!.toStringAsFixed(digits)} $unit (${typical.laps} laps)';

String _rate(double? hz) => hz == null ? '—' : '${hz.toStringAsFixed(1)} Hz';

void _report(String label, DayTheoreticalBest result) {
  print('== $label: ${result.corners.length} corners');
  for (final corner in result.corners) {
    final technique = corner.brakingTechnique;
    print(
      '${corner.name}: ${technique.source.isEmpty ? '—' : technique.source} '
      '${_rate(technique.rateHz)}, braking on ${technique.lapsBraking} of '
      '${technique.lapsMeasured} laps'
      '${technique.unavailableReason.isEmpty ? '' : ' (${technique.unavailableReason})'}',
    );
    print(
      '  hit ${_value(technique.hit, 2, 'g/s')}; peak ${_value(technique.peak, 2, 'g')} '
      'at ${_value(technique.peakFraction, 2, 'of zone')}',
    );
    print(
      '  trail ${_value(technique.trailSeconds, 2, 's')}, ${_value(technique.trailMeters, 0, 'm')} '
      '(lateral ${_rate(technique.lateralRateHz)})',
    );
    print(
      '  release ${_value(technique.release, 2, 'g/s')}; brake to throttle '
      '${_value(technique.brakeToThrottle, 2, 's')} (throttle ${_rate(technique.throttleRateHz)})',
    );
    print(
      '  pedal: brake ${_rate(technique.brakeRateHz)}, '
      '${technique.laps.isEmpty ? '' : technique.laps.first.$2.pedalReason}',
    );
  }
  final day = summarizeBrakingTechniqueDay([
    for (final corner in result.corners) corner.brakingTechnique,
  ]);
  print(
    'Day: ${day.cornersBraked} of ${day.corners} corners braked, hit ${day.hit}, '
    'release ${day.release}, trail ${day.trailSeconds}, brake to throttle ${day.brakeToThrottle}',
  );
}

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the VBO day: from longitudinal G, the OBD brake refused for ramps', () {
    final result = _theoreticalBest(folder, '.vbo');
    expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
    _report('VBO', result);
    final braked = [
      for (final corner in result.corners)
        if (corner.brakingTechnique.unavailableReason.isEmpty) corner.brakingTechnique,
    ];
    expect(braked, isNotEmpty);
    for (final technique in braked) {
      expect(technique.source, brakingTechniqueFromG);
      expect(technique.unitAssumed, isTrue); // longacc-calc declares no unit
      // The brake is OBD, written at 10 Hz but changing about twice a second.
      expect(technique.brakeRateHz, lessThan(4));
      expect(technique.pedalApplication.median, isNull);
      for (final (_, lap) in technique.laps) {
        if (lap.measured) expect(lap.pedalReason, brakingTechniqueBrakeTooSlow);
      }
    }
  }, skip: skip);

  test('the RCZ day: from speed, the OBD brake refused for ramps', () {
    final result = _theoreticalBest(folder, '.rcz');
    expect(result.state, DayTheoreticalBestState.ready, reason: result.message);
    _report('RCZ', result);
    final braked = [
      for (final corner in result.corners)
        if (corner.brakingTechnique.unavailableReason.isEmpty) corner.brakingTechnique,
    ];
    expect(braked, isNotEmpty);
    for (final technique in braked) {
      expect(technique.source, brakingTechniqueFromSpeed);
      expect(technique.brakeRateHz, lessThan(4));
      expect(technique.pedalApplication.median, isNull);
    }
  }, skip: skip);
}
