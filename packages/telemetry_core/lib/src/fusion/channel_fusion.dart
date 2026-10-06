// Port of FlappedEar Overlays native/src/telemetry/ChannelFusion.{h,cpp}
// (revision d4d1039, channel-fusion-v1) (FET-50), with Overlays' KAN-188 gap
// markers (see [_keepMarkersInside] and [_markGaps]): channels from a run's
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
import '../selection.dart';
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

  /// The 95th percentile of the absolute differences (FET-201), for review.
  double highDifference = 0.0;

  /// Share of the compared samples far off ([fusionConflictFarFactor]
  /// tolerances or more apart).
  double fractionOverTolerance = 0.0;

  /// Share of the samples where the channel is active (either recording more
  /// than the tolerance above the overlap's lowest value) that are far off;
  /// 0 with fewer than 10 such samples.
  double activeFractionOverTolerance = 0.0;
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
  final int source; // 0 = primary, 1 = the alternative, -1 = a gap marker
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

// `std::nextafter(value, toward)` for finite doubles.
double _nextToward(double value, double toward) {
  if (value.isNaN || toward.isNaN) return double.nan;
  if (value == toward) return toward;
  if (value == 0.0) return toward > 0.0 ? double.minPositive : -double.minPositive;
  final bits = ByteData(8)..setFloat64(0, value);
  final raw = bits.getInt64(0);
  // Away from zero is one up in the magnitude bits, for either sign.
  bits.setInt64(0, (toward > value) == (value > 0.0) ? raw + 1 : raw - 1);
  return bits.getFloat64(0);
}

// A gap marker (a NaN one step inside a gap, the RCZ parser) can round onto
// its neighbour when mapped through the clock (Overlays KAN-188). Keep each
// non-finite sample strictly between its neighbours, so no two times are
// equal and no marker swaps places with a real sample.
void _keepMarkersInside(List<double> times, List<double> values) {
  for (var index = 1; index < times.length; ++index) {
    if (!values[index].isFinite && times[index] <= times[index - 1]) {
      times[index] = _nextToward(times[index - 1], double.infinity);
    }
  }
  for (var index = times.length - 2; index >= 0; --index) {
    if (!values[index].isFinite && times[index] >= times[index + 1]) {
      times[index] = _nextToward(times[index + 1], double.negativeInfinity);
    }
  }
}

// std::numeric_limits<float>::quiet_NaN(): the positive quiet NaN (Dart's
// double.nan may carry the sign bit, which a float keeps).
final double _quietNan = (ByteData(8)..setUint64(0, 0x7ff8000000000000)).getFloat64(0);

// Gap markers where two neighbouring real samples are farther apart than the
// gap threshold of their sources (Overlays KAN-188): a merged channel mixes
// cadences, so the threshold read back from it can be longer than either
// source's and bridge a gap neither recorded across. A marker has source -1.
List<_Sample> _markGaps(List<_Sample> samples, double primaryGap, double alternativeGap) {
  double gapOf(_Sample sample) => sample.source == 0 ? primaryGap : alternativeGap;
  final result = <_Sample>[];
  for (var index = 0; index < samples.length; ++index) {
    if (index > 0) {
      final before = samples[index - 1], after = samples[index];
      final gap = stdMax(gapOf(before), gapOf(after));
      if (gap > 0.0 &&
          before.value.isFinite &&
          after.value.isFinite &&
          after.time - before.time > gap) {
        result
          ..add(_Sample(_nextToward(before.time, after.time), _quietNan, -1))
          ..add(_Sample(_nextToward(after.time, before.time), _quietNan, -1));
      }
    }
    result.add(samples[index]);
  }
  return result;
}

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

// Where [samples] have data: runs of consecutive finite samples. A step
// longer than [gap] or a missing (non-finite) sample ends a run, so a
// stretch whose timestamps are present but whose values are NaN is not
// covered (FET-200; Overlays builds coverage from timestamps alone).
List<_Span> _finiteSpans(List<_Sample> samples, double gap) {
  final result = <_Span>[];
  var open = false;
  for (final sample in samples) {
    if (!sample.value.isFinite) {
      open = false;
      continue;
    }
    if (!open || (gap > 0.0 && sample.time - result.last.end > gap)) {
      result.add(_Span(sample.time, sample.time));
      open = true;
    } else {
      result.last.end = sample.time;
    }
  }
  return result;
}

/// [preferred] without the missing (NaN) samples of each hole between two
/// finite samples that [inserted] (time-ordered) fills: the hole holds at
/// least one inserted sample and [otherCoverage] covers the missing sample
/// (FET-200).
List<_Sample> _droppingFilledHoles(
  List<_Sample> preferred,
  List<_Span> otherCoverage,
  List<_Sample> inserted,
) {
  final insertedTimes = [for (final sample in inserted) sample.time];
  final kept = <_Sample>[];
  var index = 0;
  while (index < preferred.length) {
    if (preferred[index].value.isFinite) {
      kept.add(preferred[index++]);
      continue;
    }
    final first = index;
    while (index < preferred.length && !preferred[index].value.isFinite) {
      ++index;
    }
    final after = index < preferred.length ? preferred[index].time : double.infinity;
    final before = first > 0 ? preferred[first - 1].time : double.negativeInfinity;
    var next = lowerBound(insertedTimes, before);
    while (next < insertedTimes.length && insertedTimes[next] <= before) {
      ++next;
    }
    final filled = next < insertedTimes.length && insertedTimes[next] < after;
    for (var hole = first; hole < index; ++hole) {
      if (!filled || !_covered(otherCoverage, preferred[hole].time)) kept.add(preferred[hole]);
    }
  }
  return kept;
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

/// How many tolerances apart two samples must be to count as far off
/// (FET-201). Two loggers of one fast signal (a 100 Hz accelerometer) read
/// at slightly different instants differ by a tolerance or two now and
/// then; a broken or wrongly scaled channel differs by much more.
const fusionConflictFarFactor = 3.0;

/// Share of compared samples far off from which two recordings conflict
/// (FET-201): one in ten, so the 90th percentile is far off. Two loggers
/// of a vibrating 100 Hz accelerometer on the real day reach 6 %.
const fusionConflictFraction = 0.10;

/// Share of the samples where the channel is active that are far off from
/// which two recordings conflict (FET-201), so a brake that agrees at rest
/// but not while braking conflicts.
const fusionActiveConflictFraction = 0.10;

/// The low percentile of a recording that counts as its rest value when
/// deciding where a channel is active (FET-201): one stray low sample does
/// not move it.
const fusionRestPercentile = 0.05;

/// Whether two recordings of one quantity conflict (FET-201): when the
/// median difference is above [tolerance] (Overlays' only rule), when more
/// than [fusionConflictFraction] of the samples differ by more than
/// [fusionConflictFarFactor] tolerances, or when more than
/// [fusionActiveConflictFraction] of the samples where the channel is
/// active do. Each rule needs at least 10 samples. A sample is active when
/// either recording is more than [tolerance] above its own rest value
/// ([fusionRestPercentile]); that suits channels that rise from rest (a
/// brake, a throttle), and for others the overall share still applies. A
/// median alone hides a channel that agrees at rest and disagrees in every
/// braking zone.
///
/// [median], when given, is the median difference of [medianSamples]
/// samples measured elsewhere (Overlays' sampling, kept for parity) and
/// replaces the median of these samples.
({double median, double high, double fractionOver, double activeFractionOver, bool conflicting})
fusionConflictMeasures(
  List<double> alternative,
  List<double> reference,
  double tolerance, {
  double? median,
  int? medianSamples,
}) {
  final count = alternative.length < reference.length ? alternative.length : reference.length;
  final medianCount = median == null ? count : (medianSamples ?? count);
  if (count == 0) {
    final middle = median ?? 0.0;
    return (
      median: middle,
      high: 0.0,
      fractionOver: 0.0,
      activeFractionOver: 0.0,
      conflicting: medianCount >= 10 && middle > tolerance,
    );
  }
  final restAlternative = _percentile(alternative, count, fusionRestPercentile);
  final restReference = _percentile(reference, count, fusionRestPercentile);
  final differences = Float64List(count);
  var over = 0, active = 0, activeOver = 0;
  for (var index = 0; index < count; ++index) {
    final difference = (alternative[index] - reference[index]).abs();
    differences[index] = difference;
    final isOver = difference > fusionConflictFarFactor * tolerance;
    if (isOver) ++over;
    if (alternative[index] - restAlternative > tolerance ||
        reference[index] - restReference > tolerance) {
      ++active;
      if (isOver) ++activeOver;
    }
  }
  final high = selectKth(differences, count, ((count - 1) * 0.95).round());
  final middle = median ?? selectKth(differences, count, count ~/ 2);
  final fractionOver = over / count;
  final activeFractionOver = active >= 10 ? activeOver / active : 0.0;
  final conflicting =
      (medianCount >= 10 && middle > tolerance) ||
      (count >= 10 &&
          (fractionOver > fusionConflictFraction ||
              activeFractionOver > fusionActiveConflictFraction));
  return (
    median: middle,
    high: high,
    fractionOver: fractionOver,
    activeFractionOver: activeFractionOver,
    conflicting: conflicting,
  );
}

/// The median difference between two recordings, as Overlays measures it.
double fusionMedianDifference(List<double> alternative, List<double> reference) {
  final count = alternative.length < reference.length ? alternative.length : reference.length;
  if (count == 0) return 0.0;
  final differences = Float64List(count);
  for (var index = 0; index < count; ++index) {
    differences[index] = (alternative[index] - reference[index]).abs();
  }
  return selectKth(differences, count, count ~/ 2);
}

double _percentile(List<double> values, int count, double fraction) {
  final copy = Float64List(count);
  for (var index = 0; index < count; ++index) {
    copy[index] = values[index];
  }
  return selectKth(copy, count, ((count - 1) * fraction).round());
}

/// Factors between the declared [unit] and a common other unit of the same
/// quantity: % and a fraction, km/h and m/s, g and m/s². An unknown unit
/// takes them all plus a thousandth. Factors under 3 (mph) are left out: a
/// sensor reading half or two thirds of the other is a fault to show, not a
/// unit to hide.
List<double> _unitFactorsFor(String unit) {
  final u = unit.trim().toLowerCase();
  if (u == '%') return const [100.0];
  if (u == 'km/h' || u == 'kmh' || u == 'kph' || u == 'm/s') return const [3.6];
  if (u == 'g' || u == 'm/s2' || u == 'm/s\u00b2') return const [9.80665];
  if (u == 'rpm' || u == 'c' || u == '\u00b0c' || u == 'degc') return const [];
  return const [3.6, 9.80665, 100.0, 1000.0];
}

/// Whether two recordings of one quantity, one with no declared unit, are
/// in different units (FET-201): their spreads (5th to 95th percentile)
/// differ by about a factor between the declared [unit] and a common other
/// unit of the quantity, as a 0..1 brake against
/// a % one does, and rescaled by that factor they agree. A channel that is
/// flat, dead, noisy or merely reads low is not a unit, even when its
/// spread happens to match a factor: it is a disagreement the driver sees
/// as a conflict. [unit] is the declared side's unit; [referenceDeclared]
/// says which side declares it. For a unit this does not know, a sensor
/// reading a unit factor apart and agreeing once rescaled cannot be told
/// from a unit difference, and counts as one.
bool fusionScalesDiffer(
  List<double> alternative,
  List<double> reference,
  double tolerance, {
  String unit = '',
  bool referenceDeclared = true,
}) {
  final count = alternative.length < reference.length ? alternative.length : reference.length;
  if (count == 0) return false;
  final spreadAlternative =
      _percentile(alternative, count, 0.95) - _percentile(alternative, count, 0.05);
  final spreadReference = _percentile(reference, count, 0.95) - _percentile(reference, count, 0.05);
  final larger = stdMax(spreadAlternative, spreadReference);
  final smaller = stdMin(spreadAlternative, spreadReference);
  if (larger <= tolerance) return false;
  final ratio = larger / smaller;
  for (final factor in _unitFactorsFor(unit)) {
    if (ratio <= factor / 1.15 || ratio >= factor * 1.15) continue;
    // The guess holds only if the undeclared recording, brought into the
    // declared unit ([tolerance]'s), agrees with the declared one.
    final undeclared = referenceDeclared ? alternative : reference;
    final declared = referenceDeclared ? reference : alternative;
    final undeclaredNarrower = referenceDeclared
        ? spreadAlternative < spreadReference
        : spreadReference < spreadAlternative;
    final scale = undeclaredNarrower ? factor : 1.0 / factor;
    final converted = [for (var index = 0; index < count; ++index) undeclared[index] * scale];
    return !fusionConflictMeasures(converted, declared.sublist(0, count), tolerance).conflicting;
  }
  return false;
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
      _keepMarkersInside(times, channel.values);
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
      final compared = <double>[];
      final references = <double>[];
      var low = double.infinity, high = -low;
      for (var index = 0; index < times.length; ++index) {
        final double value = channel.values[index];
        final reference = primary.valueAt(fused.name, times[index]);
        if (!value.isFinite || reference == null) continue;
        compared.add(value);
        references.add(reference);
        low = stdMin(low, reference);
        high = stdMax(high, reference);
      }
      // An undeclared unit takes the declared side's tolerance.
      final tolerance = fusionConflictTolerance(
        primaryUnit.isEmpty ? alternativeUnit : primaryUnit,
        high - low,
      );
      // Overlays' median at the alternative's samples, kept for parity. The
      // share of far-off samples is measured at the coarser recording's
      // samples (FET-201): a 1 Hz primary interpolated at 10 Hz differs
      // from a true 10 Hz recording on every brake ramp.
      final medianDifference = fusionMedianDifference(compared, references);
      var sampledAlternative = compared, sampledReference = references;
      final primaryInterval = _medianInterval(fused.channel.timestamps);
      if (interval > 0.0 && interval < 0.75 * primaryInterval) {
        final alternativeChannel = TelemetryChannel(
          name: name,
          unit: channel.unit,
          timestamps: times,
          values: channel.values,
        );
        sampledAlternative = <double>[];
        sampledReference = <double>[];
        final primaryTimes = fused.channel.timestamps;
        final primaryValues = fused.channel.values;
        for (var index = 0; index < primaryTimes.length; ++index) {
          final double reference = primaryValues[index];
          if (!reference.isFinite) continue;
          final value = telemetryValueAt(alternativeChannel, primaryTimes[index]);
          if (value == null) continue;
          sampledAlternative.add(value);
          sampledReference.add(reference);
        }
      }
      final measures = fusionConflictMeasures(
        sampledAlternative,
        sampledReference,
        tolerance,
        median: medianDifference,
        medianSamples: compared.length,
      );
      final comparedSamples = compared.length;
      // A unit only one side declares (VBO declares none, KAN-184) counts as
      // the same unit only when at least 10 samples agree in the median and
      // both recordings spread alike; otherwise it is a mismatch, so values
      // in another scale are never fused. Beyond that, a disagreement is a
      // conflict the driver sees (FET-201), not a hidden mismatch.
      if (oneUndeclared &&
          (comparedSamples < 10 ||
              medianDifference > tolerance ||
              fusionScalesDiffer(
                compared,
                references,
                tolerance,
                unit: primaryUnit.isEmpty ? alternativeUnit : primaryUnit,
                referenceDeclared: primaryUnit.isNotEmpty,
              ))) {
        result.unitMismatches.add('$key: ${source.sourceId}');
        continue;
      }
      final conflicting = measures.conflicting;
      fused.comparedSourceId = source.sourceId;
      fused.comparedSamples = comparedSamples;
      fused.medianDifference = medianDifference;
      fused.highDifference = measures.high;
      fused.fractionOverTolerance = measures.fractionOver;
      fused.activeFractionOverTolerance = measures.activeFractionOver;
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
      // Coverage counts finite samples only, so the other source fills
      // where the preferred one has timestamps but no values (FET-200).
      // A missing preferred sample is dropped only when the other source
      // covers it and actually places a sample in the same hole between
      // two finite preferred samples; otherwise it stays and keeps the gap,
      // so no reading interpolates across the preferred source's own
      // missing values.
      final coverage = _finiteSpans(preferred, preferAlternative ? gap : primaryGap);
      final otherCoverage = _finiteSpans(other, preferAlternative ? primaryGap : gap);
      final inserted = [
        for (final sample in other)
          if (!_covered(coverage, sample.time)) sample,
      ];
      final merged = [..._droppingFilledHoles(preferred, otherCoverage, inserted), ...inserted];
      // As Overlays' std::stable_sort.
      stableSort(merged, (_Sample a, _Sample b) => a.time < b.time);
      // Strictly increasing timestamps: an equal time keeps the preferred
      // sample.
      final sorted = <_Sample>[];
      for (final sample in merged) {
        if (sorted.isNotEmpty && sample.time <= sorted.last.time) {
          if (sample.source == (preferAlternative ? 1 : 0)) sorted.last = sample;
          continue;
        }
        sorted.add(sample);
      }
      final ordered = _markGaps(sorted, primaryGap, gap);
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
