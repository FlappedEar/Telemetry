import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import 'support/sessions.dart';

void main() {
  test('stops a parse deterministically', () {
    final text = StringBuffer('[column names]\ntime speed\n[data]\n');
    for (var row = 0; row < 10000; ++row) {
      text.write('$row ${row % 200}\n');
    }
    var checks = 0;
    expect(
      () => parse(text.toString(), cancelled: () => ++checks == 4),
      throwsA(isA<OperationCancelled>()),
    );
    expect(checks, greaterThanOrEqualTo(4));
  });

  final beforeLimits = {
    'too many lines': '\n' * VboLimits.maximumLines,
    'oversized line': 'x' * (VboLimits.maximumLineCharacters + 1),
    'oversized field':
        '[column names]\ntime,speed\n[data]\n0,${'x' * (VboLimits.maximumFieldCharacters + 1)}',
    'too many comma columns': '[column names]\n${',' * 200000}\n[data]\n0',
  };
  beforeLimits.forEach((name, source) {
    test('cancellation wins over a limit error: $name', () {
      var checks = 0;
      expect(
        () => parse(source, cancelled: () => ++checks == 4),
        throwsA(isA<OperationCancelled>()),
      );
      expect(checks, 4);
    });
  });

  test('can stop at every checkpoint of a successful parse', () {
    final source = '[column names]\ntime,\nspeed\n[data]\n0,42${',' * 16384}';
    var total = 0;
    expect(
      parse(
        source,
        cancelled: () {
          ++total;
          return false;
        },
      ).sampleCount,
      1,
    );
    for (var stopAt = 1; stopAt <= total; ++stopAt) {
      var checks = 0;
      expect(
        () => parse(source, cancelled: () => ++checks == stopAt),
        throwsA(isA<OperationCancelled>()),
      );
      expect(checks, stopAt);
    }
  });

  test('stops lap detection', () {
    final session = parse(fixture('event-laps.vbo'));
    expect(
      () => deriveSourceLapSession(session, cancelled: () => true),
      throwsA(isA<OperationCancelled>()),
    );
  });
}
