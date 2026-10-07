// The projection constants of track_progress.dart measured on a real day
// (FET-215): every timed lap of the day projected on an axis built from
// each session's fastest lap, and the quantity each constant bounds
// measured from the geometry. Set FLAPPEDEAR_REAL_DAY to a folder of one
// day's VBO files; nothing from them is written anywhere, and only
// aggregate figures are printed. docs/projection-constants.md records them.
import 'dart:io';
import 'dart:math' as math;

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/projection_probe.dart';

/// Figures docs/projection-constants.md quotes (finding 1), held within a
/// tight band: the lap projections split into more than one segment, and the
/// fixes left unprojected. Before FET-257 fixed finding 1 they were 89 and
/// 2,078.
const _splitLaps = 46;
const _unprojected = 982;

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test(
    'real laps never project to the wrong place and stay inside the step constants',
    () {
      final files =
          Directory(folder)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.vbo'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      final sessions = [for (final file in files) parseVboFile(file.path)];
      final laps = [for (final session in sessions) deriveSourceLapSession(session)];

      // One axis per session, from its fastest lap, as a comparison builds
      // it; every timed lap of the day is projected on every axis.
      final axes = <ProgressAxis>[];
      for (final lapSession in laps) {
        final gate = lapSession.selectedStartGate;
        final fastest = lapSession.fastestLapIndex;
        if (gate == null || fastest == null) continue;
        final number = lapSession.timedLaps[fastest].number;
        final trace = lapSession.lapTraces.firstWhere((trace) => trace.lapNumber == number);
        final origin = GeoCoordinate(
          (gate.endpointA.latitudeDegrees + gate.endpointB.latitudeDegrees) / 2.0,
          (gate.endpointA.longitudeDegrees + gate.endpointB.longitudeDegrees) / 2.0,
        );
        final axis = buildProgressAxis(trace, origin, gate);
        expect(axis.valid, isTrue);
        axes.add(axis);
      }
      expect(axes, isNotEmpty);

      final probe = ProjectionProbe();
      final refusals = RefusalTally();
      // The ambiguity refusals while locked on the first session's axis, by
      // where on it they fall.
      var firstAxisRefusals = const <double>[];
      var projectedLaps = 0, splitLaps = 0, fixes = 0, projectedFixes = 0;
      var largestGateGap = 0.0;
      var largestError = 0.0;
      final lengths = [for (final axis in axes) axis.lengthMeters];
      for (final (a, axis) in axes.indexed) {
        for (final (s, lapSession) in laps.indexed) {
          final session = sessions[s];
          for (final lap in lapSession.timedLaps.where((lap) => lap.referenceEligible)) {
            final times = <double>[];
            final points = <MetricPoint>[];
            final latitude = session.channel('latitude')!;
            for (var i = 0; i < latitude.timestamps.length; ++i) {
              final time = latitude.timestamps[i];
              if (time < lap.startTelemetryTime || time > lap.endTelemetryTime) continue;
              final longitude = session.valueAt('longitude', time);
              final coordinate = GeoCoordinate(latitude.values[i], longitude ?? double.nan);
              if (longitude == null || !isValidCoordinate(coordinate)) continue;
              times.add(time);
              points.add(projectCoordinate(coordinate, axis.origin));
            }
            final followed = probe.measure(axis, times, points);
            final followedAt = {for (var i = 0; i < times.length; ++i) times[i]: followed[i]};
            final segments = projectLapTrace(
              axis,
              session,
              lap.startTelemetryTime,
              lap.endTelemetryTime,
            );
            final accepted = refusals.accepted;
            refusals.replay(axis, session, lap.startTelemetryTime, lap.endTelemetryTime);
            expect(
              refusals.accepted - accepted,
              segments.fold(0, (sum, segment) => sum + segment.samples.length),
            );
            ++projectedLaps;
            if (segments.length != 1) ++splitLaps;
            fixes += times.length;
            for (final segment in segments) {
              for (final sample in segment.samples) {
                // Projected progress is unwrapped; compare it round the loop.
                var error =
                    (sample.progressMeters - followedAt[sample.telemetryTime]!) % axis.lengthMeters;
                if (error > axis.lengthMeters / 2) error -= axis.lengthMeters;
                largestError = math.max(largestError, error.abs());
              }
            }
            projectedFixes += segments.fold(0, (sum, segment) => sum + segment.samples.length);
            if (segments.isNotEmpty) {
              largestGateGap = math.max(
                largestGateGap,
                math.max(
                  segments.first.samples.first.progressMeters.abs(),
                  (axis.lengthMeters - segments.last.samples.last.progressMeters).abs(),
                ),
              );
            }
          }
        }
        if (a == 0) firstAxisRefusals = [...refusals.lockedAmbiguityProgress]..sort();
      }
      final unprojected = fixes - projectedFixes;
      print(
        '${axes.length} axes of ${lengths.reduce(math.min).toStringAsFixed(0)}–'
        '${lengths.reduce(math.max).toStringAsFixed(0)} m, '
        'spacing ${axes.first.spacingMeters.toStringAsFixed(2)} m; '
        '$projectedLaps lap projections, $splitLaps not in one segment, '
        '$projectedFixes of $fixes fixes projected',
      );
      print('Measured: $probe');
      print(
        'Unprojected: $unprojected fixes '
        '(${(100 * unprojected / fixes).toStringAsFixed(2)}%): $refusals',
      );
      double quantile(List<double> sorted, double share) =>
          sorted[math.min(sorted.length - 1, (sorted.length * share).floor())];
      if (firstAxisRefusals.isNotEmpty) {
        int within(double from, double to) =>
            firstAxisRefusals.where((progress) => progress >= from && progress <= to).length;
        print(
          'Ambiguous while locked on the first axis: ${firstAxisRefusals.length} fixes, '
          '${within(140, 185)} at 140–185 m, ${within(140, 200)} at 140–200 m; '
          'median ${quantile(firstAxisRefusals, 0.5).toStringAsFixed(0)} m, '
          'quartiles ${quantile(firstAxisRefusals, 0.25).toStringAsFixed(0)}–'
          '${quantile(firstAxisRefusals, 0.75).toStringAsFixed(0)} m',
        );
      }
      print(
        'Nearest other part of the track: '
        '${axes.map((axis) => nearestOtherPart(axis, 30.0)).reduce(math.min).toStringAsFixed(1)} m '
        'more than 30 m along it, '
        '${axes.map((axis) => nearestOtherPart(axis, 100.0)).reduce(math.min).toStringAsFixed(1)} m '
        'more than 100 m along it',
      );
      print('Projected against followed progress: ≤ ${largestError.toStringAsFixed(2)} m');
      print('Gate: first or last projected fix within ${largestGateGap.toStringAsFixed(2)} m');

      // Every projected fix is where the lap really is on the axis.
      expect(largestError, lessThan(1.0));
      // Within the 3 m backward tolerance, the 5 s gap, the forward window
      // and the 15 m gate tolerance, and the heading never disagrees.
      expect(probe.largestBackwardStep, lessThanOrEqualTo(3.0));
      expect(probe.longestInterval, lessThan(5.0));
      expect(probe.largestWindowShare, lessThan(1.0));
      expect(largestGateGap, lessThanOrEqualTo(gateCoverageToleranceMeters));
      expect(probe.lowestHeadingCosine, greaterThan(0.0));
      // The refusals are read rule by rule, and the reading agrees with
      // projectSample on every fix.
      expect(refusals.disagreements, 0);
      expect(refusals.refused, unprojected);
      // docs/projection-constants.md quotes these; a change in the
      // projection that moves them must update the page too.
      expect(splitLaps, inInclusiveRange(_splitLaps - 2, _splitLaps + 2));
      expect(unprojected, inInclusiveRange(_unprojected - 20, _unprojected + 20));
      // Not asserted, because the reference day exceeds it (FET-215
      // findings in docs/projection-constants.md): one off-track
      // excursion goes beyond the 20 m proximity. 1% of fixes are more
      // than 12 m off the reference lap's line; since FET-257 most keep
      // their place while locked (finding 1), apart from those well inside
      // a bend, near another part of the track, or before a fix close to
      // the line confirms the lock.
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
