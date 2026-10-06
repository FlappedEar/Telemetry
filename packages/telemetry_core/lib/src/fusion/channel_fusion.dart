// Port of FlappedEar Overlays native/src/telemetry/ChannelFusion.{h,cpp}
// (revision d4d1039, channel-fusion-v1) (FET-50): channels from a run's
// alternative recordings brought onto the primary recording's clock, with
// the provenance of every output sample and an explicit rule wherever two
// recordings measure the same thing. Nothing is overwritten silently:
// - a source is used only when its clock alignment was "aligned";
// - a channel only an alternative has is added on the primary clock;
// - a channel both have keeps the primary unless a rule says otherwise; if
//   their overlapping measurements disagree and no rule was chosen, the
//   conflict is reported as unresolved;
// - units must match exactly; nothing is rescaled.
// One deliberate difference from Overlays: an added speed takes the unit its
// own recording declares (a VBO `[header]` line, FET-112), where Overlays
// keeps the channel's raw, empty unit.
// Samples are never resampled or interpolated: each output sample is a real
// sample of one source with its timestamp transformed, so gaps stay gaps.
import 'dart:typed_data';

import '../operation.dart';
import '../speed_units.dart';
import '../telemetry_session.dart';
import 'std_math.dart';

const channelFusionAlgorithm = 'channel-fusion-v1';

/// `primaryTime = sourceTime + offsetSeconds + driftPpm * 1e-6 * sourceTime`.
final class SourceClock {
  const SourceClock({this.offsetSeconds = 0.0, this.driftPpm = 0.0});

  final double offsetSeconds;
  final double driftPpm;
}

/// An alternative recording offered for fusion.
final class FusionSource {
  const FusionSource({
    required this.sourceId,
    required this.session,
    this.clock = const SourceClock(),
    required this.alignmentStatus,
  });

  final String sourceId;
  final TelemetrySession? session;
  final SourceClock clock;

  /// Must be "aligned".
  final String alignmentStatus;
}

enum FusionRule {
  /// Keep the primary's samples.
  primaryOnly,

  /// The primary, plus the alternative where the primary has none.
  fillGaps,

  /// The alternative, plus the primary where the alternative has none.
  preferAlternative,
}

/// The rule chosen for one channel and the alternative source it applies to.
typedef FusionChoice = ({String sourceId, FusionRule rule});

final class FusionPolicy {
  const FusionPolicy({this.rules = const {}});

  /// By channel key (the alias when the channel has one, e.g. "speed",
  /// otherwise its name).
  final Map<String, FusionChoice> rules;
}

/// Contiguous output samples of one source.
final class FusedSegment {
  const FusedSegment({
    required this.sourceId,
    required this.start,
    required this.end,
    required this.clock,
    required this.sampleIntervalSeconds,
  });

  final String sourceId;

  /// On the primary clock.
  final double start;
  final double end;
  final SourceClock clock;

  /// The source's median spacing: its real resolution.
  final double sampleIntervalSeconds;
}

final class FusedChannel {
  FusedChannel({
    required this.key,
    required this.name,
    required this.unit,
    required this.rule,
    required this.segments,
    required this.channel,
  });

  final String key;
  final String name;
  final String unit;

  /// "primary", "added", "fillGaps", "preferAlternative" or
  /// "unresolvedConflict".
  String rule;
  List<FusedSegment> segments;
  TelemetryChannel channel;

  /// When an alternative also measured it: how the overlap compared.
  String comparedSourceId = '';
  int comparedSamples = 0;
  double medianDifference = 0.0;
  bool conflicting = false;
}

final class ChannelFusionResult {
  final List<FusedChannel> channels = [];

  /// Keys whose conflict has no rule.
  final List<String> unresolved = [];

  /// "key: sourceId" pairs that were not fused.
  final List<String> unitMismatches = [];

  /// Source IDs whose clocks are not aligned.
  final List<String> refusedSources = [];
}

final class _Sample {
  const _Sample(this.time, this.value, this.source);

  final double time;
  final double value; // a float32
  final int source; // 0 = primary, 1 = the alternative
}

final class _Span {
  _Span(this.start, this.end);

  final double start;
  double end;
}

bool _validClock(SourceClock clock) =>
    clock.offsetSeconds.isFinite && clock.driftPpm.isFinite && 1.0 + clock.driftPpm * 1e-6 > 0.0;

double _toPrimary(double time, SourceClock clock) =>
    time + clock.offsetSeconds + clock.driftPpm * 1e-6 * time;

// The middle step, upper median, counting every step as Overlays does.
double _medianInterval(List<double> times) {
  if (times.length < 2) return 0.0;
  final steps = Float64List(times.length - 1);
  for (var index = 1; index < times.length; ++index) {
    steps[index - 1] = times[index] - times[index - 1];
  }
  steps.sort();
  return steps[steps.length ~/ 2];
}

// Contiguous stretches: a step longer than [gap] splits them.
List<_Span> _spans(List<double> times, double gap) {
  final result = <_Span>[];
  for (final time in times) {
    if (result.isEmpty || (gap > 0.0 && time - result.last.end > gap)) {
      result.add(_Span(time, time));
    } else {
      result.last.end = time;
    }
  }
  return result;
}

bool _covered(List<_Span> coverage, double time) {
  // The first span starting after [time].
  var low = 0, high = coverage.length;
  while (low < high) {
    final middle = low + ((high - low) >> 1);
    if (time < coverage[middle].start) {
      high = middle;
    } else {
      low = middle + 1;
    }
  }
  return low != 0 && time <= coverage[low - 1].end;
}

// The key a channel is matched by: its alias when it has one, else its name.
String _channelKey(TelemetrySession session, String name) {
  final aliases = [
    for (final entry in session.aliases.entries)
      if (entry.value == name) entry.key,
  ];
  if (aliases.isEmpty) return name;
  aliases.sort();
  return aliases.first;
}

String _primaryNameFor(TelemetrySession primary, String key, String alternativeName) {
  final aliased = primary.aliases[key] ?? '';
  if (aliased.isNotEmpty && primary.channels.containsKey(aliased)) return aliased;
  return primary.channels.containsKey(alternativeName) ? alternativeName : '';
}

// Output samples of one source as segments of contiguous stretches.
void _appendSegments(
  List<FusedSegment> segments,
  List<_Sample> samples,
  int source,
  String sourceId,
  SourceClock clock,
  double gap,
  double interval,
) {
  for (var index = 0; index < samples.length; ++index) {
    if (samples[index].source != source) continue;
    final continues =
        index > 0 &&
        samples[index - 1].source == source &&
        !(gap > 0.0 && samples[index].time - samples[index - 1].time > gap) &&
        segments.isNotEmpty &&
        segments.last.sourceId == sourceId;
    if (continues) {
      final last = segments.last;
      segments.last = FusedSegment(
        sourceId: last.sourceId,
        start: last.start,
        end: samples[index].time,
        clock: last.clock,
        sampleIntervalSeconds: last.sampleIntervalSeconds,
      );
    } else {
      segments.add(
        FusedSegment(
          sourceId: sourceId,
          start: samples[index].time,
          end: samples[index].time,
          clock: clock,
          sampleIntervalSeconds: interval,
        ),
      );
    }
  }
}

// QString::trimmed() and Qt's case-insensitive comparison, by simple case
// folding of each character.
String _foldCase(String text) {
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final character = String.fromCharCode(rune);
    final upper = character.toUpperCase();
    buffer.write(upper.runes.length == 1 ? upper.toLowerCase() : character.toLowerCase());
  }
  return buffer.toString();
}

/// The difference above which two recordings of one quantity conflict, by
/// unit: km/h 2, % 3, g 0.05, C 2, rpm 100; otherwise 5 % of the primary's
/// range in the overlap.
///
/// "°C" matches since KAN-184 in both apps (Overlays had compared it with a
/// Latin-1 view of its UTF-8 source, so it took the 5 % rule).
double fusionConflictTolerance(String unit, double overlapRange) {
  final u = unit.trim().toLowerCase();
  if (u == 'km/h' || u == 'kmh' || u == 'kph') return 2.0;
  if (u == '%') return 3.0;
  if (u == 'g') return 0.05;
  if (u == 'c' || u == '\u00b0c' || u == 'degc') return 2.0;
  if (u == 'rpm') return 100.0;
  return stdMax(1e-9, 0.05 * overlapRange.abs());
}

List<_Sample> _samplesOf(List<double> times, List<double> values, int source) => [
  for (var index = 0; index < times.length && index < values.length; ++index)
    _Sample(times[index], values[index], source),
];

/// Fuses [alternatives] into [primary] by [policy]. Cooperatively
/// cancellable (throws [OperationCancelled]).
ChannelFusionResult fuseChannels(
  TelemetrySession primary,
  String primarySourceId,
  List<FusionSource> alternatives, {
  FusionPolicy policy = const FusionPolicy(),
  CancellationCheck? cancelled,
}) {
  final result = ChannelFusionResult();
  final byKey = <String, int>{};
  // The primary's own channels, unchanged.
  final primaryNames = primary.channels.keys.toList()..sort();
  for (final name in primaryNames) {
    final channel = primary.channels[name]!;
    final fused = FusedChannel(
      key: _channelKey(primary, name),
      name: name,
      unit: channel.unit,
      rule: 'primary',
      segments: [],
      channel: channel,
    );
    _appendSegments(
      fused.segments,
      _samplesOf(channel.timestamps, channel.values, 0),
      0,
      primarySourceId,
      const SourceClock(),
      telemetryGapThreshold(channel),
      _medianInterval(channel.timestamps),
    );
    byKey[fused.key] = result.channels.length;
    result.channels.add(fused);
  }

  for (final source in alternatives) {
    throwIfCancelled(cancelled);
    final session = source.session;
    if (session == null || source.alignmentStatus != 'aligned' || !_validClock(source.clock)) {
      result.refusedSources.add(source.sourceId);
      continue;
    }
    final names = session.channels.keys.toList()..sort();
    for (final name in names) {
      throwIfCancelled(cancelled);
      final channel = session.channels[name]!;
      if (channel.timestamps.length != channel.values.length || channel.timestamps.isEmpty) {
        continue;
      }
      final key = _channelKey(session, name);
      final times = Float64List(channel.timestamps.length);
      for (var index = 0; index < times.length; ++index) {
        times[index] = _toPrimary(channel.timestamps[index], source.clock);
      }
      final gap = telemetryGapThreshold(channel) * (1.0 + source.clock.driftPpm * 1e-6);
      final interval = _medianInterval(times);
      final primaryName = _primaryNameFor(primary, key, name);
      final existing = byKey[key];

      if (primaryName.isEmpty && existing == null) {
        // Only the alternative recorded it: added on the primary clock. A
        // speed takes the unit its own recording declares (a VBO declares
        // it on a `[header]` line the primary's session does not carry,
        // FET-112), so it is never read in the unit assumed for unlabelled
        // speeds.
        final unit = channel.unit.trim().isEmpty && isSessionSpeedChannel(session, name)
            ? declaredSpeedUnit(session, name)
            : channel.unit;
        final fused = FusedChannel(
          key: key,
          name: name,
          unit: unit,
          rule: 'added',
          segments: [],
          channel: TelemetryChannel(
            name: name,
            unit: unit,
            timestamps: times,
            values: Float32List.fromList(channel.values),
          ),
        );
        _appendSegments(
          fused.segments,
          _samplesOf(times, channel.values, 1),
          1,
          source.sourceId,
          source.clock,
          gap,
          interval,
        );
        byKey[key] = result.channels.length;
        result.channels.add(fused);
        continue;
      }
      // Added earlier by another alternative under a different key.
      if (existing == null) continue;
      final fused = result.channels[existing];
      // Already decided by an earlier alternative.
      if (fused.rule != 'primary') continue;
      final primaryUnit = fused.unit.trim(), alternativeUnit = channel.unit.trim();
      final oneUndeclared = primaryUnit.isEmpty != alternativeUnit.isEmpty;
      if (!oneUndeclared && _foldCase(primaryUnit) != _foldCase(alternativeUnit)) {
        result.unitMismatches.add('$key: ${source.sourceId}');
        continue;
      }

      // Compare the overlap at the alternative's own samples.
      final differences = <double>[];
      var low = double.infinity, high = -low;
      for (var index = 0; index < times.length; ++index) {
        final double value = channel.values[index];
        final reference = primary.valueAt(fused.name, times[index]);
        if (!value.isFinite || reference == null) continue;
        differences.add((value - reference).abs());
        low = stdMin(low, reference);
        high = stdMax(high, reference);
      }
      var medianDifference = 0.0;
      var conflicting = false;
      if (differences.isNotEmpty) {
        differences.sort();
        medianDifference = differences[differences.length ~/ 2];
        // An undeclared unit takes the declared side's tolerance.
        conflicting =
            differences.length >= 10 &&
            medianDifference >
                fusionConflictTolerance(
                  primaryUnit.isEmpty ? alternativeUnit : primaryUnit,
                  high - low,
                );
      }
      // A unit only one side declares (VBO declares none, KAN-184) counts as
      // the same unit only when at least 10 samples agree; otherwise it is a
      // mismatch, so values in another scale are never fused.
      if (oneUndeclared && (differences.length < 10 || conflicting)) {
        result.unitMismatches.add('$key: ${source.sourceId}');
        continue;
      }
      fused.comparedSourceId = source.sourceId;
      fused.comparedSamples = differences.length;
      fused.medianDifference = medianDifference;
      fused.conflicting = conflicting;

      final chosen = policy.rules[key];
      final ruled = chosen != null && chosen.sourceId == source.sourceId;
      if (!ruled || chosen.rule == FusionRule.primaryOnly) {
        if (ruled) {
          fused.rule = 'primary';
        } else if (fused.conflicting) {
          fused.rule = 'unresolvedConflict';
          result.unresolved.add(key);
        }
        continue;
      }
      // Merge: the preferred source everywhere it has data, the other only
      // outside the preferred one's recorded stretches.
      final preferAlternative = chosen.rule == FusionRule.preferAlternative;
      final primarySamples = _samplesOf(fused.channel.timestamps, fused.channel.values, 0);
      final alternativeSamples = _samplesOf(times, channel.values, 1);
      final preferred = preferAlternative ? alternativeSamples : primarySamples;
      final other = preferAlternative ? primarySamples : alternativeSamples;
      final primaryGap = telemetryGapThreshold(fused.channel);
      final coverage = _spans([
        for (final sample in preferred) sample.time,
      ], preferAlternative ? gap : primaryGap);
      final merged = [
        ...preferred,
        for (final sample in other)
          if (!_covered(coverage, sample.time)) sample,
      ];
      // The times are distinct (a preferred time is always covered), so any
      // sort gives std::sort's order.
      merged.sort((a, b) => a.time.compareTo(b.time));
      // Strictly increasing timestamps: an equal time keeps the preferred
      // sample.
      final ordered = <_Sample>[];
      for (final sample in merged) {
        if (ordered.isNotEmpty && sample.time <= ordered.last.time) {
          if (sample.source == (preferAlternative ? 1 : 0)) ordered.last = sample;
          continue;
        }
        ordered.add(sample);
      }
      fused.channel = TelemetryChannel(
        name: fused.channel.name,
        unit: fused.channel.unit,
        timestamps: Float64List.fromList([for (final sample in ordered) sample.time]),
        values: Float32List.fromList([for (final sample in ordered) sample.value]),
      );
      final primarySegments = <FusedSegment>[];
      final alternativeSegments = <FusedSegment>[];
      _appendSegments(
        primarySegments,
        ordered,
        0,
        primarySourceId,
        const SourceClock(),
        primaryGap,
        _medianInterval(primary.channels[fused.name]!.timestamps),
      );
      _appendSegments(
        alternativeSegments,
        ordered,
        1,
        source.sourceId,
        source.clock,
        gap,
        interval,
      );
      final segments = [...primarySegments, ...alternativeSegments];
      stableSort(segments, (FusedSegment a, FusedSegment b) => a.start < b.start);
      fused.segments = segments;
      fused.rule = preferAlternative ? 'preferAlternative' : 'fillGaps';
    }
  }
  return result;
}

/// The primary session with [fusion] applied: merged channels replace the
/// primary's, added channels join it (under their alias when the primary has
/// none by that name). Unresolved and primary-only channels stay the
/// primary's. Metadata "fusedChannels" lists the channels that changed.
TelemetrySession fusedSession(TelemetrySession primary, ChannelFusionResult fusion) {
  final channels = Map.of(primary.channels);
  final aliases = Map.of(primary.aliases);
  final changed = <String>[];
  for (final fused in fusion.channels) {
    if (fused.rule != 'added' && fused.rule != 'fillGaps' && fused.rule != 'preferAlternative') {
      continue;
    }
    channels[fused.name] = fused.channel;
    if (fused.key != fused.name && !aliases.containsKey(fused.key)) {
      aliases[fused.key] = fused.name;
    }
    changed.add(fused.name);
  }
  changed.sort();
  return TelemetrySession(
    duration: primary.duration,
    startTime: primary.startTime,
    metadata: {...primary.metadata, 'fusedChannels': changed.join(',')},
    channels: channels,
    aliases: aliases,
    warnings: primary.warnings,
    timingGates: primary.timingGates,
    sampleCount: primary.sampleCount,
  );
}
