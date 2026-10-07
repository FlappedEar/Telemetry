import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/best_phases_card.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'rectangle_vbo.dart';
import '../support/temp_directory.dart';

DayLapRow _row(String runId, String runName, int number) => DayLapRow(
  runId: runId,
  runName: runName,
  type: LapSectionType.lap,
  lapNumber: number,
  start: number * 100.0,
  end: number * 100.0 + 90 + number,
  sourceRevision: 'a' * 64,
);

final _a = _row('run1', 'Session 1', 1), _b = _row('run2', 'Session 2', 2);

PhasePiece _part(int index, String name, PhasePart part) => PhasePiece(
  segmentIndex: index,
  segmentId: 'c$index',
  name: name,
  part: part,
  corner: true,
);

// A straight, a corner split in three, a corner that is not split; lap A
// is the best lap, lap B is quicker in the corner's middle and exit, and
// its speed is not known where the last corner starts.
DayTheoreticalBest _built() => DayTheoreticalBest(
  groupId: 'g',
  state: DayTheoreticalBestState.ready,
  bestLap: _a,
  laps: [
    for (final (row, best) in [(_a, true), (_b, false)])
      DayLapSectors(
        lap: row,
        times: LapSectorTimes(lapReference: row.reference),
        lossSeconds: const [],
        bestOfDay: best,
      ),
  ],
  bestPhases: PhaseReference(
    pieces: [
      PhaseReferencePiece(
        piece: const PhasePiece(
          segmentIndex: 0,
          segmentId: 's1',
          name: 'Straight 1',
        ),
        seconds: 5.0,
        lapReference: _a.reference,
      ),
      PhaseReferencePiece(
        piece: _part(1, 'Corner 1', PhasePart.entry),
        seconds: 1.4,
        lapReference: _a.reference,
        join: PhaseJoin.sameLap,
      ),
      PhaseReferencePiece(
        piece: _part(1, 'Corner 1', PhasePart.middle),
        seconds: 1.3,
        lapReference: _b.reference,
        join: PhaseJoin.apart,
        joinMetresPerSecond: 0.8,
      ),
      PhaseReferencePiece(
        piece: _part(1, 'Corner 1', PhasePart.exit),
        seconds: 3.5,
        lapReference: _b.reference,
        join: PhaseJoin.sameLap,
      ),
      PhaseReferencePiece(
        piece: const PhasePiece(
          segmentIndex: 2,
          segmentId: 'c2',
          name: 'Corners 2–3',
          corner: true,
          splitReason: cornerPhaseMultipleApexes,
        ),
        seconds: 8.8,
        lapReference: _a.reference,
        join: PhaseJoin.unknown,
      ),
    ],
    totalSeconds: 20.0,
    joinedSeconds: 20.2,
    joinedLapCount: 1,
    lapSeconds: {
      _a.reference: [5.0, 1.4, 1.5, 3.7, 8.8],
      _b.reference: [5.1, 1.5, 1.3, 3.5, null],
    },
    speedUnit: 'km/h',
  ),
);

Future<void> _pump(
  WidgetTester tester,
  Widget card, {
  Locale? locale,
  bool open = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(412, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    TelemetryApp(
      locale: locale,
      home: Scaffold(body: ListView(children: [card])),
    ),
  );
  await tester.pumpAndSettle();
  if (open) {
    await tester.tap(find.byKey(const ValueKey('bestPhasesToggle')));
    await tester.pumpAndSettle();
  }
}

String _text(WidgetTester tester, Finder finder) => [
  for (final widget in tester.widgetList<Text>(
    find.descendant(of: finder, matching: find.byType(Text)),
  ))
    widget.data ?? '',
].join('|');

void main() {
  testWidgets('a target from real laps: each part, its lap and the loss', (
    tester,
  ) async {
    // Each lap is slow somewhere else, so the parts come from several laps.
    final directory = Directory.systemTemp.createTempSync('best_phases');
    addTearDown(() => deleteTemporaryDirectory(directory));
    final files = {
      'a.vbo': [
        rectangleLap(30, 50, 120, 20),
        rectangleLap(31, 300, 400, 25),
        rectangleLap(30, 550, 650, 22),
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
    final result = dayTheoreticalBest(
      outcome.analysis!,
      outingRuns(outcome.runs),
    );
    final phases = result.bestPhases!;
    expect(phases.valid, isTrue);
    final sections = result.sectionProgression([
      for (final named in outcome.runs)
        ProgressionRunInfo(id: named.run.id, name: named.name),
    ]);
    await _pump(
      tester,
      BestPhasesCard(result: result, sections: sections),
      open: false,
    );
    // Closed: one line with the total.
    expect(
      find.text(
        'Each corner\'s best entry, middle and exit of the day, as a target: '
        '${displayTime(phases.totalSeconds!)}.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('bestPhasesTime')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('bestPhasesToggle')));
    await tester.pumpAndSettle();

    String value(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;
    final best = result.bestLap!;
    expect(value('bestPhasesTime'), displayTime(phases.totalSeconds!));
    expect(
      value('bestPhasesLapTime'),
      displayTime(phases.lapTotal(best.reference)!),
    );
    expect(
      value('bestPhasesLoss'),
      displayDelta(phases.lapTotal(best.reference)! - phases.totalSeconds!),
    );
    // Next to the theoretical bests.
    expect(value('bestPhasesTotal value'), displayTime(phases.totalSeconds!));
    expect(
      value('bestPhasesRaw value'),
      displayTime(result.theoreticalBestSeconds!),
    );
    expect(value('bestPhasesJoined value'), displayTime(phases.joinedSeconds!));
    expect(
      value('bestPhasesRealistic value'),
      displayTime(result.realistic!.totalSeconds!),
    );
    expect(
      value('bestPhasesTypical value'),
      displayTime(repeatableTheoreticalBest(sections)!),
    );
    // The recordings declare no speed unit: differences are in m/s.
    expect(phases.speedUnit, isEmpty);
    expect(
      find.textContaining('at most 0.6\u00a0m/s wherever two laps meet'),
      findsOneWidget,
    );

    // A split corner: its three parts with the best lap's losses.
    final split = phases.pieces.indexWhere(
      (piece) => piece.piece.part == PhasePart.entry,
    );
    expect(split, isNonNegative);
    final losses = phases.lossesOf(best.reference);
    for (final (i, label) in ['Entry', 'Middle', 'Exit'].indexed) {
      final row = find.byKey(ValueKey('bestPhasesPiece ${split + i}'));
      final texts = _text(tester, row).split('|');
      expect(
        [texts.first, texts.last],
        [label, displayDelta(losses[split + i]!)],
      );
    }

    // Another lap: its own losses.
    final other = result.laps.firstWhere((lap) => !lap.bestOfDay).lap;
    final dropdown = find.byKey(const ValueKey('bestPhasesLap'));
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    expect(dropdown.hitTestable(), findsOneWidget);
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final item = find.textContaining('${other.displayName} · ').last;
    expect(item.hitTestable(), findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
    final theirs = phases.lossesOf(other.reference);
    expect(
      _text(
        tester,
        find.byKey(ValueKey('bestPhasesPiece $split')),
      ).split('|').last,
      displayDelta(theirs[split]!),
    );
    expect(
      value('bestPhasesLapTime'),
      displayTime(phases.lapTotal(other.reference)!),
    );
  });

  testWidgets('a corner not split, laps that do not join, and joins not known', (
    tester,
  ) async {
    await _pump(tester, BestPhasesCard(result: _built()));
    // The corner that is not split says why, and is taken whole.
    final whole = find.byKey(const ValueKey('bestPhasesSegment 2'));
    expect(
      find.descendant(
        of: whole,
        matching: find.text('Not split: more than one tight part'),
      ),
      findsOneWidget,
    );
    expect(
      _text(tester, find.byKey(const ValueKey('bestPhasesSegmentLoss 2'))),
      'Corners 2–3|Not split: more than one tight part|'
      'Best 8.800 s, Session 1 · LAP 1 · this lap set it|±0.000\u00a0s',
    );
    // The middle comes from lap B, 0.2 s quicker; it does not join.
    expect(
      _text(tester, find.byKey(const ValueKey('bestPhasesPiece 2'))),
      'Middle|Best 1.300 s, Session 2 · LAP 2 · this lap 1.500 s|'
      'Does not join the part before: 2.9\u00a0km/h apart|+0.200\u00a0s',
    );
    expect(
      find.text(
        'At 1 of 1 line where two laps meet, their speeds differ by more than '
        '2.0\u00a0km/h: there the best phases is not a lap the car drove.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Corner 1 · Entry → Corner 1 · Middle: 2.9\u00a0km/h apart'),
      findsOneWidget,
    );
    expect(
      find.text(
        '1 more line could not be checked: a lap has no speed in a known unit there.',
      ),
      findsOneWidget,
    );
    // The corner's loss is its parts' together.
    expect(
      _text(tester, find.byKey(const ValueKey('bestPhasesSegmentLoss 1'))),
      'Corner 1|+0.400\u00a0s',
    );
    // No raw best, no typical yet: never zero.
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('bestPhasesRaw value')))
          .data,
      '—',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('bestPhasesTypical')),
        matching: find.text('—'),
      ),
      findsOneWidget,
    );

    // Lap B is not timed through the last corner: no loss, no lap total.
    await tester.tap(find.byKey(const ValueKey('bestPhasesLap')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Session 2 · LAP 2 · ').last);
    await tester.pumpAndSettle();
    expect(
      _text(tester, find.byKey(const ValueKey('bestPhasesSegmentLoss 2'))),
      'Corners 2–3|Not split: more than one tight part|'
      'Best 8.800 s, Session 1 · LAP 1 · this lap is not timed here|—',
    );
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('bestPhasesLoss'))).data,
      '—',
    );
    expect(
      find.textContaining('not offered as a reference lap'),
      findsOneWidget,
    );
  });

  testWidgets('speeds in different units are shown in m/s', (tester) async {
    final built = _built();
    final phases = built.bestPhases!;
    await _pump(
      tester,
      BestPhasesCard(
        result: DayTheoreticalBest(
          groupId: 'g',
          state: DayTheoreticalBestState.ready,
          bestLap: built.bestLap,
          laps: built.laps,
          bestPhases: PhaseReference(
            pieces: phases.pieces,
            totalSeconds: phases.totalSeconds,
            joinedUnavailableReason: phaseReferenceNoSpeed,
            lapSeconds: phases.lapSeconds,
          ),
        ),
      ),
    );
    expect(
      find.text('Corner 1 · Entry → Corner 1 · Middle: 0.8\u00a0m/s apart'),
      findsOneWidget,
    );
    expect(find.textContaining('0.6\u00a0m/s'), findsOneWidget);
  });

  testWidgets('while it is worked out, and without a result', (tester) async {
    await _pump(tester, const BestPhasesCard(result: null, loading: true));
    expect(find.byKey(const ValueKey('bestPhasesWorking')), findsOneWidget);
    expect(
      find.text(
        'Each corner\'s best entry, middle and exit of the day, as a target.',
      ),
      findsOneWidget,
    );
    await _pump(
      tester,
      BestPhasesCard(
        key: const ValueKey('unavailable'),
        result: DayTheoreticalBest(
          groupId: 'g',
          state: DayTheoreticalBestState.unavailable,
          message: 'No eligible laps in this group to calculate a theoretical best from.',
        ),
      ),
      open: false,
    );
    // The page remembers the card was opened.
    if (find.text('Show').evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('bestPhasesToggle')));
      await tester.pumpAndSettle();
    }
    expect(find.byKey(const ValueKey('bestPhasesUnavailable')), findsOneWidget);
    expect(
      find.text(
        'Not shown: No eligible laps in this group to calculate a theoretical best from.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('fits a small phone with text ×2', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: Scaffold(
              body: ListView(children: [BestPhasesCard(result: _built())]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final toggle = find.byKey(const ValueKey('bestPhasesToggle'));
    expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
    // A tap that misses fails here rather than warning.
    Future<void> tapOn(Finder target) async {
      await tester.scrollUntilVisible(
        target,
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(target.hitTestable(), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await tapOn(toggle);
    expect(tester.takeException(), isNull);
    await tapOn(find.byKey(const ValueKey('bestPhasesLap')));
    final item = find.textContaining('Session 2 · LAP 2 · ').last;
    expect(item.hitTestable(), findsOneWidget);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final row = find.byKey(const ValueKey('bestPhasesPiece 2'));
    await tester.scrollUntilVisible(
      row,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      _text(tester, row),
      'Middle|±0.000\u00a0s|Best 1.300 s, Session 2 · LAP 2 · this lap set it|'
      'Does not join the part before: 2.9\u00a0km/h apart',
      reason: 'at text ×2 the loss goes under the name',
    );
    expect(tester.getRect(row).right, lessThanOrEqualTo(320));
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.overflow, isNot(TextOverflow.visible));
    }
  });

  testWidgets('the card speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    await _pump(
      tester,
      BestPhasesCard(result: _built()),
      locale: const Locale('pl'),
    );
    expect(find.text('Najlepsze fazy'), findsWidgets);
    expect(find.text('Najlepsze fazy, które się łączą'), findsOneWidget);
    expect(find.text('Gdzie spotykają się okrążenia'), findsOneWidget);
    expect(
      _text(tester, find.byKey(const ValueKey('bestPhasesPiece 2'))),
      'Środek|Najlepiej 1.300 s, Sesja 2 · OKR. 2 · to okrążenie 1.500 s|'
      'Nie łączy się z poprzednią częścią: różnica 2.9\u00a0km/h|+0.200\u00a0s',
    );
    expect(
      find.text('Nie podzielono: więcej niż jedna najciaśniejsza część'),
      findsOneWidget,
    );
    expect(find.text('Część po części'), findsOneWidget);
    expect(find.text('Traci'), findsOneWidget);
    expect(find.textContaining('Best'), findsNothing);
  });
}
