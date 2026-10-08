// A reference lap kept in the driver profile on a real day (FET-276): one
// session's recording is today's day, another session's VBO or RCZ is the
// day's reference, kept as a copy in a temporary profile; the profile is read
// back from disk, and moved through a bundle into a second temporary profile,
// and the same reference lap time comes back each time. Set
// FLAPPEDEAR_REAL_DAY to a folder of one day's recordings; they are only
// read, copies go to temporary folders that are deleted at the end.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the reference lap of a real day survives the profile on disk and a bundle', () async {
    final temporary = Directory.systemTemp
        .createTempSync('real-reference')
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

    // Today: the last session, saved as a day of a temporary profile A.
    final a = p.join(temporary, 'A');
    final todayPath = files.last.path;
    final runs = nameRunsInRecordingOrder(prepareTelemetryImport([todayPath]).runs);
    final analysis = analyzeDay([
      for (final named in runs)
        DayRunInput(
          runId: named.run.id,
          name: named.name,
          contentSha256: named.run.contentSha256,
          session: named.run.telemetry,
          laps: named.run.laps,
        ),
    ]);
    final best = analysis.chosenGroup!.ranking!.bestOfDay!;
    final todaySession = runs.single.run.telemetry;
    final line = referenceLineOf(todaySession, runs.single.run.laps, best.lapNumber)!;
    final dayFile = p.join(a, 'Days', 'today.fetproject');
    Directory(p.dirname(dayFile)).createSync(recursive: true);
    await saveDayDocument(
      dayFile,
      dayDocument(
        eventId: 'today',
        name: 'Today',
        runs: runs,
        analysis: analysis,
        projectPath: dayFile,
      ),
    );
    var profile = addDayToProfile(
      DriverProfile.empty(),
      ProfileDayInput.fromAnalysis(
        eventId: 'today',
        file: 'Days/today.fetproject',
        name: 'Today',
        analysis: analysis,
      ),
      defaultCarName: 'My car',
      defaultTrackName: 'Track',
    );

    // The reference: the other session with the fastest lap on today's line.
    String? referenceVbo;
    double? fastest;
    for (final file in files.take(files.length - 1)) {
      final timing = timeReferenceLaps([
        ReferenceRecording(label: p.basename(file.path), session: loadRecording(file.path)),
      ], line);
      if (timing.fastest != null &&
          (fastest == null || timing.fastest!.durationSeconds < fastest)) {
        fastest = timing.fastest!.durationSeconds;
        referenceVbo = file.path;
      }
    }
    expect(fastest, closeTo(109.898, 0.005));

    for (final source in [
      referenceVbo!,
      '${referenceVbo.substring(0, referenceVbo.length - 4)}.rcz',
    ]) {
      final name = p.basename(source);
      final expected = timeReferenceLaps([
        ReferenceRecording(label: name, id: name, session: loadRecording(source)),
      ], line);
      final lap = expected.fastest!;
      print(
        '$name: lap ${lap.lapNumber} ${lap.durationSeconds.toStringAsFixed(3)} s on today\'s line',
      );

      // Kept: a copy in the profile, the choice by file name and lap.
      final copy = keepReferenceFile(a, source);
      profile = setProfileDayReference(profile, 'today', copy.reference(name, name, lap.lapNumber));
      File(p.join(a, profileIndexName)).writeAsStringSync(encodeDriverProfile(profile));
      final text = File(p.join(a, profileIndexName)).readAsStringSync();
      expect(text, isNot(contains(folder)), reason: 'no path of the owner\'s files');

      void checkRestored(DriverProfile read, String root, String where) {
        final reference = read.day('today')!.reference as ProfileReferenceFile;
        expect(reference.recordingId, name);
        expect(reference.lapNumber, lap.lapNumber);
        final path = profileReferenceFilePath(root, reference)!;
        expect(p.isWithin(p.join(root, 'Recordings'), path), isTrue);
        final timing = timeReferenceLaps([
          ReferenceRecording(
            label: reference.name,
            id: reference.recordingId,
            session: loadRecording(path),
          ),
        ], line);
        final restored = timing.candidates.firstWhere(
          (candidate) =>
              candidate.recordingId == reference.recordingId &&
              candidate.lapNumber == reference.lapNumber,
        );
        expect(restored.durationSeconds, closeTo(lap.durationSeconds, 1e-9), reason: where);
        expect(
          restored.durationSeconds - best.durationSeconds,
          closeTo(lap.durationSeconds - best.durationSeconds, 1e-9),
        );
        print(
          '$where: $name lap ${restored.lapNumber} ${restored.durationSeconds.toStringAsFixed(3)} s, '
          'today\'s best ${best.durationSeconds.toStringAsFixed(3)} s, '
          'Δ ${(best.durationSeconds - restored.durationSeconds).toStringAsFixed(3)} s',
        );
      }

      // The profile read back from disk.
      checkRestored(decodeDriverProfile(text), a, 'reloaded');

      // Through a bundle into a second temporary profile.
      final bundle = p.join(temporary, 'driver$profileBundleExtension');
      if (File(bundle).existsSync()) File(bundle).deleteSync();
      final export = await writeProfileBundle(profile, a, bundle);
      expect(export.referencesMissing, 0);
      final b = p.join(temporary, 'B-$name');
      final read = await readProfileBundle(DriverProfile.empty(), b, bundle);
      expect(read.added, ['today']);
      expect(read.referencesNotKept, isEmpty);
      checkRestored(read.profile, b, 'imported');
      // One copy of the reference, however it came.
      expect(
        Directory(p.join(b, 'Recordings'))
            .listSync()
            .where((entry) => p.basename(entry.path) == copy.sha256 + copy.extension),
        hasLength(1),
      );
    }
  }, skip: skip);
}
