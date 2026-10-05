import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../app/app_navigation.dart';

/// Keeps the screen on while the Coach place is shown (with any page opened
/// from it) and [setting] is on, so the next-session card stays readable
/// between sessions without a touch. Only while the app is in the
/// foreground: hidden, minimised or in the background, the screen sleeps as
/// usual on every platform.
class KeepScreenOn extends StatefulWidget {
  const KeepScreenOn({
    super.key,
    required this.navigation,
    required this.setting,
    required this.child,
    this.toggle = _wakelock,
  });

  final AppNavigation navigation;
  final ValueListenable<bool> setting;
  final Widget child;

  /// Turns the screen lock off (true) or back on (false); the platform's
  /// wake lock by default.
  final Future<void> Function(bool on) toggle;

  static Future<void> _wakelock(bool on) => WakelockPlus.toggle(enable: on);

  @override
  State<KeepScreenOn> createState() => _KeepScreenOnState();
}

class _KeepScreenOnState extends State<KeepScreenOn> {
  bool _on = false;
  late final AppLifecycleListener _lifecycle;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    // Desktop wake locks outlive a hidden window, so the app lets go itself.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        _foreground = state == AppLifecycleState.resumed;
        _update();
      },
    );
    widget.navigation.addListener(_update);
    widget.setting.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(KeepScreenOn old) {
    super.didUpdateWidget(old);
    if (!identical(old.navigation, widget.navigation)) {
      old.navigation.removeListener(_update);
      widget.navigation.addListener(_update);
    }
    if (!identical(old.setting, widget.setting)) {
      old.setting.removeListener(_update);
      widget.setting.addListener(_update);
    }
    _update();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.navigation.removeListener(_update);
    widget.setting.removeListener(_update);
    if (_on) _set(false);
    super.dispose();
  }

  void _update() {
    final navigation = widget.navigation;
    final on =
        _foreground &&
        widget.setting.value &&
        navigation.attached &&
        navigation.dayAvailable &&
        navigation.section == AppSection.coach;
    if (on != _on) _set(on);
  }

  void _set(bool on) {
    _on = on;
    // A platform without a wake lock keeps its own screen timeout.
    widget.toggle(on).catchError((Object error) {
      debugPrint('Screen kept on: not available ($error)');
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
