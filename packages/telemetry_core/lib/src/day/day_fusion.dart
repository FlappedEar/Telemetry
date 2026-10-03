// Source fusion of a day's runs without a review (FET-51): each run's
// alternative recording (the RCZ of the drive its VBO recorded) is aligned to
// the primary (recording-alignment-v1) and, when the alignment is "aligned",
// its channels are fused (channel-fusion-v1) at once, as the owner decided
// for segments too. The decision is the run's `fusion` object of the
// `.fetproject` format (Overlays KAN-103): bound to both recordings' content,
// applied without aligning again while both still match.
//
// Laps, lap rows, timing and rankings never come from the fused session:
// they stay derived from the primary alone. Only the analysis that reads
// channels uses [RunFusion.session].
import '../fusion/channel_fusion.dart';
import '../fusion/recording_alignment.dart';
import '../intake/import_plan.dart';
import '../intake/recording_source.dart';
import '../operation.dart';
import '../telemetry_session.dart';

/// How a run's alternative recording is used.
enum RunFusionState {
  /// Aligned and fused: [RunFusion.session] has the alternative's channels.
  fused,

  /// The clocks could not be aligned ([RunFusion.status] says how, and
  /// [RunFusion.reason] why): nothing is fused.
  notAligned,

  /// The alternative recording the document names could not be used
  /// ([RunFusion.reason]): nothing is fused.
  unavailable,
}

/// A run's alternative recording and what fusing it did.
final class RunFusion {
  const RunFusion._({
    required this.state,
    required this.primarySourceId,
    required this.primaryRevision,
    required this.alternativeSourceId,
    required this.alternativeFormat,
    this.alternative,
    this.status = '',
    this.reason = '',
    this.clock = const SourceClock(),
    this.uncertaintySeconds = 0.0,
    this.resolvedByDeclaredClock = false,
    this.rules = const {},
    this.result,
    this.session,
    this.fromDocument = false,
  });

  /// The alternative recording the document names, which could not be used
  /// because of [reason] (in English, for the app to map).
  const RunFusion.unavailable({
    required String primarySourceId,
    required String primaryRevision,
    required String alternativeSourceId,
    required RecordingFormat? alternativeFormat,
    required String reason,
  }) : this._(
         state: RunFusionState.unavailable,
         primarySourceId: primarySourceId,
         primaryRevision: primaryRevision,
         alternativeSourceId: alternativeSourceId,
         alternativeFormat: alternativeFormat,
         reason: reason,
       );

  final RunFusionState state;
  final String primarySourceId;

  /// The primary recording's content SHA-256.
  final String primaryRevision;
  final String alternativeSourceId;

  /// Null when the alternative is unavailable and its format unknown.
  final RecordingFormat? alternativeFormat;

  /// Null when [state] is [RunFusionState.unavailable].
  final TelemetryRunProposal? alternative;

  /// The alignment's status ([alignmentAligned] and so on); "aligned" for
  /// a decision applied from the document.
  final String status;

  /// Why it is not aligned (the alignment's reason) or not available.
  final String reason;

  /// The alternative's clock on the primary's.
  final SourceClock clock;
  final double uncertaintySeconds;
  final bool resolvedByDeclaredClock;

  /// The rule of each channel key both recordings measure, where one was
  /// chosen. Conflicting channels always have one: [FusionRule.primaryOnly]
  /// unless the user chose otherwise.
  final Map<String, FusionRule> rules;

  /// Null unless [state] is [RunFusionState.fused].
  final ChannelFusionResult? result;

  /// The primary session with the fused channels; null unless fused.
  final TelemetrySession? session;

  /// The clock and rules came from the document's decision, without
  /// aligning again.
  final bool fromDocument;

  bool get fused => state == RunFusionState.fused;

  /// The channels of [session] whose samples come from the alternative, in
  /// whole ("added") or in part ("fillGaps", "preferAlternative"), by name.
  Map<String, String> get channelOrigins => {
    for (final channel in result?.channels ?? const <FusedChannel>[])
      if (channel.rule == 'added' ||
          channel.rule == 'fillGaps' ||
          channel.rule == 'preferAlternative')
        channel.name: channel.rule,
  };

  /// The channels both recordings measured whose measurements disagree, by
  /// key, with the rule applied to each.
  List<FusedChannel> get conflicts => [
    for (final channel in result?.channels ?? const <FusedChannel>[])
      if (channel.conflicting) channel,
  ];

  /// The rule applied to channel [key].
  FusionRule ruleOf(String key) => rules[key] ?? FusionRule.primaryOnly;

  /// The run's `fusion` object for the `.fetproject` document (Overlays'
  /// KAN-103 decision); null unless fused.
  Map<String, Object?>? get decision {
    final alternative = this.alternative;
    if (!fused || alternative == null) return null;
    // At most 64 rules: chosen rules first; primaryOnly is also what an
    // unlisted channel gets.
    final keys = rules.keys.toList()
      ..sort((a, b) {
        final byRule = (rules[a] == FusionRule.primaryOnly ? 1 : 0).compareTo(
          rules[b] == FusionRule.primaryOnly ? 1 : 0,
        );
        return byRule != 0 ? byRule : a.compareTo(b);
      });
    final written = keys.take(_maximumRules).toList()..sort();
    return {
      'algorithm': channelFusionAlgorithm,
      'alternativeSourceId': alternativeSourceId,
      'primarySourceRevision': primaryRevision,
      'alternativeSourceRevision': alternative.contentSha256,
      'clock': {
        'offsetSeconds': clock.offsetSeconds,
        'driftPpm': clock.driftPpm,
        'uncertaintySeconds': uncertaintySeconds,
        'alignmentAlgorithm': recordingAlignmentAlgorithm,
        'resolvedByDeclaredClock': resolvedByDeclaredClock,
      },
      'rules': [
        for (final key in written) {'key': key, 'rule': rules[key]!.name},
      ],
    };
  }
}

const _maximumRules = 64;

/// Fuses [alternative] into [primary] on [clock] with [rules]; a
/// conflicting channel without a rule keeps the primary
/// ([FusionRule.primaryOnly]) and gets that rule.
RunFusion _fuse(
  TelemetryRunProposal primary,
  TelemetryRunProposal alternative, {
  required String status,
  required SourceClock clock,
  required double uncertaintySeconds,
  required bool resolvedByDeclaredClock,
  required Map<String, FusionRule> rules,
  required bool fromDocument,
  CancellationCheck? cancelled,
}) {
  ChannelFusionResult run(Map<String, FusionRule> rules) => fuseChannels(
    primary.telemetry,
    primary.sourceId,
    [
      FusionSource(
        sourceId: alternative.sourceId,
        session: alternative.telemetry,
        clock: clock,
        alignmentStatus: alignmentAligned,
      ),
    ],
    policy: FusionPolicy(
      rules: {
        for (final MapEntry(:key, :value) in rules.entries)
          key: (sourceId: alternative.sourceId, rule: value),
      },
    ),
    cancelled: cancelled,
  );
  var chosen = Map.of(rules);
  var result = run(chosen);
  if (result.unresolved.isNotEmpty) {
    chosen = {...chosen, for (final key in result.unresolved) key: FusionRule.primaryOnly};
    result = run(chosen);
  }
  return RunFusion._(
    state: RunFusionState.fused,
    primarySourceId: primary.sourceId,
    primaryRevision: primary.contentSha256,
    alternativeSourceId: alternative.sourceId,
    alternativeFormat: alternative.format,
    alternative: alternative,
    status: status,
    clock: clock,
    uncertaintySeconds: uncertaintySeconds,
    resolvedByDeclaredClock: resolvedByDeclaredClock,
    rules: Map.unmodifiable(chosen),
    result: result,
    session: fusedSession(primary.telemetry, result),
    fromDocument: fromDocument,
  );
}

/// Aligns [alternative] to [primary] and, when aligned, fuses it with no
/// rule but [FusionRule.primaryOnly] for conflicting channels: channels only
/// the alternative has are added, every other channel stays the primary's.
/// Cooperatively cancellable (throws [OperationCancelled]).
RunFusion fuseRunRecordings(
  TelemetryRunProposal primary,
  TelemetryRunProposal alternative, {
  CancellationCheck? cancelled,
}) {
  final alignment = alignRecordings(primary.telemetry, alternative.telemetry, cancelled: cancelled);
  final offset = alignment.offset;
  if (alignment.status != alignmentAligned || offset == null) {
    return RunFusion._(
      state: RunFusionState.notAligned,
      primarySourceId: primary.sourceId,
      primaryRevision: primary.contentSha256,
      alternativeSourceId: alternative.sourceId,
      alternativeFormat: alternative.format,
      alternative: alternative,
      status: alignment.status,
      reason: alignment.reason,
    );
  }
  return _fuse(
    primary,
    alternative,
    status: alignment.status,
    clock: SourceClock(offsetSeconds: offset, driftPpm: alignment.driftPpm ?? 0.0),
    uncertaintySeconds: alignment.uncertaintySeconds ?? 0.0,
    resolvedByDeclaredClock: alignment.resolvedByDeclaredClock,
    rules: const {},
    fromDocument: false,
    cancelled: cancelled,
  );
}

/// Whether [decision] (a run's `fusion` object) is bound to exactly these
/// recordings: its alternative is [alternative] and both content revisions
/// are the recordings' own.
bool fusionDecisionApplies(
  Map<String, Object?> decision,
  TelemetryRunProposal primary,
  TelemetryRunProposal alternative,
) =>
    decision['algorithm'] == channelFusionAlgorithm &&
    decision['alternativeSourceId'] == alternative.sourceId &&
    decision['primarySourceRevision'] == primary.contentSha256 &&
    decision['alternativeSourceRevision'] == alternative.contentSha256 &&
    decision['clock'] is Map;

/// Applies a saved [decision] (see [fusionDecisionApplies]) without
/// aligning again: its clock and its rules.
RunFusion applyFusionDecision(
  Map<String, Object?> decision,
  TelemetryRunProposal primary,
  TelemetryRunProposal alternative, {
  CancellationCheck? cancelled,
}) {
  final clock = decision['clock'] as Map;
  double number(Object? value) => value is num ? value.toDouble() : 0.0;
  final rules = <String, FusionRule>{};
  for (final value in (decision['rules'] as List?) ?? const []) {
    if (value case {'key': final String key, 'rule': final String rule}) {
      for (final candidate in FusionRule.values) {
        if (candidate.name == rule) rules[key] = candidate;
      }
    }
  }
  return _fuse(
    primary,
    alternative,
    status: alignmentAligned,
    clock: SourceClock(
      offsetSeconds: number(clock['offsetSeconds']),
      driftPpm: number(clock['driftPpm']),
    ),
    uncertaintySeconds: number(clock['uncertaintySeconds']),
    resolvedByDeclaredClock: clock['resolvedByDeclaredClock'] == true,
    rules: rules,
    fromDocument: true,
    cancelled: cancelled,
  );
}

/// [fusion] again with [rule] for channel [key]; null when [fusion] is not
/// fused.
RunFusion? withFusionRule(
  RunFusion fusion,
  TelemetryRunProposal primary,
  String key,
  FusionRule rule, {
  CancellationCheck? cancelled,
}) {
  final alternative = fusion.alternative;
  if (!fusion.fused || alternative == null) return null;
  return _fuse(
    primary,
    alternative,
    status: fusion.status,
    clock: fusion.clock,
    uncertaintySeconds: fusion.uncertaintySeconds,
    resolvedByDeclaredClock: fusion.resolvedByDeclaredClock,
    rules: {...fusion.rules, key: rule},
    fromDocument: fusion.fromDocument,
    cancelled: cancelled,
  );
}

/// The fusion of every run of [primaries] that [plan] has an alternative
/// recording for (an RCZ grouped under its VBO by [automaticVboPrimaries]),
/// by run id. Aligning takes a few seconds per run: run it in the
/// background.
Map<String, RunFusion> fuseImportedRuns(
  TelemetryImportPlan plan,
  Iterable<TelemetryRunProposal> primaries, {
  CancellationCheck? cancelled,
}) {
  final groups = automaticVboPrimaries(plan);
  final byId = {for (final run in primaries) run.id: run};
  final result = <String, RunFusion>{};
  for (final run in plan.runs) {
    final primary = byId[groups[run.id]];
    if (primary == null || primary.id == run.id || result.containsKey(primary.id)) continue;
    if (primary.format != RecordingFormat.vbo || run.format != RecordingFormat.rcz) continue;
    throwIfCancelled(cancelled);
    result[primary.id] = fuseRunRecordings(primary, run, cancelled: cancelled);
  }
  return result;
}
