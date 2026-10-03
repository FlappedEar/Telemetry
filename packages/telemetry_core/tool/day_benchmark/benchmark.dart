// The day benchmark (FET-41): wall time and memory of each step the app takes
// for one day of recordings, run as the app runs them. Prints figures only:
// times, MiB and counts, never names or values from the recordings.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'synthetic_day.dart';

/// The steps, in the order they run.
const benchmarkSteps = [
  'parse and import',
  'day analysis',
  'theoretical best and segments',
  'A/B comparison',
  'Corner Analyzer',
  'channel summaries',
  'day report',
];

/// What to run.
final class BenchmarkOptions {
  const BenchmarkOptions({
    this.paths = const [],
    this.includeSubfolders = false,
    this.isolates = true,
    this.heap = true,
    this.sampleInterval = const Duration(milliseconds: 2),
  });

  /// Recordings and folders, as the user would choose them.
  final List<String> paths;
  final bool includeSubfolders;

  /// Runs import, analysis, the theoretical best and the channel summaries
  /// in background isolates as the app does; false runs every step on one
  /// isolate, for profiling the analysis code alone.
  final bool isolates;

  /// Samples heap use through the VM service when it can be started.
  final bool heap;
  final Duration sampleInterval;
}

/// One step's figures.
final class StepFigures {
  StepFigures(this.name);

  final String name;
  int micros = 0;
  int peakRss = 0;
  int endRss = 0;
  int? peakHeap;
  int? endHeap;
  bool ran = false;

  Map<String, Object?> toJson(int baselineRss) => {
    'step': name,
    'milliseconds': micros / 1000.0,
    'peakRssMiB': _mib(peakRss),
    'peakAboveStartMiB': _mib(peakRss - baselineRss),
    'endRssMiB': _mib(endRss),
    'peakHeapMiB': peakHeap == null ? null : _mib(peakHeap!),
    'endHeapMiB': endHeap == null ? null : _mib(endHeap!),
    'ran': ran,
  };
}

/// Everything one benchmark run measured.
final class BenchmarkResult {
  BenchmarkResult({
    required this.steps,
    required this.counts,
    required this.digest,
    required this.baselineRss,
    required this.maxRss,
    required this.heapSampled,
    required this.isolates,
  });

  final List<StepFigures> steps;

  /// Files, sessions, samples, laps, segments.
  final Map<String, int> counts;

  /// SHA-256 of the results (laps, ranking, comparison, Corner Analyzer,
  /// channel summaries and the day report), to check that a change leaves
  /// them identical without printing them.
  final String digest;
  final int baselineRss;
  final int maxRss;
  final bool heapSampled;
  final bool isolates;

  Map<String, Object?> toJson() => {
    'isolates': isolates,
    'baselineRssMiB': _mib(baselineRss),
    'maxRssMiB': _mib(maxRss),
    'counts': counts,
    'resultDigest': digest,
    'steps': [for (final step in steps) step.toJson(baselineRss)],
  };

  /// A plain-text table.
  String format() {
    final out = StringBuffer();
    String pad(Object value, int width, {bool left = false}) =>
        left ? '$value'.padRight(width) : '$value'.padLeft(width);
    String mib(int? bytes) => bytes == null ? 'n/a' : _mib(bytes).toStringAsFixed(1);
    out.writeln(
      '${pad('step', 30, left: true)}${pad('ms', 10)}${pad('peak RSS', 10)}'
      '${pad('above start', 13)}${pad('RSS after', 11)}${pad('peak heap', 11)}${pad('heap after', 12)}',
    );
    var total = 0;
    for (final step in steps) {
      total += step.micros;
      out.writeln(
        '${pad(step.name, 30, left: true)}'
        '${pad(step.ran ? (step.micros / 1000).toStringAsFixed(1) : 'skipped', 10)}'
        '${pad(mib(step.peakRss), 10)}${pad(mib(step.peakRss - baselineRss), 13)}'
        '${pad(mib(step.endRss), 11)}'
        '${pad(mib(step.peakHeap), 11)}${pad(mib(step.endHeap), 12)}',
      );
    }
    out
      ..writeln('${pad('total', 30, left: true)}${pad((total / 1000).toStringAsFixed(1), 10)}')
      ..writeln(
        'MiB. RSS before the first step ${mib(baselineRss)}, process peak ${mib(maxRss)}; '
        '${isolates ? 'steps in background isolates as in the app' : 'all steps on one isolate'}'
        '${heapSampled ? '' : '; heap not sampled (no VM service)'}.',
      )
      ..writeln(counts.entries.map((entry) => '${entry.key} ${entry.value}').join(', '))
      ..writeln('result digest $digest');
    return out.toString();
  }
}

double _mib(int bytes) => bytes / (1024 * 1024);

/// Runs the benchmark: the steps in a worker isolate, this isolate sampling
/// the process's resident set (and the heap, when the VM service runs)
/// meanwhile.
Future<BenchmarkResult> runDayBenchmark(BenchmarkOptions options) async {
  final heap = options.heap ? await _HeapProbe.start() : null;
  final steps = {for (final name in benchmarkSteps) name: StepFigures(name)};
  final baseline = ProcessInfo.currentRss;
  StepFigures? current;
  var heapNow = await heap?.read();
  final sampler = Timer.periodic(options.sampleInterval, (_) {
    final step = current;
    if (step == null) return;
    final rss = ProcessInfo.currentRss;
    if (rss > step.peakRss) step.peakRss = rss;
  });
  var sampling = true;
  final heapLoop = heap == null
      ? Future<void>.value()
      : Future(() async {
          while (sampling) {
            heapNow = await heap.read();
            final step = current, used = heapNow;
            if (step != null && used != null && used > (step.peakHeap ?? 0)) {
              step.peakHeap = used;
            }
            await Future<void>.delayed(options.sampleInterval);
          }
        });

  final port = ReceivePort();
  final done = Completer<(Map<String, int>, String)>();
  final starts = <String, int>{};
  port.listen((message) {
    switch (message) {
      case ('begin', final String name, final int at):
        final step = steps[name]!;
        starts[name] = at;
        step
          ..ran = true
          ..peakRss = ProcessInfo.currentRss
          ..peakHeap = heapNow;
        current = step;
      case ('end', final String name, final int at):
        final step = steps[name]!;
        step
          ..micros = at - starts[name]!
          ..endRss = ProcessInfo.currentRss
          ..endHeap = heapNow;
        if (step.endRss > step.peakRss) step.peakRss = step.endRss;
        if (identical(current, step)) current = null;
      case ('done', final Map<String, int> counts, final String digest):
        done.complete((counts, digest));
      case [final Object? error, final Object? stack]:
        if (!done.isCompleted) {
          done.completeError(
            StateError('The benchmark failed: $error'),
            stack is String ? StackTrace.fromString(stack) : null,
          );
        }
      case null:
        if (!done.isCompleted) done.completeError(StateError('The benchmark stopped.'));
    }
  });
  await Isolate.spawn(
    _worker,
    (port.sendPort, options.paths, options.includeSubfolders, options.isolates),
    onError: port.sendPort,
    onExit: port.sendPort,
    debugName: 'day benchmark',
  );
  try {
    final (counts, digest) = await done.future;
    return BenchmarkResult(
      steps: [for (final name in benchmarkSteps) steps[name]!],
      counts: counts,
      digest: digest,
      baselineRss: baseline,
      maxRss: ProcessInfo.maxRss,
      heapSampled: heap != null,
      isolates: options.isolates,
    );
  } finally {
    sampler.cancel();
    sampling = false;
    await heapLoop;
    await heap?.close();
    port.close();
  }
}

/// Heap in use by this isolate group, from the VM service's
/// `getMemoryUsage`. The worker isolates share this isolate's heap.
final class _HeapProbe {
  _HeapProbe(this._socket, this._isolateId) {
    _socket.listen((data) {
      if (data is! String) return;
      final decoded = jsonDecode(data);
      if (decoded is! Map<String, Object?>) return;
      final pending = _pending.remove(decoded['id']);
      if (pending == null) return;
      final result = decoded['result'];
      pending.complete(
        result is Map<String, Object?> && result['heapUsage'] is int
            ? result['heapUsage'] as int
            : null,
      );
    }, onDone: () => _closed = true);
  }

  final WebSocket _socket;
  final String _isolateId;
  final Map<Object?, Completer<int?>> _pending = {};
  var _next = 0;
  var _closed = false;

  static Future<_HeapProbe?> start() async {
    try {
      final isolateId = developer.Service.getIsolateId(Isolate.current);
      if (isolateId == null) return null;
      var info = await developer.Service.getInfo();
      info.serverWebSocketUri ??
          (info = await developer.Service.controlWebServer(enable: true, silenceOutput: true));
      final uri = info.serverWebSocketUri;
      if (uri == null) return null;
      final probe = _HeapProbe(await WebSocket.connect(uri.toString()), isolateId);
      if (await probe.read() != null) return probe;
      await probe.close();
      return null;
    } on Object {
      return null;
    }
  }

  Future<int?> read() {
    if (_closed) return Future.value();
    final id = ++_next;
    final completer = _pending[id] = Completer<int?>();
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': 'getMemoryUsage',
        'params': {'isolateId': _isolateId},
      }),
    );
    return completer.future.timeout(const Duration(seconds: 5), onTimeout: () => null);
  }

  Future<void> close() async {
    await _socket.close();
  }
}

// --- The worker: the app's steps, in the app's order. ---------------------

int _now() => DateTime.now().microsecondsSinceEpoch;

void _begin(SendPort port, String step) => port.send(('begin', step, _now()));
void _end(SendPort port, String step) => port.send(('end', step, _now()));

typedef _Imported = ({List<NamedRun> runs, DayAnalysis? analysis, int files, int alternatives});

/// What the app's import isolate does (lib/import/import_runner.dart): scan,
/// prepare, keep the primary runs, name them and analyse the day.
_Imported _importDay(SendPort port, List<String> paths, bool includeSubfolders) {
  _begin(port, benchmarkSteps[0]);
  final scan = scanTelemetrySources(paths, includeSubfolders: includeSubfolders);
  if (scan.error.isNotEmpty) throw StateError('Nothing to import: ${scan.files.length} files.');
  final plan = prepareTelemetryImport(scan.files);
  final groups = automaticVboPrimaries(plan);
  final primaries = [
    for (final run in plan.runs)
      if (groups[run.id] == run.id) run,
  ];
  final runs = nameRunsInRecordingOrder(primaries);
  _end(port, benchmarkSteps[0]);
  _begin(port, benchmarkSteps[1]);
  final analysis = runs.isEmpty
      ? null
      : analyzeDay([
          for (final named in runs)
            DayRunInput(
              runId: named.run.id,
              name: named.name,
              contentSha256: named.run.contentSha256,
              session: named.run.telemetry,
              laps: named.run.laps,
            ),
        ]);
  return (
    runs: runs,
    analysis: analysis,
    files: plan.files.length,
    alternatives: plan.runs.length - primaries.length,
  );
}

// Built outside the worker so the isolate's closure holds only its inputs,
// as DayResultsController does.
DayTheoreticalBest Function() _theoreticalBestJob(
  DayAnalysis analysis,
  Map<String, OutingRun> runs,
) =>
    () => dayTheoreticalBest(analysis, runs, random: math.Random(41));

DayChannelSummaries Function() _channelSummariesJob(
  List<DayLapRow> rows,
  Map<String, TelemetrySession?> sessions,
) =>
    () => summarizeDayChannels(rows, sessions);

Future<void> _worker((SendPort, List<String>, bool, bool) message) async {
  final (port, paths, includeSubfolders, isolates) = message;
  final digest = _Digest();

  // Import and analysis, in one background isolate as the app runs them;
  // the analysis step ends once the result is back.
  final imported = isolates
      ? await Isolate.run(() => _importDay(port, paths, includeSubfolders))
      : _importDay(port, paths, includeSubfolders);
  _end(port, benchmarkSteps[1]);
  final runs = imported.runs;
  final analysis = imported.analysis;
  if (analysis == null) throw StateError('No session could be imported.');
  var samples = 0, channelSamples = 0;
  for (final named in runs) {
    final session = named.run.telemetry;
    samples += session.sampleCount;
    for (final channel in session.channels.values) {
      channelSamples += channel.sampleCount;
    }
    digest.add([
      named.name,
      session.sampleCount,
      session.channels.length,
      [for (final lap in named.run.laps.timedLaps) lap.durationSeconds],
    ]);
  }
  digest.add([
    for (final row in analysis.rows)
      [
        dayLapReferenceJson(row.reference),
        row.type.name,
        row.durationSeconds,
        row.referenceEligible,
        row.referenceIssue.name,
        row.offRoute,
      ],
  ]);
  digest.add([
    for (final lap in analysis.ranking?.eligibleLaps ?? const <DayLapRow>[])
      dayLapReferenceJson(lap.reference),
  ]);

  // The theoretical best of the group shown, with automatic segments.
  _begin(port, benchmarkSteps[2]);
  final job = _theoreticalBestJob(analysis, outingRuns(runs));
  final theoretical = isolates ? await Isolate.run(job) : job();
  _end(port, benchmarkSteps[2]);

  // The best lap against the next fastest of the group, as the comparison
  // page first draws it: axis, projections, map, Δ time and default charts.
  final eligible = [...dayEligibleLaps(analysis)]
    ..sort((x, y) => x.durationSeconds.compareTo(y.durationSeconds));
  LapComparison? comparison;
  DayLapRow? lapA, lapB;
  if (eligible.length >= 2) {
    _begin(port, benchmarkSteps[3]);
    lapA = eligible[0];
    lapB = eligible[1];
    final a = dayComparisonLap(runs, lapA), b = dayComparisonLap(runs, lapB);
    if (a != null && b != null) {
      comparison = LapComparison(a, b);
      final length = comparison.axisLengthMeters;
      digest.add([length, comparison.trace(0).length, comparison.trace(1).length]);
      digest.add([
        for (final slot in [0, 1]) comparison.overlayTrack(slot).length,
      ]);
      for (final points in [600, 300]) {
        digest.addSeries(comparison.deltaSeries(0, length, points));
        for (final channel in comparison.defaultChartChannels) {
          for (final slot in [0, 1]) {
            digest.addSeries(comparison.channelSeries(slot, channel, 0, length, points));
          }
        }
      }
      digest.add([for (final option in comparison.mapLayerOptions) option.id]);
    }
    _end(port, benchmarkSteps[3]);
  }

  // The Corner Analyzer of that pair on the theoretical best's segments:
  // every segment analysed with its heart rate, and the time losses.
  var segments = 0;
  if (comparison != null && comparison.axis.valid) {
    _begin(port, benchmarkSteps[4]);
    final analyzer = CornerAnalyzer.of(
      comparison,
      dayComparisonSegmentation(analysis, lapA!, lapB!, theoreticalBest: theoretical),
    );
    segments = analyzer.segments.length;
    for (final segment in analyzer.segments) {
      digest.addAnalysis(analyzer.analyze(segment.id));
      if (segment.endMeters != segment.startMeters) {
        final heart = analyzer.heartRate(segment.startMeters, segment.endMeters);
        digest.add([heart.valid, for (final lap in heart.laps) channelSummaryMap(lap.summary)]);
      }
    }
    final losses = analyzer.timeLosses();
    digest.add([losses.valid, losses.lapDeltaSeconds]);
    _end(port, benchmarkSteps[4]);
  }

  _begin(port, benchmarkSteps[5]);
  final channelsJob = _channelSummariesJob(analysis.rows, {
    for (final named in runs) named.run.id: named.run.telemetry,
  });
  final channels = isolates ? await Isolate.run(channelsJob) : channelsJob();
  _end(port, benchmarkSteps[5]);
  digest.addChannels(channels);

  _begin(port, benchmarkSteps[6]);
  final key = dayDecisionsKey(analysis);
  final report = dayReport(
    analysis: analysis,
    eventId: 'benchmark',
    runs: progressionRunInfo(runs),
    decisionsKey: key,
    theoretical: theoretical,
    theoreticalKey: key,
    channels: channels,
  );
  final reportJson = jsonEncode(_jsonSafe(report));
  _end(port, benchmarkSteps[6]);
  digest.add(reportJson);

  port.send((
    'done',
    {
      'files': imported.files,
      'sessions': runs.length,
      'alternativeSources': imported.alternatives,
      'samples': samples,
      'channelSamples': channelSamples,
      'laps': analysis.rows.where((row) => row.type == LapSectionType.lap).length,
      'eligibleLaps': eligible.length,
      'segments': theoretical.segments.length,
      'analyzerSegments': segments,
    },
    digest.hex,
  ));
}

/// JSON with every non-finite number written as a string.
Object? _jsonSafe(Object? value) => switch (value) {
  final double number when !number.isFinite => '$number',
  final Map<Object?, Object?> map => {
    for (final MapEntry(:key, :value) in map.entries) '$key': _jsonSafe(value),
  },
  final Iterable<Object?> list => [for (final item in list) _jsonSafe(item)],
  _ => value,
};

/// A running SHA-256 of results.
final class _Digest {
  final _sink = _BytesSink();
  late final _hash = sha256.startChunkedConversion(_sink);

  void add(Object? value) => _hash.add(utf8.encode('${jsonEncode(_jsonSafe(value))}\n'));

  void addSeries(ChartSeries series) => add([
    series.minimum,
    series.maximum,
    series.unit,
    series.reason,
    for (final segment in series.segments)
      [
        for (final point in segment) [point.x, point.y],
      ],
  ]);

  void addAnalysis(SegmentAnalysis? analysis) {
    if (analysis == null) return add(null);
    Object? metric(AnalyzerMetric? metric) => metric == null
        ? null
        : [
            for (final value in [metric.a, metric.b])
              [value.value, value.provenance, value.unavailableReason],
            metric.delta.value,
            metric.delta.unavailableReason,
          ];
    final speeds = analysis.speeds, corner = analysis.corner;
    final braking = analysis.braking, exit = analysis.exitEffects;
    add([
      analysis.segmentId,
      analysis.type,
      metric(analysis.sectorTime),
      for (final row in [speeds.entry, speeds.maximum, speeds.minimum, speeds.exit]) metric(row),
      if (corner != null)
        for (final row in [corner.entry, corner.apex, corner.minimum, corner.exit]) metric(row),
      if (braking != null)
        for (final row in [braking.point, braking.seconds, braking.peakDeceleration]) metric(row),
      if (exit != null) ...[metric(exit.pickup), metric(exit.exitSpeed)],
    ]);
  }

  void addChannels(DayChannelSummaries summaries) {
    Object? channel(RunChannel? channel) => channel == null
        ? null
        : [
            channel.channel,
            channel.unit,
            channelSummaryMap(channel.run),
            for (final section in channel.sections) channelSummaryMap(section.summary),
            [
              for (final point in channel.trace) [point?.time, point?.mean],
            ],
            [
              for (final cooling in channel.cooling)
                [
                  cooling.interval.startTime,
                  cooling.interval.endTime,
                  cooling.interval.startValue,
                  cooling.interval.endValue,
                  cooling.section?.lapNumber,
                ],
            ],
          ];
    add(summaries.error);
    for (final run in summaries.runs) {
      add([
        run.runId,
        run.unavailableReason,
        for (final entry in run.channels) channel(entry),
        channel(run.heartRate),
        for (final lap in run.laps)
          [lap.acceleration.strongG, lap.acceleration.channel, lap.acceleration.sampleCount],
      ]);
    }
  }

  String get hex {
    _hash.close();
    return _sink.value.toString();
  }
}

final class _BytesSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

// --- Command line. ---------------------------------------------------------

const _usage = '''
Measures the app's steps for one day of recordings: wall time, peak and
final resident set (RSS) and, when the VM service can run, heap use.

  dart run tool/day_benchmark.dart [options] <recording or folder>...
  dart run tool/day_benchmark.dart --synthetic=6 --laps=12

Options:
  --synthetic=N     write a synthetic day of N sessions to a temporary folder
                    and measure it (no recordings needed)
  --laps=N          laps per synthetic session (default 4)
  --rate=HZ         synthetic sample rate (default 20)
  --subfolders      include subfolders of the chosen folders
  --one-isolate     run every step on one isolate instead of in background
                    isolates as the app does (for profiling)
  --no-heap         do not start the VM service to sample the heap
  --json=FILE       also write the figures as JSON
  --runs=N          run the whole benchmark N times, each in a fresh isolate
                    (default 1)

For figures close to the phone's, compile it ahead of time first:
  dart compile exe tool/day_benchmark.dart -o /tmp/day_benchmark
(an AOT executable has no VM service, so the heap is not sampled).
''';

/// Parses [arguments], runs the benchmark and prints the figures; returns
/// the exit code.
Future<int> runBenchmarkCli(List<String> arguments, {StringSink? out}) async {
  out ??= stdout;
  final paths = <String>[];
  var synthetic = 0, laps = 4, runs = 1;
  var rate = 20.0;
  var subfolders = false, isolates = true, heap = true;
  String? json;
  for (final argument in arguments) {
    final value = argument.contains('=') ? argument.substring(argument.indexOf('=') + 1) : '';
    if (argument == '-h' || argument == '--help') {
      out.write(_usage);
      return 0;
    } else if (argument.startsWith('--synthetic=')) {
      synthetic = int.tryParse(value) ?? -1;
    } else if (argument.startsWith('--laps=')) {
      laps = int.tryParse(value) ?? -1;
    } else if (argument.startsWith('--rate=')) {
      rate = double.tryParse(value) ?? -1;
    } else if (argument.startsWith('--runs=')) {
      runs = int.tryParse(value) ?? -1;
    } else if (argument.startsWith('--json=')) {
      json = value;
    } else if (argument == '--subfolders') {
      subfolders = true;
    } else if (argument == '--one-isolate') {
      isolates = false;
    } else if (argument == '--no-heap') {
      heap = false;
    } else if (argument.startsWith('-')) {
      out.write('Unknown option $argument\n\n$_usage');
      return 64;
    } else {
      paths.add(argument);
    }
  }
  if (synthetic < 0 || synthetic > 64 || laps < 1 || laps > 200 || runs < 1 || rate <= 0) {
    out.write('Invalid number.\n\n$_usage');
    return 64;
  }
  if ((synthetic == 0) == paths.isEmpty) {
    out.write(_usage);
    return 64;
  }
  Directory? temporary;
  try {
    if (synthetic > 0) {
      temporary = Directory.systemTemp.createTempSync('fet_day_benchmark');
      writeSyntheticDay(temporary.path, sessions: synthetic, laps: laps, rateHz: rate);
      paths.add(temporary.path);
    }
    final results = <BenchmarkResult>[];
    for (var run = 1; run <= runs; ++run) {
      final result = await runDayBenchmark(
        BenchmarkOptions(
          paths: paths,
          includeSubfolders: subfolders,
          isolates: isolates,
          heap: heap,
        ),
      );
      results.add(result);
      if (runs > 1) out.writeln('Run $run of $runs');
      out.writeln(result.format());
    }
    if (json != null) {
      File(json)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(
          const JsonEncoder.withIndent('  ')
              .convert([for (final result in results) result.toJson()]),
        );
    }
    return 0;
  } on Object catch (error) {
    out.writeln('$error');
    return 1;
  } finally {
    temporary?.deleteSync(recursive: true);
  }
}
