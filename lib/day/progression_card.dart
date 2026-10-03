import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import 'touch.dart';

/// "11:20:05 UTC on 19 Aug 2026" from a recording clock.
String recordingClockText(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
  String two(int value) => value.toString().padLeft(2, '0');
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)} UTC on '
      '${time.day} ${months[time.month - 1]} ${time.year}';
}

/// How the day went: each session's best and typical lap in recording
/// order, and each segment's typical time per session.
class ProgressionCard extends StatefulWidget {
  const ProgressionCard({
    super.key,
    required this.progression,
    required this.result,
    this.loading = false,
    this.onOpenLap,
  });

  final DayProgression progression;

  /// The theoretical best, which times every segment; null while it is
  /// calculated for the first time.
  final DayTheoreticalBest? result;
  final bool loading;
  final void Function(DayLapRow lap)? onOpenLap;

  @override
  State<ProgressionCard> createState() => _ProgressionCardState();
}

class _ProgressionCardState extends State<ProgressionCard> {
  // Kept for the page: the list rebuilds the card when it scrolls back.
  late bool _bySection =
      readPageState(context, 'progressionBySection') ?? false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Progression', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              key: const ValueKey('progressionView'),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('By session')),
                ButtonSegment(value: true, label: Text('By segment')),
              ],
              selected: {_bySection},
              onSelectionChanged: (selection) => setState(() {
                _bySection = selection.single;
                writePageState(context, 'progressionBySection', _bySection);
              }),
            ),
            const SizedBox(height: 8),
            if (_bySection) ..._sections(context) else ..._sessions(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _sessions(BuildContext context) {
    final theme = Theme.of(context);
    final progression = widget.progression;
    final low = progression.minimumSeconds, high = progression.maximumSeconds;
    return [
      Text(
        'Sessions in recording order; sessions without a recording time '
        'follow in import order. The bar runs from the quickest to the '
        'slowest ranked lap on one time scale, the middle half boxed and the '
        'typical lap marked.',
        style: theme.textTheme.bodySmall,
      ),
      if (progression.runs.isEmpty) const Text('No session to compare.'),
      for (var i = 0; i < progression.runs.length; ++i)
        _session(context, progression.runs[i], i, low, high),
    ];
  }

  Widget _session(
    BuildContext context,
    ProgressionRun run,
    int index,
    double? low,
    double? high,
  ) {
    final theme = Theme.of(context);
    final best = run.bestLap;
    final distribution = run.distribution;
    final typical =
        run.eligibleLapCount >= minimumConsistencySamples &&
        distribution != null;
    final delta = run.bestDeltaPreviousListedSeconds;
    final details = [
      run.firstSectionUtcMilliseconds == null
          ? 'Recording time unavailable'
          : recordingClockText(run.firstSectionUtcMilliseconds!),
      switch (run.state) {
        ProgressionRunState.noRecordedLaps => 'No recorded laps',
        ProgressionRunState.noEligibleLaps =>
          'No ranked lap · 0 of ${run.lapCount} laps',
        ProgressionRunState.available =>
          '${run.eligibleLapCount} of ${run.lapCount} laps ranked',
      },
      typical
          ? 'Typical ${displayTime(distribution.median)}'
          : 'Typical lap needs at least $minimumConsistencySamples ranked laps',
      if (delta != null)
        'Best ${displayDelta(delta)} against ${run.previousListedRunName}',
      if (run.run.conditions case final conditions?) 'Conditions: $conditions',
      if (run.run.setupChanges case final setup?) 'Setup: $setup',
      if (run.run.notes case final notes?) 'Notes: $notes',
    ];
    return InkWell(
      key: ValueKey('progressionRun ${run.runId}'),
      onTap: best == null || widget.onOpenLap == null
          ? null
          : () => widget.onOpenLap!(best),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${index + 1}. ${run.runName}',
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  best == null ? '—' : displayTime(best.durationSeconds),
                  key: ValueKey('progressionBest ${run.runId}'),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            if (best != null)
              Text(
                'Best: LAP ${best.lapNumber}',
                style: theme.textTheme.bodySmall,
              ),
            for (final line in details)
              Text(line, style: theme.textTheme.bodySmall),
            if (typical && low != null && high != null) ...[
              const SizedBox(height: 4),
              SizedBox(
                height: 18,
                width: double.infinity,
                child: CustomPaint(
                  key: ValueKey('progressionBar ${run.runId}'),
                  painter: _RangePainter(
                    distribution: distribution,
                    low: low,
                    high: high,
                    line: theme.colorScheme.outline,
                    box: theme.colorScheme.primaryContainer,
                    mark: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _sections(BuildContext context) {
    final theme = Theme.of(context);
    final result = widget.result;
    if (widget.loading || result == null) {
      return [const Text('Measured with the theoretical best…')];
    }
    if (result.state != DayTheoreticalBestState.ready) {
      return [Text(result.message)];
    }
    final sections = result.sectionProgression([
      for (final run in widget.progression.runs) run.run,
    ]);
    return [
      Text(
        'Each segment\'s typical time (median) and spread (middle half) per '
        'session. The quickest typical time of each segment is highlighted. '
        'Fewer than $minimumConsistencySamples laps: no statistics. Tap a cell '
        'for its laps.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      _SectionTable(sections: sections, result: result),
    ];
  }
}

class _RangePainter extends CustomPainter {
  const _RangePainter({
    required this.distribution,
    required this.low,
    required this.high,
    required this.line,
    required this.box,
    required this.mark,
  });

  final LapDistribution distribution;
  final double low, high;
  final Color line, box, mark;

  @override
  void paint(Canvas canvas, Size size) {
    double x(double seconds) => high <= low
        ? size.width / 2
        : 2 +
              (size.width - 4) *
                  ((seconds - low) / (high - low)).clamp(0.0, 1.0);
    final middle = size.height / 2;
    canvas.drawLine(
      Offset(x(distribution.minimum), middle),
      Offset(x(distribution.maximum), middle),
      Paint()
        ..color = line
        ..strokeWidth = 2,
    );
    canvas.drawRect(
      Rect.fromLTRB(
        x(distribution.q1),
        2,
        math.max(x(distribution.q3), x(distribution.q1) + 2),
        size.height - 2,
      ),
      Paint()..color = box,
    );
    canvas.drawLine(
      Offset(x(distribution.median), 0),
      Offset(x(distribution.median), size.height),
      Paint()
        ..color = mark
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_RangePainter old) =>
      old.distribution != distribution || old.low != low || old.high != high;
}

/// Segments by sessions: the segment names stay while the sessions scroll
/// sideways on a phone.
class _SectionTable extends StatelessWidget {
  const _SectionTable({required this.sections, required this.result});

  final SectionProgression sections;
  final DayTheoreticalBest result;

  static const _nameWidth = 96.0, _cellWidth = 112.0;

  String _lapName(Object? reference) {
    for (final lap in result.laps) {
      if (lap.lap.reference == reference) return lap.lap.displayName;
    }
    return 'Lap unavailable';
  }

  void _showLaps(
    BuildContext context,
    SectionProgressionRow row,
    SectionProgressionSession session,
    SectionProgressionCell cell,
  ) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const ValueKey('sectionCellLaps'),
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              '${row.name} · ${session.run.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final lap in cell.laps)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_lapName(lap.reference)),
                trailing: Text(displayTime(lap.seconds)),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final numbers = theme.textTheme.bodySmall?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (sections.sessions.isEmpty) {
      return const Text('No session has timed segments.');
    }
    final label = theme.textTheme.labelMedium;
    return StickyTable(
      key: const ValueKey('sectionTable'),
      firstWidth: _nameWidth,
      cellWidths: [for (final _ in sections.sessions) _cellWidth],
      rowHeight: 52,
      header: StickyRow(
        first: const SizedBox.shrink(),
        cells: [
          for (final session in sections.sessions)
            TableCellText(
              session.run.name,
              style: label,
              alignment: Alignment.center,
              maxLines: 2,
            ),
        ],
      ),
      rows: [
        for (final row in sections.segments)
          StickyRow(
            first: TableCellText(
              row.name,
              style: label,
              alignment: Alignment.centerLeft,
              maxLines: 2,
            ),
            cells: [
              for (var c = 0; c < row.cells.length; ++c)
                _cell(context, row, c, numbers, scheme),
            ],
          ),
      ],
    );
  }

  Widget _cell(
    BuildContext context,
    SectionProgressionRow row,
    int index,
    TextStyle? numbers,
    ColorScheme scheme,
  ) {
    final cell = row.cells[index];
    final summary = cell.summary;
    final quickest = summary.available && summary.median == row.fastestTypical;
    final content = summary.available
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                displayTime(summary.median!),
                style: numbers?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: quickest ? scheme.onPrimaryContainer : null,
                ),
              ),
              Text(
                'spread ${summary.interquartileRange!.toStringAsFixed(3)} s',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: quickest ? scheme.onPrimaryContainer : null,
                ),
              ),
            ],
          )
        : Text(
            summary.count == 0
                ? '—'
                : '${summary.count} ${summary.count == 1 ? 'lap' : 'laps'}',
            style: numbers?.copyWith(color: scheme.outline),
          );
    return InkWell(
      key: ValueKey('sectionCell ${row.segmentId} ${cell.runId}'),
      onTap: cell.laps.isEmpty
          ? null
          : () => _showLaps(context, row, sections.sessions[index], cell),
      child: Container(
        color: quickest ? scheme.primaryContainer : null,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // Only a last resort: the cell grows with the text size.
        child: FittedBox(fit: BoxFit.scaleDown, child: content),
      ),
    );
  }
}
