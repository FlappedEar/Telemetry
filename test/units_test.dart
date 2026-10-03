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
    detectedSpeedUnit = '';
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
    expect(commonSpeedUnit([kmh, kmh]), 'km/h');
    expect(commonSpeedUnit([kmh, mph]), '');
    expect(commonSpeedUnit([kmh, none]), '');
  });

  test('the setting overrides the detected and the recorded unit', () {
    detectedSpeedUnit = 'km/h';
    expect(speedUnitLabel(), 'km/h');
    expect(speedUnitLabel('mph'), 'mph');
    expect(speedUnitLabel('kmh'), 'km/h');
    speedUnitSetting.value = SpeedUnitSetting.milesPerHour;
    expect(speedUnitLabel(), 'mph');
    expect(speedUnitLabel('km/h'), 'mph');
    expect(displayUnit('velocity-obd', ''), 'mph');
    expect(displayUnit('coolant_temp-obd', '°C'), '°C');
  });

  testWidgets('the settings dialog changes the label', (tester) async {
    detectedSpeedUnit = 'km/h';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => SpeedUnitScope(child: child!),
        home: Scaffold(
          appBar: AppBar(actions: const [SettingsButton()]),
          body: Builder(builder: (context) => Text(speedUnitOf(context))),
        ),
      ),
    );
    expect(find.text('km/h'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Automatic: km/h'), findsOneWidget);
    await tester.tap(find.text('mph'));
    await tester.pumpAndSettle();
    expect(speedUnitSetting.value, SpeedUnitSetting.milesPerHour);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('mph'), findsOneWidget);
  });
}
