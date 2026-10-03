import 'dart:typed_data';

/// Inverse hyperbolic tangent, as glibc computes it.
///
/// A port of glibc 2.39's `__ieee754_atanh` (sysdeps/ieee754/dbl-64/e_atanh.c)
/// and the `__log1p` it calls (s_log1p.c, Sun's fdlibm with glibc's
/// polynomial order), which is what Overlays' `std::atanh` calls. Dart has no
/// atanh; a formula like `0.5 * log((1 + x) / (1 - x))` is often one ULP
/// off. It matches glibc's generic x86-64 build bit for bit; on CPUs with
/// FMA, glibc picks an FMA-contracted `__log1p` that differs in the last bit
/// for about one argument in 10 000.
double atanh(double x) {
  final xa = x.abs();
  double t;
  if (xa < 0.5) {
    if (xa < 3.725290298461914e-9) return x; // 2^-28
    t = xa + xa;
    t = 0.5 * log1p(t + t * xa / (1.0 - xa));
  } else if (xa < 1.0) {
    t = 0.5 * log1p((xa + xa) / (1.0 - xa));
  } else {
    if (xa > 1.0) return double.nan;
    if (x.isNaN) return x;
    return x > 0 ? double.infinity : double.negativeInfinity;
  }
  return x.isNegative ? -t : t;
}

const _ln2Hi = 6.93147180369123816490e-01; // 3fe62e42 fee00000
const _ln2Lo = 1.90821492927058770002e-10; // 3dea39ef 35793c76
const _lp1 = 6.666666666666735130e-01; // 3FE55555 55555593
const _lp2 = 3.999999999940941908e-01; // 3FD99999 9997FA04
const _lp3 = 2.857142874366239149e-01; // 3FD24924 94229359
const _lp4 = 2.222219843214978396e-01; // 3FCC71C5 1D8E78AF
const _lp5 = 1.818357216161805012e-01; // 3FC74664 96CB03DE
const _lp6 = 1.531383769920937332e-01; // 3FC39A09 D078C69F
const _lp7 = 1.479819860511658591e-01; // 3FC2F112 DF3E5244

final _bits = ByteData(8);

int _highWord(double value) {
  _bits.setFloat64(0, value, Endian.little);
  return _bits.getInt32(4, Endian.little);
}

double _withHighWord(double value, int high) {
  _bits.setFloat64(0, value, Endian.little);
  _bits.setInt32(4, high, Endian.little);
  return _bits.getFloat64(0, Endian.little);
}

/// log(1 + x), as glibc 2.39's `__log1p` computes it.
double log1p(double x) {
  final hx = _highWord(x);
  final ax = hx & 0x7fffffff;
  var k = 1;
  var f = 0.0, c = 0.0;
  var hu = 0;
  if (hx < 0x3FDA827A) {
    // x < 0.41422
    if (ax >= 0x3ff00000) {
      // x <= -1.0
      return x == -1.0 ? double.negativeInfinity : double.nan;
    }
    if (ax < 0x3e200000) {
      // |x| < 2^-29
      if (ax < 0x3c900000) return x; // |x| < 2^-54
      return x - x * x * 0.5;
    }
    if (hx > 0 || hx <= -1076707645) {
      // -0.2929 < x < 0.41422 (0xbfd2bec3 as int32)
      k = 0;
      f = x;
      hu = 1;
    }
  } else if (hx >= 0x7ff00000) {
    return x + x;
  }
  if (k != 0) {
    double u;
    if (hx < 0x43400000) {
      u = 1.0 + x;
      hu = _highWord(u);
      k = (hu >> 20) - 1023;
      c = k > 0 ? 1.0 - (u - x) : x - (u - 1.0); // correction term
      c /= u;
    } else {
      u = x;
      hu = _highWord(u);
      k = (hu >> 20) - 1023;
      c = 0;
    }
    hu &= 0x000fffff;
    if (hu < 0x6a09e) {
      u = _withHighWord(u, hu | 0x3ff00000); // normalize u
    } else {
      k += 1;
      u = _withHighWord(u, hu | 0x3fe00000); // normalize u/2
      hu = (0x00100000 - hu) >> 2;
    }
    f = u - 1.0;
  }
  final hfsq = 0.5 * f * f;
  if (hu == 0) {
    // |f| < 2^-20
    if (f == 0.0) {
      if (k == 0) return 0.0;
      c += k * _ln2Lo;
      return k * _ln2Hi + c;
    }
    final r = hfsq * (1.0 - 0.66666666666666666 * f);
    if (k == 0) return f - r;
    return k * _ln2Hi - ((r - (k * _ln2Lo + c)) - f);
  }
  final s = f / (2.0 + f);
  final z = s * s;
  final r1 = z * _lp1, z2 = z * z;
  final r2 = _lp2 + z * _lp3, z4 = z2 * z2;
  final r3 = _lp4 + z * _lp5, z6 = z4 * z2;
  final r4 = _lp6 + z * _lp7;
  final r = r1 + z2 * r2 + z4 * r3 + z6 * r4;
  if (k == 0) return f - (hfsq - s * (hfsq + r));
  return k * _ln2Hi - ((hfsq - (s * (hfsq + r) + (k * _ln2Lo + c))) - f);
}
