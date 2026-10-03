// Areas to inspect next (analysis/focus_areas.dart, KAN-73), ported from
// FlappedEar Overlays native/tests/FocusAreasTests.cpp: chosen from
// computed observations only, observation separate from hypothesis, no
// causal or "brake later" claims, evidence on every area.
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

Map<String, Object?> lap(String name) => {'runId': name};

FocusLoss loss(String segment, double seconds, String lapName) =>
    FocusLoss(segmentId: segment, name: 'Corner $segment', lossSeconds: seconds, lap: lap(lapName));

FocusSectorGap gap(
  String id,
  String name,
  double seconds,
  String label,
  String source,
  String sourceLabel,
) => FocusSectorGap(
  segmentId: id,
  name: name,
  gapSeconds: seconds,
  bestLap: lap('best'),
  bestLapLabel: label,
  sourceLap: lap(source),
  sourceLapLabel: sourceLabel,
);

CornerLapObservation braking(
  double meters,
  String provenance,
  String lapName, {
  double minimumSpeed = 80.0,
}) => CornerLapObservation(lapReference: lap(lapName))
  ..brakingPointMeters = meters
  ..brakingProvenance = provenance
  ..minimumSpeed = minimumSpeed;

// Words that would turn an observation into advice or a causal claim.
void expectNoAdviceWording(FocusArea area) {
  for (final text in [area.observation, area.hypothesis]) {
    for (final word in [
      'brake later',
      'should',
      'because you',
      'you must',
      'caused',
      'guarantee',
    ]) {
      expect(text.toLowerCase(), isNot(contains(word)), reason: text);
    }
  }
  expect(area.observation, isNotEmpty);
  expect(area.hypothesis, isNotEmpty);
  expect(area.lap, isNotNull);
  expect(area.against, isNotNull);
}

void main() {
  test('selects one of each kind first', () {
    final inputs = FocusInputs(
      referenceLap: lap('best'),
      referenceLabel: 'Session 5 · LAP 2',
      comparedLapCount: 5,
      gaps: [
        gap('7', 'Corner 7', 0.412, 'Session 5 · LAP 2', 's3l2', 'Session 3 · LAP 2'),
        gap('8', 'Corner 8', 0.2, 'Session 5 · LAP 2', 's4l1', 'Session 4 · LAP 1'),
      ],
      // Corner 2 loses on four of five laps (median 0.3); corner 7 is taken
      // by the gap.
      losses: [
        loss('2', 0.25, 'a'),
        loss('2', 0.30, 'b'),
        loss('2', 0.31, 'c'),
        loss('2', 0.6, 'd'),
        loss('7', 0.5, 'a'),
        loss('7', 0.5, 'b'),
        loss('7', 0.5, 'c'),
      ],
      corners: [
        FocusCorner(
          segmentId: '4',
          name: 'Corner 4',
          observations: [
            braking(100, 'measured', 'a'),
            braking(120, 'measured', 'b'),
            braking(140, 'measured', 'c'),
            braking(160, 'measured', 'd'),
          ],
        ),
      ],
    );
    final areas = selectFocusAreas(inputs);
    expect(areas, hasLength(3));
    expect(areas[0].kind, FocusAreaKind.sectorGap);
    expect(areas[0].segmentId, '7');
    expect(areas[0].observation, contains('0.412 s'));
    expect(areas[0].observation, contains('Session 3 · LAP 2'));
    expect(areas[0].against, lap('s3l2'));
    expect(areas[1].kind, FocusAreaKind.repeatedLoss);
    expect(areas[1].segmentId, '2'); // corner 7 already has an area
    expect(areas[1].sampleCount, 4);
    expect(areas[1].observation, contains('In 4 of 5 compared laps'));
    expect(areas[1].against, inputs.referenceLap);
    expect(areas[1].lap, anyOf(lap('b'), lap('c'))); // the typical lap, near the median
    expect(areas[2].kind, FocusAreaKind.brakingSpread);
    areas.forEach(expectNoAdviceWording);
  });

  test('requires repeats and thresholds', () {
    final inputs = FocusInputs(
      referenceLap: lap('best'),
      referenceLabel: 'best',
      comparedLapCount: 5,
      // Two losses are not a pattern; tiny losses and gaps are not areas.
      losses: [
        loss('2', 0.4, 'a'),
        loss('2', 0.4, 'b'),
        loss('3', 0.01, 'a'),
        loss('3', 0.02, 'b'),
        loss('3', 0.03, 'c'),
      ],
      gaps: [gap('9', 'Corner 9', 0.01, 'best', 'x', 'x')],
      corners: [
        FocusCorner(
          segmentId: '4',
          name: 'Corner 4',
          observations: [
            braking(100, 'measured', 'a'),
            braking(102, 'measured', 'b'),
            braking(104, 'measured', 'c'),
          ],
        ),
      ],
    );
    expect(selectFocusAreas(inputs), isEmpty);
  });

  test('keeps measured braking apart and makes no braking claim', () {
    // Inferred braking points spread widely but are never mixed with
    // measured ones.
    expect(
      selectFocusAreas(
        FocusInputs(
          corners: [
            FocusCorner(
              segmentId: '4',
              name: 'Corner 4',
              observations: [
                braking(100, 'measured', 'a'),
                braking(101, 'measured', 'b'),
                braking(102, 'measured', 'c'),
                braking(40, 'inferred', 'd'),
                braking(200, 'inferred', 'e'),
              ],
            ),
          ],
        ),
      ),
      isEmpty,
    );
    final areas = selectFocusAreas(
      FocusInputs(
        corners: [
          FocusCorner(
            segmentId: '4',
            name: 'Corner 4',
            observations: [
              braking(100, 'measured', 'early'),
              braking(115, 'measured', 'b'),
              braking(130, 'measured', 'c'),
              braking(150, 'measured', 'late'),
            ],
          ),
        ],
      ),
    );
    expect(areas, hasLength(1));
    expect(areas[0].unit, 'm');
    expect(areas[0].observation, contains('measured from the brake signal'));
    expect(
      areas[0].hypothesis,
      contains('does not show whether earlier or later braking is faster or safe'),
    );
    expect(areas[0].lap, lap('early'));
    expect(areas[0].against, lap('late'));
    expectNoAdviceWording(areas[0]);
    // A minimum-speed spread (8 of 80 km/h) with a steady braking point.
    final speed = selectFocusAreas(
      FocusInputs(
        speedUnit: 'km/h',
        corners: [
          FocusCorner(
            segmentId: '5',
            name: 'Corner 5',
            observations: [
              braking(100, 'measured', 'a', minimumSpeed: 70),
              braking(101, 'measured', 'b', minimumSpeed: 78),
              braking(102, 'measured', 'c', minimumSpeed: 86),
              braking(103, 'measured', 'd', minimumSpeed: 94),
            ],
          ),
        ],
      ),
    );
    expect(speed, hasLength(1));
    expect(speed[0].kind, FocusAreaKind.minimumSpeedSpread);
    expect(speed[0].observation, contains('km/h'));
    expect(speed[0].hypothesis, contains('not by itself better'));
    expectNoAdviceWording(speed[0]);
  });

  test('is short, deterministic and empty without observations', () {
    expect(selectFocusAreas(FocusInputs()), isEmpty);
    final inputs = FocusInputs(
      referenceLap: lap('best'),
      gaps: [for (var i = 0; i < 8; ++i) gap('$i', 'Corner $i', 0.1 + 0.01 * i, 'best', 'x', 'x')],
    );
    final areas = selectFocusAreas(inputs);
    expect(areas, hasLength(3));
    expect(areas[0].segmentId, '7'); // largest gap first
    expect(areas[1].segmentId, '6');
    expect(selectFocusAreas(inputs, maximum: 5), hasLength(5));
    // Equal scores order by segment id, whatever the input order.
    final tied = FocusInputs(
      gaps: [gap('b', 'B', 0.2, 'best', 'x', 'x'), gap('a', 'A', 0.2, 'best', 'x', 'x')],
    );
    expect(selectFocusAreas(tied)[0].segmentId, 'a');
  });
}
