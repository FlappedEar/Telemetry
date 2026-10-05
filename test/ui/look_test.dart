import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/app/app_navigation.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/settings_dialog.dart';
import 'package:telemetry/ui/keep_screen_on.dart';
import 'package:telemetry/ui/theme.dart';
import 'package:telemetry/units.dart';

/// WCAG contrast ratio of [a] on [b].
double _contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

void main() {
  group('sunlight look', () {
    final theme = FetTheme.sunlight();
    final scheme = theme.colorScheme;

    test('is light, with text that reads in the sun', () {
      expect(theme.brightness, Brightness.light);
      // WCAG AAA for body text, AA for coloured text and buttons.
      expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(7));
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh,
      ]) {
        expect(_contrast(scheme.onSurfaceVariant, surface), greaterThan(7));
        expect(_contrast(scheme.primary, surface), greaterThan(4.5));
      }
      expect(_contrast(scheme.onPrimary, scheme.primary), greaterThan(4.5));
      expect(_contrast(scheme.error, scheme.surface), greaterThan(4.5));
      final colors = theme.extension<FetColors>()!;
      for (final color in [colors.loss, colors.gain, colors.dayBest]) {
        expect(_contrast(color, scheme.surface), greaterThan(4.5));
      }
    });

    test('keeps the lap colours: A amber, B blue', () {
      final colors = theme.extension<FetColors>()!;
      expect(colors.you, const Color(0xfffcb203));
      expect(colors.reference, const Color(0xff3d8bff));
    });

    test('the dark look is unchanged by default', () {
      expect(appLookSetting.value, AppLook.dark);
      expect(FetTheme.of(AppLook.dark).brightness, Brightness.dark);
      expect(FetTheme.of(AppLook.dark).colorScheme.primary, FetTheme.amber);
    });
  });

  testWidgets('settings switch the look of the whole app at once', (
    tester,
  ) async {
    addTearDown(() => appLookSetting.value = AppLook.dark);
    await tester.pumpWidget(
      const TelemetryApp(home: Scaffold(body: SettingsDialog())),
    );
    BuildContext context() => tester.element(find.byType(SettingsDialog));
    expect(Theme.of(context()).brightness, Brightness.dark);
    await tester.tap(find.text('Sunlight'));
    await tester.pumpAndSettle();
    expect(appLookSetting.value, AppLook.sunlight);
    expect(Theme.of(context()).brightness, Brightness.light);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(Theme.of(context()).brightness, Brightness.dark);
  });

  testWidgets('settings turn keeping the screen on off and on', (tester) async {
    addTearDown(() => keepScreenOnSetting.value = true);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const TelemetryApp(home: Scaffold(body: SettingsDialog())),
    );
    expect(keepScreenOnSetting.value, isTrue);
    await tester.tap(find.byKey(const ValueKey('keepScreenOnSetting')));
    await tester.pumpAndSettle();
    expect(keepScreenOnSetting.value, isFalse);
  });

  group('keep the screen on', () {
    late AppNavigation navigation;
    late ValueNotifier<bool> setting;
    late List<bool> calls;
    final host = Object();

    setUp(() {
      navigation = AppNavigation();
      setting = ValueNotifier(true);
      calls = [];
    });

    Future<void> show(WidgetTester tester) => tester.pumpWidget(
      KeepScreenOn(
        navigation: navigation,
        setting: setting,
        toggle: (on) async => calls.add(on),
        child: const SizedBox(),
      ),
    );

    Future<void> go(WidgetTester tester, AppSection section) async {
      navigation.update(
        section: section,
        dayAvailable: true,
        libraryAvailable: false,
      );
      await tester.pump();
    }

    testWidgets('only while the Coach place is shown', (tester) async {
      navigation.attach(host, (_) {});
      await show(tester);
      await tester.pump();
      expect(calls, isEmpty);
      await go(tester, AppSection.coach);
      expect(calls, [true]);
      await go(tester, AppSection.day);
      expect(calls, [true, false]);
      await go(tester, AppSection.coach);
      // The day closes: the Coach place goes with it.
      navigation.detach(host);
      await tester.pump();
      expect(calls, [true, false, true, false]);
    });

    testWidgets('not when the setting is off', (tester) async {
      navigation.attach(host, (_) {});
      await show(tester);
      await go(tester, AppSection.coach);
      expect(calls, [true]);
      setting.value = false;
      await tester.pump();
      expect(calls, [true, false]);
      await go(tester, AppSection.day);
      await go(tester, AppSection.coach);
      expect(calls, [true, false]);
      setting.value = true;
      await tester.pump();
      expect(calls, [true, false, true]);
    });

    testWidgets('lets the screen sleep when the app is taken down', (
      tester,
    ) async {
      navigation.attach(host, (_) {});
      await show(tester);
      await go(tester, AppSection.coach);
      await tester.pumpWidget(const SizedBox());
      expect(calls, [true, false]);
    });

    testWidgets('lets the screen sleep while the app is not in front', (
      tester,
    ) async {
      navigation.attach(host, (_) {});
      await show(tester);
      await go(tester, AppSection.coach);
      expect(calls, [true]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(calls, [true, false]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, [true, false, true]);
    });

    testWidgets('a platform without a wake lock is not an error', (
      tester,
    ) async {
      navigation.attach(host, (_) {});
      await tester.pumpWidget(
        KeepScreenOn(
          navigation: navigation,
          setting: setting,
          toggle: (on) async => throw UnsupportedError('no wake lock'),
          child: const SizedBox(),
        ),
      );
      await go(tester, AppSection.coach);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
