import 'dart:math' as math;

/// A made-up track day for the user guide's screenshots: three sessions on
/// an invented 2 km circuit, written as RaceChrono-style VBO text. The
/// speeds come from a simple grip and power model, so laps, corners,
/// braking, coasting and G look like a real day. No real data.
///
/// Returns file name to VBO text.
Map<String, String> demoDay() => {
  'Session 1.vbo': _session(
    start: (10, 05),
    laps: [0.90, 0.95, 0.97, 0.96, 0.98],
    coast: [false, true, true, false, true],
  ),
  'Session 2.vbo': _session(
    start: (11, 40),
    laps: [0.97, 0.99, 1.00, 0.985, 0.99, 1.0],
    coast: [true, false, false, true, false, false],
  ),
  'Session 3.vbo': _session(
    start: (14, 20),
    laps: [0.985, 1.01, 0.995, 1.005],
    coast: [false, false, true, false],
  ),
};

const _lat0 = 52.0, _lon0 = 21.0;
const _metersPerDegree = 6371000.0 * math.pi / 180.0;
const _step = 0.5; // metres between outline points
const _hz = 20;

/// Control points (east, north) in metres of a closed, clockwise circuit
/// whose start line is at the first point, on the main straight.
const _controls = <(double, double)>[
  (0, 0),
  (0, 220),
  (10, 330),
  (60, 380),
  (140, 370),
  (190, 320),
  (230, 300),
  (290, 320),
  (340, 380),
  (420, 400),
  (480, 360),
  (490, 280),
  (440, 200),
  (430, 120),
  (470, 40),
  (460, -60),
  (390, -110),
  (300, -100),
  (240, -40),
  (170, -40),
  (110, -110),
  (50, -140),
  (8, -110),
  (0, -40),
];

List<(double, double)>? _cachedOutline;

/// The circuit as points [_step] metres apart (centripetal Catmull-Rom).
List<(double, double)> _outline() {
  if (_cachedOutline != null) return _cachedOutline!;
  final dense = <(double, double)>[];
  final n = _controls.length;
  for (var i = 0; i < n; ++i) {
    final p0 = _controls[(i - 1 + n) % n], p1 = _controls[i];
    final p2 = _controls[(i + 1) % n], p3 = _controls[(i + 2) % n];
    for (var s = 0; s < 200; ++s) {
      final t = s / 200, t2 = t * t, t3 = t2 * t;
      double c(double a, double b, double c, double d) =>
          0.5 *
          (2 * b +
              (-a + c) * t +
              (2 * a - 5 * b + 4 * c - d) * t2 +
              (-a + 3 * b - 3 * c + d) * t3);
      dense.add((c(p0.$1, p1.$1, p2.$1, p3.$1), c(p0.$2, p1.$2, p2.$2, p3.$2)));
    }
  }
  // Resample at an even spacing.
  final out = <(double, double)>[dense.first];
  var carry = 0.0;
  for (var i = 1; i <= dense.length; ++i) {
    var a = dense[i - 1];
    final b = dense[i % dense.length];
    var length = _distance(a, b);
    while (carry + length >= _step) {
      final f = (_step - carry) / length;
      a = (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f);
      out.add(a);
      length = _distance(a, b);
      carry = 0;
    }
    carry += length;
  }
  return _cachedOutline = out;
}

double _distance((double, double) a, (double, double) b) =>
    math.sqrt(math.pow(b.$1 - a.$1, 2) + math.pow(b.$2 - a.$2, 2));

/// Signed curvature (1/m, + turning left) at each outline point, smoothed.
List<double> _curvature(List<(double, double)> p) {
  final n = p.length;
  const span = 20; // points either side
  final raw = List<double>.generate(n, (i) {
    final a = p[(i - span + n) % n], b = p[i], c = p[(i + span) % n];
    final cross = (b.$1 - a.$1) * (c.$2 - b.$2) - (b.$2 - a.$2) * (c.$1 - b.$1);
    final ab = _distance(a, b), bc = _distance(b, c), ac = _distance(a, c);
    return 2 * cross / (ab * bc * ac);
  });
  const half = 30;
  return List<double>.generate(n, (i) {
    var sum = 0.0;
    for (var j = -half; j <= half; ++j) {
      sum += raw[(i + j + n) % n];
    }
    return sum / (2 * half + 1);
  });
}

/// Speed (m/s) at each outline point for a lap at [pace] (1 = the most
/// grip). Braking and acceleration share the grip with cornering, so the
/// G-G diagram comes out round. With [coast], the driver lifts before
/// braking and brakes a little less hard.
List<double> _speeds(
  List<double> curvature,
  double pace, {
  bool coast = false,
  double phase = 0,
}) {
  final n = curvature.length;
  // Grip varies a little around the lap, differently on every lap, so each
  // lap is quickest somewhere else.
  final grip = List<double>.generate(
    n,
    (i) => 13.5 * pace * (1 + 0.05 * math.sin(i * _step / 160 + phase)),
  );
  final v = List<double>.generate(n, (i) {
    final k = curvature[i].abs();
    return math.min(52.0, k < 1e-6 ? 52.0 : math.sqrt(grip[i] / k));
  });
  // The share of grip left for braking or accelerating at speed [speed].
  double left(int i, double speed) {
    final lateral = speed * speed * curvature[i].abs() / grip[i];
    return math.sqrt(math.max(0.12, 1 - lateral * lateral));
  }

  final brake = 12.0 * pace, power = 7.0 * pace;
  // Three passes around the loop so the start line joins up.
  for (var pass = 0; pass < 3; ++pass) {
    for (var i = 1; i <= n; ++i) {
      final prev = v[(i - 1) % n];
      final rate = power * (1 - prev / 58.0) * left((i - 1) % n, prev);
      final limit = math.sqrt(prev * prev + 2 * rate * _step);
      if (v[i % n] > limit) v[i % n] = limit;
    }
    for (var i = n - 2; i >= -1; --i) {
      final next = v[(i + 1 + n) % n];
      final rate = brake * left((i + 1 + n) % n, next);
      final limit = math.sqrt(next * next + 2 * rate * _step);
      if (v[(i + n) % n] > limit) v[(i + n) % n] = limit;
    }
  }
  if (coast) {
    // Lift off 40 m before each braking point, slowing at 0.25 g.
    final starts = [
      for (var i = 0; i < n; ++i)
        if (v[(i + 1) % n] < v[i] - 0.01 && v[i] >= v[(i - 1 + n) % n]) i,
    ];
    for (final start in starts) {
      for (var j = 1; j <= 80; ++j) {
        final i = (start - j + n) % n, next = (i + 1) % n;
        final limit = math.sqrt(v[next] * v[next] + 2 * 2.5 * _step);
        if (v[i] <= limit) break;
        v[i] = limit;
      }
    }
  }
  return v;
}

String _session({
  required (int, int) start,
  required List<double> laps,
  required List<bool> coast,
}) {
  final outline = _outline();
  final curvature = _curvature(outline);
  final n = outline.length;
  final perimeter = n * _step;
  final profiles = [
    for (var i = 0; i < laps.length; ++i)
      _speeds(curvature, laps[i], coast: coast[i], phase: i * 2.3 + start.$2),
  ];
  // Out lap and in lap at a gentle pace.
  final easy = _speeds(curvature, 0.7);
  final cosLat = math.cos(_lat0 * math.pi / 180.0);
  // RaceChrono Pro 10.2.4 writes arc-minutes.
  String coordinate(double east, double north) =>
      '+${((_lat0 + north / _metersPerDegree) * 60).toStringAsFixed(6)} '
      '+${((_lon0 + east / (_metersPerDegree * cosLat)) * 60).toStringAsFixed(6)}';

  // From the pit exit (before the line) to the pit entry on the in lap.
  const pitExit = -260.0;
  final end = laps.length * perimeter + 420;
  double speedAt(double d) {
    final lap = (d / perimeter).floor(); // -1 = out lap
    final index = ((d % perimeter) / _step).floor() % n;
    if (lap < 0) return math.min(easy[index], 8 + (d - pitExit) * 0.15);
    if (lap >= laps.length) {
      return math.max(6.0, math.min(easy[index], 6 + (end - d) * 0.12));
    }
    return profiles[lap][index];
  }

  final rows = StringBuffer();
  var d = pitExit, t = 0.0, previous = speedAt(pitExit);
  final startSeconds = start.$1 * 3600.0 + start.$2 * 60.0;
  final random = math.Random(start.$1 * 60 + start.$2);
  while (d < end) {
    final v = speedAt(d);
    final wrapped = d % perimeter;
    final i = (wrapped / _step).floor() % n;
    final j = (i + 1) % n;
    final f = wrapped / _step - (wrapped / _step).floor();
    // A little lateral wander so lines differ from lap to lap.
    final lapIndex = (d / perimeter).floor();
    final wander = 1.2 * math.sin(d / 37.0 + lapIndex * 1.7);
    final dx = outline[j].$1 - outline[i].$1,
        dy = outline[j].$2 - outline[i].$2;
    final norm = math.max(1e-9, math.sqrt(dx * dx + dy * dy));
    final east = outline[i].$1 + dx * f - dy / norm * wander;
    final north = outline[i].$2 + dy * f + dx / norm * wander;
    final along = (v - previous) * _hz / 9.81;
    final lateral = v * v * curvature[i] / 9.81;
    final inLap = lapIndex < 0 || lapIndex >= laps.length;
    final coasting = !inLap && coast[lapIndex] && along < -0.05 && along > -0.4;
    final brakePct = along < -0.4 || (along < -0.15 && !coasting)
        ? math.min(100.0, -along * 75)
        : 0.0;
    final throttlePct = along < -0.05
        ? 0.0
        : (along > 0.12 ? (inLap ? 45.0 : 100.0) : 28.0);
    final clock = startSeconds + t;
    final hh = (clock ~/ 3600).toString().padLeft(2, '0');
    final mm = ((clock % 3600) ~/ 60).toString().padLeft(2, '0');
    final ss = (clock % 60).toStringAsFixed(2).padLeft(5, '0');
    final heading = (math.atan2(dx, dy) * 180 / math.pi + 360) % 360;
    final sats = 11 + random.nextInt(3);
    rows.writeln(
      '${sats.toString().padLeft(3, '0')} $hh$mm$ss ${coordinate(east, north)} '
      '${(v * 3.6).toStringAsFixed(2)} ${heading.toStringAsFixed(1)} '
      '${brakePct.toStringAsFixed(1)} ${throttlePct.toStringAsFixed(1)} '
      '${along.toStringAsFixed(3)} ${lateral.toStringAsFixed(3)}',
    );
    previous = v;
    d += v / _hz;
    t += 1 / _hz;
  }
  // The gate's centre, and a point 20 m back along the direction of travel.
  final gateA = coordinate(0, 0).replaceAll('+', '').split(' '),
      gateB = coordinate(0, -20).replaceAll('+', '').split(' ');
  final created =
      '${start.$1.toString().padLeft(2, '0')}:'
      '${start.$2.toString().padLeft(2, '0')}:00';
  return 'File created on 12/09/2026 at $created\n\n'
      '[header]\nsatellites\ntime\nlatitude\nlongitude\nvelocity kmh\n'
      'heading\nbrake\nthrottle\nlongacc\nlatacc\n\n'
      '[comments]\nGenerated by RaceChrono Pro v10.2.4\n\n'
      '[laptiming]\n'
      'Start ${gateA[1]} ${gateA[0]} ${gateB[1]} ${gateB[0]} Start / finish\n\n'
      '[column names]\nsats time latitude longitude velocity heading '
      'brake throttle longacc latacc\n\n[data]\n$rows';
}
