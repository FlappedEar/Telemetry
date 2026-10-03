import 'dart:typed_data';

/// The [k]th smallest of the first [count] values of [values]: the value at
/// index [k] once they are sorted, found without sorting (Hoare's
/// selection). Reorders [values]; NaN is not allowed. Equal values may be
/// zeros of either sign, so a caller that keeps the sign of zero must not
/// use it.
double selectKth(Float64List values, int count, int k) {
  assert(k >= 0 && k < count && count <= values.length);
  var low = 0, high = count - 1;
  while (low < high) {
    final pivot = values[low + ((high - low) >> 1)];
    var i = low, j = high;
    while (i <= j) {
      while (values[i] < pivot) {
        ++i;
      }
      while (values[j] > pivot) {
        --j;
      }
      if (i <= j) {
        final swap = values[i];
        values[i] = values[j];
        values[j] = swap;
        ++i;
        --j;
      }
    }
    if (k <= j) {
      high = j;
    } else if (k >= i) {
      low = i;
    } else {
      return values[k];
    }
  }
  return values[k];
}
