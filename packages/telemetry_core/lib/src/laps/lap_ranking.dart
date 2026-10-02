import 'lap_session.dart';

/// Indices of the laps that ranking, statistics and references may use.
List<int> eligibleLapIndices(List<TimedLap> laps) => [
  for (var index = 0; index < laps.length; ++index)
    if (laps[index].referenceEligible) index,
];

/// Finds the fastest eligible lap (the first on a tie) and sets every eligible
/// lap's delta to it. Ineligible laps keep a delta of 0.
(List<TimedLap>, int?) rankLaps(List<TimedLap> laps) {
  int? fastest;
  for (final index in eligibleLapIndices(laps)) {
    if (fastest == null || laps[index].durationSeconds < laps[fastest].durationSeconds) {
      fastest = index;
    }
  }
  if (fastest == null) {
    return ([for (final lap in laps) lap.copyWith(deltaToBestSeconds: 0.0)], null);
  }
  final best = laps[fastest].durationSeconds;
  return (
    [
      for (final lap in laps)
        lap.copyWith(deltaToBestSeconds: lap.referenceEligible ? lap.durationSeconds - best : 0.0),
    ],
    fastest,
  );
}

/// [session] with its ranking recomputed, for example after a user exclusion.
LapSession recomputeLapRanking(LapSession session) {
  final (laps, fastest) = rankLaps(session.timedLaps);
  return session.withTimedLaps(laps, fastest);
}
