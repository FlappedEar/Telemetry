// A synthetic day of RaceChrono-style VBO recordings for the day benchmark
// (FET-41). Generated tracks only: no real recording, GPS trace or heart rate.
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

const double _lat0 = 52.0, _lon0 = 21.0;
const double _metersPerDegree = 6371000.0 * math.pi / 180.0;
const double _spacing = 0.5;

/// The outline of a closed track from the start gate at the origin, heading
/// north, one point every half metre: a rounded rectangle with two long
/// straights, two short sides and four corners of [radius] metres.
List<(double, double, double)> _outline({
  double long = 600.0,
  double short = 140.0,
  double radius = 45.0,
}) {
  // (east, north, curvature 1/m).
  final points = <(double, double, double)>[];
  var x = 0.0, y = -long / 2, heading = math.pi / 2;
  void straight(double length) {
    final steps = (length / _spacing).round();
    for (var i = 0; i < steps; ++i) {
      points.add((x, y, 0.0));
      x += _spacing * math.cos(heading);
      y += _spacing * math.sin(heading);
    }
  }

  void corner() {
    final steps = (math.pi / 2 * radius / _spacing).round();
    final turn = math.pi / 2 / steps;
    for (var i = 0; i < steps; ++i) {
      points.add((x, y, 1.0 / radius));
      final chord = 2 * radius * math.sin(turn / 2);
      heading += turn / 2;
      x += chord * math.cos(heading);
      y += chord * math.sin(heading);
      heading += turn / 2;
    }
  }

  for (var side = 0; side < 2; ++side) {
    straight(long);
    corner();
    straight(short);
    corner();
  }
  // Start the outline at the gate (the middle of the first straight).
  final gate = (long / 2 / _spacing).round();
  return [...points.sublist(gate), ...points.sublist(0, gate)];
}

/// Target speed in m/s at each outline point: limited by lateral grip in the
/// corners, then by braking and acceleration along the lap.
List<double> _speedProfile(List<(double, double, double)> outline) {
  const grip = 1.25 * 9.81, top = 52.0, brake = 9.0, accelerate = 4.5;
  final count = outline.length;
  final speed = [
    for (final (_, _, curvature) in outline)
      curvature > 0 ? math.min(top, math.sqrt(grip / curvature)) : top,
  ];
  // Two passes each way so the limits wrap around the start line.
  for (var pass = 0; pass < 2; ++pass) {
    for (var i = 1; i <= count; ++i) {
      final previous = speed[(i - 1) % count];
      final limit = math.sqrt(previous * previous + 2 * accelerate * _spacing);
      if (speed[i % count] > limit) speed[i % count] = limit;
    }
    for (var i = count - 2; i >= -1; --i) {
      final next = speed[(i + 1) % count];
      final limit = math.sqrt(next * next + 2 * brake * _spacing);
      final index = (i + count) % count;
      if (speed[index] > limit) speed[index] = limit;
    }
  }
  return speed;
}

String _clock(double seconds) {
  // Whole milliseconds, so a time never reads "60.000" seconds.
  final milliseconds = (seconds * 1000).round();
  final hours = milliseconds ~/ 3600000;
  final minutes = milliseconds % 3600000 ~/ 60000;
  final rest = milliseconds % 60000;
  return '${'$hours'.padLeft(2, '0')}${'$minutes'.padLeft(2, '0')}'
      '${'${rest ~/ 1000}'.padLeft(2, '0')}.${'${rest % 1000}'.padLeft(3, '0')}';
}

String _arcMinutes(double degrees) {
  final value = degrees * 60.0;
  return '${value < 0 ? '-' : '+'}${value.abs().toStringAsFixed(6)}';
}

/// One synthetic session as RaceChrono Pro 10.2.4 VBO text: [laps] laps at
/// [rateHz], starting [startSeconds] after midnight on 1 June 2026. Lap times
/// vary by a few tenths, temperatures rise and heart rate follows the effort.
String syntheticSessionVbo({
  required int session,
  int laps = 6,
  double rateHz = 20.0,
  double startSeconds = 9 * 3600.0,
}) {
  final outline = _outline();
  final profile = _speedProfile(outline);
  final perimeter = outline.length * _spacing;
  final cosLat = math.cos(_lat0 * math.pi / 180.0);
  (double, double) degrees(double east, double north) =>
      (_lat0 + north / _metersPerDegree, _lon0 + east / (_metersPerDegree * cosLat));

  (double, double, double, double) at(double distance) {
    final wrapped = distance % perimeter;
    final position = wrapped / _spacing;
    final index = position.floor() % outline.length;
    final next = (index + 1) % outline.length;
    final fraction = position - position.floor();
    final (x0, y0, k0) = outline[index];
    final (x1, y1, _) = outline[next];
    final v = profile[index] + (profile[next] - profile[index]) * fraction;
    return (x0 + (x1 - x0) * fraction, y0 + (y1 - y0) * fraction, k0, v);
  }

  final created = startSeconds.floor();
  String two(int value) => '$value'.padLeft(2, '0');
  final lines = <String>[
    'File created on 01/06/2026 at ${two(created ~/ 3600)}:${two(created % 3600 ~/ 60)}:'
        '${two(created % 60)}',
    '',
    '[header]',
    'satellites',
    'time',
    'latitude',
    'longitude',
    'velocity kmh',
    'heading',
    'longacc',
    'latacc',
    'rpm',
    'throttle',
    'brake',
    'oil temp',
    'water temp',
    'heart rate',
    '',
    '[comments]',
    'Generated by RaceChrono Pro v10.2.4',
    'Synthetic session $session for the day benchmark',
    '',
    '[laptiming]',
  ];
  final (centreLat, centreLon) = degrees(0.0, 0.0);
  final (backLat, backLon) = degrees(0.0, -20.0);
  lines.add(
    'Start ${(centreLon * 60).toStringAsFixed(6)} ${(centreLat * 60).toStringAsFixed(6)} '
    '${(backLon * 60).toStringAsFixed(6)} ${(backLat * 60).toStringAsFixed(6)} Start / finish',
  );
  lines.addAll([
    '',
    '[column names]',
    'sats time lat long velocity heading longacc latacc rpm throttle brake '
        'oil_temp water_temp heart_rate',
    '',
    '[data]',
  ]);
  final random = math.Random(session);
  final dt = 1.0 / rateHz;
  var distance = -40.0, time = 0.0, previousSpeed = profile.last;
  var oil = 70.0 + session, water = 75.0 + session, heart = 95.0;
  final end = (laps + 0.4) * perimeter;
  final rows = StringBuffer();
  while (distance < end) {
    final lap = (distance / perimeter).floor();
    // Each lap is a little slower or faster than the ideal profile.
    final pace = 0.94 + 0.03 * math.sin(lap * 1.7 + session) + 0.004 * random.nextDouble();
    final (east, north, curvature, ideal) = at(distance);
    final speed = ideal * pace;
    final acceleration = (speed - previousSpeed) / dt;
    final (lat, lon) = degrees(east, north);
    final (aheadEast, aheadNorth, _, _) = at(distance + 1.0);
    final heading = (90 - math.atan2(aheadNorth - north, aheadEast - east) * 180 / math.pi) % 360;
    final braking = acceleration < -1.0;
    final throttle = braking ? 0.0 : (acceleration > 0.5 ? 100.0 : 35.0);
    final brake = braking ? math.min(100.0, -acceleration * 9.0) : 0.0;
    oil += (105.0 - oil) * 0.0004 * dt * 10;
    water += (92.0 - water) * 0.0003 * dt * 10;
    heart += ((braking || curvature > 0 ? 165.0 : 140.0) - heart) * 0.02;
    rows
      ..write('${(9 + random.nextInt(4)).toString().padLeft(3, '0')} ')
      ..write('${_clock(startSeconds + time)} ')
      ..write('${_arcMinutes(lat)} ${_arcMinutes(lon)} ')
      ..write('${(speed * 3.6).toStringAsFixed(3)} ${heading.toStringAsFixed(2)} ')
      ..write('${(acceleration / 9.81).toStringAsFixed(3)} ')
      ..write('${(speed * speed * curvature / 9.81).toStringAsFixed(3)} ')
      ..write('${(2500 + speed * 110).round()} ${throttle.toStringAsFixed(1)} ')
      ..write('${brake.toStringAsFixed(1)} ${oil.toStringAsFixed(1)} ${water.toStringAsFixed(1)} ')
      ..write('${heart.round()}\r\n');
    distance += speed * dt;
    previousSpeed = speed;
    time += dt;
  }
  return '${lines.join('\r\n')}\r\n$rows';
}

/// Writes [sessions] synthetic sessions of [laps] laps into [folder], 90
/// minutes apart, and returns their paths.
List<String> writeSyntheticDay(
  String folder, {
  int sessions = 2,
  int laps = 4,
  double rateHz = 20.0,
}) {
  Directory(folder).createSync(recursive: true);
  return [
    for (var session = 1; session <= sessions; ++session)
      (File(p.join(folder, 'synthetic_session_$session.vbo'))..writeAsStringSync(
            syntheticSessionVbo(
              session: session,
              laps: laps,
              rateHz: rateHz,
              startSeconds: 9 * 3600.0 + (session - 1) * 5400.0,
            ),
          ))
          .path,
  ];
}
