import 'package:flutter/material.dart';

/// The app's look: a dark track-day dashboard of charcoal panels, with the
/// FlappedEar amber for your lap and blue for the reference lap.
///
/// Screens use [ColorScheme] roles and [TextTheme] styles, plus
/// [FetColors] for the lap and timing colours, so the look changes here only.
abstract final class FetTheme {
  static const sans = 'Sora';
  static const mono = 'JetBrainsMono';

  /// FlappedEar amber, from the brand logo.
  static const amber = Color(0xfffcb203);

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
    final text = _text(scheme);
    const corner = BorderRadius.all(Radius.circular(3));
    const shape = RoundedRectangleBorder(borderRadius: corner);
    const buttonSize = Size(64, 44);
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: scheme,
      fontFamily: sans,
      fontFamilyFallback: const [mono],
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      canvasColor: scheme.surface,
      extensions: const [FetColors.dark],
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
      // Tabs: filled amber for the selected one, as on a timing screen.
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.onPrimary,
        unselectedLabelColor: scheme.onSurfaceVariant,
        labelStyle: text.titleSmall,
        unselectedLabelStyle: text.titleSmall,
        indicator: const BoxDecoration(color: amber, borderRadius: corner),
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
                ? amber
                : scheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected)
                ? amber
                : scheme.onSurfaceVariant,
          ),
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

/// Lap and timing colours. Your lap is FlappedEar amber and the reference
/// lap blue on every map and chart; time lost is red and time gained green;
/// purple marks the fastest of the day, as on a timing screen.
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
