// Reading, validating and writing version 3 (event) documents, following
// FlappedEar Overlays' EventProjectCodec, ProjectLimits, BoundedJsonLoader and
// the validators they call (VBOOverlay ca2bde5) (FET-25).
import 'dart:convert';
import 'dart:io';

import 'hash_ids.dart';
import 'qt_json.dart';
import 'source_reference.dart';
import 'track_segments.dart';

/// Largest document or recovery snapshot, in bytes.
const int maximumProjectBytes = 4 * 1024 * 1024;
const int maximumJsonDepth = 32;

/// Longest JSON string or key, in UTF-16 code units (Qt's `QString::size`).
const int maximumStringCharacters = 4096;
const int maximumIdCharacters = 128;
const int maximumNameCharacters = 160;
const int maximumRuns = 64;
const int maximumSourcesPerRun = 8;
const int maximumTelemetrySources = 128;
const int maximumLapExclusions = 20000;
const int maximumExclusionReasonCharacters = 256;
const int maximumSegmentReviewDecisions = 64;
const int maximumComparisonChannels = 4;
const double maximumComparisonRangeMeters = 1000000.0;
const int maximumFusionRules = 64;
const double maximumFusionOffsetSeconds = 86400.0;
const double maximumFusionDriftPpm = 1000.0;
const int maximumWidgets = 256;
const int maximumCuesPerWidget = 256;
const int maximumTotalCues = 4096;
const int maximumSettingsEntries = 128;
const int _minimumChapters = 2;
const int _maximumChapters = 64;
const double _maximumChapterSeconds = 86400.0;

/// The algorithm stamp inside every lap reference.
const lapReferenceAlgorithm = 'source-laps-v1';

/// A document that cannot be opened or saved, and why.
final class FetprojectError implements Exception {
  const FetprojectError(this.message);

  final String message;

  @override
  String toString() => message;
}

final _digest = RegExp(r'^[0-9a-f]{64}$');
final _gates = RegExp(r'^gates-v1:[0-9a-f]{64}$');
final _compatibility = RegExp(r'^compatibility-v1:[0-9a-f]{64}$');

// Where Overlays checks only a regular expression, PCRE2's `$` also matches
// before a final newline, so a value ending in `\n` passes (matched as found;
// see README). Where it also checks the length, the strict forms above apply.
final _digestOrNewline = RegExp(r'^[0-9a-f]{64}\n?$');
final _gatesOrNewline = RegExp(r'^gates-v1:[0-9a-f]{64}\n?$');
final _compatibilityOrNewline = RegExp(r'^compatibility-v1:[0-9a-f]{64}\n?$');

bool _isNumber(Object? value) => value is num;
double _number(Object? value) => (value as num).toDouble();
bool _isText(Object? value, int limit) =>
    value is String &&
    qtTrimmed(value).isNotEmpty &&
    !value.contains('\u0000') &&
    value.length <= limit;

Map<String, Object?>? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;

/// Decodes and validates a `.fetproject` file's bytes. Throws
/// [FetprojectError] with a reason for anything that is not a valid version 3
/// document; version 2 single-recording projects are refused (plan decision
/// 10).
Map<String, Object?> decodeFetproject(List<int> bytes) {
  if (bytes.length > maximumProjectBytes) {
    throw FetprojectError(
      'The document is ${bytes.length} bytes; the limit is $maximumProjectBytes bytes.',
    );
  }
  final Object? decoded;
  try {
    decoded = qtJsonDecode(utf8.decode(bytes));
  } on FormatException catch (error) {
    throw FetprojectError('The document is not valid JSON: ${error.message}');
  }
  final project = _object(decoded);
  if (project == null) {
    throw const FetprojectError('The document is not a JSON object.');
  }
  if (project['version'] == 2) {
    throw const FetprojectError(
      'This is a single-recording FlappedEar Overlays project (version 2). '
      'Telemetry opens day documents (version 3); import the recording instead.',
    );
  }
  final error = validateFetproject(project);
  if (error != null) throw FetprojectError(error);
  return project;
}

/// Why [project] is not a valid version 3 document, or null when it is.
String? validateFetproject(Map<String, Object?> project) {
  final generic = _validateValue(project, 0);
  if (generic != null) return generic;
  if (project['version'] != 3) return 'Unsupported project version.';
  final event = _validateEvent(project);
  if (event != null) return event;
  if (!project.containsKey('scene')) return null;
  final scene = _object(project['scene']);
  final widgets = scene?['widgets'];
  if (widgets is! List) return 'Project scene/widgets structure is missing.';
  return _validateWidgets(widgets);
}

String? _validateValue(Object? value, int depth) {
  if (depth > maximumJsonDepth) {
    return 'JSON nesting exceeds $maximumJsonDepth levels.';
  }
  if (value is String && value.length > maximumStringCharacters) {
    return 'JSON string exceeds $maximumStringCharacters characters.';
  }
  if (value is List) {
    for (final item in value) {
      final error = _validateValue(item, depth + 1);
      if (error != null) return error;
    }
  } else if (value is Map) {
    for (final entry in value.entries) {
      if ((entry.key as String).length > maximumStringCharacters) {
        return 'JSON string exceeds $maximumStringCharacters characters.';
      }
      final error = _validateValue(entry.value, depth + 1);
      if (error != null) return error;
    }
  }
  return null;
}

String? _validateWidgets(List<Object?> widgets) {
  if (widgets.length > maximumWidgets) {
    return 'Widget count exceeds $maximumWidgets.';
  }
  var totalCues = 0;
  for (final value in widgets) {
    final widget = _object(value);
    if (widget == null) return 'Each widget must be a JSON object.';
    final id = widget['id'], type = widget['type'];
    if (id is! String ||
        id.isEmpty ||
        id.length > maximumIdCharacters ||
        type is! String ||
        type.isEmpty ||
        type.length > maximumIdCharacters) {
      return 'Widget id or type is missing or too long.';
    }
    if (widget.containsKey('settings')) {
      final settings = _object(widget['settings']);
      if (settings == null) return 'Widget settings must be an object.';
      if (settings.length > maximumSettingsEntries) {
        return 'Widget settings exceed $maximumSettingsEntries entries.';
      }
    }
    if (widget.containsKey('cues')) {
      final cues = widget['cues'];
      if (cues is! List) return 'Widget cues must be an array.';
      totalCues += cues.length;
      if (cues.length > maximumCuesPerWidget || totalCues > maximumTotalCues) {
        return 'Widget cue count exceeds the project limit.';
      }
    }
  }
  return null;
}

/// Whether [reference] is a lap reference: exactly the ten fields, version
/// 1, valid identities and digests, a known section type and finite bounds.
bool validLapReference(Map<String, Object?> reference) {
  if (reference.length != 10 || reference['version'] != 1) return false;
  for (final key in ['eventId', 'runId', 'sourceId', 'algorithm']) {
    final value = reference[key];
    if (value is! String ||
        qtTrimmed(value).isEmpty ||
        value.length > 128 ||
        value.contains('\u0000')) {
      return false;
    }
  }
  for (final key in ['sourceRevision', 'derivationKey']) {
    final value = reference[key];
    if (value is! String || !_digestOrNewline.hasMatch(value)) return false;
  }
  if (!const ['OUT', 'LAP', 'IN', 'UNKNOWN'].contains(reference['type'])) {
    return false;
  }
  final start = reference['startTime'], end = reference['endTime'];
  if (!_isNumber(start) || !_isNumber(end)) return false;
  final a = _number(start), b = _number(end);
  return a.isFinite && b.isFinite && a >= 0 && b > a;
}

/// Whether [value] is a valid `lapExclusions` array for [eventId]: absent,
/// or unique two-key entries of a LAP reference and a reason.
bool validLapExclusions(
  Object? value,
  Object? eventId, {
  required bool present,
}) {
  if (!present) return true;
  if (value is! List || value.length > maximumLapExclusions) return false;
  final seen = <String>{};
  for (final item in value) {
    final entry = _object(item);
    final reference = _object(entry?['reference']);
    final reason = entry?['reason'];
    if (entry == null ||
        reference == null ||
        entry.length != 2 ||
        !validLapReference(reference) ||
        reference['type'] != 'LAP' ||
        reference['eventId'] != eventId ||
        reason is! String ||
        qtTrimmed(reason).isEmpty ||
        reason.length > maximumExclusionReasonCharacters ||
        reason.contains('\u0000')) {
      return false;
    }
    if (!seen.add(lapReferenceKey(reference))) return false;
  }
  return true;
}

bool _validReference(Object? value) {
  final reference = _object(value);
  if (reference == null) return false;
  for (final key in ['relativePath', 'absolutePath']) {
    if (reference.containsKey(key) && reference[key] is! String) return false;
    if (((reference[key] as String?) ?? '').contains('\u0000')) return false;
  }
  final relative = (reference['relativePath'] as String?) ?? '';
  final absolute = (reference['absolutePath'] as String?) ?? '';
  if (qtTrimmed(relative).isEmpty && qtTrimmed(absolute).isEmpty) return false;
  if (relative.isNotEmpty && qtIsAbsolutePath(relative)) return false;
  if (absolute.isNotEmpty && !qtIsAbsolutePath(absolute)) return false;
  return !reference.containsKey('fingerprint') ||
      reference['fingerprint'] is Map;
}

/// The fingerprint of [run]'s primary telemetry source, or an empty map.
Map<String, Object?> primaryFingerprint(Map<String, Object?> run) {
  final sources = _object(run['sources']);
  final telemetry = sources?['telemetry'];
  if (telemetry is List) {
    for (final value in telemetry) {
      final source = _object(value);
      if (source != null && source['id'] == run['primaryTelemetrySourceId']) {
        final fingerprint = _object(
          _object(source['reference'])?['fingerprint'],
        );
        return fingerprint ?? {};
      }
    }
  }
  return {};
}

bool _jsonEquals(Object? a, Object? b) => qtCompactJson(a) == qtCompactJson(b);

bool _validConfiguration(Map<String, Object?> run) {
  if (!run.containsKey('trackConfiguration')) return true;
  final config = _object(run['trackConfiguration']);
  if (config == null) return false;
  final layout = config['layoutId'];
  final direction = config['direction'];
  final revision = config['gateRevision'];
  // Qt's isNull() is false for an absent key, so both must be present.
  return config.containsKey('layoutId') &&
      (layout == null || _isText(layout, maximumIdCharacters)) &&
      const ['unknown', 'clockwise', 'counterclockwise'].contains(direction) &&
      config.containsKey('gateRevision') &&
      (revision == null ||
          (revision is String && _gatesOrNewline.hasMatch(revision))) &&
      config['sourceId'] == run['primaryTelemetrySourceId'] &&
      config['sourceFingerprint'] is Map &&
      _jsonEquals(config['sourceFingerprint'], primaryFingerprint(run));
}

bool _validFusion(Map<String, Object?> run) {
  if (!run.containsKey('fusion')) return true;
  final fusion = _object(run['fusion']);
  if (fusion == null) return false;
  final alternative = fusion['alternativeSourceId'];
  if (fusion['algorithm'] != 'channel-fusion-v1' ||
      !_isText(alternative, maximumIdCharacters) ||
      alternative == run['primaryTelemetrySourceId']) {
    return false;
  }
  final telemetry = _object(run['sources'])?['telemetry'];
  if (telemetry is! List ||
      !telemetry.any((value) => _object(value)?['id'] == alternative)) {
    return false;
  }
  for (final key in ['primarySourceRevision', 'alternativeSourceRevision']) {
    final revision = fusion[key];
    if (revision is! String || !_digest.hasMatch(revision)) return false;
  }
  final clock = _object(fusion['clock']);
  if (clock == null) return false;
  final offset = clock['offsetSeconds'], drift = clock['driftPpm'];
  final uncertainty = clock['uncertaintySeconds'];
  if (!_isNumber(offset) ||
      !_isNumber(drift) ||
      !_isNumber(uncertainty) ||
      _number(offset).abs() > maximumFusionOffsetSeconds ||
      _number(drift).abs() > maximumFusionDriftPpm ||
      _number(uncertainty) < 0 ||
      _number(uncertainty) > maximumFusionOffsetSeconds) {
    return false;
  }
  final rules = fusion['rules'];
  if (rules is! List || rules.length > maximumFusionRules) return false;
  final keys = <Object?>{};
  for (final value in rules) {
    final rule = _object(value);
    if (rule == null ||
        !_isText(rule['key'], maximumIdCharacters) ||
        !keys.add(rule['key']) ||
        !const [
          'primaryOnly',
          'fillGaps',
          'preferAlternative',
        ].contains(rule['rule'])) {
      return false;
    }
  }
  return true;
}

bool _validReview(Object? value, {required bool present}) {
  if (!present || value == null) return true;
  final review = _object(value);
  if (review == null ||
      review.length != 4 ||
      review['version'] != 'track-segment-review-v1') {
    return false;
  }
  final reference = review['trackConfigurationReference'];
  final algorithm = review['proposalAlgorithm'];
  if (reference is! String ||
      !_compatibilityOrNewline.hasMatch(reference) ||
      algorithm is! String ||
      qtTrimmed(algorithm).isEmpty ||
      algorithm.length > 64 ||
      algorithm.contains('\u0000')) {
    return false;
  }
  final rejected = review['rejected'];
  if (rejected is! List || rejected.length > maximumSegmentReviewDecisions) {
    return false;
  }
  for (final item in rejected) {
    final decision = _object(item);
    if (decision == null ||
        decision.length != 3 ||
        !const ['sector', 'corner', 'straight'].contains(decision['type'])) {
      return false;
    }
    final start = decision['startProgressMeters'],
        end = decision['endProgressMeters'];
    bool bound(Object? meters) =>
        _isNumber(meters) &&
        _number(meters).isFinite &&
        _number(meters) >= 0 &&
        _number(meters) <= 1e6;
    if (!bound(start) || !bound(end) || _number(start) == _number(end)) {
      return false;
    }
  }
  return true;
}

bool _validInference(Object? value) {
  final inference = _object(value);
  if (inference == null) return false;
  final revision = inference['sourceRevision'];
  final gate = inference['gateRevision'];
  final layout = inference['layoutId'];
  return _isText(inference['algorithm'], 128) &&
      revision is String &&
      _digest.hasMatch(revision) &&
      inference.containsKey('gateRevision') &&
      (gate == null || (gate is String && _gates.hasMatch(gate))) &&
      _isText(layout, 128) &&
      (layout as String).length > 13 &&
      layout.startsWith('gps-route-v1:') &&
      const ['clockwise', 'counterclockwise'].contains(inference['direction']);
}

bool _validVideo(Map<String, Object?> video) {
  if (!video.containsKey('chapters')) return true;
  final chapters = video['chapters'];
  if (chapters is! List ||
      chapters.length < _minimumChapters ||
      chapters.length > _maximumChapters) {
    return false;
  }
  bool validPath(Map<String, Object?> object, String key, bool absolute) {
    if (!object.containsKey(key)) return true;
    final value = object[key];
    if (value is! String || value.contains('\u0000') || value.length > 4096) {
      return false;
    }
    return value.isEmpty || qtIsAbsolutePath(value) == absolute;
  }

  for (final item in chapters) {
    final chapter = _object(item);
    if (chapter == null ||
        !validPath(chapter, 'relativePath', false) ||
        !validPath(chapter, 'absolutePath', true)) {
      return false;
    }
    if (qtTrimmed((chapter['relativePath'] as String?) ?? '').isEmpty &&
        qtTrimmed((chapter['absolutePath'] as String?) ?? '').isEmpty) {
      return false;
    }
    if (chapter.containsKey('fingerprint') && chapter['fingerprint'] is! Map) {
      return false;
    }
    final duration = chapter['durationSeconds'];
    if (!_isNumber(duration) ||
        !_number(duration).isFinite ||
        _number(duration) <= 0 ||
        _number(duration) > _maximumChapterSeconds) {
      return false;
    }
  }
  // The first chapter is the video reference itself.
  final first = _object(chapters.first)!;
  return ['relativePath', 'absolutePath', 'fingerprint'].every(
    (key) =>
        first.containsKey(key) == video.containsKey(key) &&
        _jsonEquals(first[key], video[key]),
  );
}

String? _validateDecisions(Map<String, Object?> event) {
  if (!event.containsKey('analysisDecisions')) return null;
  final decisions = _object(event['analysisDecisions']);
  if (decisions == null) return 'Analysis decisions must be an object.';
  final group = decisions['comparisonGroupId'];
  if (decisions.containsKey('comparisonGroupId') &&
      group != null &&
      (group is! String || !_compatibility.hasMatch(group))) {
    return 'Saved comparison group is malformed.';
  }
  if (decisions.containsKey('comparisonSlots')) {
    final slots = decisions['comparisonSlots'];
    if (slots is! List || slots.length != 2) {
      return 'Saved comparison slots must be a pair.';
    }
    for (final item in slots) {
      if (item == null) continue;
      final reference = _object(item);
      if (reference == null ||
          !validLapReference(reference) ||
          reference['type'] != 'LAP' ||
          reference['eventId'] != event['id']) {
        return 'Saved comparison slot reference is invalid.';
      }
    }
  }
  final range = decisions['comparisonRange'];
  if (decisions.containsKey('comparisonRange') && range != null) {
    final object = _object(range);
    if (object == null) return 'Saved comparison range must be an object.';
    final start = object['startMeters'], end = object['endMeters'];
    if (!_isNumber(start) ||
        !_isNumber(end) ||
        !_number(start).isFinite ||
        !_number(end).isFinite ||
        _number(start) < 0 ||
        _number(end) <= _number(start) ||
        _number(end) > maximumComparisonRangeMeters) {
      return 'Saved comparison range is malformed.';
    }
  }
  final channels = decisions['comparisonChannels'];
  if (decisions.containsKey('comparisonChannels') && channels != null) {
    if (channels is! List || channels.length > maximumComparisonChannels) {
      return 'Saved comparison channels must be a bounded array.';
    }
    final seen = <Object?>{};
    for (final item in channels) {
      if (!_isText(item, maximumIdCharacters) || !seen.add(item)) {
        return 'Saved comparison channel entry is invalid or duplicated.';
      }
    }
  }
  return null;
}

String? _validateEvent(Map<String, Object?> project) {
  for (final key in ['sources', 'sync', 'videoPath', 'vboPath']) {
    if (project.containsKey(key)) {
      return 'Event projects cannot contain root $key.';
    }
  }
  final event = _object(project['event']) ?? const <String, Object?>{};
  final decisions = _validateDecisions(event);
  if (decisions != null) return decisions;
  if (!_isText(event['id'], maximumIdCharacters) ||
      !_isText(event['name'], maximumNameCharacters) ||
      !_isText(event['activeRunId'], maximumIdCharacters) ||
      event['runs'] is! List) {
    return 'Event metadata is missing or malformed.';
  }
  if (!validLapExclusions(
    event['lapExclusions'],
    event['id'],
    present: event.containsKey('lapExclusions'),
  )) {
    return 'Lap exclusions contain an invalid reference, duplicate or reason.';
  }
  final runs = event['runs'] as List;
  if (runs.isEmpty || runs.length > maximumRuns) {
    return 'An event must contain 1–64 runs.';
  }
  final runIds = <Object?>{};
  final sourceIds = <Object?>{};
  for (final value in runs) {
    final run = _object(value) ?? const <String, Object?>{};
    if (!_isText(run['id'], maximumIdCharacters) ||
        runIds.contains(run['id']) ||
        !_isText(run['name'], maximumNameCharacters) ||
        !_isText(run['primaryTelemetrySourceId'], maximumIdCharacters)) {
      return 'Run metadata or identity is invalid.';
    }
    for (final key in ['notes', 'conditions', 'setupChanges']) {
      final text = run[key];
      if (run.containsKey(key) &&
          text != null &&
          (text is! String ||
              text.length > maximumStringCharacters ||
              text.contains('\u0000'))) {
        return 'Run notes, conditions and setup changes must be bounded text or unknown.';
      }
    }
    runIds.add(run['id']);
    final sources = _object(run['sources']) ?? const <String, Object?>{};
    final telemetry = sources['telemetry'];
    if (telemetry is! List ||
        telemetry.isEmpty ||
        telemetry.length > maximumSourcesPerRun) {
      return 'Each run must contain 1–8 telemetry sources.';
    }
    var primaryFound = false;
    for (final sourceValue in telemetry) {
      final source = _object(sourceValue) ?? const <String, Object?>{};
      if (source.containsKey('contentSha256')) {
        final digest = source['contentSha256'];
        if (digest is! String || !_digest.hasMatch(digest)) {
          return 'Telemetry content identity is malformed.';
        }
      }
      if (!_isText(source['id'], maximumIdCharacters) ||
          sourceIds.contains(source['id']) ||
          !_validReference(source['reference'])) {
        return 'Telemetry source identity or reference is invalid.';
      }
      sourceIds.add(source['id']);
      primaryFound |= source['id'] == run['primaryTelemetrySourceId'];
    }
    if (!primaryFound || sourceIds.length > maximumTelemetrySources) {
      return 'Primary telemetry source is missing or event source limit exceeded.';
    }
    if (!_validConfiguration(run)) {
      return 'Track configuration or its primary source binding is invalid.';
    }
    if (!validTrackSegments(run['trackSegments'])) {
      return 'Track segments are invalid, out of order, or exceed the bound.';
    }
    if (!_validReview(
      run['trackSegmentReview'],
      present: run.containsKey('trackSegmentReview'),
    )) {
      return 'Track segment review decisions are invalid or exceed the bound.';
    }
    if (run.containsKey('trackInference') &&
        !_validInference(run['trackInference'])) {
      return 'Track inference provenance is malformed.';
    }
    if (!_validFusion(run)) {
      return "Source fusion decision is malformed or not bound to this run's recordings.";
    }
    if (sources.containsKey('video') &&
        (!_validReference(sources['video']) ||
            !_validVideo(_object(sources['video'])!))) {
      return 'Run video reference is invalid.';
    }
    final sync = _object(run['sync']) ?? const <String, Object?>{};
    final offset = sync['offset'], scale = sync['timeScale'];
    if (!_isNumber(offset) ||
        !_isNumber(scale) ||
        !_number(offset).isFinite ||
        !_number(scale).isFinite ||
        _number(scale) <= 0) {
      return 'Run synchronization is invalid.';
    }
  }
  if (!runIds.contains(event['activeRunId'])) {
    return 'Active run does not belong to the event.';
  }
  return null;
}

/// [project] as `QJsonDocument::toJson(QJsonDocument::Indented)` writes it:
/// four-space indentation, keys in code point order, and a final newline.
String encodeFetproject(Map<String, Object?> project) {
  final buffer = StringBuffer();
  void write(Object? value, int indent) {
    final inner = '    ' * (indent + 1);
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort(compareByCodePoint);
      buffer.write('{\n');
      for (var i = 0; i < keys.length; ++i) {
        buffer.write('$inner${qtCompactJson(keys[i])}: ');
        write(value[keys[i]], indent + 1);
        buffer.write(i + 1 < keys.length ? ',\n' : '\n');
      }
      buffer.write('${'    ' * indent}}');
    } else if (value is List) {
      buffer.write('[\n');
      for (var i = 0; i < value.length; ++i) {
        buffer.write(inner);
        write(value[i], indent + 1);
        buffer.write(i + 1 < value.length ? ',\n' : '\n');
      }
      buffer.write('${'    ' * indent}]');
    } else {
      buffer.write(qtCompactJson(value));
    }
  }

  write(project, 0);
  buffer.write('\n');
  return buffer.toString();
}

/// Reads and validates the document at [path], refusing a file over
/// [maximumProjectBytes] before reading it.
Future<Map<String, Object?>> readFetproject(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw FetprojectError('$path is not a readable file.');
  }
  final size = await file.length();
  if (size > maximumProjectBytes) {
    throw FetprojectError(
      'The document is $size bytes; the limit is $maximumProjectBytes bytes.',
    );
  }
  return decodeFetproject(await file.readAsBytes());
}

/// Validates [project] and writes it to [path] atomically: to a temporary
/// file in the same folder, flushed, then renamed over [path], so a failed
/// save leaves the previous document whole.
///
/// Where the folder refuses the temporary file but [path] itself may be
/// written, [path] is written in place, which is not atomic. The macOS
/// sandbox grants the app only the file chosen in the save or open panel,
/// not its folder, so there the temporary file failed with "Cannot open
/// file" and nothing saved. The in-place write is read back; when it fails
/// or reads back differently, the previous document is written back if it
/// can be, and the save fails ([writeDocumentInPlace]).
Future<void> writeFetproject(String path, Map<String, Object?> project) async {
  if (path.isEmpty) throw const FetprojectError('Project path is empty.');
  final error = validateFetproject(project);
  if (error != null) throw FetprojectError(error);
  final bytes = utf8.encode(encodeFetproject(project));
  if (bytes.length > maximumProjectBytes) {
    throw FetprojectError(
      'The document would be ${bytes.length} bytes; the limit is $maximumProjectBytes bytes.',
    );
  }
  final temporary = File(
    '$path.${DateTime.now().microsecondsSinceEpoch}.$pid.tmp',
  );
  try {
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(path);
  } on FileSystemException catch (failure) {
    if (_permissionDenied(failure) && !await temporary.exists()) {
      return writeDocumentInPlace(path, bytes);
    }
    try {
      if (await temporary.exists()) await temporary.delete();
    } on FileSystemException {
      // The original failure is the one worth reporting.
    }
    throw FetprojectError('Could not save the project: ${failure.message}');
  }
}

/// Writes [bytes] over [path] and reads them back. On a failure (a full
/// disk partway, say) the previous content is written back when possible,
/// so a failed save does not leave a cut document behind; the error says
/// whether the previous document is unchanged or the file may be
/// incomplete. Not exported: `writeFetproject` uses it where the folder
/// refuses a temporary file. [write] stands in for the file write in tests.
Future<void> writeDocumentInPlace(
  String path,
  List<int> bytes, {
  Future<void> Function(File file, List<int> bytes)? write,
}) async {
  final file = File(path);
  final writeBytes =
      write ??
      (File file, List<int> bytes) => file.writeAsBytes(bytes, flush: true);
  // The previous document, when it can be read and is not larger than a
  // document may be (a large file chosen in Save As is not kept).
  List<int>? previous;
  try {
    if (await file.length() <= maximumProjectBytes) {
      previous = await file.readAsBytes();
    }
  } on FileSystemException {
    previous = null; // A new document, or not readable.
  }
  final existed = previous != null || await file.exists();
  // What is left after a failed write, for the message.
  Future<String> outcome() async {
    if (!existed) {
      try {
        if (await file.exists()) await file.delete();
        return '; nothing was saved';
      } on FileSystemException {
        return '; the file may be incomplete';
      }
    }
    return await _restore(file, previous, writeBytes)
        ? '; the previously saved version is unchanged'
        : '; the file may be incomplete';
  }

  try {
    await writeBytes(file, bytes);
  } on FileSystemException catch (failure) {
    final system = failure.osError?.message ?? '';
    throw FetprojectError(
      'Could not save the project: ${failure.message}'
      '${system.isEmpty ? '' : ' ($system)'}${await outcome()}',
    );
  }
  final List<int> written;
  try {
    written = await file.readAsBytes();
  } on FileSystemException {
    // Writable but not readable: the write itself succeeded.
    return;
  }
  if (!_sameBytes(written, bytes)) {
    throw FetprojectError(
      'Could not save the project: the saved document reads back differently'
      '${await outcome()}',
    );
  }
}

/// Writes [previous] back over [file] when there is one; whether [file]
/// now holds exactly [previous] (also when the failed write never touched
/// it).
Future<bool> _restore(
  File file,
  List<int>? previous,
  Future<void> Function(File file, List<int> bytes) write,
) async {
  if (previous == null) return false;
  try {
    if (_sameBytes(await file.readAsBytes(), previous)) return true;
  } on FileSystemException {
    // Not readable now: try writing it back.
  }
  try {
    await write(file, previous);
    return _sameBytes(await file.readAsBytes(), previous);
  } on FileSystemException {
    return false;
  }
}

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; ++i) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Whether [failure] is the system refusing access (EPERM or EACCES on
/// macOS and Linux, ERROR_ACCESS_DENIED on Windows), not a full disk or a
/// missing folder.
bool _permissionDenied(FileSystemException failure) =>
    switch (failure.osError?.errorCode) {
      1 || 13 => !Platform.isWindows,
      5 => Platform.isWindows,
      _ => false,
    };
