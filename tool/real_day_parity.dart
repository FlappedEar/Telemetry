// Runs every check on a real day's recordings in one go (FET-55): the real
// tests of the app and of telemetry_core, and every parity check against
// FlappedEar Overlays' own C++ (each tool under
// packages/telemetry_core/tool/cpp_* is built, run over the day to write a
// local reference, and the Dart test compared with it). Prints one line per
// check: PASS, FAIL or SKIP, the number of tests and the time taken.
//
//   FET_REAL_DAY=<folder of one day's VBO and RCZ files> \
//   VBOOVERLAY_DIR=<FlappedEar/Overlay checkout> \
//   QT_PREFIX=<Qt 6.8 prefix> \
//     dart run tool/real_day_parity.dart [--verbose] [--keep] [--only=<name>,...]
//
// VBOOVERLAY_DIR defaults to /tmp/vbooverlay and QT_PREFIX to
// /opt/Qt/6.8.3/gcc_64, as in packages/telemetry_core/tool/README.md; without
// an Overlays checkout the parity checks are skipped. The C++ tools are built
// once into FET_PARITY_BUILD (default: <system temp>/fet-real-parity-build).
//
// Real recordings are private: nothing is written into the repository. The
// references and logs go to a temporary folder that is deleted at the end
// unless --keep is given (then it is printed; it holds derived real data, so
// never commit or share it). --verbose also prints the figures the tests
// print (counts and times; the coach's plan is text).
import 'dart:convert';
import 'dart:io';

final _root = File.fromUri(Platform.script).parent.parent.path;
final _core = '$_root/packages/telemetry_core';

/// The tool's output: summary lines only.
void _say(String line) => stdout.writeln(line);

final class _Check {
  _Check(
    this.name,
    this.package,
    this.test, {
    this.env = const {},
    this.tools = const [],
    this.prepare,
  });

  final String name;

  /// The package folder the test runs in.
  final String package;
  final String test;
  final Map<String, String> env;

  /// The C++ tools (folders of packages/telemetry_core/tool) it needs.
  final List<String> tools;

  /// Writes the check's reference; returns an error or null.
  final Future<String?> Function(_Context context)? prepare;

  bool get flutter => package == _root;
}

final class _Context {
  _Context(this.work, this.build, this.verbose);

  final Directory work;
  final String build;
  final bool verbose;
  int _logs = 0;

  String tool(String name) => '$build/$name/$name';

  /// Runs [executable]; its output goes to a log in [work] only.
  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String> environment = const {},
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: {'LC_ALL': 'C.UTF-8', ...environment},
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    File('${work.path}/log-${++_logs}.txt').writeAsStringSync(
      '\$ $executable ${arguments.join(' ')}\n${result.stdout}\n${result.stderr}',
    );
    return result;
  }

  /// Runs [executable] writing its standard output to [output].
  Future<String?> runTo(
    String output,
    String executable,
    List<String> arguments, {
    Map<String, String> environment = const {},
  }) async {
    final result = await run(
      executable,
      arguments,
      workingDirectory: _core,
      environment: environment,
    );
    if (result.exitCode != 0) {
      return '${executable.split('/').last} exited ${result.exitCode}';
    }
    File(output).writeAsStringSync(result.stdout as String);
    return null;
  }
}

String _env(String name, String fallback) {
  final value = Platform.environment[name];
  return value == null || value.isEmpty ? fallback : value;
}

Future<void> main(List<String> arguments) async {
  final verbose = arguments.contains('--verbose');
  final keep = arguments.contains('--keep');
  final only = {
    for (final argument in arguments)
      if (argument.startsWith('--only=')) ...argument.substring(7).split(','),
  };
  final day = Platform.environment['FET_REAL_DAY'] ?? '';
  if (day.isEmpty || !Directory(day).existsSync()) {
    stderr.writeln(
      'Set FET_REAL_DAY to a folder of one day\'s VBO and RCZ recordings.',
    );
    exit(64);
  }
  final overlays = _env('VBOOVERLAY_DIR', '/tmp/vbooverlay');
  final qt = _env('QT_PREFIX', '/opt/Qt/6.8.3/gcc_64');
  final build = _env(
    'FET_PARITY_BUILD',
    '${Directory.systemTemp.path}/fet-real-parity-build',
  );
  final haveOverlays = File('$overlays/native/src/app/TelemetryController.cpp')
      .existsSync();

  final recordings = [
    for (final entity in Directory(day).listSync())
      if (entity is File &&
          RegExp(r'\.(vbo|rcz)$', caseSensitive: false).hasMatch(entity.path))
        entity.absolute.path,
  ]..sort();
  final vbos = [
    for (final path in recordings)
      if (path.toLowerCase().endsWith('.vbo')) path,
  ];
  final rczs = [
    for (final path in recordings)
      if (path.toLowerCase().endsWith('.rcz')) path,
  ];
  final dayPath = Directory(day).absolute.path;

  final work = Directory.systemTemp.createTempSync('fet-real-parity');
  final context = _Context(work, build, verbose);
  String reference(String name) => '${work.path}/$name.json';

  // A parity check whose C++ tool writes a reference over the day's VBOs.
  _Check dump(String name, String tool, String test, String prefix) => _Check(
    name,
    _core,
    'test/parity/$test',
    tools: [tool],
    env: {
      '${prefix}_REFERENCE': reference(tool),
      '${prefix}_DIRS': dayPath,
      'FET_PARITY_REPORT': '1',
    },
    prepare: (context) async {
      final result = await context.run(context.tool(tool), [
        reference(tool),
        ...vbos,
      ], workingDirectory: _core);
      return result.exitCode == 0 ? null : '$tool exited ${result.exitCode}';
    },
  );

  final checks = <_Check>[
    for (final (index, vbo) in vbos.indexed)
      _Check(
        'real VBO ${index + 1}/${vbos.length}',
        _core,
        'test/real_vbo_test.dart',
        env: {'FLAPPEDEAR_REAL_VBO': vbo},
      ),
    for (final (index, rcz) in rczs.indexed)
      _Check(
        'real RCZ ${index + 1}/${rczs.length}',
        _core,
        'test/rcz/rcz_parser_test.dart',
        env: {'FLAPPEDEAR_REAL_RCZ': rcz},
      ),
    _Check(
      'coach on the day',
      _core,
      'test/day/real_day_coach_test.dart',
      env: {'FLAPPEDEAR_REAL_DAY': dayPath},
    ),
    _Check(
      'track day rehearsal (app)',
      _root,
      'test/real/track_day_rehearsal_test.dart',
      env: {'FLAPPEDEAR_REAL_DAY': dayPath},
    ),
    _Check(
      'fusion in the day (app)',
      _root,
      'test/day/fusion_real_test.dart',
      env: {'FET_FUSION_DAY': dayPath},
    ),
    _Check(
      'fusion parity',
      _core,
      'test/fusion/real_fusion_test.dart',
      tools: ['cpp_fusion_dump'],
      env: {
        'FET_FUSION_DAY': dayPath,
        'FET_FUSION_REFERENCE': reference('fusion'),
      },
      prepare: (context) async {
        final pairs = '${work.path}/pairs.json';
        final listed = await context.run(
          'dart',
          ['test', 'test/fusion/real_fusion_test.dart'],
          workingDirectory: _core,
          environment: {
            'FET_FUSION_DAY': dayPath,
            'FET_FUSION_PAIRS_OUT': pairs,
          },
        );
        if (listed.exitCode != 0 || !File(pairs).existsSync()) {
          return 'listing the pairs failed';
        }
        final result = await context.run(
          context.tool('cpp_fusion_dump'),
          ['--pairs', pairs, reference('fusion')],
          environment: {'GLIBC_TUNABLES': 'glibc.cpu.hwcaps=-AVX2,-FMA'},
        );
        return result.exitCode == 0
            ? null
            : 'cpp_fusion_dump exited ${result.exitCode}';
      },
    ),
    _Check(
      'fingerprint parity',
      _core,
      'test/parity/fingerprint_parity_test.dart',
      tools: ['cpp_project_roundtrip'],
      env: {
        'FET_FINGERPRINT_REFERENCE': reference('fingerprint'),
        'FET_PARITY_REPORT': '1',
      },
      prepare: (context) => context.runTo(
        reference('fingerprint'),
        context.tool('cpp_project_roundtrip'),
        ['fingerprint', ...recordings],
      ),
    ),
    dump(
      'segments parity',
      'cpp_segments_dump',
      'segments_parity_test.dart',
      'FET_SEGMENTS',
    ),
    dump(
      'segment editing parity',
      'cpp_segment_editing_dump',
      'segment_editing_parity_test.dart',
      'FET_EDITING',
    ),
    dump(
      'theoretical best parity',
      'cpp_theoretical_best_dump',
      'theoretical_best_parity_test.dart',
      'FET_TB',
    ),
    dump(
      'corner metrics parity',
      'cpp_corner_metrics_dump',
      'corner_metrics_parity_test.dart',
      'FET_CORNER',
    ),
    dump(
      'progression parity',
      'cpp_progression_dump',
      'progression_parity_test.dart',
      'FET_PROGRESSION',
    ),
    dump(
      'day report parity',
      'cpp_dayreport_dump',
      'dayreport_parity_test.dart',
      'FET_DAYREPORT',
    ),
    dump(
      'comparison parity',
      'cpp_comparison_dump',
      'comparison_parity_test.dart',
      'FET_COMPARISON',
    ),
    dump(
      'corner analyzer parity',
      'cpp_corner_analyzer_dump',
      'corner_analyzer_parity_test.dart',
      'FET_ANALYZER',
    ),
    dump(
      'driving parity',
      'cpp_driving_dump',
      'driving_parity_test.dart',
      'FET_DRIVING',
    ),
    for (final extension in ['.vbo', '.rcz'])
      _Check(
        'Overlays round trip (${extension.substring(1).toUpperCase()})',
        _core,
        'test/day/overlays_roundtrip_test.dart',
        tools: ['cpp_project_roundtrip'],
        env: {
          'FLAPPEDEAR_OVERLAYS_ROUNDTRIP': context.tool(
            'cpp_project_roundtrip',
          ),
          'FET_ROUNDTRIP_RECORDINGS': dayPath,
          'FET_ROUNDTRIP_EXTENSION': extension,
          'FET_PARITY_REPORT': '1',
        },
      ),
    _Check(
      'Overlays fusion round trip',
      _core,
      'test/day/overlays_fusion_roundtrip_test.dart',
      tools: ['cpp_project_roundtrip'],
      env: {
        'FLAPPEDEAR_OVERLAYS_ROUNDTRIP': context.tool('cpp_project_roundtrip'),
        'FET_FUSION_ROUNDTRIP_DAY': dayPath,
      },
    ),
  ];

  _say('Real day: ${vbos.length} VBO, ${rczs.length} RCZ recording(s)');
  if (!haveOverlays) {
    _say(
      'No FlappedEar/Overlay checkout at VBOOVERLAY_DIR: parity checks are skipped.',
    );
  }
  final built = <String, String?>{};
  Future<String?> buildTool(String tool) async =>
      built[tool] ??= await () async {
        final source = '$_core/tool/$tool';
        final configure = await context.run('cmake', [
          '-S', source, '-B', '$build/$tool', '-DCMAKE_BUILD_TYPE=Release', //
          '-DVBOOVERLAY_DIR=$overlays', '-DCMAKE_PREFIX_PATH=$qt',
        ]);
        if (configure.exitCode != 0) return 'configuring $tool failed';
        final compile = await context.run('cmake', [
          '--build',
          '$build/$tool',
          '-j${Platform.numberOfProcessors}',
        ]);
        return compile.exitCode == 0 ? null : 'building $tool failed';
      }();

  var passed = 0, failed = 0, skipped = 0;
  for (final check in checks) {
    if (only.isNotEmpty && !only.any((name) => check.name.contains(name))) {
      continue;
    }
    final clock = Stopwatch()..start();
    String line(String status, String detail) =>
        '${status.padRight(4)}  ${check.name.padRight(34)} $detail (${(clock.elapsedMilliseconds / 1000).toStringAsFixed(1)} s)';
    if (check.tools.isNotEmpty && !haveOverlays) {
      ++skipped;
      _say(line('SKIP', 'needs the Overlays checkout'));
      continue;
    }
    String? error;
    for (final tool in check.tools) {
      error ??= await buildTool(tool);
    }
    if (error == null && check.prepare != null) {
      error = await check.prepare!(context);
    }
    if (error != null) {
      ++failed;
      _say(line('FAIL', error));
      continue;
    }
    final outcome = await _runTest(context, check);
    if (outcome.failed > 0 || !outcome.success) {
      ++failed;
      _say(line('FAIL', outcome.counts));
    } else if (outcome.passed == 0) {
      ++skipped;
      _say(line('SKIP', outcome.counts));
    } else {
      ++passed;
      _say(line('PASS', outcome.counts));
    }
    if (verbose) {
      for (final message in outcome.prints) {
        _say('      $message');
      }
    }
  }
  _say('Summary: $passed passed, $failed failed, $skipped skipped');
  if (keep) {
    _say('References and logs (private, never commit): ${work.path}');
  } else {
    work.deleteSync(recursive: true);
    if (failed > 0) _say('Run again with --keep to read the logs.');
  }
  exit(failed == 0 ? 0 : 1);
}

final class _Outcome {
  int passed = 0, failed = 0, skipped = 0;
  bool success = false;
  final List<String> prints = [];

  String get counts => '$passed passed, $failed failed, $skipped skipped';
}

/// Runs [check]'s test with the JSON reporter and counts the results.
Future<_Outcome> _runTest(_Context context, _Check check) async {
  final result = await context.run(
    check.flutter ? 'flutter' : 'dart',
    ['test', '--reporter', 'json', check.test],
    workingDirectory: check.package,
    environment: check.env,
  );
  final outcome = _Outcome();
  final hidden = <int>{};
  for (final line in LineSplitter.split(result.stdout as String)) {
    if (!line.startsWith('{')) continue;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    switch (decoded['type']) {
      case 'testStart':
        final test = decoded['test'] as Map<String, Object?>;
        if (test['url'] == null) hidden.add(test['id'] as int);
      case 'testDone':
        if (decoded['hidden'] == true || hidden.contains(decoded['testID'])) {
          if (decoded['result'] != 'success') ++outcome.failed;
          continue;
        }
        if (decoded['skipped'] == true) {
          ++outcome.skipped;
        } else if (decoded['result'] == 'success') {
          ++outcome.passed;
        } else {
          ++outcome.failed;
        }
      case 'print':
        if (decoded['messageType'] == 'print') {
          outcome.prints.add(decoded['message'] as String);
        }
      case 'done':
        outcome.success = decoded['success'] == true;
    }
  }
  return outcome;
}
