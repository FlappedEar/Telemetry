import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/focus_areas_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';

final _route = RouteShape(
  origin: const GeoCoordinate(50.0, 19.0),
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

const _dayMs = 24 * 3600 * 1000;
const _day0 = 1756454400000; // 2025-08-29

ProfileDay _day(
  String id, {
  required int dayNumber,
  String car = 'clio',
  Map<String, double> losses = const {},
}) => ProfileDay(
  eventId: id,
  file: 'Days/$id.fetproject',
  name: 'Day $id',
  carId: car,
  trackId: 'jastrzab',
  startMilliseconds: _day0 + dayNumber * _dayMs,
  sessions: [
    ProfileSession(
      runId: 's1',
      name: 'Session 1',
      lapCount: 6,
      stats: SessionStats(
        rankedLaps: 4,
        corners: [
          for (final MapEntry(:key, :value) in losses.entries)
            CornerStats(cornerId: key, laps: 4, lossSeconds: value),
        ],
      ),
    ),
  ],
);

DriverProfile _profile(List<ProfileDay> days) => DriverProfile(
  driverId: 'driver',
  cars: [
    ProfileCar(id: 'clio', name: 'Clio'),
    ProfileCar(id: 'golf', name: 'Golf'),
  ],
  tracks: [
    ProfileTrack(
      id: 'jastrzab',
      name: 'Jastrząb',
      route: _route,
      corners: [
        TrackCorner(id: 'k1', name: 'Turn 1', start: 0.1, end: 0.15),
        TrackCorner(id: 'k2', name: 'Turn 2', start: 0.4, end: 0.45),
      ],
    ),
  ],
  days: days,
);

void main() {
  final english = lookupAppLocalizations(const Locale('en'));
  final polish = lookupAppLocalizations(const Locale('pl'));

  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('focus_before'));
  tearDown(() => directory.deleteSync(recursive: true));

  // A day of two sessions, each slow somewhere else, opened without a
  // library: its focus areas.
  Future<DayResultsController> open(WidgetTester tester) async {
    final files = {
      'a.vbo': [
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
        rectangleLap(30.5, 100, 160, 24),
      ],
      'b.vbo': [rectangleLap(29), rectangleLap(30.5, 700, 780, 20)],
    };
    final paths = <String>[];
    files.forEach((name, laps) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(rectangleVbo(laps));
      paths.add(path);
    });
    final outcome = runDayImport((paths: paths, includeSubfolders: false));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(home: DayResultsPage.controller(controller: controller)),
    );
    await tester.pumpAndSettle();
    return controller;
  }

  testWidgets('no line without a library', (tester) async {
    final controller = await open(tester);
    expect(controller.focusAreas, isNotEmpty);
    final first = find.byKey(const ValueKey('focusArea 0'));
    await tester.scrollUntilVisible(
      first,
      200,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('dayResultsSummary')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(first, findsOneWidget);
    expect(find.byKey(const ValueKey('focusBefore 0')), findsNothing);
    expect(find.textContaining('Earlier visits here'), findsNothing);
  });

  testWidgets('each area at a corner says what earlier visits measured', (
    tester,
  ) async {
    final controller = await open(tester);
    final result = controller.theoreticalBest!;
    final area = controller.focusAreas.first;

    // The day's corner at [start]–[end] of the lap, in the area's segment.
    DayCornerSpan span(double start, double end) {
      GeoCoordinate at(double fraction) {
        final point = _route.points[(fraction * 256).round() % 256];
        return unprojectCoordinate(
          point.eastMeters,
          point.northMeters,
          _route.origin,
        );
      }

      return DayCornerSpan(
        segmentId: area.segmentId,
        name: area.name,
        start: at(start),
        end: at(end),
      );
    }

    // The line under the first area, for [profile] with the area's segment
    // on Turn 1 unless [spans] say otherwise.
    Future<String?> line(
      DriverProfile? profile, {
      List<DayCornerSpan>? spans,
      String eventId = 'today',
    }) async {
      final before = focusBefore(
        english,
        profile,
        eventId,
        spans ?? [span(0.1, 0.15)],
      );
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FocusAreasCard(
                result: result,
                areas: [area],
                lapLabel: controller.lapLabel,
                before: before,
              ),
            ),
          ),
        ),
      );
      final text = find.byKey(const ValueKey('focusBefore 0'));
      if (text.evaluate().isEmpty) return null;
      return tester.widget<Text>(text).data;
    }

    final date = DateFormat.yMMMd().format(
      DateTime.fromMillisecondsSinceEpoch(_day0 + 10 * _dayMs),
    );
    // Turn 1 among the costliest on both earlier visits, the last on day
    // 10; the Golf's day does not count, nor does the later one.
    expect(
      await line(
        _profile([
          _day('a', dayNumber: 0, losses: {'k1': 0.6, 'k2': 0.05}),
          _day('b', dayNumber: 10, losses: {'k1': 0.4}),
          _day('golf', dayNumber: 15, car: 'golf', losses: {'k1': 0.9}),
          _day('today', dayNumber: 20, losses: {'k1': 0.3}),
          _day('later', dayNumber: 30, losses: {'k1': 0.9}),
        ]),
      ),
      'Earlier visits here (Turn 1): it cost time on 2 of 2 visits, last on '
      '$date.',
    );
    // Costly once, then measured twice without it.
    expect(
      await line(
        _profile([
          _day('a', dayNumber: 0, losses: {'k1': 0.6}),
          _day('b', dayNumber: 10, losses: {'k1': 0.05}),
          _day('c', dayNumber: 15, losses: {'k1': 0.02}),
          _day('today', dayNumber: 20),
        ]),
      ),
      'Earlier visits here (Turn 1): it cost time on 1 of 3 visits, but not '
      'on the last 2 visits that measured it.',
    );
    expect(
      await line(
        _profile([
          _day('a', dayNumber: 0, losses: {'k1': 0.05}),
          _day('today', dayNumber: 20),
        ]),
      ),
      'Earlier visits here (Turn 1): measured on 1 visit, never among the '
      'corners that cost the most time.',
    );
    expect(
      await line(
        _profile([
          _day('golf', dayNumber: 0, car: 'golf', losses: {'k1': 0.6}),
          _day('today', dayNumber: 20),
        ]),
      ),
      'Earlier visits here (Turn 1): none in this car in your library.',
    );
    expect(
      await line(
        _profile([
          _day('a', dayNumber: 0, losses: {'k2': 0.6}),
          _day('today', dayNumber: 20),
        ]),
      ),
      'Earlier visits here (Turn 1): this corner was not measured before.',
    );
    final visited = _profile([
      _day('a', dayNumber: 0, losses: {'k1': 0.6}),
      _day('today', dayNumber: 20),
    ]);
    expect(
      await line(visited, spans: [span(0.6, 0.65)]),
      "Earlier visits here: this place is not one of the track's corners "
      'in your library yet.',
    );
    // No library, a day not in it, or no corner of the day on the ground
    // (no usable axis): no line.
    expect(await line(null), isNull);
    expect(await line(visited, spans: const []), isNull);
    expect(await line(visited, eventId: 'elsewhere'), isNull);

    // The track corner adding the day placed the area's segment on (kept
    // with its figures) wins over matching the day's corners again, which
    // is only for days added before it was kept (FET-184).
    final placed = _profile([
      _day('a', dayNumber: 0, losses: {'k1': 0.6}),
      ProfileDay(
        eventId: 'today',
        file: 'Days/today.fetproject',
        name: 'Day today',
        carId: 'clio',
        trackId: 'jastrzab',
        startMilliseconds: _day0 + 20 * _dayMs,
        sessions: [
          ProfileSession(
            runId: 's1',
            name: 'Session 1',
            stats: SessionStats(
              rankedLaps: 4,
              corners: [
                CornerStats(cornerId: 'k2', segmentId: area.segmentId, laps: 4),
              ],
            ),
          ),
        ],
      ),
    ]);
    const turn2 =
        'Earlier visits here (Turn 2): this corner was not measured '
        'before.';
    expect(await line(placed), turn2);
    expect(await line(placed, spans: const []), turn2);
  });

  test('the Polish texts count visits', () {
    expect(
      polish.focusBeforeLost(2, 5, 'Zakręt 1', '29 sie 2026'),
      'Wcześniejsze wizyty tutaj (Zakręt 1): ten zakręt kosztował czas na 2 '
      'z 5 wizyt, ostatnio 29 sie 2026.',
    );
    expect(polish.focusBeforeNever(1, 'Zakręt 1'), contains('na 1 wizycie'));
    expect(polish.focusBeforeNever(3, 'Zakręt 1'), contains('na 3 wizytach'));
  });
}
