import 'dart:math' as math;

/// A synthetic, undated VBO recording driving a 100 m circle through a start
/// line, one lap per speed (m/s), at 10 Hz. No real data.
String circuitVbo(List<double> speeds) {
  const lat0 = 52.0, lon0 = 21.0;
  const metersPerDegree = 6371000.0 * math.pi / 180.0;
  final cosLat = math.cos(lat0 * math.pi / 180.0);
  String coordinate(double east, double north) =>
      '${(lat0 + north / metersPerDegree).toStringAsFixed(8)} '
      '${(lon0 + east / (metersPerDegree * cosLat)).toStringAsFixed(8)}';
  final gateA = coordinate(-10, 0).split(' '), gateB = coordinate(10, 0).split(' ');
  final rows = StringBuffer();
  var travelled = 0.0, t = 0.0;
  final total = (speeds.length + 0.5) * 2 * math.pi;
  while (travelled < total) {
    final lap = math.min(travelled ~/ (2 * math.pi), speeds.length - 1);
    final a = -0.25 + travelled;
    rows.writeln(
      '${t.toStringAsFixed(2)} ${coordinate(-100 + 100 * math.cos(a), 100 * math.sin(a))} '
      '${(speeds[lap] * 3.6 * (0.8 + 0.2 * math.cos(2 * a))).toStringAsFixed(2)}',
    );
    travelled += speeds[lap] / 10 / 100;
    t += 0.1;
  }
  return '[header]\ncoordinate units = degrees\n[laptiming]\n'
      'Start ${gateA[1]} ${gateA[0]} ${gateB[1]} ${gateB[0]} start\n'
      '[column names]\ntime latitude longitude velocity\n[data]\n$rows';
}
