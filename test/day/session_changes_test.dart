import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/session_changes.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

SessionSegmentChange _change(
  String id,
  String name,
  double seconds,
  double before, [
  double? spread,
  double? spreadBefore,
]) => SessionSegmentChange(
  segmentId: id,
  name: name,
  type: 'corner',
  seconds: seconds,
  referenceSeconds: before,
  spreadSeconds: spread,
  referenceSpreadSeconds: spreadBefore,
);

SessionSummary _summary({
  List<SessionSegmentChange> changes = const [],
  String? previous = 'Session 5',
  int earlier = 5,
}) => SessionSummary(
  runId: '6',
  runName: 'Session 6',
  earlierSessions: earlier,
  previousRunName: previous,
  lapSpread: 2.52,
  previousLapSpread: 7.813,
  segmentsCompared: changes.length,
  changes: changes,
);

Future<void> _pump(
  WidgetTester tester,
  SessionSummary? summary, {
  bool pending = false,
  bool ready = true,
  Locale? locale,
}) => tester.pumpWidget(
  TelemetryApp(
    locale: locale,
    home: Scaffold(
      body: SingleChildScrollView(
        child: SessionChanges(
          session: 'Session 6',
          summary: summary,
          pending: pending,
          ready: ready,
        ),
      ),
    ),
  ),
);

String _text(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(Text),
      ),
    )
    .map((text) => text.data)
    .join(' | ');

void main() {
  testWidgets('quicker and slower segments, most first, each with its '
      'spread, and how many stayed the same', (tester) async {
    await _pump(
      tester,
      _summary(
        changes: [
          _change('c1', 'Corner 1', 9.6, 9.8, 0.1, 0.2),
          _change('s2', 'Straight 2', 8.4, 8.1, 0.1, 0.1),
          _change('c3', 'Corner 3', 21.04, 21.02),
          _change('c8', 'Corner 8', 5.0, 5.409, 0.05, 0.3),
          _change('c9', 'Corner 9', 6.11, 6.05),
        ],
      ),
    );
    expect(
      _text(tester, 'sessionChangesLapSpread'),
      'Lap-time spread: 2.520 s (Session 5: 7.813 s)',
    );
    final quicker = tester.getTopLeft(
      find.byKey(const ValueKey('sessionChange c8')),
    );
    final next = tester.getTopLeft(
      find.byKey(const ValueKey('sessionChange c1')),
    );
    expect(quicker.dy, lessThan(next.dy));
    expect(
      _text(tester, 'sessionChange c8'),
      'Corner 8 | Typical 5.000\u00a0s (Session 5: 5.409\u00a0s) | Spread 0.050 s '
      '(Session 5: 0.300 s) | −0.409\u00a0s',
    );
    expect(
      _text(tester, 'sessionChange s2'),
      'Straight 2 | Typical 8.400\u00a0s (Session 5: 8.100\u00a0s) | Spread 0.100 s '
      '(Session 5: 0.100 s) | +0.300\u00a0s',
    );
    // Corner 9 +0.06 counts; Corner 3 +0.02 does not.
    expect(find.byKey(const ValueKey('sessionChange c9')), findsOneWidget);
    expect(find.byKey(const ValueKey('sessionChange c3')), findsNothing);
    expect(
      _text(tester, 'sessionChangesSame'),
      '1 segment within 0.05 s of before.',
    );
    final slower = tester.getTopLeft(
      find.byKey(const ValueKey('sessionChangesSlower')),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sessionChange s2'))).dy,
      greaterThan(slower.dy),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('sessionChange s2'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('sessionChange c9'))).dy,
      ),
    );
  });

  testWidgets('nothing quicker or slower says so', (tester) async {
    await _pump(
      tester,
      _summary(changes: [_change('c1', 'Corner 1', 9.6, 9.62)]),
    );
    expect(find.text('No segment quicker by 0.05 s or more.'), findsOneWidget);
    expect(find.text('No segment slower by 0.05 s or more.'), findsOneWidget);
  });

  testWidgets('a list that cannot be shown says why', (tester) async {
    Future<String> reason(
      SessionSummary? summary, {
      bool pending = false,
      bool ready = true,
    }) async {
      await _pump(tester, summary, pending: pending, ready: ready);
      return _text(tester, 'sessionChangesReason');
    }

    expect(await reason(_summary(), pending: true), 'Working…');
    expect(
      await reason(_summary(), ready: false),
      isNot(anyOf('Working…', '')),
    );
    expect(
      await reason(null),
      'Session 6 has no timed laps on the circuit shown.',
    );
    expect(
      await reason(_summary(previous: null, earlier: 0)),
      isNot(anyOf('Working…', '')),
    );
    expect(await reason(_summary()), isNot(anyOf('Working…', '')));
  });

  testWidgets('in Polish', (tester) async {
    await _pump(
      tester,
      _summary(changes: [_change('c8', 'Corner 8', 5.0, 5.409, 0.05, 0.3)]),
      locale: const Locale('pl'),
    );
    expect(
      _text(tester, 'sessionChange c8'),
      'Zakręt 8 | Typowo 5.000\u00a0s (Sesja 5: 5.409\u00a0s) | Rozrzut 0.050 s '
      '(Sesja 5: 0.300 s) | −0.409\u00a0s',
    );
    expect(find.text('Szybciej'), findsOneWidget);
  });
}
