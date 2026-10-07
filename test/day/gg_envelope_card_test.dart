import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/background_task.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/gg_envelope_card.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'driving_vbo.dart';
import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

const _revision =
    'a000000000000000000000000000000000000000000000000000000000000000';

/// A recording of G pairs at 10 Hz: 100 pairs in every direction, combined
/// G evenly from 0.2 g to [peak] (or the direction's own in [peaks]). No
/// real data.
TelemetrySession _session(
  double peak, {
  Map<GgDirection, double> peaks = const {},
  int perDirection = 100,
  String longitudinal = 'longacc-calc',
  String lateral = 'latacc-calc',
  List<(double, double)> extra = const [],
}) {
  final pairs = <(double, double)>[
    for (final direction in GgDirection.values)
      for (var i = 0; i < perDirection; ++i)
        () {
          final top = peaks[direction] ?? peak;
          final magnitude = 0.2 + (top - 0.2) * i / (perDirection - 1);
          return (
            magnitude * math.cos(direction.angle),
            magnitude * math.sin(direction.angle),
          );
        }(),
    ...extra,
  ];
  final times = Float64List.fromList([
    for (var i = 0; i < pairs.length; ++i) i / 10,
  ]);
  TelemetryChannel channel(String name, Iterable<double> values) =>
      TelemetryChannel(
        name: name,
        unit: 'g',
        timestamps: times,
        values: Float32List.fromList(values.toList()),
      );
  return TelemetrySession(
    duration: times.last,
    startTime: 0,
    metadata: const {},
    channels: {
      longitudinal: channel(longitudinal, [for (final pair in pairs) pair.$1]),
      lateral: channel(lateral, [for (final pair in pairs) pair.$2]),
    },
    aliases: {
      'longitudinalAcceleration': longitudinal,
      'lateralAcceleration': lateral,
    },
    warnings: const [],
    timingGates: const [],
    sampleCount: pairs.length,
  );
}

DayLapRow _lap(String run, int clock) => DayLapRow(
  runId: run,
  runName: 'Session $run',
  type: LapSectionType.lap,
  lapNumber: 1,
  start: 0,
  end: 1000,
  sourceRevision: _revision,
  timestampMilliseconds: clock,
);

/// Session 1 brakes hardest; session 3, the latest, brakes 0.19 g less
/// (its 95th percentile) and turns left hardest; session 2 has too few
/// samples.
DayGgEnvelope _day({bool latestMissing = false}) => dayGgEnvelope(
  [_lap('1', 1000), _lap('2', 2000), _lap('3', 3000)],
  {
    '1': _session(1.0, peaks: {GgDirection.braking: 1.4}),
    '2': _session(1.2, perDirection: 10),
    '3': latestMissing
        ? null
        : _session(
            1.0,
            peaks: {GgDirection.braking: 1.2, GgDirection.left: 1.3},
          ),
  },
);

Future<void> _pumpView(
  WidgetTester tester,
  Widget view, {
  Locale locale = const Locale('en'),
}) async {
  await tester.binding.setSurfaceSize(const Size(412, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    TelemetryApp(
      locale: locale,
      home: Scaffold(body: ListView(children: [view])),
    ),
  );
  await tester.pump();
}

/// Lets the inline background job (a microtask under `flutter test`) run
/// and its result show.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pump();
}

String _text(WidgetTester tester, String key) =>
    tester.widget<Text>(find.byKey(ValueKey(key))).data!;

/// A background task finished, or stopped, by the test.
final class _ManualTask implements BackgroundTask<DayGgEnvelope> {
  final completer = Completer<DayGgEnvelope>();
  bool cancelled = false;

  @override
  Future<DayGgEnvelope> get result => completer.future;

  @override
  void cancel() => cancelled = true;
}

void main() {
  test('the diagram puts accelerating up and turning left on the left', () {
    const centre = Offset(100, 100);
    Offset at(GgDirection direction) =>
        GgEnvelopePainter.project(centre, 50, 1.0, direction, 0.5);
    expect(at(GgDirection.accelerating).dy, lessThan(centre.dy));
    expect(at(GgDirection.accelerating).dx, closeTo(centre.dx, 1e-9));
    expect(at(GgDirection.braking).dy, greaterThan(centre.dy));
    expect(at(GgDirection.left).dx, lessThan(centre.dx));
    expect(at(GgDirection.left).dy, closeTo(centre.dy, 1e-9));
    expect(at(GgDirection.right).dx, greaterThan(centre.dx));
    expect(at(GgDirection.brakingLeft).dx, lessThan(centre.dx));
    expect(at(GgDirection.brakingLeft).dy, greaterThan(centre.dy));
    // 0.5 g of a 1 g outer ring: half the radius.
    expect((at(GgDirection.braking) - centre).distance, closeTo(25, 1e-9));
    // A recording's positive lateral G is turning left.
    expect(ggDirectionOf(0, 0.8), GgDirection.left);
  });

  testWidgets('says how many samples were beyond the plausible limit', (
    tester,
  ) async {
    final day = dayGgEnvelope(
      [_lap('1', 1000)],
      {
        '1': _session(1.0, extra: [(-5.0, 0.0)]),
      },
    );
    await _pumpView(tester, GgEnvelopeView(envelope: day));
    expect(
      _text(tester, 'ggEnvelopeOutliers 1'),
      'Session 1: 1 sample beyond 4\u00a0g left out as implausible',
    );
    addTearDown(() => Intl.defaultLocale = null);
    await _pumpView(
      tester,
      GgEnvelopeView(envelope: day),
      locale: const Locale('pl'),
    );
    expect(
      _text(tester, 'ggEnvelopeOutliers 1'),
      'Sesja 1: 1 próbkę powyżej 4\u00a0g pominięto jako nieprawdopodobne',
    );
    // None lost: no line.
    await _pumpView(tester, GgEnvelopeView(envelope: _day()));
    expect(
      find.byWidgetPredicate(
        (widget) => '${widget.key}'.contains('ggEnvelopeOutliers'),
      ),
      findsNothing,
    );
  });

  testWidgets('shows each direction, the day\'s best and what is unused', (
    tester,
  ) async {
    await _pumpView(tester, GgEnvelopeView(envelope: _day()));
    expect(find.text('G-G envelope'), findsOneWidget);
    expect(find.byKey(const ValueKey('ggEnvelopePlot')), findsOneWidget);
    // The legend: the sessions with an envelope and the day's best.
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text('Session 3'), findsOneWidget);
    expect(find.text("Day's best"), findsNWidgets(2));
    expect(find.text('Session 3, latest'), findsOneWidget);
    // 0.2 + (1.4 − 0.2) × 94 / 99 and 0.2 + (1.2 − 0.2) × 94 / 99.
    expect(_text(tester, 'ggEnvelopeBest braking'), '1.34\u00a0g · Session 1');
    expect(_text(tester, 'ggEnvelopeLatest braking'), '1.15\u00a0g');
    expect(_text(tester, 'ggEnvelopeBest left'), '1.24\u00a0g · Session 3');
    expect(_text(tester, 'ggEnvelopeLatest right'), '0.96\u00a0g');
    expect(find.text('Braking + turning left'), findsOneWidget);
    expect(find.text('Accelerating + turning right'), findsOneWidget);
    // Unused only in braking, highlighted.
    expect(
      _text(tester, 'ggEnvelopeUnused'),
      'Unused envelope in Session 3: '
      'Braking 1.15\u00a0g against 1.34\u00a0g (Session 1).',
    );
    final braking = tester.widget<Text>(
      find.byKey(const ValueKey('ggEnvelopeLatest braking')),
    );
    expect(braking.style?.fontWeight, FontWeight.w700);
    final right = tester.widget<Text>(
      find.byKey(const ValueKey('ggEnvelopeLatest right')),
    );
    expect(right.style?.fontWeight, isNot(FontWeight.w700));
    // Too little data, said, never drawn as zero.
    expect(
      find.text(
        'Session 2: Too little data: fewer than 25 samples in every direction',
      ),
      findsOneWidget,
    );
    expect(find.text('Session 2'), findsNothing);
    // Calculated G is labelled as such.
    expect(
      find.text(
        'All sessions: longacc-calc / latacc-calc, '
        'calculated from GPS by the logger',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('at least 0.10\u00a0g below'), findsOneWidget);
    expect(find.textContaining('not a share of available grip'), findsOne);
  });

  testWidgets('speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    await _pumpView(
      tester,
      GgEnvelopeView(envelope: _day()),
      locale: const Locale('pl'),
    );
    expect(find.text('Obwiednia G–G'), findsOneWidget);
    expect(find.text('Sesja 3, ostatnia'), findsOneWidget);
    expect(find.text('Najlepsza dnia'), findsNWidgets(2));
    expect(find.text('Hamowanie + skręt w lewo'), findsOneWidget);
    expect(_text(tester, 'ggEnvelopeBest braking'), '1.34\u00a0g · Sesja 1');
    expect(
      _text(tester, 'ggEnvelopeUnused'),
      'Sesja 3, niewykorzystana obwiednia: '
      'Hamowanie 1.15\u00a0g wobec 1.34\u00a0g (Sesja 1).',
    );
    expect(
      find.text(
        'Sesja 2: Za mało danych: mniej niż 25 próbek w każdym kierunku',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Wszystkie sesje: longacc-calc / latacc-calc, '
        'obliczone przez rejestrator z GPS',
      ),
      findsOneWidget,
    );
    for (final english in ['G-G envelope', 'Braking', 'Session', 'unused']) {
      expect(find.textContaining(english), findsNothing);
    }
  });

  testWidgets('a latest session without an envelope compares nothing', (
    tester,
  ) async {
    await _pumpView(
      tester,
      GgEnvelopeView(envelope: _day(latestMissing: true)),
    );
    expect(
      _text(tester, 'ggEnvelopeUnused'),
      'Session 3 has no envelope, so nothing is compared.',
    );
    expect(find.text('Session 3: Recording unavailable.'), findsOneWidget);
    expect(_text(tester, 'ggEnvelopeLatest braking'), '—');
  });

  testWidgets('one session has nothing to compare; none says so', (
    tester,
  ) async {
    final one = dayGgEnvelope([_lap('1', 1000)], {'1': _session(1.0)});
    await _pumpView(tester, GgEnvelopeView(envelope: one));
    expect(
      _text(tester, 'ggEnvelopeUnused'),
      'Only one session has an envelope, so there is nothing to compare it '
      'with yet.',
    );
    expect(
      find.text(
        'Session 1: longacc-calc / latacc-calc, '
        'calculated from GPS by the logger',
      ),
      findsOneWidget,
    );
    final none = dayGgEnvelope([_lap('1', 1000)], {'1': null});
    await _pumpView(tester, GgEnvelopeView(envelope: none));
    expect(find.byKey(const ValueKey('ggEnvelopeNone')), findsOneWidget);
    expect(find.byKey(const ValueKey('ggEnvelopePlot')), findsNothing);
    expect(find.text('Session 1: Recording unavailable.'), findsOneWidget);
  });

  testWidgets('the latest session within the margin everywhere', (
    tester,
  ) async {
    final day = dayGgEnvelope(
      [_lap('1', 1000), _lap('2', 2000)],
      {
        '1': _session(1.0, peaks: {GgDirection.braking: 1.1}),
        '2': _session(1.05, longitudinal: 'long accel', lateral: 'lat accel'),
      },
    );
    await _pumpView(tester, GgEnvelopeView(envelope: day));
    expect(
      _text(tester, 'ggEnvelopeUnused'),
      "Session 2 came within 0.10\u00a0g of the day's best in every direction "
      'it has a value for.',
    );
    // Different channels: one line per session.
    expect(
      find.text('Session 2: long accel / lat accel, measured'),
      findsOneWidget,
    );
    expect(find.textContaining('Session 1: longacc-calc'), findsOneWidget);
  });

  group('on a day', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('gg'));
    tearDown(() => deleteTemporaryDirectory(directory));

    DayImportOutcome importDay() {
      final files = {
        'a.vbo': [rectangleBrakingLap(250, 15), rectangleBrakingLap(240, 16)],
        'b.vbo': [rectangleBrakingLap(260, 14), rectangleBrakingLap(255, 15)],
      };
      final paths = <String>[];
      files.forEach((name, laps) {
        final path = '${directory.path}/$name';
        File(
          path,
        ).writeAsStringSync(withAcceleration(rectangleVbo(laps, pedals: true)));
        paths.add(path);
      });
      return runDayImport((paths: paths, includeSubfolders: false));
    }

    TelemetrySession? Function(String) sessionsOf(DayImportOutcome outcome) =>
        (runId) => outcome.runs
            .firstWhere((named) => named.run.id == runId)
            .run
            .telemetry;

    testWidgets('works the envelope out in the background, again when the '
        'laps change', (tester) async {
      final outcome = importDay();
      final eligible = dayEligibleLaps(outcome.analysis!);
      expect(eligible.length, greaterThanOrEqualTo(2));
      final inputs = <GgEnvelopeInput>[];
      BackgroundTask<DayGgEnvelope> runner(GgEnvelopeInput input) {
        inputs.add(input);
        return defaultGgEnvelopeRunner(input);
      }

      Widget card(List<DayLapRow> laps) => GgEnvelopeCard(
        laps: laps,
        sessionOf: sessionsOf(outcome),
        runner: runner,
      );
      await _pumpView(tester, card(eligible));
      await _finish(tester);
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
      expect(inputs, hasLength(1));
      // Only the laps passed (no out or in laps), and only the G channels
      // go to the background.
      expect(inputs.single.laps, eligible);
      for (final session in inputs.single.sessions.values) {
        expect(session!.channels.keys, unorderedEquals(['longacc', 'latacc']));
      }
      // Undeclared units are said.
      expect(
        find.text(
          'All sessions: longacc / latacc, measured, '
          'units not declared by the recording',
        ),
        findsOneWidget,
      );
      // The same laps again: nothing new to work out.
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(body: ListView(children: [card(List.of(eligible))])),
        ),
      );
      await _finish(tester);
      expect(inputs, hasLength(1));
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
      // One lap fewer: worked out again.
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(body: ListView(children: [card(eligible.sublist(1))])),
        ),
      );
      expect(
        find.byKey(const ValueKey('ggEnvelopeRecalculating')),
        findsOneWidget,
      );
      await _finish(tester);
      expect(inputs, hasLength(2));
      expect(
        find.byKey(const ValueKey('ggEnvelopeRecalculating')),
        findsNothing,
      );
      expect(inputs.last.laps, eligible.sublist(1));
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
    });

    testWidgets('a stale result is ignored, replaced and closed work stops', (
      tester,
    ) async {
      final outcome = importDay();
      final eligible = dayEligibleLaps(outcome.analysis!);
      final tasks = <_ManualTask>[];
      final inputs = <GgEnvelopeInput>[];
      BackgroundTask<DayGgEnvelope> runner(GgEnvelopeInput input) {
        inputs.add(input);
        return tasks.last;
      }

      Widget card(List<DayLapRow> laps) => GgEnvelopeCard(
        laps: laps,
        sessionOf: sessionsOf(outcome),
        runner: runner,
      );
      DayGgEnvelope compute(GgEnvelopeInput input) =>
          dayGgEnvelope(input.laps, input.sessions);
      tasks.add(_ManualTask());
      await _pumpView(tester, card(eligible));
      expect(find.text('Calculating the G-G envelope…'), findsOneWidget);
      // Fewer laps before the first result: the first task is stopped.
      tasks.add(_ManualTask());
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(body: ListView(children: [card(eligible.sublist(1))])),
        ),
      );
      expect(tasks[0].cancelled, isTrue);
      expect(tasks[1].cancelled, isFalse);
      // The stopped task's result arrives anyway: it is not shown.
      tasks[0].completer.complete(compute(inputs[0]));
      await tester.pump();
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsNothing);
      expect(find.text('Calculating the G-G envelope…'), findsOneWidget);
      tasks[1].completer.complete(compute(inputs[1]));
      await tester.pump();
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
      // Worked out again: the result stays, with a progress bar.
      tasks.add(_ManualTask());
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(body: ListView(children: [card(eligible)])),
        ),
      );
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('ggEnvelopeRecalculating')),
        findsOneWidget,
      );
      // Closed while working: the work is stopped.
      await tester.pumpWidget(const SizedBox());
      expect(tasks[2].cancelled, isTrue);
    });

    testWidgets('a renamed session is named anew', (tester) async {
      final outcome = importDay();
      final eligible = dayEligibleLaps(outcome.analysis!);
      Widget card(List<DayLapRow> laps) =>
          GgEnvelopeCard(laps: laps, sessionOf: sessionsOf(outcome));
      await _pumpView(tester, card(eligible));
      await _finish(tester);
      expect(find.text('Session 1'), findsOneWidget);
      final firstRun = eligible.first.runId;
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(
            body: ListView(
              children: [
                card([
                  for (final row in eligible)
                    row.runId == firstRun
                        ? row.copyWith(runName: 'Warm-up')
                        : row,
                ]),
              ],
            ),
          ),
        ),
      );
      await _finish(tester);
      expect(find.text('Warm-up'), findsOneWidget);
      expect(find.text('Session 1'), findsNothing);
    });

    test('the envelope is worked out in its own isolate', () async {
      debugRunInIsolate = true;
      addTearDown(() => debugRunInIsolate = false);
      final outcome = importDay();
      final input = (
        laps: dayEligibleLaps(outcome.analysis!),
        sessions: {
          for (final named in outcome.runs)
            named.run.id: ggEnvelopeSession(named.run.telemetry),
        },
      );
      final inIsolate = await defaultGgEnvelopeRunner(input).result;
      final here = dayGgEnvelope(input.laps, input.sessions);
      expect(inIsolate.error, isEmpty);
      expect(inIsolate.sessions, hasLength(here.sessions.length));
      for (var i = 0; i < here.sessions.length; ++i) {
        for (final direction in GgDirection.values) {
          expect(
            inIsolate.sessions[i].valueG(direction),
            here.sessions[i].valueG(direction),
          );
        }
      }
    });

    testWidgets('a failure says why and can be calculated again', (
      tester,
    ) async {
      final outcome = importDay();
      var fail = true;
      BackgroundTask<DayGgEnvelope> runner(GgEnvelopeInput input) {
        if (fail) throw StateError('no isolate');
        return defaultGgEnvelopeRunner(input);
      }

      await _pumpView(
        tester,
        GgEnvelopeCard(
          laps: dayEligibleLaps(outcome.analysis!),
          sessionOf: sessionsOf(outcome),
          runner: runner,
        ),
      );
      expect(
        find.text(
          'The G-G envelope could not be calculated: Bad state: no isolate',
        ),
        findsOneWidget,
      );
      fail = false;
      await tester.tap(find.text('Calculate again'));
      await tester.pump();
      await _finish(tester);
      expect(find.byKey(const ValueKey('ggEnvelopeTable')), findsOneWidget);
    });

    testWidgets('the day page shows the card among the analysis cards', (
      tester,
    ) async {
      final outcome = importDay();
      await tester.binding.setSurfaceSize(const Size(412, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        TelemetryApp(
          home: DayResultsPage(runs: outcome.runs, analysis: outcome.analysis!),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('ggEnvelopeTable')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('G-G envelope'), findsOneWidget);
      expect(find.text('Session 2, latest'), findsOneWidget);
    });
  });
}
