// Port of FlappedEar Overlays native/src/telemetry/DayReport.{h,cpp}
// (revision d4d1039, FET-36): a computed day report (KAN-71). The report
// presents results already computed elsewhere (ranking, theoretical best,
// time losses, consistency, progression, recorded temperatures and heart
// rate); it never recalculates them, and a screen presents the report rather
// than recomputing.
//
// Every result carries its producing algorithm (and revision where the
// producer has one), the range it covers, a data status, and evidence
// references a screen can open (a lap, a segment of a lap, a recorded channel
// of a run). Results are keyed by the analysis decisions (group, approved
// segments, exclusions, population) they were computed under; a result whose
// decisions key differs from the report's is reported as "stale" and its
// value is dropped, so a changed decision never shows an old number.
//
// The document is plain JSON (maps, lists, strings, numbers, booleans), as
// Overlays writes it.
const String dayReportSchema = 'flappedear.day-report';
const int dayReportSchemaVersion = 1;
const String dayReportAlgorithm = 'day-report-v1';

// Bounds for reading an untrusted report document.
const int maximumDayReportResults = 64;
const int maximumDayReportEvidence = 4096;

/// A result's data status.
enum DayResultStatus {
  /// Computed for the current decisions.
  available('available'),

  /// Computed, but there is no result (the reason says why).
  unavailable('unavailable'),

  /// Not requested yet.
  notComputed('notComputed'),

  /// A worker is running.
  computing('computing'),

  /// Computed under different analysis decisions; the value is dropped.
  stale('stale');

  const DayResultStatus(this.code);

  /// The name in the report document.
  final String code;
}

const _evidenceKinds = {'lap', 'segment', 'channel', 'run'};

/// One result going into a report.
final class DayReportResult {
  DayReportResult({
    required this.id,
    required this.algorithm,
    this.revision = '',
    this.status = DayResultStatus.notComputed,
    this.reason = '',
    Map<String, Object?>? range,
    Map<String, Object?>? value,
    List<Map<String, Object?>>? evidence,
    this.decisionsKey = const [],
  }) : range = range ?? {},
       value = value ?? {},
       evidence = evidence ?? [];

  /// Stable identifier, e.g. `bestLap`, `theoreticalBest`.
  final String id;

  /// The producing algorithm; required.
  final String algorithm;

  /// A finer producer revision, when it has one.
  final String revision;
  DayResultStatus status;

  /// Why a result is unavailable or not computed.
  String reason;

  /// `scope` ("day", "run", ...), `groupId` and what else it covers.
  final Map<String, Object?> range;

  /// The computed result (only when available).
  final Map<String, Object?> value;

  /// `{"kind": "lap" | "segment" | "channel" | "run", ...}`.
  final List<Map<String, Object?>> evidence;

  /// The analysis decisions it was computed under (opaque bytes); empty when
  /// it does not depend on them (whole-recording channel summaries,
  /// invalidated with the run set instead).
  final List<int> decisionsKey;
}

/// What a report is assembled from.
final class DayReportInput {
  const DayReportInput({
    this.eventId = '',
    this.groupId = '',
    this.groupLabel = '',
    this.decisionsKey = const [],
    this.results = const [],
  });

  final String eventId;
  final String groupId;
  final String groupLabel;

  /// The current analysis decisions (opaque bytes, written in hex).
  final List<int> decisionsKey;
  final List<DayReportResult> results;
}

/// The report document. Throws [ArgumentError] for a malformed input
/// (missing id or algorithm, duplicate id, evidence without a kind).
Map<String, Object?> buildDayReport(DayReportInput input) {
  final results = <Map<String, Object?>>[];
  final ids = <String>{};
  for (final result in input.results) {
    if (result.id.isEmpty) throw ArgumentError('A day-report result needs an id.');
    if (result.algorithm.isEmpty) {
      throw ArgumentError('Day-report result ${result.id} has no algorithm.');
    }
    if (!ids.add(result.id)) throw ArgumentError('Duplicate day-report result ${result.id}.');
    for (final item in result.evidence) {
      if (!_evidenceKinds.contains(item['kind'])) {
        throw ArgumentError('Day-report result ${result.id} has evidence without a kind.');
      }
    }
    var status = result.status;
    var reason = result.reason;
    // Never present a number computed under other analysis decisions.
    if (status == DayResultStatus.available &&
        result.decisionsKey.isNotEmpty &&
        !_sameBytes(result.decisionsKey, input.decisionsKey)) {
      status = DayResultStatus.stale;
      reason = 'The analysis decisions changed after this result was computed.';
    }
    results.add({
      'id': result.id,
      'algorithm': result.algorithm,
      'status': status.code,
      'range': result.range,
      if (result.revision.isNotEmpty) 'revision': result.revision,
      if (status == DayResultStatus.available) ...{
        'value': result.value,
        'evidence': result.evidence,
      } else ...{
        'evidence': <Map<String, Object?>>[],
        if (reason.isNotEmpty) 'reason': reason,
      },
    });
  }
  return {
    'schema': dayReportSchema,
    'version': dayReportSchemaVersion,
    'algorithm': dayReportAlgorithm,
    'eventId': input.eventId,
    'groupId': input.groupId,
    'groupLabel': input.groupLabel,
    'decisionsKey': _hex(input.decisionsKey),
    'results': results,
  };
}

String _hex(List<int> key) =>
    [for (final byte in key) (byte & 0xff).toRadixString(16).padLeft(2, '0')].join();

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Checks a report document read from elsewhere; empty when valid,
/// otherwise the first problem found. Bounded before iterating.
String validateDayReport(Map<String, Object?> report) {
  if (report['schema'] != dayReportSchema) return 'Not a day report.';
  final version = report['version'];
  if (version is! num || version != dayReportSchemaVersion) {
    return 'Unsupported day-report version.';
  }
  final results = report['results'];
  if (results is! List) return 'The day report has no results.';
  if (results.length > maximumDayReportResults) return 'The day report has too many results.';
  final ids = <String>{};
  var evidenceCount = 0;
  for (final value in results) {
    if (value is! Map) return 'A day-report result is not an object.';
    final id = value['id'] is String ? value['id'] as String : '';
    if (id.isEmpty || ids.contains(id)) return 'A day-report result has a missing or duplicate id.';
    ids.add(id);
    final algorithm = value['algorithm'];
    if (algorithm is! String || algorithm.isEmpty) return 'Result $id has no algorithm.';
    final status = value['status'];
    if (!DayResultStatus.values.any((known) => known.code == status)) {
      return 'Result $id has an unknown status.';
    }
    if (value['range'] is! Map) return 'Result $id has no range.';
    if ((status == 'available') != value.containsKey('value')) {
      return 'Result $id has a value that does not match its status.';
    }
    final evidence = value['evidence'];
    if (evidence is! List) return 'Result $id has no evidence list.';
    evidenceCount += evidence.length;
    if (evidenceCount > maximumDayReportEvidence) return 'The day report has too much evidence.';
    for (final item in evidence) {
      if (item is! Map || !_evidenceKinds.contains(item['kind'])) {
        return 'Result $id has evidence without a known kind.';
      }
    }
  }
  return '';
}
