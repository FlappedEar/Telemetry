/// A lap time as `M:SS` with 0–3 decimals, such as `1:40.23`.
///
/// The time is rounded to the shown precision before minutes are split, so
/// 59.96 s at one decimal reads `1:00.0`, never `0:60.0`. Null for a negative
/// or non-finite time, so callers show their own placeholder.
String? formatLapTime(double seconds, int decimals) {
  if (!seconds.isFinite || seconds < 0.0) return null;
  final places = decimals.clamp(0, 3);
  const unitsPerPlace = [1, 10, 100, 1000];
  final unitsPerSecond = unitsPerPlace[places];
  final scaled = seconds * unitsPerSecond;
  // Bounded far below the integer range for any lap; long times still format.
  final total = (scaled < 9.0e15 ? scaled : 9.0e15).round();
  final perMinute = 60 * unitsPerSecond;
  final minutes = total ~/ perMinute;
  final rest = total % perMinute;
  final wholeSeconds = (rest ~/ unitsPerSecond).toString().padLeft(2, '0');
  if (places == 0) return '$minutes:$wholeSeconds';
  final fraction = (rest % unitsPerSecond).toString().padLeft(places, '0');
  return '$minutes:$wholeSeconds.$fraction';
}
