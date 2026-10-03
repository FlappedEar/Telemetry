import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

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
    declaredSpeedUnits = const [];
  });
  tearDown(() => directory.deleteSync(recursive: true));

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

  Future<void> pumpApp(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => SpeedUnitScope(child: child!),
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
}
