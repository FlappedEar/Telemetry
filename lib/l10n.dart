import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'l10n/app_localizations.dart';

export 'l10n/app_localizations.dart';

/// The languages the app speaks, English first: it is the language used
/// when the device prefers none of them.
const supportedLocales = [Locale('en'), Locale('pl')];

/// The language the app uses for a device that prefers [preferred], in its
/// order of preference: the first one the app speaks, else English. Only
/// the language counts; en-GB and pl-PL get English and Polish.
Locale resolveAppLocale(List<Locale>? preferred) {
  for (final locale in preferred ?? const <Locale>[]) {
    for (final supported in supportedLocales) {
      if (supported.languageCode == locale.languageCode) return supported;
    }
  }
  return supportedLocales.first;
}

/// Makes [locale] the language of numbers and dates formatted without a
/// [BuildContext] (format.dart). Called by the app when its language is
/// chosen.
void useFormattingLocale(Locale locale) {
  Intl.defaultLocale = locale.toLanguageTag();
}

extension AppStrings on BuildContext {
  /// The app's text in the current language.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension TrackDirectionText on AppLocalizations {
  /// [direction] as a label: "Clockwise".
  String direction(TrackDirection direction) => switch (direction) {
    TrackDirection.clockwise => directionClockwise,
    TrackDirection.counterclockwise => directionCounterclockwise,
  };

  /// [direction] inside a sentence: "clockwise".
  String directionInSentence(TrackDirection direction) => switch (direction) {
    TrackDirection.clockwise => directionClockwiseInSentence,
    TrackDirection.counterclockwise => directionCounterclockwiseInSentence,
  };
}
