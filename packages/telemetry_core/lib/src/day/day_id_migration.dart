// Ids a day saved before FET-250 holds, moved to the ids of today.
//
// FET-250 changed the `gateRevision` (`gates-v1:` → `gates-v2:`) so that the
// VBO and the RCZ of one circuit form one `compatibility-v1` group. The ids
// that hang on a group (the segments and goals a driver kept, the group shown)
// and the route a run was given are stored with the old revision. Opening a
// day moves them, so nothing the driver kept is lost; the next save writes
// the new ids.
import 'package:fetproject/fetproject.dart' as fet;

import '../telemetry_session.dart';
import 'day_analysis.dart';
import 'run_goals.dart';

/// Moves [run] (a day document's run, whose recording is [session]) from
/// the `gates-v1:` revision of its gates to the current one, in its
/// `trackConfiguration` and its saved route (`trackInference`), when the
/// stored revision is that session's own, so the route keeps its id and the
/// run's lap references can be rekeyed. The lap derivation key hashes the
/// track configuration, so the old key of the run is recorded in [keys]
/// (`runId|old key` → new key) for [rekeyLapReferences]. A gate that is not
/// the session's, or a session whose gates are unresolved, is left as saved.
void migrateRunGates(Map<String, Object?> run, TelemetrySession session, Map<String, String> keys) {
  final legacy = legacySessionGateRevision(session);
  final current = sessionGateRevision(session);
  if (legacy == null || current == null) return;
  final before = fet.lapDerivationV1Key(run);
  final configuration = run['trackConfiguration'];
  var changed = false;
  if (configuration is Map<String, Object?> && configuration['gateRevision'] == legacy) {
    configuration['gateRevision'] = current;
    changed = true;
  }
  final inference = run['trackInference'];
  if (inference is Map<String, Object?> && inference['gateRevision'] == legacy) {
    inference['gateRevision'] = current;
  }
  if (changed) keys['${run['id']}|$before'] = fet.lapDerivationV1Key(run);
}

/// Replaces the `derivationKey` of every lap reference in [event] (exclusions
/// and the comparison pair) that [keys] (from [migrateRunGates]) names.
void rekeyLapReferences(Object? event, Map<String, String> keys) {
  if (keys.isEmpty) return;
  void walk(Object? value) {
    if (value is Map<String, Object?>) {
      final key = value['derivationKey'];
      final moved = key is String ? keys['${value['runId']}|$key'] : null;
      if (moved != null) value['derivationKey'] = moved;
      value.values.forEach(walk);
    } else if (value is List) {
      value.forEach(walk);
    }
  }

  walk(event);
}

/// Old group id → current group id, for every loaded run of [analysis]
/// whose group id was derived from a legacy gate revision. [sessions] are the
/// loaded runs' recordings by run id.
Map<String, String> legacyGroupIds(DayAnalysis analysis, Map<String, TelemetrySession> sessions) {
  final map = <String, String>{};
  sessions.forEach((runId, session) {
    final configuration = analysis.configurations[runId];
    final current = configuration?.compatibilityGroupId;
    final legacyGate = legacySessionGateRevision(session);
    if (configuration == null || current == null || legacyGate == null) return;
    final legacy = fet.compatibilityV1Id({...configuration.toJson(), 'gateRevision': legacyGate});
    if (legacy != null && legacy != current) map[legacy] = current;
  });
  return map;
}

/// [document] (a day document) with every group id in [ids] replaced:
/// the group shown, the runs' kept segments and their goals' group.
void remapDocumentGroupIds(Map<String, Object?> document, Map<String, String> ids) {
  if (ids.isEmpty) return;
  final event = document['event'];
  if (event is! Map<String, Object?>) return;
  final decisions = event['analysisDecisions'];
  if (decisions is Map<String, Object?>) {
    final shown = decisions['comparisonGroupId'];
    if (shown is String && ids.containsKey(shown)) decisions['comparisonGroupId'] = ids[shown];
  }
  final runs = event['runs'];
  if (runs is! List) return;
  for (final run in runs) {
    if (run is! Map<String, Object?>) continue;
    final segments = run['trackSegments'];
    if (segments is List) {
      for (final segment in segments) {
        if (segment is! Map<String, Object?>) continue;
        final reference = segment['trackConfigurationReference'];
        if (reference is String && ids.containsKey(reference)) {
          segment['trackConfigurationReference'] = ids[reference];
        }
      }
    }
    final review = run['trackSegmentReview'];
    if (review is Map<String, Object?>) {
      final reference = review['trackConfigurationReference'];
      if (reference is String && ids.containsKey(reference)) {
        review['trackConfigurationReference'] = ids[reference];
      }
    }
    final goals = run[runGoalsKey];
    if (goals is Map<String, Object?>) {
      final group = goals['groupId'];
      if (group is String && ids.containsKey(group)) goals['groupId'] = ids[group];
    }
  }
}
