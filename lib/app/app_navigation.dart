import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';

/// The app's places, the same on every screen: a bottom bar on a phone, a
/// side rail on a wide screen.
enum AppSection { home, library, day }

/// Which place is shown and how to go to another; the start page drives it
/// (see `DayImportPage`), and [AppFrame] draws it around every page.
final class AppNavigation extends ChangeNotifier {
  AppSection _section = AppSection.home;
  bool _dayAvailable = false;
  bool _libraryAvailable = false;
  ValueChanged<AppSection>? _select;
  Object? _host;

  /// Tracks the page on top, so a tap is ignored while a dialog is open.
  final observer = _TopRouteObserver();

  AppSection get section => _section;

  /// Whether a day is open, so the Day place can be shown.
  bool get dayAvailable => _dayAvailable;

  /// Whether there is a driver profile library to show.
  bool get libraryAvailable => _libraryAvailable;

  /// Whether a page drives the places; without one no bar is drawn.
  bool get attached => _host != null;

  /// Makes [host] the page that answers taps on the places.
  void attach(Object host, ValueChanged<AppSection> select) {
    observer.reset();
    _host = host;
    _select = select;
    // Attached while the host is first built: the frame redraws after it.
    scheduleMicrotask(notifyListeners);
  }

  void detach(Object host) {
    if (!identical(_host, host)) return;
    _host = null;
    _select = null;
    _section = AppSection.home;
    _dayAvailable = false;
    _libraryAvailable = false;
    // Detached while the tree is taken down.
    scheduleMicrotask(notifyListeners);
  }

  /// Called by the host whenever what is shown changes.
  void update({
    required AppSection section,
    required bool dayAvailable,
    required bool libraryAvailable,
  }) {
    if (section == _section &&
        dayAvailable == _dayAvailable &&
        libraryAvailable == _libraryAvailable) {
      return;
    }
    _section = section;
    _dayAvailable = dayAvailable;
    _libraryAvailable = libraryAvailable;
    notifyListeners();
  }

  /// A tap on [section]; ignored while a dialog or menu is open over the
  /// page, which it would otherwise close unanswered.
  void select(AppSection section) {
    if (observer.popupOnTop) return;
    _select?.call(section);
  }
}

final class _TopRouteObserver extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  bool get popupOnTop => _routes.isNotEmpty && _routes.last is PopupRoute;

  /// Forgets the routes of a navigator gone before its pages were popped.
  void reset() => _routes.clear();

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (newRoute == null) return;
    if (index < 0) {
      _routes.add(newRoute);
    } else {
      _routes[index] = newRoute;
    }
  }
}

/// The app's one navigation.
final appNavigation = AppNavigation();

/// The app's navigator, which the places pop and push on.
final appNavigatorKey = GlobalKey<NavigatorState>();

/// Draws the places around [child], the app's pages: a bottom bar below
/// [wideWidth], a side rail from it. Without a host (a page shown by
/// itself, as in tests) it draws nothing.
class AppFrame extends StatelessWidget {
  const AppFrame({super.key, required this.navigation, required this.child});

  /// From this width the places are a side rail.
  static const wideWidth = 900.0;

  final AppNavigation navigation;
  final Widget child;

  /// The width the places are drawn for (the window's); null for a page
  /// shown without them.
  static double? widthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_FrameWidth>()?.width;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: navigation,
    child: child,
    builder: (context, child) {
      if (!navigation.attached) return child!;
      final l10n = context.l10n;
      final places = [
        (AppSection.home, Icons.home_outlined, Icons.home, l10n.navHome, true),
        if (navigation.libraryAvailable)
          (
            AppSection.library,
            Icons.collections_bookmark_outlined,
            Icons.collections_bookmark,
            l10n.navLibrary,
            true,
          ),
        (
          AppSection.day,
          Icons.flag_outlined,
          Icons.flag,
          l10n.navDay,
          navigation.dayAvailable,
        ),
      ];
      final selected = places.indexWhere((p) => p.$1 == navigation.section);
      void go(int index) => navigation.select(places[index].$1);
      return LayoutBuilder(
        builder: (context, constraints) {
          child = _FrameWidth(width: constraints.maxWidth, child: child!);
          if (constraints.maxWidth >= wideWidth) {
            return Row(
              children: [
                FocusTraversalGroup(
                  child: NavigationRail(
                    key: const ValueKey('appPlaces'),
                    selectedIndex: selected < 0 ? null : selected,
                    labelType: NavigationRailLabelType.all,
                    onDestinationSelected: go,
                    destinations: [
                      for (final (section, icon, selectedIcon, label, enabled)
                          in places)
                        NavigationRailDestination(
                          icon: Icon(
                            icon,
                            key: ValueKey('place-${section.name}'),
                          ),
                          selectedIcon: Icon(
                            selectedIcon,
                            key: ValueKey('place-${section.name}'),
                          ),
                          label: Text(label),
                          disabled: !enabled,
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: child!),
              ],
            );
          }
          return Column(
            children: [
              // The bar takes the bottom inset; the pages above it do not.
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: child!,
                ),
              ),
              NavigationBar(
                key: const ValueKey('appPlaces'),
                selectedIndex: selected < 0 ? 0 : selected,
                onDestinationSelected: go,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  for (final (section, icon, selectedIcon, label, enabled)
                      in places)
                    NavigationDestination(
                      icon: Icon(icon, key: ValueKey('place-${section.name}')),
                      selectedIcon: Icon(
                        selectedIcon,
                        key: ValueKey('place-${section.name}'),
                      ),
                      label: label,
                      enabled: enabled,
                      // Touch first: no tooltips (and no overlay up here).
                      tooltip: '',
                    ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

/// The width the places were laid out for, so a page decides its own
/// layout with them.
class _FrameWidth extends InheritedWidget {
  const _FrameWidth({required this.width, required super.child});

  final double width;

  @override
  bool updateShouldNotify(_FrameWidth old) => width != old.width;
}

/// The app's logo beside its name, for the start page's title.
class AppTitle extends StatelessWidget {
  const AppTitle({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      // The ears and the two laps; the name beside it is the label.
      ExcludeSemantics(
        child: Image.asset(
          'assets/branding/splash-logo.png',
          key: const ValueKey('appLogo'),
          width: 48,
          height: 48,
          errorBuilder: (_, _, _) => const SizedBox.square(dimension: 48),
        ),
      ),
      const SizedBox(width: 4),
      // A phone's bar keeps the whole name, smaller if need be.
      Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(context.l10n.appTitle),
        ),
      ),
    ],
  );
}
