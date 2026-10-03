// The C++ standard library helpers Overlays' fusion code relies on, with
// their exact semantics (comparison order, NaN and signed-zero behaviour),
// which `dart:math` does not share.

/// `std::min(a, b)`: [a] unless [b] is smaller.
double stdMin(double a, double b) => b < a ? b : a;

/// `std::max(a, b)`: [a] unless it is smaller than [b].
double stdMax(double a, double b) => a < b ? b : a;

/// `std::clamp(value, low, high)`.
double stdClamp(double value, double low, double high) => value < low
    ? low
    : high < value
    ? high
    : value;

/// libstdc++'s `std::midpoint` for doubles.
double stdMidpoint(double a, double b) {
  const low = 2.2250738585072014e-308 * 2; // numeric_limits<double>::min() * 2
  const high = 1.7976931348623157e308 / 2; // numeric_limits<double>::max() / 2
  final absA = a < 0 ? -a : a;
  final absB = b < 0 ? -b : b;
  if (absA <= high && absB <= high) return (a + b) / 2;
  if (absA < low) return a + b / 2;
  if (absB < low) return a / 2 + b;
  return a / 2 + b / 2;
}

/// Sorts [list] in place, keeping the order of elements that are not
/// [less] than each other, as `std::stable_sort` does.
void stableSort<T>(List<T> list, bool Function(T a, T b) less) {
  if (list.length < 2) return;
  var source = List<T>.of(list);
  var target = List<T>.of(list);
  for (var width = 1; width < list.length; width *= 2) {
    for (var start = 0; start < list.length; start += 2 * width) {
      final middle = start + width < list.length ? start + width : list.length;
      final end = start + 2 * width < list.length ? start + 2 * width : list.length;
      var left = start, right = middle, out = start;
      while (left < middle && right < end) {
        target[out++] = less(source[right], source[left]) ? source[right++] : source[left++];
      }
      while (left < middle) {
        target[out++] = source[left++];
      }
      while (right < end) {
        target[out++] = source[right++];
      }
    }
    final swap = source;
    source = target;
    target = swap;
  }
  list.setAll(0, source);
}
