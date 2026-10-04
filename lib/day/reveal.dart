import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/widgets.dart';

/// Scrolls [context]'s widget into view at the top of its scrollable, over
/// [duration], then once more without animating when the scroll ended where
/// it was going: what is above the widget can still settle while it scrolls
/// and move its top. When the person took the scroll over (a drag, a wheel)
/// or something else moved it, the scroll ended elsewhere and is left there.
/// [current] reads the widget's context again after the animation.
Future<void> revealSettled(
  BuildContext context, {
  required BuildContext? Function() current,
  Duration duration = const Duration(milliseconds: 300),
}) async {
  final position = Scrollable.maybeOf(context)?.position;
  final object = context.findRenderObject();
  final viewport = object == null
      ? null
      : RenderAbstractViewport.maybeOf(object);
  final target =
      position == null || viewport == null || !position.hasContentDimensions
      ? null
      : viewport
            .getOffsetToReveal(object!, 0)
            .offset
            .clamp(position.minScrollExtent, position.maxScrollExtent);
  await Scrollable.ensureVisible(context, duration: duration);
  final settled = current();
  if (target == null ||
      settled == null ||
      !settled.mounted ||
      position == null ||
      !position.hasPixels ||
      (position.pixels - target).abs() > 1.0) {
    return;
  }
  await Scrollable.ensureVisible(settled);
}
