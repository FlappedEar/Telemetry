import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/channel_names.dart';
import 'package:telemetry/day/day_context.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/comparison_page.dart';
import 'package:telemetry/day/lap_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry_core/telemetry_core.dart' show deltaTimeChannel;

import 'day/rectangle_vbo.dart';
import 'support/temp_directory.dart';

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('channelNames');
    channelNamesSetting.value = const {};
    listedChannelsSetting.value = const [];
    rememberedLapChannels.value = null;
  });
  tearDown(() {
    channelNamesSetting.value = const {};
    listedChannelsSetting.value = const [];
    deleteTemporaryDirectory(directory);
  });

  DayImportOutcome importDay() {
    final path = '${directory.path}/a.vbo';
    File(path).writeAsStringSync(
      rectangleVbo(
        [rectangleLap(30), rectangleLap(31)],
        pedals: true,
        car: true,
      ),
    );
    return runDayImport((paths: [path], includeSubfolders: false));
  }

  // The channels charted on the lap page.
  List<String> lapChannels(WidgetTester tester) => [
    for (final element
        in find
            .byWidgetPredicate(
              (widget) =>
                  widget.key is ValueKey<String> &&
                  (widget.key! as ValueKey<String>).value.startsWith(
                    'lapChart ',
                  ),
            )
            .evaluate())
      (element.widget.key! as ValueKey<String>).value.substring(9),
  ];

  test('settings read back only well-formed, bounded names and stars', () {
    expect(readChannelNames(null), isEmpty);
    expect(readChannelNames(['Throttle']), isEmpty);
    expect(
      readChannelNames({
        'accelerator_pos-obd': ' Throttle ',
        'rpm': 3,
        'blank': '  ',
        'long': 'x' * 100,
      }),
      {'accelerator_pos-obd': 'Throttle', 'long': 'x' * 40},
    );
    expect(
      readChannelNames({for (var i = 0; i < 600; i++) 'c$i': 'n$i'}).length,
      maximumSettingsChannels,
    );
    expect(readListedChannels('rpm'), isEmpty);
    expect(readListedChannels(['rpm', 'rpm', '', 3, 'brake']), [
      'rpm',
      'brake',
    ]);
  });

  test('names are trimmed, and a blank name shows the recorded one', () {
    setChannelName('accelerator_pos-obd', '  Throttle ');
    expect(channelDisplayName('accelerator_pos-obd'), 'Throttle');
    expect(channelDisplayName('velocity'), 'velocity');
    setChannelName('accelerator_pos-obd', ' ');
    expect(channelNamesSetting.value, isEmpty);
    expect(channelDisplayName('accelerator_pos-obd'), 'accelerator_pos-obd');
  });

  test('a picked channel takes the chart\'s place', () {
    expect(replaceChannel(['a', 'b', 'c'], 'b', 'd'), ['a', 'd', 'c']);
    // A channel already charted moves rather than showing twice.
    expect(replaceChannel(['a', 'b', 'c'], 'a', 'c'), ['c', 'b']);
  });

  test('once channels are starred, menus list only those and Δ time', () {
    final channels = [deltaTimeChannel, 'velocity', 'throttle', 'rpm'];
    expect(listedChoices(channels), channels);
    setChannelListed('rpm', true);
    setChannelListed('rpm', true);
    expect(listedChannelsSetting.value, ['rpm']);
    expect(listedChoices(channels), [deltaTimeChannel, 'rpm']);
    // With every starred channel charted, the menu lists none but All
    // channels, rather than all of them again.
    expect(listedChoices(['velocity', 'throttle']), isEmpty);
    setChannelListed('rpm', false);
    expect(listedChannelsSetting.value, isEmpty);
  });

  test('the open day lists its recorded channels until it closes', () {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    expect(
      openDayContext.recordedChannels,
      containsAll(['velocity', 'throttle', 'brake']),
    );
    expect(
      openDayContext.recordedChannels,
      orderedEquals([...openDayContext.recordedChannels]..sort()),
    );
    controller.dispose();
    expect(openDayContext.recordedChannels, isEmpty);
  });

  testWidgets('a chart shows its given name and swaps channel from its title', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    final row = outcome.analysis!.rows.firstWhere((row) => row.lapNumber == 1);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapChart throttle')), findsOneWidget);
    expect(find.byKey(const ValueKey('lapChart brake')), findsNothing);

    // A name given in settings shows at once, with the recorded name.
    setChannelName('throttle', 'Throttle pedal');
    await tester.pump();
    expect(find.text('Throttle pedal'), findsOneWidget);
    expect(find.text('recorded as throttle'), findsOneWidget);

    // The title lists the channels not charted; one picked takes its place.
    await tester.tap(find.byKey(const ValueKey('chartPick throttle')));
    await tester.pumpAndSettle();
    final offered = [
      for (final item in tester.widgetList<PopupMenuItem<String>>(
        find.byType(PopupMenuItem<String>),
      ))
        item.value,
    ];
    expect(offered, contains('brake'));
    for (final shown in rememberedLapChannels.value ?? lapChannels(tester)) {
      expect(offered, isNot(contains(shown)));
    }
    await tester.tap(find.text('brake').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lapChart brake')), findsOneWidget);
    expect(find.byKey(const ValueKey('lapChart throttle')), findsNothing);
    expect(rememberedLapChannels.value, contains('brake'));

    // The add menu lists a named channel by both names.
    await tester.tap(find.byKey(const ValueKey('addChartChannel')));
    await tester.pumpAndSettle();
    expect(find.text('Throttle pedal · throttle'), findsOneWidget);
  });

  testWidgets('settings name every recorded channel of the open day', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const TelemetryApp(home: Scaffold(body: SettingsButton())),
    );
    await tester.tap(find.byType(SettingsButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('openChannelNames')));
    await tester.pumpAndSettle();
    for (final channel in openDayContext.recordedChannels) {
      expect(find.byKey(ValueKey('channelName $channel')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('channelNamesNoDay')), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('channelNameField throttle')),
      'Throttle',
    );
    await tester.pump();
    expect(channelNamesSetting.value, {'throttle': 'Throttle'});
    expect(find.text('Shown as Throttle'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('channelNameClear throttle')));
    await tester.pump();
    expect(channelNamesSetting.value, isEmpty);
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('channelNameField throttle')),
          )
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('without a day open, named channels are still listed', (
    tester,
  ) async {
    setChannelName('accelerator_pos-obd', 'Throttle');
    await tester.pumpWidget(const TelemetryApp(home: ChannelNamesPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('channelNamesNoDay')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('channelName accelerator_pos-obd')),
      findsOneWidget,
    );
  });

  testWidgets('stars limit the chart menus, and All channels lists the rest', (
    tester,
  ) async {
    final outcome = importDay();
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    addTearDown(controller.dispose);
    final row = outcome.analysis!.rows.firstWhere((row) => row.lapNumber == 1);
    await tester.binding.setSurfaceSize(const Size(1200, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Starred in settings.
    await tester.pumpWidget(const TelemetryApp(home: ChannelNamesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('channelListed brake')));
    await tester.pump();
    expect(listedChannelsSetting.value, ['brake']);

    await tester.pumpWidget(
      TelemetryApp(
        home: LapPage(controller: controller, row: row),
      ),
    );
    await tester.pumpAndSettle();
    final hidden = [
      for (final channel in openDayContext.recordedChannels)
        if (channel != 'brake' &&
            find.byKey(ValueKey('lapChart $channel')).evaluate().isEmpty &&
            channel != 'latitude' &&
            channel != 'longitude')
          channel,
    ];
    expect(hidden, isNotEmpty);
    await tester.tap(find.byKey(const ValueKey('chartPick throttle')));
    await tester.pumpAndSettle();
    expect(find.text('brake'), findsOneWidget);
    for (final channel in hidden) {
      expect(find.text(channel), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('chartAllChannels')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a channel'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('allChannels ${hidden.first}')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('lapChart ${hidden.first}')), findsOneWidget);
    expect(find.byKey(const ValueKey('lapChart throttle')), findsNothing);
  });

  testWidgets('the comparison swaps its Δ time chart from the title', (
    tester,
  ) async {
    final outcome = importDay();
    final analysis = outcome.analysis!;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: analysis,
    );
    addTearDown(controller.dispose);
    final best = analysis.ranking!.bestOfDay!;
    final a = controller
        .comparisonCandidates(best)
        .firstWhere((row) => row.reference != best.reference);
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: ComparisonPage(controller: controller, a: a, b: best),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('comparisonChart $deltaTimeChannel')),
      findsOneWidget,
    );
    final deltaTitle = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('chartPick Δ'),
    );
    await tester.tap(deltaTitle);
    await tester.pumpAndSettle();
    final picked = tester
        .widgetList<PopupMenuItem<String>>(find.byType(PopupMenuItem<String>))
        .first
        .value!;
    await tester.tap(find.byType(PopupMenuItem<String>).first);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('comparisonChart $deltaTimeChannel')),
      findsNothing,
    );
    expect(find.byKey(ValueKey('comparisonChart $picked')), findsOneWidget);
    // No chart shows twice, and Δ time is offered back in the app's words.
    final shown = controller.savedComparison.channels!;
    expect(shown, contains(picked));
    expect(shown.toSet().length, shown.length);
    await tester.tap(find.byKey(ValueKey('chartPick $picked')));
    await tester.pumpAndSettle();
    expect(find.text('Δ time (A − B)'), findsWidgets);
  });
}
