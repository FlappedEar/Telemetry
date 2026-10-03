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

/// Makes [locale] the language of dates formatted without a
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

extension RouteReasonText on AppLocalizations {
  /// A reason from `telemetry_core` route detection in the app's language;
  /// a reason the app does not know yet is shown as written.
  String routeReason(String reason) => switch (reason) {
    'Not enough repeated, complete GPS laps to identify a route '
        'automatically.' =>
      routeReasonTooFewLaps,
    "Complete laps follow conflicting routes; review this recording's "
        'layout.' =>
      routeReasonConflictingLaps,
    'GPS route matches more than one incompatible group; review this '
        "recording's layout." =>
      routeReasonSeveralGroups,
    _ => reason,
  };
}

final _sessionName = RegExp(r'^Session (\d+)$');

extension SessionNameText on AppLocalizations {
  /// A run name from `telemetry_core` ("Session 2") in the app's language
  /// ("Sesja 2"); any other name is shown as written.
  String session(String name) {
    final number = _sessionName.firstMatch(name)?.group(1);
    return number == null ? name : sessionName(int.parse(number));
  }
}

extension FusionReasonText on AppLocalizations {
  /// Why a session's other recording was not combined with it, from the
  /// reason `telemetry_core` gives, in the app's language.
  String fusionReason(RunFusion fusion) => fusionReasonText(
    fusion.reason,
    unavailable: fusion.state == RunFusionState.unavailable,
  );

  /// [reason] as [fusionReason] says it: why the recording could not be
  /// used when [unavailable], else why it could not be aligned.
  String fusionReasonText(String reason, {required bool unavailable}) =>
      unavailable
      ? switch (reason) {
          'Recording not found.' => fusionReasonNotFound,
          'The file found is a different recording.' => fusionReasonDifferent,
          'Aligning failed.' => fusionReasonFailed,
          _ => fusionReasonUnreadable,
        }
      : switch (reason) {
          'noSpeed' => fusionReasonNoSpeed,
          'shortOverlap' => fusionReasonShortOverlap,
          'weakMatch' ||
          'tooFewWindows' ||
          'windowsDisagree' ||
          'implausibleDrift' ||
          'repeatedMatch' => fusionReasonAmbiguous,
          'declaredClockDisagrees' => fusionReasonClockDisagrees,
          _ => fusionReasonInsufficient,
        };
}
