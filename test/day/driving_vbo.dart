import 'dart:math' as math;

/// [vbo] (a [rectangleVbo] recording) with longitudinal and lateral G
/// added as `longacc` and `latacc` columns, derived from its speed and the
/// heading change between neighbouring positions: + accelerating and + to
/// the left, as RaceChrono records them. With [liftOff], the 15 % part
/// throttle of a recording with pedals becomes 3 %, so it coasts at a
/// steady speed. No real data.
String withAcceleration(String vbo, {bool liftOff = false}) {
  final lines = vbo.split('\n');
  final columns = lines.indexOf('[column names]') + 1;
  final data = lines.indexOf('[data]') + 1;
  lines[columns] = '${lines[columns]} longacc latacc';
  final throttle = lines[columns].split(' ').indexOf('throttle');
  final rows = [
    for (var i = data; i < lines.length; ++i)
      if (lines[i].trim().isNotEmpty) lines[i].split(' '),
  ];
  if (liftOff && throttle >= 0) {
    for (final row in rows) {
      if (row[throttle] == '15.0') row[throttle] = '3.0';
    }
  }
  const metersPerDegree = 6371000.0 * math.pi / 180.0;
  final cosLat = math.cos(52.0 * math.pi / 180.0);
  double time(int i) => double.parse(rows[i][0]);
  double north(int i) => double.parse(rows[i][1]) * metersPerDegree;
  double east(int i) => double.parse(rows[i][2]) * metersPerDegree * cosLat;
  double speed(int i) => double.parse(rows[i][3]) / 3.6;
  double heading(int i) {
    final a = math.max(0, i - 1), b = math.min(rows.length - 1, i + 1);
    return math.atan2(north(b) - north(a), east(b) - east(a));
  }

  final out = lines.sublist(0, data);
  for (var i = 0; i < rows.length; ++i) {
    final a = math.max(0, i - 1), b = math.min(rows.length - 1, i + 1);
    final span = time(b) - time(a);
    var turn = heading(b) - heading(a);
    turn = (turn + math.pi) % (2 * math.pi) - math.pi;
    final longitudinal = span > 0 ? (speed(b) - speed(a)) / span / 9.81 : 0.0;
    final lateral = span > 0 ? speed(i) * turn / span / 9.81 : 0.0;
    out.add(
      '${rows[i].join(' ')} ${longitudinal.toStringAsFixed(3)} '
      '${lateral.toStringAsFixed(3)}',
    );
  }
  return '${out.join('\n')}\n';
}
