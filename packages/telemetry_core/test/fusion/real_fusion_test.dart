// Recording alignment and channel fusion on a real day. Runs only when
// FET_FUSION_DAY names a folder of recordings; real recordings are private
// and never committed. Report this result separately from synthetic tests.
//
// The pairs are the import plan's: each RCZ grouped under the VBO it
// uniquely matches (automaticVboPrimaries). For every pair the test aligns
// the RCZ to the VBO and, when there is a measured offset, fuses it as
// Overlays' app does (no rules) and again with fillGaps for every channel
// both recorded; an unaligned pair is fused with its measured clock anyway
// ("forced") to exercise the fusion. It prints summary figures only.
//
// FET_FUSION_PAIRS_OUT=<file> writes the pairs, as cpp_fusion_dump --pairs
// reads them; FET_FUSION_REFERENCE=<file> (that tool's output) compares
// every value with Overlays' C++. Both files hold local paths: keep them out
// of the repository.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_json.dart';

void main() {
  final day = Platform.environment['FET_FUSION_DAY'] ?? '';
  final skip = day.isEmpty
      ? 'FET_FUSION_DAY is not set'
      : !Directory(day).existsSync()
      ? 'FET_FUSION_DAY is not a folder'
      : null;

  test(
    'aligns and fuses the VBO and RCZ recordings of a real day',
    () {
      final paths = [
        for (final entity in Directory(day).listSync())
          if (entity is File && supportsRecordingPath(entity.path)) entity.path,
      ]..sort();
      final plan = prepareTelemetryImport(paths);
      final groups = automaticVboPrimaries(plan);
      final runs = {for (final run in plan.runs) run.id: run};
      final pairs = [
        for (final MapEntry(key: alternative, value: primary) in groups.entries)
          if (alternative != primary) (runs[primary]!, runs[alternative]!),
      ]..sort((a, b) => a.$1.sourcePath.compareTo(b.$1.sourcePath));
      print('recordings: ${paths.length}, pairs: ${pairs.length}');
      expect(pairs, isNotEmpty);

      final pairsOut = Platform.environment['FET_FUSION_PAIRS_OUT'];
      if (pairsOut != null) {
        File(pairsOut).writeAsStringSync(
          jsonEncode({
            'pairs': [
              for (final (primary, alternative) in pairs)
                {'primary': primary.sourcePath, 'alternative': alternative.sourcePath},
            ],
          }),
        );
      }
      final referencePath = Platform.environment['FET_FUSION_REFERENCE'];
      final reference = referencePath == null
          ? null
          : ((qtJsonDecode(File(referencePath).readAsStringSync()) as Map)['pairs'] as List)
                .cast<Map<String, Object?>>();
      if (reference != null) expect(reference, hasLength(pairs.length));

      var failures = <String>[];
      for (var index = 0; index < pairs.length; ++index) {
        final (primaryRun, alternativeRun) = pairs[index];
        final primary = primaryRun.telemetry, alternative = alternativeRun.telemetry;
        final check = FusionCheck('pair ${index + 1}');
        final expected = reference?[index];
        final alignment = alignRecordings(primary, alternative);
        if (expected != null) {
          check.alignment('alignment', alignment, expected['alignment'] as Map<String, Object?>);
        }
        final summary = StringBuffer(
          'pair ${index + 1}: ${alignment.status}'
          '${alignment.reason.isEmpty ? '' : ' (${alignment.reason})'}, '
          'offset ${_seconds(alignment.offset)}, drift ${_ppm(alignment.driftPpm)}, '
          'uncertainty ${_seconds(alignment.uncertaintySeconds)}, '
          'declared ${_seconds(alignment.declaredOffset)}, '
          'correlation ${alignment.correlation.toStringAsFixed(4)}, '
          'confidence ${alignment.confidence}, windows ${alignment.usedWindows}/${alignment.windows.length}'
          '${alignment.resolvedByDeclaredClock ? ', resolved by the declared clock' : ''}',
        );
        final offset = alignment.offset;
        if (offset != null) {
          final forced = alignment.status != alignmentAligned;
          final source = FusionSource(
            sourceId: 'alternative',
            session: alternative,
            clock: SourceClock(offsetSeconds: offset, driftPpm: alignment.driftPpm ?? 0.0),
            alignmentStatus: alignmentAligned,
          );
          final plain = fuseChannels(primary, 'primary', [source]);
          final filled = fuseChannels(
            primary,
            'primary',
            [source],
            policy: FusionPolicy(
              rules: {
                for (final channel in plain.channels)
                  if (channel.comparedSourceId.isNotEmpty)
                    channel.key: (sourceId: 'alternative', rule: FusionRule.fillGaps),
              },
            ),
          );
          if (expected != null) {
            check.same('forced', forced, expected['forced']);
            check.fusion('fusion', plain, expected['fusion'] as Map<String, Object?>);
            check.fusion('filled', filled, expected['filled'] as Map<String, Object?>);
            check.session(
              'filled session',
              fusedSession(primary, filled),
              expected['filledSession'] as Map<String, Object?>,
            );
          }
          int count(ChannelFusionResult result, bool Function(FusedChannel) test) =>
              result.channels.where(test).length;
          summary.write(
            '; fusion${forced ? ' (forced)' : ''}: '
            'added ${count(plain, (c) => c.rule == 'added')}, '
            'compared ${count(plain, (c) => c.comparedSourceId.isNotEmpty)}, '
            'conflicting ${count(plain, (c) => c.conflicting)} '
            '(unresolved ${plain.unresolved.length}), '
            'unit mismatches ${plain.unitMismatches.length}, '
            'merged with fillGaps ${count(filled, (c) => c.rule == 'fillGaps')}',
          );
        }
        if (expected != null) {
          summary.write(
            '; C++: ${check.compared} values, '
            '${check.mismatched == 0 ? 'all equal' : '${check.mismatched} differ'}',
          );
          failures = [...failures, ...check.failures];
        }
        print(summary);
      }
      expect(failures, isEmpty);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

String _seconds(double? value) => value == null ? 'none' : '${value.toStringAsFixed(3)} s';

String _ppm(double? value) => value == null ? 'none' : '${value.toStringAsFixed(1)} ppm';
