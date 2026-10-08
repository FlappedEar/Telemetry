// The corner-phase reference (FET-226): each piece's fastest lap, the joins
// between laps at the realistic best's speed rule, and the quickest
// combination that joins.
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

// A straight, a corner split in three, and another straight.
const _pieces = [
  PhasePiece(segmentIndex: 0, segmentId: 's1', name: 'Straight 1'),
  PhasePiece(
    segmentIndex: 1,
    segmentId: 'c1',
    name: 'Corner 1',
    part: PhasePart.entry,
    corner: true,
  ),
  PhasePiece(
    segmentIndex: 1,
    segmentId: 'c1',
    name: 'Corner 1',
    part: PhasePart.middle,
    corner: true,
  ),
  PhasePiece(
    segmentIndex: 1,
    segmentId: 'c1',
    name: 'Corner 1',
    part: PhasePart.exit,
    corner: true,
  ),
  PhasePiece(segmentIndex: 2, segmentId: 's2', name: 'Straight 2'),
];

// A lap at one speed everywhere, so it joins any lap at that speed.
PhaseLapInput _lap(Object reference, List<double?> seconds, {double? speed = 30}) => PhaseLapInput(
  lapReference: reference,
  seconds: seconds,
  entrySpeeds: [for (final _ in seconds) speed],
  exitSpeeds: [for (final _ in seconds) speed],
);

void main() {
  test('takes each piece from the lap fastest through it', () {
    final result = computePhaseReference(
      _pieces,
      [
        _lap('a', [5.0, 1.0, 2.0, 3.0, 6.0]),
        _lap('b', [5.1, 1.2, 1.8, 3.1, 6.0]),
        _lap('c', [4.9, 1.1, 2.1, 2.9, 6.1]),
      ],
      segmentMeets: const [true, true],
    );
    expect(result.valid, isTrue);
    expect([for (final piece in result.pieces) piece.lapReference], ['c', 'a', 'b', 'c', 'a']);
    expect([for (final piece in result.pieces) piece.seconds], [4.9, 1.0, 1.8, 2.9, 6.0]);
    expect(result.totalSeconds, closeTo(16.6, 1e-9));
    expect(result.lapCount, 3);
    // The first lap wins a tie (Straight 2: a and b).
    expect(result.pieces.last.lapReference, 'a');
    // Every lap is at one speed: they all join.
    expect(result.joinedSeconds, closeTo(16.6, 1e-9));
    expect(result.joinedLapCount, 3);
    expect(result.joinedUnavailableReason, isEmpty);
    expect(
      [for (final piece in result.pieces) piece.join],
      [
        PhaseJoin.none, // the first: the lap does not close across the gate
        PhaseJoin.joins,
        PhaseJoin.joins,
        PhaseJoin.joins,
        PhaseJoin.joins,
      ],
    );
    expect(result.pieces[1].joinMetresPerSecond, 0);
  });

  test('a lap\'s losses are its time minus the fastest, piece by piece', () {
    final result = computePhaseReference(_pieces, [
      _lap('a', [5.0, 1.0, 2.0, 3.0, 6.0]),
      _lap('b', [5.1, 1.2, 1.8, null, 6.0]),
    ]);
    final losses = result.lossesOf('a');
    expect(losses[0], 0);
    expect(losses[2], closeTo(0.2, 1e-12));
    expect(result.lapTotal('a'), closeTo(17.0, 1e-12));
    // Not timed through a piece: no loss there and no total, never zero.
    expect(result.lossesOf('b')[3], isNull);
    expect(result.lapTotal('b'), isNull);
    // A lap that is not in the reference.
    expect(result.lossesOf('z'), isEmpty);
    expect(result.lapTotal('z'), isNull);
  });

  test('two laps join at up to 2 km/h apart, not beyond', () {
    PhaseReference across(double into) => computePhaseReference(
      _pieces.sublist(0, 2),
      [
        PhaseLapInput(
          lapReference: 'a',
          seconds: [5.0, 1.2],
          entrySpeeds: [0, 0],
          exitSpeeds: [realisticJoinMetresPerSecond, 0],
        ),
        PhaseLapInput(
          lapReference: 'b',
          seconds: [5.2, 1.0],
          entrySpeeds: [0, into],
          exitSpeeds: [0, 0],
        ),
      ],
      segmentMeets: const [true],
    );
    final at = across(0);
    expect(at.pieces[1].join, PhaseJoin.joins);
    expect(at.pieces[1].joinMetresPerSecond, realisticJoinMetresPerSecond);
    expect(at.joinedSeconds, closeTo(6.0, 1e-12));
    expect(at.joinedLapCount, 2);
    final beyond = across(-1e-9);
    expect(beyond.pieces[1].join, PhaseJoin.apart);
    expect(beyond.pieces[1].joinMetresPerSecond, greaterThan(realisticJoinMetresPerSecond));
    // The raw best still takes both; the joined one keeps to a lap.
    expect(beyond.totalSeconds, closeTo(6.0, 1e-12));
    expect(beyond.joinedSeconds, closeTo(6.2, 1e-12));
    expect(beyond.joinedLapCount, 1);
    expect(beyond.joinsOf(PhaseJoin.apart).single.piece.part, PhasePart.entry);
  });

  test('segments meet within 0.5 m; farther apart they are not joined', () {
    Map<String, Object?> segment(double start, double end) => {
      'startProgressMeters': start,
      'endProgressMeters': end,
    };
    expect(segmentsMeet([segment(0, 100), segment(100 + realisticJoinGapMeters, 200)]).meets, [
      true,
    ]);
    expect(segmentsMeet([segment(0, 100), segment(100.5001, 200)]).meets, [false]);
    // The last across the gate into the first closes the lap.
    expect(segmentsMeet([segment(10, 100), segment(100, 10)]).closes, isTrue);
    expect(segmentsMeet([segment(10, 100), segment(100, 9)]).closes, isFalse);
    expect(segmentsMeet([segment(10, 100), segment(100, 9.5)]).closes, isTrue);

    // Two straights, one after the other.
    const straights = [
      PhasePiece(segmentIndex: 0, segmentId: 's1', name: 'Straight 1'),
      PhasePiece(segmentIndex: 1, segmentId: 's2', name: 'Straight 2'),
    ];
    // Two laps meeting where the segments do not: no join to judge.
    final apart = computePhaseReference(
      straights,
      [
        _lap('a', [5.0, 6.2], speed: 10),
        _lap('b', [5.2, 6.0], speed: 40),
      ],
      segmentMeets: const [false],
    );
    expect(apart.pieces[1].join, PhaseJoin.none);
    expect(apart.joinedSeconds, closeTo(11.0, 1e-12));
    // The same segments meeting: the speeds are 30 m/s apart.
    final met = computePhaseReference(
      straights,
      [
        _lap('a', [5.0, 6.2], speed: 10),
        _lap('b', [5.2, 6.0], speed: 40),
      ],
      segmentMeets: const [true],
    );
    expect(met.pieces[1].join, PhaseJoin.apart);
    expect(met.joinedSeconds, closeTo(11.2, 1e-12));
  });

  test('the parts of one corner always meet; the lap closes across the gate', () {
    final result = computePhaseReference(
      _pieces,
      [
        _lap('a', [5.0, 1.0, 2.0, 3.0, 6.2], speed: 10),
        _lap('b', [5.2, 1.2, 1.8, 3.1, 6.0], speed: 40),
      ],
      segmentMeets: const [false, false],
      closes: true,
    );
    // Straight 1 meets nothing after it, but the corner's middle meets its
    // entry, and Straight 1 meets Straight 2 across the gate.
    expect(result.pieces[1].join, PhaseJoin.none);
    expect(result.pieces[2].join, PhaseJoin.apart);
    expect(result.pieces[3].join, PhaseJoin.apart);
    expect(result.pieces[0].join, PhaseJoin.apart);
    expect(result.pieces[4].join, PhaseJoin.none);
  });

  test('a speed not known is not a join, and without speeds nothing joins', () {
    final unknown = computePhaseReference(
      _pieces.sublist(0, 2),
      [
        _lap('a', [5.0, 1.2]),
        _lap('b', [5.2, 1.0], speed: null),
      ],
      segmentMeets: const [true],
    );
    expect(unknown.pieces[1].join, PhaseJoin.unknown);
    expect(unknown.pieces[1].joinMetresPerSecond, isNull);
    // b cannot be joined to: the joined best keeps to a.
    expect(unknown.joinedSeconds, closeTo(6.2, 1e-12));
    final none = computePhaseReference(
      _pieces.sublist(0, 2),
      [
        _lap('a', [5.0, 1.2], speed: null),
        _lap('b', [5.2, 1.0], speed: double.nan),
      ],
      segmentMeets: const [true],
    );
    expect(none.valid, isTrue);
    expect(none.joinedSeconds, isNull);
    expect(none.joinedUnavailableReason, phaseReferenceNoSpeed);
  });

  test('no total while a piece has no time; no joined best when no laps join', () {
    final missing = computePhaseReference(_pieces.sublist(0, 2), [
      _lap('a', [5.0, null]),
      _lap('b', [double.nan, null]),
    ]);
    expect(missing.valid, isFalse);
    expect(missing.totalSeconds, isNull);
    expect(missing.unavailableReason, phaseReferenceIncompleteCoverage);
    expect(missing.pieces[0].seconds, 5.0);
    expect(missing.pieces[1].seconds, isNull);
    expect(missing.pieces[1].lapReference, isNull);
    expect(missing.joinedUnavailableReason, phaseReferenceIncompleteCoverage);
    final split = computePhaseReference(
      _pieces.sublist(0, 2),
      [
        _lap('a', [5.0, null], speed: 10),
        _lap('b', [null, 1.0], speed: 40),
      ],
      segmentMeets: const [true],
    );
    expect(split.valid, isTrue);
    expect(split.joinedSeconds, isNull);
    expect(split.joinedUnavailableReason, phaseReferenceNoJoin);
    expect(
      computePhaseReference(const [], const []).unavailableReason,
      phaseReferenceIncompleteCoverage,
    );
  });

  test('negative times and laps that do not match the pieces are left out', () {
    final result = computePhaseReference(_pieces.sublist(0, 2), [
      _lap('short', [1.0]),
      _lap('a', [-1.0, 1.2]),
      _lap('b', [5.2, 1.0]),
    ]);
    expect(result.pieces[0].lapReference, 'b');
    expect(result.lapSeconds.keys, ['a', 'b']);
    expect(result.lossesOf('short'), isEmpty);
  });

  test('a corner taken whole keeps why it is not split', () {
    final result = computePhaseReference(
      const [
        PhasePiece(
          segmentIndex: 0,
          segmentId: 'c2',
          name: 'Corners 2–3',
          corner: true,
          splitReason: cornerPhaseMultipleApexes,
        ),
      ],
      [
        _lap('a', [8.8]),
      ],
    );
    expect(result.pieces.single.piece.part, PhasePart.whole);
    expect(result.pieces.single.piece.splitReason, cornerPhaseMultipleApexes);
    expect(result.totalSeconds, 8.8);
  });

  test('cancels between steps', () {
    expect(
      () => computePhaseReference(_pieces, [
        _lap('a', [5.0, 1.0, 2.0, 3.0, 6.0]),
      ], cancelled: () => true),
      throwsA(isA<OperationCancelled>()),
    );
  });
}
