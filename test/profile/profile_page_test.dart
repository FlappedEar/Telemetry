// The Profile place: what the profile works out across days, shown.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry/profile/profile_page.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/temp_directory.dart';

/// No profile folder, as when the profile cannot be used.
final class _NoFolder implements ProfileStore {
  const _NoFolder();

  @override
  Future<String?> folder() async => null;
}

Future<R> _inPlace<R>(FutureOr<R> Function() computation) async =>
    computation();

final _route = RouteShape(
  origin: const GeoCoordinate(52, 17),
  points: [
    for (var i = 0; i < 256; ++i)
      MetricPoint(
        100 * math.cos(i * math.pi / 128),
        100 * math.sin(i * math.pi / 128),
      ),
  ],
  lengthMeters: 628,
  direction: TrackDirection.clockwise,
);

const _day0 = 1735689600000; // 2025-01-01
const _dayMs = 86400000;

ProfileSession _session(
  String runId, {
  required double best,
  required double median,
  required double spread,
  double distance = 20000,
  List<CornerStats> corners = const [],
}) => ProfileSession(
  runId: runId,
  name: 'Session ${runId.substring(1)}',
  lapCount: 10,
  bestLapSeconds: best,
  stats: SessionStats(
    distanceMeters: distance,
    drivingSeconds: distance / 25,
    rankedLaps: 8,
    medianLapSeconds: median,
    lapSpreadSeconds: spread,
    corners: corners,
  ),
);

CornerStats _corner(String id, double loss) => CornerStats(
  cornerId: id,
  laps: 8,
  minimumSpeed: 15,
  bestMinimumSpeed: 15.5,
  exitSpeed: 20,
  bestExitSpeed: 20.3,
  brakingSpreadMeters: 5,
  lossSeconds: loss,
  liftSeconds: 0.3,
  decelerationG: 0.8,
  bestDecelerationG: 0.9,
);

ProfileDay _visit(String id, int number, double best) => ProfileDay(
  eventId: id,
  file: 'Days/$id.fetproject',
  name: id,
  carId: 'car1',
  trackId: 'jastrzab',
  startMilliseconds: _day0 + number * _dayMs,
  sessions: [
    _session(
      's1',
      best: best,
      median: best + 1,
      spread: 1.5,
      corners: [_corner('c1', 0.4), _corner('c2', 0.05)],
    ),
  ],
  bestLapSeconds: best,
  theoreticalBestSeconds: best - 1,
);

DriverProfile _profile(List<ProfileDay> days) => DriverProfile(
  driverId: 'driver',
  cars: [
    ProfileCar(id: 'car1', name: 'Clio'),
    ProfileCar(id: 'car2', name: 'Unused'),
  ],
  tracks: [
    ProfileTrack(
      id: 'jastrzab',
      name: 'Jastrząb',
      route: _route,
      corners: [
        TrackCorner(id: 'c1', name: 'Corner 1', start: 0.1, end: 0.2),
        TrackCorner(id: 'c2', name: 'Corner 2', start: 0.5, end: 0.6),
      ],
    ),
  ],
  days: days,
);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('profile'));
  tearDown(() => deleteTemporaryDirectory(directory));

  Future<void> show(
    WidgetTester tester,
    DriverProfile profile, {
    String? locale,
  }) async {
    final folder = p.join(directory.path, 'Profile');
    Directory(p.join(folder, profileDaysFolder)).createSync(recursive: true);
    File(p.join(folder, profileFileName))
        .writeAsStringSync(encodeDriverProfile(profile));
    final library = ProfileLibrary(
      store: FolderProfileStore(folder),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: _inPlace,
    );
    await tester.runAsync(library.load);
    await tester.binding.setSurfaceSize(const Size(412, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        locale: locale == null ? null : Locale(locale),
        home: ProfilePage(library: library),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a profile with no day says what will appear', (tester) async {
    await show(tester, _profile(const []));
    expect(find.byKey(const ValueKey('profileEmpty')), findsOneWidget);
  });

  testWidgets('totals, skills, cars, records and repeated losses', (
    tester,
  ) async {
    await show(tester, _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.5)]));
    String total(String label) =>
        tester.widget<Text>(find.byKey(ValueKey('profileTotal $label'))).data!;
    expect(total('Days'), '2');
    expect(total('Sessions'), '2');
    expect(total('Distance'), '40.0 km');
    expect(total('Time on track'), '27\u00a0min');
    expect(find.byKey(const ValueKey('profileMeasured')), findsNothing);

    // Every skill of the model, measured or not, says where it stands.
    for (final skill in skillCatalogue) {
      expect(find.byKey(ValueKey('skill ${skill.id}')), findsOneWidget);
    }
    final pace = tester
        .widget<Text>(
          find.byKey(const ValueKey('skillDetails paceConsistency')),
        )
        .data!;
    expect(pace, startsWith('Level 3 of 5'));
    expect(pace, contains('High confidence'));
    expect(pace, contains('16 ranked laps over 2 days'));
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillValue paceConsistency')),
          )
          .data,
      'Lap time spread: 1.50 s',
    );
    String value(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('skillValue $id'))).data!;
    expect(value('liftTiming'), 'Off the throttle to braking: 0.30\u00a0s');
    // 0.8 g against the best ever there, 0.9 g.
    expect(
      value('brakingEffectiveness'),
      'Braking below your best: 0.10\u00a0g',
    );
    // No throttle figures in this profile.
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails throttleCommitment')),
          )
          .data,
      'Needs more evidence',
    );

    // Only cars that drove.
    expect(find.byKey(const ValueKey('profileCar car1')), findsOneWidget);
    expect(find.byKey(const ValueKey('profileCar car2')), findsNothing);

    // The track's records, with the progress since the visit before.
    final track = find.byKey(const ValueKey('profileTrack jastrzab'));
    expect(
      find.descendant(of: track, matching: find.textContaining('1:31.500')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: track,
        matching: find.text(
          'Last visit: best lap 0.500 s faster than the visit before',
        ),
      ),
      findsOneWidget,
    );

    // Corner 1 lost time on both visits; Corner 2 too little to count.
    expect(find.byKey(const ValueKey('profileRepeated 0')), findsOneWidget);
    expect(find.text('Jastrząb · Corner 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('profileRepeated 1')), findsNothing);
  });

  testWidgets('in Polish', (tester) async {
    await show(
      tester,
      _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.5)]),
      locale: 'pl',
    );
    expect(find.text('Wszystkie dni'), findsOneWidget);
    expect(find.text('Powtarzalność tempa'), findsOneWidget);
    expect(find.text('Potrzeba więcej danych'), findsWidgets);
    expect(
      find.text('Od odjęcia gazu do hamowania: 0.30\u00a0s'),
      findsOneWidget,
    );
    expect(find.textContaining('2 wizyty'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails paceConsistency')),
          )
          .data,
      contains('16 sklasyfikowanych okrążeń z 2 dni'),
    );
  });

  testWidgets('a slower last visit says so', (tester) async {
    await show(tester, _profile([_visit('d1', 0, 91.5), _visit('d2', 7, 92)]));
    expect(
      find.text(
        'Last visit: best lap 0.500\u00a0s slower than the visit before',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a best lap equal to the shown precision is no change', (
    tester,
  ) async {
    await show(
      tester,
      _profile([_visit('d1', 0, 92), _visit('d2', 7, 91.9998)]),
    );
    expect(find.textContaining('Last visit:'), findsNothing);
  });

  testWidgets('days with nothing measured show no zeros', (tester) async {
    final day = _visit('d1', 0, 92);
    await show(
      tester,
      _profile([
        ProfileDay(
          eventId: day.eventId,
          file: day.file,
          name: day.name,
          carId: 'car1',
          sessions: [
            ProfileSession(runId: 's1', name: 'Session 1', lapCount: 10),
          ],
        ),
      ]),
    );
    String total(String label) =>
        tester.widget<Text>(find.byKey(ValueKey('profileTotal $label'))).data!;
    expect(total('Distance'), '—');
    expect(total('Time on track'), '—');
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('profileMeasured'))).data,
      startsWith('Distance and time cover 0 of 1 session:'),
    );
    expect(
      find.text('1 day · distance and time not measured yet'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profileTracksNone')), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('skillDetails paceConsistency')),
          )
          .data,
      'Needs more evidence',
    );
  });

  testWidgets('a profile that cannot be used says so, not "no days"', (
    tester,
  ) async {
    final library = ProfileLibrary(
      store: const _NoFolder(),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: _inPlace,
    );
    await tester.pumpWidget(TelemetryApp(home: ProfilePage(library: library)));
    // Still loading.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('profileEmpty')), findsNothing);
    await tester.runAsync(library.load);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profileUnavailable')), findsOneWidget);
    expect(find.byKey(const ValueKey('profileEmpty')), findsNothing);
  });
}
