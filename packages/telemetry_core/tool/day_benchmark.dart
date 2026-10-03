// Measures one day of recordings step by step (FET-41); see tool/README.md.
import 'dart:io';

import 'day_benchmark/benchmark.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runBenchmarkCli(arguments);
}
