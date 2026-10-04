import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry/day/document_pickers.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/main.dart' as app;

import '../test/day/blank_tiles.dart';
import '../test/day/day_results_page_test.dart' show circuitVbo;

/// Hands the import the recording already copied into the app, as the host
/// pickers do after the system picker returns.
final class _Picked implements RecordingPickers {
  const _Picked(this.paths);

  final List<String> paths;

  @override
  Future<List<String>> pickRecordings() async => paths;

  @override
  Future<String?> pickFolder() async => null;
}

/// Pumps until [finder] finds something; the import and opening run in
/// background isolates in real time on the device.
Future<void> waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 90),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await tester.pump();
  }
}

/// Removes the unsaved-day snapshot the app keeps for recovery, so a run
/// (or a test that failed before saving) leaves nothing behind for the next.
Future<void> clearRecovery() async {
  final file = File(
    p.join((await getApplicationSupportDirectory()).path, 'day-recovery.json'),
  );
  if (file.existsSync()) file.deleteSync();
}

/// The best lap's time on the day page, under "Best day".
// The time is the last text on the Best day bar, after its label and the
// lap's name.
String bestLapTime(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('dayBestBar')),
        matching: find.byType(Text),
      ),
    )
    .last
    .data!;

// Runs on a real iOS simulator and Android emulator in CI, with the app's
// real storage, background isolates, recovery and saved-days folder: the app
// starts; a recording is imported, its results shown, the day saved, the
// app's widgets built again from nothing (the process keeps running) and the
// saved day reopened with the same results; and on Android a recording
// shared to the app with ACTION_SEND (sent by
// .github/scripts/android-integration-test.sh) opens as the day.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // A first frame that never comes fails the test with a result after three
  // minutes, instead of leaving the tool waiting until CI stops it.
  testWidgets('the app starts and shows its first screen', (tester) async {
    // main() loads the settings before runApp; without the await,
    // pumpAndSettle can return before the app has been built.
    await app.main();
    await tester.pumpAndSettle();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.title, 'FlappedEar Telemetry');
    expect(find.byType(Scaffold), findsWidgets);
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('import, save, start again and reopen a day', (tester) async {
    final support = await getApplicationSupportDirectory();
    final recordings = Directory(p.join(support.path, 'integration-test'))
      ..createSync(recursive: true);
    final recording = File(p.join(recordings.path, 'session.vbo'))
      ..writeAsStringSync(circuitVbo([30, 28, 31]));
    final before = (await const PlatformDocumentPickers().savedDays()).toSet();
    await clearRecovery();
    // Map tiles stay off the network: blank tiles, as in the widget tests.
    debugTileProvider = BlankTiles.new;
    addTearDown(() async {
      debugTileProvider = null;
      await clearRecovery();
      for (final path in await const PlatformDocumentPickers().savedDays()) {
        if (!before.contains(path)) File(path).deleteSync();
      }
      recordings.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      TelemetryApp(home: DayImportPage(pickers: _Picked([recording.path]))),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose recordings…'));
    await waitFor(tester, find.text('Show the day\'s results'));
    expect(find.text('1 session imported'), findsOneWidget);

    await tester.tap(find.text('Show the day\'s results'));
    await waitFor(tester, find.text('Best day'));
    await tester.pumpAndSettle();
    final best = bestLapTime(tester);
    // "22.440 s" under a minute, "1:49.898" above.
    expect(best, matches(RegExp(r'^(\d+:\d\d\.\d{3}|\d+\.\d{3}\u00a0s)$')));

    await tester.tap(find.byTooltip('Save'));
    await waitFor(tester, find.textContaining('Saved as'));
    final saved = (await const PlatformDocumentPickers().savedDays())
        .where((path) => !before.contains(path))
        .toList();
    expect(saved, hasLength(1));
    final name = p.basenameWithoutExtension(saved.single);

    // Start again: a new widget tree with the default pickers and stores,
    // as after a relaunch; only what is on the device's storage carries over.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const TelemetryApp());
    await tester.pumpAndSettle();
    await waitFor(tester, find.text('Open a saved day…'));
    // The import page reads the recovery file in the background: give it
    // time to show a banner if there were one to show.
    for (var i = 0; i < 10; ++i) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tester.pump();
    }
    expect(find.textContaining('has unsaved changes'), findsNothing);

    await tester.tap(find.text('Open a saved day…'));
    await waitFor(tester, find.text(name));
    await tester.tap(find.text(name));
    await waitFor(tester, find.text('Best day'));
    await tester.pumpAndSettle();
    expect(bestLapTime(tester), best);
    expect(find.textContaining('could not be opened'), findsNothing);
  }, timeout: const Timeout(Duration(minutes: 4)));

  // The CI script sends the share once this test says it is waiting;
  // see android/app/src/debug (TestShareProvider) for the file it shares.
  testWidgets(
    'a recording shared with ACTION_SEND opens as the day',
    (tester) async {
      final fixtures = Directory(
        p.join((await getTemporaryDirectory()).path, 'share-fixtures'),
      )..createSync(recursive: true);
      // MainActivity copies shares to files/incoming (the support folder).
      final incoming = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'incoming'),
      );
      await clearRecovery();
      // The day page shows a map: its tiles stay off the network too, so a
      // runner without network does not fail the test.
      debugTileProvider = BlankTiles.new;
      addTearDown(() async {
        debugTileProvider = null;
        fixtures.deleteSync(recursive: true);
        if (incoming.existsSync()) incoming.deleteSync(recursive: true);
        await clearRecovery();
      });
      File(p.join(fixtures.path, 'shared.vbo'))
          .writeAsStringSync(circuitVbo([30, 28, 31]));

      await tester.pumpWidget(const TelemetryApp());
      await tester.pumpAndSettle();
      // The CI script polls for this file: print inside a test goes to the
      // test runner on the host, not to the device's log.
      File(p.join(fixtures.path, 'ready')).writeAsStringSync('');
      // A share with no day in progress is imported and opened as today's
      // day straight away, so the day page is what appears.
      await waitFor(
        tester,
        find.text('Best day'),
        timeout: const Duration(minutes: 2),
      );
      await tester.pumpAndSettle();
      expect(
        bestLapTime(tester),
        matches(RegExp(r'^(\d+:\d\d\.\d{3}|\d+\.\d{3}\u00a0s)$')),
      );
    },
    skip: !Platform.isAndroid || !const bool.fromEnvironment('SHARE_TEST'),
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
