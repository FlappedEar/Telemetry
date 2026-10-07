// A reference lap from another session of a real day (FET-175): one
// session's VBO is today's day, another session's VBO is the reference,
// timed on today's line and compared segment by segment. Set
// FLAPPEDEAR_REAL_DAY to a folder of one day's recordings; nothing from
// them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

String _time(double seconds) {
  final rounded = (seconds * 1000).round() / 1000;
  final minutes = rounded ~/ 60;
  final rest = rounded - minutes * 60;
  return minutes > 0
      ? '$minutes:${rest.toStringAsFixed(3).padLeft(6, '0')}'
      : '${rest.toStringAsFixed(3)} s';
}

String _delta(double seconds) => '${seconds >= 0 ? '+' : '−'}${seconds.abs().toStringAsFixed(3)}';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test("another session's best lap is a reference for today's laps", () {
    final files =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.vbo'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    expect(files.length, greaterThanOrEqualTo(2));

    // Today: the last session alone.
    final todaySession = loadRecording(files.last.path);
    final todayLaps = deriveSourceLapSession(todaySession);
    final analysis = analyzeDay([
      DayRunInput(
        runId: 'run1',
        name: 'Session 1',
        contentSha256: '1'.padLeft(64, '0'),
        session: todaySession,
        laps: todayLaps,
      ),
    ]);
    final group = analysis.chosenGroup!;
    final best = group.ranking!.bestOfDay!;
    final gate = todayLaps.selectedStartGate!;

    // The reference: the other session with the fastest lap on today's line.
    ReferenceTiming? reference;
    var referenceFile = '';
    for (final file in files.take(files.length - 1)) {
      final timing = timeReferenceLaps([
        ReferenceRecording(label: file.uri.pathSegments.last, session: loadRecording(file.path)),
      ], gate);
      expect(timing.refusal, ReferenceRefusal.none, reason: file.path);
      if (reference == null ||
          timing.fastest!.durationSeconds < reference.fastest!.durationSeconds) {
        reference = timing;
        referenceFile = file.uri.pathSegments.last;
      }
    }
    final lap = reference!.fastest!;

    // Segments: the day's automatic ones from today's best lap.
    final segments = automaticTrackSegments(
      documentRuns: const [],
      groupId: group.id,
      storedSegments: null,
      session: todaySession,
      laps: todayLaps,
      lapNumber: best.lapNumber,
      startTime: best.start,
      endTime: best.end,
      random: Random(1),
    )!;
    final compared = ReferenceLapComparison(
      today: ComparisonLap(
        session: todaySession,
        laps: todayLaps,
        start: best.start,
        end: best.end,
        lapNumber: best.lapNumber,
      ),
      timing: reference,
      lap: lap,
      referenceSession: reference.recordings[lap.recordingIndex].session,
      segmentation: ComparisonSegmentation(shared: approvedSegmentation(segments, group.id)),
    );
    final times = compared.segmentTimes();
    final units = referenceChannelUnits(
      todaySession,
      reference.recordings[lap.recordingIndex].session,
      'speed',
    );

    print(
      'Today: ${files.last.uri.pathSegments.last}, best LAP ${best.lapNumber} '
      '${_time(best.durationSeconds)}',
    );
    print(
      'Reference: $referenceFile, lap ${lap.lapNumber}, ${_time(lap.durationSeconds)} '
      '(${reference.candidates.length} laps timed on today\'s line, nearest '
      '${reference.nearestGateDistanceMeters!.toStringAsFixed(1)} m)',
    );
    print('Lap Δ (today − reference): ${_delta(compared.lapDeltaSeconds)}');
    print(
      'Speed units: today ${units.today.unit.isEmpty ? '(none)' : units.today.unit}'
      '${units.today.assumed ? ' assumed' : ''}, reference '
      '${units.reference.unit.isEmpty ? '(none)' : units.reference.unit}'
      '${units.reference.assumed ? ' assumed' : ''}, comparable ${units.comparable}',
    );
    for (final time in times) {
      print(
        '  ${time.segment.name.padRight(12)} ${time.segment.type.padRight(8)} '
        'today ${time.todaySeconds?.toStringAsFixed(3) ?? '—'}  '
        'ref ${time.referenceSeconds?.toStringAsFixed(3) ?? '—'}  '
        'Δ ${time.deltaSeconds == null ? time.unavailableReason : _delta(time.deltaSeconds!)}',
      );
    }

    expect(compared.comparison.axis.valid, isTrue);
    expect(times, isNotEmpty);
    expect(times.every((time) => time.deltaSeconds != null), isTrue);
    // The segments add up to the lap.
    expect(
      times.fold<double>(0, (sum, time) => sum + time.deltaSeconds!),
      closeTo(compared.lapDeltaSeconds, 0.05),
    );
    // The day's best lap (1:49.898) is in an earlier session, and timed on
    // the last session's line it keeps its time; the last session's best
    // is 1:51.238.
    expect(lap.durationSeconds, closeTo(109.898, 0.005));
    expect(best.durationSeconds, closeTo(111.238, 0.005));
    expect(compared.lapDeltaSeconds, closeTo(1.340, 0.01));
    expect(units.comparable, isTrue);
  }, skip: skip);
}
