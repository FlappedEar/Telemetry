import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// The results of one imported day and the user's choices on them: the group
/// shown and the laps excluded. Re-ranking keeps rows and routes, so it runs
/// on the interface thread.
final class DayResultsController extends ChangeNotifier {
  DayResultsController({
    required List<NamedRun> runs,
    required DayAnalysis analysis,
  }) : runs = List.unmodifiable(runs),
       _analysis = analysis,
       _groupId = analysis.chosenGroupId;

  final List<NamedRun> runs;
  DayAnalysis _analysis;
  String? _groupId;
  final Map<DayLapReference, String> _exclusions = {};

  DayAnalysis get analysis => _analysis;
  DayRanking? get ranking => _analysis.ranking;
  Map<DayLapReference, String> get exclusions => Map.unmodifiable(_exclusions);

  /// The recording of [runId].
  TelemetrySession? session(String runId) {
    for (final named in runs) {
      if (named.run.id == runId) return named.run.telemetry;
    }
    return null;
  }

  /// Shows [groupId]'s ranking first.
  void chooseGroup(String groupId) {
    if (groupId == _analysis.chosenGroupId) return;
    _groupId = groupId;
    _rerank();
  }

  /// Leaves [row] out of the ranking with [reason]; an empty reason is
  /// refused.
  bool exclude(DayLapRow row, String reason) {
    final trimmed = reason.trim();
    if (row.type != LapSectionType.lap ||
        trimmed.isEmpty ||
        trimmed.length > 256) {
      return false;
    }
    _exclusions[row.reference] = trimmed;
    _rerank();
    return true;
  }

  void include(DayLapRow row) {
    if (_exclusions.remove(row.reference) != null) _rerank();
  }

  /// The user's reason for excluding [row], or null.
  String? exclusionReason(DayLapRow row) => _exclusions[row.reference];

  void _rerank() {
    _analysis = rerankDay(
      _analysis,
      exclusions: _exclusions,
      preferredGroupId: _groupId,
    );
    notifyListeners();
  }

  /// Why [row] is not ranked in the shown group; empty when it is ranked.
  List<LapIssue> issues(DayLapRow row) {
    final chosen = _analysis.chosenGroup;
    final configuration =
        _analysis.configurations[row.runId] ?? const TrackConfiguration();
    final issues = dayLapIssues(
      row,
      configuration,
      userExclusionReason: _exclusions[row.reference] ?? '',
    );
    if (chosen != null && configuration.compatibilityGroupId != chosen.id) {
      for (final issue in lapCompatibilityIssues(
        configuration,
        reference: chosen.configuration,
      )) {
        if (!issues.contains(issue)) issues.insert(0, issue);
      }
    }
    return issues;
  }

  /// Whether [row] is the best lap of the day in the shown group.
  bool isBestOfDay(DayLapRow row) =>
      ranking?.bestOfDay?.reference == row.reference;

  /// Whether [row] is its run's best lap in the shown group.
  bool isBestOfRun(DayLapRow row) =>
      ranking?.runs.any((run) => run.bestLap?.reference == row.reference) ??
      false;
}
