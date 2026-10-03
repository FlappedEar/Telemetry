import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/corner_details.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/day/telemetry_chart.dart';
import 'package:telemetry/day/touch.dart';
import 'package:telemetry/day/track_dialog.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/diagnostics/diagnostics_page.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';

import '../day/blank_tiles.dart';
import '../day/driving_vbo.dart';
import '../day/rectangle_vbo.dart';
import '../support/temp_directory.dart';

/// The phone and tablet sizes the owner uses at the track.
const sizes = {
  'small phone portrait': Size(360, 740),
  'Pixel portrait': Size(412, 915),
  'tablet landscape': Size(1180, 820),
};

/// [androidTapTargetGuideline] for a screen in the middle of a scrolled
/// list: a target the list's edge cuts is measured by its whole size, not
/// by the part on screen, so every scroll position can be checked.
class _ListTapTargetGuideline extends MinimumTapTargetGuideline {
  const _ListTapTargetGuideline(this.sizes)
    : super(
        size: const Size(48, 48),
        link: 'https://support.google.com/accessibility/android/answer/7101858',
      );

  /// The whole size of the render box behind each semantics node, by id.
  final Map<int, Size> sizes;

  /// [sizes] for the render tree on screen now.
  static Map<int, Size> measure(WidgetTester tester) {
    final sizes = <int, Size>{};
    void visit(RenderObject object) {
      final node = object.debugSemantics;
      if (node != null && object is RenderBox && object.hasSize) {
        sizes[node.id] = object.size;
      }
      object.visitChildren(visit);
    }

    for (final view in tester.binding.renderViews) {
      visit(view);
    }
    return sizes;
  }

  @override
  bool shouldSkipNode(SemanticsNode node) {
    if (super.shouldSkipNode(node)) return true;
    final whole = sizes[node.id];
    return whole != null && whole.width >= 47.99 && whole.height >= 47.99;
  }
}

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('touch'));
  tearDown(() => deleteTemporaryDirectory(directory));

  // A synthetic day with pedals, G, an oil temperature and heart rate, its
  // theoretical best and channel summaries calculated. No real data.
  Future<DayResultsController> day() async {
    final files = {
      'a.vbo': [
        rectangleBrakingLap(250, 15),
        rectangleBrakingLap(240, 13),
        rectangleBrakingLap(255, 15.5),
      ],
      'b.vbo': [
        rectangleBrakingLap(260, 14),
        rectangleBrakingLap(262, 16),
        rectangleBrakingLap(250, 14.5),
      ],
    };
    final paths = <String>[];
    files.forEach((name, laps) {
      final path = '${directory.path}/$name';
      File(path).writeAsStringSync(
        withAcceleration(
          rectangleVbo(laps, pedals: true, car: true),
          liftOff: true,
        ),
      );
      paths.add(path);
    });
    final outcome = runDayImport((paths: paths, includeSubfolders: false));
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
      theoreticalBestRunner: (job) async => job(),
      channelSummariesRunner: (job) async => job(),
    );
    await controller.requestTheoreticalBest();
    await controller.requestChannelSummaries();
    return controller;
  }

  Finder inKey(String key) => find
      .descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Scrollable),
      )
      .first;
  Finder firstList() => find
      .byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      )
      .hitTestable()
      .first;

  /// The semantics tree built afresh for what is on screen now: a scrolled
  /// list keeps the clipped rectangles of its earlier position otherwise.
  Future<SemanticsHandle> semanticsOn(WidgetTester tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pump();
    return semantics;
  }

  /// Every target on screen is at least 48 × 48 dp and has a label.
  Future<void> checkScreen(WidgetTester tester) async {
    final semantics = await semanticsOn(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    semantics.dispose();
  }

  /// [checkScreen] at every position of [list], from top to bottom.
  Future<void> checkList(WidgetTester tester, Finder list) async {
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    for (var step = 0; step < 60; ++step) {
      final semantics = await semanticsOn(tester);
      await expectLater(
        tester,
        meetsGuideline(
          _ListTapTargetGuideline(_ListTapTargetGuideline.measure(tester)),
        ),
      );
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
      if (position.pixels >= position.maxScrollExtent - 1) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.6)
            .clamp(0.0, position.maxScrollExtent)
            .toDouble(),
      );
      await tester.pumpAndSettle();
    }
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> show(WidgetTester tester, Size size, double textScale) async {
    await tester.binding.setSurfaceSize(size);
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  for (final MapEntry(key: name, value: size) in sizes.entries) {
    for (final textScale in const [1.0, 1.3]) {
      // Large text on the small phone and the tablet.
      if (textScale != 1.0 && size.width == 412) continue;
      final variant = textScale == 1.0 ? name : '$name, text ×$textScale';
      group(variant, () {
        testWidgets('the day page, its sheets and its pages have 48 dp '
            'targets with labels', (tester) async {
          await show(tester, size, textScale);
          final controller = (await tester.runAsync(day))!;
          await tester.pumpWidget(
            TelemetryApp(
              home: DayResultsPage.controller(controller: controller),
            ),
          );
          await tester.pumpAndSettle();
          final narrow = size.width < 900;
          await checkList(tester, inKey('dayResultsSummary'));
          if (narrow) {
            await tester.tap(
              find.widgetWithText(NavigationDestination, 'Laps'),
            );
            await tester.pumpAndSettle();
          }
          await checkList(tester, inKey('dayResultsLaps'));
          if (narrow) {
            await tester.tap(find.widgetWithText(NavigationDestination, 'Day'));
            await tester.pumpAndSettle();
          }
          final summary = inKey('dayResultsSummary');
          Future<void> open(Finder target) async {
            tester.state<ScrollableState>(summary).position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester.scrollUntilVisible(target, 300, scrollable: summary);
            await tester.ensureVisible(target);
            await tester.pumpAndSettle();
            await tester.tap(target);
            await tester.pumpAndSettle();
          }

          // The theoretical best's corner, in its sheet.
          await open(find.byKey(const ValueKey('lossRow Corner 1')));
          expect(find.byType(CornerDetails), findsOneWidget);
          await checkScreen(tester);
          await tester.tapAt(const Offset(4, 4));
          await tester.pumpAndSettle();

          // The segment editor, with a segment's tools open.
          await open(find.byKey(const ValueKey('editSegments')));
          await checkList(tester, firstList());
          await tester.tap(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'segment ',
                      ),
                )
                .first,
          );
          await tester.pumpAndSettle();
          await checkList(tester, firstList());
          await tester.pageBack();
          await tester.pumpAndSettle();

          // A focus area, a channel and the day report.
          await open(find.byKey(const ValueKey('focusArea 0')));
          await checkList(tester, firstList());
          await tester.pageBack();
          await tester.pumpAndSettle();
          await open(find.byKey(const ValueKey('carChannel oil_temp')));
          await checkList(tester, firstList());
          await tester.pageBack();
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('openDayReport')));
          await tester.pumpAndSettle();
          await checkList(tester, firstList());
          await tester.pageBack();
          await tester.pumpAndSettle();

          // A circuit's dialog.
          tester.state<ScrollableState>(summary).position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(
            find.text('Circuits'),
            300,
            scrollable: summary,
          );
          // The circuit's edit button, which may be just past the heading.
          for (
            var i = 0;
            i < 20 && find.byIcon(Icons.edit_outlined).evaluate().isEmpty;
            ++i
          ) {
            await tester.drag(summary, const Offset(0, -100));
            await tester.pumpAndSettle();
          }
          final circuit = find.byIcon(Icons.edit_outlined).first;
          await tester.ensureVisible(circuit);
          await tester.pumpAndSettle();
          await tester.tap(circuit);
          await tester.pumpAndSettle();
          expect(find.byType(TrackDialog), findsOneWidget);
          await checkScreen(tester);
          await tester.binding.handlePopRoute();
          await tester.pumpAndSettle();

          // The More menu, and the diagnostics page it opens.
          await tester.tap(find.byKey(const ValueKey('moreMenu')));
          await tester.pumpAndSettle();
          await checkScreen(tester);
          await tester.tap(find.byKey(const ValueKey('openDiagnostics')));
          await tester.pumpAndSettle();
          expect(find.byType(DiagnosticsPage), findsOneWidget);
          await checkList(tester, firstList());
        });

        testWidgets('the import page and its menu have 48 dp targets with '
            'labels', (tester) async {
          await show(tester, size, textScale);
          await tester.pumpWidget(const TelemetryApp(home: DayImportPage()));
          await tester.pumpAndSettle();
          await checkScreen(tester);
          await tester.tap(find.byKey(const ValueKey('moreMenu')));
          await tester.pumpAndSettle();
          await checkScreen(tester);
        });

        testWidgets('the lap page and the comparison have 48 dp targets '
            'with labels', (tester) async {
          await show(tester, size, textScale);
          final controller = (await tester.runAsync(day))!;
          addTearDown(controller.dispose);
          final best = controller.analysis.ranking!.bestOfDay!;
          await tester.pumpWidget(
            TelemetryApp(
              home: LapPage(controller: controller, row: best),
            ),
          );
          await tester.pumpAndSettle();
          await checkList(tester, firstList());

          // The lap picker.
          final compare = find.byKey(const ValueKey('lapCompare'));
          await tester.ensureVisible(compare);
          await tester.pumpAndSettle();
          await tester.tap(compare);
          await tester.pumpAndSettle();
          await checkScreen(tester);
          await tester.tap(
            find
                .byWidgetPredicate(
                  (widget) =>
                      widget.key is ValueKey<String> &&
                      (widget.key! as ValueKey<String>).value.startsWith(
                        'suggestedLap ',
                      ),
                )
                .first,
          );
          await tester.pumpAndSettle();
          expect(find.byType(ComparisonPage), findsOneWidget);

          // Opened on a segment: the Corner Analyzer, G-G, driving states
          // and coasting come first.
          final other = controller
              .comparisonCandidates(best)
              .firstWhere((row) => row.reference != best.reference);
          await tester.pumpWidget(
            TelemetryApp(
              home: ComparisonPage(
                controller: controller,
                a: other,
                b: best,
                segmentId: controller.theoreticalBest!.segments[1].segmentId,
                fromTheoreticalBest: true,
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (size.width >= 900) {
            await checkList(tester, inKey('comparisonSummary'));
            await checkList(tester, inKey('comparisonCharts'));
          } else {
            await checkList(tester, inKey('comparisonSummary'));
          }
        });
      });
    }
  }

  group('gestures on a phone', () {
    testWidgets('one finger scrolls the page over the map; two fingers '
        'zoom and move it', (tester) async {
      await show(tester, const Size(412, 915), 1);
      final controller = (await tester.runAsync(day))!;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        TelemetryApp(
          home: LapPage(
            controller: controller,
            row: controller.analysis.ranking!.bestOfDay!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.state<ScrollableState>(firstList()).position;
      final map = find.byType(TrackMap);
      final zoom = find.descendant(
        of: find.byType(PinchZoom),
        matching: find.byType(Transform),
      );
      double scale() =>
          tester.widget<Transform>(zoom).transform.getMaxScaleOnAxis();

      // One finger, upward on the map: the page scrolls, the map stays.
      await tester.dragFrom(tester.getCenter(map), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(page.pixels, greaterThan(100));
      expect(scale(), 1);
      // Sideways, one finger leaves the map as it is too.
      await tester.dragFrom(tester.getCenter(map), const Offset(-150, 0));
      await tester.pumpAndSettle();
      expect(scale(), 1);
      page.jumpTo(0);
      await tester.pumpAndSettle();

      // Two fingers apart, moving up as they go: the map zooms, the page
      // does not scroll.
      final centre = tester.getCenter(map);
      final first = await tester.startGesture(centre - const Offset(30, 0));
      final second = await tester.startGesture(centre + const Offset(30, 0));
      for (var step = 1; step <= 10; ++step) {
        await first.moveBy(const Offset(-8, -6));
        await second.moveBy(const Offset(8, -6));
        await tester.pump();
      }
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(scale(), greaterThan(2));
      expect(page.pixels, 0);

      // Two fingers together move the zoomed map.
      final before = tester.widget<Transform>(zoom).transform.getTranslation();
      final third = await tester.startGesture(centre - const Offset(20, 0));
      final fourth = await tester.startGesture(centre + const Offset(20, 0));
      for (var step = 1; step <= 5; ++step) {
        await third.moveBy(const Offset(10, 0));
        await fourth.moveBy(const Offset(10, 0));
        await tester.pump();
      }
      await third.up();
      await fourth.up();
      await tester.pumpAndSettle();
      final after = tester.widget<Transform>(zoom).transform.getTranslation();
      expect(after.x, greaterThan(before.x));
      expect(page.pixels, 0);
    });

    // The maps people see draw over tiles: the lap's map and the
    // comparison's, each tried with one finger, two fingers and a double tap.
    for (final comparison in const [false, true]) {
      testWidgets('over tiles, one finger scrolls the '
          '${comparison ? 'comparison' : 'lap'} page past the map; two '
          'fingers and a double tap zoom it', (tester) async {
        await show(tester, const Size(412, 915), 1);
        mapBackground.value = MapBackground.streets;
        debugTileProvider = BlankTiles.new;
        addTearDown(() {
          mapBackground.value = MapBackground.none;
          debugTileProvider = null;
        });
        final controller = (await tester.runAsync(day))!;
        addTearDown(controller.dispose);
        final best = controller.analysis.ranking!.bestOfDay!;
        final other = controller
            .comparisonCandidates(best)
            .firstWhere((row) => row.reference != best.reference);
        await tester.pumpWidget(
          TelemetryApp(
            home: comparison
                ? ComparisonPage(controller: controller, a: other, b: best)
                : LapPage(controller: controller, row: best),
          ),
        );
        await tester.pumpAndSettle();
        final map = find.byType(FlutterMap);
        expect(map, findsOneWidget);
        await tester.ensureVisible(map);
        await tester.pumpAndSettle();
        final page = tester
            .state<ScrollableState>(
              find.ancestor(of: map, matching: find.byType(Scrollable)).first,
            )
            .position;
        MapCamera camera() =>
            MapCamera.of(tester.element(find.byType(MapAttribution)));
        final start = camera();

        // One finger, up or down on the map: the page scrolls, the map
        // stays where it was.
        final scrolled = page.pixels;
        final room = page.maxScrollExtent - scrolled;
        await tester.dragFrom(
          tester.getCenter(map),
          Offset(0, room > 100 ? -150 : 150),
        );
        await tester.pumpAndSettle();
        expect((page.pixels - scrolled).abs(), greaterThan(80));
        expect(camera().zoom, start.zoom);
        expect(camera().center, start.center);
        await tester.ensureVisible(map);
        await tester.pumpAndSettle();

        // Two fingers apart: the map zooms and the page stays.
        final top = page.pixels;
        final centre = tester.getCenter(map);
        final first = await tester.startGesture(centre - const Offset(30, 0));
        final second = await tester.startGesture(centre + const Offset(30, 0));
        for (var step = 1; step <= 10; ++step) {
          await first.moveBy(const Offset(-8, -6));
          await second.moveBy(const Offset(8, -6));
          await tester.pump();
        }
        await first.up();
        await second.up();
        await tester.pumpAndSettle();
        final pinched = camera().zoom;
        expect(pinched, greaterThan(start.zoom + 1));
        expect(page.pixels, top);

        // Two fingers together move it.
        final moved = camera().center;
        final third = await tester.startGesture(centre - const Offset(20, 0));
        final fourth = await tester.startGesture(centre + const Offset(20, 0));
        for (var step = 1; step <= 5; ++step) {
          await third.moveBy(const Offset(10, 0));
          await fourth.moveBy(const Offset(10, 0));
          await tester.pump();
        }
        await third.up();
        await fourth.up();
        await tester.pumpAndSettle();
        expect(camera().center.longitude, lessThan(moved.longitude));
        expect(camera().zoom, closeTo(pinched, 1e-6));
        expect(page.pixels, top);

        // A double tap zooms in further.
        await tester.tapAt(centre);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tapAt(centre);
        await tester.pumpAndSettle();
        expect(camera().zoom, greaterThan(pinched + 0.5));
      });
    }

    testWidgets('a drag up a chart scrolls the page and leaves the cursor; '
        'a sideways drag or a tap moves it', (tester) async {
      await show(tester, const Size(412, 915), 1);
      final controller = (await tester.runAsync(day))!;
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        TelemetryApp(
          home: LapPage(
            controller: controller,
            row: controller.analysis.ranking!.bestOfDay!,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final page = tester.state<ScrollableState>(firstList()).position;
      final chart = find.byType(TelemetryChart).first;
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      double cursor() => tester.widget<TelemetryChart>(chart).cursor.value;
      final start = cursor();
      final scrolled = page.pixels;

      await tester.dragFrom(
        tester.getCenter(chart) + const Offset(0, 40),
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(page.pixels, greaterThan(scrolled + 100));
      expect(cursor(), start);

      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();
      final top = page.pixels;
      await tester.dragFrom(
        tester.getCenter(chart) + const Offset(-100, 40),
        const Offset(150, 0),
      );
      await tester.pumpAndSettle();
      expect(cursor(), isNot(start));
      expect(page.pixels, top);

      final moved = cursor();
      await tester.tapAt(tester.getCenter(chart) + const Offset(-150, 40));
      await tester.pumpAndSettle();
      expect(cursor(), isNot(moved));
    });
  });

  group('back on a phone', () {
    testWidgets('closes the sheet and the dialog and keeps the lap chosen, '
        'also when the list scrolls it away', (tester) async {
      await show(tester, const Size(412, 915), 1);
      final controller = (await tester.runAsync(day))!;
      await tester.pumpWidget(
        TelemetryApp(home: DayResultsPage.controller(controller: controller)),
      );
      await tester.pumpAndSettle();
      final summary = inKey('dayResultsSummary');
      Future<void> reach(Finder target) async {
        await tester.scrollUntilVisible(target, 300, scrollable: summary);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
      }

      // A lap chosen in the sector table.
      final result = controller.theoreticalBest!;
      final other = result.laps.firstWhere((lap) => !lap.bestOfDay);
      final row = find.byKey(ValueKey('sectorRow ${other.lap.displayName}'));
      await reach(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      DayLapReference chosen() => tester
          .widget<DropdownButton<DayLapReference>>(
            find.byKey(const ValueKey('lossLap')),
          )
          .value!;
      expect(chosen(), other.lap.reference);

      // The system back closes a sheet, then a dialog, not the page.
      final corner = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('lossRow '),
      );
      await reach(corner.first);
      await tester.tap(corner.first);
      await tester.pumpAndSettle();
      expect(find.byType(CornerDetails), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(CornerDetails), findsNothing);
      expect(find.byType(DayResultsPage), findsOneWidget);

      await reach(find.text('Circuits'));
      final circuit = find.byIcon(Icons.edit_outlined).first;
      await reach(circuit);
      await tester.tap(circuit);
      await tester.pumpAndSettle();
      expect(find.byType(TrackDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TrackDialog), findsNothing);
      expect(find.byType(DayResultsPage), findsOneWidget);

      // A lap opened and closed with back: the day page is as it was.
      await tester.tap(find.widgetWithText(NavigationDestination, 'Laps'));
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byKey(const ValueKey('dayResultsLaps')),
              matching: find.text(other.lap.displayName),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.byType(LapPage), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LapPage), findsNothing);
      await tester.tap(find.widgetWithText(NavigationDestination, 'Day'));
      await tester.pumpAndSettle();

      // Scrolled to the end, which rebuilds the card on the way back.
      final position = tester.state<ScrollableState>(summary).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('lossLap')), findsNothing);
      position.jumpTo(0);
      await tester.pumpAndSettle();
      await reach(find.byKey(const ValueKey('lossLap')));
      expect(chosen(), other.lap.reference);
    });

    testWidgets('the Corner Analyzer keeps its segment and zoom when the '
        'page scrolls it away and back', (tester) async {
      await show(tester, const Size(412, 915), 1);
      final controller = (await tester.runAsync(day))!;
      addTearDown(controller.dispose);
      final best = controller.analysis.ranking!.bestOfDay!;
      final other = controller
          .comparisonCandidates(best)
          .firstWhere((row) => row.reference != best.reference);
      await tester.pumpWidget(
        TelemetryApp(
          home: ComparisonPage(
            controller: controller,
            a: other,
            b: best,
            segmentId: controller.theoreticalBest!.segments[1].segmentId,
            fromTheoreticalBest: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('cornerAnalyzerNext'));
      await tester.ensureVisible(next);
      await tester.pumpAndSettle();
      await tester.tap(next);
      await tester.pumpAndSettle();
      String? segment() => tester
          .widget<DropdownButton<String>>(
            find.byKey(const ValueKey('cornerAnalyzerSegmentPicker')),
          )
          .value;
      final chosen = segment();
      (double, double) range() {
        final chart = tester.widget<TelemetryChart>(
          find.byType(TelemetryChart, skipOffstage: false).first,
        );
        return (chart.start, chart.end);
      }

      final list = inKey('comparisonSummary');
      final position = tester.state<ScrollableState>(list).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cornerAnalyzer')), findsNothing);
      final zoomed = range();
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(segment(), chosen);
      // Not zoomed back to the segment it was opened on, nor scrolled.
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(range(), zoomed);
    });
  });
}
