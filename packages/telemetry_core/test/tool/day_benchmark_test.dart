// The day benchmark runs (FET-41). Its figures are not checked: timings
// depend on the machine.
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/day_benchmark/benchmark.dart';

void main() {
  test('measures every step of a synthetic day', () async {
    final out = StringBuffer();
    final directory = Directory.systemTemp.createTempSync('day_benchmark_test');
    addTearDown(() => directory.deleteSync(recursive: true));
    final json = '${directory.path}/figures.json';
    final code = await runBenchmarkCli([
      '--synthetic=2',
      '--laps=3',
      '--rate=10',
      '--no-heap',
      '--json=$json',
    ], out: out);
    expect(code, 0, reason: '$out');
    final text = '$out';
    for (final step in benchmarkSteps) {
      expect(text, contains(step));
    }
    expect(text, isNot(contains('skipped')));
    expect(text, contains('sessions 2'));
    final figures = jsonDecode(File(json).readAsStringSync()) as List<Object?>;
    final run = figures.single as Map<String, Object?>;
    expect((run['steps'] as List<Object?>).length, benchmarkSteps.length);
    expect((run['counts'] as Map<String, Object?>)['segments'], greaterThan(0));
  });

  test('gives the same results on one isolate', () async {
    final inIsolates = StringBuffer(), oneIsolate = StringBuffer();
    expect(
      await runBenchmarkCli([
        '--synthetic=1',
        '--laps=3',
        '--rate=10',
        '--no-heap',
      ], out: inIsolates),
      0,
    );
    expect(
      await runBenchmarkCli([
        '--synthetic=1',
        '--laps=3',
        '--rate=10',
        '--no-heap',
        '--one-isolate',
      ], out: oneIsolate),
      0,
    );
    String digest(StringBuffer out) => RegExp(r'result digest (\w+)').firstMatch('$out')![1]!;
    expect(digest(oneIsolate), digest(inIsolates));
  });

  test('refuses a call without recordings', () async {
    final out = StringBuffer();
    expect(await runBenchmarkCli(const [], out: out), 64);
    expect('$out', contains('--synthetic'));
  });
}
