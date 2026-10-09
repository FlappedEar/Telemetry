// The day's corner-phase reference (FET-226): the group's ranked laps timed
// through every corner's entry, middle and exit (FET-221) and every other
// segment whole, on the theoretical best's shared axis, with each lap's
// speed where each piece starts and ends for the joins. Worked out in the
// theoretical best's background job, from the same laps.
import '../analysis/corner_phase_times.dart';
import '../analysis/corner_phases.dart' show cornerPhaseInvalidInput;
import '../analysis/outing_theoretical_best.dart';
import '../analysis/phase_reference.dart';
import '../analysis/realistic_theoretical_best.dart';
import '../analysis/sector_timing.dart';
import '../analysis/track_progress.dart';
import '../operation.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'day_corners.dart';
import 'day_laps.dart';

/// The best phases of [computed]'s laps (the group's ranked laps, timed on
/// the approved segments), with [corners] split as FET-221 splits them and
/// [sessions] (by run id) giving each lap's speed. A corner is taken whole
/// when it is not split, or when no lap is timed through its parts.
PhaseReference dayPhaseReference(
  OutingTheoreticalBest computed,
  List<DayCorner> corners,
  Map<String, TelemetrySession> sessions, {
  CancellationCheck? cancelled,
}) {
  final approved = computed.approved;
  final segments = approved.segments;
  final population = <int>[
    for (var k = 0; k < computed.population.length; ++k)
      if (computed.population[k].times case final times
          when times.valid &&
              times.stamp.revision == approved.revision &&
              times.stamp.trackConfigurationReference == approved.trackConfigurationReference)
        k,
  ];
  DayCorner? cornerAt(int index) {
    for (final corner in corners) {
      if (corner.segmentIndex == index) return corner;
    }
    return null;
  }

  // Each lap's phase times through each split corner, by segment index.
  final phases = <int, List<CornerPhaseTimes>>{};
  final pieces = <PhasePiece>[];
  for (var index = 0; index < segments.length; ++index) {
    final segment = segments[index];
    final id = segment['id'] is String ? segment['id'] as String : '';
    final corner = cornerAt(index);
    final name = corner?.name ?? (segment['name'] is String ? segment['name'] as String : id);
    final isCorner = corner != null || segment['type'] == 'corner';
    if (corner != null && corner.phaseSplit.valid) {
      final times = [
        for (final k in population)
          corner.phaseTimes(computed.population[k].times.lapReference as DayLapReference),
      ];
      // Split only when every lap timed through the whole corner is timed
      // through its parts too: a lap left out of the parts could be the
      // fastest through the corner, and the parts then would not be a finer
      // grain of the theoretical best.
      var every = true;
      for (final (position, k) in population.indexed) {
        final timed = computed.population[k].times.sectors
            .where((sector) => sector.segmentId == id)
            .any((sector) => sector.seconds != null);
        if (timed && !times[position].valid) every = false;
      }
      if (every && times.any((time) => time.valid)) {
        phases[index] = times;
        for (final part in [PhasePart.entry, PhasePart.middle, PhasePart.exit]) {
          pieces.add(
            PhasePiece(segmentIndex: index, segmentId: id, name: name, part: part, corner: true),
          );
        }
        continue;
      }
    }
    pieces.add(
      PhasePiece(
        segmentIndex: index,
        segmentId: id,
        name: name,
        corner: isCorner,
        splitReason: !isCorner
            ? ''
            : corner == null
            ? cornerPhaseInvalidInput
            : corner.phaseSplit.valid
            ? cornerPhaseTimesNotTimed
            : corner.phaseSplit.unavailableReason,
      ),
    );
  }
  throwIfCancelled(cancelled);

  final units = <String>{};
  final laps = <PhaseLapInput>[];
  for (final (position, k) in population.indexed) {
    final times = computed.population[k].times;
    final session = k < computed.runIds.length ? sessions[computed.runIds[k]] : null;
    final trace = k < computed.traces.length ? computed.traces[k] : const <ProgressSegment>[];
    if (session?.channel('speed') case final channel?) {
      // As written; only the spellings of km/h and mph are folded together.
      final written = effectiveChannelUnit(session!, channel.name);
      final folded = normalizedSpeedUnit(written);
      units.add(folded.isNotEmpty ? folded : written);
    }
    double? speed(double? time) => session == null ? null : speedMetresPerSecondAt(session, time);
    SectorTime? sector(String id) {
      for (final candidate in times.sectors) {
        if (candidate.segmentId == id) return candidate;
      }
      return null;
    }

    final seconds = <double?>[], entry = <double?>[], exit = <double?>[];
    var index = 0;
    while (index < pieces.length) {
      final piece = pieces[index];
      final timed = sector(piece.segmentId);
      final split = phases[piece.segmentIndex];
      if (split == null) {
        seconds.add(timed?.seconds);
        entry.add(speed(timed?.startTime));
        exit.add(speed(timed?.endTime));
        index += 1;
        continue;
      }
      final own = split[position];
      final corner = cornerAt(piece.segmentIndex)!;
      if (!own.valid) {
        seconds.addAll([null, null, null]);
        entry.addAll([null, null, null]);
        exit.addAll([null, null, null]);
      } else {
        // Where the lap was at each line: the sector's own start and end,
        // and the two lines inside the corner on the lap's projection.
        final lines = [
          speed(timed?.startTime),
          speed(timeAtProgress(trace, corner.phaseSplit.entryEndMeters)),
          speed(timeAtProgress(trace, corner.phaseSplit.midEndMeters)),
          speed(timed?.endTime),
        ];
        seconds.addAll([own.entry, own.mid, own.exit]);
        entry.addAll(lines.sublist(0, 3));
        exit.addAll(lines.sublist(1));
      }
      index += 3;
    }
    laps.add(
      PhaseLapInput(
        lapReference: times.lapReference,
        seconds: seconds,
        entrySpeeds: entry,
        exitSpeeds: exit,
      ),
    );
  }
  final (:meets, :closes) = segmentsMeet(segments);
  return computePhaseReference(
    pieces,
    laps,
    segmentMeets: meets,
    closes: closes,
    // One unit shared by every lap, if it is known: a speed without a unit
    // is read as km/h (speedInMetresPerSecond) and said to be assumed; a
    // declared unit is never relabelled, and one that is not known (or
    // several) leaves differences in m/s.
    speedUnit: switch (units.length == 1 ? units.single : null) {
      null => '',
      '' => 'km/h',
      final unit when metresPerSecondPerSpeedUnit(unit) != null => unit,
      _ => '',
    },
    speedUnitAssumed: units.contains(''),
    cancelled: cancelled,
  );
}
