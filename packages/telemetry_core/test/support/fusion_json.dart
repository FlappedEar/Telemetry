// Compares the Dart recording alignment and channel fusion with the JSON
// that tool/cpp_fusion_dump writes for Overlays' C++. Every number must be
// equal; a channel's samples are compared through their digest (64-bit
// FNV-1a over the little-endian bytes of every double timestamp, then every
// float value) and the sampled rows.
import 'dart:typed_data';

import 'package:telemetry_core/telemetry_core.dart';

/// The digest cpp_fusion_dump writes for a channel.
String channelDigest(TelemetryChannel channel) {
  var hash = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  final bytes = ByteData(8);
  void feed(int count) {
    for (var i = 0; i < count; ++i) {
      hash = (hash ^ bytes.getUint8(i)) * prime;
    }
  }

  for (final time in channel.timestamps) {
    bytes.setFloat64(0, time, Endian.little);
    feed(8);
  }
  for (final value in channel.values) {
    bytes.setFloat32(0, value, Endian.little);
    feed(4);
  }
  return (hash >>> 32).toRadixString(16).padLeft(8, '0') +
      (hash & 0xffffffff).toRadixString(16).padLeft(8, '0');
}

/// Collects differences from the reference, with counts for a report.
final class FusionCheck {
  FusionCheck(this.what);

  final String what;
  final List<String> failures = [];
  int compared = 0;
  int mismatched = 0;

  void _fail(String message) {
    ++mismatched;
    if (failures.length < 30) failures.add('$what: $message');
  }

  void same(String where, Object? actual, Object? expected) {
    ++compared;
    if (actual is List && expected is List) {
      if (actual.length != expected.length) {
        _fail('$where: $actual, expected $expected');
        return;
      }
      for (var i = 0; i < actual.length; ++i) {
        if (actual[i] != expected[i]) {
          _fail('$where: $actual, expected $expected');
          return;
        }
      }
      return;
    }
    if (actual != expected) _fail('$where: $actual, expected $expected');
  }

  /// Exact equality; null in the reference is NaN, infinity or no value.
  void number(String where, double? actual, Object? expected) {
    ++compared;
    if (expected == null) {
      if (actual != null && actual.isFinite) _fail('$where: $actual, expected no value');
      return;
    }
    final value = (expected as num).toDouble();
    if (actual != value) _fail('$where: $actual, expected $value');
  }

  void sync(String where, SyncCandidate actual, Map<String, Object?> expected) {
    final d = actual.diagnostics;
    number('$where offset', actual.offset, expected['offset']);
    number('$where timeScale', actual.timeScale, expected['timeScale']);
    number('$where confidence', actual.confidence, expected['confidence']);
    same('$where strategy', actual.strategy, expected['strategy']);
    number('$where correlation', d.correlation, expected['correlation']);
    number('$where peakUniqueness', d.peakUniqueness, expected['peakUniqueness']);
    same('$where validSamples', d.validSamples, expected['validSamples']);
    number('$where sampleRate', d.sampleRate, expected['sampleRate']);
    number('$where coarseOffset', d.coarseOffset, expected['coarseOffset']);
    same('$where autoApply', shouldAutoApplySyncCandidate(actual), expected['autoApply']);
  }

  void alignment(String where, RecordingAlignment actual, Map<String, Object?> expected) {
    same('$where status', actual.status, expected['status']);
    same('$where reason', actual.reason, expected['reason']);
    same(
      '$where declaredOffset present',
      actual.declaredOffset != null,
      expected['declaredOffset'] != null,
    );
    number('$where declaredOffset', actual.declaredOffset, expected['declaredOffset']);
    same('$where offset present', actual.offset != null, expected['offset'] != null);
    number('$where offset', actual.offset, expected['offset']);
    same('$where driftPpm present', actual.driftPpm != null, expected['driftPpm'] != null);
    number('$where driftPpm', actual.driftPpm, expected['driftPpm']);
    same(
      '$where uncertainty present',
      actual.uncertaintySeconds != null,
      expected['uncertaintySeconds'] != null,
    );
    number('$where uncertaintySeconds', actual.uncertaintySeconds, expected['uncertaintySeconds']);
    number('$where correlation', actual.correlation, expected['correlation']);
    number('$where peakUniqueness', actual.peakUniqueness, expected['peakUniqueness']);
    number('$where confidence', actual.confidence, expected['confidence']);
    number('$where overlapSeconds', actual.overlapSeconds, expected['overlapSeconds']);
    same('$where usedWindows', actual.usedWindows, expected['usedWindows']);
    same(
      '$where resolvedByDeclaredClock',
      actual.resolvedByDeclaredClock,
      expected['resolvedByDeclaredClock'],
    );
    final windows = (expected['windows'] as List).cast<List<Object?>>();
    same('$where windows', actual.windows.length, windows.length);
    for (var i = 0; i < actual.windows.length && i < windows.length; ++i) {
      final window = actual.windows[i];
      number('$where window $i time', window.candidateTime, windows[i][0]);
      number('$where window $i offset', window.offset, windows[i][1]);
      number('$where window $i correlation', window.correlation, windows[i][2]);
      same('$where window $i used', window.used, windows[i][3]);
    }
  }

  void channel(String where, TelemetryChannel actual, Map<String, Object?> expected) {
    same('$where name', actual.name, expected['name']);
    same('$where unit', actual.unit, expected['unit']);
    same('$where count', actual.timestamps.length, expected['count']);
    same('$where valueCount', actual.values.length, expected['valueCount']);
    same('$where digest', channelDigest(actual), expected['digest']);
    final rows = expected['samples'];
    if (rows is! List) return;
    for (final row in rows.cast<List<Object?>>()) {
      final index = row[0] as int;
      if (index >= actual.timestamps.length) {
        _fail('$where sample $index missing');
        continue;
      }
      number('$where time $index', actual.timestamps[index], row[1]);
      number('$where value $index', actual.values[index], row[2]);
    }
  }

  void fusion(String where, ChannelFusionResult actual, Map<String, Object?> expected) {
    final channels = (expected['channels'] as List).cast<Map<String, Object?>>();
    same('$where channels', actual.channels.length, channels.length);
    for (var i = 0; i < actual.channels.length && i < channels.length; ++i) {
      final fused = actual.channels[i];
      final json = channels[i];
      final at = '$where ${json['key']}';
      same('$at key', fused.key, json['key']);
      same('$at name', fused.name, json['name']);
      same('$at unit', fused.unit, json['unit']);
      same('$at rule', fused.rule, json['rule']);
      same('$at comparedSourceId', fused.comparedSourceId, json['comparedSourceId']);
      same('$at comparedSamples', fused.comparedSamples, json['comparedSamples']);
      number('$at medianDifference', fused.medianDifference, json['medianDifference']);
      same('$at conflicting', fused.conflicting, json['conflicting']);
      final segments = (json['segments'] as List).cast<List<Object?>>();
      same('$at segments', fused.segments.length, segments.length);
      for (var s = 0; s < fused.segments.length && s < segments.length; ++s) {
        final segment = fused.segments[s];
        same('$at segment $s source', segment.sourceId, segments[s][0]);
        number('$at segment $s start', segment.start, segments[s][1]);
        number('$at segment $s end', segment.end, segments[s][2]);
        number('$at segment $s offset', segment.clock.offsetSeconds, segments[s][3]);
        number('$at segment $s drift', segment.clock.driftPpm, segments[s][4]);
        number('$at segment $s interval', segment.sampleIntervalSeconds, segments[s][5]);
      }
      channel('$at channel', fused.channel, json['channel'] as Map<String, Object?>);
    }
    same('$where unresolved', actual.unresolved, expected['unresolved']);
    same('$where unitMismatches', actual.unitMismatches, expected['unitMismatches']);
    same('$where refusedSources', actual.refusedSources, expected['refusedSources']);
  }

  void session(String where, TelemetrySession actual, Map<String, Object?> expected) {
    final channels = expected['channels'] as Map<String, Object?>;
    same(
      '$where channel names',
      (actual.channels.keys.toList()..sort()),
      (channels.keys.toList()..sort()),
    );
    for (final MapEntry(:key, :value) in channels.entries) {
      final channel = actual.channels[key];
      if (channel == null) {
        _fail('$where channel $key missing');
        continue;
      }
      this.channel('$where $key', channel, value as Map<String, Object?>);
    }
    same('$where aliases', _sortedEntries(actual.aliases), _sortedEntries(expected['aliases']));
    same('$where metadata', _sortedEntries(actual.metadata), _sortedEntries(expected['metadata']));
    number('$where duration', actual.duration, expected['duration']);
    same('$where sampleCount', actual.sampleCount, expected['sampleCount']);
  }

  static List<String> _sortedEntries(Object? map) =>
      [for (final MapEntry(:key, :value) in (map as Map).entries) '$key=$value']..sort();
}
