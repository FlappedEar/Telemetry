// The driver profile on a real day split in two, as if driven on two days.
// Set FLAPPEDEAR_REAL_DAY to a folder of one day's VBO files; nothing from
// them is written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test(
    'both halves of a real day are one track, also after reading the profile back',
    () {
      final files =
          Directory(folder)
              .listSync()
              .whereType<File>()
              .where((file) => file.path.toLowerCase().endsWith('.vbo'))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, greaterThanOrEqualTo(2));
      final runs = <DayRunInput>[
        for (final (index, file) in files.indexed)
          () {
            final session = parseVboFile(file.path);
            return DayRunInput(
              runId: 'run${index + 1}',
              name: 'Session ${index + 1}',
              contentSha256: '${index + 1}'.padLeft(64, '0'),
              session: session,
              laps: deriveSourceLapSession(session),
            );
          }(),
      ];
      final half = runs.length ~/ 2;
      ProfileDayInput day(String id, List<DayRunInput> runs) => ProfileDayInput.fromAnalysis(
        eventId: id,
        file: 'Days/$id.fetproject',
        name: id,
        analysis: analyzeDay(runs),
      );
      final first = day('first', runs.take(half).toList());
      final second = day('second', runs.skip(half).toList());
      expect(first.route, isNotNull);
      expect(second.route, isNotNull);

      var profile = addDayToProfile(
        DriverProfile.empty(Random(1)),
        first,
        defaultCarName: 'My car',
        defaultTrackName: 'Track',
      );
      profile = decodeDriverProfile(encodeDriverProfile(profile));
      profile = addDayToProfile(
        profile,
        second,
        defaultCarName: 'My car',
        defaultTrackName: 'Track',
      );
      expect(profile.tracks, hasLength(1));
      expect(profile.day('second')!.trackId, profile.day('first')!.trackId);
      final track = profile.tracks.single;
      print(
        'Track: ${track.route.lengthMeters.toStringAsFixed(0)} m, ${track.route.direction.label}; '
        'best ${first.bestLapSeconds?.toStringAsFixed(3)} s and '
        '${second.bestLapSeconds?.toStringAsFixed(3)} s; '
        'sessions ${[for (final d in profile.days)
          for (final s in d.sessions) '${s.name}: ${s.lapCount} laps'].join(', ')}',
      );
      final best = [first.bestLapSeconds!, second.bestLapSeconds!].reduce(min);
      expect(best, analyzeDay(runs).ranking!.bestOfDay!.durationSeconds);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
