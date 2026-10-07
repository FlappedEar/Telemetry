import 'package:flutter/foundation.dart';
import 'package:telemetry_core/telemetry_core.dart';

/// What an open day tells the rest of the app about its recordings: built
/// whole by the day that owns it and never changed (FET-209). A day that
/// changes publishes a new one.
@immutable
final class DayContext {
  const DayContext({
    this.channelSources = const {},
    this.recordedChannels = const [],
    this.speedUnits = const [],
    this.channelSpeedUnits = const {},
  });

  /// The context of a day of [sessions] (each session's own recording, not
  /// its fused one), with the channels that came from another recording than the
  /// session's own in [channelSources].
  factory DayContext.of(
    Iterable<TelemetrySession> sessions, {
    Map<String, String> channelSources = const {},
  }) {
    final recorded = <String>{...channelSources.keys};
    final speedUnits = <String>[];
    final byChannel = <String, List<String>>{};
    for (final session in sessions) {
      recorded.addAll(session.channelNames());
      final alias = session.aliases['speed'];
      speedUnits.add(declaredSpeedUnit(session, alias ?? 'speed'));
      for (final name in session.channels.keys) {
        if (!isSpeedChannel(name) && name != alias) continue;
        byChannel
            .putIfAbsent(name.toLowerCase(), () => [])
            .add(declaredSpeedUnit(session, name));
      }
    }
    return DayContext(
      channelSources: Map.unmodifiable(channelSources),
      recordedChannels: List.unmodifiable(recorded.toList()..sort()),
      speedUnits: List.unmodifiable(speedUnits),
      channelSpeedUnits: Map.unmodifiable({
        for (final MapEntry(:key, :value) in byChannel.entries)
          key: List<String>.unmodifiable(value),
      }),
    );
  }

  /// No day is open.
  static const none = DayContext();

  /// The channels that came, in at least one session, from a recording
  /// other than the session's own (the RCZ fused into its VBO), with that
  /// recording's format ("RCZ"), by channel name.
  final Map<String, String> channelSources;

  /// The names of every channel the day recorded, its fused recordings'
  /// included, sorted.
  final List<String> recordedChannels;

  /// The speed unit each recording declares ("km/h", "mph", or empty when
  /// it declares none).
  final List<String> speedUnits;

  /// The speed units the recordings declare per speed channel, keyed by
  /// lower-case channel name: one entry per recording that has the channel.
  final Map<String, List<String>> channelSpeedUnits;
}

/// The open day's context, [DayContext.none] when none is open. Only the
/// day that published a context replaces or clears it ([DayContextOwner]),
/// so a day closing after another opened leaves the newer one in place.
/// Read when building or calling, never listened to: it changes while a
/// closing page is unmounted, when nothing may rebuild.
DayContext get openDayContext => _openDayContext;
DayContext _openDayContext = DayContext.none;

/// Sets the open day's context directly, bypassing [DayContextOwner].
@visibleForTesting
void debugSetOpenDayContext(DayContext context) => _openDayContext = context;

/// A day's hold on [openDayContext].
final class DayContextOwner {
  DayContext? _published;

  /// Makes [context] the open day's, taking it over from any other day.
  void open(DayContext context) {
    _published = context;
    _openDayContext = context;
  }

  /// Replaces this day's context with [context] while it is still the open
  /// one; does nothing once another day has opened, or after [close].
  void update(DayContext context) {
    if (_published == null || !identical(_openDayContext, _published)) {
      return;
    }
    _published = context;
    _openDayContext = context;
  }

  /// Clears the open day's context if it is still this day's.
  void close() {
    if (_published != null && identical(_openDayContext, _published)) {
      _openDayContext = DayContext.none;
    }
    _published = null;
  }
}
