// A corner-phase reference (FET-226, idea 10 of FET-217): the day's best
// entry, middle and exit of every corner, each from the lap fastest through
// that part, as a target ("the braking of lap 3, the mid-corner of lap 7,
// the exit of lap 5"). Corners are split by their shape (FET-221), so every
// lap is timed over the same metres; a straight, or a corner that is not
// split, is one piece, its fastest whole time.
//
// It is the raw theoretical best (each segment's fastest time from any lap)
// at a finer grain: a split corner's three parts may come from three laps
// where the theoretical best takes the whole corner from one, so it is never
// slower. Like the raw best it ignores whether the pieces join; the rule of
// the realistic best (FET-222) says where they do: two laps join where their
// speeds differ by at most [realisticJoinMetresPerSecond], and the quickest
// combination of pieces that joins everywhere is worked out beside it.
import '../operation.dart';
import 'realistic_theoretical_best.dart';

/// No piece, or a piece no lap timed: no total.
const String phaseReferenceIncompleteCoverage = 'incompleteCoverage';

/// No lap records a speed in a known unit, so no two laps can be joined.
const String phaseReferenceNoSpeed = 'noSpeed';

/// Every piece is timed, but no laps join at every line between them.
const String phaseReferenceNoJoin = 'noJoin';

/// Which part of its segment a piece is.
enum PhasePart {
  /// The whole segment: a straight, or a corner that is not split.
  whole,

  /// From the corner's start to the start of its tightest part.
  entry,

  /// Through the tightest part.
  middle,

  /// From the end of the tightest part to the corner's end.
  exit,
}

/// One piece of the lap: a corner's part, or a whole segment.
final class PhasePiece {
  const PhasePiece({
    required this.segmentIndex,
    required this.segmentId,
    required this.name,
    this.part = PhasePart.whole,
    this.corner = false,
    this.splitReason = '',
  });

  /// The segment's position among the approved segments.
  final int segmentIndex;
  final String segmentId, name;
  final PhasePart part;

  /// The segment is a corner.
  final bool corner;

  /// For a corner taken whole: why it is not split. Empty otherwise.
  final String splitReason;
}

/// One lap's time through each piece and its speed (m/s) where each piece
/// starts and ends; null where not timed or the speed is not known.
final class PhaseLapInput {
  PhaseLapInput({
    required this.lapReference,
    required List<double?> seconds,
    required List<double?> entrySpeeds,
    required List<double?> exitSpeeds,
  }) : seconds = List.unmodifiable(seconds),
       entrySpeeds = List.unmodifiable(entrySpeeds),
       exitSpeeds = List.unmodifiable(exitSpeeds);

  final Object? lapReference;

  /// By piece, in lap order.
  final List<double?> seconds, entrySpeeds, exitSpeeds;
}

/// How a piece of the reference meets the one before it.
enum PhaseJoin {
  /// The first piece, or the two do not meet (a gap between segments).
  none,

  /// Both come from the same lap.
  sameLap,

  /// Two laps whose speeds there differ by at most
  /// [realisticJoinMetresPerSecond].
  joins,

  /// Two laps whose speeds there differ by more.
  apart,

  /// Two laps, and the speed of either is not known there.
  unknown,
}

/// The fastest time through one piece and the lap that set it.
final class PhaseReferencePiece {
  const PhaseReferencePiece({
    required this.piece,
    this.seconds,
    this.lapReference,
    this.join = PhaseJoin.none,
    this.joinMetresPerSecond,
  });

  final PhasePiece piece;

  /// Null when no lap is timed through it.
  final double? seconds;
  final Object? lapReference;

  /// How it meets the piece before it (for the first piece, the last one
  /// when the lap closes there).
  final PhaseJoin join;

  /// With [PhaseJoin.joins] or [PhaseJoin.apart]: the speed difference
  /// there, in m/s.
  final double? joinMetresPerSecond;
}

/// The best phases of the day: each piece's fastest time, their sum, and
/// the quickest combination of pieces that joins.
final class PhaseReference {
  PhaseReference({
    List<PhaseReferencePiece> pieces = const [],
    this.totalSeconds,
    this.unavailableReason = '',
    this.joinedSeconds,
    this.joinedLapCount = 0,
    this.joinedUnavailableReason = '',
    Map<Object?, List<double?>> lapSeconds = const {},
    this.speedUnit = '',
  }) : pieces = List.unmodifiable(pieces),
       lapSeconds = Map.unmodifiable({
         for (final MapEntry(:key, :value) in lapSeconds.entries)
           key: List<double?>.unmodifiable(value),
       });

  /// In lap order.
  final List<PhaseReferencePiece> pieces;

  /// The sum of [pieces] when every one is timed.
  final double? totalSeconds;

  /// Non-empty: no [totalSeconds].
  final String unavailableReason;

  /// The quickest combination of pieces in which laps join wherever two
  /// meet; null with [joinedUnavailableReason].
  final double? joinedSeconds;

  /// How many laps [joinedSeconds] is made of.
  final int joinedLapCount;
  final String joinedUnavailableReason;

  /// Each lap's time through every piece, by lap reference.
  final Map<Object?, List<double?>> lapSeconds;

  /// The unit the laps' speeds are recorded in when they all declare the
  /// same one, else empty. Joins are compared in m/s.
  final String speedUnit;

  bool get valid => unavailableReason.isEmpty && totalSeconds != null;

  /// How many different laps the pieces come from.
  int get lapCount => {
    for (final piece in pieces)
      if (piece.seconds != null) piece.lapReference,
  }.length;

  /// The pieces whose join with the one before is [join].
  List<PhaseReferencePiece> joinsOf(PhaseJoin join) => [
    for (final piece in pieces)
      if (piece.join == join) piece,
  ];

  /// [lap]'s time minus the fastest, per piece; null where either is not
  /// timed, and an empty list for a lap that is not in the reference.
  List<double?> lossesOf(Object? lap) {
    final own = lapSeconds[lap];
    if (own == null) return const [];
    return [
      for (var i = 0; i < pieces.length; ++i)
        own[i] == null || pieces[i].seconds == null ? null : own[i]! - pieces[i].seconds!,
    ];
  }

  /// [lap]'s time through every piece together; null when any is not timed.
  double? lapTotal(Object? lap) {
    final own = lapSeconds[lap];
    if (own == null || own.length != pieces.length) return null;
    var total = 0.0;
    for (final seconds in own) {
      if (seconds == null) return null;
      total += seconds;
    }
    return total;
  }
}

/// The best phases of [laps] through [pieces] (in lap order). Consecutive
/// pieces of one segment always meet; the last piece of segment i meets the
/// first of i + 1 when [segmentMeets] says so (see [segmentsMeet]), and with
/// [closes] the last piece meets the first across the gate. The first lap,
/// in [laps]' order, with the fastest time wins a tie. Laps whose lists do
/// not match [pieces] are left out.
PhaseReference computePhaseReference(
  List<PhasePiece> pieces,
  List<PhaseLapInput> laps, {
  List<bool> segmentMeets = const [],
  bool closes = false,
  String speedUnit = '',
  CancellationCheck? cancelled,
}) {
  final count = pieces.length;
  if (count == 0) {
    return PhaseReference(
      unavailableReason: phaseReferenceIncompleteCoverage,
      speedUnit: speedUnit,
    );
  }
  double? finite(double? value) => value != null && value.isFinite ? value : null;
  final population = [
    for (final lap in laps)
      if (lap.seconds.length == count &&
          lap.entrySpeeds.length == count &&
          lap.exitSpeeds.length == count)
        lap,
  ];
  final seconds = [
    for (final lap in population)
      [
        for (final value in lap.seconds)
          if (finite(value) case final time? when time >= 0) time else null,
      ],
  ];
  final entry = [
    for (final lap in population) [for (final value in lap.entrySpeeds) finite(value)],
  ];
  final exit = [
    for (final lap in population) [for (final value in lap.exitSpeeds) finite(value)],
  ];

  // Whether piece i meets piece i + 1.
  final meets = [
    for (var i = 0; i + 1 < count; ++i)
      pieces[i].segmentIndex == pieces[i + 1].segmentIndex ||
          (pieces[i].segmentIndex < segmentMeets.length &&
              pieces[i + 1].segmentIndex == pieces[i].segmentIndex + 1 &&
              segmentMeets[pieces[i].segmentIndex]),
  ];
  final closing = closes && count > 1;

  // Each piece's fastest lap (index into population), or -1.
  final fastest = List<int>.filled(count, -1);
  for (var i = 0; i < count; ++i) {
    for (var k = 0; k < population.length; ++k) {
      final time = seconds[k][i];
      if (time != null && (fastest[i] < 0 || time < seconds[fastest[i]][i]!)) fastest[i] = k;
    }
  }
  throwIfCancelled(cancelled);

  ({PhaseJoin join, double? difference}) joinInto(int i) {
    final before = i == 0 ? count - 1 : i - 1;
    final met = i == 0 ? closing : meets[before];
    final (a, b) = (fastest[before], fastest[i]);
    if (!met || a < 0 || b < 0) return (join: PhaseJoin.none, difference: null);
    if (a == b) return (join: PhaseJoin.sameLap, difference: null);
    final out = exit[a][before], into = entry[b][i];
    if (out == null || into == null) return (join: PhaseJoin.unknown, difference: null);
    return (
      join: speedsJoin(out, into) ? PhaseJoin.joins : PhaseJoin.apart,
      difference: (out - into).abs(),
    );
  }

  final complete = !fastest.contains(-1);
  final total = complete
      ? [for (var i = 0; i < count; ++i) seconds[fastest[i]][i]!].fold(0.0, (a, b) => a + b)
      : null;

  double? joined;
  var joinedLaps = 0;
  var joinedReason = '';
  if (!complete) {
    joinedReason = phaseReferenceIncompleteCoverage;
  } else if (!population.any(
    (lap) => [...lap.entrySpeeds, ...lap.exitSpeeds].any((v) => finite(v) != null),
  )) {
    joinedReason = phaseReferenceNoSpeed;
  } else {
    final chain = quickestJoinedChain(
      seconds: seconds,
      entrySpeeds: entry,
      exitSpeeds: exit,
      meets: meets,
      closes: closing,
      cancelled: cancelled,
    );
    if (chain == null) {
      joinedReason = phaseReferenceNoJoin;
    } else {
      joined = chain.total;
      joinedLaps = chain.laps.toSet().length;
    }
  }

  return PhaseReference(
    pieces: [
      for (var i = 0; i < count; ++i)
        () {
          final (:join, :difference) = joinInto(i);
          return PhaseReferencePiece(
            piece: pieces[i],
            seconds: fastest[i] < 0 ? null : seconds[fastest[i]][i],
            lapReference: fastest[i] < 0 ? null : population[fastest[i]].lapReference,
            join: join,
            joinMetresPerSecond: difference,
          );
        }(),
    ],
    totalSeconds: total,
    unavailableReason: complete ? '' : phaseReferenceIncompleteCoverage,
    joinedSeconds: joined,
    joinedLapCount: joinedLaps,
    joinedUnavailableReason: joinedReason,
    lapSeconds: {
      for (var k = 0; k < population.length; ++k) population[k].lapReference: seconds[k],
    },
    speedUnit: speedUnit,
  );
}
