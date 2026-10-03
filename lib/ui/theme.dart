import 'package:flutter/material.dart';

/// The app's look: white and high-contrast in light mode, for reading a
/// phone in sunlight on the pit lane, with one orange accent. Dark mode
/// follows the system.
///
/// Screens use [ColorScheme] roles and [TextTheme] styles, plus
/// [FetColors] for the timing colours, so the look changes here only.
abstract final class FetTheme {
  static const sans = 'IBMPlexSans';
  static const mono = 'IBMPlexMono';

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final light = brightness == Brightness.light;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: const Color(0xffd9480f),
          brightness: brightness,
          dynamicSchemeVariant: DynamicSchemeVariant.neutral,
        ).copyWith(
          primary: light ? const Color(0xffc2410c) : const Color(0xffff7a3d),
          onPrimary: light ? Colors.white : const Color(0xff1a0a00),
          primaryContainer: light
              ? const Color(0xffffe8dc)
              : const Color(0xff4a1d08),
          onPrimaryContainer: light
              ? const Color(0xff3d1300)
              : const Color(0xffffdccb),
          secondary: light ? const Color(0xff121212) : const Color(0xfff2f2ee),
          onSecondary: light ? Colors.white : const Color(0xff121212),
          tertiary: light ? const Color(0xff6d35d6) : const Color(0xffb794ff),
          onTertiary: light ? Colors.white : const Color(0xff1d0a40),
          surface: light ? Colors.white : const Color(0xff111110),
          onSurface: light ? const Color(0xff121212) : const Color(0xfff2f2ee),
          onSurfaceVariant: light
              ? const Color(0xff5c5c57)
              : const Color(0xffb5b5ae),
          surfaceContainerLowest: light
              ? Colors.white
              : const Color(0xff0b0b0a),
          surfaceContainerLow: light
              ? const Color(0xfff7f7f5)
              : const Color(0xff1a1a18),
          surfaceContainer: light
              ? const Color(0xfff3f3f0)
              : const Color(0xff20201e),
          surfaceContainerHigh: light
              ? const Color(0xffecece8)
              : const Color(0xff272725),
          surfaceContainerHighest: light
              ? const Color(0xffe4e4df)
              : const Color(0xff2e2e2b),
          outline: light ? const Color(0xff8a8a84) : const Color(0xff8e8e87),
          outlineVariant: light
              ? const Color(0xffe2e2dd)
              : const Color(0xff2e2e2b),
          surfaceTint: Colors.transparent,
        );
    final text = _text(scheme);
    const corner = BorderRadius.all(Radius.circular(4));
    const buttonShape = RoundedRectangleBorder(borderRadius: corner);
    const buttonSize = Size(64, 44);
    return ThemeData(
      colorScheme: scheme,
      fontFamily: sans,
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      extensions: [light ? FetColors.light : FetColors.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: text.titleLarge,
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: corner,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: buttonShape,
          minimumSize: buttonSize,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: buttonShape,
          minimumSize: buttonSize,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: buttonShape,
          minimumSize: buttonSize,
          textStyle: text.labelLarge,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(shape: buttonShape),
      ),
      chipTheme: ChipThemeData(
        shape: buttonShape,
        side: BorderSide(color: scheme.outlineVariant),
        labelStyle: text.labelLarge,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onSurface,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: corner,
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: buttonShape,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.onSurface,
        thumbColor: scheme.onSurface,
        inactiveTrackColor: scheme.outlineVariant,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: corner),
      ),
    );
  }

  /// Plex Sans has tabular digits by default, so times line up in columns.
  /// Display styles, used for lap times, are set in Plex Mono.
  static TextTheme _text(ColorScheme scheme) {
    final base = Typography.material2021().englishLike.apply(
      fontFamily: sans,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    TextStyle? timing(TextStyle? style) => style?.copyWith(
      fontFamily: mono,
      fontFamilyFallback: const [sans],
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
    );
    TextStyle? strong(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w600);
    return base.copyWith(
      displayLarge: timing(base.displayLarge),
      displayMedium: timing(base.displayMedium),
      displaySmall: timing(base.displaySmall),
      headlineSmall: strong(base.headlineSmall),
      titleLarge: strong(base.titleLarge),
      titleMedium: strong(base.titleMedium),
      titleSmall: strong(base.titleSmall),
      labelLarge: strong(base.labelLarge),
    );
  }
}

/// Timing colours, by the motorsport convention: purple for the fastest of
/// the day, green for the fastest of a session, orange for time lost.
@immutable
class FetColors extends ThemeExtension<FetColors> {
  const FetColors({
    required this.dayBest,
    required this.sessionBest,
    required this.loss,
    required this.onTiming,
  });

  final Color dayBest;
  final Color sessionBest;
  final Color loss;

  /// Text on [dayBest], [sessionBest] and [loss].
  final Color onTiming;

  static const light = FetColors(
    dayBest: Color(0xff6d35d6),
    sessionBest: Color(0xff0a7d45),
    loss: Color(0xffc2410c),
    onTiming: Colors.white,
  );

  static const dark = FetColors(
    dayBest: Color(0xff8f5cf0),
    sessionBest: Color(0xff1f9d5c),
    loss: Color(0xffe8590c),
    onTiming: Colors.white,
  );

  /// The theme's timing colours; [light] outside a themed app.
  static FetColors of(BuildContext context) =>
      Theme.of(context).extension<FetColors>() ?? light;

  @override
  FetColors copyWith({
    Color? dayBest,
    Color? sessionBest,
    Color? loss,
    Color? onTiming,
  }) => FetColors(
    dayBest: dayBest ?? this.dayBest,
    sessionBest: sessionBest ?? this.sessionBest,
    loss: loss ?? this.loss,
    onTiming: onTiming ?? this.onTiming,
  );

  @override
  FetColors lerp(FetColors? other, double t) => other == null
      ? this
      : FetColors(
          dayBest: Color.lerp(dayBest, other.dayBest, t)!,
          sessionBest: Color.lerp(sessionBest, other.sessionBest, t)!,
          loss: Color.lerp(loss, other.loss, t)!,
          onTiming: Color.lerp(onTiming, other.onTiming, t)!,
        );
}
