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
  String get daySectionDay => 'Day';

  @override
  String get daySectionLaps => 'Laps';

  @override
  String get daySectionCompare => 'Compare';

  @override
  String get compareIntro =>
      'Two laps side by side: where one gains and loses time, segment by segment and corner by corner.';

  @override
  String get compareNeedsTwoLaps =>
      'Comparing needs two ranked laps of one circuit.';

  @override
  String get comparePickTwoLaps => 'Pick two laps';

  @override
  String get compareAgainstBest => 'Against the best of the day';

  @override
  String compareLapA(String time) {
    return 'A $time';
  }

  @override
  String compareLapB(String time) {
    return 'B $time';
  }

  @override
  String get dayBestLabel => 'Best day';

  @override
  String get theoreticalBestLabel => 'Theoretical best';

  @override
  String get theoreticalBestHint => 'Fastest of every segment';

  @override
  String get dayResultsTitle => 'Day results';

  @override
  String get addRecordings => 'Add recordings';

  @override
  String get dayReport => 'Day report';

  @override
  String get moreActions => 'More';

  @override
  String get saveAs => 'Save as…';

  @override
  String get addingRecordings => 'Adding recordings';

  @override
  String get waitUntilSessionAdded => 'Wait until the session is added.';

  @override
  String get nothingAdded => 'Nothing was added.';

  @override
  String addedToDay(String sessions) {
    return '$sessions added to the day.';
  }

  @override
  String savedAs(String file) {
    return 'Saved as $file.';
  }

  @override
  String savedAsChangesPending(String file) {
    return 'Saved as $file. Changes made while saving are not saved yet.';
  }

  @override
  String notSaved(String error) {
    return 'Not saved: $error';
  }

  @override
  String get waitThenFindRecordings =>
      'Wait until the recordings are added, then find the others.';

  @override
  String get saveThenFindRecordings =>
      'Save the day first, then find its recordings.';

  @override
  String get recordingsAddedMeanwhile =>
      'Recordings were added meanwhile. Find the recordings again.';

  @override
  String get noMissingRecordingFound =>
      'No missing recording was found in that folder.';

  @override
  String differentRecordingsNotUsed(int count, String files) {
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
  String dayReopenFailed(String error) {
    return 'The day could not be opened again: $error';
  }

  @override
  String sessionsNotOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions could not be opened',
      one: '1 session could not be opened',
    );
    return '$_temp0';
  }

  @override
  String get missingSessionsKept =>
      'They stay in the day when it is saved, but are not shown.';

  @override
  String get lookingForRecordings => 'Looking…';

  @override
  String get findRecordingsInFolder => 'Find recordings in a folder…';

  @override
  String lapsShareBestTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps share this time; the earliest is shown.',
      one: '1 lap has this time.',
    );
    return '$_temp0';
  }

  @override
  String get bestLapTrace => 'Trace of the best lap, coloured by speed';

  @override
  String get tapToOpenLap => 'Tap to open the lap.';

  @override
  String get comparedLaps => 'Compared laps';

  @override
  String groupLapCount(String group, int eligible, int count) {
    return '$group · $eligible/$count laps';
  }

  @override
  String lapsRanked(int count, int eligible) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$eligible of $count laps ranked',
      one: '$eligible of 1 lap ranked',
    );
    return '$_temp0';
  }

  @override
  String get bestLapOfEachSession => 'Best lap of each session';

  @override
  String noRankedLap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No ranked lap · $count laps',
      one: 'No ranked lap · 1 lap',
    );
    return '$_temp0';
  }

  @override
  String typicalTime(String time) {
    return 'typical $time';
  }

  @override
  String get circuitNotIdentified =>
      'Its circuit could not be identified, so its laps are not compared.';

  @override
  String get circuits => 'Circuits';

  @override
  String get notes => 'Notes';

  @override
  String get circuitNotIdentifiedShort => 'Not identified';

  @override
  String get detectedRoute => 'Detected route';

  @override
  String get directionUnknown => 'direction unknown';

  @override
  String get circuitSetByYou => 'set by you';

  @override
  String get circuitInferredFromGps => 'inferred from GPS';

  @override
  String get noBestLapNoCircuit =>
      'No best lap: no session has enough complete GPS laps to identify its circuit.';

  @override
  String get noBestLapNoRankable =>
      'No best lap: no lap of this group can be ranked.';

  @override
  String get compareTwoLaps => 'Compare two laps';

  @override
  String get bestOfDay => 'Best of the day';

  @override
  String bestOfSession(String session) {
    return 'Best of $session';
  }

  @override
  String lapExcluded(String reason) {
    return 'Excluded: $reason';
  }

  @override
  String get lapExcludedNoReason => 'Excluded';

  @override
  String lapNotRanked(String issue) {
    return 'Not ranked: $issue';
  }

  @override
  String get noStartFinishPass => 'No start/finish pass';

  @override
  String get notTimed => 'Not timed';

  @override
  String get pickLapA => 'Lap A';

  @override
  String pickLapB(String lap) {
    return 'Compare $lap with';
  }

  @override
  String lapName(String session, int number) {
    return '$session · LAP $number';
  }

  @override
  String outLapName(String session) {
    return '$session · OUT';
  }

  @override
  String inLapName(String session) {
    return '$session · IN';
  }

  @override
  String unknownLapName(String session) {
    return '$session · UNKNOWN';
  }

  @override
  String circuitGroup(int number, String layout, String direction) {
    return 'Group $number · $layout · $direction';
  }

  @override
  String circuitGroupUnresolved(String session) {
    return 'Unresolved · $session';
  }

  @override
  String get noteUndated =>
      'Recording date and time unavailable; listed after the dated recordings in import order.';

  @override
  String get noteNoPasses =>
      'No reliable start/finish passes; lap type is unknown.';

  @override
  String get lapIssueLayoutUnresolved => 'Layout needs confirmation';

  @override
  String get lapIssueDirectionUnresolved => 'Direction needs confirmation';

  @override
  String get lapIssueTimingGateUnresolved => 'Timing gates unresolved';

  @override
  String get lapIssueChangedLayout => 'Different layout';

  @override
  String get lapIssueOppositeDirection => 'Opposite direction';

  @override
  String get lapIssueChangedTimingGate => 'Different timing gates';

  @override
  String get lapIssueIncompleteGps => 'Incomplete GPS';

  @override
  String get lapIssueInvalidGps => 'Invalid GPS';

  @override
  String get lapIssueUserExclusion => 'User exclusion';

  @override
  String get lapIssueNotTimedLap => 'Not a complete timed lap';

  @override
  String get lapIssueStaleSource => 'Source changed; reload recording';

  @override
  String get lapIssueIneligibleLap => 'Lap is not eligible';

  @override
  String get lapIssueDifferentRoute =>
      'Lap leaves the route the other laps took (off track, a detour or the pit lane)';
}
