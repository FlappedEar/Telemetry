import 'dart:math' as math;

/// A synthetic, undated recording driving a rounded rectangle (300 m by
/// 150 m, 30 m corners) counter-clockwise through a start line at the
/// origin, at 10 Hz: one lap per entry of [laps], each the speed (m/s) at a
/// distance along the lap. It has four corners and four straights, so the
/// day gets segments. No real data.
String rectangleVbo(List<double Function(double distance)> laps) {
  const lat0 = 52.0, lon0 = 21.0;
  const metersPerDegree = 6371000.0 * math.pi / 180.0;
  final cosLat = math.cos(lat0 * math.pi / 180.0);
  String coordinate(double east, double north) =>
      '${(lat0 + north / metersPerDegree).toStringAsFixed(8)} '
      '${(lon0 + east / (metersPerDegree * cosLat)).toStringAsFixed(8)}';
  const width = 300.0, height = 150.0, radius = 30.0;
  final outline = <(double, double)>[];
  void straight(double x0, double y0, double x1, double y1) {
    final length = math.sqrt(math.pow(x1 - x0, 2) + math.pow(y1 - y0, 2));
    final steps = (length / 0.5).round();
    for (var i = 0; i < steps; ++i) {
      outline.add((x0 + (x1 - x0) * i / steps, y0 + (y1 - y0) * i / steps));
    }
  }

  void corner(double cx, double cy, double from) {
    final steps = (math.pi / 2 * radius / 0.5).round();
    for (var i = 0; i < steps; ++i) {
      final a = from + math.pi / 2 * i / steps;
      outline.add((cx + radius * math.cos(a), cy + radius * math.sin(a)));
    }
  }

  const half = height / 2 - radius, left = -width + radius, right = -radius;
  straight(0, 0, 0, half);
  corner(right, half, 0);
  straight(right, height / 2, left, height / 2);
  corner(left, half, math.pi / 2);
  straight(-width, half, -width, -half);
  corner(left, -half, math.pi);
  straight(left, -height / 2, right, -height / 2);
  corner(right, -half, 3 * math.pi / 2);
  straight(0, -half, 0, 0);
  final perimeter = outline.length * 0.5;
  final gateA = coordinate(-10, 0).split(' '),
      gateB = coordinate(10, 0).split(' ');
  final rows = StringBuffer();
  var distance = -20.0, t = 0.0;
  while (distance < (laps.length + 0.3) * perimeter) {
    final lap = math.max(0, math.min(distance ~/ perimeter, laps.length - 1));
    final speed = laps[lap](distance - lap * perimeter);
    final wrapped = distance % perimeter;
    final index = (wrapped / 0.5).floor() % outline.length;
    final next = (index + 1) % outline.length;
    final fraction = wrapped / 0.5 - (wrapped / 0.5).floor();
    final east =
        outline[index].$1 + (outline[next].$1 - outline[index].$1) * fraction;
    final north =
        outline[index].$2 + (outline[next].$2 - outline[index].$2) * fraction;
    rows.writeln(
      '${t.toStringAsFixed(2)} ${coordinate(east, north)} '
      '${(speed * 3.6).toStringAsFixed(2)}',
    );
    distance += speed / 10;
    t += 0.1;
  }
  return '[header]\ncoordinate units = degrees\n[laptiming]\n'
      'Start ${gateA[1]} ${gateA[0]} ${gateB[1]} ${gateB[0]} start\n'
      '[column names]\ntime latitude longitude velocity\n[data]\n$rows';
}

/// A lap at [straight] m/s, slowed to [slow] m/s from [from] to [to] metres.
double Function(double) rectangleLap(
  double straight, [
  double from = 0,
  double to = 0,
  double slow = 0,
]) =>
    (d) => d >= from && d <= to ? slow : straight;
