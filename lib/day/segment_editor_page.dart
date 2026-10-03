import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'day_results_controller.dart';
import 'segment_review_page.dart';
import 'theoretical_best_card.dart';
import 'track_map.dart';

/// The segment types a driver can choose, as stored.
const segmentTypes = ['corner', 'straight', 'sector'];

/// "Corner", "Straight", "Sector".
String segmentTypeLabel(AppLocalizations l10n, String type) => switch (type) {
  'corner' => l10n.segmentEditorTypeCorner,
  'straight' => l10n.segmentEditorTypeStraight,
  _ => l10n.segmentEditorTypeSector,
};

/// A segment's name in the app's language: an automatic name, also when
/// split ("Corner 3 (2)"), is translated; a name the user gave is shown as
/// written.
String _segmentName(AppLocalizations l10n, String name) =>
    l10n.tbSegmentName(name);

final _translatedShort = RegExp(r'^(\p{L})\p{L}*\s+(.+)$', unicode: true);

/// [shortSegmentName] of a segment's name as shown: a translated automatic
/// name keeps its first letter in any language ("Z3" for "Zakręt 3"); a
/// name the user gave is shortened exactly as before.
String _shortName(AppLocalizations l10n, String stored) {
  final shown = _segmentName(l10n, stored);
  if (shown == stored) return shortSegmentName(stored);
  final match = _translatedShort.firstMatch(shown);
  return match == null
      ? shown
      : '${match.group(1)!.toUpperCase()}${match.group(2)}';
}

final _wouldBeEmpty = RegExp(r'^“(.*)” would become empty\.$');
final _wouldBeInvalid = RegExp(r'^“(.*)” would be invalid\.$');
final _wouldOverlap = RegExp(r'^“(.*)” would overlap “(.*)”\.$');
final _tooMany = RegExp(r'^At most (\d+) segments can be approved\.$');
final _bounds = RegExp(r'^Bounds must lie between 0 and (.+) m\.$');

/// Why a segment edit was refused (`DayResultsController` and
/// `telemetry_core` segment editing) in the app's language; an error the
/// app does not know is shown as written.
String _segmentError(AppLocalizations l10n, String error) {
  if (_wouldBeEmpty.firstMatch(error) case final m?) {
    return l10n.segmentEditorErrorWouldBeEmpty(_segmentName(l10n, m[1]!));
  }
  if (_wouldBeInvalid.firstMatch(error) case final m?) {
    return l10n.segmentEditorErrorWouldBeInvalid(_segmentName(l10n, m[1]!));
  }
  if (_wouldOverlap.firstMatch(error) case final m?) {
    return l10n.segmentEditorErrorWouldOverlap(
      _segmentName(l10n, m[1]!),
      _segmentName(l10n, m[2]!),
    );
  }
  if (_tooMany.firstMatch(error) case final m?) {
    return l10n.segmentEditorErrorTooMany(int.parse(m[1]!));
  }
  if (_bounds.firstMatch(error) case final m?) {
    return l10n.segmentEditorErrorBounds(m[1]!);
  }
  return switch (error) {
    'The day is being saved.' => l10n.segmentEditorErrorSaving,
    'The segments can be edited once the theoretical best is calculated.' =>
      l10n.segmentEditorErrorNotCalculated,
    'The segments are already the automatic ones.' =>
      l10n.segmentEditorErrorAlreadyAutomatic,
    'This edit is not possible.' => l10n.segmentEditorErrorNotPossible,
    'The theoretical best needs at least one segment. Restore the automatic '
        'segments instead.' =>
      l10n.segmentEditorErrorLastSegment,
    'This segment is no longer approved.' =>
      l10n.segmentEditorErrorNoLongerApproved,
    'Nothing to undo.' => l10n.segmentEditorErrorNothingToUndo,
    'Nothing to redo.' => l10n.segmentEditorErrorNothingToRedo,
    'The segments changed outside this editor, so the edit history was '
        'cleared.' =>
      l10n.segmentEditorErrorHistoryCleared,
    'The stored approved segments are invalid.' =>
      l10n.segmentEditorErrorInvalidStored,
    'Segments approved for a different track configuration must be '
        'discarded first.' =>
      l10n.segmentEditorErrorOtherConfiguration,
    'Only one segment may cross the start/finish line.' =>
      l10n.segmentEditorErrorCrossesGate,
    'Choose corner, straight or sector.' => l10n.segmentEditorErrorChooseType,
    'The track axis is unavailable.' => l10n.segmentEditorErrorNoAxis,
    'Split inside the segment, away from its ends.' =>
      l10n.segmentEditorErrorSplitInside,
    'Enter a name of 1–160 characters for the new segment.' =>
      l10n.segmentEditorErrorSplitName,
    'Choose two different approved segments.' =>
      l10n.segmentEditorErrorMergeSame,
    'Only segments that share a boundary can be merged.' =>
      l10n.segmentEditorErrorMergeNotAdjacent,
    'Merging would cover the whole lap; a segment needs distinct start and '
        'end.' =>
      l10n.segmentEditorErrorMergeWholeLap,
    'Enter a name of 1–160 characters.' => l10n.segmentEditorErrorName,
    'A segment cannot be empty.' => l10n.segmentEditorErrorEmpty,
    _ => error,
  };
}

/// Reviews and corrects the day's track segments (FET-34): the best lap's
/// map with the segment boundaries, and the segments in lap order. Tap a
/// segment to rename it, change its type, move its start or end, split it,
/// merge it with the next one or remove it. Each change times every lap
/// again; "Restore automatic" goes back to the best lap's proposals, and
/// "Review proposals" opens the optional proposal review
/// ([SegmentReviewPage]).
class SegmentEditorPage extends StatefulWidget {
  const SegmentEditorPage({
    super.key,
    required this.controller,
    this.path,
    this.gate,
  });

  final DayResultsController controller;

  /// The best lap's trace.
  final LapPath? path;
  final (Offset, Offset)? gate;

  @override
  State<SegmentEditorPage> createState() => _SegmentEditorPageState();
}

class _SegmentEditorPageState extends State<SegmentEditorPage> {
  // The last calculated result, shown while the next one is calculated.
  DayTheoreticalBest? _shown;
  String? _selectedId;

  // Each fix of the best lap's trace on the shared axis, for the map.
  DayTheoreticalBest? _placedFor;
  List<(double, PathPoint)> _placed = const [];
  Map<double, double?> _progressOfFix = const {};

  DayResultsController get _controller => widget.controller;

  // A boundary being placed on the map (Overlays' "Pick on map"): which one
  // of the selected segment, and where the tools take it.
  BoundaryPick? _pickTarget;
  ValueChanged<double>? _pickDeliver;

  // The larger side of the best lap's session on the map, by which Overlays
  // scales its pick tolerances.
  DayTheoreticalBest? _scaleFor;
  double _mapScale = double.nan;

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
    final result = _controller.theoreticalBest;
    if (result == null && !_controller.theoreticalBestLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.requestTheoreticalBest();
      });
    }
    if (result != null && !identical(result, _shown)) {
      _shown = result;
      // The tools that asked for a point are built again for this result.
      _pickTarget = null;
      _pickDeliver = null;
    }
    if (mounted) setState(() {});
  }

  void _tell(String message) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));

  void _report(String error) {
    if (error.isNotEmpty) _tell(_segmentError(context.l10n, error));
  }

  void _place(DayTheoreticalBest result) {
    if (identical(result, _placedFor)) return;
    _placedFor = result;
    final path = widget.path;
    final best = result.bestLap;
    if (path == null || best == null) {
      _placed = const [];
      _progressOfFix = const {};
      return;
    }
    final placed = <(double, PathPoint)>[];
    final progress = <double, double?>{};
    for (final segment in path.segments) {
      for (final point in segment) {
        final at = result.progressAt(best, point.telemetryTime);
        progress[point.telemetryTime] = at;
        if (at != null) placed.add((at, point));
      }
    }
    _placed = placed;
    _progressOfFix = progress;
  }

  /// The fix of the best lap nearest to [progress] along the track.
  PathPoint? _pointAt(double progress, double length) {
    PathPoint? nearest;
    var distance = double.infinity;
    for (final (at, point) in _placed) {
      final apart = (at - progress).abs();
      final circular = length > 0 ? math.min(apart, length - apart) : apart;
      if (circular < distance) {
        distance = circular;
        nearest = point;
      }
    }
    return nearest;
  }

  double _scaleOf(DayTheoreticalBest result) {
    if (identical(result, _scaleFor)) return _mapScale;
    _scaleFor = result;
    final best = result.bestLap;
    final session = best == null ? null : _controller.session(best.runId);
    final origin = widget.path?.origin;
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    void add(double x, double y) {
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }

    if (session != null && origin != null) {
      final whole = lapPath(
        session,
        0,
        session.duration,
        origin: origin,
        maximumPoints: 4000,
      );
      for (final segment in whole.segments) {
        for (final point in segment) {
          add(point.eastMeters, point.northMeters);
        }
      }
    }
    if (!minX.isFinite) {
      for (final (_, point) in _placed) {
        add(point.eastMeters, point.northMeters);
      }
    }
    return _mapScale = minX.isFinite
        ? math.max(maxX - minX, maxY - minY)
        : double.nan;
  }

  void _startPick(BoundaryPick? target, ValueChanged<double> deliver) =>
      setState(() {
        _pickTarget = target;
        _pickDeliver = target == null ? null : deliver;
      });

  void _pickAt(DayTheoreticalBest result, double east, double north) {
    final deliver = _pickDeliver;
    if (_pickTarget == null || deliver == null) return;
    final pick = pickBoundaryAt(
      [
        for (final (at, point) in _placed)
          ProgressMapPoint(at, point.eastMeters, point.northMeters),
      ],
      east,
      north,
      mapScaleMeters: _scaleOf(result),
      lengthMeters: result.axisLengthMeters,
    );
    final l10n = context.l10n;
    final progress = pick.progressMeters;
    if (progress == null) {
      _tell(switch (pick.reason) {
        'ambiguous' => l10n.segmentPickAmbiguous,
        'farFromTrack' => l10n.segmentPickFar,
        _ => l10n.segmentPickNoTrace,
      });
      return;
    }
    setState(() {
      _pickTarget = null;
      _pickDeliver = null;
    });
    deliver(progress);
  }

  int? _indexOf(DayTheoreticalBest result, String? id) {
    if (id == null) return null;
    for (var i = 0; i < result.segments.length; ++i) {
      if (result.approvedSegment(i)?['id'] == id) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final result = _shown;
    final l10n = context.l10n;
    final loading =
        _controller.theoreticalBestLoading ||
        _controller.theoreticalBest == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.segmentEditorTitle),
        actions: [
          IconButton(
            key: const ValueKey('undoSegmentEdit'),
            tooltip: l10n.segmentEditorUndo,
            icon: const Icon(Icons.undo),
            onPressed: _controller.canUndoSegmentEdit && !loading
                ? () => _report(_controller.undoSegmentEdit())
                : null,
          ),
          IconButton(
            key: const ValueKey('redoSegmentEdit'),
            tooltip: l10n.segmentEditorRedo,
            icon: const Icon(Icons.redo),
            onPressed: _controller.canRedoSegmentEdit && !loading
                ? () => _report(_controller.redoSegmentEdit())
                : null,
          ),
        ],
      ),
      body: SafeArea(
        child: result == null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    Text(l10n.segmentEditorTiming),
                  ],
                ),
              )
            : result.state != DayTheoreticalBestState.ready
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.tbMessage(result.message)),
                    if (!loading && offersCalculateAgain(result))
                      CalculateAgainButton(_controller.retryTheoreticalBest),
                  ],
                ),
              )
            : _ready(context, result, loading),
      ),
    );
  }

  Widget _ready(BuildContext context, DayTheoreticalBest result, bool busy) {
    _place(result);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final selected = _indexOf(result, _selectedId);
    final path = widget.path;
    final picking = _pickTarget;
    final map = path == null || path.isEmpty
        ? null
        : Stack(
            children: [
              Positioned.fill(
                child: TrackMap(
                  key: const ValueKey('segmentMap'),
                  path: path,
                  gate: widget.gate,
                  pointColor: _segmentColors(result, selected),
                  marks: _boundaryMarks(result, selected),
                  onTapMeters: picking == null || busy
                      ? null
                      : (east, north) => _pickAt(result, east, north),
                  semanticLabel: selected == null
                      ? l10n.segmentEditorMapLabel
                      : l10n.segmentEditorMapLabelHighlighted(
                          _segmentName(l10n, result.segments[selected].name),
                        ),
                ),
              ),
              if (picking != null)
                Positioned(
                  left: 8,
                  top: 8,
                  right: 64,
                  child: IgnorePointer(
                    child: Container(
                      key: const ValueKey('segmentPickBanner'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        switch (picking) {
                          BoundaryPick.start => l10n.segmentPickBannerStart,
                          BoundaryPick.end => l10n.segmentPickBannerEnd,
                          BoundaryPick.split => l10n.segmentPickBannerSplit,
                        },
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
    final list = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.segmentsAutomatic
                        ? l10n.segmentEditorAutomatic
                        : l10n.segmentEditorEdited,
                    key: const ValueKey('segmentsState'),
                    style: theme.textTheme.titleSmall,
                  ),
                  Text(
                    l10n.segmentEditorSummary(
                      result.theoreticalBestSeconds == null
                          ? '—'
                          : displayTime(result.theoreticalBestSeconds!),
                      result.segments.length,
                    ),
                    key: const ValueKey('editorTheoreticalBest'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            // Wraps its label with large text rather than squeeze the
            // segments' summary.
            Flexible(
              child: TextButton.icon(
                key: const ValueKey('restoreAutomatic'),
                icon: const Icon(Icons.restore),
                label: Text(l10n.segmentEditorRestoreAutomatic),
                onPressed: result.segmentsAutomatic || busy
                    ? null
                    : () => _confirmRestore(),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text(
          result.segmentsAutomatic
              ? switch (result.bestLap) {
                  final best? => l10n.segmentEditorProposedFrom(l10n.lap(best)),
                  null => l10n.segmentEditorProposedFromBestLap,
                }
              : l10n.segmentEditorCorrectionsSaved,
          style: theme.textTheme.bodySmall,
        ),
      ),
      // The optional review of the automatic proposals (FET-56).
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('reviewProposals'),
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinInteractiveDimension, 48),
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: Text(l10n.segmentReviewOpen),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SegmentReviewPage(controller: _controller),
              ),
            ),
          ),
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView.builder(
          key: const ValueKey('segmentList'),
          itemCount: result.segments.length,
          itemBuilder: (context, index) => _segmentRow(
            context,
            result,
            index,
            selected: index == selected,
            busy: busy,
          ),
        ),
      ),
    ];
    final progress = SizedBox(
      height: 4,
      child: busy ? const LinearProgressIndicator() : null,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Sideways (a phone in landscape): the map beside the list, so
        // the list keeps its height.
        if (map != null &&
            constraints.maxWidth > constraints.maxHeight &&
            constraints.maxWidth >= 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              progress,
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 2, child: map),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: list,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            progress,
            if (map != null)
              SizedBox(
                // A short screen (or large text) keeps room for the list.
                height: (constraints.maxHeight * 0.35).clamp(140.0, 240.0),
                child: map,
              ),
            ...list,
          ],
        );
      },
    );
  }

  Color _segmentColor(BuildContext context, int index, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    // Blue stands out from the amber and green of the other segments.
    if (selected) return scheme.secondary;
    return index.isEven ? scheme.primary : scheme.tertiary;
  }

  // Text on [_segmentColor].
  Color _segmentInk(BuildContext context, int index, bool selected) {
    final scheme = Theme.of(context).colorScheme;
    if (selected) return scheme.onSecondary;
    return index.isEven ? scheme.onPrimary : scheme.onTertiary;
  }

  Color? Function(PathPoint) _segmentColors(
    DayTheoreticalBest result,
    int? selected,
  ) {
    final neutral = Theme.of(context).colorScheme.outline;
    final colors = [
      for (var i = 0; i < result.segments.length; ++i)
        _segmentColor(context, i, i == selected),
    ];
    final progress = _progressOfFix;
    return (point) {
      final at = progress[point.telemetryTime];
      final index = at == null ? null : result.segmentAt(at);
      return index == null ? neutral : colors[index];
    };
  }

  List<MapMark> _boundaryMarks(DayTheoreticalBest result, int? selected) {
    final length = result.axisLengthMeters;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final marks = <MapMark>[];
    for (var i = 0; i < result.segments.length; ++i) {
      if (i == selected) continue;
      final point = _pointAt(result.segments[i].startProgressMeters, length);
      if (point != null) {
        marks.add(
          MapMark(point.eastMeters, point.northMeters, onSurface, radius: 4),
        );
      }
    }
    if (selected != null) {
      final segment = result.segments[selected];
      for (final progress in [
        segment.startProgressMeters,
        segment.endProgressMeters,
      ]) {
        final point = _pointAt(progress, length);
        if (point != null) {
          marks.add(
            MapMark(
              point.eastMeters,
              point.northMeters,
              Theme.of(context).colorScheme.onSurface,
              radius: 7,
            ),
          );
        }
      }
      final pending = _pendingMarks;
      for (final progress in pending) {
        final point = _pointAt(progress, length);
        if (point != null) {
          marks.add(
            MapMark(
              point.eastMeters,
              point.northMeters,
              const Color(0xffd95926),
              radius: 7,
            ),
          );
        }
      }
    }
    return marks;
  }

  // Boundaries the open segment tools would set, shown before they apply.
  List<double> _pendingMarks = const [];

  Widget _segmentRow(
    BuildContext context,
    DayTheoreticalBest result,
    int index, {
    required bool selected,
    required bool busy,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final segment = result.segments[index];
    final name = _segmentName(l10n, segment.name);
    final id = result.approvedSegment(index)?['id'] as String? ?? '';
    final length = segment.endProgressMeters >= segment.startProgressMeters
        ? segment.endProgressMeters - segment.startProgressMeters
        : segment.endProgressMeters +
              result.axisLengthMeters -
              segment.startProgressMeters;
    final row = l10n.segmentEditorRow(
      segmentTypeLabel(l10n, segment.type),
      segment.startProgressMeters.toStringAsFixed(0),
      segment.endProgressMeters.toStringAsFixed(0),
      length.toStringAsFixed(0),
    );
    final tile = ListTile(
      key: ValueKey('segment $id'),
      selected: selected,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _segmentColor(context, index, selected),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _shortName(l10n, segment.name),
          maxLines: 1,
          overflow: TextOverflow.clip,
          style: theme.textTheme.labelSmall?.copyWith(
            color: _segmentInk(context, index, selected),
          ),
        ),
      ),
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        result.segmentMatchesProposal(index)
            ? row
            : l10n.segmentEditorRowEdited(row),
      ),
      trailing: Text(
        segment.seconds == null ? '—' : displayTime(segment.seconds!),
        style: theme.textTheme.bodySmall,
      ),
      onTap: () => setState(() {
        _selectedId = selected ? null : id;
        _pendingMarks = const [];
        _pickTarget = null;
        _pickDeliver = null;
      }),
    );
    if (!selected) return tile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile,
        _SegmentTools(
          key: ValueKey('tools $id ${identityHashCode(result)}'),
          result: result,
          index: index,
          busy: busy,
          picking: _pickTarget,
          onPick: _startPick,
          onPending: (marks) => setState(() => _pendingMarks = marks),
          onEdit:
              ({
                required String name,
                required String type,
                required double start,
                required double end,
                required bool joined,
              }) => _report(
                _controller.editSegment(
                  id,
                  name: name,
                  type: type,
                  startMeters: start,
                  endMeters: end,
                  keepAdjacentJoined: joined,
                ),
              ),
          onSplit: (at) => _report(_controller.splitSegment(id, at)),
          onMerge: (otherId) => _report(_controller.mergeSegments(id, otherId)),
          onRemove: () {
            final error = _controller.removeSegment(id);
            if (error.isEmpty) setState(() => _selectedId = null);
            _report(error);
          },
        ),
        const Divider(height: 1),
      ],
    );
  }

  Future<void> _confirmRestore() async {
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.segmentEditorRestoreTitle),
        content: Text(context.l10n.segmentEditorRestoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('confirmRestore'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.segmentEditorRestore),
          ),
        ],
      ),
    );
    if (restore != true || !mounted) return;
    setState(() => _selectedId = null);
    _report(_controller.restoreAutomaticSegments());
  }
}

/// Which boundary of the selected segment a tap on the map places.
enum BoundaryPick { start, end, split }

typedef _EditCallback = void Function({
  required String name,
  required String type,
  required double start,
  required double end,
  required bool joined,
});

/// The tools of the selected segment: name and type, its two boundaries
/// nudged in metres, a split point, merge with the next segment and remove.
class _SegmentTools extends StatefulWidget {
  const _SegmentTools({
    super.key,
    required this.result,
    required this.index,
    required this.busy,
    required this.picking,
    required this.onPick,
    required this.onPending,
    required this.onEdit,
    required this.onSplit,
    required this.onMerge,
    required this.onRemove,
  });

  final DayTheoreticalBest result;
  final int index;
  final bool busy;

  /// The boundary being placed on the map, if any.
  final BoundaryPick? picking;

  /// Asks the page for a point on the map ([BoundaryPick] null: no longer).
  final void Function(BoundaryPick? target, ValueChanged<double> deliver)
  onPick;
  final ValueChanged<List<double>> onPending;
  final _EditCallback onEdit;
  final ValueChanged<double> onSplit;
  final ValueChanged<String> onMerge;
  final VoidCallback onRemove;

  @override
  State<_SegmentTools> createState() => _SegmentToolsState();
}

class _SegmentToolsState extends State<_SegmentTools> {
  // The name as shown: an automatic name in the app's language.
  String get _shownName => _segmentName(context.l10n, _segment.name);

  // Seeded once: a later change of language does not count as an edit.
  late final String _seededName = _shownName;
  late final TextEditingController _name = TextEditingController(
    text: _seededName,
  );
  late String _type = _segment.type;
  late double _start = _segment.startProgressMeters;
  late double _end = _segment.endProgressMeters;
  bool _joined = true;

  // The split point as a distance from the segment's start.
  late double _splitAfter = _span / 2;

  TheoreticalBestRow get _segment => widget.result.segments[widget.index];
  double get _length => widget.result.axisLengthMeters;

  double get _span {
    final segment = _segment;
    final span = segment.endProgressMeters - segment.startProgressMeters;
    return span > 0 ? span : span + _length;
  }

  bool get _changed =>
      _name.text.trim() != _seededName ||
      _type != _segment.type ||
      _start != _segment.startProgressMeters ||
      _end != _segment.endProgressMeters;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  // Moves a bound by [delta] metres around the loop: past the gate it
  // continues from the other end.
  double _moved(double value, double delta) {
    var next = value + delta;
    if (next < 0) next += _length;
    if (next > _length) next -= _length;
    return double.parse(next.toStringAsFixed(3));
  }

  // A field takes a picked point as Overlays shows it, to 0.1 m.
  static double _tenth(double value) => double.parse(value.toStringAsFixed(1));

  void _picked(BoundaryPick target, double meters) {
    if (!mounted) return;
    switch (target) {
      case BoundaryPick.start:
        setState(() => _start = _tenth(meters));
        _pending();
      case BoundaryPick.end:
        setState(() => _end = _tenth(meters));
        _pending();
      case BoundaryPick.split:
        var after = _tenth(meters) - _segment.startProgressMeters;
        if (after < 0) after += _length;
        if (after < 1 || after > _span - 1) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(context.l10n.segmentPickOutside)),
            );
          return;
        }
        setState(() => _splitAfter = after);
        widget.onPending([(_segment.startProgressMeters + after) % _length]);
    }
  }

  Widget _pickButton(BoundaryPick target) {
    final l10n = context.l10n;
    final active = widget.picking == target;
    return Align(
      alignment: Alignment.center,
      child: TextButton.icon(
        key: ValueKey('pick ${target.name}'),
        style: TextButton.styleFrom(
          minimumSize: const Size(kMinInteractiveDimension, 48),
        ),
        icon: Icon(active ? Icons.close : Icons.ads_click),
        label: Text(active ? l10n.segmentPickActive : l10n.segmentPickOnMap),
        onPressed: widget.busy
            ? null
            : () => widget.onPick(
                active ? null : target,
                (meters) => _picked(target, meters),
              ),
      ),
    );
  }

  void _pending() {
    final marks = <double>[
      if (_start != _segment.startProgressMeters) _start,
      if (_end != _segment.endProgressMeters) _end,
    ];
    widget.onPending(marks);
  }

  Widget _nudges(
    String label,
    String key,
    double value,
    ValueChanged<double> set,
  ) {
    final theme = Theme.of(context);
    Widget nudge(double delta) => SizedBox(
      width: 48,
      height: 48,
      child: IconButton.outlined(
        key: ValueKey(
          '$key ${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)}',
        ),
        tooltip: '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(0)} m',
        onPressed: widget.busy
            ? null
            : () {
                setState(() => set(_moved(value, delta)));
                _pending();
              },
        icon: Text(
          '${delta > 0 ? '+' : '−'}${delta.abs().toStringAsFixed(0)}',
          style: theme.textTheme.labelMedium,
        ),
      ),
    );
    return Row(
      children: [
        nudge(-10),
        const SizedBox(width: 4),
        nudge(-1),
        Expanded(
          child: Column(
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                '${value.toStringAsFixed(1)} m',
                key: ValueKey('$key value'),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ),
        nudge(1),
        const SizedBox(width: 4),
        nudge(10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final result = widget.result;
    final count = result.segments.length;
    final next = count > 1 ? (widget.index + 1) % count : null;
    final nextId = next == null
        ? null
        : result.approvedSegment(next)?['id'] as String?;
    final splitAt = (_segment.startProgressMeters + _splitAfter) % _length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('segmentName'),
            controller: _name,
            maxLength: 160,
            decoration: InputDecoration(labelText: l10n.segmentEditorName),
            onChanged: (_) => setState(() {}),
          ),
          SegmentedButton<String>(
            key: const ValueKey('segmentType'),
            segments: [
              for (final type in segmentTypes)
                ButtonSegment(
                  value: type,
                  label: Text(segmentTypeLabel(l10n, type)),
                ),
            ],
            selected: {_type},
            onSelectionChanged: (types) => setState(() => _type = types.first),
          ),
          const SizedBox(height: 12),
          _nudges(
            l10n.segmentEditorStart,
            'segmentStart',
            _start,
            (value) => _start = value,
          ),
          _pickButton(BoundaryPick.start),
          _nudges(
            l10n.segmentEditorEnd,
            'segmentEnd',
            _end,
            (value) => _end = value,
          ),
          _pickButton(BoundaryPick.end),
          SwitchListTile(
            key: const ValueKey('keepJoined'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.segmentEditorKeepJoined),
            value: _joined,
            onChanged: (value) => setState(() => _joined = value),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  key: const ValueKey('applySegment'),
                  onPressed: _changed && !widget.busy
                      ? () => widget.onEdit(
                          // An automatic name left as shown keeps its
                          // stored (English) name.
                          name: _name.text.trim() == _seededName
                              ? _segment.name
                              : _name.text,
                          type: _type,
                          start: _start,
                          end: _end,
                          joined: _joined,
                        )
                      : null,
                  child: Text(l10n.segmentEditorApply),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                key: const ValueKey('resetSegment'),
                onPressed: _changed
                    ? () {
                        setState(() {
                          _name.text = _seededName;
                          _type = _segment.type;
                          _start = _segment.startProgressMeters;
                          _end = _segment.endProgressMeters;
                        });
                        widget.onPending(const []);
                      }
                    : null,
                child: Text(l10n.segmentEditorReset),
              ),
            ],
          ),
          const Divider(height: 24),
          Text(
            l10n.segmentEditorSplitAt(splitAt.toStringAsFixed(1)),
            key: const ValueKey('splitValue'),
            style: theme.textTheme.bodySmall,
          ),
          if (_span > 2) _pickButton(BoundaryPick.split),
          if (_span > 2)
            Slider(
              key: const ValueKey('splitSlider'),
              min: 1,
              max: _span - 1,
              value: _splitAfter.clamp(1, _span - 1),
              onChanged: widget.busy
                  ? null
                  : (value) {
                      setState(() => _splitAfter = value.roundToDouble());
                      widget.onPending([
                        (_segment.startProgressMeters + _splitAfter) % _length,
                      ]);
                    },
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('splitSegment'),
                icon: const Icon(Icons.call_split),
                label: Text(l10n.segmentEditorSplitHere),
                onPressed: widget.busy || _span <= 2
                    ? null
                    : () => widget.onSplit(splitAt),
              ),
              OutlinedButton.icon(
                key: const ValueKey('mergeSegment'),
                icon: const Icon(Icons.merge),
                label: Text(
                  next == null
                      ? l10n.segmentEditorMergeWithNext
                      : l10n.segmentEditorMergeWith(
                          _shortName(l10n, result.segments[next].name),
                        ),
                ),
                onPressed: widget.busy || nextId == null
                    ? null
                    : () => widget.onMerge(nextId),
              ),
              OutlinedButton.icon(
                key: const ValueKey('removeSegment'),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.segmentEditorRemove),
                onPressed: widget.busy || count <= 1 ? null : widget.onRemove,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
