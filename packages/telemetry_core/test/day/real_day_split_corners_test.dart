// Corner chains divided into single corners (FET-115) on a real day. Set
// FLAPPEDEAR_REAL_DAY to a folder of one day's VBO files; nothing from them is
// written anywhere.
import 'dart:io';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

final configuration = 'compatibility-v1:${'0123456789abcdef' * 4}';

void main() {
  final folder = Platform.environment['FLAPPEDEAR_REAL_DAY'] ?? '';
  final skip = folder.isEmpty ? 'FLAPPEDEAR_REAL_DAY is not set' : null;

  test('the best lap has single corners; a day saved with chains keeps them', () {
    final files =
        Directory(folder)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.toLowerCase().endsWith('.vbo'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final inputs = [
      for (final (index, file) in files.indexed)
        () {
          final session = loadRecording(file.path);
          return DayRunInput(
            runId: 'run${index + 1}',
            name: 'Session ${index + 1}',
            contentSha256: '${index + 1}'.padLeft(64, '0'),
            session: session,
            laps: deriveSourceLapSession(session),
          );
        }(),
    ];
    final best = analyzeDay(inputs).chosenGroup!.ranking!.bestOfDay!;
    final input = inputs.firstWhere((candidate) => candidate.runId == best.runId);
    SegmentReview review({bool split = true, List<Map<String, Object?>> approved = const []}) =>
        computeSegmentReview(
          input.session,
          input.laps,
          lapNumber: best.lapNumber,
          startTime: best.start,
          endTime: best.end,
          splitCornerChains: split,
          approved: approved,
        );

    final chained = review(split: false);
    final split = review();
    List<String> names(SegmentReview r) => [for (final p in r.proposals.proposals) p.name];
    print('chained: ${names(chained).join(', ')}');
    print('split: ${names(split).join(', ')}');
    expect(chained.proposals.proposals.where((p) => p.chainedCorners > 1), isNotEmpty);
    expect(split.proposals.proposals.where((p) => p.chainedCorners > 1), isEmpty);
    expect(split.proposals.proposals.length, greaterThan(chained.proposals.proposals.length));

    // The pieces still tile the lap: every proposal starts where the one
    // before it ends, round the whole lap.
    final all = split.proposals.proposals;
    for (var i = 0; i < all.length; ++i) {
      final next = all[(i + 1) % all.length];
      expect(all[i].end.progressMeters, closeTo(next.start.progressMeters, 1e-6), reason: '$i');
    }
    expect(
      all.fold<double>(0, (sum, p) => sum + p.lengthMeters),
      closeTo(split.axis.lengthMeters, 1e-6),
    );

    // A chain's turn is the sum of its corners' (the stretch between two
    // corners turns next to nothing).
    final chainTurn = chained.proposals.proposals.fold<double>(0, (sum, p) => sum + p.turnRadians);
    final splitTurn = all.fold<double>(0, (sum, p) => sum + p.turnRadians);
    expect(splitTurn, closeTo(chainTurn, 1e-6));

    // Segments approved by an earlier version are still the proposals shown.
    final earlier = approveAllProposals(null, chained, configuration, random: Random(1))!;
    expect(names(review(approved: earlier)), names(chained));
    final now = approveAllProposals(null, split, configuration, random: Random(1))!;
    expect(names(review(approved: now)), names(split));
    expect(names(review()), names(split));
  }, skip: skip);
}
