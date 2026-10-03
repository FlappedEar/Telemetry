// Comparison decisions between Telemetry and FlappedEar Overlays (FET-53),
// on the shared fixtures' recordings. Runs only when
// FLAPPEDEAR_OVERLAYS_ROUNDTRIP names the built tool/cpp_project_roundtrip;
// see tool/README.md.
//
// - A day whose comparison group nobody chose stays "automatic" in Overlays
//   after Telemetry saves it.
// - The comparison set up in Telemetry (the A/B pair, the range and the
//   charts) is the one Overlays restores, and the one set up in Overlays
//   opens in Telemetry and survives its re-save.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/roundtrip.dart';

final _tool = Platform.environment['FLAPPEDEAR_OVERLAYS_ROUNDTRIP'];
const _skip = 'Set FLAPPEDEAR_OVERLAYS_ROUNDTRIP to tool/cpp_project_roundtrip';

Object? _output(List<String> arguments) {
  final result = Process.runSync(
    _tool!,
    arguments,
    environment: {'LC_ALL': 'C.UTF-8'},
    stdoutEncoding: utf8,
  );
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return jsonDecode(result.stdout as String);
}

Map<String, Object?> _inspect(String path) =>
    (_output(['inspect', path])! as List).single as Map<String, Object?>;

Map<String, Object?> _object(Object? value) => value! as Map<String, Object?>;

String _label(DayLapRow row) => '${row.runName} · ${row.type.label} ${row.lapNumber}';

Map<String, Object?>? _decisions(String path) =>
    (readDayDocument(path)['event']! as Map)['analysisDecisions'] as Map<String, Object?>?;

/// Telemetry opens the day at [path] and saves it, with [comparison].
Future<OpenedDay> _telemetrySave(
  String path, {
  ComparisonDecisions comparison = const ComparisonDecisions(),
}) async {
  final day = openDay(path);
  expect(day.missing, isEmpty);
  await saveDayDocument(
    path,
    dayDocument(
      eventId: day.eventId,
      name: day.name,
      runs: day.runs,
      analysis: day.analysis!,
      exclusions: day.exclusions,
      projectPath: path,
      previous: day.document,
      previousPath: path,
      comparison: comparison,
    ),
  );
  return day;
}

void main() {
  late Directory directory;
  late String root;
  late List<String> recordings;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('overlays_comparison');
    root = directory.resolveSymbolicLinksSync();
    copyRoundtripFixtures(root);
    recordings = [
      for (final name in ['morning', 'midday', 'afternoon'])
        p.join(root, 'recordings', '$name.vbo'),
    ];
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'a group nobody chose stays automatic through a Telemetry save',
    () async {
      final path = p.join(root, 'automatic.fetproject');
      final imported = _output(['import', path, 'Automatic day', ...recordings])! as Map;
      expect(imported['comparisonSelectionState'], 'automatic');
      expect(_decisions(path), isNull);

      await _telemetrySave(path);
      expect(_decisions(path), isNull);
      final inspected = _inspect(path);
      expect(inspected['comparisonSelectionState'], 'automatic');
      expect(inspected['comparisonGroupId'], imported['comparisonGroupId']);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'a comparison set up in Telemetry is the one Overlays restores',
    () async {
      final path = p.join(root, 'telemetry-compared.fetproject');
      _output(['import', path, 'Telemetry comparison', ...recordings]);
      final day = openDay(path);
      final laps = day.analysis!.ranking!.eligibleLaps;
      final a = laps[1], b = laps[0];
      await _telemetrySave(
        path,
        comparison: ComparisonDecisions(
          slots: [a.reference, b.reference],
          range: (15.0, 210.5),
          channels: const [deltaTimeChannel, 'velocity'],
        ),
      );

      final comparison = _object(_inspect(path)['comparison']);
      expect(comparison['slots'], [
        {'lap': _label(a), 'state': 'ready'},
        {'lap': _label(b), 'state': 'ready'},
      ]);
      expect(comparison['pairReady'], isTrue);
      expect(comparison['range'], [15.0, 210.5]);
      expect(comparison['channels'], [deltaTimeChannel, 'velocity']);
      // Overlays' save keeps the decisions as Telemetry wrote them.
      final written = _decisions(path);
      _output(['resave', path]);
      expect(_decisions(path), written);
      expect(_inspect(path)['comparisonSelectionState'], 'automatic');
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );

  test(
    'a comparison set up in Overlays opens in Telemetry and survives its save',
    () async {
      final path = p.join(root, 'overlays-compared.fetproject');
      final imported = _output(['import', path, 'Overlays comparison', ...recordings])! as Map;
      final eligible = [
        for (final lap in (imported['laps']! as List).cast<Map<String, Object?>>())
          if (lap['referenceEligible'] == true && lap['groupId'] == imported['comparisonGroupId'])
            lap['label']! as String,
      ];
      expect(eligible.length, greaterThanOrEqualTo(2));
      final compared =
          _output([
                'compare',
                path,
                eligible.last,
                eligible.first,
                '20',
                '180.25',
                deltaTimeChannel,
                'velocity',
              ])!
              as Map<String, Object?>;
      final overlays = _object(compared['comparison']);
      expect(overlays['pairReady'], isTrue);

      final day = openDay(path);
      final rows = {for (final row in day.analysis!.rows) row.reference: row};
      final slots = day.comparison.slots!;
      expect([for (final slot in slots) _label(rows[slot]!)], [eligible.last, eligible.first]);
      expect(day.comparison.range, (20.0, 180.25));
      expect(day.comparison.channels, [deltaTimeChannel, 'velocity']);
      expect(dayLapsComparable(day.analysis!, rows[slots[0]]!, rows[slots[1]]!), isTrue);

      // Telemetry's save keeps them; Overlays restores the same comparison.
      final written = _decisions(path);
      await _telemetrySave(path);
      expect(_decisions(path), written);
      expect(_object(_inspect(path)['comparison']), overlays);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: _tool == null ? _skip : false,
  );
}
