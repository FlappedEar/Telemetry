import 'package:flutter/material.dart';

import 'theme.dart';

/// A timing-screen bar: a small label and a title on the left, a time in
/// large monospaced digits on the right, on a lap colour; tappable when
/// [onTap] is given.
class HeadlineBar extends StatelessWidget {
  const HeadlineBar({
    super.key,
    required this.label,
    required this.title,
    required this.time,
    required this.color,
    required this.onColor,
    this.onTap,
  });

  final String label;
  final String title;
  final String time;
  final Color color;
  final Color onColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Material(
      color: color,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: text.labelSmall?.copyWith(
                            color: onColor,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          title,
                          style: text.titleSmall?.copyWith(color: onColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // At its full size, flush right, up to half the bar; with
                  // large text on a narrow phone it shrinks rather than
                  // squeeze the name.
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth / 2,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        time,
                        style: text.headlineSmall?.copyWith(
                          fontFamily: FetTheme.mono,
                          fontWeight: FontWeight.w700,
                          color: onColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
