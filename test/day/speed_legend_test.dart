import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

void main() {
  final path = LapPath(
    origin: const GeoCoordinate(52, 21),
    segments: [
      [
        for (var i = 0; i <= 10; ++i)
          PathPoint(i.toDouble(), i * 10.0, 0, 60 + i * 6.0),
      ],
    ],
    speedUnit: 'km/h',
  );

  Future<void> pump(
    WidgetTester tester,
    double scale, {
    String label = 'Prędkość',
    Locale locale = const Locale('pl'),
  }) async {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(() => Intl.defaultLocale = null);
    await tester.pumpWidget(
      TelemetryApp(
        locale: locale,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 328,
              child: LabelledSpeedLegend(label: label, path: path),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('a phone with Polish text ×2 puts the label above the scale', (
    tester,
  ) async {
    await pump(tester, 2);
    expect(tester.takeException(), isNull);
    expect(
      tester.getBottomLeft(find.text('Prędkość')).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(SpeedLegend)).dy),
    );
  });

  testWidgets('English text keeps the label beside the scale', (tester) async {
    await pump(tester, 1, label: 'Speed', locale: const Locale('en'));
    expect(tester.takeException(), isNull);
    expect(
      tester.getCenter(find.text('Speed')).dy,
      closeTo(tester.getCenter(find.byType(SpeedLegend)).dy, 4),
    );
  });
}
