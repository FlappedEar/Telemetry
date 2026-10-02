// Port of the compatibility part of VBOOverlay
// native/src/telemetry/OutingLaps.{h,cpp} (FET-21): which laps of a day may be
// compared, and why a lap may not.
import 'package:fetproject/fetproject.dart' as fet;

import '../laps/lap_session.dart';

/// The way round the circuit.
enum TrackDirection {
  clockwise('Clockwise'),
  counterclockwise('Counterclockwise');

  const TrackDirection(this.label);

  final String label;
}

/// A run's circuit: its layout, direction and timing-gate revision. Laps are
/// compared only when all three are known and equal.
final class TrackConfiguration {
  const TrackConfiguration({this.layoutId, this.direction, this.gateRevision});

  /// A layout name the user chose, or a detected `gps-route-v1:` route.
  final String? layoutId;
  final TrackDirection? direction;

  /// The `gates-v1:` revision of the recording's timing gates.
  final String? gateRevision;

  /// Whether [layoutId] is a route detected from GPS rather than a name.
  bool get detectedRoute => layoutId?.startsWith('gps-route-v1:') ?? false;

  /// The configuration as the shared document stores it.
  Map<String, Object?> toJson() => {
    'layoutId': layoutId,
    'direction': direction?.name ?? 'unknown',
    'gateRevision': gateRevision,
  };

  /// The `compatibility-v1` group, or null when anything is unresolved.
  /// Unknown values never form a group, even when two runs share them.
  String? get compatibilityGroupId => fet.compatibilityV1Id(toJson());

  TrackConfiguration copyWith({String? layoutId, TrackDirection? direction}) => TrackConfiguration(
    layoutId: layoutId ?? this.layoutId,
    direction: direction ?? this.direction,
    gateRevision: gateRevision,
  );

  @override
  bool operator ==(Object other) =>
      other is TrackConfiguration &&
      other.layoutId == layoutId &&
      other.direction == direction &&
      other.gateRevision == gateRevision;

  @override
  int get hashCode => Object.hash(layoutId, direction, gateRevision);
}

/// Why a lap cannot be compared or ranked.
enum LapIssue {
  layoutUnresolved('layout-unresolved', 'Layout needs confirmation'),
  directionUnresolved('direction-unresolved', 'Direction needs confirmation'),
  timingGateUnresolved('timing-gate-unresolved', 'Timing gates unresolved'),
  changedLayout('changed-layout', 'Different layout'),
  oppositeDirection('opposite-direction', 'Opposite direction'),
  changedTimingGate('changed-timing-gate', 'Different timing gates'),
  incompleteGps('incomplete-gps', 'Incomplete GPS'),
  invalidGps('invalid-gps', 'Invalid GPS'),
  userExclusion('user-exclusion', 'User exclusion'),
  notTimedLap('not-timed-lap', 'Not a complete timed lap'),
  staleSource('stale-source', 'Source changed; reload recording'),
  ineligibleLap('ineligible-lap', 'Lap is not eligible'),
  differentRecordedRoute(
    'different-recorded-route',
    'Lap leaves the route the other laps took (off track, a detour or the pit lane)',
  );

  const LapIssue(this.code, this.label);

  /// The stable code Overlays uses.
  final String code;
  final String label;
}

bool _knownLayout(TrackConfiguration configuration) {
  final value = configuration.layoutId;
  return value != null &&
      value.trim().isNotEmpty &&
      value.length <= 128 &&
      !value.contains('\u0000');
}

final _gatesPattern = RegExp(r'^gates-v1:[0-9a-f]{64}$');

bool _knownGates(TrackConfiguration configuration) =>
    _gatesPattern.hasMatch(configuration.gateRevision ?? '');

/// Why a lap of a run with [configuration] cannot be compared with laps of a
/// run with [reference] (or at all, without one). Empty when it can.
List<LapIssue> lapCompatibilityIssues(
  TrackConfiguration configuration, {
  TrackConfiguration? reference,
  LapReferenceIssue issue = LapReferenceIssue.none,
  bool userExcluded = false,
}) {
  final issues = <LapIssue>[];
  if (!_knownLayout(configuration) || (reference != null && !_knownLayout(reference))) {
    issues.add(LapIssue.layoutUnresolved);
  }
  if (configuration.direction == null || (reference != null && reference.direction == null)) {
    issues.add(LapIssue.directionUnresolved);
  }
  if (!_knownGates(configuration) || (reference != null && !_knownGates(reference))) {
    issues.add(LapIssue.timingGateUnresolved);
  }
  if (reference != null) {
    if (_knownLayout(configuration) &&
        _knownLayout(reference) &&
        configuration.layoutId != reference.layoutId) {
      issues.add(LapIssue.changedLayout);
    }
    if (configuration.direction != null &&
        reference.direction != null &&
        configuration.direction != reference.direction) {
      issues.add(LapIssue.oppositeDirection);
    }
    if (_knownGates(configuration) &&
        _knownGates(reference) &&
        configuration.gateRevision != reference.gateRevision) {
      issues.add(LapIssue.changedTimingGate);
    }
  }
  if (issue == LapReferenceIssue.gpsGap) issues.add(LapIssue.incompleteGps);
  if (issue == LapReferenceIssue.invalidGps) issues.add(LapIssue.invalidGps);
  if (userExcluded) issues.add(LapIssue.userExclusion);
  return issues;
}
