// A reference lap kept in the driver profile on a real day (FET-276), through
// the app's own pieces: ProfileLibrary, ProfileReferenceStore and
// ReferenceLapHolder. Set FLAPPEDEAR_REAL_DAY to a folder of one day's
// recordings (VBO, and the same sessions as RCZ): the last session is today,
// another session's file is the reference, copied into a temporary profile;
// a second start of the library, and a bundle imported into another
// temporary profile, give back the same lap and time. The recordings are
// only read; the temporary folders are deleted at the end.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/profile_reference_store.dart';
import 'package:telemetry/day/reference_lap.dart';
import 'package:telemetry/day/reference_lap_page.dart' show referenceLine;
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry_core/telemetry_core.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test(
    'the reference lap of a real day comes back through the library, the '
    'store and the holder, after a restart and through a bundle',
    () async {
      final temporary = Directory.systemTemp
          .createTempSync('real-reference-store')
          .resolveSymbolicLinksSync();
      addTearDown(() => Directory(temporary).deleteSync(recursive: true));
      final files =
          Directory(folder)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.vbo'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(2));

      ProfileLibrary libraryOn(String root) => ProfileLibrary(
        store: FolderProfileStore(root),
        defaultCarName: 'My car',
        defaultTrackName: (number) => 'Track $number',
      );

      // Today: the last session, a day of the profile at [a].
      final a = p.join(temporary, 'A');
      final outcome = runDayImport((
        paths: [files.last.path],
        includeSubfolders: false,
      ));
      final today = DayResultsController(
        runs: outcome.runs,
        analysis: outcome.analysis!,
      );
      addTearDown(today.dispose);
      final dayPath = profileDayPath(a, today.eventId);
      Directory(p.dirname(dayPath)).createSync(recursive: true);
      await today.save(dayPath);
      final line = referenceLine(today)!;
      final best = today.analysis.chosenGroup!.ranking!.bestOfDay!;

      Future<ReferenceLapHolder> holderOf(
        ProfileLibrary library,
        String eventId,
      ) async {
        await library.load();
        return ReferenceLapHolder(
          dayId: eventId,
          store: ProfileReferenceStore(library, keepsDay: () => true),
        );
      }

      Future<void> kept(ReferenceLapHolder holder) async {
        for (
          var i = 0;
          i < 200 && holder.keepState != ReferenceKeep.saved;
          i++
        ) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(holder.keepState, ReferenceKeep.saved);
      }

      // The other session whose fastest lap on today's line is the best.
      final library = libraryOn(a);
      addTearDown(library.dispose);
      String? referenceVbo;
      double? fastest;
      for (final file in files.take(files.length - 1)) {
        // Without a store: looking at a file keeps nothing.
        final probe = ReferenceLapHolder(dayId: 'probe');
        await probe.load(ReferenceFile(file.path), line);
        final seconds = probe.timing?.fastest?.durationSeconds;
        probe.dispose();
        if (seconds != null && (fastest == null || seconds < fastest)) {
          fastest = seconds;
          referenceVbo = file.path;
        }
      }
      expect(fastest, closeTo(109.898, 0.005));
      expect(
        Directory(p.join(a, 'Recordings')).existsSync(),
        isFalse,
        reason: 'looking at files keeps nothing',
      );

      for (final source in [
        referenceVbo!,
        '${referenceVbo.substring(0, referenceVbo.length - 4)}.rcz',
      ]) {
        final name = p.basename(source);
        final shelf = libraryOn(a);
        addTearDown(shelf.dispose);
        final holder = await holderOf(shelf, today.eventId);
        await holder.load(ReferenceFile(source), line);
        expect(holder.state, ReferenceState.ready);
        final lap = holder.lap!;
        await kept(holder);
        holder.dispose();
        final text = File(p.join(a, profileFileName)).readAsStringSync();
        expect(text, isNot(contains(folder)), reason: 'no path of the owner');

        void same(ReferenceLapHolder restored, String where) {
          expect(restored.state, ReferenceState.ready, reason: where);
          expect(restored.lap!.lapNumber, lap.lapNumber, reason: where);
          expect(
            restored.lap!.durationSeconds,
            closeTo(lap.durationSeconds, 1e-9),
            reason: where,
          );
          // ignore: avoid_print
          print(
            '$where: $name lap ${restored.lap!.lapNumber} '
            '${restored.lap!.durationSeconds.toStringAsFixed(3)} s, '
            'today\'s best ${best.durationSeconds.toStringAsFixed(3)} s, '
            'Δ ${(best.durationSeconds - restored.lap!.durationSeconds).toStringAsFixed(3)} s',
          );
        }

        // A second start of the library.
        final again = libraryOn(a);
        addTearDown(again.dispose);
        final restored = await holderOf(again, today.eventId);
        await restored.restore(line);
        same(restored, 'restarted');
        restored.dispose();

        // Through a bundle into another profile: the reference comes along.
        final bundle = p.join(temporary, 'driver$profileBundleExtension');
        if (File(bundle).existsSync()) File(bundle).deleteSync();
        final export = (await again.exportBundle(bundle))!;
        expect(export.referencesMissing, 0);
        final b = p.join(temporary, 'B-$name');
        final other = libraryOn(b);
        addTearDown(other.dispose);
        await other.load();
        final imported = (await other.importBundle(bundle))!;
        expect(imported.added, [today.eventId]);
        expect(imported.referencesNotKept, isEmpty);
        final arrived = await holderOf(other, today.eventId);
        await arrived.restore(line);
        same(arrived, 'imported');
        arrived.dispose();
        // One copy of the reference, named by its hash, in the new profile.
        final reference =
            other.profile!.day(today.eventId)!.reference
                as ProfileReferenceFile;
        expect(
          Directory(p.join(b, 'Recordings'))
              .listSync()
              .where((entry) => p.basename(entry.path) == reference.fileName),
          hasLength(1),
        );
      }
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
