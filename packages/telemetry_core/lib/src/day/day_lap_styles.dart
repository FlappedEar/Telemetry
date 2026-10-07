// The day's laps by driving style (FET-223): the ranked laps of the shown
// group, each compared corner by corner with the day's typical lap
// (lap_styles.dart), from what the corner analysis already measures.
//
// Where braking started is the braking technique's own reading of the
// longitudinal deceleration (braking_technique.dart): the recorded G, else
// the speed's slope, with its own unit rules; never the brake pedal, which an
// OBD recording updates only about twice a second. Its onset time is placed
// on the lap's shared axis to give metres before the corner's entry. A
// recording with neither a usable G nor a speed gives no braking point, and
// says so. Throttle pickup, minimum and exit speed are the corner analysis's
// own, in the units it read them in.
//
// Only the group's ranked laps are given here: out and in laps, laps the
// user excluded and laps with issues are not grouped.
import '../analysis/braking_technique.dart';
import '../analysis/lap_styles.dart';
import '../analysis/outing_theoretical_best.dart';
import '../analysis/track_progress.dart';
import '../operation.dart';
import '../speed_units.dart';
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
    List<String> brakeAssumedUnits = const [],
    List<String> speedAssumedUnits = const [],
    this.speedUnitMissing = false,
    this.brakeUnavailableReason = '',
  }) : inputs = List.unmodifiable(inputs),
       brakeAssumedUnits = List.unmodifiable(brakeAssumedUnits),
       speedAssumedUnits = List.unmodifiable(speedAssumedUnits);

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

  /// The units the braking points were read in without the recording
  /// declaring them: "g" for a longitudinal acceleration, the speed's
  /// assumed unit ("km/h" or "mph") for a deceleration from the speed. Empty
  /// when every unit was declared.
  final List<String> brakeAssumedUnits;

  /// The speed units the user's settings assumed for speeds the recording
  /// declares no unit for, as the corner speeds were read (the unit is
  /// shown as assumed, never as declared).
  final List<String> speedAssumedUnits;

  /// A speed channel has no unit at all (declared or assumed): speeds are
  /// shown without one.
  final bool speedUnitMissing;

  /// Why no braking point could be read (nothing measured), or empty.
  final String brakeUnavailableReason;

  bool get available => styles.available;

  /// Ranked laps that were grouped.
  int get groupedLapCount => styles.lapCount;

  /// The lap of [result].
  DayLapRow rowOf(LapStyleResult result) => result.lap as DayLapRow;
}

String _speedUnitOrKmh(BrakingTechniqueLap lap) =>
    lap.assumedUnit.isEmpty ? 'km/h' : lap.assumedUnit;

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
  var brakeFigures = 0, throttleFigures = 0;
  var speedUnitMissing = false;
  final brakeAssumed = <String>{}, speedAssumed = <String>{};
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
      BrakingTechniqueLap? technique;
      for (final (reference, lap) in corner.brakingTechnique.laps) {
        if (reference == row.reference) technique = lap;
      }
      final onset = technique?.onsetTime;
      if (technique != null && onset != null && trace != null && !crossesGate) {
        final progress = progressAtTime(trace, onset);
        if (progress != null) {
          brake = corner.startProgressMeters - progress;
          brakeSource = '${technique.source}|${technique.channel}';
          ++brakeFigures;
          if (technique.unitAssumed) {
            brakeAssumed.add(
              technique.source == brakingTechniqueFromSpeed ? _speedUnitOrKmh(technique) : 'g',
            );
          }
        }
      } else if (technique != null && technique.unavailableReason.isNotEmpty) {
        brakeReasons.add(technique.unavailableReason);
      }
      double? pickup;
      final progress = metrics.exit.pickup.progressMeters;
      if (progress != null && !crossesGate) {
        pickup = progress - corner.startProgressMeters;
        ++throttleFigures;
      }
      final speeds = metrics.speeds;
      final measuredSpeed = speeds.valid && speeds.provenance == 'measured';
      if (measuredSpeed) {
        final session = sessions[row.runId];
        final declared = session == null ? '' : fileDeclaredSpeedUnit(session, speeds.channel);
        if (speeds.unit.trim().isEmpty) {
          speedUnitMissing = true;
        } else if (declared.isEmpty) {
          speedAssumed.add(speeds.unit.trim());
        }
      }
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
    brakeAssumedUnits: brakeAssumed.toList()..sort(),
    speedAssumedUnits: speedAssumed.toList()..sort(),
    speedUnitMissing: speedUnitMissing,
    brakeUnavailableReason: brakeFigures == 0 && brakeReasons.isNotEmpty
        ? (brakeReasons.toList()..sort()).first
        : '',
  );
}
