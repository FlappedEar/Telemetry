import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day/day_results_page_test.dart' show FakeDocuments, circuitVbo;
import 'support/temp_directory.dart';

/// A tiny synthetic VBO whose header declares [velocityHeader].
TelemetrySession vbo(Directory directory, String velocityHeader) {
  final file = File('${directory.path}/${velocityHeader.hashCode}.vbo')
    ..writeAsStringSync(
      '[header]\ntime\nlatitude\nlongitude\n$velocityHeader\n'
      '[column names]\ntime lat long velocity\n[data]\n'
      '0.00 52.0 21.0 50.0\n0.10 52.0001 21.0 51.0\n',
    );
  return parseVboFile(file.path);
}

void main() {
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('units');
    speedUnitSetting.value = SpeedUnitSetting.automatic;
    declareDaySpeedUnits(const []);
  });
  tearDown(() => deleteTemporaryDirectory(directory));

  test('reads the speed unit from the VBO header, as a label only', () {
    final kmh = vbo(directory, 'velocity kmh');
    final mph = vbo(directory, 'velocity mph');
    final none = vbo(directory, 'velocity');
    expect(sessionSpeedUnit(kmh), 'km/h');
    expect(sessionSpeedUnit(mph), 'mph');
    expect(sessionSpeedUnit(none), '');
    // The recorded channel keeps no unit: values are never converted.
    expect(kmh.channels[kmh.aliases['speed']]!.unit, '');
  });

  test('a declared unit is never overridden by the setting', () {
    declaredSpeedUnits = const ['km/h'];
    for (final setting in SpeedUnitSetting.values) {
      speedUnitSetting.value = setting;
      expect(speedUnitLabel(), 'km/h', reason: '$setting');
      expect(speedUnitLabel('km/h'), 'km/h', reason: '$setting');
      expect(speedUnitLabel('kmh'), 'km/h', reason: '$setting');
      expect(speedUnitLabel('mph'), 'mph', reason: '$setting');
      expect(displayUnit('velocity-obd', ''), 'km/h', reason: '$setting');
    }
    expect(displayUnit('coolant_temp-obd', '°C'), '°C');
  });

  test('the setting is assumed only for unlabelled speeds', () {
    declaredSpeedUnits = const [''];
    expect(speedUnitLabel(), '');
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    expect(speedUnitLabel(), 'mph');
    expect(displayUnit('velocity', ''), 'mph');
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    expect(speedUnitLabel(), 'km/h');
    // A channel's own unit still wins over the assumption.
    expect(speedUnitLabel('mph'), 'mph');
  });

  test('a day mixing units shows none rather than a wrong one', () {
    // km/h declared, one recording unlabelled.
    declaredSpeedUnits = const ['km/h', ''];
    expect(speedUnitLabel(), '');
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    expect(speedUnitLabel(), '');
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    expect(speedUnitLabel(), 'km/h');
    // Recordings declaring different units.
    declaredSpeedUnits = const ['km/h', 'mph'];
    for (final setting in SpeedUnitSetting.values) {
      speedUnitSetting.value = setting;
      expect(speedUnitLabel(), '', reason: '$setting');
    }
    expect(daySpeedUnit(const [], 'mph'), '');
  });

  test('each speed channel keeps the unit its header line declares', () {
    final file = File('${directory.path}/obd.vbo')
      ..writeAsStringSync(
        '[header]\ntime\nlatitude\nlongitude\nvelocity kmh\nvelocity-obd mph\n'
        'velocity-calc\n'
        '[column names]\ntime lat long velocity velocity-obd velocity-calc\n'
        '[data]\n0.00 52.0 21.0 50.0 31.0 50.0\n0.10 52.0001 21.0 51.0 32.0 51.0\n',
      );
    final session = parseVboFile(file.path);
    declareDaySpeedUnits([session]);
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    expect(displayUnit('velocity', ''), 'km/h');
    expect(displayUnit('velocity-obd', ''), 'mph');
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    expect(displayUnit('velocity', ''), 'km/h');
    // Declared nowhere: the assumption names it.
    expect(displayUnit('velocity-calc', ''), 'mph');
    speedUnitSetting.value = SpeedUnitSetting.automatic;
    expect(displayUnit('velocity-calc', ''), '');
  });

  testWidgets('a day recorded in km/h shows km/h with mph chosen, end to end', (
    tester,
  ) async {
    final path = '${directory.path}/kmh.vbo';
    File(path).writeAsStringSync(
      circuitVbo([30, 28, 31]).replaceFirst(
        '[header]\n',
        '[header]\ntime\nlatitude\nlongitude\nvelocity kmh\n',
      ),
    );
    final outcome = runDayImport((paths: [path], includeSubfolders: false));
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    final controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    expect(declaredSpeedUnits, ['km/h']);
    expect(speedUnitLabel(), 'km/h');
    expect(displayUnit('velocity', ''), 'km/h');
    await tester.binding.setSurfaceSize(const Size(1200, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('km/h'), findsWidgets);
    expect(find.textContaining('mph'), findsNothing);
    // Closing the day forgets its units.
    await tester.pumpWidget(const SizedBox());
    expect(declaredSpeedUnits, isEmpty);
  });

  // Arek's second audit, finding 1: the analysis reads speeds in the unit
  // the screens show, not in a unit of its own.
  test('a day with speeds in a unit the app does not name labels none', () {
    // m/s against km/h: neither unit stands for the other.
    declaredChannelSpeedUnits = const {
      'speed': ['m/s', 'km/h'],
    };
    declaredSpeedUnits = const ['m/s', 'km/h'];
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    expect(displayUnit('speed', ''), '');
    expect(speedUnitLabel(), '');
    declaredSpeedUnits = const ['m/s'];
    expect(speedUnitLabel(), 'm/s');
  });

  test('the analysis reads the declared or assumed speed unit', () async {
    final declared = '${directory.path}/mph.vbo';
    File(declared).writeAsStringSync(
      circuitVbo([30, 28, 31]).replaceFirst(
        '[header]\n',
        '[header]\ntime\nlatitude\nlongitude\nvelocity mph\n',
      ),
    );
    final unlabelled = '${directory.path}/none.vbo';
    File(unlabelled).writeAsStringSync(circuitVbo([30, 29, 31]));
    String unit(DayResultsController controller, String runId) {
      final session = controller.session(runId)!;
      return session.channels[session.aliases['speed']]!.unit;
    }

    // A unit the recording declares, whatever the setting.
    var outcome = runDayImport((paths: [declared], includeSubfolders: false));
    var controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final mphRun = outcome.runs.single.run;
    expect(unit(controller, mphRun.id), 'mph');
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
    expect(unit(controller, mphRun.id), 'mph');
    // The recording itself, which its fingerprint is taken from, is as parsed.
    expect(mphRun.telemetry.channels['velocity']!.unit, '');
    controller.dispose();

    // An unlabelled recording takes the setting, and its results are
    // calculated again when the setting changes.
    speedUnitSetting.value = SpeedUnitSetting.automatic;
    outcome = runDayImport((paths: [unlabelled], includeSubfolders: false));
    controller = DayResultsController(
      runs: outcome.runs,
      analysis: outcome.analysis!,
    );
    final run = outcome.runs.single.run;
    expect(unit(controller, run.id), '');
    await controller.requestTheoreticalBest();
    expect(controller.theoreticalBest, isNotNull);
    var notified = 0;
    controller.addListener(() => ++notified);
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    expect(notified, greaterThan(0));
    expect(unit(controller, run.id), 'mph');
    expect(controller.theoreticalBest, isNull);
    // One unit through the day: the coach reports speeds in it.
    expect(controller.coachSpeedsConverted, isFalse);
    await controller.requestTheoreticalBest();
    expect(controller.theoreticalBest!.corners, isNotEmpty);
    for (final corner in controller.theoreticalBest!.corners) {
      for (final (_, metrics) in corner.laps) {
        expect(metrics.speeds.unit, 'mph');
      }
    }
    // A closed day no longer follows the setting.
    controller.dispose();
    speedUnitSetting.value = SpeedUnitSetting.kilometresPerHour;
  });

  Future<void> pumpApp(WidgetTester tester, {Locale? locale}) =>
      tester.pumpWidget(
        TelemetryApp(
          locale: locale,
          home: Scaffold(
            appBar: AppBar(actions: const [SettingsButton()]),
            body: Builder(
              builder: (context) => Text('speed ${speedUnitOf(context)}'),
            ),
          ),
        ),
      );

  Future<void> chooseInSettings(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  }

  testWidgets('choosing mph keeps a day recorded in km/h in km/h', (
    tester,
  ) async {
    declaredSpeedUnits = const ['km/h'];
    await pumpApp(tester);
    expect(find.text('speed km/h'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('declare km/h'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await chooseInSettings(tester, 'mph');
    expect(speedUnitSetting.value, SpeedUnitSetting.milesPerHour);
    expect(find.text('speed km/h'), findsOneWidget);
    expect(find.text('speed mph'), findsNothing);
  });

  testWidgets('the settings dialog labels unlabelled speeds', (tester) async {
    declaredSpeedUnits = const [''];
    await pumpApp(tester);
    expect(find.text('speed '), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.text('Its recordings do not say their speed unit.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await chooseInSettings(tester, 'mph');
    expect(find.text('speed mph'), findsOneWidget);
  });

  testWidgets('settings open the licences with the app and map credits', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Open-source licences'));
    await tester.tap(find.text('Open-source licences'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.textContaining('Apache License 2.0'), findsOneWidget);
    expect(
      find.textContaining('© OpenStreetMap contributors (ODbL)'),
      findsOneWidget,
    );
    expect(find.textContaining('© MapTiler'), findsOneWidget);
    expect(
      find.textContaining('Weather data by Open-Meteo.com (CC BY 4.0)'),
      findsOneWidget,
    );
  });

  testWidgets('the licences entry is translated', (tester) async {
    await pumpApp(tester, locale: const Locale('pl'));
    await tester.tap(find.byTooltip('Ustawienia'));
    await tester.pumpAndSettle();
    expect(find.text('O aplikacji'), findsOneWidget);
    await tester.ensureVisible(find.text('Licencje open source'));
    await tester.tap(find.text('Licencje open source'));
    await tester.pumpAndSettle();
    expect(find.textContaining('współtwórcy OpenStreetMap'), findsOneWidget);
  });

  testWidgets('the settings dialog fits a small phone held sideways', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(740, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    declaredSpeedUnits = const ['km/h', ''];
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Open-source licences'),
      50,
      scrollable: find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Open-source licences').hitTestable(), findsOneWidget);
  });

  testWidgets('the settings dialog counts recordings without a unit', (
    tester,
  ) async {
    declaredSpeedUnits = const ['km/h', ''];
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        "The open day's recordings declare km/h. "
        '1 of its recordings does not say its speed unit.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the settings dialog speaks Polish', (tester) async {
    addTearDown(() => Intl.defaultLocale = null);
    declaredSpeedUnits = const ['km/h', 'mph', '', ''];
    await pumpApp(tester, locale: const Locale('pl'));
    await tester.tap(find.byTooltip('Ustawienia'));
    await tester.pumpAndSettle();
    expect(find.text('Jednostka dla prędkości bez oznaczenia'), findsOneWidget);
    expect(
      find.text(
        'Zapisy otwartego dnia podają km/h i mph. '
        '2 z jego zapisów nie podają jednostki prędkości.',
      ),
      findsOneWidget,
    );
    expect(find.text('Brak'), findsOneWidget);
    await tester.tap(find.text('Zamknij'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsDialog), findsNothing);
  });

  testWidgets('the settings dialog keeps a readable width on a desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const TelemetryApp(home: Scaffold(body: SettingsDialog())),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('speedUnitSetting'))).width,
      lessThanOrEqualTo(480),
    );
    expect(
      tester.getSize(find.byType(SingleChildScrollView)).width,
      lessThanOrEqualTo(480),
    );
  });
}
