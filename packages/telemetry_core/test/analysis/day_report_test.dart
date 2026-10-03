// The computed day report (analysis/day_report.dart, KAN-71), ported from
// FlappedEar Overlays native/tests/DayReportTests.cpp: provenance on every
// result, stale results never show a value, and a report read from
// elsewhere is validated and bounded.
import 'dart:convert';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

List<int> key(String text) => utf8.encode(text);

DayReportResult bestLap(String decisions) => DayReportResult(
  id: 'bestLap',
  algorithm: 'outing-ranking-v1',
  status: DayResultStatus.available,
  range: {'scope': 'day', 'groupId': 'g1', 'eligibleLapCount': 12},
  value: {'seconds': 109.898, 'label': 'Session 5 · LAP 2'},
  evidence: [
    {
      'kind': 'lap',
      'reference': {'runId': 'r5'},
    },
  ],
  decisionsKey: key(decisions),
);

DayReportInput input(String decisions, List<DayReportResult> results) => DayReportInput(
  eventId: 'event',
  groupId: 'g1',
  groupLabel: 'Group 1',
  decisionsKey: key(decisions),
  results: results,
);

List<Map<String, Object?>> resultsOf(Map<String, Object?> report) =>
    (report['results'] as List).cast<Map<String, Object?>>();

// A deep copy, as a report read from elsewhere would be.
Map<String, Object?> copy(Map<String, Object?> report) =>
    jsonDecode(jsonEncode(report)) as Map<String, Object?>;

void main() {
  test('carries provenance for every result', () {
    final report = buildDayReport(
      input('key-1', [
        bestLap('key-1'),
        DayReportResult(
          id: 'theoreticalBest',
          algorithm: 'theoretical-best-v1',
          reason: 'Not calculated yet.',
          range: {'scope': 'day', 'groupId': 'g1'},
        ),
      ]),
    );
    expect(report['schema'], dayReportSchema);
    expect(report['version'], dayReportSchemaVersion);
    expect(report['decisionsKey'], '6b65792d31'); // "key-1" in hex
    final results = resultsOf(report);
    expect(results, hasLength(2));
    final best = results[0];
    expect(best['status'], 'available');
    expect(best['algorithm'], 'outing-ranking-v1');
    expect((best['range'] as Map)['eligibleLapCount'], 12);
    expect(best['evidence'], hasLength(1));
    expect((best['value'] as Map)['seconds'], closeTo(109.898, 1e-9));
    final theoretical = results[1];
    expect(theoretical['status'], 'notComputed');
    expect(theoretical.containsKey('value'), isFalse);
    expect(theoretical['reason'], 'Not calculated yet.');
    expect(validateDayReport(copy(report)), isEmpty);
  });

  test('drops values computed under other decisions', () {
    // A lap was excluded after the ranking ran: the old number must not show.
    var result = resultsOf(buildDayReport(input('key-2', [bestLap('key-1')]))).first;
    expect(result['status'], 'stale');
    expect(result.containsKey('value'), isFalse);
    expect(result['evidence'], isEmpty);
    expect(result['reason'], isNotEmpty);
    // A result that does not depend on the decisions is never stale by them.
    final independent = DayReportResult(
      id: 'temperatures',
      algorithm: 'outing-ranking-v1',
      status: DayResultStatus.available,
      range: {'scope': 'day'},
    );
    result = resultsOf(buildDayReport(input('key-2', [independent]))).first;
    expect(result['status'], 'available');
  });

  test('rejects malformed input', () {
    expect(() => buildDayReport(input('k', [bestLap('k'), bestLap('k')])), throwsArgumentError);
    expect(
      () => buildDayReport(
        input('k', [
          DayReportResult(id: 'bestLap', algorithm: '', status: DayResultStatus.available),
        ]),
      ),
      throwsArgumentError,
    );
    expect(
      () => buildDayReport(input('k', [DayReportResult(id: '', algorithm: 'a')])),
      throwsArgumentError,
    );
    expect(
      () => buildDayReport(
        input('k', [
          DayReportResult(
            id: 'bestLap',
            algorithm: 'a',
            evidence: [
              {'reference': <String, Object?>{}},
            ],
          ),
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('validates read reports', () {
    final good = buildDayReport(input('k', [bestLap('k')]));
    expect(validateDayReport(copy(good)), isEmpty);
    expect(validateDayReport({}), isNotEmpty);
    expect(validateDayReport(copy(good)..['version'] = 99), isNotEmpty);
    expect(validateDayReport(copy(good)..['results'] = 'x'), isNotEmpty);
    Map<String, Object?> withResult(void Function(Map<String, Object?> entry) change) {
      final report = copy(good);
      change(resultsOf(report).first);
      return report;
    }

    // A value on a result that is not available.
    expect(validateDayReport(withResult((entry) => entry['status'] = 'stale')), isNotEmpty);
    // Unknown status and unknown evidence kind.
    expect(validateDayReport(withResult((entry) => entry['status'] = 'guessed')), isNotEmpty);
    expect(
      validateDayReport(
        withResult(
          (entry) => entry['evidence'] = [
            {'kind': 'video'},
          ],
        ),
      ),
      isNotEmpty,
    );
    expect(validateDayReport(withResult((entry) => entry.remove('range'))), isNotEmpty);
    expect(validateDayReport(withResult((entry) => entry['algorithm'] = '')), isNotEmpty);
    // Bounded: too many results or too much evidence is refused before use.
    final large = copy(good)
      ..['results'] = [
        for (var i = 0; i <= maximumDayReportResults; ++i) {...resultsOf(good).first, 'id': 'r$i'},
      ];
    expect(validateDayReport(large), isNotEmpty);
    expect(
      validateDayReport(
        withResult(
          (entry) => entry['evidence'] = [
            for (var i = 0; i <= maximumDayReportEvidence; ++i) {'kind': 'lap'},
          ],
        ),
      ),
      isNotEmpty,
    );
  });
}
