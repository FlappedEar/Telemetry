import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'day_results_controller.dart';
import 'theoretical_best_card.dart' show TheoreticalBestText;

/// The optional review of the automatic segment proposals (FET-56), as
/// FlappedEar Overlays' segment review shows them: each proposal of the lap
/// the segments are measured on with its state against the approved
/// segments, its turn, its boundaries with their tolerance and uncertainty,
/// and a corner's geometric apex. Reject (and restore) a proposal, approve
/// every open one, or compute them again. Segments stay automatic: nothing
/// here needs to be done before the day's results or the next session.
class SegmentReviewPage extends StatefulWidget {
  const SegmentReviewPage({super.key, required this.controller});

  final DayResultsController controller;

  @override
  State<SegmentReviewPage> createState() => _SegmentReviewPageState();
}

/// [issue] in the app's language.
String segmentChangeIssueText(
  AppLocalizations l10n,
  SegmentChangeIssue issue,
) => switch (issue) {
  SegmentChangeIssue.saving => l10n.segmentReviewSaving,
  SegmentChangeIssue.segmentsUnavailable =>
    l10n.segmentReviewSegmentsUnavailable,
  SegmentChangeIssue.notReady => l10n.segmentReviewNotReady,
  SegmentChangeIssue.noLongerAvailable => l10n.segmentReviewNoLongerAvailable,
  SegmentChangeIssue.notOpen => l10n.segmentReviewNotOpen,
  SegmentChangeIssue.notStored => l10n.segmentReviewNotStored,
  SegmentChangeIssue.noneApproved => l10n.segmentReviewNoneApproved,
  SegmentChangeIssue.nothingToUndo => l10n.segmentReviewNothingToUndo,
  SegmentChangeIssue.nothingToRedo => l10n.segmentReviewNothingToRedo,
  SegmentChangeIssue.historyCleared => l10n.segmentReviewHistoryCleared,
};

class _SegmentReviewPageState extends State<SegmentReviewPage> {
  DayResultsController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    // The theoretical best is calculated again after a change of the
    // segments; the proposals follow once it is there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_controller.theoreticalBest == null &&
          !_controller.theoreticalBestLoading) {
        _controller.requestTheoreticalBest();
      } else {
        _controller.requestSegmentReview();
      }
    });
    if (mounted) setState(() {});
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _report(SegmentChangeIssue? issue) {
    if (issue != null) _tell(segmentChangeIssueText(context.l10n, issue));
  }

  void _approveAll() {
    final outcome = _controller.approveAllSegmentProposals();
    final issue = outcome.issue;
    if (issue == null) {
      _tell(context.l10n.segmentReviewApproved(outcome.approved));
    } else {
      _report(issue);
    }
  }

  void _reject(int index, bool rejected) =>
      _report(_controller.rejectSegmentProposal(index, rejected: rejected));

  void _history({required bool undo}) => _report(
    undo ? _controller.undoSegmentChange() : _controller.redoSegmentChange(),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy =
        _controller.theoreticalBestLoading ||
        _controller.theoreticalBest == null ||
        _controller.segmentReviewLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.segmentReviewTitle),
        actions: [
          IconButton(
            key: const ValueKey('undoReview'),
            tooltip: l10n.segmentReviewUndo,
            icon: const Icon(Icons.undo),
            onPressed: _controller.canUndoSegmentEdit && !busy
                ? () => _history(undo: true)
                : null,
          ),
          IconButton(
            key: const ValueKey('redoReview'),
            tooltip: l10n.segmentReviewRedo,
            icon: const Icon(Icons.redo),
            onPressed: _controller.canRedoSegmentEdit && !busy
                ? () => _history(undo: false)
                : null,
          ),
        ],
      ),
      // A readable width on a wide window.
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _body(context, busy),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, bool busy) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final result = _controller.theoreticalBest;
    final review = _controller.segmentReview;
    Widget waiting(String text) => Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(text),
        ],
      ),
    );
    if (result == null || _controller.theoreticalBestLoading) {
      return waiting(l10n.segmentReviewWaiting);
    }
    if (result.state != DayTheoreticalBestState.ready) {
      return Padding(
        padding: const EdgeInsets.all(16),
        // In the app's language, as on the Theoretical best card.
        child: Text(l10n.tbMessage(result.message)),
      );
    }
    if (review == null) return waiting(l10n.segmentReviewComputing);
    final items = _controller.segmentReviewItems;
    final open = items.any((item) => item.state == SegmentReviewState.proposed);
    // The header scrolls with the proposals, so nothing overflows a short
    // screen or large text.
    final header = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          l10n.segmentReviewIntro,
          key: const ValueKey('reviewIntro'),
          style: theme.textTheme.bodySmall,
        ),
      ),
      if (review.ready)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            l10n.segmentReviewSummary(
              items.length,
              review.lap?.displayName ?? '',
            ),
            key: const ValueKey('reviewSummary'),
            style: theme.textTheme.titleSmall,
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _reason(context, review),
            key: const ValueKey('reviewMessage'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: review.failed ? theme.colorScheme.error : null,
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('approveAllProposals'),
              icon: const Icon(Icons.done_all),
              label: Text(l10n.segmentReviewApproveAll),
              onPressed: open && !busy ? _approveAll : null,
            ),
            OutlinedButton.icon(
              key: const ValueKey('recomputeProposals'),
              icon: const Icon(Icons.refresh),
              label: Text(l10n.segmentReviewRecompute),
              onPressed: busy ? null : _controller.recomputeSegmentProposals,
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      const SizedBox(height: 8),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 4,
          // Said when it appears: the strip alone says nothing to a screen
          // reader.
          child: busy
              ? Semantics(
                  liveRegion: true,
                  child: LinearProgressIndicator(
                    semanticsLabel: context.l10n.segmentEditorTiming,
                  ),
                )
              : null,
        ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('proposalList'),
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: header.length + items.length,
            itemBuilder: (context, position) {
              if (position < header.length) return header[position];
              final index = position - header.length;
              return _ProposalCard(
                key: ValueKey('proposal $index'),
                item: items[index],
                phases: index < review.phases.length
                    ? review.phases[index]
                    : null,
                busy: busy,
                onReject: (rejected) => _reject(index, rejected),
              );
            },
          ),
        ),
      ],
    );
  }

  String _reason(BuildContext context, DayProposalReview review) {
    final l10n = context.l10n;
    return switch (review.reason) {
      segmentReviewNoLap => l10n.segmentReviewNoLap,
      segmentReviewNoAxis => l10n.segmentReviewNoAxis,
      'continuousCorner' => l10n.segmentReviewContinuousCorner,
      'noCorners' => l10n.segmentReviewNoCorners,
      'tooManySegments' => l10n.segmentReviewTooMany(
        segmentReviewMaximumSegments,
      ),
      _ => l10n.segmentReviewFailed,
    };
  }
}

/// One proposal: its state, name and type, turn, boundaries, uncertainty and
/// apex, and Reject or Restore while it is open or rejected.
class _ProposalCard extends StatelessWidget {
  const _ProposalCard({
    super.key,
    required this.item,
    required this.phases,
    required this.busy,
    required this.onReject,
  });

  final SegmentReviewItem item;
  final CornerGeometryPhases? phases;
  final bool busy;
  final ValueChanged<bool> onReject;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final proposal = item.proposal;
    // The theme's roles, so the text keeps its contrast with the theme.
    final scheme = theme.colorScheme;
    final (stateText, stateColor) = switch (item.state) {
      SegmentReviewState.approved => (
        l10n.segmentReviewStateApproved,
        scheme.tertiary,
      ),
      SegmentReviewState.rejected => (
        l10n.segmentReviewStateRejected,
        scheme.onSurfaceVariant,
      ),
      SegmentReviewState.superseded => (
        l10n.segmentReviewStateSuperseded,
        scheme.error,
      ),
      SegmentReviewState.proposed => (
        l10n.segmentReviewStateProposed,
        scheme.secondary,
      ),
    };
    final corner = proposal.type.name == 'corner';
    var type = switch (proposal.type.name) {
      'corner' => l10n.segmentReviewCorner,
      'straight' => l10n.segmentReviewStraight,
      _ => l10n.segmentReviewSector,
    };
    if (corner) {
      final degrees = fixed(
        (proposal.turnRadians * 180 / 3.141592653589793).abs(),
        0,
      );
      type +=
          ' · ${proposal.turnRadians > 0 ? l10n.segmentReviewTurnLeft(degrees) : l10n.segmentReviewTurnRight(degrees)}';
    }
    String reasons(List<String> codes) => [
      for (final code in codes)
        switch (code) {
          proposalUncertainConnectedCorners =>
            l10n.segmentReviewConnectedCorners,
          proposalUncertainShortStraight => l10n.segmentReviewShortStraight,
          proposalUncertainGpsGap => l10n.segmentReviewGpsGap,
          _ => l10n.segmentReviewUncertainOther,
        },
    ].join(', ');
    final uncertainty = [
      if (!proposal.start.certain)
        l10n.segmentReviewStartUncertain(
          reasons(proposal.start.uncertaintyReasons),
        ),
      if (!proposal.end.certain)
        l10n.segmentReviewEndUncertain(
          reasons(proposal.end.uncertaintyReasons),
        ),
    ].join(' · ');
    // The geometric apex of an unedited corner, as Overlays shows it.
    String? apex;
    final phases = this.phases;
    if (!item.edited && phases != null && phases.valid) {
      final point = phases.apex;
      apex = point.resolved
          ? l10n.segmentReviewApex(
              fixed(point.progressMeters, 1),
              fixed(point.toleranceMeters, 0),
            )
          : switch (point.unresolvedReason) {
              cornerPhaseMultipleApexes => l10n.segmentReviewApexMultiple,
              cornerPhaseCrossesGate => l10n.segmentReviewApexCrossesGate,
              _ => l10n.segmentReviewApexUnresolved,
            };
    }
    final wraps = proposal.end.progressMeters < proposal.start.progressMeters;
    final decidable =
        item.state == SegmentReviewState.proposed ||
        item.state == SegmentReviewState.rejected;
    final small = theme.textTheme.bodySmall;
    return Opacity(
      opacity: item.state == SegmentReviewState.rejected ? 0.6 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: stateColor),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      stateText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: stateColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      proposal.name,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(type, style: small),
              Text(
                l10n.segmentReviewBounds(
                  fixed(proposal.start.progressMeters, 1),
                  fixed(proposal.start.toleranceMeters, 0),
                  fixed(proposal.end.progressMeters, 1),
                  fixed(proposal.end.toleranceMeters, 0),
                  fixed(proposal.lengthMeters, 1),
                ),
                style: small,
              ),
              if (wraps) Text(l10n.segmentReviewCrossesLine, style: small),
              if (uncertainty.isNotEmpty)
                Text(
                  uncertainty,
                  style: small?.copyWith(color: scheme.primary),
                ),
              if (apex != null) Text(apex, style: small),
              if (decidable)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey(
                      item.state == SegmentReviewState.rejected
                          ? 'restoreProposal'
                          : 'rejectProposal',
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(kMinInteractiveDimension, 48),
                    ),
                    icon: Icon(
                      item.state == SegmentReviewState.rejected
                          ? Icons.undo
                          : Icons.block,
                    ),
                    label: Text(
                      item.state == SegmentReviewState.rejected
                          ? l10n.segmentReviewRestore
                          : l10n.segmentReviewReject,
                    ),
                    onPressed: busy
                        ? null
                        : () => onReject(
                            item.state != SegmentReviewState.rejected,
                          ),
                  ),
                )
              else
                const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
