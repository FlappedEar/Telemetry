import 'dart:math' as math;
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _revision = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

DayRunInput run(
  String id,
  TelemetrySession session, {
  String? layoutName,
  TrackDirection? direction,
}) => DayRunInput(
  runId: id,
  name: 'Session ${id.substring(id.length - 1)}',
  contentSha256: _revision.replaceFirst('a', id.substring(id.length - 1)),
  session: session,
  laps: deriveSourceLapSession(session),
  layoutName: layoutName,
  direction: direction,
);

void main() {
  group('inferTrack', () {
    test('finds a counterclockwise circuit and every lap on it', () {
      final laps = deriveSourceLapSession(circuitSession(speeds: [30, 28, 31, 29]));
      final inference = inferTrack(laps);
      expect(inference.supported, isTrue);
      expect(inference.route!.direction, TrackDirection.counterclockwise);
      expect(inference.route!.lengthMeters, closeTo(2 * math.pi * 100, 10));
      expect(inference.matchingLaps, {1, 2, 3, 4});
    });

    test('finds a clockwise circuit', () {
      final laps = deriveSourceLapSession(circuitSession(clockwise: true));
      expect(inferTrack(laps).route!.direction, TrackDirection.clockwise);
    });

    test('drops a lap that leaves the line the other laps took', () {
      final session = circuitSession(
        speeds: [30, 30, 30, 30],
        radiusOf: (lap, angle) => lap == 1 && angle > 2.0 && angle < 2.6 ? 120.0 : 100.0,
      );
      final inference = inferTrack(deriveSourceLapSession(session));
      expect(inference.supported, isTrue);
      expect(inference.matchingLaps, {1, 3, 4});
    });

    test('needs repeated complete laps', () {
      final laps = deriveSourceLapSession(circuitSession(speeds: [30]));
      final inference = inferTrack(laps);
      expect(inference.supported, isFalse);
      expect(inference.reason, contains('Not enough'));
    });

    test('routes of different length or direction do not match', () {
      RouteShape route({double radius = 100, bool clockwise = false}) =>
          inferTrack(deriveSourceLapSession(circuitSession(radius: radius, clockwise: clockwise)))
              .route!;
      expect(routesMatch(route(), route()), isTrue);
      expect(routesMatch(route(), route(radius: 130)), isFalse);
      expect(routesMatch(route(), route(clockwise: true)), isFalse);
    });

    test('honours cancellation', () {
      final laps = deriveSourceLapSession(circuitSession());
      expect(() => inferTrack(laps, cancelled: () => true), throwsA(isA<OperationCancelled>()));
    });
  });

  group('analyzeDay', () {
    test('groups runs on one circuit and ranks the day', () {
      final day = analyzeDay([
        run('run:1', circuitSession(speeds: [30, 28, 31], firstTimestampMilliseconds: 1000)),
        run('run:2', circuitSession(speeds: [29, 32, 30], firstTimestampMilliseconds: 900000)),
      ]);
      expect(day.groups, hasLength(1));
      final group = day.groups.single;
      expect(group.resolved, isTrue);
      expect(group.label, 'Group 1 · Detected route · Counterclockwise');
      expect(group.runIds, ['run:1', 'run:2']);
      expect(day.chosenGroupId, group.id);
      expect(day.ranking!.bestOfDay!.displayName, 'Session 2 · LAP 2');
      expect(day.ranking!.eligibleLapCount, 6);
      expect(day.rows.first.displayName, 'Session 1 · OUT');
      expect(day.rows.last.displayName, 'Session 2 · IN');
      expect(day.messages, isEmpty);
      expect(day.configurations['run:1']!.gateRevision, startsWith('gates-v1:'));
      expect(day.configurations['run:1']!.gateRevision, sessionGateRevision(circuitSession()));
    });

    test('keeps different circuits apart and leads with the group with most laps', () {
      final day = analyzeDay([
        run('run:1', circuitSession(radius: 200, speeds: [30, 30])),
        run('run:2', circuitSession(speeds: [30, 30, 30])),
        run('run:3', circuitSession(speeds: [31, 31])),
      ]);
      expect(day.groups.where((group) => group.resolved), hasLength(2));
      expect(day.chosenGroup!.runIds, ['run:2', 'run:3']);
      expect(day.ranking!.bestOfDay!.runId, 'run:3');
      final preferred = analyzeDay([
        run('run:1', circuitSession(radius: 200, speeds: [30, 30])),
        run('run:2', circuitSession(speeds: [30, 30, 30])),
      ], preferredGroupId: day.groups.first.id);
      expect(preferred.chosenGroup!.runIds, ['run:1']);
    });

    test('a manual layout wins over inference', () {
      final day = analyzeDay([
        run(
          'run:1',
          circuitSession(),
          layoutName: 'Club',
          direction: TrackDirection.counterclockwise,
        ),
        run('run:2', circuitSession()),
      ]);
      expect(day.configurations['run:1']!.layoutId, 'Club');
      expect(day.groups.map((group) => group.label), [
        'Group 1 · Club · Counterclockwise',
        'Group 2 · Detected route · Counterclockwise',
      ]);
    });

    test('regroupDay applies and removes a manual layout without re-inferring', () {
      final day = analyzeDay([
        run('run:1', circuitSession(speeds: [30, 30, 30])),
        run('run:2', circuitSession(speeds: [31, 31])),
      ]);
      expect(day.groups, hasLength(1));
      final named = regroupDay(
        day,
        manualTracks: {
          'run:1': const TrackConfiguration(
            layoutId: 'Club',
            direction: TrackDirection.counterclockwise,
          ),
          'run:2': const TrackConfiguration(
            layoutId: 'Club',
            direction: TrackDirection.counterclockwise,
          ),
        },
      );
      expect(named.groups.map((group) => group.label), ['Group 1 · Club · Counterclockwise']);
      expect(named.ranking!.eligibleLapCount, 5);
      final split = regroupDay(
        named,
        manualTracks: {
          'run:1': const TrackConfiguration(layoutId: 'Club', direction: TrackDirection.clockwise),
        },
      );
      expect(split.groups, hasLength(2));
      expect(split.manualTracks.keys, ['run:1']);
      final back = regroupDay(split, manualTracks: const {});
      expect(back.groups.single.label, day.groups.single.label);
      expect(back.ranking!.bestOfDay!.reference, day.ranking!.bestOfDay!.reference);
    });

    test('a run without laps is unresolved and says why', () {
      final day = analyzeDay([
        run('run:1', circuitSession(speeds: [30])),
        run('run:2', circuitSession()),
      ]);
      expect(day.groups.first.label, 'Unresolved · Session 1');
      expect(day.groups.first.resolved, isFalse);
      expect(day.messages.map((message) => message.runId), contains('run:1'));
      expect(day.chosenGroup!.runIds, ['run:2']);
    });

    test('applies user exclusions', () {
      final first = analyzeDay([run('run:1', circuitSession())]);
      final best = first.ranking!.bestOfDay!;
      final second = analyzeDay(
        [run('run:1', circuitSession())],
        exclusions: {best.reference: 'Traffic'},
      );
      expect(second.ranking!.bestOfDay!.reference, isNot(best.reference));
      expect(second.ranking!.excludedLaps.single.userReason, 'Traffic');
      final reranked = rerankDay(first, exclusions: {best.reference: 'Traffic'});
      expect(reranked.ranking!.bestOfDay!.reference, second.ranking!.bestOfDay!.reference);
      expect(rerankDay(reranked).ranking!.bestOfDay!.reference, best.reference);
    });
  });

  group('lapPath', () {
    test('returns the fixes of a lap with speed, split at a GPS gap', () {
      final session = circuitSession();
      final lap = deriveSourceLapSession(session).timedLaps.first;
      final path = lapPath(session, lap.startTelemetryTime, lap.endTelemetryTime);
      expect(path.segments, hasLength(1));
      expect(path.segments.single.first.speed, closeTo(108, 1e-3));
      final lat = session.channel('latitude')!;
      final lon = session.channel('longitude')!;
      List<double> without(List<double> values, Float64List times) => [
        for (var i = 0; i < times.length; ++i)
          if (times[i] < 5 || times[i] > 8) values[i],
      ];
      final gapped = TelemetrySession(
        duration: session.duration,
        startTime: 0,
        metadata: const {},
        channels: {
          'latitude': TelemetryChannel(
            name: 'latitude',
            timestamps: Float64List.fromList(without(lat.timestamps, lat.timestamps)),
            values: Float32List.fromList(
              without(lat.values.map((v) => v.toDouble()).toList(), lat.timestamps),
            ),
          ),
          'longitude': TelemetryChannel(
            name: 'longitude',
            timestamps: Float64List.fromList(without(lon.timestamps, lon.timestamps)),
            values: Float32List.fromList(
              without(lon.values.map((v) => v.toDouble()).toList(), lon.timestamps),
            ),
          ),
        },
        aliases: const {'latitude': 'latitude', 'longitude': 'longitude'},
        warnings: const [],
        timingGates: const [],
        sampleCount: 0,
      );
      final split = lapPath(gapped, 0, 20);
      expect(split.segments, hasLength(2));
      expect(split.segments.first.last.telemetryTime, lessThan(5));
      expect(split.segments.last.first.telemetryTime, greaterThan(8));
      expect(split.segments.first.first.speed, isNull);
    });
  });
}
