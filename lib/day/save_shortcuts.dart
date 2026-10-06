import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// [child] where Ctrl+S (Cmd+S on a Mac) calls [onSave]: the day page and
/// the lap and Corner Analyzer pages opened from it, at any depth.
Widget saveShortcuts(VoidCallback? onSave, Widget child) {
  if (onSave == null) return child;
  return CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
    },
    child: Focus(autofocus: true, child: child),
  );
}
