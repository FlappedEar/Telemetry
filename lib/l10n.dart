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

extension LapNameText on AppLocalizations {
  /// A lap's name in the app's language, "Sesja 3 · OKR. 2", instead of
  /// `DayLapRow.displayName` ("Session 3 · LAP 2").
  String lap(DayLapRow row) {
    final run = session(row.runName);
    return switch (row.type) {
      LapSectionType.lap => lapName(run, row.lapNumber),
      LapSectionType.outLap => outLapName(run),
      LapSectionType.inLap => inLapName(run),
      LapSectionType.unknown => unknownLapName(run),
    };
  }
}

extension LapIssueText on AppLocalizations {
  /// Why a lap is not ranked, in the app's language.
  String lapIssue(LapIssue issue) => switch (issue) {
    LapIssue.layoutUnresolved => lapIssueLayoutUnresolved,
    LapIssue.directionUnresolved => lapIssueDirectionUnresolved,
    LapIssue.timingGateUnresolved => lapIssueTimingGateUnresolved,
    LapIssue.changedLayout => lapIssueChangedLayout,
    LapIssue.oppositeDirection => lapIssueOppositeDirection,
    LapIssue.changedTimingGate => lapIssueChangedTimingGate,
    LapIssue.incompleteGps => lapIssueIncompleteGps,
    LapIssue.invalidGps => lapIssueInvalidGps,
    LapIssue.userExclusion => lapIssueUserExclusion,
    LapIssue.notTimedLap => lapIssueNotTimedLap,
    LapIssue.staleSource => lapIssueStaleSource,
    LapIssue.ineligibleLap => lapIssueIneligibleLap,
    LapIssue.differentRecordedRoute => lapIssueDifferentRoute,
  };
}

extension DayNoteText on AppLocalizations {
  /// A note of the day's analysis (`DayMessage.text`) in the app's
  /// language; a note the app does not know, such as an error, is shown as
  /// written.
  String dayNote(String text) => switch (text) {
    'Recording date and time unavailable; listed after the dated '
        'recordings in import order.' =>
      noteUndated,
    'No reliable start/finish passes; lap type is unknown.' => noteNoPasses,
    _ => routeReason(text),
  };
}
