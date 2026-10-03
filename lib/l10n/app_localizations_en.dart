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
  String get coachTitle => 'Next session';

  @override
  String coachSubtitle(String session) {
    return 'Coaching $session against the day\'s faster laps';
  }

  @override
  String get coachLoading => 'Prepared after the theoretical best…';

  @override
  String coachFailed(String error) {
    return 'The coach could not run: $error';
  }

  @override
  String get coachNoTheoreticalBest =>
      'The coach needs the theoretical best, which could not be computed.';

  @override
  String get coachSpeedHidden =>
      'Speeds are not shown: the recordings\' speed units differ, or the coach converted them to km/h, and speeds are never shown converted or mixed.';

  @override
  String get coachLabel => 'Coach suggestion';

  @override
  String get coachMeasuredLabel => 'Measured';

  @override
  String get coachTryLabel => 'Try';

  @override
  String get coachKeepLabel => 'Keep';

  @override
  String get coachWhy => 'Why?';

  @override
  String get coachFooter =>
      'Coach suggestions follow DrivingCoach\'s rules and suggest an opportunity, not a promised gain. The areas below are observations.';

  @override
  String get coachKindEarlyLift => 'Try a later lift';

  @override
  String get coachKindExcessiveCoasting => 'Reduce coasting';

  @override
  String get coachKindLowMinimumSpeed =>
      'Keep more speed through the slow point';

  @override
  String get coachKindLateThrottle => 'Return to throttle sooner';

  @override
  String get coachKindImproving => 'Keep current approach';

  @override
  String coachItemTitle(String segment, String label) {
    return '$segment · $label';
  }

  @override
  String get coachActionEarlyLift =>
      'Try a slightly later lift within the approach you have already repeated successfully. Keep the braking point unchanged.';

  @override
  String get coachActionExcessiveCoasting =>
      'Reduce the gap with neither pedal engaged. Focus on smoother pedal transitions. Keep the braking point unchanged.';

  @override
  String get coachActionLowMinimumSpeed =>
      'Repeat the line and approach from your faster laps, aiming for a smoother minimum-speed phase. Keep the exit as your check.';

  @override
  String get coachActionLateThrottle =>
      'Work toward a smooth, slightly earlier throttle return after the slow point, using your faster laps as a reference.';

  @override
  String get coachActionImproving =>
      'Keep the approach from your latest laps. Repeat it before making another change.';

  @override
  String coachMeasuredOne(String metric, String observed, String reference) {
    return '$metric: $observed on this session\'s laps, $reference on your faster lap.';
  }

  @override
  String coachMeasuredMany(String metric, String observed, String reference) {
    return '$metric: $observed on this session\'s laps, $reference on your faster laps.';
  }

  @override
  String coachMeasuredImproving(String metric, String before, String after) {
    return '$metric improved on three laps in a row, from $before to $after, without losing exit speed.';
  }

  @override
  String get coachMetricLiftPoint => 'Lift point';

  @override
  String get coachMetricLongestCoast => 'Longest coast';

  @override
  String get coachMetricMinimumSpeed => 'Minimum speed';

  @override
  String get coachMetricThrottleReturn => 'Throttle return';

  @override
  String get coachMetricSegmentTime => 'Segment time';

  @override
  String get coachMetricExitSpeed => 'Exit speed';

  @override
  String get coachMetricBrakingStart => 'Braking start';

  @override
  String get coachMetricCoastDistance => 'Coast distance';

  @override
  String get coachReasonReady =>
      'Choose one focus at a time for your next run.';

  @override
  String get coachReasonNoSegments =>
      'The coach needs the day\'s segments and sector times first.';

  @override
  String coachReasonNoLapInGroup(String session) {
    return '$session has no timed lap in the laps compared.';
  }

  @override
  String get coachReasonNoCorners =>
      'The laps compared have no approved corner.';

  @override
  String coachReasonNoRecording(String session) {
    return 'The recording of $session is not available, so it cannot be coached.';
  }

  @override
  String coachReasonNoCornerMeasurements(String session) {
    return 'No lap of $session could be measured through a corner.';
  }

  @override
  String coachReasonNoFasterLap(String session) {
    return 'No lap of $session has a faster lap of the day to compare with.';
  }

  @override
  String get coachReasonNoPedals =>
      'Throttle and brake are not recorded, so lift, coasting and throttle return cannot be compared, and the speeds show no repeated pattern.';

  @override
  String get coachReasonNoPattern =>
      'Compared with your faster laps, no pattern stands out.';

  @override
  String coachReasonTooFewLaps(String session) {
    return 'A pattern was seen on fewer than three laps of $session, too few to plan from.';
  }

  @override
  String get coachReasonBelowThreshold =>
      'No repeated pattern is clear enough to suggest a change.';

  @override
  String get coachWhyAffected => 'This session\'s laps';

  @override
  String get coachWhyFaster => 'Faster laps compared';

  @override
  String get coachWhyBefore => 'First of the three laps';

  @override
  String coachWhyValues(String observed, String reference) {
    return '$observed against $reference';
  }

  @override
  String coachWhySupport(String score) {
    return 'Support $score of 0.9. A conservative score for how well the laps back the pattern, not a probability.';
  }

  @override
  String coachWhyMap(String segment) {
    return 'Best lap trace with $segment highlighted';
  }

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

  @override
  String fusionPending(String format) {
    return 'Lining up with its $format…';
  }

  @override
  String fusionLinedUp(String format, String offset) {
    return 'Lined up with its $format ($offset); nothing to add';
  }

  @override
  String fusionCombinedWith(String format, String sessions) {
    return '$format added to $sessions.';
  }

  @override
  String fusionMissingTitle(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'The $format of $count sessions could not be used',
      one: 'The $format of 1 session could not be used',
    );
    return '$_temp0';
  }

  @override
  String fusionMissingLine(String session, String path, String reason) {
    return '$session: $path · $reason';
  }

  @override
  String get fusionChannelSpeed => 'Speed';

  @override
  String get fusionChannelLatitude => 'Latitude';

  @override
  String get fusionChannelLongitude => 'Longitude';

  @override
  String get fusionChannelSatellites => 'Satellites';

  @override
  String fusionRelinkDifferent(String files) {
    return 'Not used, a different recording: $files.';
  }

  @override
  String fusionAddedNotCombined(String format, String sessions) {
    return '$format added to $sessions, but it could not be combined; it is kept and tried again when the day opens.';
  }

  @override
  String get fusionReasonFailed => 'lining them up failed';

  @override
  String relinkDifferentRecordings(int count, String files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$files in that folder are different recordings and were not used.',
      one: '$files in that folder is a different recording and was not used.',
    );
    return '$_temp0';
  }

  @override
  String get relinkNothingFound =>
      'No missing recording was found in that folder.';

  @override
  String get settings => 'Settings';

  @override
  String get settingsSpeedUnitHeading => 'Unit for unlabelled speeds';

  @override
  String get settingsSpeedUnitHelp =>
      'Used only for recordings that do not say their speed unit. A unit a recording declares is always shown as declared. Values are never converted.';

  @override
  String get speedUnitNone => 'None';

  @override
  String get settingsNoDayOpen => 'No day open yet.';

  @override
  String settingsDeclaredUnits(String units) {
    return 'The open day\'s recordings declare $units.';
  }

  @override
  String get unitsAnd => ' and ';

  @override
  String get settingsAllUnlabelled =>
      'Its recordings do not say their speed unit.';

  @override
  String settingsSomeUnlabelled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count of its recordings do not say their speed unit.',
      one: '1 of its recordings does not say its speed unit.',
    );
    return '$_temp0';
  }

  @override
  String get close => 'Close';

  @override
  String get appleMapLegal => 'Legal';

  @override
  String get segmentPickOnMap => 'Pick on map';

  @override
  String get segmentPickActive => 'Tap the map… (cancel)';

  @override
  String get segmentPickBannerStart => 'Tap the track line to place the start';

  @override
  String get segmentPickBannerEnd => 'Tap the track line to place the end';

  @override
  String get segmentPickBannerSplit => 'Tap the track line to place the split';

  @override
  String get segmentPickAmbiguous =>
      'Another part of the track passes close by here. Set the distance with the buttons instead.';

  @override
  String get segmentPickFar => 'Tap on the lap\'s track line.';

  @override
  String get segmentPickNoTrace =>
      'The lap trace is not available for picking.';

  @override
  String get segmentPickOutside =>
      'Pick a point inside this segment to split it.';

  @override
  String get variabilityHeading => 'Lap to lap in each corner';

  @override
  String get variabilityIntro =>
      'How much each corner changes from lap to lap over the group\'s laps: typical is the median, spread the middle half of the laps (interquartile range), from at least 3 laps. Observations, not causes.';

  @override
  String get variabilityNone => 'No corner was measured on enough laps.';

  @override
  String get variabilityNotMeasured => 'Not measured on these laps.';

  @override
  String variabilityLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return '$_temp0';
  }

  @override
  String get variabilityMeasured => 'measured';

  @override
  String get variabilityInferred => 'inferred';

  @override
  String variabilitySpread(String label, String spread, String tail) {
    return '$label: spread $spread · $tail';
  }

  @override
  String variabilityTypical(
    String label,
    String typical,
    String spread,
    String tail,
  ) {
    return '$label: typical $typical · spread $spread · $tail';
  }

  @override
  String variabilityTooFew(String label, String tail) {
    return '$label: too few laps ($tail)';
  }

  @override
  String get variabilityBraking => 'Braking point';

  @override
  String get variabilityApex => 'Apex speed';

  @override
  String get variabilityMinimum => 'Minimum speed';

  @override
  String get variabilityExit => 'Exit speed';

  @override
  String get variabilityPickup => 'Throttle pickup';

  @override
  String variabilityLine(String spread, String accuracy) {
    return 'Line: spread $spread m · $accuracy';
  }

  @override
  String variabilityGpsAccuracy(String meters) {
    return 'GPS accuracy about $meters m';
  }

  @override
  String get variabilityGpsUnknown => 'GPS accuracy not recorded';

  @override
  String get variabilityLineUnresolved =>
      ' · not distinguishable from GPS error';

  @override
  String get calculateAgain => 'Calculate again';

  @override
  String get retryRecordings => 'Retry recordings';

  @override
  String get retryRecordingsLooking => 'Opening…';

  @override
  String get retryRecordingsSaveFirst =>
      'Save the day first, then try the recordings again.';

  @override
  String get retryRecordingsStill =>
      'The recordings are still not where the day says.';

  @override
  String get sessionDetailsHeading => 'Session details';

  @override
  String get sessionDetailsNone => 'No conditions, setup changes or notes';

  @override
  String sessionDetailsTitle(String session) {
    return 'Details of $session';
  }

  @override
  String get sessionDetailsName => 'Name';

  @override
  String get sessionDetailsNameRequired => 'A session needs a name.';

  @override
  String get sessionDetailsConditions => 'Conditions';

  @override
  String get sessionDetailsConditionsHint => 'Dry, 18 °C';

  @override
  String get sessionDetailsSetup => 'Setup changes';

  @override
  String get sessionDetailsSetupHint => 'Tyres +0.1 bar';

  @override
  String get sessionDetailsNotes => 'Notes';

  @override
  String get sessionDetailsSaved =>
      'Kept in the day\'s file, which FlappedEar Overlays reads too.';

  @override
  String get detailsInvalid => 'This text cannot be saved.';

  @override
  String get renameDayMenu => 'Rename day…';

  @override
  String get renameDayTitle => 'Rename day';

  @override
  String get renameDayName => 'Day name';

  @override
  String get renameDayRequired => 'A day needs a name.';

  @override
  String get retryRecordingsWaitAdding =>
      'Wait until the recordings are added, then retry.';

  @override
  String get retryRecordingsAddedMeanwhile =>
      'Recordings were added meanwhile. Retry the recordings again.';

  @override
  String get retryRecordingsNone =>
      'None of the day\'s recordings could be opened, so the day stays as it is.';

  @override
  String retryRecordingsFailed(String reason) {
    return 'The day could not be opened again: $reason';
  }

  @override
  String get retryRecordingsChangedMeanwhile =>
      'The day was changed meanwhile. Save it, then retry the recordings.';

  @override
  String get lapsCompareTwo => 'Compare two laps';

  @override
  String get lapsLastComparison => 'Last comparison';

  @override
  String recordingsKeptApart(String format) {
    return 'Its $format is kept beside it and not combined';
  }

  @override
  String recordingsKeptApartUntilReopened(String format) {
    return 'Its $format is kept beside it and not combined until the day is opened again';
  }

  @override
  String get recordingsCheckClock => 'Check clock';

  @override
  String recordingsMakePrimary(String format) {
    return 'Make $format primary';
  }

  @override
  String get recordingsDontCombine => 'Don\'t combine';

  @override
  String recordingsChangingPrimary(String format) {
    return 'Reading the $format as this session\'s recording…';
  }

  @override
  String clockChecking(String primary, String alternative) {
    return 'Comparing the clocks of the $primary and the $alternative…';
  }

  @override
  String get clockAligned => 'The clocks line up.';

  @override
  String clockNotAligned(String reason) {
    return 'The clocks cannot be lined up: $reason.';
  }

  @override
  String clockMeasured(
    String primary,
    String alternative,
    String offset,
    String uncertainty,
  ) {
    return 'Measured from the speed traces: $primary time = $alternative time $offset ± $uncertainty';
  }

  @override
  String clockDrift(String ppm) {
    return 'Clock drift: $ppm ppm';
  }

  @override
  String clockCorrelation(
    String correlation,
    String overlap,
    int used,
    int windows,
  ) {
    return 'Speed correlation $correlation over $overlap of overlap; $used of $windows stretches agree';
  }

  @override
  String clockDeclared(String offset) {
    return 'The loggers\' clocks say $offset';
  }

  @override
  String get clockNoDeclared => 'The loggers do not both state a start time';

  @override
  String get clockAccept => 'Accept and combine';

  @override
  String get clockRefuse => 'Refuse';

  @override
  String clockRefuseNote(String primary, String alternative) {
    return 'Refusing keeps the $alternative beside the session without combining it; its analysis then uses the $primary only.';
  }

  @override
  String clockReopenNote(String alternative) {
    return 'The day\'s file cannot keep a refusal: when the day is opened again, the $alternative is lined up and combined again.';
  }
}
