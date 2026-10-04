import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The widest a page of text and cards gets: lines stay readable on a large
/// screen.
const double readableWidth = 840;

/// Padding that centres content at most [maxWidth] wide in [width], with at
/// least 16 on each side. Padding rather than a narrower box, so the mouse
/// wheel still scrolls over the margins.
EdgeInsets readablePadding(double width, {double maxWidth = readableWidth}) =>
    EdgeInsets.symmetric(
      horizontal: math.max(16, (width - maxWidth) / 2),
      vertical: 16,
    );

/// A page's scrolling list, at most [maxWidth] wide and centred.
class ReadableListView extends StatelessWidget {
  const ReadableListView({
    super.key,
    required this.children,
    this.maxWidth = readableWidth,
  });

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: readablePadding(constraints.maxWidth, maxWidth: maxWidth),
      children: children,
    ),
  );
}
