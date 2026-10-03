// Port of VBOOverlay native/src/telemetry/TelemetryImportPlan.{h,cpp} and the
// run naming of DocumentControllerImport.cpp (KAN-119) (FET-17): a list of
// recordings as the proposed runs of one day.
import 'dart:io';
import 'dart:math' as math;

import 'package:path/path.dart' as p;

import '../geometry.dart';
import '../laps/lap_detection.dart';
import '../laps/lap_session.dart';
import '../operation.dart';
import '../rcz/rcz_parser.dart';
import '../telemetry_session.dart';
import '../vbo/vbo_file.dart';
import 'recording_source.dart';

/// Parses the recording at [path] with the parser its extension names.
TelemetrySession loadRecording(String path, {CancellationCheck? cancelled}) =>
    switch (recordingFormatOf(path)) {
      RecordingFormat.vbo => parseVboFile(path, cancelled: cancelled),
      RecordingFormat.rcz => RczParser.parseFile(path, cancelled: cancelled),
      null => throw const RecordingSourceError('Choose a VBO or RaceChrono RCZ telemetry file.'),
    };

/// The absolute start of a recording in Unix milliseconds, from the recording
/// itself; null when it has no established clock. Never from a file name or
/// modification time.
int? recordingTimestamp(TelemetrySession session) =>
    int.tryParse(session.metadata['firstTimestampMilliseconds'] ?? '');

/// A recording proposed as a run. Review decides grouping before anything is
/// committed.
final class TelemetryRunProposal {
  const TelemetryRunProposal({
    required this.id,
    required this.sourceId,
    required this.sourcePath,
    required this.format,
    required this.contentSha256,
    required this.telemetry,
    required this.laps,
  });

  /// `run:` and the content SHA-256.
  final String id;

  /// `sha256:` and the content SHA-256.
  final String sourceId;

  /// The selected path, absolute and normalised; links are not resolved.
  final String sourcePath;
  final RecordingFormat format;

  /// Lowercase hex.
  final String contentSha256;
  final TelemetrySession telemetry;
  final LapSession laps;
}

enum TelemetryImportFileStatus { ready, duplicate, error }

/// What happened to one requested path.
final class TelemetryImportFileResult {
  const TelemetryImportFileResult({
    required this.requestedPath,
    required this.status,
    this.runId = '',
    this.message = '',
    this.detail = '',
  });

  final String requestedPath;
  final TelemetryImportFileStatus status;

  /// The retained proposal for ready and duplicate files; empty for errors.
  final String runId;
  final String message;

  /// For a defect ([unexpectedFileError]): its stack trace, for a bug
  /// report; empty otherwise.
  final String detail;
}

/// How [TelemetryImportFileResult.message] starts when reading the file hit
/// a defect (an [Error]) rather than a bad recording; the error follows.
const unexpectedFileError = 'Unexpected error while reading this file: ';

/// Two recordings of different formats whose GPS traces agree. Evidence, not
/// proof: it does not establish a common date or clock by itself.
final class TelemetryRunMatchCandidate {
  const TelemetryRunMatchCandidate({
    required this.firstRunId,
    required this.secondRunId,
    required this.comparedGpsSamples,
    required this.maximumSeparationMeters,
    required this.gpsDurationDifferenceSeconds,
    required this.reviewReason,
  });

  final String firstRunId;
  final String secondRunId;
  final int comparedGpsSamples;
  final double maximumSeparationMeters;
  final double gpsDurationDifferenceSeconds;
  final String reviewReason;
}

final class TelemetryImportPlan {
  TelemetryImportPlan({
    required List<TelemetryRunProposal> runs,
    required List<TelemetryImportFileResult> files,
    required List<TelemetryRunMatchCandidate> possibleSameRuns,
  }) : runs = List.unmodifiable(runs),
       files = List.unmodifiable(files),
       possibleSameRuns = List.unmodifiable(possibleSameRuns);

  /// Ready recordings in request order.
  final List<TelemetryRunProposal> runs;

  /// One result per requested path, in request order.
  final List<TelemetryImportFileResult> files;
  final List<TelemetryRunMatchCandidate> possibleSameRuns;
}

/// Batch ceilings. Callers may lower, never raise, them.
final class TelemetryImportLimits {
  const TelemetryImportLimits({
    this.maximumFiles = 64,
    this.maximumFileBytes = 128 * 1024 * 1024,
    this.maximumBatchBytes = 256 * 1024 * 1024,
    this.maximumRetainedChannelSamples = 16000000,
  });

  final int maximumFiles;
  final int maximumFileBytes;

  /// Every attempt counts, duplicates and failures included.
  final int maximumBatchBytes;
  final int maximumRetainedChannelSamples;

  void _validate() {
    const ceilings = TelemetryImportLimits();
    bool within(int value, int ceiling) => value > 0 && value <= ceiling;
    if (!within(maximumFiles, ceilings.maximumFiles) ||
        !within(maximumFileBytes, ceilings.maximumFileBytes) ||
        !within(maximumBatchBytes, ceilings.maximumBatchBytes) ||
        !within(maximumRetainedChannelSamples, ceilings.maximumRetainedChannelSamples)) {
      throw ArgumentError(
        'Import limits must be positive and no greater than the safety ceilings.',
      );
    }
  }
}

const int _maximumPathLength = 4096;

/// Prepares [paths] for review, sequentially and synchronously; run it off
/// the interface thread.
///
/// Each file is size-checked, hashed, parsed, counted against the sample
/// budget, given its laps and hashed again; a file that changed in between is
/// an error. Repeated content (per extension) is a duplicate of the first.
/// One file's error never stops the batch. Cancellation and an invalid or
/// oversized request throw, so no partial plan is ever returned. [progress]
/// receives (processed, total) before the first file and after each one.
TelemetryImportPlan prepareTelemetryImport(
  List<String> paths, {
  TelemetryImportLimits limits = const TelemetryImportLimits(),
  CancellationCheck? cancelled,
  void Function(int processed, int total)? progress,
}) {
  throwIfCancelled(cancelled);
  limits._validate();
  if (paths.length > limits.maximumFiles) {
    throw const ResourceLimitError('Too many files in one import; select a smaller batch.');
  }
  final runs = <TelemetryRunProposal>[];
  final files = <TelemetryImportFileResult>[];
  final retainedDigests = <String, String>{};
  var inputBytes = 0, retainedSamples = 0;
  progress?.call(0, paths.length);
  for (final path in paths) {
    throwIfCancelled(cancelled);
    TelemetryImportFileResult result;
    try {
      if (path.length > _maximumPathLength) {
        throw const ResourceLimitError('Telemetry source path is too long.');
      }
      final format = recordingFormatOf(path);
      if (format == null) {
        throw const RecordingSourceError('Choose a VBO or RaceChrono RCZ telemetry file.');
      }
      if (!FileSystemEntity.isFileSync(path)) {
        throw const RecordingSourceError('Telemetry source is not an existing regular file.');
      }
      final size = File(path).lengthSync();
      if (size <= 0 || size > limits.maximumFileBytes) {
        throw const ResourceLimitError(
          'Telemetry file is empty or exceeds the per-file import limit.',
        );
      }
      if (size > limits.maximumBatchBytes - inputBytes) {
        throw const ResourceLimitError('Batch input-byte limit exceeded; import fewer recordings.');
      }
      inputBytes += size;
      // The selected name decides the parser, also for a link to a backing
      // file named differently.
      final sourcePath = p.normalize(p.absolute(path));
      final digest = contentSha256(sourcePath, size, cancelled: cancelled);
      // A VBO renamed to RCZ must fail that parser, not inherit the real
      // VBO's result because its bytes are identical.
      final digestKey = '${format.name}:$digest';
      final duplicate = retainedDigests[digestKey];
      if (duplicate != null) {
        result = TelemetryImportFileResult(
          requestedPath: path,
          status: TelemetryImportFileStatus.duplicate,
          runId: duplicate,
          message: 'Identical file content already present in this batch.',
        );
      } else {
        final session = loadRecording(sourcePath, cancelled: cancelled);
        final samples = _channelSamples(
          session,
          limits.maximumRetainedChannelSamples - retainedSamples,
          cancelled,
        );
        final laps = deriveSourceLapSession(session, cancelled: cancelled);
        if (contentSha256(sourcePath, size, cancelled: cancelled) != digest) {
          throw const RecordingSourceError(
            'Telemetry source changed during import; retry with a stable file.',
          );
        }
        final run = TelemetryRunProposal(
          id: 'run:$digest',
          sourceId: recordingSourceId(digest),
          sourcePath: sourcePath,
          format: format,
          contentSha256: digest,
          telemetry: session,
          laps: laps,
        );
        retainedSamples += samples;
        retainedDigests[digestKey] = run.id;
        runs.add(run);
        result = TelemetryImportFileResult(
          requestedPath: path,
          status: TelemetryImportFileStatus.ready,
          runId: run.id,
        );
      }
    } on OperationCancelled {
      rethrow;
    } on FileSystemException catch (error) {
      result = _error(path, error.osError?.message ?? error.message);
    } on Exception catch (error) {
      result = _error(path, error.toString());
    } on Error catch (error, stack) {
      // A defect while reading one file (a bug, not a bad recording) marks
      // that file and leaves the others of the import alone.
      result = TelemetryImportFileResult(
        requestedPath: path,
        status: TelemetryImportFileStatus.error,
        message: '$unexpectedFileError$error',
        detail: '$stack',
      );
    }
    files.add(result);
    progress?.call(files.length, paths.length);
  }
  final matches = _findPossibleMatches(runs, cancelled);
  throwIfCancelled(cancelled);
  return TelemetryImportPlan(runs: runs, files: files, possibleSameRuns: matches);
}

TelemetryImportFileResult _error(String path, String message) => TelemetryImportFileResult(
  requestedPath: path,
  status: TelemetryImportFileStatus.error,
  message: message,
);

int _channelSamples(TelemetrySession session, int available, CancellationCheck? cancelled) {
  if (!session.duration.isFinite || session.duration < 0.0 || !session.startTime.isFinite) {
    throw const RecordingSourceError('Telemetry source has an invalid time range.');
  }
  var count = 0;
  for (final channel in session.channels.values) {
    throwIfCancelled(cancelled);
    if (channel.timestamps.length != channel.values.length) {
      throw const RecordingSourceError(
        'Telemetry source has mismatched channel timestamps and values.',
      );
    }
    if (channel.values.length > available - count) {
      throw const ResourceLimitError(
        'Batch decoded-sample limit exceeded; import fewer recordings.',
      );
    }
    count += channel.values.length;
  }
  return count;
}

const int _signatureSize = 32;
const int _minimumCompared = 29;
const double _maximumSeparationMeters = 10.0;

final class _TraceEvidence {
  final List<GeoCoordinate?> gps = List.filled(_signatureSize, null);
  double duration = 0.0;
  bool usable = false;
}

TelemetryChannel? _gpsChannel(TelemetrySession session, String alias) {
  final channel = session.channel(alias);
  if (channel == null ||
      channel.values.length < 16 ||
      channel.timestamps.length != channel.values.length) {
    return null;
  }
  return channel;
}

/// The raw sample nearest [time] within 0.6 s; never interpolated.
double? _nearbyRawValue(TelemetryChannel channel, double time) {
  final times = channel.timestamps;
  var index = lowerBound(times, time);
  if (index == times.length || (index > 0 && time - times[index - 1] <= times[index] - time)) {
    --index;
  }
  if (index < 0 || (times[index] - time).abs() > 0.6 || !channel.values[index].isFinite) {
    return null;
  }
  return channel.values[index];
}

/// The validated RaceChrono VBO export stores west-positive longitude and RCZ
/// east-positive; only the comparison evidence is normalised.
GeoCoordinate _matchingCoordinate(TelemetrySession session, double latitude, double longitude) =>
    GeoCoordinate(
      latitude,
      session.metadata['gpsLongitudeConvention'] == 'west-positive' ? -longitude : longitude,
    );

GeoCoordinate? _coordinateAt(TelemetrySession session, double time) {
  final latitude = _gpsChannel(session, 'latitude');
  final longitude = _gpsChannel(session, 'longitude');
  if (latitude == null || longitude == null) return null;
  final lat = _nearbyRawValue(latitude, time);
  final lon = _nearbyRawValue(longitude, time);
  if (lat == null || lon == null) return null;
  final coordinate = _matchingCoordinate(session, lat, lon);
  return isValidCoordinate(coordinate) ? coordinate : null;
}

_TraceEvidence _traceEvidence(TelemetrySession session, CancellationCheck? cancelled) {
  final evidence = _TraceEvidence();
  final latitude = _gpsChannel(session, 'latitude');
  final longitude = _gpsChannel(session, 'longitude');
  if (latitude == null || longitude == null) return evidence;
  final start = math.max(latitude.timestamps.first, longitude.timestamps.first);
  final end = math.min(latitude.timestamps.last, longitude.timestamps.last);
  evidence.duration = end - start;
  if (!start.isFinite || !evidence.duration.isFinite || evidence.duration < 10.0) {
    return evidence;
  }
  var valid = 0;
  GeoCoordinate? origin;
  var displacement = 0.0;
  for (var i = 0; i < _signatureSize; ++i) {
    throwIfCancelled(cancelled);
    final coordinate = _coordinateAt(session, start + evidence.duration * i / (_signatureSize - 1));
    if (coordinate == null) continue;
    evidence.gps[i] = coordinate;
    ++valid;
    origin ??= coordinate;
    final point = projectCoordinate(coordinate, origin);
    displacement = math.max(displacement, hypot(point.eastMeters, point.northMeters));
  }
  // A stationary paddock trace or sparse GPS is not useful evidence.
  evidence.usable = valid >= _minimumCompared && displacement >= 50.0;
  return evidence;
}

List<TelemetryRunMatchCandidate> _findPossibleMatches(
  List<TelemetryRunProposal> runs,
  CancellationCheck? cancelled,
) {
  final traces = [for (final run in runs) _traceEvidence(run.telemetry, cancelled)];
  final matches = <TelemetryRunMatchCandidate>[];
  for (var first = 0; first < runs.length; ++first) {
    for (var second = first + 1; second < runs.length; ++second) {
      throwIfCancelled(cancelled);
      if (runs[first].format == runs[second].format) continue;
      final a = traces[first], b = traces[second];
      final durationDifference = (a.duration - b.duration).abs();
      final tolerance = (math.min(a.duration, b.duration) * 0.01).clamp(1.0, 2.0);
      if (!a.usable || !b.usable || durationDifference > tolerance) continue;
      final firstSession = runs[first].telemetry, secondSession = runs[second].telemetry;
      final firstClock = recordingTimestamp(firstSession);
      final secondClock = recordingTimestamp(secondSession);
      final sameClock =
          firstClock != null && secondClock != null && (firstClock - secondClock).abs() <= 1000;
      final shift = sameClock ? (secondClock - firstClock) / 1000.0 : 0.0;
      var compared = 0;
      var maximumSeparation = 0.0;
      for (var i = 0; i < _signatureSize; ++i) {
        throwIfCancelled(cancelled);
        var firstGps = a.gps[i], secondGps = b.gps[i];
        if (sameClock) {
          // Compare the same absolute instant, not equal fractions of two
          // exports whose first and last samples may differ.
          final begin = math.max(0.0, shift);
          final end = math.min(firstSession.duration, shift + secondSession.duration);
          final time = begin + (end - begin) * i / (_signatureSize - 1);
          firstGps = _coordinateAt(firstSession, time);
          secondGps = _coordinateAt(secondSession, time - shift);
        }
        if (firstGps == null || secondGps == null) continue;
        final point = projectCoordinate(firstGps, secondGps);
        maximumSeparation = math.max(maximumSeparation, hypot(point.eastMeters, point.northMeters));
        ++compared;
      }
      if (compared < _minimumCompared || maximumSeparation > _maximumSeparationMeters) continue;
      matches.add(
        TelemetryRunMatchCandidate(
          firstRunId: runs[first].id,
          secondRunId: runs[second].id,
          comparedGpsSamples: compared,
          maximumSeparationMeters: maximumSeparation,
          gpsDurationDifferenceSeconds: durationDifference,
          reviewReason:
              'Similar elapsed GPS traces in VBO and RCZ. Confirm recording date, clock and '
              'source grouping; files have not been merged.',
        ),
      );
    }
  }
  return matches;
}

/// Groups each RCZ under the VBO it uniquely matches: starts within 1 s,
/// durations within 2 s, and the GPS evidence of [TelemetryRunMatchCandidate].
/// VBO is primary and the RCZ an alternative source, whose channels
/// [fuseImportedRuns] fuses into it. Returns run id to group id (the primary's id); a run that is its
/// own primary maps to itself. Undated, differently dated and ambiguous
/// matches stay separate.
Map<String, String> automaticVboPrimaries(TelemetryImportPlan plan) {
  if (plan.runs.length > 64 || plan.possibleSameRuns.length > 2016) {
    throw const ResourceLimitError('Source grouping exceeds the import limit.');
  }
  final runs = {for (final run in plan.runs) run.id: run};
  final groups = {for (final run in plan.runs) run.id: run.id};
  final matches = <(String, String)>[];
  final counts = <String, int>{};
  for (final match in plan.possibleSameRuns) {
    final a = runs[match.firstRunId], b = runs[match.secondRunId];
    if (a == null || b == null || a.format == b.format) continue;
    final first = recordingTimestamp(a.telemetry), second = recordingTimestamp(b.telemetry);
    if (first == null ||
        second == null ||
        (first - second).abs() > 1000 ||
        (a.telemetry.duration - b.telemetry.duration).abs() > 2) {
      continue;
    }
    if (match.comparedGpsSamples < _minimumCompared ||
        !match.maximumSeparationMeters.isFinite ||
        match.maximumSeparationMeters > _maximumSeparationMeters) {
      continue;
    }
    final primary = a.format == RecordingFormat.vbo ? a : b;
    final alternative = a.format == RecordingFormat.rcz ? a : b;
    if (primary.format != RecordingFormat.vbo || alternative.format != RecordingFormat.rcz) {
      continue;
    }
    matches.add((alternative.id, primary.id));
    counts[a.id] = (counts[a.id] ?? 0) + 1;
    counts[b.id] = (counts[b.id] ?? 0) + 1;
  }
  for (final (alternative, primary) in matches) {
    if (counts[alternative] == 1 && counts[primary] == 1) groups[alternative] = primary;
  }
  return groups;
}

/// Whether [a] and [b] are one drive recorded as a VBO and an RCZ, by the
/// rules of [automaticVboPrimaries]: used when a recording is added to a day
/// that already has the other one.
bool sameDriveInOtherFormat(
  TelemetryRunProposal a,
  TelemetryRunProposal b, {
  CancellationCheck? cancelled,
}) {
  if (a.format == b.format || a.id == b.id) return false;
  final first = recordingTimestamp(a.telemetry), second = recordingTimestamp(b.telemetry);
  // The cheap checks first: most pairs are told apart by their clocks.
  if (first == null ||
      second == null ||
      (first - second).abs() > 1000 ||
      (a.telemetry.duration - b.telemetry.duration).abs() > 2) {
    return false;
  }
  final plan = TelemetryImportPlan(
    runs: [a, b],
    files: const [],
    possibleSameRuns: _findPossibleMatches([a, b], cancelled),
  );
  final groups = automaticVboPrimaries(plan);
  return groups[a.id] != a.id || groups[b.id] != b.id;
}

/// A primary run and the name it gets.
typedef NamedRun = ({TelemetryRunProposal run, String name});

/// Names [primaries] "Session N" in recording-time order, continuing after
/// [existingRuns] runs already in the day. A run without a recording clock
/// follows the dated ones, in the given order. Names are meant to be stored,
/// so they never renumber.
List<NamedRun> nameRunsInRecordingOrder(
  List<TelemetryRunProposal> primaries, {
  int existingRuns = 0,
}) {
  final order = List.generate(primaries.length, (index) => index);
  final starts = [for (final run in primaries) recordingTimestamp(run.telemetry)];
  order.sort((left, right) {
    final a = starts[left], b = starts[right];
    if ((a == null) != (b == null)) return a == null ? 1 : -1;
    if (a != null && b != null && a != b) return a.compareTo(b);
    return left.compareTo(right); // stable
  });
  var number = existingRuns;
  return [for (final index in order) (run: primaries[index], name: 'Session ${++number}')];
}

/// Guards background results (AGENTS.md: "Background work"). Each [begin]
/// starts a new generation; a result may change committed state only while
/// its ticket is still current and names the same sources.
final class ImportGeneration {
  int _current = 0;
  Set<String> _sources = const {};

  /// Starts a generation for [sourceIds], making every earlier ticket stale.
  ImportTicket begin(Iterable<String> sourceIds) {
    _sources = Set.unmodifiable(sourceIds);
    return ImportTicket._(++_current, _sources);
  }

  /// Makes every outstanding ticket stale, for example when the day closes.
  void invalidate() {
    ++_current;
    _sources = const {};
  }

  /// Whether a result carrying [ticket] may still be committed.
  bool isCurrent(ImportTicket ticket) =>
      ticket._generation == _current &&
      ticket._sources.length == _sources.length &&
      ticket._sources.containsAll(_sources);
}

final class ImportTicket {
  const ImportTicket._(this._generation, this._sources);
  final int _generation;
  final Set<String> _sources;
}
