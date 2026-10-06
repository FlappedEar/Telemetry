// A corner's time split into entry, middle and exit (FET-221) on synthetic
// loops: the parts are timed over the same metres on every lap and add up to
// the corner's time.
import 'package:fetproject/fetproject.dart';
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/synthetic_loop.dart';

// One tight 60-degree arc between two gentle ones: one tightest part.
List<LoopStep> _singleApexHalf() => [
  straight(100),
  arc(60, 50),
  arc(60, 12),
  arc(60, 50),
  straight(100),
];

// Two tight arcs joined by a gentle one.
List<LoopStep> _doubleApexHalf() => [
  straight(100),
  arc(45, 12),
  arc(90, 60),
  arc(45, 12),
  straight(100),
];

final _configuration = 'compatibility-v1:${'c' * 64}';

typedef _Corner = ({ProgressAxis axis, TrackFeatures features, Map<String, Object?> segment});

_Corner _firstCorner(List<LoopStep> half) {
  final axis = buildLoopAxis(half);
  final features = computeTrackFeatures(axis, segmentReviewSmoothingMeters);
  final proposal = proposeTrackSegments(
    axis,
    features,
  ).proposals.firstWhere((proposal) => proposal.type == TrackSegmentType.corner);
  return (
    axis: axis,
    features: features,
    segment: makeTrackSegment(
      TrackSegmentType.corner,
      proposal.name,
      proposal.start.progressMeters,
      proposal.end.progressMeters,
      _configuration,
    ),
  );
}

void main() {
  final corner = _firstCorner(_singleApexHalf());
  final split = cornerPhaseSplit(corner.axis, corner.features, corner.segment);

  List<ProgressSegment> drive(double Function(double) speed) {
    final lap = driveLap(_singleApexHalf(), speed);
    return projectLapTrace(corner.axis, lap.session, 0.0, lap.endTime);
  }

  test('splits at the start and end of the tightest part', () {
    expect(split.valid, isTrue, reason: split.unavailableReason);
    expect(split.startMeters, corner.segment['startProgressMeters']);
    expect(split.endMeters, corner.segment['endProgressMeters']);
    expect(split.startMeters, lessThan(split.entryEndMeters));
    expect(split.entryEndMeters, lessThan(split.midEndMeters));
    expect(split.midEndMeters, lessThan(split.endMeters));
    // The 12 m arc runs from 152 m to 165 m along the path.
    expect(split.entryEndMeters, closeTo(152, 12));
    expect(split.midEndMeters, closeTo(165, 12));
  });

  test('times each part, and the parts add up to the corner', () {
    final steady = cornerPhaseTimes(split, drive((_) => 20));
    expect(steady.valid, isTrue);
    expect(steady.entry, closeTo((split.entryEndMeters - split.startMeters) / 20, 0.02));
    expect(steady.mid, closeTo((split.midEndMeters - split.entryEndMeters) / 20, 0.02));
    expect(steady.exit, closeTo((split.endMeters - split.midEndMeters) / 20, 0.02));
    expect(steady.total, closeTo((split.endMeters - split.startMeters) / 20, 0.03));
    expect(steady.entry! + steady.mid! + steady.exit!, steady.total);
  });

  test('a lap slower only through the middle loses time only there', () {
    final best = cornerPhaseTimes(split, drive((_) => 20));
    // 15 m/s through the tightest part, 20 elsewhere.
    final slow = cornerPhaseTimes(
      split,
      drive((s) => s >= split.entryEndMeters && s <= split.midEndMeters ? 15 : 20),
    );
    final mid = split.midEndMeters - split.entryEndMeters;
    expect(slow.mid! - best.mid!, closeTo(mid / 15 - mid / 20, 0.05));
    expect((slow.entry! - best.entry!).abs(), lessThan(0.03));
    expect((slow.exit! - best.exit!).abs(), lessThan(0.03));
  });

  test('a corner that cannot be split says why', () {
    final double = _firstCorner(_doubleApexHalf());
    expect(
      cornerPhaseSplit(double.axis, double.features, double.segment).unavailableReason,
      cornerPhaseMultipleApexes,
    );
    final length = corner.axis.lengthMeters;
    final acrossGate = makeTrackSegment(
      TrackSegmentType.corner,
      'Corner 9',
      length - 20,
      15,
      _configuration,
    );
    final across = cornerPhaseSplit(corner.axis, corner.features, acrossGate);
    expect(across.unavailableReason, cornerPhaseCrossesGate);
    expect(cornerPhaseTimes(across, drive((_) => 20)).unavailableReason, cornerPhaseCrossesGate);
  });

  test('a gap inside one part is not bridged either', () {
    final lap = driveLap(
      _singleApexHalf(),
      (_) => 20,
      gpsGap: (split.startMeters + 3, split.entryEndMeters - 3),
    );
    expect(split.entryEndMeters - split.startMeters, greaterThan(10));
    final trace = projectLapTrace(corner.axis, lap.session, 0.0, lap.endTime);
    expect(cornerPhaseTimes(split, trace).unavailableReason, cornerPhaseTimesNotTimed);
  });

  test('times nobody measured are not valid', () {
    expect(const CornerPhaseTimes().valid, isFalse);
    expect(const CornerPhaseTimes().total, isNull);
    expect(const CornerPhaseTimes(unavailableReason: '').valid, isFalse);
  });

  test('a lap not covered through the corner is not timed (never bridged)', () {
    final lap = driveLap(
      _singleApexHalf(),
      (_) => 20,
      gpsGap: (split.entryEndMeters - 5, split.midEndMeters + 5),
    );
    final trace = projectLapTrace(corner.axis, lap.session, 0.0, lap.endTime);
    final times = cornerPhaseTimes(split, trace);
    expect(times.unavailableReason, cornerPhaseTimesNotTimed);
    expect(times.total, isNull);
  });
}
