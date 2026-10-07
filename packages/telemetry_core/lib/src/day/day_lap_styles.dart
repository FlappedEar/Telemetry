// The day's laps by driving style (FET-223): the ranked laps of the shown
// group, each compared corner by corner with the day's typical lap
// (lap_styles.dart), from what the corner analysis already measures.
//
// Where braking started is read from the longitudinal deceleration, never
// from the brake pedal: an OBD pedal updates about twice a second, so its
// onset is coarse, and the corner analysis may still use it for its own
// figures. The corner's braking is measured again here on the same laps with
// the pedal set aside ([computeBrakingMetrics] then falls back to the
// recorded longitudinal acceleration, as the braking source judges it). A
// recording without a usable longitudinal acceleration gives no braking
// point, and says so. Throttle pickup, minimum and exit speed are the corner
// analysis's own, in the units it read them in.
//
// Only the group's ranked laps are given here: out and in laps, laps the
// user excluded and laps with issues are not grouped.
import '../analysis/braking_metrics.dart';
import '../analysis/lap_styles.dart';
import '../analysis/outing_theoretical_best.dart';
import '../operation.dart';
import '../telemetry_session.dart';
import 'day_corners.dart';
import 'day_laps.dart';

/// The day's ranked laps with their styles.
final class DayLapStyles {
  DayLapStyles({
    required this.styles,
    List<LapStyleInput> inputs = const [],
    this.timedLapCount = 0,
    this.brakeCornerFigures = 0,
    this.throttleCornerFigures = 0,
    this.brakeUnitAssumed = false,
    this.speedUnitMissing = false,
    this.brakeUnavailableReason = '',
  }) : inputs = List.unmodifiable(inputs);

  final LapStyles styles;

  /// What each lap measured at each corner, before the typical was taken
  /// off (the figures the styles are worked out from).
  final List<LapStyleInput> inputs;

  /// The timed laps of the group, ranked or not: the ones not ranked are
  /// not grouped.
  final int timedLapCount;

  /// Corner-and-lap figures of braking point and of throttle pickup that
  /// the styles rest on (before the typicals' minimum of laps).
  final int brakeCornerFigures, throttleCornerFigures;

  /// The deceleration channel declares no unit and is read as g.
  final bool brakeUnitAssumed;

  /// A speed channel declares no unit (and none was assumed in settings):
  /// speeds are shown without one.
  final bool speedUnitMissing;

  /// Why no braking point could be read (nothing measured), or empty.
  final String brakeUnavailableReason;

  bool get available => styles.available;

  /// Ranked laps that were grouped.
  int get groupedLapCount => styles.lapCount;

  /// The lap of [result].
  DayLapRow rowOf(LapStyleResult result) => result.lap as DayLapRow;
}

TelemetrySession _withoutBrakePedal(TelemetrySession session) {
  if (!session.aliases.containsKey('brake')) return session;
  return TelemetrySession(
    duration: session.duration,
    startTime: session.startTime,
    metadata: session.metadata,
    channels: session.channels,
    aliases: {
      for (final MapEntry(:key, :value) in session.aliases.entries)
        if (key != 'brake') key: value,
    },
    warnings: session.warnings,
    timingGates: session.timingGates,
    sampleCount: session.sampleCount,
  );
}

/// The lap styles of [rows] (the group's ranked laps) at [corners] of
/// [computed]. [sessions] are the runs' recordings by run id.
/// [timedLapCount] is how many timed laps the group has, ranked or not.
DayLapStyles dayLapStyles(
  OutingTheoreticalBest computed,
  List<DayCorner> corners,
  List<DayLapRow> rows,
  Map<String, TelemetrySession> sessions, {
  int? timedLapCount,
  CancellationCheck? cancelled,
}) {
  final withoutPedal = <String, TelemetrySession>{};
  TelemetrySession? deceleration(String runId) {
    final session = sessions[runId];
    return session == null
        ? null
        : withoutPedal.putIfAbsent(runId, () => _withoutBrakePedal(session));
  }

  var brakeFigures = 0, throttleFigures = 0;
  var brakeUnitAssumed = false, speedUnitMissing = false;
  final brakeReasons = <String>{};
  final cornersOf = <DayLapReference, List<LapCornerSample>>{
    for (final row in rows) row.reference: [],
  };
  for (final corner in corners) {
    throwIfCancelled(cancelled);
    final crossesGate = corner.endProgressMeters < corner.startProgressMeters;
    for (final (row, metrics) in corner.laps) {
      final samples = cornersOf[row.reference];
      if (samples == null) continue;
      double? brake;
      var brakeSource = '';
      final trace = corner.traces[row.reference];
      final session = deceleration(row.runId);
      if (trace != null && session != null) {
        final braking = computeBrakingMetrics(
          computed.axisLengthMeters,
          computed.approved,
          corner.segmentId,
          trace,
          session,
          row.start,
          row.end,
        );
        if (braking.valid && braking.distanceBeforeEntryMeters != null) {
          brake = braking.distanceBeforeEntryMeters;
          brakeSource = '${braking.method}|${braking.channel}';
          ++brakeFigures;
          if (session.channels[braking.channel]?.unit.trim().isEmpty ?? false) {
            brakeUnitAssumed = true;
          }
        } else if (braking.unavailableReason.isNotEmpty) {
          brakeReasons.add(braking.unavailableReason);
        }
      }
      double? pickup;
      final progress = metrics.exit.pickup.progressMeters;
      if (progress != null && !crossesGate) {
        pickup = progress - corner.startProgressMeters;
        ++throttleFigures;
      }
      final speeds = metrics.speeds;
      final measuredSpeed = speeds.valid && speeds.provenance == 'measured';
      if (measuredSpeed && speeds.unit.trim().isEmpty) speedUnitMissing = true;
      samples.add(
        LapCornerSample(
          cornerId: corner.segmentId,
          brakeBeforeEntryMeters: brake,
          brakeSource: brakeSource,
          pickupAfterEntryMeters: pickup,
          pickupSource: '${metrics.exit.pickup.method}|${metrics.exit.pickup.channel}',
          minimumSpeed: measuredSpeed ? speeds.minimum.value : null,
          exitSpeed: measuredSpeed ? speeds.exit.value : null,
          speedUnit: speeds.unit,
          speedSource: speeds.channel,
        ),
      );
    }
  }
  final inputs = [
    for (final row in rows)
      LapStyleInput(lap: row, seconds: row.durationSeconds, corners: cornersOf[row.reference]!),
  ];
  final styles = computeLapStyles(inputs);
  return DayLapStyles(
    styles: styles,
    inputs: inputs,
    timedLapCount: timedLapCount ?? rows.length,
    brakeCornerFigures: brakeFigures,
    throttleCornerFigures: throttleFigures,
    brakeUnitAssumed: brakeUnitAssumed,
    speedUnitMissing: speedUnitMissing,
    brakeUnavailableReason: brakeFigures == 0 && brakeReasons.isNotEmpty
        ? (brakeReasons.toList()..sort()).first
        : '',
  );
}
