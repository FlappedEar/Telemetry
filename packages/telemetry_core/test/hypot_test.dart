import 'dart:math' as math;

import 'package:telemetry_core/src/geometry.dart';
import 'package:test/test.dart';

// Expected values come from glibc 2.39's std::hypot (x86-64). The pairs are
// synthetic ones where sqrt(1 + r²) scaling is one ULP away from it.
void main() {
  test('matches glibc hypot where the ratio formula is one ULP off', () {
    const cases = [
      (-324.63536048986964, 324.6353604898694, 459.1037296306523),
      (255.9703840073316, 255.9703840073315, 361.9967886290175),
      (-6.068226597549324, -45.55564434936921, 45.95802548114333),
      (-156.62291398726902, -156.62291398726902, 221.49824913919056),
      (0.9259980456788228, 0.9259980456788232, 1.3095589949299722),
      (15.592720515835857, 15.592720515835856, 22.051436827788272),
    ];
    for (final (x, y, expected) in cases) {
      expect(hypot(x, y), expected, reason: '($x, $y)');
      expect(hypot(y, x), expected);
    }
  });

  test('one-ULP neighbours tie the way glibc ties them', () {
    // glibc rounds both to the same value; a strict `<` nearest-point
    // search must therefore keep the first candidate.
    expect(hypot(1.1870705633364693, 1.8520715610775667), 2.199842173814353);
    expect(hypot(1.1870705633364693, 1.8520715610775669), 2.199842173814353);
  });

  test('edge cases', () {
    expect(hypot(3, 4), 5);
    expect(hypot(0, 0), 0);
    expect(hypot(-0.0, 2), 2);
    expect(hypot(1e300, 1e300), 1.4142135623730952e300);
    expect(hypot(1e-300, 1e-300), 1.414213562373095e-300);
    expect(hypot(double.maxFinite, 1), double.maxFinite);
    expect(hypot(double.infinity, double.nan), double.infinity);
    expect(hypot(double.nan, 1).isNaN, isTrue);
    expect(hypot(5e-324, 5e-324), 5e-324);
  });

  test('scaling constants are exact powers of two', () {
    expect(2.409919865102884e-181, math.pow(2.0, -600));
    expect(6.703903964971299e+153, math.pow(2.0, 511));
    expect(1.4916681462400413e-154, math.pow(2.0, -511));
    expect(5.551115123125783e-17, math.pow(2.0, -54));
  });
}
