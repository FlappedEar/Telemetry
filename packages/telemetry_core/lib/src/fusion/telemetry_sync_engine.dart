// Port of FlappedEar Overlays native/src/telemetry/TelemetrySyncEngine.{h,cpp}
// (revision d4d1039) (FET-50): the offset between two recordings from the
// cross-correlation of their speed traces.
import 'dart:math' as math;
import 'dart:typed_data';

import '../operation.dart';
import '../telemetry_session.dart';
import 'atanh.dart';
import 'std_math.dart';

/// How the sync engine reached its candidate.
final class SyncDiagnostics {
  const SyncDiagnostics({
    this.correlation = -1.0,
    this.peakUniqueness = 0.0,
    this.validSamples = 0,
    this.sampleRate = 0.0,
    this.coarseOffset = 0.0,
  });

  final double correlation;
  final double peakUniqueness;
  final int validSamples;
  final double sampleRate;
  final double coarseOffset;
}

/// An offset proposed by [synchronizeTelemetry]:
/// `telemetryTime = videoTime + offset`.
final class SyncCandidate {
  const SyncCandidate({
    this.offset = 0.0,
    this.timeScale = 1.0,
    this.confidence = 0.0,
    this.strategy = 'GPS speed',
    this.diagnostics = const SyncDiagnostics(),
  });

  final double offset;
  final double timeScale;
  final double confidence;
  final String strategy;
  final SyncDiagnostics diagnostics;
}

/// Thrown when two speed traces cannot be correlated (too few samples,
/// timestamps out of order, no speed channel). Its message is Overlays'.
final class SyncError implements Exception {
  const SyncError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Confidence is the engine's bounded composite of correlation strength, peak
/// uniqueness, and usable overlap. A 0.75 automatic threshold requires all
/// three to be strong.
const double automaticSyncConfidenceThreshold = 0.75;
const double minimumSyncOverlapSeconds = 20.0;

/// Below this correlation of the speed traces a candidate is only offered,
/// never applied automatically.
const double minimumAutomaticSyncCorrelation = 0.8;

/// Resource budgets.
const int maximumSyncSignalSamples = 1000000;
const int maximumSyncGridSamples = 1000000;
const int maximumSyncOffsets = 100001;
const int maximumSyncSamplePairs = 50000000;

enum SyncConfidenceLevel { high, medium, low }

SyncConfidenceLevel syncConfidenceLevel(double confidence) {
  if (!confidence.isFinite || confidence < 0.0 || confidence > 1.0) {
    return SyncConfidenceLevel.low;
  }
  if (confidence >= automaticSyncConfidenceThreshold) return SyncConfidenceLevel.high;
  return confidence >= 0.45 ? SyncConfidenceLevel.medium : SyncConfidenceLevel.low;
}

bool shouldAutoApplySyncCandidate(SyncCandidate candidate) =>
    candidate.offset.isFinite &&
    candidate.timeScale.isFinite &&
    candidate.timeScale > 0.0 &&
    syncConfidenceLevel(candidate.confidence) == SyncConfidenceLevel.high;

void _validateSignal(TelemetryChannel signal, CancellationCheck? cancelled) {
  if (signal.timestamps.length != signal.values.length || signal.values.length < 20) {
    throw const SyncError('Synchronization requires at least 20 aligned GPS speed samples.');
  }
  if (signal.values.length > maximumSyncSignalSamples) {
    throw const ResourceLimitError('Synchronization signal exceeds the 1000000-sample limit.');
  }
  for (var i = 0; i < signal.timestamps.length; ++i) {
    if ((i & 0xff) == 0) throwIfCancelled(cancelled);
    final time = signal.timestamps[i];
    if (!time.isFinite || (i != 0 && time <= signal.timestamps[i - 1])) {
      throw const SyncError('Synchronization timestamps must be finite and strictly increasing.');
    }
  }
}

int _gridCount(double span, double step, int maximum) {
  final intervals = (span / step).floorToDouble();
  if (!span.isFinite || span < 0.0 || !intervals.isFinite || intervals >= maximum) {
    throw const ResourceLimitError(
      'Synchronization grid exceeds the supported time/search budget.',
    );
  }
  return intervals.toInt() + 1;
}

double _gridTime(double start, double step, int index) {
  final value = start + index * step;
  if (!value.isFinite || (index != 0 && value <= start + (index - 1) * step)) {
    throw const SyncError('Synchronization time grid exceeds supported numeric precision.');
  }
  return value;
}

final class _Result {
  _Result(this.offset, this.score, this.samples, this.significance);

  final double offset;
  final double score;
  final int samples;

  // Evidence for a positive correlation over this many samples (Fisher z
  // times sqrt(n - 3)).
  final double significance;
}

double _significanceOf(double score, int samples) {
  if (samples <= 3 || !score.isFinite) return double.negativeInfinity;
  return atanh(stdClamp(score, -0.999999, 0.999999)) * math.sqrt((samples - 3).toDouble());
}

double _correlation(Float64List a, Float64List b, int length, CancellationCheck? cancelled) {
  if (length < 2) return -1.0;
  var sumA = 0.0, sumB = 0.0;
  for (var index = 0; index < length; ++index) {
    sumA += a[index];
  }
  for (var index = 0; index < length; ++index) {
    sumB += b[index];
  }
  final meanA = sumA / length;
  final meanB = sumB / length;
  var numerator = 0.0, varianceA = 0.0, varianceB = 0.0;
  for (var index = 0; index < length; ++index) {
    if ((index & 0xfff) == 0) throwIfCancelled(cancelled);
    final da = a[index] - meanA;
    final db = b[index] - meanB;
    numerator += da * db;
    varianceA += da * da;
    varianceB += db * db;
  }
  return varianceA > 0.0 && varianceB > 0.0
      ? stdClamp(numerator / math.sqrt(varianceA * varianceB), -1.0, 1.0)
      : -1.0;
}

final class _Budget {
  int remainingPairs = maximumSyncSamplePairs;
}

SyncCandidate _calculate(
  TelemetryChannel video,
  TelemetryChannel telemetry,
  double searchWindow,
  double sampleRate,
  double centerOffset,
  bool rankBySignificance,
  _Budget budget,
  CancellationCheck? cancelled,
) {
  final step = 1.0 / sampleRate;
  final firstOffset = centerOffset - searchWindow;
  final lastOffset = centerOffset + searchWindow;
  if (!firstOffset.isFinite || !lastOffset.isFinite) {
    throw const SyncError('Synchronization offset range is not finite.');
  }
  final offsets = _gridCount(lastOffset - firstOffset + step / 2.0, step, maximumSyncOffsets);
  final samples = _gridCount(
    video.timestamps.last - video.timestamps.first,
    step,
    maximumSyncGridSamples,
  );
  final pairs = offsets * samples;
  if (pairs > budget.remainingPairs) {
    throw const ResourceLimitError('Synchronization exceeds the 50000000 sample-pair work budget.');
  }
  budget.remainingPairs -= pairs;
  // Validate the grid's precision before allocating or doing correlation work.
  _gridTime(firstOffset, step, offsets - 1);
  _gridTime(video.timestamps.first, step, samples - 1);
  final results = <_Result>[];
  final a = Float64List(samples), b = Float64List(samples);
  for (var offsetIndex = 0; offsetIndex < offsets; ++offsetIndex) {
    throwIfCancelled(cancelled);
    final offset = _gridTime(firstOffset, step, offsetIndex);
    var count = 0;
    for (var sampleIndex = 0; sampleIndex < samples; ++sampleIndex) {
      if ((sampleIndex & 0xff) == 0) throwIfCancelled(cancelled);
      final time = _gridTime(video.timestamps.first, step, sampleIndex);
      // Overlays KAN-157: the shared lookup, so a loss of GPS fix is not
      // bridged into a ramp that correlates.
      final av = telemetryValueAt(video, time);
      final bv = telemetryValueAt(telemetry, time + offset);
      if (av != null && bv != null && av.isFinite && bv.isFinite) {
        a[count] = av;
        b[count] = bv;
        ++count;
      }
    }
    final score = _correlation(a, b, count, cancelled);
    results.add(_Result(offset, score, count, _significanceOf(score, count)));
  }
  throwIfCancelled(cancelled);
  // A correlation over a handful of overlapping points can be perfect by
  // accident: offsets without the minimum overlap are ranked only when no
  // offset has it.
  final minimumSamples = sampleRate * minimumSyncOverlapSeconds + 1.0;
  if (results.any((item) => item.samples >= minimumSamples)) {
    results.removeWhere((item) => item.samples < minimumSamples);
  }
  // The global search ranks by significance; the local refinement, where
  // the overlap is nearly constant, by correlation alone. Stable, as
  // std::stable_sort.
  stableSort(
    results,
    rankBySignificance
        ? (_Result left, _Result right) => left.significance > right.significance
        : (_Result left, _Result right) => left.score > right.score,
  );
  final best = results.first;
  // The strongest competing offset, at least 5 s away, over the whole range.
  var second = -1.0;
  for (final item in results) {
    if ((item.offset - best.offset).abs() >= 5.0) {
      second = item.score;
      break;
    }
  }
  final uniqueness = stdClamp((best.score - second) / 0.25, 0.0, 1.0);
  final durationScore = stdMin(1.0, best.samples / (sampleRate * 20.0));
  final strength = stdClamp((best.score + 1.0) / 2.0, 0.0, 1.0);
  final milliseconds = best.offset * 1000.0;
  if (!milliseconds.isFinite) {
    throw const SyncError('Synchronization offset exceeds millisecond rounding range.');
  }
  var confidence =
      (100.0 * strength * (0.35 + 0.4 * uniqueness + 0.25 * durationScore)).roundToDouble() / 100.0;
  // Require twenty seconds worth of usable resampled overlap before
  // automatic use.
  if (best.samples < minimumSamples || best.score < minimumAutomaticSyncCorrelation) {
    confidence = stdMin(confidence, automaticSyncConfidenceThreshold - 0.01);
  }
  return SyncCandidate(
    offset: milliseconds.roundToDouble() / 1000.0,
    confidence: confidence,
    diagnostics: SyncDiagnostics(
      correlation: best.score,
      peakUniqueness: uniqueness,
      validSamples: best.samples,
      sampleRate: sampleRate,
    ),
  );
}

/// The offset of [telemetry]'s speed trace against [video]'s
/// (`telemetryTime = videoTime + offset`): a 1 Hz search over every offset
/// that leaves 20 s of overlap, ranked by significance, refined at 10 Hz
/// within ±5 s.
///
/// Throws [SyncError] when either trace is missing or unusable,
/// [ResourceLimitError] beyond the work budget and [OperationCancelled].
SyncCandidate synchronizeTelemetry(
  TelemetrySession video,
  TelemetrySession telemetry, {
  CancellationCheck? cancelled,
}) {
  throwIfCancelled(cancelled);
  final videoSpeed = video.channels[video.aliases['speed'] ?? ''];
  final telemetrySpeed = telemetry.channels[telemetry.aliases['speed'] ?? ''];
  if (videoSpeed == null || telemetrySpeed == null) {
    throw const SyncError('GPS speed is not available in both telemetry sources.');
  }
  _validateSignal(videoSpeed, cancelled);
  _validateSignal(telemetrySpeed, cancelled);
  // Every offset (telemetry = video + offset) that leaves the minimum
  // overlap, in both directions. When either recording is shorter than that,
  // the shorter one must lie fully inside the other.
  final videoFirst = videoSpeed.timestamps.first, videoLast = videoSpeed.timestamps.last;
  final telemetryFirst = telemetrySpeed.timestamps.first;
  final telemetryLast = telemetrySpeed.timestamps.last;
  final requiredOverlap = stdMin(
    stdMin(minimumSyncOverlapSeconds, videoLast - videoFirst),
    telemetryLast - telemetryFirst,
  );
  var minimum = telemetryFirst - videoLast + requiredOverlap;
  var maximum = telemetryLast - videoFirst - requiredOverlap;
  if (maximum < minimum) {
    final swap = minimum;
    minimum = maximum;
    maximum = swap;
  }
  if (!minimum.isFinite || !maximum.isFinite) {
    throw const SyncError('Synchronization timestamp differences are not finite.');
  }
  final center = stdMidpoint(minimum, maximum);
  final window = stdMax(1.0, (maximum - minimum) / 2.0);
  final budget = _Budget();
  final coarse = _calculate(
    videoSpeed,
    telemetrySpeed,
    window,
    1.0,
    center,
    true,
    budget,
    cancelled,
  );
  final fine = _calculate(
    videoSpeed,
    telemetrySpeed,
    5.0,
    10.0,
    coarse.offset,
    false,
    budget,
    cancelled,
  );
  throwIfCancelled(cancelled);
  // Refinement estimates a more precise offset, but cannot erase competing
  // peaks outside its local window or improve the global evidence of
  // uniqueness.
  return SyncCandidate(
    offset: fine.offset,
    timeScale: fine.timeScale,
    confidence: stdMin(fine.confidence, coarse.confidence),
    strategy: fine.strategy,
    diagnostics: SyncDiagnostics(
      correlation: fine.diagnostics.correlation,
      peakUniqueness: stdMin(fine.diagnostics.peakUniqueness, coarse.diagnostics.peakUniqueness),
      validSamples: fine.diagnostics.validSamples,
      sampleRate: fine.diagnostics.sampleRate,
      coarseOffset: coarse.offset,
    ),
  );
}
