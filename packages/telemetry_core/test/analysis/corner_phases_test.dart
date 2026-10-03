// Corner entry/apex/exit and per-lap minimum speed (corner_phases.dart,
// corner_speeds.dart), ported from Overlays' CornerPhaseTests.cpp: geometric
// phases come from the shared axis; the minimum-speed location is measured
// per lap and is never conflated with the apex.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/synthetic_loop.dart';

// Tight 60-degree arc between two gentle ones: one short high-curvature region.
List<LoopStep> _singleApexHalf() => [
  straight(100),
  arc(60, 50),
  arc(60, 12),
  arc(60, 50),
  straight(100),
];

// Two tight 45-degree arcs joined by a long gentle one: two separate regions.
List<LoopStep> _doubleApexHalf() => [
  straight(100),
  arc(45, 12),
  arc(90, 60),
  arc(45, 12),
  straight(100),
];

typedef _Corner = ({ProgressAxis axis, TrackFeatures features, TrackSegmentProposal proposal});

_Corner _firstCorner(List<LoopStep> half) {
  final axis = buildLoopAxis(half);
  final features = computeTrackFeatures(axis, 6.0);
  final proposal = proposeTrackSegments(
    axis,
    features,
  ).proposals.firstWhere((proposal) => proposal.type == TrackSegmentType.corner);
  return (axis: axis, features: features, proposal: proposal);
}

// Minimum 12 m/s at path distance 185 m, 30 m/s elsewhere.
double _speedDipAt185(double s) => 30.0 - 18.0 * math.exp(-math.pow((s - 185.0) / 15.0, 2.0));

final _configuration = 'compatibility-v1:${'c' * 64}';

ApprovedSegmentation _approvedAs(
  TrackSegmentProposal proposal, [
  TrackSegmentType type = TrackSegmentType.corner,
]) => approvedSegmentation([
  makeTrackSegment(
    type,
    proposal.name,
    proposal.start.progressMeters,
    proposal.end.progressMeters,
    _configuration,
  ),
], _configuration);

String _onlyId(ApprovedSegmentation approved) => approved.segments.first['id']! as String;

TrackSegmentProposal _reshaped(
  TrackSegmentProposal proposal, {
  TrackSegmentType? type,
  double? start,
  double? end,
}) => TrackSegmentProposal(
  type: type ?? proposal.type,
  name: proposal.name,
  start: SegmentProposalBoundary(
    start ?? proposal.start.progressMeters,
    proposal.start.toleranceMeters,
  ),
  end: SegmentProposalBoundary(end ?? proposal.end.progressMeters, proposal.end.toleranceMeters),
  lengthMeters: proposal.lengthMeters,
  turnRadians: proposal.turnRadians,
  peakCurvaturePerMeter: proposal.peakCurvaturePerMeter,
);

TelemetrySession _withoutSpeed(TelemetrySession session) =>
    withChannels(session, aliases: {...session.aliases}..remove('speed'));

List<ProgressSegment> _trace(_Corner corner, DrivenLap lap) =>
    projectLapTrace(corner.axis, lap.session, 0.0, lap.endTime);

void main() {
  test('entry and exit reuse the corner boundaries', () {
    final corner = _firstCorner(_singleApexHalf());
    final phases = proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal);
    expect(phases.valid, isTrue);
    expect(phases.entry.method, cornerPhaseCurvatureOnset);
    expect(phases.entry.progressMeters, corner.proposal.start.progressMeters);
    expect(phases.entry.toleranceMeters, corner.proposal.start.toleranceMeters);
    expect(phases.exit.method, cornerPhaseCurvatureRelease);
    expect(phases.exit.progressMeters, corner.proposal.end.progressMeters);
    expect(phases.entry.resolved, isTrue);
    expect(phases.exit.resolved, isTrue);
    expect(phases.entry.evidence['source'], trackSegmentProposalAlgorithm);
  });

  test('a single apex sits in the high-curvature region', () {
    final corner = _firstCorner(_singleApexHalf());
    final phases = proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal);
    expect(phases.valid, isTrue);
    expect(phases.apex.resolved, isTrue);
    expect(phases.apex.method, cornerPhasePeakCurvature);
    expect(phases.apex.uncertaintyReasons, isEmpty);
    expect(phases.apexCandidatesMeters, hasLength(1));
    // The tight arc spans path distance ~152.4..165.0 m; its centre is ~158.7 m.
    expect(
      (phases.apex.progressMeters - 158.7).abs(),
      lessThanOrEqualTo(phases.apex.toleranceMeters),
    );
    expect(phases.apex.evidence['peakCurvaturePerMeter']! as double, greaterThan(1.0 / 20.0));
  });

  test('multiple apexes are left unresolved', () {
    final corner = _firstCorner(_doubleApexHalf());
    final phases = proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal);
    expect(phases.valid, isTrue);
    expect(phases.apex.unresolvedReason, cornerPhaseMultipleApexes);
    expect(phases.apex.resolved, isFalse);
    expect(phases.apexCandidatesMeters, hasLength(2));
    // Tight arcs centred at path distance ~104.7 m and ~208.4 m.
    expect((phases.apexCandidatesMeters[0] - 104.7).abs(), lessThan(8.0));
    expect((phases.apexCandidatesMeters[1] - 208.4).abs(), lessThan(8.0));
    expect(phases.apex.evidence['candidatesMeters'], hasLength(2));
    expect(phases.entry.resolved, isTrue);
    expect(phases.exit.resolved, isTrue);
  });

  test('a broad constant-radius apex is widened', () {
    final corner = _firstCorner(stadium());
    final phases = proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal);
    expect(phases.valid, isTrue);
    expect(phases.apex.resolved, isTrue);
    expect(phases.apex.uncertaintyReasons, contains(cornerPhaseBroadPeak));
    // A 125.7 m semicircle from 100 m: its middle is ~162.8 m.
    expect((phases.apex.progressMeters - 162.8).abs(), lessThan(6.0));
    expect(phases.apex.toleranceMeters, greaterThan(40.0));
  });

  test('the minimum speed is located separately from the apex', () {
    final corner = _firstCorner(_singleApexHalf());
    final lap = driveLap(_singleApexHalf(), _speedDipAt185);
    final trace = _trace(corner, lap);
    expect(trace, isNotEmpty);
    final minimum = locateMinimumSpeed(corner.axis, corner.proposal, trace, lap.session, 1.0);
    expect(minimum.resolved, isTrue, reason: minimum.unresolvedReason);
    expect(minimum.method, cornerPhaseMinimumSpeed);
    expect(
      (minimum.progressMeters - 185.0).abs(),
      lessThanOrEqualTo(minimum.toleranceMeters + 2.0),
    );
    expect(minimum.toleranceMeters, lessThan(10.0));
    expect(minimum.uncertaintyReasons, isEmpty);
    expect(minimum.evidence['channel'], 'velocity');
    expect(minimum.evidence['unit'], 'km/h');
    expect(((minimum.evidence['minimumValue']! as double) - 12.0 * 3.6).abs(), lessThan(1.0));

    final phases = proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal);
    expect(phases.apex.resolved, isTrue);
    expect(
      (phases.apex.progressMeters - minimum.progressMeters).abs(),
      greaterThan(20.0),
      reason: 'the apex is geometry; the minimum-speed point is where this lap was slowest',
    );
  });

  test('the minimum speed is unresolved on incomplete data', () {
    final corner = _firstCorner(_singleApexHalf());

    final gpsGapLap = driveLap(_singleApexHalf(), _speedDipAt185, gpsGap: (170.0, 200.0));
    final gpsGap = locateMinimumSpeed(
      corner.axis,
      corner.proposal,
      _trace(corner, gpsGapLap),
      gpsGapLap.session,
      1.0,
    );
    expect(gpsGap.unresolvedReason, cornerPhaseIncompleteCoverage);
    expect(gpsGap.evidence['missingSamples']! as int, greaterThan(0));

    final speedGapLap = driveLap(_singleApexHalf(), _speedDipAt185, speedGap: (175.0, 195.0));
    expect(
      locateMinimumSpeed(
        corner.axis,
        corner.proposal,
        _trace(corner, speedGapLap),
        speedGapLap.session,
        1.0,
      ).unresolvedReason,
      cornerPhaseIncompleteCoverage,
    );

    final normal = driveLap(_singleApexHalf(), _speedDipAt185);
    expect(
      locateMinimumSpeed(
        corner.axis,
        corner.proposal,
        _trace(corner, normal),
        _withoutSpeed(normal.session),
        1.0,
      ).unresolvedReason,
      cornerPhaseSpeedChannelMissing,
    );

    final flatLap = driveLap(_singleApexHalf(), (_) => 25.0);
    expect(
      locateMinimumSpeed(
        corner.axis,
        corner.proposal,
        _trace(corner, flatLap),
        flatLap.session,
        1.0,
      ).unresolvedReason,
      cornerPhaseFlatSpeed,
    );

    final wrapping = _reshaped(corner.proposal, start: corner.axis.lengthMeters - 30.0, end: 30.0);
    expect(
      locateMinimumSpeed(
        corner.axis,
        wrapping,
        _trace(corner, normal),
        normal.session,
        1.0,
      ).unresolvedReason,
      cornerPhaseCrossesGate,
    );
  });

  test('invalid inputs are rejected', () {
    final corner = _firstCorner(_singleApexHalf());
    expect(
      proposeCornerGeometryPhases(corner.axis, corner.features, corner.proposal).valid,
      isTrue,
    );
    expect(
      proposeCornerGeometryPhases(const ProgressAxis(), corner.features, corner.proposal).valid,
      isFalse,
    );
    expect(
      proposeCornerGeometryPhases(corner.axis, const TrackFeatures(), corner.proposal).valid,
      isFalse,
    );

    final straightProposal = _reshaped(corner.proposal, type: TrackSegmentType.straight);
    expect(
      proposeCornerGeometryPhases(corner.axis, corner.features, straightProposal).valid,
      isFalse,
    );
    final outOfAxis = _reshaped(corner.proposal, end: corner.axis.lengthMeters + 1.0);
    expect(proposeCornerGeometryPhases(corner.axis, corner.features, outOfAxis).valid, isFalse);

    expect(
      proposeCornerGeometryPhases(
        corner.axis,
        corner.features,
        corner.proposal,
        const CornerPhaseOptions(apexSeparationRatio: 0.8),
      ).valid,
      isFalse,
    );
    expect(
      proposeCornerGeometryPhases(
        corner.axis,
        corner.features,
        corner.proposal,
        const CornerPhaseOptions(flatSpeedFraction: double.nan),
      ).valid,
      isFalse,
    );

    final lap = driveLap(_singleApexHalf(), _speedDipAt185);
    final trace = _trace(corner, lap);
    for (final (proposal, step) in [
      (corner.proposal, 0.0),
      (corner.proposal, 1e-6),
      (straightProposal, 1.0),
    ]) {
      expect(
        locateMinimumSpeed(corner.axis, proposal, trace, lap.session, step).unresolvedReason,
        cornerPhaseInvalidInput,
      );
    }
  });

  test('entry, apex, minimum and exit speeds are reported separately', () {
    // The apex speed is read at the geometric apex, the minimum where this
    // lap was slowest, ~28 m later.
    final corner = _firstCorner(_singleApexHalf());
    final approved = _approvedAs(corner.proposal);
    final lap = driveLap(_singleApexHalf(), _speedDipAt185);
    final speeds = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      _onlyId(approved),
      _trace(corner, lap),
      lap.session,
    );
    expect(speeds.valid, isTrue);
    expect(speeds.provenance, 'measured');
    expect(speeds.channel, 'velocity');
    expect(speeds.unit, 'km/h');
    expect(speeds.stamp.calculationAlgorithm, cornerSpeedsAlgorithm);
    expect(segmentationResultCurrent(speeds.stamp, approved, cornerSpeedsAlgorithm), isTrue);
    for (final value in [speeds.entry, speeds.apex, speeds.minimum, speeds.exit]) {
      expect(value.value, isNotNull, reason: value.unavailableReason);
      expect(value.telemetryTime, isNotNull);
      expect(value.limitations, isEmpty);
    }
    expect(speeds.entry.progressMeters, corner.proposal.start.progressMeters);
    expect(speeds.exit.progressMeters, corner.proposal.end.progressMeters);
    expect(speeds.entry.value, greaterThan(100.0));
    expect(speeds.exit.value, greaterThan(100.0));
    expect((speeds.minimum.value! - 12.0 * 3.6).abs(), lessThan(1.0));
    expect((speeds.minimum.progressMeters - 185.0).abs(), lessThan(5.0));
    expect((speeds.apex.progressMeters - speeds.minimum.progressMeters).abs(), greaterThan(20.0));
    expect(speeds.apex.value! - speeds.minimum.value!, greaterThan(50.0));
    expect((speeds.coveredMeters - speeds.lengthMeters).abs(), lessThan(1e-6));
    expect(
      speeds.meanSampleSpacingMeters,
      inExclusiveRange(0.0, sparseSampleSpacingMeters + 1e-12),
    );
  });

  test('corner speeds are limited or withheld on poor data', () {
    final corner = _firstCorner(_singleApexHalf());
    final approved = _approvedAs(corner.proposal);
    final id = _onlyId(approved);

    // A GPS gap inside the corner: no minimum, boundary speeds outside it remain.
    final gapped = driveLap(_singleApexHalf(), _speedDipAt185, gpsGap: (170.0, 200.0));
    final withGap = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      id,
      _trace(corner, gapped),
      gapped.session,
    );
    expect(withGap.minimum.value, isNull);
    expect(withGap.minimum.unavailableReason, cornerPhaseIncompleteCoverage);
    expect(withGap.entry.value != null && withGap.exit.value != null, isTrue);
    expect(withGap.coveredMeters, lessThan(withGap.lengthMeters - 20.0));

    // Sparse speed samples: values are kept but explicitly limited.
    final lap = driveLap(_singleApexHalf(), _speedDipAt185);
    final velocity = lap.session.channels['velocity']!;
    final thinned = TelemetryChannel(
      name: velocity.name,
      unit: velocity.unit,
      timestamps: Float64List.fromList([
        for (var i = 0; i < velocity.timestamps.length; i += 40) velocity.timestamps[i],
      ]),
      values: Float32List.fromList([
        for (var i = 0; i < velocity.values.length; i += 40) velocity.values[i],
      ]),
    );
    final sparse = withChannels(
      lap.session,
      channels: {...lap.session.channels, 'velocity': thinned},
    );
    final limited = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      id,
      projectLapTrace(corner.axis, sparse, 0.0, lap.endTime),
      sparse,
    );
    expect(limited.meanSampleSpacingMeters, greaterThan(sparseSampleSpacingMeters));
    expect(limited.entry.value, isNotNull);
    expect(limited.entry.limitations, contains(cornerSpeedSparseSamples));
    expect(limited.exit.limitations, contains(cornerSpeedSparseSamples));

    // No speed channel: nothing is derived from GPS positions instead.
    final missing = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      id,
      _trace(corner, lap),
      _withoutSpeed(lap.session),
    );
    expect(missing.valid, isTrue);
    expect(missing.provenance, 'unavailable');
    for (final value in [missing.entry, missing.apex, missing.minimum, missing.exit]) {
      expect(value.value, isNull);
      expect(value.unavailableReason, cornerPhaseSpeedChannelMissing);
    }
  });

  test('corner speeds handle other segment shapes', () {
    // Two separate apexes: no apex speed, the minimum is still measured.
    final doubleCorner = _firstCorner(_doubleApexHalf());
    final doubleApproved = _approvedAs(doubleCorner.proposal);
    final doubleLap = driveLap(_doubleApexHalf(), _speedDipAt185);
    final twoApexes = computeCornerSpeeds(
      doubleCorner.axis,
      doubleCorner.features,
      doubleApproved,
      _onlyId(doubleApproved),
      _trace(doubleCorner, doubleLap),
      doubleLap.session,
    );
    expect(twoApexes.apex.value, isNull);
    expect(twoApexes.apex.unavailableReason, cornerPhaseMultipleApexes);
    expect(twoApexes.minimum.value, isNotNull);

    final corner = _firstCorner(_singleApexHalf());
    final lap = driveLap(_singleApexHalf(), _speedDipAt185);
    final trace = _trace(corner, lap);

    // A straight has no apex, but its minimum speed is still measured.
    final straightApproved = _approvedAs(corner.proposal, TrackSegmentType.straight);
    final straightSpeeds = computeCornerSpeeds(
      corner.axis,
      corner.features,
      straightApproved,
      _onlyId(straightApproved),
      trace,
      lap.session,
    );
    expect(straightSpeeds.apex.unavailableReason, cornerSpeedNotACorner);
    expect(straightSpeeds.minimum.value, isNotNull);

    // A segment across the gate cannot be measured within one lap.
    final wrapped = _approvedAs(
      _reshaped(corner.proposal, start: corner.axis.lengthMeters - 30.0, end: 30.0),
    );
    final acrossGate = computeCornerSpeeds(
      corner.axis,
      corner.features,
      wrapped,
      _onlyId(wrapped),
      trace,
      lap.session,
    );
    expect(acrossGate.valid, isTrue);
    for (final value in [acrossGate.entry, acrossGate.apex, acrossGate.minimum, acrossGate.exit]) {
      expect(value.unavailableReason, cornerPhaseCrossesGate);
    }

    final approved = _approvedAs(corner.proposal);
    expect(
      computeCornerSpeeds(
        corner.axis,
        corner.features,
        approved,
        'missing',
        trace,
        lap.session,
      ).valid,
      isFalse,
    );
    expect(
      computeCornerSpeeds(
        const ProgressAxis(),
        corner.features,
        approved,
        'x',
        trace,
        lap.session,
      ).valid,
      isFalse,
    );
  });

  test('corner speeds of two laps are compared A minus B', () {
    // Lap B is driven 10% slower everywhere, so every delta is predictable.
    final corner = _firstCorner(_singleApexHalf());
    final approved = _approvedAs(corner.proposal);
    final id = _onlyId(approved);
    final lapA = driveLap(_singleApexHalf(), _speedDipAt185);
    final lapB = driveLap(_singleApexHalf(), (s) => _speedDipAt185(s) * 0.9);
    final traceB = _trace(corner, lapB);
    final speedsA = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      id,
      _trace(corner, lapA),
      lapA.session,
    );
    final speedsB = computeCornerSpeeds(
      corner.axis,
      corner.features,
      approved,
      id,
      traceB,
      lapB.session,
    );
    expect(speedsA.valid && speedsB.valid, isTrue);

    final comparison = compareCornerSpeeds(speedsA, speedsB);
    expect(comparison.valid, isTrue);
    expect(comparison.unavailableReason, isEmpty);
    expect((comparison.entryDelta! - 0.1 * speedsA.entry.value!).abs(), lessThan(0.5));
    expect(comparison.apexDelta, greaterThan(0.0)); // A was faster everywhere
    expect(comparison.minimumDelta, greaterThan(0.0));
    expect(comparison.exitDelta, greaterThan(0.0));

    // A different segment (even with identical bounds) is never compared.
    final other = approvedSegmentation([
      makeTrackSegment(
        TrackSegmentType.corner,
        'Other',
        corner.proposal.start.progressMeters,
        corner.proposal.end.progressMeters,
        _configuration,
      ),
    ], _configuration);
    final speedsOther = computeCornerSpeeds(
      corner.axis,
      corner.features,
      other,
      _onlyId(other),
      traceB,
      lapB.session,
    );
    expect(speedsOther.valid, isTrue);
    final differentRevision = compareCornerSpeeds(speedsA, speedsOther);
    expect(differentRevision.valid, isFalse);
    expect(differentRevision.unavailableReason, cornerSpeedDifferentSegmentOrRevision);

    // An invalid input on either side withholds the whole comparison.
    expect(compareCornerSpeeds(CornerSpeeds(), speedsB).valid, isFalse);
  });
}
