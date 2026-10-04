import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/l10n.dart';

/// [path]'s source with adjacent string literals joined, so a text split
/// over lines reads as written.
String _source(String path) =>
    File(path)
        .readAsStringSync()
        .replaceAll(RegExp(r'''['"]\s*\n\s*['"]'''), '');

void main() {
  final english = lookupAppLocalizations(const Locale('en'));
  final polish = lookupAppLocalizations(const Locale('pl'));

  test('the import page translates the errors and notes of an import', () {
    // Each text as its source writes it, and one such text as shown. A
    // reworded text fails here instead of showing English in Polish.
    const runner = 'lib/import/import_runner.dart';
    const controller = 'lib/import/day_import_controller.dart';
    const scan = 'packages/telemetry_core/lib/src/intake/folder_scan.dart';
    const plan = 'packages/telemetry_core/lib/src/intake/import_plan.dart';
    final texts = <(String, String, String)>[
      (controller, "'The import failed: \$error'", 'The import failed: boom'),
      (controller, "'No recording could be imported.'", ''),
      (runner, "error ?? 'Import failed.'", 'Import failed.'),
      (
        runner,
        "StateError('The import stopped unexpectedly.')",
        'Bad state: The import stopped unexpectedly.',
      ),
      (
        runner,
        "'\$name: same content as \${names[file.runId]}; imported once.'",
        'b.vbo: same content as a.vbo; imported once.',
      ),
      (
        runner,
        "'\${names[run.id]}: the same drive as \${names[primary]}; kept as its "
            "alternative source.'",
        'a.rcz: the same drive as a.vbo; kept as its alternative source.',
      ),
      (scan, "'The folder does not exist or is not a folder.'", ''),
      (scan, "'Choose the folder itself, not a link to it.'", ''),
      (
        scan,
        "'The folder holds \${files.length} recordings; import at most "
            "\${limits.maximumFiles} at a time. Choose a smaller folder.'",
        'The folder holds 501 recordings; import at most 500 at a time. '
            'Choose a smaller folder.',
      ),
      (
        scan,
        "'Stopped after \${limits.maximumEntries} files and folders; "
            "recordings beyond that were not scanned.'",
        'Stopped after 10000 files and folders; recordings beyond that were '
            'not scanned.',
      ),
      (
        scan,
        "'\$tooDeep folder(s) deeper than \${limits.maximumDepth} levels were "
            "not scanned.'",
        'day: 2 folder(s) deeper than 8 levels were not scanned.',
      ),
      (
        scan,
        "'\$links link(s) were not followed.'",
        'day: 3 link(s) were not followed.',
      ),
      (
        scan,
        "'\$others other file(s) were ignored; only VBO and RCZ recordings are "
            "imported.'",
        'day: 4 other file(s) were ignored; only VBO and RCZ recordings are '
            'imported.',
      ),
      (
        scan,
        "'No VBO or RCZ recordings were found\${includeSubfolders ? '' : ' "
            "(subfolders were not included)'}.'",
        'No VBO or RCZ recordings were found.',
      ),
      (
        scan,
        "'No VBO or RCZ recordings were found\${includeSubfolders ? '' : ' "
            "(subfolders were not included)'}.'",
        'day: No VBO or RCZ recordings were found (subfolders were not '
            'included).',
      ),
      (
        scan,
        "'That is \${files.length} recordings; import at most "
            "\${limits.maximumFiles} at a time.'",
        'That is 600 recordings; import at most 500 at a time.',
      ),
      (scan, "'No VBO or RCZ recordings to import.'", ''),
      (
        scan,
        "'\$name: not found; not imported.'",
        'a.vbo: not found; not imported.',
      ),
      (
        scan,
        "'\$name: a macOS metadata file, not a recording; not imported.'",
        '._a.vbo: a macOS metadata file, not a recording; not imported.',
      ),
      (scan, "'\$name: a link; not followed.'", 'a.vbo: a link; not followed.'),
      (
        scan,
        "'\$name: not a VBO or RCZ recording; not imported.'",
        'notes.txt: not a VBO or RCZ recording; not imported.',
      ),
      (
        plan,
        "'Choose a VBO or RaceChrono RCZ telemetry file.'",
        'a.vbo: Choose a VBO or RaceChrono RCZ telemetry file.',
      ),
      (
        plan,
        "'Telemetry source is not an existing regular file.'",
        'a.vbo: Telemetry source is not an existing regular file.',
      ),
      (
        plan,
        "'Too many files in one import; select a smaller batch.'",
        'a.vbo: Too many files in one import; select a smaller batch.',
      ),
      (
        plan,
        "'Telemetry source path is too long.'",
        'a.vbo: Telemetry source path is too long.',
      ),
      (
        plan,
        "'Telemetry file is empty or exceeds the per-file import limit.'",
        'a.vbo: Telemetry file is empty or exceeds the per-file import limit.',
      ),
      (
        plan,
        "'Batch input-byte limit exceeded; import fewer recordings.'",
        'a.vbo: Batch input-byte limit exceeded; import fewer recordings.',
      ),
      (
        plan,
        "'Identical file content already present in this batch.'",
        'a.vbo: Identical file content already present in this batch.',
      ),
      (
        plan,
        "'Telemetry source changed during import; retry with a stable file.'",
        'a.vbo: Telemetry source changed during import; retry with a stable file.',
      ),
      (
        plan,
        "'Telemetry source has an invalid time range.'",
        'a.vbo: Telemetry source has an invalid time range.',
      ),
      (
        plan,
        "'Telemetry source has mismatched channel timestamps and values.'",
        'a.vbo: Telemetry source has mismatched channel timestamps and values.',
      ),
      (
        plan,
        "'Batch decoded-sample limit exceeded; import fewer recordings.'",
        'a.vbo: Batch decoded-sample limit exceeded; import fewer recordings.',
      ),
      (
        plan,
        "'Source grouping exceeds the import limit.'",
        'a.vbo: Source grouping exceeds the import limit.',
      ),
    ];
    final sources = <String, String>{};
    for (final (path, literal, sample) in texts) {
      final source = sources[path] ??= _source(path);
      expect(source, contains(literal), reason: path);
      final shown = sample.isEmpty
          ? literal.substring(1, literal.length - 1)
          : sample;
      expect(english.coreText(shown), shown);
      expect(polish.coreText(shown), isNot(shown), reason: shown);
    }
    expect(
      polish.coreText('The import failed: Import failed.'),
      'Import nie powiódł się: Import nie powiódł się.',
    );
    expect(
      polish.coreText('a: b.vbo: not found; not imported.'),
      'a: b.vbo: nie znaleziono; nie zaimportowano.',
    );
    // Adding to a day words it apart, with the session's name translated;
    // not half translated as an import's note.
    const appended =
        'a.rcz: the same drive as Session 2 in the other format; kept as its '
        'alternative source.';
    expect(english.coreText(appended), appended);
    expect(
      polish.coreText(appended),
      'a.rcz: ten sam przejazd co Sesja 2 w drugim formacie; zachowano jako '
      'jego alternatywne źródło.',
    );
    expect(
      polish.coreText('broken.vbo: Unsupported format'),
      'broken.vbo: Unsupported format',
    );
  });
}
