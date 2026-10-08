// The track day as the driver lives it on a phone (FET-167, FET-168): after each
// session the recording is shared from RaceChrono, and the app adds it to
// today's day in the library and shows the Next session card, with no
// question asked. Session 1's RCZ is shared after its VBO, and the app is
// started again (as the system closes it between sessions) before the
// fourth session. Set FLAPPEDEAR_REAL_DAY to a folder of one day's VBO and
// RCZ files; the recordings are copied only into a temporary folder,
// deleted at the end, as the app copies a share. Skipped
// otherwise.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/day/document_pickers.dart';
import 'package:telemetry/day/track_map.dart';
import 'package:telemetry/import/day_import_page.dart';
import 'package:telemetry/import/incoming_recordings.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/profile_library.dart';

import '../day/blank_tiles.dart';
import '../day/recovery_test.dart' show FileRecoveryStore;
import '../support/temp_directory.dart';

final class _Shares implements IncomingRecordings {
  final controller = StreamController<List<String>>.broadcast();

  @override
  Stream<List<String>> get received => controller.stream;
}

/// A phone keeps its days in the library only.
final class _NoSavedDays implements DocumentPickers {
  @override
  Future<SaveLocation?> saveLocation(String name) async => null;

  @override
  Future<String?> pickDocument() async => null;

  @override
  Future<String?> pickFolder() async => null;

  @override
  Future<List<String>> savedDays() async => const [];
}

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  testWidgets(
    'each shared session joins today\'s day and is coached',
    (tester) async {
      debugTileProvider = BlankTiles.new;
      final work = Directory.systemTemp.createTempSync('track_day_shares');
      addTearDown(() {
        debugTileProvider = null;
        deleteTemporaryDirectory(work);
      });
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final recordings = Directory(
        folder,
      ).listSync().whereType<File>().map((file) => file.path).toList()..sort();
      List<String> withExtension(String extension) => [
        for (final path in recordings)
          if (path.toLowerCase().endsWith(extension)) path,
      ];
      final vbos = withExtension('.vbo');
      final rczs = withExtension('.rcz');
      expect(vbos.length, greaterThan(3));
      // RaceChrono shares a copy; the app keeps its own (MainActivity copies
      // shares to files/incoming), so each share is copied here first.
      String share(String path) {
        final copy = p.join(work.path, 'incoming', p.basename(path));
        File(copy).parent.createSync(recursive: true);
        File(path).copySync(copy);
        return copy;
      }

      final profile = p.join(work.path, 'Profile');
      final recovery = FileRecoveryStore(p.join(work.path, 'recovery.json'));
      late _Shares shares;
      Future<void> start() async {
        shares = _Shares();
        await tester.pumpWidget(
          TelemetryApp(
            home: DayImportPage(
              key: UniqueKey(),
              incoming: shares,
              recovery: recovery,
              documents: _NoSavedDays(),
              library: ProfileLibrary(
                store: FolderProfileStore(profile),
                defaultCarName: 'My car',
                defaultTrackName: (number) => 'Track $number',
              ),
            ),
          ),
        );
        await tester.pump();
      }

      /// Runs real time (isolates, files) between frames until [done].
      Future<void> until(bool Function() done, String what) async {
        for (var i = 0; i < 3000 && !done(); ++i) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        if (!done()) {
          // ignore: avoid_print
          print(
            find
                .byType(Text)
                .evaluate()
                .map((e) => (e.widget as Text).data)
                .join(" | "),
          );
        }
        expect(done(), isTrue, reason: what);
      }

      List<Map<String, Object?>> days() {
        final dir = Directory(p.join(profile, profileDaysFolder));
        if (!dir.existsSync()) return const [];
        return [
          for (final file in dir.listSync().whereType<File>())
            if (file.path.endsWith('.fetproject'))
              (jsonDecode(file.readAsStringSync()) as Map)
                  .cast<String, Object?>(),
        ];
      }

      int savedRuns() => days().fold(
        0,
        (sum, day) => sum + ((day['event'] as Map)['runs'] as List).length,
      );

      bool coached(int session) => find
          .textContaining('Coaching Session $session ')
          .evaluate()
          .isNotEmpty;

      bool coachReady() =>
          find.byKey(const ValueKey('coachReason')).evaluate().isNotEmpty;

      // The session summary (FET-233) heads the Coach place, so on a phone
      // the Next session card is further down the list: scrolled to, as
      // the driver would.
      Future<void> untilCoached(int session) async {
        final list = find.byKey(const ValueKey('dayResultsCoach'));
        bool summarized() =>
            find.text('Session $session in 30 seconds').evaluate().isNotEmpty;
        for (var i = 0; i < 3000 && !(coached(session) && coachReady()); ++i) {
          if (summarized() && list.evaluate().isNotEmpty) {
            await tester.drag(list, const Offset(0, -200));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        await until(
          () => coached(session) && coachReady(),
          'Session $session coached on the Next session card',
        );
      }

      await start();
      final clock = Stopwatch()..start();
      for (var i = 0; i < vbos.length; ++i) {
        final session = i + 1;
        if (session == 4) {
          // The system closed the app between sessions.
          await until(
            () => savedRuns() == 3,
            'sessions 1 to 3 saved in the library before the restart',
          );
          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await start();
        }
        clock.reset();
        shares.controller.add([share(vbos[i])]);
        // The first session opens the day; each later one moves the day
        // to its Next session card.
        if (session == 1) {
          await until(
            () => find.text('Best lap of the day').evaluate().isNotEmpty,
            'Session 1 opened as the day',
          );
        } else {
          await untilCoached(session);
        }
        final shown = clock.elapsed;
        await until(() => savedRuns() == session, 'Session $session saved');
        expect(days(), hasLength(1), reason: 'one day in the library');
        expect(find.byType(DayResultsPage), findsOneWidget);
        // ignore: avoid_print
        print(
          'Session $session: coached ${shown.inMilliseconds} ms after the '
          'share, saved ${clock.elapsed.inMilliseconds} ms; '
          '${find.byKey(const ValueKey('coachReason')).evaluate().map((e) => (e.widget as Text).data).join()}'
          '${find.byKey(const ValueKey('coachItem 0')).evaluate().isEmpty ? '' : ' (with items)'}',
        );
        if (session == 1 && rczs.isNotEmpty) {
          // Its RCZ, shared after it, joins Session 1 and adds no session.
          shares.controller.add([share(rczs.first)]);
          await until(
            () => find
                .textContaining('kept as its alternative source')
                .evaluate()
                .isNotEmpty,
            'the RCZ kept with Session 1',
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 500)),
          );
          await tester.pump();
          expect(savedRuns(), 1);
        }
      }
      final day = days().single;
      final runs = (day['event'] as Map)['runs'] as List;
      expect(runs, hasLength(vbos.length));
      // The day's summary in the library follows its theoretical best,
      // worked out after the save.
      for (var i = 0; i < 50; ++i) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
      final library = ProfileLibrary(
        store: FolderProfileStore(profile),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
      );
      await tester.runAsync(library.load);
      final listed = library.profile!.days.single;
      expect(listed.sessions, hasLength(vbos.length));
      // ignore: avoid_print
      print(
        'Library: ${listed.sessions.length} sessions, best lap '
        '${listed.bestLapSeconds}, theoretical best '
        '${listed.theoreticalBestSeconds}',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
    },
    // A phone: no folder picker, the bar at the bottom.
    variant: TargetPlatformVariant.only(TargetPlatform.android),
    skip: skip != null,
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
