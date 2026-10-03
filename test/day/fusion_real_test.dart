// A real day's VBO and RCZ recordings combined (FET-51). Runs only when
// FET_FUSION_DAY names a folder of recordings; real recordings are private
// and never committed. It prints summary figures only. Report this result
// separately from synthetic tests.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/format.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// What a lap row shows and is ranked by.
List<Object> _rows(DayResultsController controller) => [
  for (final row in controller.analysis.rows)
    (
      row.reference,
      row.displayName,
      row.durationSeconds,
      controller.issues(row).join(','),
      controller.isBestOfDay(row),
      controller.isBestOfRun(row),
    ),
];

void main() {
  final day = Platform.environment['FET_FUSION_DAY'] ?? '';
  final skip = day.isEmpty
      ? 'FET_FUSION_DAY is not set'
      : !Directory(day).existsSync()
      ? 'FET_FUSION_DAY is not a folder'
      : null;

  test(
    'the RCZ of each session is combined and no lap changes',
    () async {
      final vbos = [
        for (final entity in Directory(day).listSync())
          if (entity is File && entity.path.toLowerCase().endsWith('.vbo'))
            entity.path,
      ];
      final plain = runDayImport((paths: vbos, includeSubfolders: false));
      final both = runDayImport((paths: [day], includeSubfolders: false));
      final alone = DayResultsController(
        runs: plain.runs,
        analysis: plain.analysis!,
      );
      final fused = DayResultsController(
        runs: both.runs,
        analysis: both.analysis!,
        fusions: both.fusions,
      );
      addTearDown(alone.dispose);
      addTearDown(fused.dispose);
      final fusions = both.fusions.values.toList();
      final step = both.steps.firstWhere(
        (step) => step.name == 'Align and combine VBO and RCZ',
      );
      debugPrint(
        'sessions ${both.runs.length}, pairs ${fusions.length}, '
        'aligned ${fusions.where((fusion) => fusion.fused).length}, '
        'added ${[for (final fusion in fusions) fusion.channelOrigins.length]}, '
        'conflicts ${[for (final fusion in fusions) fusion.conflicts.length]}, '
        'unit mismatches '
        '${[for (final fusion in fusions) fusion.result?.unitMismatches.length]}, '
        'resolved by declared clock '
        '${fusions.where((fusion) => fusion.resolvedByDeclaredClock).length}, '
        'aligning took ${step.duration.inMilliseconds} ms',
      );
      expect(fusions, hasLength(both.runs.length));
      expect(fusions.every((fusion) => fusion.fused), isTrue);
      expect(_rows(fused), _rows(alone));
      final best = fused.ranking!.bestOfDay!;
      expect(best.reference, alone.ranking!.bestOfDay!.reference);
      debugPrint(
        'rows ${fused.analysis.rows.length}, '
        'best lap ${displayTime(best.durationSeconds)}',
      );

      // Saved and opened again: applied from the document, nothing aligned.
      final directory = Directory.systemTemp.createTempSync('fusion_real');
      addTearDown(() => directory.deleteSync(recursive: true));
      final path = '${directory.path}/Day.fetproject';
      await fused.save(path);
      final clock = Stopwatch()..start();
      final opened = DayResultsController.opened(openDay(path));
      addTearDown(opened.dispose);
      final reopened = [
        for (final named in opened.runs) opened.fusion(named.run.id),
      ];
      debugPrint(
        'reopened in ${clock.elapsedMilliseconds} ms: '
        '${reopened.where((fusion) => fusion?.fromDocument ?? false).length} '
        'of ${reopened.length} applied from the document',
      );
      expect(reopened.every((fusion) => fusion!.fromDocument), isTrue);
      expect(opened.dirty, isFalse);
      expect(_rows(opened), _rows(alone));
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
