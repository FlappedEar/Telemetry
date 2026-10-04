import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Whether [context] is on a phone or tablet, where one finger scrolls the
/// page and maps take two fingers (Android, iOS).
bool isTouchPlatform(BuildContext context) =>
    switch (Theme.of(context).platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => true,
      _ => false,
    };

/// A scale gesture that needs two fingers. It claims the gesture as soon as
/// the second finger lands, before the page's scroll can take it, and never
/// takes a one-finger drag, which stays with the page.
class TwoFingerScaleGestureRecognizer extends ScaleGestureRecognizer {
  TwoFingerScaleGestureRecognizer({super.debugOwner})
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );

  final Set<int> _down = {};

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _down.add(event.pointer);
    if (_down.length >= 2) resolve(GestureDisposition.accepted);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _down.remove(event.pointer);
    }
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _down.clear();
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void resolve(GestureDisposition disposition) {
    // One finger never wins: it is the page's scroll.
    if (disposition == GestureDisposition.accepted && _down.length < 2) {
      return;
    }
    super.resolve(disposition);
  }

  @override
  String get debugDescription => 'two-finger scale';
}

/// Listens for two-finger gestures on [child]: [onStart] when the second
/// finger lands, [onUpdate] while two or more fingers move, with the scale
/// since the start and the focal point in [child]'s coordinates.
class TwoFingerGestures extends StatelessWidget {
  const TwoFingerGestures({
    super.key,
    required this.onStart,
    required this.onUpdate,
    this.onEnd,
    required this.child,
  });

  final void Function(Offset focalPoint) onStart;
  final void Function(Offset focalPoint, double scale) onUpdate;
  final VoidCallback? onEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    var active = false;
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        TwoFingerScaleGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              TwoFingerScaleGestureRecognizer
            >(() => TwoFingerScaleGestureRecognizer(debugOwner: this), (
              recognizer,
            ) {
              recognizer
                ..onStart = (details) {
                  active = details.pointerCount >= 2;
                  if (active) onStart(details.localFocalPoint);
                }
                ..onUpdate = (details) {
                  if (details.pointerCount < 2) return;
                  if (!active) {
                    // A finger came back: start again from here.
                    active = true;
                    onStart(details.localFocalPoint);
                    return;
                  }
                  onUpdate(details.localFocalPoint, details.scale);
                }
                ..onEnd = (_) {
                  if (active) onEnd?.call();
                  active = false;
                };
            }),
      },
      child: child,
    );
  }
}

/// Zooms and moves [child] with two fingers (one finger scrolls the page);
/// on desktop, the mouse drags and the wheel zooms. Never zooms out past
/// the whole of [child].
class PinchZoom extends StatefulWidget {
  const PinchZoom({
    super.key,
    required this.child,
    this.maxScale = 12,
    this.desktop = true,
  });

  final Widget child;
  final double maxScale;

  /// Whether the mouse zooms it on desktop too; when false, [child] is shown
  /// as it is there.
  final bool desktop;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  final _transform = TransformationController();
  Matrix4 _startMatrix = Matrix4.identity();
  Offset _startScene = Offset.zero;
  double _startScale = 1;
  Size _size = Size.zero;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _start(Offset focal) {
    _startMatrix = _transform.value.clone();
    _startScale = _startMatrix.getMaxScaleOnAxis();
    _startScene = _transform.toScene(focal);
  }

  void _update(Offset focal, double scale) {
    final s = (_startScale * scale).clamp(1.0, widget.maxScale);
    // The scene point first under the fingers stays under them.
    var dx = focal.dx - _startScene.dx * s, dy = focal.dy - _startScene.dy * s;
    dx = dx.clamp(math.min(0.0, _size.width * (1 - s)), 0.0);
    dy = dy.clamp(math.min(0.0, _size.height * (1 - s)), 0.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    if (!isTouchPlatform(context)) {
      return widget.desktop
          ? InteractiveViewer(maxScale: widget.maxScale, child: widget.child)
          : widget.child;
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        _size = constraints.biggest;
        return ClipRect(
          child: TwoFingerGestures(
            onStart: _start,
            onUpdate: _update,
            child: ValueListenableBuilder(
              valueListenable: _transform,
              builder: (context, matrix, child) =>
                  Transform(transform: matrix, child: child),
              child: widget.child,
            ),
          ),
        );
      },
    );
  }
}

/// What a card on [context]'s page remembers under [identifier], such as
/// the lap chosen. A list rebuilds a card it scrolled out of view, so a card
/// keeps its choices here rather than in its state alone.
T? readPageState<T>(BuildContext context, String identifier) {
  final value = PageStorage.maybeOf(context)
      ?.readState(context, identifier: identifier);
  return value is T ? value : null;
}

/// Remembers [value] for [readPageState].
void writePageState(BuildContext context, String identifier, Object? value) =>
    PageStorage.maybeOf(context)
        ?.writeState(context, value, identifier: identifier);

/// Keeps [child]'s state, such as a tab's scroll position, while it is not
/// shown.
class KeepAliveItem extends StatefulWidget {
  const KeepAliveItem({super.key, required this.child});

  final Widget child;

  @override
  State<KeepAliveItem> createState() => _KeepAliveItemState();
}

class _KeepAliveItemState extends State<KeepAliveItem>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Text shown in lap A's or B's colour stays readable in both themes: the
/// colour itself on a dark background, a darker shade of it on a light one.
/// Lines, dots and swatches keep the colour itself.
Color readableOn(BuildContext context, Color color) {
  if (Theme.of(context).brightness == Brightness.dark) return color;
  final hsl = HSLColor.fromColor(color);
  return hsl.withLightness(math.min(hsl.lightness, 0.36)).toColor();
}

/// One row of a [StickyTable].
final class StickyRow {
  const StickyRow({
    this.key,
    required this.first,
    required this.cells,
    this.onTap,
    this.color,
    this.semanticsLabel,
    this.selected = false,
  });

  final Key? key;
  final Widget first;
  final List<Widget> cells;
  final VoidCallback? onTap;
  final Color? color;

  /// The whole row as a screen reader says it, in place of its cells one
  /// by one, which say a column of numbers with no column names.
  final String? semanticsLabel;

  /// Whether the row is the one picked.
  final bool selected;
}

/// A table whose first column stays in place while the other columns scroll
/// sideways. Each row is one tap target across both parts, at least 48 dp
/// high; widths and heights grow with the text size. Cells fill their
/// place: see [TableCellText].
class StickyTable extends StatelessWidget {
  const StickyTable({
    super.key,
    required this.firstWidth,
    required this.cellWidths,
    required this.header,
    required this.rows,
    this.footer,
    this.rowHeight = 48,
    this.headerHeight = 40,
    this.scrollKey,
  });

  /// Widths at the normal text size.
  final double firstWidth;
  final List<double> cellWidths;
  final StickyRow header;
  final List<StickyRow> rows;
  final StickyRow? footer;
  final double rowHeight;
  final double headerHeight;

  /// The key of the sideways scroll view.
  final Key? scrollKey;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    double grow(double value) => math.max(value, scaler.scale(value));
    final first = grow(firstWidth);
    final widths = [for (final width in cellWidths) grow(width)];
    final line = Theme.of(context).colorScheme.outlineVariant;
    Widget divider(double width) => SizedBox(
      width: width,
      height: 1,
      child: ColoredBox(color: line),
    );
    final rest = widths.fold(0.0, (sum, width) => sum + width);

    Widget part(StickyRow row, double height, bool lead, {Key? key}) {
      final content = lead
          ? SizedBox(width: first, height: height, child: row.first)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < row.cells.length; ++i)
                  SizedBox(
                    width: i < widths.length ? widths[i] : widths.last,
                    height: height,
                    child: row.cells[i],
                  ),
              ],
            );
      final colored = row.color == null
          ? content
          : ColoredBox(color: row.color!, child: content);
      if (row.semanticsLabel case final label?) {
        final tappable = row.onTap == null
            ? colored
            : InkWell(
                onTap: row.onTap,
                excludeFromSemantics: true,
                child: colored,
              );
        // One node for the row, on its first part.
        return KeyedSubtree(
          key: key,
          child: lead
              ? Semantics(
                  container: true,
                  excludeSemantics: true,
                  button: row.onTap != null,
                  // Only a row that can be picked has a picked state.
                  selected: row.onTap == null ? null : row.selected,
                  label: label,
                  onTap: row.onTap,
                  child: tappable,
                )
              : ExcludeSemantics(child: tappable),
        );
      }
      if (row.onTap == null) return KeyedSubtree(key: key, child: colored);
      return InkWell(
        key: key,
        onTap: row.onTap,
        // One target for the row: the scrolling part is not announced
        // twice.
        excludeFromSemantics: !lead,
        child: colored,
      );
    }

    List<Widget> column(bool lead) => [
      part(header, grow(headerHeight), lead),
      divider(lead ? first : rest),
      for (final row in rows)
        part(row, grow(rowHeight), lead, key: lead ? row.key : null),
      if (footer case final footer?) ...[
        divider(lead ? first : rest),
        part(footer, grow(rowHeight), lead),
      ],
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: first,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: column(true),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            key: scrollKey,
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: column(false),
            ),
          ),
        ),
      ],
    );
  }
}

/// The text of a [StickyTable] cell: numbers right-aligned, labels left.
class TableCellText extends StatelessWidget {
  const TableCellText(
    this.text, {
    super.key,
    this.style,
    this.color,
    this.alignment = Alignment.centerRight,
    this.maxLines = 1,
  });

  final String text;
  final TextStyle? style;
  final Color? color;
  final Alignment alignment;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Container(
    color: color,
    alignment: alignment,
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: alignment.x > 0 ? TextAlign.end : TextAlign.start,
    ),
  );
}

/// [child], a tappable row, read by a screen reader as one button with its
/// text: what an InkWell alone does not say.
class ButtonRow extends StatelessWidget {
  const ButtonRow({
    super.key,
    required this.child,
    this.enabled = true,
    this.merge = true,
  });

  final Widget child;

  /// False when the row does nothing on a tap.
  final bool enabled;

  /// False when the row holds a button of its own, which must stay its own
  /// node with its own action.
  final bool merge;

  @override
  Widget build(BuildContext context) {
    // A row that does nothing on a tap is plain text, not a disabled button.
    if (!enabled) return child;
    final row = Semantics(container: !merge, button: true, child: child);
    return merge ? MergeSemantics(child: row) : row;
  }
}
