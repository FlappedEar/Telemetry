// A reference lap from another session of a real day (FET-175): one
// session's VBO is today's day, another session's VBO, or its RCZ (with
// east-positive longitudes), is the reference, timed on today's line and
// compared segment by segment. Set
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

  test("another session's best lap, as VBO or RCZ, is a reference for today's laps", () {
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
    final line = referenceLineOf(todaySession, todayLaps, best.lapNumber)!;
    expect(line.westPositive, isTrue);
    expect(line.route, isNotNull);

    // The reference: the other session with the fastest lap on today's line.
    ReferenceTiming? reference;
    var referenceFile = '';
    final dropped = <String>[];
    for (final file in files.take(files.length - 1)) {
      final timing = timeReferenceLaps([
        ReferenceRecording(label: file.uri.pathSegments.last, session: loadRecording(file.path)),
      ], line);
      expect(timing.refusal, ReferenceRefusal.none, reason: file.path);
      // Without today's route: which laps the route check drops.
      final unchecked = timeReferenceLaps([
        ReferenceRecording(label: file.uri.pathSegments.last, session: loadRecording(file.path)),
      ], ReferenceLine(gate: line.gate, westPositive: line.westPositive));
      final kept = {for (final lap in timing.candidates) lap.lapNumber};
      for (final lap in unchecked.candidates) {
        if (!kept.contains(lap.lapNumber)) {
          dropped.add('${file.uri.pathSegments.last} lap ${lap.lapNumber}');
        }
      }
      if (reference == null ||
          timing.fastest!.durationSeconds < reference.fastest!.durationSeconds) {
        reference = timing;
        referenceFile = file.uri.pathSegments.last;
      }
    }

    // The route check drops one lap: session 2's lap 4, which the day ranks
    // apart too, as following a different recorded route.
    print('Off today\'s route: $dropped');
    expect(dropped, hasLength(1));
    expect(dropped.single, allOf(contains('_112959_'), endsWith(' lap 4')));

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
    final segmentation = ComparisonSegmentation(shared: approvedSegmentation(segments, group.id));
    final today = ComparisonLap(
      session: todaySession,
      laps: todayLaps,
      start: best.start,
      end: best.end,
      lapNumber: best.lapNumber,
    );

    ReferenceLapComparison compare(ReferenceTiming timing, String name) {
      final lap = timing.fastest!;
      final session = timing.recordings[lap.recordingIndex].session;
      final compared = ReferenceLapComparison(
        today: today,
        timing: timing,
        lap: lap,
        referenceSession: session,
        segmentation: segmentation,
      );
      final times = compared.segmentTimes();
      final units = referenceChannelUnits(todaySession, session, 'speed');
      print(
        'Reference: $name, lap ${lap.lapNumber}, ${_time(lap.durationSeconds)} '
        '(${timing.candidates.length} laps timed on today\'s line, nearest '
        '${timing.nearestGateDistanceMeters!.toStringAsFixed(1)} m, coverage '
        '${(compared.coverage * 100).toStringAsFixed(1)} %)',
      );
      print('Lap Δ (today − reference): ${_delta(compared.lapDeltaSeconds!)}');
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
      expect(compared.comparison.axis.valid, isTrue, reason: name);
      expect(compared.coverage, greaterThan(referenceMinimumCoverage), reason: name);
      expect(times, isNotEmpty, reason: name);
      expect(times.every((time) => time.deltaSeconds != null), isTrue, reason: name);
      // The segments add up to the lap.
      expect(
        times.fold<double>(0, (sum, time) => sum + time.deltaSeconds!),
        closeTo(compared.lapDeltaSeconds!, 0.05),
        reason: name,
      );
      expect(units.comparable, isTrue, reason: name);
      return compared;
    }

    print(
      'Today: ${files.last.uri.pathSegments.last}, best LAP ${best.lapNumber} '
      '${_time(best.durationSeconds)}',
    );
    final fromVbo = compare(reference!, referenceFile);
    // The day's best lap (1:49.898) is in an earlier session, and timed on
    // the last session's line it keeps its time; the last session's best
    // is 1:51.238.
    expect(fromVbo.lap.durationSeconds, closeTo(109.898, 0.005));
    expect(best.durationSeconds, closeTo(111.238, 0.005));
    expect(fromVbo.lapDeltaSeconds, closeTo(1.340, 0.01));

    // The same session's RCZ: east-positive longitudes, mirrored into the
    // VBO day's frame, the same lap within the two loggers' timing.
    final rczPath = '${referenceFile.substring(0, referenceFile.length - 4)}.rcz';
    final rcz = File('$folder/$rczPath');
    expect(rcz.existsSync(), isTrue, reason: rcz.path);
    final rczSession = loadRecording(rcz.path);
    expect(longitudeWestPositive(rczSession), isFalse);
    final rczTiming = timeReferenceLaps([
      ReferenceRecording(label: rczPath, session: rczSession),
    ], line);
    expect(rczTiming.refusal, ReferenceRefusal.none);
    final fromRcz = compare(rczTiming, rczPath);
    expect(fromRcz.lap.lapNumber, fromVbo.lap.lapNumber);
    expect(fromRcz.lap.durationSeconds, closeTo(109.898, 0.05));
    expect(fromRcz.lapDeltaSeconds, closeTo(1.340, 0.05));
  }, skip: skip);
}
