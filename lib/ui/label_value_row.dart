import 'package:flutter/material.dart';

/// A label on the left and a value at the right edge. The value keeps to
/// its own width, up to [valueShare] of the row, and wraps beyond it, so
/// large text neither runs off the screen nor squeezes the label to a
/// letter per line.
class LabelValueRow extends StatelessWidget {
  const LabelValueRow({
    super.key,
    required this.label,
    required this.value,
    this.valueShare = 0.6,
    this.crossAxisAlignment = CrossAxisAlignment.center,
  });

  final Widget label;
  final Widget value;
  final double valueShare;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Expanded(child: label),
        const SizedBox(width: 8),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: constraints.maxWidth * valueShare,
          ),
          child: value,
        ),
      ],
    ),
  );
}
