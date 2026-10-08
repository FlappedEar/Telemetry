// How much each segment's time varies within one session (FET-224, idea 8
// of FET-217), in fixed bands for the consistency map: the spread (the
// interquartile range of the session's times through the segment, at least
// minimumConsistencySamples laps) is the one the session's section
// progression already gives; nothing is measured differently. Fixed bands,
// not scaled to the day, so a tidy session is not painted red.

/// The upper edges of the spread bands, in seconds: band 0 is up to the
/// first, band [segmentSpreadBandsSeconds].length is above the last.
const List<double> segmentSpreadBandsSeconds = [0.10, 0.25, 0.50, 1.00];

/// The band of a spread of [seconds]: how many band edges it is above.
/// A value on an edge belongs to the band below it.
int segmentSpreadBand(double seconds) {
  var band = 0;
  for (final edge in segmentSpreadBandsSeconds) {
    if (seconds > edge) band++;
  }
  return band;
}
