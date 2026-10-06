import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/circuits/circuit_directory.dart';
import 'package:telemetry/day/track_dialog.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/units.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../support/temp_directory.dart';

// Synthetic circuits; no real recording.
String list(int revision, List<(String, String, double, double)> circuits) =>
    jsonEncode({
      'format': circuitListFormat,
      'version': 1,
      'revision': revision,
      'source': 'test',
      'circuits': [
        for (final (id, name, lat, lon) in circuits)
          {'id': id, 'name': name, 'lat': lat, 'lon': lon},
      ],
    });

const alpha = GeoCoordinate(50.0, 20.0);
const elsewhere = GeoCoordinate(10.0, 10.0);

void main() {
  late Directory directory;
  setUp(() => directory = Directory.systemTemp.createTempSync('circuits'));
  tearDown(() => deleteTemporaryDirectory(directory));

  CircuitDirectory make({
    int shipped = 1,
    Future<String> Function(Uri uri, int maximum)? fetch,
  }) => CircuitDirectory(
    bundled: () async => list(shipped, [('a', 'Alpha', 50.0, 20.0)]),
    folder: () async => directory,
    fetch: fetch ?? (uri, maximum) async => throw const SocketException('no'),
  );

  test('the shipped list names a route that starts near a circuit', () async {
    final circuits = make();
    await circuits.load();
    expect(circuits.find(alpha)?.name, 'Alpha');
    expect(circuits.find(elsewhere), isNull);
    expect(circuits.find(null), isNull);
  });

  test('fetches the published file and keeps a newer list only', () async {
    Uri? asked;
    var answer = list(2, [('a', 'Alpha ring', 50.0, 20.0)]);
    final circuits = make(
      fetch: (uri, maximum) async {
        asked = uri;
        return answer;
      },
    );
    expect(await circuits.refresh(), CircuitRefresh.updated);
    expect(
      asked.toString(),
      'https://raw.githubusercontent.com/FlappedEar/Telemetry/main/'
      'assets/circuits/circuits.json',
    );
    expect(circuits.find(alpha)?.name, 'Alpha ring');
    expect(await circuits.refresh(), CircuitRefresh.upToDate);
    answer = list(1, [('a', 'Older', 50.0, 20.0)]);
    expect(await circuits.refresh(), CircuitRefresh.upToDate);
    answer = 'not a list';
    expect(await circuits.refresh(), CircuitRefresh.failed);
    expect(circuits.find(alpha)?.name, 'Alpha ring');

    // Kept for the next start, until the app ships a newer list.
    final next = make();
    await next.load();
    expect(next.list.revision, 2);
    expect(next.find(alpha)?.name, 'Alpha ring');
    final newerApp = make(shipped: 3);
    await newerApp.load();
    expect(newerApp.find(alpha)?.name, 'Alpha');
  });

  test('a failed fetch keeps the list in use', () async {
    final circuits = make();
    expect(await circuits.refresh(), CircuitRefresh.failed);
    expect(circuits.find(alpha)?.name, 'Alpha');
  });

  test('the driver renames a circuit, adds one and forgets them', () async {
    final circuits = make();
    expect(await circuits.nameAt(alpha, '  Home track '), isTrue);
    expect(circuits.find(alpha)?.name, 'Home track');
    expect(circuits.mine.single.id, 'a');
    expect(circuits.listed('a')?.name, 'Alpha');

    expect(
      await circuits.nameAt(elsewhere, 'Kart track', random: Random(1)),
      isTrue,
    );
    expect(circuits.find(elsewhere)?.name, 'Kart track');
    expect(circuits.mine.last.id, startsWith('my:'));
    expect(circuits.mine.last.radiusMeters, ownCircuitRadiusMeters);
    // Renaming the driver's own circuit keeps it one circuit.
    expect(await circuits.nameAt(elsewhere, 'Kart'), isTrue);
    expect(circuits.mine.length, 2);

    expect(await circuits.nameAt(alpha, ' '), isFalse);
    expect(await circuits.nameAt(alpha, 'x' * 129), isFalse);

    // Kept on this device.
    final next = make();
    await next.load();
    expect(next.find(alpha)?.name, 'Home track');
    expect(next.find(elsewhere)?.name, 'Kart');
    expect(
      jsonDecode(File(p.join(directory.path, 'mine.json')).readAsStringSync()),
      containsPair('format', userCircuitsFormat),
    );

    await next.remove('a');
    expect(next.find(alpha)?.name, 'Alpha');
    await next.remove(next.mine.single.id);
    expect(next.find(elsewhere), isNull);
    final last = make();
    await last.load();
    expect(last.mine, isEmpty);
  });

  test('a damaged file of the driver\'s is left alone', () async {
    File(p.join(directory.path, 'mine.json')).writeAsStringSync('{broken');
    File(p.join(directory.path, 'list.json')).writeAsStringSync('{broken');
    final circuits = make();
    await circuits.load();
    expect(circuits.find(alpha)?.name, 'Alpha');
    expect(circuits.mine, isEmpty);
    // The driver's damaged file is kept aside, never overwritten.
    await circuits.nameAt(alpha, 'Home track');
    final kept = directory
        .listSync()
        .whereType<File>()
        .where((file) => p.basename(file.path).startsWith('mine.unreadable-'))
        .toList();
    expect(kept.single.readAsStringSync(), '{broken');
    expect(
      decodeUserCircuits(
        File(p.join(directory.path, 'mine.json')).readAsStringSync(),
      ).single.name,
      'Home track',
    );
  });

  test('saves made at once leave the last state', () async {
    final circuits = make();
    await circuits.load();
    await Future.wait([
      circuits.nameAt(alpha, 'One'),
      circuits.nameAt(elsewhere, 'Two'),
      circuits.nameAt(alpha, 'Three'),
    ]);
    final next = make();
    await next.load();
    expect(next.find(alpha)?.name, 'Three');
    expect(next.find(elsewhere)?.name, 'Two');
  });

  test(
    'checks on launch at most once a day while update checks are on',
    () async {
      var asked = 0;
      final saved = circuitDirectory;
      addTearDown(() {
        circuitDirectory = saved;
        updateCheckSetting.value = true;
        lastCircuitCheck.value = null;
      });
      circuitDirectory = make(
        fetch: (uri, maximum) async {
          ++asked;
          return list(1, const []);
        },
      );
      final now = DateTime.utc(2026, 10, 6, 12);
      lastCircuitCheck.value = null;
      await refreshCircuitsOnLaunch(now: now);
      expect(asked, 1);
      expect(lastCircuitCheck.value, now);
      await refreshCircuitsOnLaunch(now: now.add(const Duration(hours: 23)));
      expect(asked, 1);
      updateCheckSetting.value = false;
      await refreshCircuitsOnLaunch(now: now.add(const Duration(days: 2)));
      expect(asked, 1);
      updateCheckSetting.value = true;
      await refreshCircuitsOnLaunch(now: now.add(const Duration(days: 2)));
      expect(asked, 2);
    },
  );

  group('screens', () {
    late CircuitDirectory saved;
    setUp(() => saved = circuitDirectory);
    tearDown(() => circuitDirectory = saved);

    testWidgets('settings count the list and forget the driver\'s names', (
      tester,
    ) async {
      final circuits = circuitDirectory = make();
      await tester.runAsync(() async {
        await circuits.nameAt(alpha, 'Home track');
        await circuits.nameAt(elsewhere, 'Kart track');
      });
      await tester.pumpWidget(
        const TelemetryApp(home: Scaffold(body: SettingsDialog())),
      );
      await tester.pumpAndSettle();
      expect(find.text('Circuits in the list: 1'), findsOneWidget);
      expect(find.text('Home track'), findsOneWidget);
      expect(find.text('Listed as Alpha'), findsOneWidget);
      expect(find.text('Added by you'), findsOneWidget);
      final forget = find.descendant(
        of: find.byKey(const ValueKey('ownCircuit-a')),
        matching: find.byTooltip('Forget this name'),
      );
      await tester.ensureVisible(forget);
      await tester.pumpAndSettle();
      await tester.tap(forget);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Home track'), findsNothing);
      expect(circuits.find(alpha)?.name, 'Alpha');

      await tester.ensureVisible(find.text('Update the circuit list'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Update the circuit list'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'The circuit list could not be fetched. Check the connection and '
          'try again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('the circuit name dialog names the place', (tester) async {
      final circuits = circuitDirectory = make();
      await tester.runAsync(circuits.load);
      await tester.pumpWidget(
        TelemetryApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      const CircuitNameDialog(start: alpha, name: 'Alpha'),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Circuit name'), findsOneWidget);
      final save = find.byKey(const ValueKey('saveCircuitName'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.enterText(
        find.byKey(const ValueKey('circuitNameField')),
        'Home track',
      );
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(save);
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(circuits.find(alpha)?.name, 'Home track');
      expect(find.text('Circuit name'), findsNothing);
    });
  });
}
