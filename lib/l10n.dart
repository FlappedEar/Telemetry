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

/// The texts in the device's language, for the few places without a
/// [BuildContext], such as the system file pickers.
AppLocalizations deviceL10n() => lookupAppLocalizations(
  resolveAppLocale(WidgetsBinding.instance.platformDispatcher.locales),
);

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

  /// Why adding recordings to the day failed (`DayAddition.error`); an
  /// error the app does not know is shown as written.
  String additionError(String error) => switch (error) {
    'Adding was cancelled.' => addingCancelled,
    'The day was closed.' => dayClosed,
    _ when error.startsWith('Nothing was added: ') => nothingAddedError(
      error.substring('Nothing was added: '.length),
    ),
    _ => error,
  };

  /// Why background work failed (`BackgroundTaskFailed.message`); a
  /// message the app does not know, such as an error, is shown as written.
  String taskFailure(String message) => switch (message) {
    'The work stopped.' => taskStopped,
    'The work stopped unexpectedly.' => taskStoppedUnexpectedly,
    _ => message,
  };

  /// Why a session of a saved day could not be opened
  /// (`MissingRecording.reason`); any other reason, such as a read error,
  /// is shown as written.
  String missingReason(String reason) => switch (reason) {
    'Recording not found.' => missingRecordingNotFound,
    'The same recording as another session of this day.' =>
      missingRecordingDuplicate,
    'The file found is a different recording.' => missingRecordingDifferent,
    _ => reason,
  };
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
