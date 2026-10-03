// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'FlappedEar Telemetry';

  @override
  String get directionClockwise => 'Clockwise';

  @override
  String get directionCounterclockwise => 'Counterclockwise';

  @override
  String get directionClockwiseInSentence => 'clockwise';

  @override
  String get directionCounterclockwiseInSentence => 'counterclockwise';

  @override
  String trackDialogTitle(String session) {
    return 'Circuit of $session';
  }

  @override
  String trackDialogNoRoute(String reason) {
    return 'No route was detected: $reason';
  }

  @override
  String get trackDialogNoLaps => 'no laps';

  @override
  String trackDialogDetectedRoute(String length, String direction) {
    return 'Detected route: $length m, $direction (inferred from GPS).';
  }

  @override
  String trackDialogWholeTrace(String session) {
    return 'Whole GPS trace of $session';
  }

  @override
  String get trackDialogLayoutName => 'Layout name';

  @override
  String get trackDialogLayoutHint => 'Jastrząb full circuit';

  @override
  String trackDialogSameRoute(String sessions) {
    return 'Also for the sessions on the same route: $sessions';
  }

  @override
  String get trackDialogUseDetected => 'Use the detected route';

  @override
  String get routeReasonTooFewLaps =>
      'Not enough repeated, complete GPS laps to identify a route automatically.';

  @override
  String get routeReasonConflictingLaps =>
      'Complete laps follow conflicting routes; review this recording\'s layout.';

  @override
  String get routeReasonSeveralGroups =>
      'GPS route matches more than one incompatible group; review this recording\'s layout.';

  @override
  String sessionName(int number) {
    return 'Session $number';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsLicences => 'Open-source licences';

  @override
  String get licencesLegalese =>
      'FlappedEar Telemetry is released under the Apache License 2.0.\nMaps © OpenStreetMap contributors (ODbL) and © MapTiler.';

  @override
  String channelFromSource(String format) {
    return 'from $format';
  }

  @override
  String fusionAdded(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Combined with its $format: $count channels added',
      one: 'Combined with its $format: 1 channel added',
      zero: 'Combined with its $format: no channel added',
    );
    return '$_temp0';
  }

  @override
  String fusionConflict(String channel, String primary, String alternative) {
    return '$channel: the $primary and the $alternative disagree';
  }

  @override
  String fusionKeepPrimary(String format) {
    return 'Keep $format';
  }

  @override
  String get fusionFillGaps => 'Fill gaps';

  @override
  String fusionUseAlternative(String format) {
    return 'Use $format';
  }

  @override
  String fusionNotCombined(String format, String reason) {
    return 'Not combined with its $format: $reason';
  }

  @override
  String get fusionReasonNoSpeed => 'a recording has no speed';

  @override
  String get fusionReasonShortOverlap => 'the recordings overlap too little';

  @override
  String get fusionReasonAmbiguous =>
      'their speed traces do not line up clearly';

  @override
  String get fusionReasonClockDisagrees =>
      'their clocks disagree with their speed traces';

  @override
  String get fusionReasonInsufficient => 'not enough data to line them up';

  @override
  String get fusionReasonNotFound => 'the recording was not found';

  @override
  String get fusionReasonDifferent => 'the file found is a different recording';

  @override
  String get fusionReasonUnreadable => 'it could not be read';
}
