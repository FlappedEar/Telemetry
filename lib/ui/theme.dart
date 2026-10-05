import 'package:flutter/material.dart';

/// How the app looks, chosen in settings: [dark] by default, [sunlight] for
/// reading outdoors.
enum AppLook { dark, sunlight }

/// The app's look: a dark track-day dashboard of charcoal panels, with the
/// FlappedEar amber for your lap and blue for the reference lap; or, for
/// reading in the sun at the track, [sunlight]: black on white with the same
/// lap colours.
///
/// Screens use [ColorScheme] roles and [TextTheme] styles, plus
/// [FetColors] for the lap and timing colours, so the look changes here only.
abstract final class FetTheme {
  static const sans = 'Sora';
  static const mono = 'JetBrainsMono';

  /// FlappedEar amber, from the brand logo.
  static const amber = Color(0xfffcb203);

  /// The theme [look] chooses.
  static ThemeData of(AppLook look) => switch (look) {
    AppLook.dark => dark(),
    AppLook.sunlight => sunlight(),
  };

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: amber,
      onPrimary: Color(0xff1a1200),
      primaryContainer: Color(0xff3a2c00),
      onPrimaryContainer: Color(0xffffe08a),
      secondary: Color(0xff3d8bff),
      onSecondary: Color(0xff04122b),
      secondaryContainer: Color(0xff0f2a52),
      onSecondaryContainer: Color(0xffd6e6ff),
      tertiary: Color(0xff53bc94),
      onTertiary: Color(0xff00281a),
      error: Color(0xffff6b5c),
      onError: Color(0xff2b0500),
      errorContainer: Color(0xff4d1610),
      onErrorContainer: Color(0xffffdad5),
      surface: Color(0xff111214),
      onSurface: Color(0xfff2f2f2),
      onSurfaceVariant: Color(0xffa3a6ad),
      surfaceContainerLowest: Color(0xff0b0c0e),
      surfaceContainerLow: Color(0xff16171a),
      surfaceContainer: Color(0xff1b1c1f),
      surfaceContainerHigh: Color(0xff24262a),
      surfaceContainerHighest: Color(0xff2a2c31),
      outline: Color(0xff5d6068),
      outlineVariant: Color(0xff2e3035),
      inverseSurface: Color(0xfff2f2f2),
      onInverseSurface: Color(0xff111214),
      inversePrimary: Color(0xff7a5600),
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    return _build(scheme, FetColors.dark);
  }

  /// High contrast for direct sunlight: black text on white, darker panel
  /// edges, and a deep amber for text, buttons and tabs. Lines keep the lap
  /// colours; `readableOn` darkens them where they colour text.
  static ThemeData sunlight() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xff7a5100),
      onPrimary: Colors.white,
      primaryContainer: Color(0xffffe08a),
      onPrimaryContainer: Color(0xff2b1f00),
      secondary: Color(0xff1d5fcc),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xffd6e6ff),
      onSecondaryContainer: Color(0xff04122b),
      tertiary: Color(0xff17704f),
      onTertiary: Colors.white,
      error: Color(0xffb3261e),
      onError: Colors.white,
      errorContainer: Color(0xffffdad5),
      onErrorContainer: Color(0xff410002),
      surface: Colors.white,
      onSurface: Colors.black,
      onSurfaceVariant: Color(0xff33363b),
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Color(0xfff4f5f6),
      surfaceContainer: Color(0xffeceef0),
      surfaceContainerHigh: Color(0xffdfe1e5),
      surfaceContainerHighest: Color(0xffd3d6da),
      outline: Color(0xff4a4d53),
      outlineVariant: Color(0xffb5b9bf),
      inverseSurface: Color(0xff1b1c1f),
      onInverseSurface: Color(0xfff2f2f2),
      inversePrimary: amber,
      surfaceTint: Colors.transparent,
      shadow: Colors.black,
      scrim: Colors.black,
    );
    return _build(scheme, FetColors.sunlight);
  }

  static ThemeData _build(ColorScheme scheme, FetColors colors) {
    final text = _text(scheme);
    const corner = BorderRadius.all(Radius.circular(3));
    const shape = RoundedRectangleBorder(borderRadius: corner);
    const buttonSize = Size(64, 44);
    return ThemeData(
      brightness: scheme.brightness,
      colorScheme: scheme,
      fontFamily: sans,
      fontFamilyFallback: const [mono],
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      extensions: [colors],
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleTextStyle: text.titleLarge,
      ),
      // Panels: flat charcoal, edge to edge, no outline.
      cardTheme: CardThemeData(
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 3),
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: corner),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        space: 1,
        thickness: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: shape,
          minimumSize: buttonSize,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: shape,
          minimumSize: buttonSize,
          foregroundColor: scheme.onSurface,
          backgroundColor: scheme.surfaceContainerHigh,
          side: BorderSide.none,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: shape,
          minimumSize: buttonSize,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: scheme.onSurface,
          minimumSize: const Size(44, 44),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          shape: shape,
          backgroundColor: scheme.surfaceContainerHigh,
          selectedBackgroundColor: scheme.primary,
          selectedForegroundColor: scheme.onPrimary,
          side: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: shape,
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary,
        side: BorderSide.none,
        labelStyle: text.labelLarge,
      ),
      // Tabs: the selected one filled with the primary colour (amber, deep
      // amber in sunlight), as on a timing screen.
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        indicator: BoxDecoration(color: scheme.primary, borderRadius: corner),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.primary
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.primary,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: scheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: corner),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.surfaceContainerHighest,
        contentTextStyle: text.bodyMedium,
        shape: shape,
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
      checkboxTheme: CheckboxThemeData(
        side: BorderSide(color: scheme.outline, width: 1.5),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: corner),
      ),
    );
  }

  /// Sora with tabular digits, so times line up in columns. Display styles,
  /// used for lap times, are set in JetBrains Mono.
  static TextTheme _text(ColorScheme scheme) {
    const tabular = [FontFeature.tabularFigures()];
    final base = Typography.material2021().englishLike
        .apply(
          fontFamily: sans,
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .apply(fontFamilyFallback: const [mono]);
    TextStyle? timing(TextStyle? style) => style?.copyWith(
      fontFamily: mono,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    );
    TextStyle? strong(TextStyle? style) =>
        style?.copyWith(fontWeight: FontWeight.w600);
    TextStyle? numbers(TextStyle? style) =>
        style?.copyWith(fontFeatures: tabular);
    final themed = base.copyWith(
      displayLarge: timing(base.displayLarge),
      displayMedium: timing(base.displayMedium),
      displaySmall: timing(base.displaySmall),
      headlineSmall: strong(base.headlineSmall),
      titleLarge: strong(base.titleLarge),
      titleMedium: strong(base.titleMedium),
      titleSmall: strong(base.titleSmall),
      labelLarge: strong(base.labelLarge),
    );
    return themed.copyWith(
      headlineLarge: numbers(themed.headlineLarge),
      headlineMedium: numbers(themed.headlineMedium),
      headlineSmall: numbers(themed.headlineSmall),
      titleLarge: numbers(themed.titleLarge),
      titleMedium: numbers(themed.titleMedium),
      titleSmall: numbers(themed.titleSmall),
      bodyLarge: numbers(themed.bodyLarge),
      bodyMedium: numbers(themed.bodyMedium),
      bodySmall: numbers(themed.bodySmall),
      labelLarge: numbers(themed.labelLarge),
      labelMedium: numbers(themed.labelMedium),
      labelSmall: numbers(themed.labelSmall),
    );
  }
}

/// Lap and timing colours: your lap FlappedEar amber and the reference lap
/// blue, time lost red and time gained green, and purple for the fastest of
/// the day, as on a timing screen. Maps and charts adopt them screen by
/// screen.
@immutable
class FetColors extends ThemeExtension<FetColors> {
  const FetColors({
    required this.you,
    required this.reference,
    required this.loss,
    required this.gain,
    required this.dayBest,
    required this.onLap,
  });

  final Color you;
  final Color reference;
  final Color loss;
  final Color gain;
  final Color dayBest;

  /// Text on [you] and [reference].
  final Color onLap;

  static const dark = FetColors(
    you: FetTheme.amber,
    reference: Color(0xff3d8bff),
    loss: Color(0xffff6b5c),
    gain: Color(0xff53bc94),
    dayBest: Color(0xffb37bff),
    onLap: Color(0xff111214),
  );

  /// The lap colours stay; loss, gain and the day's best are darker, so
  /// they read on white.
  static const sunlight = FetColors(
    you: FetTheme.amber,
    reference: Color(0xff3d8bff),
    loss: Color(0xffc62828),
    gain: Color(0xff17704f),
    dayBest: Color(0xff7b3fd1),
    onLap: Color(0xff111214),
  );

  /// The theme's colours; [dark] outside a themed app.
  static FetColors of(BuildContext context) =>
      Theme.of(context).extension<FetColors>() ?? dark;

  @override
  FetColors copyWith({
    Color? you,
    Color? reference,
    Color? loss,
    Color? gain,
    Color? dayBest,
    Color? onLap,
  }) => FetColors(
    you: you ?? this.you,
    reference: reference ?? this.reference,
    loss: loss ?? this.loss,
    gain: gain ?? this.gain,
    dayBest: dayBest ?? this.dayBest,
    onLap: onLap ?? this.onLap,
  );

  @override
  FetColors lerp(FetColors? other, double t) => other == null
      ? this
      : FetColors(
          you: Color.lerp(you, other.you, t)!,
          reference: Color.lerp(reference, other.reference, t)!,
          loss: Color.lerp(loss, other.loss, t)!,
          gain: Color.lerp(gain, other.gain, t)!,
          dayBest: Color.lerp(dayBest, other.dayBest, t)!,
          onLap: Color.lerp(onLap, other.onLap, t)!,
        );
}
