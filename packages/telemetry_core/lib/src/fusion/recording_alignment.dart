// Port of FlappedEar Overlays native/src/telemetry/RecordingAlignment.{h,cpp}
// (revision d4d1039, recording-alignment-v1) (FET-50): how an alternative
// recording of a run lines up in time with the run's primary recording,
// before any channel could be fused.
import 'dart:math' as math;
import 'dart:typed_data';

import '../intake/import_plan.dart' show recordingTimestamp;
import '../operation.dart';
import '../telemetry_session.dart';
import 'std_math.dart';
import 'telemetry_sync_engine.dart';

const recordingAlignmentAlgorithm = 'recording-alignment-v1';

const alignmentAligned = 'aligned';
const alignmentAmbiguous = 'ambiguous';
const alignmentConflicting = 'conflicting';
const alignmentInsufficient = 'insufficient';

final class RecordingAlignmentOptions {
  const RecordingAlignmentOptions({
    this.minimumWindowCorrelation = 0.9,
    this.maximumResidualSeconds = 0.3,
    this.maximumPlausibleDriftPpm = 1000.0,
    this.declaredToleranceSeconds = 2.0,
    this.maximumWindows = 8,
    this.minimumWindowSeconds = 60.0,
  });

  /// A window's speed match must be this strong to count.
  final double minimumWindowCorrelation;

  /// Windows must agree with the fitted line this closely.
  final double maximumResidualSeconds;
  final double maximumPlausibleDriftPpm;

  /// Declared against measured offset before they conflict.
  final double declaredToleranceSeconds;
  final int maximumWindows;
  final double minimumWindowSeconds;
}

/// One stretch of the overlap matched on its own.
final class AlignmentWindow {
  const AlignmentWindow({
    required this.candidateTime,
    required this.offset,
    required this.correlation,
    required this.used,
  });

  /// The window's centre on the candidate's clock.
  final double candidateTime;
  final double offset;
  final double correlation;
  final bool used;
}

/// The alignment of a candidate recording to a primary one, with
/// `primaryTime = candidateTime + offset + driftPpm * 1e-6 * candidateTime`.
///
/// Two kinds of evidence are kept apart: the loggers' declared start
/// timestamps ([declaredOffset]) and the offset measured from the speed
/// traces ([offset], [driftPpm]). Nothing is applied to either recording.
final class RecordingAlignment {
  const RecordingAlignment({
    this.status = alignmentInsufficient,
    this.reason = '',
    this.declaredOffset,
    this.offset,
    this.driftPpm,
    this.uncertaintySeconds,
    this.correlation = -1.0,
    this.peakUniqueness = 0.0,
    this.confidence = 0.0,
    this.overlapSeconds = 0.0,
    this.windows = const [],
    this.usedWindows = 0,
    this.resolvedByDeclaredClock = false,
  });

  /// [alignmentAligned], [alignmentAmbiguous], [alignmentConflicting] or
  /// [alignmentInsufficient].
  final String status;

  /// Why it is not aligned: `noSpeed`, `shortOverlap`, `weakMatch`,
  /// `tooFewWindows`, `windowsDisagree`, `implausibleDrift`,
  /// `declaredClockDisagrees`, `repeatedMatch` or the sync engine's message.
  final String reason;

  /// Seconds, from the loggers' start timestamps.
  final double? declaredOffset;

  /// Measured, at candidate time 0.
  final double? offset;

  /// With three agreeing windows, when resolvable over the overlap.
  final double? driftPpm;
  final double? uncertaintySeconds;

  /// Whole-overlap speed correlation.
  final double correlation;
  final double peakUniqueness;

  /// The sync engine's composite.
  final double confidence;
  final double overlapSeconds;
  final List<AlignmentWindow> windows;
  final int usedWindows;

  /// The speed match also fits elsewhere (a lap away); the agreeing declared
  /// clock chose between the matches.
  final bool resolvedByDeclaredClock;
}

TelemetryChannel? _speedChannel(TelemetrySession session) {
  final found = session.channels[session.aliases['speed'] ?? ''];
  return found == null || found.timestamps.isEmpty ? null : found;
}

// A session holding only the speed samples of [channel] in [from, to], on
// the original clock.
TelemetrySession _speedSlice(TelemetryChannel channel, double from, double to) {
  final times = <double>[];
  final values = <double>[];
  for (var index = 0; index < channel.timestamps.length; ++index) {
    final time = channel.timestamps[index];
    if (time < from || time > to) continue;
    times.add(time);
    values.add(channel.values[index]);
  }
  final slice = TelemetryChannel(
    name: channel.name,
    unit: channel.unit,
    timestamps: Float64List.fromList(times),
    values: Float32List.fromList(values),
  );
  return TelemetrySession(
    duration: 0.0,
    startTime: 0.0,
    metadata: const {},
    channels: {slice.name: slice},
    aliases: {'speed': slice.name},
    warnings: const [],
    timingGates: const [],
    sampleCount: 0,
  );
}

/// Aligns [candidate] to [primary]. Cooperatively cancellable (throws
/// [OperationCancelled]).
RecordingAlignment alignRecordings(
  TelemetrySession primary,
  TelemetrySession candidate, {
  CancellationCheck? cancelled,
  RecordingAlignmentOptions options = const RecordingAlignmentOptions(),
}) {
  final primaryStart = recordingTimestamp(primary);
  final candidateStart = recordingTimestamp(candidate);
  final declaredOffset = primaryStart != null && candidateStart != null
      ? (candidateStart - primaryStart).toDouble() / 1000.0
      : null;

  final primarySpeed = _speedChannel(primary);
  final candidateSpeed = _speedChannel(candidate);
  if (primarySpeed == null || candidateSpeed == null) {
    return RecordingAlignment(declaredOffset: declaredOffset, reason: 'noSpeed');
  }
  SyncCandidate whole;
  try {
    whole = synchronizeTelemetry(candidate, primary, cancelled: cancelled);
  } on OperationCancelled {
    rethrow;
  } on Exception catch (error) {
    return RecordingAlignment(declaredOffset: declaredOffset, reason: error.toString());
  }
  final correlation = whole.diagnostics.correlation;
  final peakUniqueness = whole.diagnostics.peakUniqueness;
  final confidence = whole.confidence;
  // The candidate's span that the primary covers under the whole offset.
  final from = stdMax(
    candidateSpeed.timestamps.first,
    primarySpeed.timestamps.first - whole.offset,
  );
  final to = stdMin(candidateSpeed.timestamps.last, primarySpeed.timestamps.last - whole.offset);
  final overlapSeconds = stdMax(0.0, to - from);
  if (overlapSeconds < minimumSyncOverlapSeconds) {
    return RecordingAlignment(
      reason: 'shortOverlap',
      declaredOffset: declaredOffset,
      correlation: correlation,
      peakUniqueness: peakUniqueness,
      confidence: confidence,
      overlapSeconds: overlapSeconds,
    );
  }

  // Windows along the overlap, each matched only near the whole offset so a
  // lap-periodic speed trace cannot match the wrong lap.
  final count = _clampInt(
    _toInt(overlapSeconds / options.minimumWindowSeconds),
    1,
    options.maximumWindows,
  );
  final width = overlapSeconds / count;
  const searchSeconds = 10.0;
  final windows = <AlignmentWindow>[];
  var usedWindows = 0;
  for (var index = 0; index < count; ++index) {
    throwIfCancelled(cancelled);
    final start = from + index * width, end = start + width;
    var window = AlignmentWindow(
      candidateTime: (start + end) / 2.0,
      offset: whole.offset,
      correlation: -1.0,
      used: false,
    );
    try {
      final part = synchronizeTelemetry(
        _speedSlice(candidateSpeed, start, end),
        _speedSlice(
          primarySpeed,
          start + whole.offset - searchSeconds,
          end + whole.offset + searchSeconds,
        ),
        cancelled: cancelled,
      );
      window = AlignmentWindow(
        candidateTime: window.candidateTime,
        offset: part.offset,
        correlation: part.diagnostics.correlation,
        used:
            part.diagnostics.correlation >= options.minimumWindowCorrelation &&
            (part.offset - whole.offset).abs() < searchSeconds,
      );
    } on OperationCancelled {
      rethrow;
    } on Exception {
      // Too few samples or no variation in this window: not evidence.
    }
    windows.add(window);
    if (window.used) ++usedWindows;
  }

  // Offset and drift: a least-squares line through the used windows.
  final used = [
    for (final window in windows)
      if (window.used) window,
  ];
  double? offset;
  double? driftPpm;
  var residual = 0.0;
  if (used.length >= 3) {
    var meanT = 0.0, meanO = 0.0;
    for (final window in used) {
      meanT += window.candidateTime;
      meanO += window.offset;
    }
    meanT /= used.length;
    meanO /= used.length;
    var covariance = 0.0, variance = 0.0;
    for (final window in used) {
      covariance += (window.candidateTime - meanT) * (window.offset - meanO);
      variance += (window.candidateTime - meanT) * (window.candidateTime - meanT);
    }
    final slope = variance > 0.0 ? covariance / variance : 0.0;
    offset = meanO - slope * meanT;
    driftPpm = slope * 1e6;
    var squares = 0.0;
    for (final window in used) {
      final error = window.offset - (offset + slope * window.candidateTime);
      squares += error * error;
    }
    residual = math.sqrt(squares / (used.length - 2));
    // A drift is reported only when it moves the offset across the windows
    // by clearly more than the offsets can be resolved.
    final span = used.last.candidateTime - used.first.candidateTime;
    if (slope.abs() * span < 2.0 * stdMax(0.05, residual)) {
      offset = meanO;
      driftPpm = null;
      var spread = 0.0;
      for (final window in used) {
        spread += (window.offset - meanO) * (window.offset - meanO);
      }
      residual = math.sqrt(spread / (used.length - 1));
    }
  } else if (used.isNotEmpty) {
    var sum = 0.0, low = used.first.offset, high = low;
    for (final window in used) {
      sum += window.offset;
      low = stdMin(low, window.offset);
      high = stdMax(high, window.offset);
    }
    offset = sum / used.length;
    residual = (high - low) / 2.0;
  } else {
    offset = whole.offset;
  }
  // The engine resolves offsets on a 10 Hz grid.
  final uncertaintySeconds = stdMax(0.05, residual);

  RecordingAlignment result(String status, String reason, {bool resolvedByDeclaredClock = false}) =>
      RecordingAlignment(
        status: status,
        reason: reason,
        declaredOffset: declaredOffset,
        offset: offset,
        driftPpm: driftPpm,
        uncertaintySeconds: uncertaintySeconds,
        correlation: correlation,
        peakUniqueness: peakUniqueness,
        confidence: confidence,
        overlapSeconds: overlapSeconds,
        windows: List.unmodifiable(windows),
        usedWindows: usedWindows,
        resolvedByDeclaredClock: resolvedByDeclaredClock,
      );

  if (whole.diagnostics.correlation < options.minimumWindowCorrelation) {
    return result(alignmentAmbiguous, 'weakMatch');
  }
  if (used.length < 2) return result(alignmentAmbiguous, 'tooFewWindows');
  if (residual > options.maximumResidualSeconds) {
    return result(alignmentAmbiguous, 'windowsDisagree');
  }
  if (driftPpm != null && driftPpm.abs() > options.maximumPlausibleDriftPpm) {
    return result(alignmentAmbiguous, 'implausibleDrift');
  }
  final declaredAgrees =
      declaredOffset != null &&
      (declaredOffset - offset).abs() <=
          stdMax(options.declaredToleranceSeconds, 3.0 * uncertaintySeconds);
  if (declaredOffset != null && !declaredAgrees) {
    return result(alignmentConflicting, 'declaredClockDisagrees');
  }
  // Laps repeat: the speed traces often also match one lap away. The match
  // alone decides only when it is unique; otherwise an agreeing declared
  // clock can tell which lap it is, and without one it stays ambiguous.
  if (whole.confidence < automaticSyncConfidenceThreshold) {
    if (!declaredAgrees) return result(alignmentAmbiguous, 'repeatedMatch');
    return result(alignmentAligned, '', resolvedByDeclaredClock: true);
  }
  return result(alignmentAligned, '');
}

// static_cast<int> of a double: truncation toward zero; out of range is
// undefined in C++, saturated here.
int _toInt(double value) {
  if (value.isNaN) return 0;
  if (value >= 2147483647.0) return 2147483647;
  if (value <= -2147483648.0) return -2147483648;
  return value.toInt();
}

int _clampInt(int value, int low, int high) => value < low
    ? low
    : high < value
    ? high
    : value;
