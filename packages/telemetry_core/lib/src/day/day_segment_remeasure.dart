// Measuring a day's automatic segments again on its best lap (FET-170).
//
// When sessions are added one at a time, the day keeps the corners in use
// (DaySegmentEdits.keepAutomatic), measured on the best lap of the time. A
// later, faster lap can then be one the kept corners cannot time: its
// projection onto the older lap's line loses lock, so some of its sectors
// have no time and the theoretical best comes out slower than the best lap
// (on the real Jastrząb day 1:50.116 against 1:49.898, where importing the
// whole day gives 1:47.905). The owner chose (2026-10-05) to measure the
// corners again on the new best lap in that case, keeping the names given to
// them. Corners whose bounds the driver moved, split or merged are the
// driver's own and stay as they are.
import 'dart:math' as math;

import 'package:fetproject/fetproject.dart' show trackSegmentTypeName;

import '../analysis/automatic_segments.dart';
import '../analysis/outing_theoretical_best.dart';
import '../operation.dart';
import 'day_analysis.dart';
import 'day_laps.dart';
import 'day_theoretical_best.dart';

Map<String, Object?>? _object(Object? value) => value is Map<String, Object?> ? value : null;

List<Map<String, Object?>> _segmentsOf(Object? value) => [
  if (value is List)
    for (final item in value)
      if (item is Map<String, Object?>) item,
];

double _number(Object? value) => value is num ? value.toDouble() : double.nan;

/// Whether the best lap of [result] has a segment without a time.
bool bestLapHasUntimedSegment(DayTheoreticalBest result) {
  for (final lap in result.laps) {
    if (lap.bestOfDay) return lap.times.sectors.any((sector) => sector.seconds == null);
  }
  return false;
}

/// The segments of [result]'s group measured again on the day's best lap,
/// when the approved ones cannot time it (a segment of the best lap has no
/// time) and they are still the automatic proposals of the lap they were
/// measured on, renamed or not. Names the driver gave are carried to the new
/// segment that covers the same part of the lap. Returns the result for the
/// new segments with [DayTheoreticalBest.remeasuredRuns] set, or null when
/// nothing is measured again: the best lap is timed, the segments were
/// edited, or the new ones do not time the best lap either.
DayTheoreticalBest? remeasureDaySegments(
  DayAnalysis analysis,
  Map<String, OutingRun> runs,
  DayTheoreticalBest result, {
  required Iterable<Object?> documentRuns,
  math.Random? random,
  CancellationCheck? cancelled,
}) {
  if (result.state != DayTheoreticalBestState.ready ||
      result.automaticSegments ||
      result.segmentRunId.isEmpty ||
      !(result.axisLengthMeters > 0) ||
      !bestLapHasUntimedSegment(result)) {
    return null;
  }
  final groupId = result.groupId;
  final group = [
    for (final candidate in analysis.groups)
      if (candidate.id == groupId && candidate.resolved) candidate,
  ].firstOrNull;
  final ranking = group?.ranking;
  final best = ranking?.bestOfDay;
  if (ranking == null || best == null || best.runId == result.segmentRunId) return null;

  // The lap the segments were measured on: the fastest of their run.
  DayLapRow? source;
  for (final row in ranking.eligibleLaps) {
    if (row.runId != result.segmentRunId) continue;
    if (source == null || row.durationSeconds < source.durationSeconds) source = row;
  }
  final sourceRun = runs[result.segmentRunId];
  if (source == null || sourceRun == null) return null;
  final review = computeSegmentReview(
    sourceRun.session,
    sourceRun.laps,
    lapNumber: source.lapNumber,
    startTime: source.start,
    endTime: source.end,
    cancelled: cancelled,
  );
  if (review.error.isNotEmpty || review.unavailable.isNotEmpty) return null;
  final proposals = review.proposals.proposals;
  final approved = [
    for (final segment in result.runSegments)
      if (segment['trackConfigurationReference'] == groupId) segment,
  ];
  if (proposals.isEmpty || proposals.length != approved.length) return null;
  final byStart = [
    ...approved,
  ]..sort((a, b) => _number(a['startProgressMeters']).compareTo(_number(b['startProgressMeters'])));
  final proposed = [...proposals]
    ..sort((a, b) => a.start.progressMeters.compareTo(b.start.progressMeters));
  const tolerance = 0.5;
  final named = <({String type, double start, double end, String name})>[];
  for (var i = 0; i < byStart.length; ++i) {
    final segment = byStart[i];
    final proposal = proposed[i];
    final type = segment['type'];
    final start = _number(segment['startProgressMeters']);
    final end = _number(segment['endProgressMeters']);
    if (type != trackSegmentTypeName(proposal.type) ||
        !((start - proposal.start.progressMeters).abs() <= tolerance) ||
        !((end - proposal.end.progressMeters).abs() <= tolerance)) {
      return null; // moved, split or merged by the driver
    }
    final name = segment['name'];
    if (name is String && name != proposal.name) {
      final length = result.axisLengthMeters;
      named.add((type: type! as String, start: start / length, end: end / length, name: name));
    }
  }

  // Without the group's segments the best lap's proposals are approved.
  final changed = <String, List<Map<String, Object?>>>{};
  final withoutGroup = [
    for (final value in documentRuns)
      if (_object(value) case final run? when run['id'] is String)
        () {
          final stored = _segmentsOf(run['trackSegments']);
          final kept = [
            for (final segment in stored)
              if (segment['trackConfigurationReference'] != groupId) segment,
          ];
          if (kept.length == stored.length) return run;
          changed[run['id']! as String] = kept;
          return {...run, 'trackSegments': kept};
        }()
      else
        value,
  ];
  var next = dayTheoreticalBest(
    analysis,
    runs,
    documentRuns: withoutGroup,
    groupId: groupId,
    random: random,
    cancelled: cancelled,
  );
  if (next.state != DayTheoreticalBestState.ready ||
      !next.automaticSegments ||
      next.segmentRunId.isEmpty ||
      bestLapHasUntimedSegment(next)) {
    return null;
  }
  var segments = [
    for (final segment in next.runSegments) {...segment},
  ];
  if (named.isNotEmpty) {
    segments = _withNames(segments, groupId, next.axisLengthMeters, named);
    final renamed = [
      for (final value in withoutGroup)
        if (_object(value) case final run? when run['id'] == next.segmentRunId)
          {...run, 'trackSegments': segments}
        else
          value,
      if (!withoutGroup.any((value) => _object(value)?['id'] == next.segmentRunId))
        {'id': next.segmentRunId, 'trackSegments': segments},
    ];
    next = dayTheoreticalBest(
      analysis,
      runs,
      documentRuns: renamed,
      groupId: groupId,
      random: random,
      cancelled: cancelled,
    );
    if (next.state != DayTheoreticalBestState.ready || bestLapHasUntimedSegment(next)) {
      return null;
    }
  }
  changed[next.segmentRunId] = segments;
  return next.withRemeasuredRuns(changed);
}

/// [segments] with each of [named]'s names on the segment of the same type
/// that overlaps it most, as fractions of the lap; each name is used once.
List<Map<String, Object?>> _withNames(
  List<Map<String, Object?>> segments,
  String groupId,
  double length,
  List<({String type, double start, double end, String name})> named,
) {
  (double, double) span(double start, double end) => (start, end < start ? end + 1.0 : end);
  double overlap((double, double) a, (double, double) b) {
    var best = 0.0;
    for (final shift in const [-1.0, 0.0, 1.0]) {
      final value = math.min(a.$2, b.$2 + shift) - math.max(a.$1, b.$1 + shift);
      if (value > best) best = value;
    }
    return best;
  }

  final result = [
    for (final segment in segments) {...segment},
  ];
  final taken = <int>{};
  for (final old in named) {
    final from = span(old.start, old.end);
    var choice = -1;
    var most = 0.0;
    for (var i = 0; i < result.length; ++i) {
      final segment = result[i];
      if (taken.contains(i) ||
          segment['trackConfigurationReference'] != groupId ||
          segment['type'] != old.type) {
        continue;
      }
      final to = span(
        _number(segment['startProgressMeters']) / length,
        _number(segment['endProgressMeters']) / length,
      );
      final shared = overlap(from, to);
      // At least half of the shorter of the two.
      if (shared > most && shared >= 0.5 * math.min(from.$2 - from.$1, to.$2 - to.$1)) {
        most = shared;
        choice = i;
      }
    }
    if (choice >= 0) {
      taken.add(choice);
      result[choice]['name'] = old.name;
    }
  }
  return result;
}
