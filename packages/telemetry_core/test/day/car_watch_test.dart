import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

const _revision = 'r';

DayLapRow _row(LapSectionType type, int number) => DayLapRow(
  runId: 'run',
  runName: 'Session 1',
  type: type,
  lapNumber: number,
  start: number * 100.0,
  end: number * 100.0 + 100,
  sourceRevision: _revision,
  referenceEligible: type == LapSectionType.lap,
);

/// A session of an out lap, timed laps with [maxima] per channel (null: not
/// recorded on that lap) and [strongG] each, then an in lap.
RunChannelSummaries _run({
  Map<String, List<double?>> maxima = const {},
  List<double?> strongG = const [],
  String unit = '',
  int? laps,
}) {
  final count =
      laps ??
      [...maxima.values.map((v) => v.length), strongG.length].reduce((a, b) => a > b ? a : b);
  final rows = [
    _row(LapSectionType.outLap, 0),
    for (var lap = 1; lap <= count; lap++) _row(LapSectionType.lap, lap),
    _row(LapSectionType.inLap, 0),
  ];
  // Out and in laps are hotter than anything timed, so reading them would
  // show.
  ChannelSummary summary(double? maximum) => maximum == null
      ? const ChannelSummary(unavailableReason: 'No valid samples.')
      : ChannelSummary(unit: unit, maximum: maximum, minimum: maximum - 2, valid: true);
  return RunChannelSummaries(
    runId: 'run',
    runName: 'Session 1',
    channels: [
      for (final MapEntry(key: name, value: values) in maxima.entries)
        RunChannel(
          channel: name,
          unit: unit,
          run: summary(200),
          sections: [
            for (final (i, row) in rows.indexed)
              ChannelSection(
                row: row,
                summary: summary(
                  row.type == LapSectionType.lap
                      ? (i - 1 < values.length ? values[i - 1] : null)
                      : 200,
                ),
              ),
          ],
        ),
    ],
    laps: [
      for (final (i, row) in rows.indexed)
        SectionAcceleration(
          row: row,
          acceleration: LapAcceleration(
            strongG: row.type == LapSectionType.lap
                ? (i - 1 < strongG.length ? strongG[i - 1] : null)
                : 0.9,
          ),
        ),
    ],
  );
}

void main() {
  test('a temperature still rising over the last three laps is noted', () {
    final watch = carWatch(
      _run(
        maxima: {
          'oil': [100, 104, 113, 121],
          'coolant': [90, 91, 92, 93],
        },
      ),
    )!;
    expect(watch.timedLaps, 4);
    expect(watch.temperaturesRead, 2);
    expect(watch.rises, hasLength(1));
    final rise = watch.rises.single;
    expect(rise.channel, 'oil');
    expect((rise.fromLap, rise.toLap, rise.from, rise.to), (2, 4, 104.0, 121.0));
    expect(rise.rise, 17);
    expect(watch.settled, isFalse);
  });

  test('a rise just under the threshold, or one that has levelled off, is '
      'not', () {
    expect(
      carWatch(
        _run(
          maxima: {
            'oil': [100, 110, 117.9],
            'gearbox': [90, 108, 108, 105],
          },
        ),
      )!.settled,
      isTrue,
    );
    // Exactly the threshold counts.
    expect(
      carWatch(
        _run(
          maxima: {
            'oil': [100, 104, 108],
          },
        ),
      )!.rises,
      hasLength(1),
    );
  });

  test('the threshold follows a declared °F', () {
    final maxima = {
      'oil': <double?>[200, 210, 214],
    };
    expect(carWatch(_run(maxima: maxima, unit: '°F'))!.rises, isEmpty);
    expect(carWatch(_run(maxima: maxima, unit: '°C'))!.rises, hasLength(1));
    expect(carWatch(_run(maxima: maxima))!.rises, hasLength(1));
    expect(carWatchRiseIn('degF'), closeTo(14.4, 1e-9));
  });

  test('largest rise first', () {
    final watch = carWatch(
      _run(
        maxima: {
          'oil': [100, 109, 118],
          'gearbox': [90, 100, 110],
        },
      ),
    )!;
    expect([for (final rise in watch.rises) rise.channel], ['gearbox', 'oil']);
  });

  test('too few timed laps, or a lap without the channel, read nothing', () {
    final short = carWatch(
      _run(
        maxima: {
          'oil': [100, 130],
        },
      ),
    )!;
    expect(short.timedLaps, 2);
    expect(short.temperaturesRead, 0);
    expect(short.read, isFalse);
    expect(short.recorded, isTrue);
    expect(carWatch(_run(laps: 5))!.recorded, isFalse);
    final gap = carWatch(
      _run(
        maxima: {
          'oil': [100, 110, null, 140],
        },
      ),
    )!;
    expect(gap.temperaturesRead, 0);
    expect(gap.rises, isEmpty);
  });

  test('strong acceleration falling on the last lap is noted with the '
      'temperature that rose most over the same laps', () {
    final watch = carWatch(
      _run(
        maxima: {
          'oil': [114, 121, 126, 128, 126],
          'gearbox': [98, 104, 108, 111, 111],
          'intake': [37, 33, 33, 38, 35],
        },
        strongG: [0.263, 0.265, 0.264, 0.256, 0.250],
      ),
    )!;
    final fall = watch.fall!;
    expect((fall.fromLap, fall.toLap, fall.from, fall.to), (2, 5, 0.265, 0.250));
    expect(fall.fall, closeTo(0.0566, 1e-4));
    expect(fall.alongside!.channel, 'gearbox');
    expect((fall.alongside!.from, fall.alongside!.to), (104.0, 111.0));
    // Levelled off over the last three laps.
    expect(watch.rises, isEmpty);
  });

  test('strong acceleration needs four laps, the last one with it, and a '
      'fall of 5%', () {
    expect(carWatch(_run(strongG: [0.30, 0.30, 0.20]))!.fall, isNull);
    expect(carWatch(_run(strongG: [0.30, 0.30, 0.30, null], laps: 4))!.fall, isNull);
    expect(carWatch(_run(strongG: [0.300, 0.300, 0.300, 0.286]))!.fall, isNull);
    final fall = carWatch(_run(strongG: [0.300, 0.300, 0.300, 0.285]))!.fall!;
    expect(fall.alongside, isNull);
    expect(fall.fromLap, 1);
  });

  test('out and in laps are left out', () {
    // Their 200 maxima and 0.9 g would otherwise rise and fall.
    final watch = carWatch(
      _run(
        maxima: {
          'oil': [100, 100, 100],
        },
        strongG: [0.3, 0.3, 0.3, 0.3],
      ),
    )!;
    expect(watch.settled, isTrue);
    expect(watch.read, isTrue);
  });

  test('a recording that could not be read has none', () {
    expect(
      carWatch(RunChannelSummaries(runId: 'run', runName: 'Session 1', unavailableReason: 'gone')),
      isNull,
    );
  });

  test('the session summary carries it for its session', () {
    final channels = DayChannelSummaries(
      runs: [
        _run(
          maxima: {
            'oil': [100, 104, 113],
          },
        ),
      ],
    );
    final progression = DayProgression(
      groupId: 'g',
      state: DayRankingState.available,
      runs: [
        ProgressionRun(
          run: ProgressionRunInfo(id: 'run', name: 'Session 1'),
          state: ProgressionRunState.available,
        ),
      ],
    );
    final summary = summarizeSession('run', progression: progression, channels: channels)!;
    expect(summary.carWatch!.rises.single.channel, 'oil');
    expect(summarizeSession('run', progression: progression)!.carWatch, isNull);
  });
}
