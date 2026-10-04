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
    return 'Detected route: $length m, $direction (inferred from GPS).';
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
  String get coachReasonTooFewLaps =>
      'A pattern was seen on fewer than three laps today, too few to plan from.';

  @override
  String get coachReasonBelowThreshold =>
      'No repeated pattern is clear enough to suggest a change.';

  @override
  String get coachReasonNotInSession =>
      'Patterns seen earlier today do not repeat on most of this session\'s laps.';

  @override
  String coachSlowLaps(String laps) {
    return 'Left out as much slower than their session\'s typical lap (traffic, warm-up or cool-down): $laps.';
  }

  @override
  String get coachWhyAffected => 'This session\'s laps';

  @override
  String get coachWhyEarlier => 'Earlier laps showing it today';

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
  String get appleMapLegal => 'Legal';

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
  String get comparePickTwoLaps => 'Compare two laps';

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
  String get dayBestLabel => 'Best lap of the day';

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
  String get setCircuit => 'Set the circuit…';

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
  String get noteNoGps =>
      'No GPS positions in this recording; laps cannot be timed.';

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

  @override
  String get tbFailedElsewhere =>
      'Not available: the theoretical best could not be calculated.';

  @override
  String get tbTiming => 'Timing every lap on one track axis…';

  @override
  String tbIntro(int segments, int laps) {
    String _temp0 = intl.Intl.pluralLogic(
      segments,
      locale: localeName,
      other: '$segments segments',
      one: '1 segment',
    );
    String _temp1 = intl.Intl.pluralLogic(
      laps,
      locale: localeName,
      other: '$laps laps',
      one: '1 lap',
    );
    return 'The fastest time of each of the $_temp0 across $_temp1. It combines parts of different laps, so it does not show that the whole lap can be driven that fast.';
  }

  @override
  String get tbSegmentsProposed =>
      'Segments proposed from the best lap; saving the day keeps them.';

  @override
  String get tbSegmentsCorrected => 'The segments include your corrections.';

  @override
  String get tbEditSegments => 'Edit segments';

  @override
  String get tbWhereTimeGoes => 'Where the time goes';

  @override
  String tbMarkedBest(String text) {
    return '$text · best';
  }

  @override
  String tbMapLabel(String lap) {
    return 'Best lap trace, each segment coloured by the time $lap loses there';
  }

  @override
  String get tbTapCorner =>
      'Tap a corner for its speeds, braking and pickup against the best lap.';

  @override
  String get tbCompareHint =>
      'The compare button opens this lap against the best lap through the segment in the Corner Analyzer.';

  @override
  String get tbOpenInAnalyzer => 'Open in the Corner Analyzer';

  @override
  String get tbSectorTimes => 'Sector times';

  @override
  String get tbSectorHint =>
      'The fastest time of each segment is highlighted. Tap a lap to show its losses on the map.';

  @override
  String tbNotCovered(String time) {
    return 'Not fully covered on this lap · fastest $time';
  }

  @override
  String tbFastestHere(String time) {
    return 'Fastest here · $time';
  }

  @override
  String tbFastestBy(String time, String lap) {
    return 'Fastest $time · $lap';
  }

  @override
  String get tbLapUnavailable => 'lap unavailable';

  @override
  String get tbBestLap => 'Best lap';

  @override
  String get tbBestLapSameSegments => 'Best lap, same segments';

  @override
  String get tbAvailable => 'Available';

  @override
  String get tbLapColumn => 'Lap';

  @override
  String get tbTimeColumn => 'Time';

  @override
  String get tbFastestRow => 'Fastest';

  @override
  String tbCellLabel(String column, String value) {
    return '$column: $value';
  }

  @override
  String tbFastestCell(String value) {
    return '$value, the fastest';
  }

  @override
  String tbSegmentCorner(String number) {
    return 'Corner $number';
  }

  @override
  String tbSegmentCorners(String numbers) {
    return 'Corners $numbers';
  }

  @override
  String tbSegmentStraight(String number) {
    return 'Straight $number';
  }

  @override
  String get tbNoConfiguration =>
      'Confirm a compatible track configuration before calculating a theoretical best.';

  @override
  String get tbNoEligibleLaps =>
      'No eligible laps in this group to calculate a theoretical best from.';

  @override
  String get tbNoApprovedRun =>
      'No run in this group has an approved segment review yet. Approve segments for at least one run first.';

  @override
  String get tbNoApprovedSegments =>
      'No approved segments to measure sectors against.';

  @override
  String get tbIncompleteCoverage =>
      'At least one sector has no fully covered time on any eligible lap, so no total is shown.';

  @override
  String get tbCancelled => 'Theoretical best calculation was cancelled.';

  @override
  String get consistencyHeading => 'Consistency';

  @override
  String consistencyIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps are',
      one: '1 lap is',
    );
    return 'Typical time is the median; the spread is the interquartile range, the width of the middle half of the laps, so one slow or quick lap does not dominate it. At least $_temp0 needed.';
  }

  @override
  String get consistencyLapTimes => 'Lap times';

  @override
  String get consistencyAllSessions => 'All sessions';

  @override
  String get consistencySegmentTimes => 'Segment times';

  @override
  String get consistencyMeasuring => 'Measured with the theoretical best…';

  @override
  String consistencyNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return 'Needs at least $_temp0';
  }

  @override
  String consistencyValue(String time, String spread) {
    return '$time · spread $spread s';
  }

  @override
  String consistencyLapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return '$_temp0';
  }

  @override
  String get timeLossTitle => 'Time losses';

  @override
  String get timeLossLoading => 'Measured with the theoretical best…';

  @override
  String get timeLossScopeSessionBest => 'Each session\'s best';

  @override
  String get timeLossScopeEveryLap => 'Every lap';

  @override
  String timeLossAgainst(String lap) {
    return 'Against $lap';
  }

  @override
  String timeLossLapsCompared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps compared',
      one: '1 lap compared',
    );
    return '$_temp0';
  }

  @override
  String timeLossLossesObserved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count losses observed',
      one: '1 loss observed',
    );
    return '$_temp0';
  }

  @override
  String timeLossUntimedLeftOut(int count) {
    return '$count not fully covered left out';
  }

  @override
  String get timeLossExplanation =>
      'Each loss is the extra time one lap took through one segment compared with the best lap, both timed on one track axis. A straight right after a corner is its own segment, so time lost on the exit is not counted in the corner. An observed loss is not a guaranteed or necessarily safe gain.';

  @override
  String get timeLossNone =>
      'No lap lost time to the best lap in any timed segment.';

  @override
  String get timeLossOnlySessionBest =>
      'With one session, its best lap is the best lap of the day, so there is nothing to compare. Choose Every lap to compare all the laps.';

  @override
  String get timeLossNoOtherLap =>
      'No other lap could be compared with the best lap.';

  @override
  String timeLossShowAll(int count) {
    return 'Show all $count';
  }

  @override
  String get timeLossReasonNoReference =>
      'The best lap could not be timed against the segments.';

  @override
  String get timeLossReasonBestLapUntimed =>
      'The group\'s best lap could not be timed against the approved segments.';

  @override
  String timeLossSegmentAfterCorner(String segment, String corner) {
    return '$segment · after $corner';
  }

  @override
  String timeLossSegmentAfterTheCorner(String segment) {
    return '$segment · after the corner';
  }

  @override
  String get timeLossLapUnavailable => 'Lap unavailable';

  @override
  String timeLossAgainstBestLap(String lap, String best) {
    return '$lap against the best lap, $best';
  }

  @override
  String get timeLossUnavailable => 'unavailable';

  @override
  String get timeLossThisLap => 'This lap';

  @override
  String get timeLossBestLap => 'Best lap';

  @override
  String get timeLossDifference => 'Difference';

  @override
  String timeLossThrough(String segment, int start, int end) {
    return 'Through $segment, from $start m to $end m after the line.';
  }

  @override
  String timeLossGap(String start, String end) {
    return 'Gap to the best lap: $start at the start of the segment, $end at its end.';
  }

  @override
  String get timeLossNoGps =>
      'Part of the segment has no GPS on one of the laps.';

  @override
  String timeLossMapLabel(String segment) {
    return 'Best lap trace with $segment highlighted';
  }

  @override
  String get timeLossDisclaimer =>
      'An observed difference between two laps, not a guaranteed or necessarily safe gain.';

  @override
  String timeLossOpenLap(String lap) {
    return 'Open $lap';
  }

  @override
  String timeLossCompareWith(String lap) {
    return 'Compare with $lap';
  }

  @override
  String get focusTitle => 'Where to look next';

  @override
  String get focusLoading => 'Selected with the theoretical best…';

  @override
  String get focusNone =>
      'No loss, sector gap or spread is large enough to single out.';

  @override
  String get focusIntro =>
      'Each starts with what was measured. The line under it is a hypothesis to check in the laps, not a cause or an instruction.';

  @override
  String get focusKindSectorGap => 'Best lap against the fastest sector';

  @override
  String get focusKindRepeatedLoss => 'Repeated loss';

  @override
  String get focusKindBrakingSpread => 'Braking-point spread';

  @override
  String get focusKindMinimumSpeedSpread => 'Lowest-speed spread';

  @override
  String focusObserved(String text) {
    return 'Observed: $text';
  }

  @override
  String focusHypothesis(String text) {
    return 'Hypothesis: $text';
  }

  @override
  String focusCompareLaps(String lap, String other) {
    return 'Compare $lap with $other';
  }

  @override
  String get focusLapUnavailable => 'a lap unavailable';

  @override
  String focusThrough(String segment) {
    return 'Through $segment';
  }

  @override
  String get focusNotTimed => 'not timed';

  @override
  String get focusBrakingNotMeasured => 'braking point not measured';

  @override
  String focusBrakingStarts(int meters) {
    return 'braking starts at $meters m';
  }

  @override
  String get focusLowestSpeedNotMeasured => 'lowest speed not measured';

  @override
  String focusLowestSpeed(String speed) {
    return 'lowest speed $speed';
  }

  @override
  String get focusDisclaimer =>
      'Measured on these laps only. It does not say which way is faster or safe.';

  @override
  String get focusCompareAB => 'Compare laps A and B';

  @override
  String focusObservationSectorGap(
    String bestLap,
    String gap,
    String segment,
    String sourceLap,
  ) {
    return 'Your best lap ($bestLap) was $gap s slower through $segment than $sourceLap, the fastest recorded there.';
  }

  @override
  String focusHypothesisSectorGap(String segment) {
    return 'Comparing the two laps through $segment may show where the time went: where braking starts, the lowest speed, and when the throttle comes back.';
  }

  @override
  String focusObservationRepeatedLoss(
    String count,
    String total,
    String segment,
    String reference,
    String median,
  ) {
    return 'In $count of $total compared laps you lost time through $segment against $reference (median $median s).';
  }

  @override
  String focusHypothesisRepeatedLoss(String reference, String segment) {
    return 'Because it repeats, comparing a typical lap with $reference through $segment may show a pattern rather than a one-off.';
  }

  @override
  String focusObservationBrakingSpread(
    String segment,
    String spread,
    String count,
  ) {
    return 'Where braking starts for $segment varies by $spread m across the middle half of $count laps (measured from the brake signal).';
  }

  @override
  String focusHypothesisBrakingSpread(String segment) {
    return 'A more repeatable braking reference for $segment may be worth checking. This does not show whether earlier or later braking is faster or safe; compare the earliest and the latest example.';
  }

  @override
  String focusObservationMinimumSpeedSpread(
    String segment,
    String spread,
    String count,
    String median,
  ) {
    return 'The lowest speed through $segment varies by $spread across the middle half of $count laps (median $median).';
  }

  @override
  String get focusObservationRecordingUnits =>
      'Speeds are in the recording\'s own units.';

  @override
  String focusHypothesisMinimumSpeedSpread(String segment) {
    return 'Comparing the slowest and the fastest example through $segment may show what differs; a higher minimum speed is not by itself better.';
  }

  @override
  String get progressionTitle => 'Progression';

  @override
  String get progressionBySession => 'By session';

  @override
  String get progressionBySegment => 'By segment';

  @override
  String get progressionSessionsIntro =>
      'Sessions in recording order; sessions without a recording time follow in import order. The bar runs from the quickest to the slowest ranked lap on one time scale, the middle half boxed and the typical lap marked.';

  @override
  String get progressionNoSession => 'No session to compare.';

  @override
  String get progressionRecordingTimeUnavailable =>
      'Recording time unavailable';

  @override
  String progressionRecordingClock(String time, String date) {
    return '$time UTC on $date';
  }

  @override
  String get progressionNoRecordedLaps => 'No recorded laps';

  @override
  String progressionNoRankedLap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'No ranked lap · 0 of $count laps',
      one: 'No ranked lap · 0 of 1 lap',
    );
    return '$_temp0';
  }

  @override
  String progressionLapsRanked(int count, int eligible) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$eligible of $count laps ranked',
      one: '$eligible of 1 lap ranked',
    );
    return '$_temp0';
  }

  @override
  String progressionTypical(String time) {
    return 'Typical $time';
  }

  @override
  String progressionTypicalNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Typical lap needs at least $count ranked laps',
      one: 'Typical lap needs at least 1 ranked lap',
    );
    return '$_temp0';
  }

  @override
  String progressionBestAgainst(String delta, String session) {
    return 'Best $delta against $session';
  }

  @override
  String progressionConditions(String conditions) {
    return 'Conditions: $conditions';
  }

  @override
  String progressionSetup(String setup) {
    return 'Setup: $setup';
  }

  @override
  String progressionNotes(String notes) {
    return 'Notes: $notes';
  }

  @override
  String progressionBestLap(int number) {
    return 'Best: LAP $number';
  }

  @override
  String get progressionMeasuring => 'Measured with the theoretical best…';

  @override
  String progressionSegmentsIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Each segment\'s typical time (median) and spread (middle half) per session. The quickest typical time of each segment is highlighted. Fewer than $count laps: no statistics. Tap a cell for its laps.',
      one: 'Each segment\'s typical time (median) and spread (middle half) per session. The quickest typical time of each segment is highlighted. Fewer than 1 lap: no statistics. Tap a cell for its laps.',
    );
    return '$_temp0';
  }

  @override
  String get progressionLapUnavailable => 'Lap unavailable';

  @override
  String get progressionNoTimedSegments => 'No session has timed segments.';

  @override
  String progressionSpread(String seconds) {
    return 'spread $seconds s';
  }

  @override
  String progressionLapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return '$_temp0';
  }

  @override
  String get channelOil => 'Oil';

  @override
  String get channelCoolant => 'Coolant';

  @override
  String get channelIntakeAir => 'Intake air';

  @override
  String get channelGearbox => 'Gearbox';

  @override
  String get channelExhaust => 'Exhaust';

  @override
  String get channelAmbient => 'Ambient';

  @override
  String get channelNotRecorded => 'Not recorded';

  @override
  String get channelNoValidSamples => 'No valid samples';

  @override
  String channelSummary(
    String mean,
    String minimum,
    String maximum,
    int coverage,
  ) {
    return 'mean $mean · $minimum – $maximum · $coverage% covered';
  }

  @override
  String channelImplausibleLeftOut(int count) {
    return '$count implausible left out';
  }

  @override
  String get channelOutLap => 'out lap';

  @override
  String get channelInLap => 'in lap';

  @override
  String channelLapSection(int number) {
    return 'lap $number';
  }

  @override
  String get channelUnknownSection => 'unknown section';

  @override
  String get channelCoolingNone => 'none recorded';

  @override
  String channelCoolingDrop(String drop, String duration) {
    return '−$drop in $duration';
  }

  @override
  String channelCooling(String cooling) {
    return 'Cooling: $cooling';
  }

  @override
  String get channelLapTime => 'Lap time';

  @override
  String get channelStrongAcceleration => 'Strong acceleration';

  @override
  String channelAssociationNoSpread(String metric, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$metric: the temperature (or the metric) did not vary over $count laps.',
      one: '$metric: the temperature (or the metric) did not vary over 1 lap.',
    );
    return '$_temp0';
  }

  @override
  String channelAssociationTooFew(String metric, int count, int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$metric: $count comparable laps with this temperature; at least $minimum are needed.',
      one:
          '$metric: 1 comparable lap with this temperature; at least $minimum are needed.',
    );
    return '$_temp0';
  }

  @override
  String channelAssociation(
    String metric,
    String rho,
    String strength,
    int count,
    String meaning,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$metric: ρ $rho · $strength · $count laps — $meaning',
      one: '$metric: ρ $rho · $strength · 1 lap — $meaning',
    );
    return '$_temp0';
  }

  @override
  String get channelStrengthWeak => 'weak';

  @override
  String get channelStrengthModerate => 'moderate';

  @override
  String get channelStrengthStrong => 'strong';

  @override
  String get channelMeaningLittle => 'little association';

  @override
  String get channelMeaningQuicker => 'hotter laps were quicker';

  @override
  String get channelMeaningSlower => 'hotter laps were slower';

  @override
  String get channelMeaningHarder => 'hotter laps accelerated harder';

  @override
  String get channelMeaningLess => 'hotter laps accelerated less';

  @override
  String get channelCarTitle => 'Car';

  @override
  String get channelCarReading =>
      'Reading each session\'s recorded temperatures…';

  @override
  String get channelCarNoChannels =>
      'None of the recordings contain a temperature channel.';

  @override
  String get channelCarIntro =>
      'Each session on its own, in recording order. Gaps in a recording are never bridged; implausible readings and placeholder zeros are left out and counted. Cooling is a continuously recorded drop of at least 5° over at least 30 s.';

  @override
  String get channelUnitsNotDeclared => 'units not declared by the recording';

  @override
  String get channelConfounded =>
      'The temperature also changed through the day, so this cannot be told apart from everything else that changed: the driver, tyres, track and fuel.';

  @override
  String get channelHeartRateIntro =>
      'Observed values from the recording, not an assessment.';

  @override
  String get channelEverySectionIntro =>
      'Every recorded section of each session.';

  @override
  String get channelWithLapPerformance => 'With lap performance';

  @override
  String channelConfoundedRose(String rho) {
    return 'The temperature also rose through the day (ρ $rho with the order of laps), so this cannot be told apart from everything else that changed over the day: the driver, tyres, track and fuel.';
  }

  @override
  String channelConfoundedFell(String rho) {
    return 'The temperature also fell through the day (ρ $rho with the order of laps), so this cannot be told apart from everything else that changed over the day: the driver, tyres, track and fuel.';
  }

  @override
  String channelSpearman(int coverage, int lowCoverage, int notRecorded) {
    return 'Spearman rank correlation over the day\'s compared laps whose sensor covered at least $coverage% of the lap. $lowCoverage left out for low coverage, $notRecorded without a valid reading. It describes how the two moved together on this day; it does not establish a critical temperature or a cause.';
  }

  @override
  String get channelDriverTitle => 'Driver';

  @override
  String get channelDriverReading =>
      'Reading each session\'s recorded heart rate…';

  @override
  String get channelDriverNoHeartRate => 'No heart rate recorded.';

  @override
  String get channelDriverIntro =>
      'Heart rate from the recordings: observed values, not an assessment. Per lap: mean bpm; tap a lap to open it.';

  @override
  String get channelHeartRate => 'Heart rate';

  @override
  String get channelEverySection => 'Every section…';

  @override
  String channelLapMean(int number, String mean) {
    return 'LAP $number · $mean';
  }

  @override
  String get channelRecordingUnavailable => 'Recording unavailable.';

  @override
  String get channelSummariesCancelled => 'Channel summaries were cancelled.';

  @override
  String cornerSummaryMin(String speed) {
    return 'Min $speed';
  }

  @override
  String cornerSummaryMinWithBest(String speed, String best) {
    return 'Min $speed (best lap $best)';
  }

  @override
  String cornerSummaryBrakes(String where) {
    return 'brakes $where';
  }

  @override
  String cornerSummaryBrakesWithBest(String where, String position) {
    return 'brakes $where ($position)';
  }

  @override
  String cornerBeforeEntry(int metres) {
    return '$metres m before';
  }

  @override
  String cornerIntoCorner(int metres) {
    return '$metres m into the corner';
  }

  @override
  String get cornerSamePosition => 'same';

  @override
  String cornerLater(int metres) {
    return '$metres m later';
  }

  @override
  String cornerEarlier(int metres) {
    return '$metres m earlier';
  }

  @override
  String get missingRecordingNotFound => 'Recording not found.';

  @override
  String get missingRecordingDuplicate =>
      'The same recording as another session of this day.';

  @override
  String get missingRecordingDifferent =>
      'The file found is a different recording.';

  @override
  String get lapB => 'Lap B';

  @override
  String get suggestedFastest => 'Suggested: the fastest';

  @override
  String get noOtherRankedLap =>
      'No other ranked lap of this group to compare with.';

  @override
  String get addingCancelled => 'Adding was cancelled.';

  @override
  String get dayClosed => 'The day was closed.';

  @override
  String nothingAddedError(String error) {
    return 'Nothing was added: $error';
  }

  @override
  String get diagnosticsTitle => 'Diagnostics';

  @override
  String get diagnosticsRefresh => 'Refresh';

  @override
  String get diagnosticsLastImport => 'Last import';

  @override
  String get diagnosticsNoImport => 'No day imported since the app started.';

  @override
  String get diagnosticsRecordingsRead => 'Recordings read';

  @override
  String get diagnosticsSessions => 'Sessions';

  @override
  String get diagnosticsSamples => 'Samples';

  @override
  String get diagnosticsChannelValues => 'Channel values';

  @override
  String get diagnosticsMemory => 'Memory';

  @override
  String get diagnosticsCurrentMemory => 'Current';

  @override
  String get diagnosticsPeakMemory => 'Peak';

  @override
  String get diagnosticsNotAvailable => 'Not available';

  @override
  String get diagnosticsMemoryNote =>
      'Resident memory of the app as the system reports it; the peak is since the app started. Times are wall time on this device.';

  @override
  String get diagnosticsStepScan => 'Find recordings';

  @override
  String get diagnosticsStepParse => 'Parse and import';

  @override
  String get diagnosticsStepAnalysis => 'Day analysis';

  @override
  String get diagnosticsStepImportTotal => 'Import, start to results';

  @override
  String get diagnosticsStepTheoreticalBest => 'Theoretical best and segments';

  @override
  String get diagnosticsStepChannelSummaries => 'Channel summaries';

  @override
  String get reportGroupNone =>
      'Choose a group of compatible laps on the results page.';

  @override
  String get reportCalculating => 'Calculating…';

  @override
  String get reportNotCalculated => 'Not calculated yet.';

  @override
  String get reportOutOfDate => 'Out of date after an analysis change.';

  @override
  String get reportUnavailable => 'Unavailable.';

  @override
  String get reportNotInReport => 'Not in this report.';

  @override
  String get reportChooseGroup => 'Choose a compatibility group.';

  @override
  String get reportNoEligibleLap => 'No eligible lap in this group.';

  @override
  String get reportNoSession => 'No session in this group.';

  @override
  String get reportNoEligibleLaps => 'No eligible laps to summarize.';

  @override
  String get reportNoHeartRate => 'No heart rate recorded.';

  @override
  String get reportNoTemperature => 'No temperature recorded.';

  @override
  String get reportBestTitle => 'Best lap and what is left';

  @override
  String get reportBestLap => 'Best lap';

  @override
  String get reportTheoreticalBest => 'Theoretical best';

  @override
  String reportTheoreticalAvailable(String seconds) {
    return '$seconds s available across the approved segments';
  }

  @override
  String get reportTheoreticalNoTotal =>
      'Some segments have no timed lap; no total.';

  @override
  String get reportOpenBestLap => 'Open best lap';

  @override
  String get reportFocusIntro =>
      'Each starts with what was measured. The line under it is a hypothesis to check in the laps, not a cause or an instruction.';

  @override
  String reportFocusCompare(String lap, String other, String segment) {
    return 'Compare $lap with $other at $segment';
  }

  @override
  String get reportLossesTitle => 'Largest time losses';

  @override
  String reportLossesIntro(String reference, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps compared',
      one: '1 lap compared',
    );
    return 'Against $reference · $_temp0. An observed loss is not a guaranteed or necessarily safe gain.';
  }

  @override
  String get reportSessionsTitle => 'Sessions';

  @override
  String get reportNoEligibleLapShort => 'no eligible lap';

  @override
  String reportSessionBest(String time) {
    return 'best $time';
  }

  @override
  String get reportSameAsPrevious => 'same as the previous session';

  @override
  String reportFasterThanPrevious(String seconds) {
    return '$seconds s faster than the previous session';
  }

  @override
  String reportSlowerThanPrevious(String seconds) {
    return '$seconds s slower than the previous session';
  }

  @override
  String reportEligibleLaps(int eligible, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return '$eligible of $_temp0 eligible';
  }

  @override
  String reportMedian(String time) {
    return 'median $time';
  }

  @override
  String reportConsistencyDay(String time, String spread, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return 'Typical lap $time · middle half within $spread s · $_temp0';
  }

  @override
  String reportConsistencyTooFew(int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      minimum,
      locale: localeName,
      other: 'Fewer than $minimum eligible laps; no spread.',
      one: 'Fewer than 1 eligible lap; no spread.',
    );
    return '$_temp0';
  }

  @override
  String reportCarPeak(String channel, String value, String session) {
    return '$channel · peak $value in $session';
  }

  @override
  String reportCoolingIntervals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recorded cooling intervals',
      one: '1 recorded cooling interval',
    );
    return '$_temp0';
  }

  @override
  String get reportNoCooling => 'no recorded cooling';

  @override
  String get reportNoTemperatureSamples => 'No valid temperature samples.';

  @override
  String reportHeartRateSummary(String mean, String minimum, String maximum) {
    return 'mean $mean bpm · $minimum – $maximum';
  }

  @override
  String reportCovered(int percent) {
    return '$percent% covered';
  }

  @override
  String get segmentEditorTitle => 'Edit segments';

  @override
  String get segmentEditorUndo => 'Undo';

  @override
  String get segmentEditorRedo => 'Redo';

  @override
  String get segmentEditorTiming => 'Timing every lap on one track axis…';

  @override
  String get segmentEditorMapLabel =>
      'Best lap trace with the segment boundaries';

  @override
  String segmentEditorMapLabelHighlighted(String segment) {
    return 'Best lap trace with the segment boundaries, $segment highlighted';
  }

  @override
  String get segmentEditorAutomatic => 'Automatic segments';

  @override
  String get segmentEditorEdited => 'Edited segments';

  @override
  String segmentEditorSummary(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segments',
      one: '1 segment',
    );
    return 'Theoretical best $time · $_temp0';
  }

  @override
  String get segmentEditorRestoreAutomatic => 'Restore automatic';

  @override
  String segmentEditorProposedFrom(String lap) {
    return 'Proposed from $lap. Tap a segment to correct it.';
  }

  @override
  String get segmentEditorProposedFromBestLap =>
      'Proposed from the best lap. Tap a segment to correct it.';

  @override
  String get segmentEditorCorrectionsSaved =>
      'Your corrections are saved with the day and are never replaced by automatic segments.';

  @override
  String get segmentEditorTypeCorner => 'Corner';

  @override
  String get segmentEditorTypeStraight => 'Straight';

  @override
  String get segmentEditorTypeSector => 'Sector';

  @override
  String segmentEditorRow(
    String type,
    String start,
    String end,
    String length,
  ) {
    return '$type · $start–$end m · $length m';
  }

  @override
  String segmentEditorRowEdited(String row) {
    return '$row · edited';
  }

  @override
  String get segmentEditorRestoreTitle => 'Restore automatic segments?';

  @override
  String get segmentEditorRestoreBody =>
      'Your corrections to this track layout\'s segments are replaced by the segments proposed from the best lap.';

  @override
  String get segmentEditorRestore => 'Restore';

  @override
  String get segmentEditorName => 'Name';

  @override
  String get segmentEditorStart => 'Start';

  @override
  String get segmentEditorEnd => 'End';

  @override
  String get segmentEditorKeepJoined => 'Move the neighbouring segment too';

  @override
  String get segmentEditorApply => 'Apply';

  @override
  String get segmentEditorReset => 'Reset';

  @override
  String segmentEditorSplitAt(String meters) {
    return 'Split at $meters m';
  }

  @override
  String get segmentEditorSplitHere => 'Split here';

  @override
  String get segmentEditorMergeWithNext => 'Merge with next';

  @override
  String segmentEditorMergeWith(String segment) {
    return 'Merge with $segment';
  }

  @override
  String get segmentEditorRemove => 'Remove';

  @override
  String get segmentEditorErrorSaving => 'The day is being saved.';

  @override
  String get segmentEditorErrorNotCalculated =>
      'The segments can be edited once the theoretical best is calculated.';

  @override
  String get segmentEditorErrorAlreadyAutomatic =>
      'The segments are already the automatic ones.';

  @override
  String get segmentEditorErrorNotPossible => 'This edit is not possible.';

  @override
  String get segmentEditorErrorLastSegment =>
      'The theoretical best needs at least one segment. Restore the automatic segments instead.';

  @override
  String get segmentEditorErrorNoLongerApproved =>
      'This segment is no longer approved.';

  @override
  String get segmentEditorErrorNothingToUndo => 'Nothing to undo.';

  @override
  String get segmentEditorErrorNothingToRedo => 'Nothing to redo.';

  @override
  String get segmentEditorErrorHistoryCleared =>
      'The segments changed outside this editor, so the edit history was cleared.';

  @override
  String get segmentEditorErrorInvalidStored =>
      'The stored approved segments are invalid.';

  @override
  String get segmentEditorErrorOtherConfiguration =>
      'Segments approved for a different track configuration must be discarded first.';

  @override
  String segmentEditorErrorWouldBeEmpty(String segment) {
    return '“$segment” would become empty.';
  }

  @override
  String segmentEditorErrorWouldBeInvalid(String segment) {
    return '“$segment” would be invalid.';
  }

  @override
  String segmentEditorErrorWouldOverlap(String segment, String other) {
    return '“$segment” would overlap “$other”.';
  }

  @override
  String segmentEditorErrorTooMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At most $count segments can be approved.',
      one: 'At most 1 segment can be approved.',
    );
    return '$_temp0';
  }

  @override
  String get segmentEditorErrorCrossesGate =>
      'Only one segment may cross the start/finish line.';

  @override
  String get segmentEditorErrorChooseType =>
      'Choose corner, straight or sector.';

  @override
  String get segmentEditorErrorNoAxis => 'The track axis is unavailable.';

  @override
  String get segmentEditorErrorSplitInside =>
      'Split inside the segment, away from its ends.';

  @override
  String get segmentEditorErrorSplitName =>
      'Enter a name of 1–160 characters for the new segment.';

  @override
  String get segmentEditorErrorMergeSame =>
      'Choose two different approved segments.';

  @override
  String get segmentEditorErrorMergeNotAdjacent =>
      'Only segments that share a boundary can be merged.';

  @override
  String get segmentEditorErrorMergeWholeLap =>
      'Merging would cover the whole lap; a segment needs distinct start and end.';

  @override
  String get segmentEditorErrorName => 'Enter a name of 1–160 characters.';

  @override
  String segmentEditorErrorBounds(String length) {
    return 'Bounds must lie between 0 and $length m.';
  }

  @override
  String get segmentEditorErrorEmpty => 'A segment cannot be empty.';

  @override
  String get reportStale =>
      'The analysis decisions changed after this result was computed.';

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
    return 'Line: spread $spread m · $accuracy';
  }

  @override
  String variabilityGpsAccuracy(String meters) {
    return 'GPS accuracy about $meters m';
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
  String get sessionDetailsConditionsHint => 'Dry, 18 °C';

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
  String get taskStopped => 'The work stopped.';

  @override
  String get taskStoppedUnexpectedly => 'The work stopped unexpectedly.';

  @override
  String get lapPageChannels => 'Channels';

  @override
  String get lapPageCursorHintTouch =>
      'Tap a chart or drag sideways across it to move the cursor; the white dot shows it on the map. Two fingers zoom and move the map.';

  @override
  String get lapPageCursorHint =>
      'Drag across a chart to move the cursor; the white dot shows it on the map.';

  @override
  String get lapPageNoChannel => 'No channel shown.';

  @override
  String get lapPageBestOfDay => 'Best lap of the day';

  @override
  String lapPageBestOfSession(String session) {
    return 'Best lap of $session';
  }

  @override
  String lapPageNotRankedExcluded(String reason) {
    return 'Not ranked: excluded (“$reason”)';
  }

  @override
  String get lapPageExclude => 'Exclude from ranking…';

  @override
  String get lapPageInclude => 'Include in ranking';

  @override
  String get lapPageCompareWith => 'Compare with…';

  @override
  String get lapPageNoGps => 'No GPS recorded for this section.';

  @override
  String lapPageTraceLabel(String lap) {
    return 'Trace of $lap, coloured by speed';
  }

  @override
  String get lapPageSpeed => 'Speed';

  @override
  String lapPageShowBest(String lap) {
    return 'Show the best lap ($lap) in grey';
  }

  @override
  String get lapPageExcludeTitle => 'Exclude this lap';

  @override
  String get lapPageReason => 'Reason';

  @override
  String get lapPageReasonHint => 'Traffic, yellow flag…';

  @override
  String get lapPageExcludeAction => 'Exclude';

  @override
  String get compareTitle => 'Compare laps';

  @override
  String get compareLayerNotRecordedEither => 'Not recorded on either lap.';

  @override
  String compareLayerNotRecordedOn(String lap) {
    return 'Not recorded on lap $lap.';
  }

  @override
  String compareLayerNoSamples(String lap) {
    return 'No usable samples on lap $lap.';
  }

  @override
  String get compareNoSharedPosition =>
      'No shared track position for this pair.';

  @override
  String compareLapDelta(String delta) {
    return 'Lap Δ $delta';
  }

  @override
  String get compareDeltaExplained => 'Δ is A − B: positive when A is behind.';

  @override
  String get compareSwap => 'Swap A and B';

  @override
  String compareBestOfSessionAsB(String session) {
    return 'B: best of $session';
  }

  @override
  String get compareBestOfDayAsB => 'B: best of the day';

  @override
  String get compareLayerLine => 'Line: A / B';

  @override
  String compareLayerOptionNotRecorded(String layer) {
    return '$layer · not recorded';
  }

  @override
  String get compareLayerSpeed => 'Speed';

  @override
  String get compareLayerDelta => 'Δ time (A−B)';

  @override
  String get compareLayerLateralG => 'Lateral G';

  @override
  String get compareLayerLongitudinalG => 'Longitudinal G';

  @override
  String get compareLayerThrottle => 'Throttle';

  @override
  String get compareLayerBrake => 'Brake (measured)';

  @override
  String get compareLayerTemperature => 'Temperature';

  @override
  String get compareLayerAAhead => 'A ahead';

  @override
  String get compareLayerABehind => 'A behind';

  @override
  String get compareLayerBraking => 'braking';

  @override
  String get compareLayerAccelerating => 'accelerating';

  @override
  String compareLegendLap(String layer, String lap) {
    return '$layer · lap $lap';
  }

  @override
  String get compareLegendCalculated => 'calculated';

  @override
  String get compareChannelsByPosition => 'Channels by track position';

  @override
  String get compareCursorHintTouch =>
      'Both laps at the same place on the track. Tap a chart or drag sideways across it to move the cursor; the dots show both laps on the map, which two fingers zoom and move.';

  @override
  String get compareCursorHint =>
      'Both laps at the same place on the track. Drag across a chart to move the cursor; the dots show both laps on the map.';

  @override
  String get compareDeltaChart => 'Δ time (A − B)';

  @override
  String get compareDeltaNote => '+ = A behind';

  @override
  String compareOpenLapHere(String lap) {
    return 'Open lap $lap here';
  }

  @override
  String get compareDisclaimer =>
      'Observed differences between two laps, not instructions.';

  @override
  String get compareRecordingsUnavailable =>
      'The recordings of these laps are not available.';

  @override
  String get compareNoGps => 'No GPS data in this section';

  @override
  String get compareMapLabel => 'Laps A and B on one map';

  @override
  String get chartReasonNotRecorded => 'not recorded';

  @override
  String get chartReasonInvalidRange => 'range not valid';

  @override
  String get chartReasonUnreadable => 'could not be read';

  @override
  String get chartNoDataInRange => 'no data in this range';

  @override
  String get chartNoData => 'No data in this range';

  @override
  String chartNotAvailable(String reasons) {
    return 'Not available · $reasons';
  }

  @override
  String get chartBrakingUp => 'braking drawn upward';

  @override
  String chartRemove(String channel) {
    return 'Remove $channel';
  }

  @override
  String chartSemantics(String channel) {
    return '$channel chart';
  }

  @override
  String chartSemanticsRange(String line, String low, String high) {
    return '${line}from $low to $high';
  }

  @override
  String get chartZoomOut => 'Zoom out';

  @override
  String get chartZoomIn => 'Zoom in around the cursor';

  @override
  String get chartWholeLap => 'Whole lap';

  @override
  String chartAtMost(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At most $count charts',
      one: 'At most 1 chart',
    );
    return '$_temp0';
  }

  @override
  String get chartAddChannel => 'Add a channel';

  @override
  String get coastingTitle => 'Coasting';

  @override
  String get coastingBySegment => 'By segment';

  @override
  String get coastingBySegmentLoading =>
      'Coasting by segment follows once the day\'s segments are calculated…';

  @override
  String get coastingBySegmentNeedsSegments =>
      'Coasting by segment needs this lap\'s group to have segments.';

  @override
  String get coastingEpisodes => 'Episodes · select one to see it';

  @override
  String coastingIntoLap(String seconds) {
    return '$seconds s into the lap';
  }

  @override
  String get drivingGgNoLongitudinal => 'No longitudinal G recorded';

  @override
  String get drivingGgNoLateral => 'No lateral G recorded';

  @override
  String get drivingGgUnsupportedUnit => 'G in an unsupported unit';

  @override
  String get drivingGgNoSamples => 'No samples in this stretch';

  @override
  String get drivingNoCoverage => 'Does not cover this stretch';

  @override
  String get drivingNotAvailable => 'Not available';

  @override
  String get drivingMeasured => 'measured';

  @override
  String get drivingCalculatedFromGps => 'calculated from GPS';

  @override
  String get drivingInferred => 'inferred';

  @override
  String get drivingUnexpectedUnit => 'unexpected unit';

  @override
  String get drivingNotRecorded => 'not recorded';

  @override
  String get drivingPedalsUnknown => 'pedals unknown';

  @override
  String get drivingNoSpeed => 'no speed';

  @override
  String get drivingBrakeMeasuredLateralGps =>
      'brake measured, lateral G from GPS';

  @override
  String drivingUnexpectedUnitChannel(String channel) {
    return '$channel is in an unexpected unit';
  }

  @override
  String get drivingNoBrakeChannel => 'no brake channel';

  @override
  String get drivingNoAcceleratorChannel => 'no accelerator channel';

  @override
  String get drivingBrakeRecorded => 'brake pedal recorded';

  @override
  String get drivingBrakingInferred =>
      'braking inferred from deceleration (no brake channel)';

  @override
  String get drivingAcceleratorRecorded => 'accelerator pedal recorded';

  @override
  String get drivingAcceleratingInferred =>
      'accelerating inferred from longitudinal G (no accelerator channel)';

  @override
  String get drivingLateralMeasured => 'lateral G measured';

  @override
  String get drivingLateralCalculated =>
      'lateral G calculated from GPS by the logger';

  @override
  String get drivingNoLateral => 'no lateral G';

  @override
  String get drivingCoastingMeasured =>
      'Measured: from the recorded brake and accelerator pedals.';

  @override
  String get drivingCoastingInferred =>
      'Inferred from longitudinal G: this recording has no brake or no accelerator pedal channel.';

  @override
  String get drivingCoastingNoPedals =>
      'Cannot be told: the recording has neither pedal channels nor longitudinal G.';

  @override
  String get drivingCoastingNoSpeed =>
      'Cannot be told: the recording has no speed.';

  @override
  String get drivingCoastingUnitMismatch =>
      'Cannot be told: a pedal or speed channel is in an unexpected unit.';

  @override
  String get drivingCoastingUnavailable =>
      'Coasting is not available for this stretch.';

  @override
  String drivingCoastingSummaryLap(
    String seconds,
    String meters,
    int count,
    String share,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$seconds s · $meters m over $_temp0 ($share % of the lap)';
  }

  @override
  String drivingCoastingSummaryStretch(
    String seconds,
    String meters,
    int count,
    String share,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count episodes',
      one: '1 episode',
    );
    return '$seconds s · $meters m over $_temp0 ($share % of the stretch)';
  }

  @override
  String get drivingCoastingNote =>
      'Coasting is time at speed with neither pedal pressed. It is not a mistake by itself: a lift can settle the car or be forced by traffic.';

  @override
  String get drivingCoastingEpisodesHint =>
      'Each episode is listed by where it starts on the track; select one to move the cursor there.';

  @override
  String drivingSelectedStretch(String meters) {
    return 'Selected stretch · $meters m';
  }

  @override
  String get drivingWholeLap => 'Whole lap';

  @override
  String get drivingGgCalculated => 'calculated from GPS by the logger';

  @override
  String drivingGgSource(
    String lap,
    String longitudinal,
    String lateral,
    String provenance,
  ) {
    return '$lap: $longitudinal / $lateral, $provenance';
  }

  @override
  String drivingLap(String lap) {
    return 'Lap $lap';
  }

  @override
  String drivingGgSemantics(String a, String b) {
    return 'G-G diagram of laps A and B: peak combined $a and $b';
  }

  @override
  String get drivingPeakLateral => 'Peak lateral';

  @override
  String get drivingPeakBraking => 'Peak braking';

  @override
  String get drivingPeakAccelerating => 'Peak accelerating';

  @override
  String get drivingPeakCombined => 'Peak combined';

  @override
  String get drivingSamples => 'Samples';

  @override
  String get drivingGgNote =>
      'Observed accelerations, not a share of available grip. Rings every 0.5 g; a circle marks each lap\'s peaks.';

  @override
  String get drivingGgAccelerating => 'accelerating';

  @override
  String get drivingGgBraking => 'braking';

  @override
  String get drivingGgLeft => 'left';

  @override
  String get drivingGgRight => 'right';

  @override
  String drivingStripLabel(String lap) {
    return 'Lap $lap along the track';
  }

  @override
  String get drivingStripHint => 'Tap to move the cursor there';

  @override
  String get drivingStatesTitle => 'Driving states';

  @override
  String get drivingBraking => 'Braking';

  @override
  String get drivingTrailBraking => 'Braking while cornering';

  @override
  String get drivingCornering => 'Cornering';

  @override
  String get drivingAccelerating => 'Accelerating';

  @override
  String get drivingCoasting => 'Coasting';

  @override
  String get drivingStatesNote =>
      'Each lap\'s share of its own time over this stretch. States overlap: cornering can come with braking, accelerating or coasting. Tap a strip to move the cursor there. Longer braking while cornering is not automatically better or safer.';

  @override
  String get cornerDetailsReasonNotMeasured => 'not measured';

  @override
  String get cornerDetailsReasonNoBraking => 'no braking detected';

  @override
  String get cornerDetailsReasonNoBrakeOrDeceleration =>
      'no brake or deceleration channel';

  @override
  String get cornerDetailsReasonNoBrakeChannel => 'no brake channel';

  @override
  String get cornerDetailsReasonNoDecelerationChannel =>
      'no deceleration channel';

  @override
  String get cornerDetailsReasonApproachClipped =>
      'approach cut off at the start/finish line';

  @override
  String get cornerDetailsReasonApproachInPreviousCorner =>
      'approach runs into the previous corner';

  @override
  String get cornerDetailsReasonAlreadyBraking =>
      'already braking before the approach';

  @override
  String get cornerDetailsReasonBrakingGap =>
      'braking interrupted by a recording gap';

  @override
  String get cornerDetailsReasonNoSamplesHere => 'no samples here';

  @override
  String get cornerDetailsReasonNoThrottleOrAcceleration =>
      'no throttle or acceleration channel';

  @override
  String get cornerDetailsReasonNoLift => 'no lift before the pickup';

  @override
  String get cornerDetailsReasonNoPickup => 'no pickup detected';

  @override
  String get cornerDetailsReasonAfterGap => 'after a recording gap';

  @override
  String get cornerDetailsReasonCutAtLapEnd => 'cut off at the lap end';

  @override
  String get cornerDetailsReasonNotCovered => 'lap not fully covered here';

  @override
  String get cornerDetailsReasonCrossesGate => 'crosses the start/finish line';

  @override
  String get cornerDetailsReasonUnitNotSupported =>
      'channel unit not supported';

  @override
  String get cornerDetailsReasonUnitNotRecorded => 'channel unit not recorded';

  @override
  String get cornerDetailsReasonNoSpeedChannel => 'no speed channel';

  @override
  String get cornerDetailsReasonMixedProvenance =>
      'measured differently on A and B';

  @override
  String get cornerDetailsReasonSegmentsDiffer =>
      'segments differ between the laps';

  @override
  String get cornerDetailsReasonDoubleApex =>
      'double apex: no single apex point';

  @override
  String get cornerDetailsReasonFlatSpeed => 'no lowest point (constant speed)';

  @override
  String get cornerDetailsReasonUnclearGeometry =>
      'corner shape too unclear to place it';

  @override
  String get cornerDetailsReasonInvalidInput => 'corner could not be measured';

  @override
  String get cornerDetailsReasonBroadApex => 'apex spread over a long arc';

  @override
  String get cornerDetailsReasonAtBoundary => 'at the edge of the corner';

  @override
  String get cornerDetailsReasonNotACorner => 'not a corner';

  @override
  String get cornerDetailsReasonSparseSamples => 'too few samples';

  @override
  String get cornerDetailsReasonSegmentNotFound =>
      'segment not found on this lap';

  @override
  String get cornerDetailsReasonNotRecorded => 'not recorded';

  @override
  String get cornerDetailsReasonNoValidSamples => 'no valid samples';

  @override
  String get cornerDetailsReasonNoReference => 'no reference lap';

  @override
  String get cornerDetailsReasonNotTimed => 'not timed';

  @override
  String get cornerDetailsReasonNoApprovedSegments => 'no approved segments';

  @override
  String get cornerDetailsReasonDrivingStateUnknown => 'driving state unknown';

  @override
  String get cornerDetailsReasonNotAvailable => 'not available';

  @override
  String get cornerDetailsFromDeceleration => 'Inferred from deceleration';

  @override
  String get cornerDetailsFromBrakeChannel => 'From the brake channel';

  @override
  String get cornerDetailsFromAcceleration => 'Inferred from acceleration';

  @override
  String get cornerDetailsFromThrottleChannel => 'From the throttle channel';

  @override
  String cornerDetailsBestMeasuredDifferently(String how) {
    return '$how; the best lap was measured differently';
  }

  @override
  String get cornerDetailsBestSpeedDifferent =>
      'The best lap’s speed was recorded differently';

  @override
  String cornerDetailsMinimumMissing(String reason) {
    return 'Minimum: $reason';
  }

  @override
  String get cornerDetailsHighestMinimumSpeed => 'Highest minimum speed';

  @override
  String get cornerDetailsHighestExitSpeed => 'Highest exit speed';

  @override
  String get cornerDetailsLatestBrakingPoint => 'Latest braking point';

  @override
  String get cornerDetailsEarliestPickup => 'Earliest throttle pickup';

  @override
  String cornerDetailsMetresIn(int metres) {
    return '$metres m in';
  }

  @override
  String cornerDetailsIsBestLap(String lap) {
    return '$lap · the best lap';
  }

  @override
  String cornerDetailsAgainstBestLap(String lap, String best) {
    return '$lap against the best lap, $best';
  }

  @override
  String get cornerDetailsBestLapUnavailable => 'unavailable';

  @override
  String get cornerDetailsThisLap => 'This lap';

  @override
  String get cornerDetailsBestLap => 'Best lap';

  @override
  String cornerDetailsEntrySpeed(String unit) {
    return 'Entry speed$unit';
  }

  @override
  String cornerDetailsMinimumSpeed(String unit) {
    return 'Minimum speed$unit';
  }

  @override
  String cornerDetailsExitSpeed(String unit) {
    return 'Exit speed$unit';
  }

  @override
  String get cornerDetailsBrakingPoint => 'Braking point, before the corner';

  @override
  String get cornerDetailsBrakingTime => 'Braking time';

  @override
  String cornerDetailsPeakDeceleration(String unit) {
    return 'Peak deceleration$unit';
  }

  @override
  String get cornerDetailsPickup => 'Throttle pickup, into the corner';

  @override
  String cornerDetailsBestOfLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Best of $count laps',
      one: 'Best of 1 lap',
    );
    return '$_temp0';
  }

  @override
  String get cornerDetailsExplanation =>
      'Braking point and pickup are distances from the corner’s start on the shared track axis. Later braking or an earlier pickup is not automatically faster. Laps measured another way are not compared.';

  @override
  String cornerDetailsNotMeasured(String corner) {
    return '$corner: this lap was not measured here.';
  }

  @override
  String get cornerAnalyzerTypeCorner => 'corner';

  @override
  String get cornerAnalyzerTypeStraight => 'straight';

  @override
  String get cornerAnalyzerTypeSector => 'sector';

  @override
  String cornerAnalyzerNoteProposed(String lap) {
    return 'Segments proposed from $lap, as used by the sector theoretical best; saving the day approves them. Boundaries are distances along that lap\'s axis, so they can shift by a few metres on these laps.';
  }

  @override
  String cornerAnalyzerNoteApproved(String session) {
    return 'Segments approved on $session, as used by the sector theoretical best. Boundaries are distances along that run\'s axis, so they can shift by a few metres on these laps.';
  }

  @override
  String get cornerAnalyzerSummarySame => 'A and B take the same time here.';

  @override
  String cornerAnalyzerSummaryFaster(String lap, String time) {
    return '$lap is $time faster here.';
  }

  @override
  String cornerAnalyzerSummaryEntry(String lap, String time, String speed) {
    return '$lap is $time faster here and carries $speed more entry speed.';
  }

  @override
  String cornerAnalyzerSummaryMinimum(String lap, String time, String speed) {
    return '$lap is $time faster here and carries $speed more minimum speed.';
  }

  @override
  String cornerAnalyzerSummaryLowest(String lap, String time, String speed) {
    return '$lap is $time faster here and carries $speed more lowest speed.';
  }

  @override
  String cornerAnalyzerSummaryExit(String lap, String time, String speed) {
    return '$lap is $time faster here and carries $speed more exit speed.';
  }

  @override
  String get cornerAnalyzerTitle => 'Corner Analyzer';

  @override
  String get cornerAnalyzerEmpty =>
      'No matching approved segments for these two laps. Approve the same track segmentation on both to use the Corner Analyzer.';

  @override
  String get cornerAnalyzerUseTheoreticalBest =>
      'Use the theoretical best’s segments';

  @override
  String get cornerAnalyzerPrevious => 'Previous segment';

  @override
  String get cornerAnalyzerNext => 'Next segment';

  @override
  String get cornerAnalyzerNoChart =>
      'No speed chart: this segment crosses the start/finish line.';

  @override
  String get cornerAnalyzerNoFigures => 'No figures for this segment.';

  @override
  String cornerAnalyzerHeartRateNote(String a, String b) {
    return 'Heart rate: mean over this segment · A $a · B $b. Observed values only.';
  }

  @override
  String cornerAnalyzerCoverage(int count, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count samples, $percent% covered',
      one: '1 sample, $percent% covered',
    );
    return '$_temp0';
  }

  @override
  String get cornerAnalyzerExplanation =>
      'Δ is A − B, coloured by the lap that is faster or carries more speed. Observed differences, not instructions.';

  @override
  String get cornerAnalyzerExplanationWithBraking =>
      'Δ is A − B, coloured by the lap that is faster or carries more speed. Braking and pickup are distances from the corner entry; braking later or picking up earlier is not automatically faster. Observed differences, not instructions.';

  @override
  String get cornerAnalyzerZoom => 'Zoom to segment';

  @override
  String cornerAnalyzerOpenLap(String lap) {
    return 'Lap $lap here';
  }

  @override
  String get cornerAnalyzerGroupTime => 'Time';

  @override
  String get cornerAnalyzerGroupBraking => 'Braking';

  @override
  String get cornerAnalyzerGroupCorner => 'Corner';

  @override
  String get cornerAnalyzerGroupSpeed => 'Speed';

  @override
  String get cornerAnalyzerGroupExit => 'Exit';

  @override
  String get cornerAnalyzerGroupDriver => 'Driver';

  @override
  String get cornerAnalyzerTimeThroughCorner => 'Time through the corner';

  @override
  String get cornerAnalyzerSectorTime => 'Sector time';

  @override
  String get cornerAnalyzerBrakingPoint => 'Braking starts, before entry';

  @override
  String get cornerAnalyzerBrakingTime => 'Time on the brakes';

  @override
  String get cornerAnalyzerPeakDeceleration => 'Peak deceleration';

  @override
  String get cornerAnalyzerEntrySpeed => 'Entry speed';

  @override
  String get cornerAnalyzerApexSpeed => 'Apex speed';

  @override
  String get cornerAnalyzerMinimumSpeed => 'Minimum speed';

  @override
  String get cornerAnalyzerTopSpeed => 'Top speed';

  @override
  String get cornerAnalyzerLowestSpeed => 'Lowest speed';

  @override
  String get cornerAnalyzerExitSpeed => 'Exit speed';

  @override
  String get cornerAnalyzerPickup => 'Throttle pickup, after entry';

  @override
  String get cornerAnalyzerHeartRate => 'Heart rate';

  @override
  String get cornerAnalyzerAHigher => 'A higher';

  @override
  String get cornerAnalyzerBHigher => 'B higher';

  @override
  String get cornerAnalyzerAFaster => 'A faster';

  @override
  String get cornerAnalyzerBFaster => 'B faster';

  @override
  String get cornerAnalyzerABrakesEarlier => 'A brakes earlier';

  @override
  String get cornerAnalyzerABrakesLater => 'A brakes later';

  @override
  String get cornerAnalyzerALonger => 'A longer';

  @override
  String get cornerAnalyzerAShorter => 'A shorter';

  @override
  String get cornerAnalyzerAHarder => 'A harder';

  @override
  String get cornerAnalyzerASofter => 'A softer';

  @override
  String get cornerAnalyzerALater => 'A later';

  @override
  String get cornerAnalyzerAEarlier => 'A earlier';

  @override
  String get cornerAnalyzerSame => 'same';

  @override
  String get cornerAnalyzerInferred => 'inferred';

  @override
  String cornerAnalyzerBothLaps(String reason) {
    return '$reason (both laps)';
  }

  @override
  String cornerAnalyzerNotCompared(String reason) {
    return 'Not compared: $reason';
  }

  @override
  String get cornerAnalyzerUnitNoteSpeed =>
      'This recording does not declare its speed unit: those values are shown as recorded, without a unit.';

  @override
  String get cornerAnalyzerUnitNoteDeceleration =>
      'This recording does not declare its deceleration unit: those values are shown as recorded, without a unit.';

  @override
  String get cornerAnalyzerUnitNoteBoth =>
      'This recording does not declare its speed and deceleration units: those values are shown as recorded, without a unit.';

  @override
  String get cornerAnalyzerChartNoSpeed =>
      'No speed recorded on either lap: no speed chart.';

  @override
  String cornerAnalyzerChartNoSamples(String segment) {
    return 'No speed samples on either lap through $segment.';
  }

  @override
  String cornerAnalyzerChartTitle(String segment) {
    return 'Speed through $segment';
  }

  @override
  String cornerAnalyzerChartLabel(String segment) {
    return 'Speed through $segment chart';
  }

  @override
  String cornerAnalyzerCursor(String offset) {
    return 'Cursor $offset m: ';
  }

  @override
  String get cornerAnalyzerEntry => 'Entry';

  @override
  String get cornerAnalyzerExit => 'Exit';

  @override
  String get cornerAnalyzerStart => 'Start';

  @override
  String get cornerAnalyzerEnd => 'End';

  @override
  String get cornerAnalyzerSpeedAxis => 'speed';

  @override
  String get cornerAnalyzerApex => 'Apex';

  @override
  String get cornerAnalyzerAxisCorner =>
      'Distance from the corner entry (m) · shaded: the corner';

  @override
  String get cornerAnalyzerAxisSegment =>
      'Distance from the segment entry (m) · shaded: the segment';

  @override
  String cornerAnalyzerAxisNoUnit(String axis) {
    return '$axis · speed unit not declared in the recording';
  }

  @override
  String get cornerAnalyzerLegendBraking => 'Braking starts';

  @override
  String get cornerAnalyzerLegendPickup => 'Throttle pickup';

  @override
  String get cornerAnalyzerLegendMinimum => 'Lowest speed';

  @override
  String importPageLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count laps',
      one: '1 lap',
    );
    return '$_temp0';
  }

  @override
  String get importPageNoGate =>
      'No laps: the recording has no start/finish line.';

  @override
  String get importPageSeveralGates =>
      'No laps: the recording has more than one start/finish line.';

  @override
  String get importPageInvalidGate =>
      'No laps: the start/finish line is not valid.';

  @override
  String get importPageNoGps => 'No laps: the recording has no usable GPS.';

  @override
  String get importPageTooFewPasses =>
      'No complete laps: the start/finish line was not crossed often enough.';

  @override
  String importPageImportFailed(String error) {
    return 'The import failed: $error';
  }

  @override
  String importPageFolderTooMany(int count, int maximum) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'The folder holds $count recordings; import at most $maximum at a time. Choose a smaller folder.',
    );
    return '$_temp0';
  }

  @override
  String importPageTooMany(int count, int maximum) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'That is $count recordings; import at most $maximum at a time.',
    );
    return '$_temp0';
  }

  @override
  String importPageStoppedAfter(int count) {
    return 'Stopped after $count files and folders; recordings beyond that were not scanned.';
  }

  @override
  String importPageTooDeep(int count, int depth) {
    return '$count folder(s) deeper than $depth levels were not scanned.';
  }

  @override
  String importPageLinksSkipped(int count) {
    return '$count link(s) were not followed.';
  }

  @override
  String importPageOtherFilesSkipped(int count) {
    return '$count other file(s) were ignored; only VBO and RCZ recordings are imported.';
  }

  @override
  String importPageSameContent(String other) {
    return 'same content as $other; imported once.';
  }

  @override
  String importPageSameDrive(String other) {
    return 'the same drive as $other; kept as its alternative source.';
  }

  @override
  String get importPageNoRecording => 'No recording could be imported.';

  @override
  String get importPageFailed => 'Import failed.';

  @override
  String get importPageStoppedUnexpectedly =>
      'Bad state: The import stopped unexpectedly.';

  @override
  String get importPageNoFolder =>
      'The folder does not exist or is not a folder.';

  @override
  String get importPageFolderLink =>
      'Choose the folder itself, not a link to it.';

  @override
  String get importPageNoneFound => 'No VBO or RCZ recordings were found.';

  @override
  String get importPageNoneFoundNoSubfolders =>
      'No VBO or RCZ recordings were found (subfolders were not included).';

  @override
  String get importPageNothingToImport => 'No VBO or RCZ recordings to import.';

  @override
  String get importPageFileNotFound => 'not found; not imported.';

  @override
  String get importPageMetadataFile =>
      'a macOS metadata file, not a recording; not imported.';

  @override
  String get importPageFileLink => 'a link; not followed.';

  @override
  String get importPageNotRecording =>
      'not a VBO or RCZ recording; not imported.';

  @override
  String importPageNotRestored(String error) {
    return 'The day could not be restored: $error';
  }

  @override
  String importPageDiscardTitle(String day) {
    return 'Discard the changes to $day?';
  }

  @override
  String get importPageDiscardBody =>
      'The unsaved changes are lost. Recordings and saved days are not touched.';

  @override
  String get importPageKeep => 'Keep';

  @override
  String get importPageDiscard => 'Discard';

  @override
  String importPageNotDiscarded(String error) {
    return 'Not discarded: $error';
  }

  @override
  String importPageCannotOpenTitle(String day) {
    return '$day could not be opened';
  }

  @override
  String get importPageNoneUsable => 'None of its recordings could be used:';

  @override
  String get importPageChooseFolderHint =>
      'Choose the folder the recordings are in to use them, also when they have not moved.';

  @override
  String get importPageImportingBehind =>
      'Importing the shared recordings. Go back to Import sessions to see them.';

  @override
  String get importPageOpenSavedTitle => 'Open a saved day';

  @override
  String get importPageAnotherFile => 'Another file…';

  @override
  String get importPageAnotherOpening =>
      'Another day is being opened. Try again after it.';

  @override
  String importPageNotOpened(String error) {
    return 'The day could not be opened: $error';
  }

  @override
  String get importPageTitle => 'Import sessions';

  @override
  String importPageUnsaved(String day, String time) {
    return '$day has unsaved changes from $time.';
  }

  @override
  String get importPageRestore => 'Restore';

  @override
  String get importPageDiscardEllipsis => 'Discard…';

  @override
  String get importPageIntroDrop =>
      'Choose the VBO or RCZ recording of each session as you drive, or a folder with a whole day, or drop them here. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.';

  @override
  String get importPageIntroFolder =>
      'Choose the VBO or RCZ recording of each session as you drive, or a folder with a whole day. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.';

  @override
  String get importPageIntro =>
      'Choose the VBO or RCZ recording of each session as you drive. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.';

  @override
  String get importPageChooseRecordings => 'Import sessions…';

  @override
  String get importPageChooseFolder => 'Choose a folder…';

  @override
  String get importPageOpening => 'Opening…';

  @override
  String get importPageOpenSaved => 'Open a saved day…';

  @override
  String get importPageProgress => 'Importing recordings';

  @override
  String get importPageChooseAgain =>
      'Choose the recordings again, or other ones, above.';

  @override
  String get importPageIncludeSubfolders => 'Include subfolders';

  @override
  String get importPageNotes => 'Import notes';

  @override
  String get importPageLooking => 'Looking for recordings…';

  @override
  String importPagePreparing(int number, int total) {
    return 'Preparing recording $number of $total…';
  }

  @override
  String get importPageCancelled => 'Import cancelled. Nothing was imported.';

  @override
  String importPageSessionsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions imported',
      one: '1 session imported',
    );
    return '$_temp0';
  }

  @override
  String get importPageShowResults => 'Open the day';

  @override
  String importPageDayUnsaved(String time) {
    return 'Not saved yet; changes kept from $time.';
  }

  @override
  String importPageDaySaved(String file) {
    return 'Saved as $file.';
  }

  @override
  String get importPageDayNotKept => 'Not saved.';

  @override
  String get importPageOpeningDay => 'Opening the day…';

  @override
  String get importPageRecordingTypes => 'VBO and RCZ recordings';

  @override
  String get importPageImportThisFolder => 'Import this folder';

  @override
  String get importPageChooseFile =>
      'Choose a VBO or RaceChrono RCZ telemetry file.';

  @override
  String get importPageNotRegularFile =>
      'Telemetry source is not an existing regular file.';

  @override
  String get importPageTooManyFiles =>
      'Too many files in one import; select a smaller batch.';

  @override
  String get importPagePathTooLong => 'Telemetry source path is too long.';

  @override
  String get importPageFileSize =>
      'Telemetry file is empty or exceeds the per-file import limit.';

  @override
  String get importPageBatchBytes =>
      'Batch input-byte limit exceeded; import fewer recordings.';

  @override
  String get importPageIdenticalContent =>
      'Identical file content already present in this batch.';

  @override
  String get importPageSourceChanged =>
      'Telemetry source changed during import; retry with a stable file.';

  @override
  String get importPageInvalidTimeRange =>
      'Telemetry source has an invalid time range.';

  @override
  String get importPageMismatchedChannels =>
      'Telemetry source has mismatched channel timestamps and values.';

  @override
  String get importPageBatchSamples =>
      'Batch decoded-sample limit exceeded; import fewer recordings.';

  @override
  String get importPageGroupingLimit =>
      'Source grouping exceeds the import limit.';

  @override
  String get segmentReviewOpen => 'Review proposals';

  @override
  String get segmentReviewTitle => 'Segment proposals';

  @override
  String get segmentReviewUndo => 'Undo';

  @override
  String get segmentReviewRedo => 'Redo';

  @override
  String get segmentReviewIntro =>
      'Segments are approved automatically, so this review is optional. A rejected proposal stays out of Approve all and is saved with the day.';

  @override
  String segmentReviewSummary(int count, String lap) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count proposals from $lap',
      one: '1 proposal from $lap',
    );
    return '$_temp0';
  }

  @override
  String get segmentReviewApproveAll => 'Approve all';

  @override
  String get segmentReviewRecompute => 'Recompute';

  @override
  String segmentReviewApproved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count proposals approved',
      one: '1 proposal approved',
    );
    return '$_temp0';
  }

  @override
  String get segmentReviewNoneApproved => 'No proposal could be approved.';

  @override
  String get segmentReviewReject => 'Reject';

  @override
  String get segmentReviewRestore => 'Restore';

  @override
  String get segmentReviewStateProposed => 'Proposed';

  @override
  String get segmentReviewStateApproved => 'Approved';

  @override
  String get segmentReviewStateRejected => 'Rejected';

  @override
  String get segmentReviewStateSuperseded => 'Overlaps approved';

  @override
  String get segmentReviewCorner => 'Corner';

  @override
  String get segmentReviewStraight => 'Straight';

  @override
  String get segmentReviewSector => 'Sector';

  @override
  String segmentReviewTurnLeft(String degrees) {
    return '$degrees° left';
  }

  @override
  String segmentReviewTurnRight(String degrees) {
    return '$degrees° right';
  }

  @override
  String segmentReviewBounds(
    String start,
    String startTolerance,
    String end,
    String endTolerance,
    String length,
  ) {
    return '$start m ±$startTolerance → $end m ±$endTolerance ($length m)';
  }

  @override
  String get segmentReviewCrossesLine => 'Crosses start/finish';

  @override
  String segmentReviewStartUncertain(String reasons) {
    return 'Start uncertain: $reasons';
  }

  @override
  String segmentReviewEndUncertain(String reasons) {
    return 'End uncertain: $reasons';
  }

  @override
  String get segmentReviewConnectedCorners =>
      'Corners connect without a straight';

  @override
  String get segmentReviewShortStraight => 'Short straight';

  @override
  String get segmentReviewGpsGap => 'Near a GPS gap in this lap';

  @override
  String segmentReviewApex(String at, String tolerance) {
    return 'Geometric apex $at m ±$tolerance m';
  }

  @override
  String get segmentReviewApexMultiple => 'Multiple apexes — review manually';

  @override
  String get segmentReviewApexCrossesGate => 'Corner crosses the timing gate';

  @override
  String get segmentReviewApexUnresolved => 'Apex unresolved';

  @override
  String get segmentReviewWaiting => 'Timing every lap on one track axis…';

  @override
  String get segmentReviewComputing => 'Finding corners and straights…';

  @override
  String get segmentReviewNoLap =>
      'The lap the segments are measured on is not available.';

  @override
  String get segmentReviewNoAxis =>
      'This lap\'s GPS trace cannot be made into a track axis.';

  @override
  String get segmentReviewContinuousCorner =>
      'No automatic proposal: this lap turns continuously, with no straight between corners.';

  @override
  String get segmentReviewNoCorners =>
      'No automatic proposal: no corner was detected on this lap.';

  @override
  String segmentReviewTooMany(int count) {
    return 'No automatic proposal: the lap would split into more than $count segments.';
  }

  @override
  String get segmentReviewFailed => 'The proposals could not be computed.';

  @override
  String get segmentReviewSaving =>
      'The day is being saved. Try again in a moment.';

  @override
  String get segmentReviewSegmentsUnavailable =>
      'The segments can be changed once the theoretical best is calculated.';

  @override
  String get segmentReviewNotReady => 'The proposals are not ready yet.';

  @override
  String get segmentReviewNoLongerAvailable =>
      'This proposal is no longer available.';

  @override
  String get segmentReviewNotOpen => 'Only open proposals can be rejected.';

  @override
  String get segmentReviewNotStored => 'The rejection cannot be stored.';

  @override
  String get segmentReviewNothingToUndo => 'Nothing to undo.';

  @override
  String get segmentReviewNothingToRedo => 'Nothing to redo.';

  @override
  String get segmentReviewHistoryCleared =>
      'The segments changed outside this editor, so the edit history was cleared.';

  @override
  String get segmentReviewUncertainOther => 'Uncertain boundary';

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
    return 'Clock drift: $ppm ppm';
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
    return 'This session reads its VBO and keeps its RCZ, and the day\'s file cannot keep a refusal for such a session: when the day is opened again, the $alternative is lined up and combined again.';
  }

  @override
  String get recordingsClockFailed =>
      'The clocks could not be compared. Try again.';

  @override
  String recordingsPrimaryMissing(String format) {
    return 'The $format is no longer where it was read from. Put it back there, then make it primary.';
  }

  @override
  String recordingsPrimaryChanged(String format) {
    return 'The $format file has changed since it was read. Open the day again, then make it primary.';
  }

  @override
  String recordingsPrimaryFailed(String format) {
    return 'The $format could not be read as this session\'s recording.';
  }

  @override
  String get recordingsBusyFind =>
      'Wait until the session\'s recordings are checked or changed, then find the others.';

  @override
  String get recordingsBusyRetry =>
      'Wait until the session\'s recordings are checked or changed, then retry.';

  @override
  String get recordingsBusyLeave =>
      'Wait until the session\'s recordings are checked or changed.';

  @override
  String get recordingsUnsaved =>
      'Save the day before changing the primary recording.';

  @override
  String get recordingsBusyAdd =>
      'Wait until the session\'s recordings are checked or changed, then add recordings.';

  @override
  String get lapPageThisLap => 'This lap';

  @override
  String lapPageGapToBest(String delta) {
    return '$delta to the best of the day';
  }

  @override
  String get importPageBest => 'Best';

  @override
  String get mapBackgroundMenu => 'Map background';

  @override
  String get mapBackgroundStreets => 'Streets';

  @override
  String get mapBackgroundSatellite => 'Satellite';

  @override
  String get mapBackgroundApple => 'Apple Maps';

  @override
  String get mapBackgroundPlain => 'Plain';

  @override
  String get documentPickerDays => 'FlappedEar day';

  @override
  String get documentPickerLookInFolder => 'Look in this folder';

  @override
  String get speedLegendNoSpeed =>
      'No speed recorded; the trace is drawn in one colour.';

  @override
  String get appErrorNotice =>
      'Something went wrong. Details are in Diagnostics.';

  @override
  String get appErrorPart => 'This part could not be shown.';

  @override
  String get diagnosticsErrors => 'Errors';

  @override
  String get diagnosticsNoErrors => 'No errors since the app started.';

  @override
  String get diagnosticsCopyErrors => 'Copy errors';

  @override
  String get diagnosticsErrorsCopied =>
      'Errors copied. Paste them into a bug report.';

  @override
  String diagnosticsErrorsDropped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count earlier errors not kept',
      one: '1 earlier error not kept',
    );
    return '$_temp0';
  }

  @override
  String importUnexpectedError(String error) {
    return 'Unexpected error while reading this file: $error';
  }

  @override
  String noteUnexpectedError(String error) {
    return 'Unexpected error while analysing this session: $error';
  }

  @override
  String diagnosticsErrorCount(int count) {
    return '$count times';
  }

  @override
  String get reviewImportTitle => 'Review the import';

  @override
  String get reviewImportIntro =>
      'Choose what happens to each recording. Nothing is imported until you confirm.';

  @override
  String get addAndReviewRecordings => 'Add and review recordings…';

  @override
  String get reviewChoiceNewSession => 'Import as a new session';

  @override
  String get reviewChoiceSkip => 'Skip this file';

  @override
  String reviewChoiceSameRunAs(String name) {
    return 'Same run as $name';
  }

  @override
  String reviewRecordingSummary(String duration, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count complete laps',
      one: '1 complete lap',
      zero: 'no complete laps',
    );
    return '$duration · $_temp0';
  }

  @override
  String reviewDuplicate(String name) {
    return 'Same content as $name; imported once.';
  }

  @override
  String reviewFailed(String reason) {
    return 'Not imported: $reason';
  }

  @override
  String get reviewAlreadyInDay => 'Already in this day; skipped.';

  @override
  String reviewPossibleSameRun(String name) {
    return 'Possibly the same run as $name: the GPS traces agree.';
  }

  @override
  String get reviewDestinationAppend => 'Add to this day';

  @override
  String get reviewDestinationNewDay => 'Start a new day';

  @override
  String get reviewNewDayNeedsSave =>
      'Save this day before starting a new one.';

  @override
  String get reviewSameRunHint =>
      'Two exports of the same run? Choose “Same run as”. The session\'s laps come from the file you link to; the other file is kept with it as its alternative recording.';

  @override
  String get reviewConfirmImport => 'Import';

  @override
  String get reviewConfirmAdd => 'Add to the day';

  @override
  String get reviewConfirmNewDay => 'Start the new day';

  @override
  String reviewSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new sessions',
      one: '1 new session',
      zero: 'No new session',
    );
    return '$_temp0';
  }

  @override
  String get reviewProblemTarget =>
      'A file is the same run as a file that is not imported as a session of its own.';

  @override
  String get reviewProblemTooMany =>
      'A session keeps one other recording at most.';

  @override
  String get reviewProblemNothing => 'Choose at least one file to import.';

  @override
  String get reviewChoicesRefused =>
      'These choices cannot be added, so nothing was added. Review the recordings again.';

  @override
  String get waitUntilRecordingsSaved =>
      'Wait until the recordings are lined up and the day is saved.';

  @override
  String get reviewChanged =>
      'The recordings changed after the review, so nothing was imported. Review them again.';

  @override
  String get reviewPreparing => 'Preparing the review…';

  @override
  String get importBusy =>
      'Finish the current import first. Nothing was imported.';

  @override
  String coreVboOpenFailed(String detail) {
    return 'Could not open VBO: $detail';
  }

  @override
  String coreVboReadFailed(String detail) {
    return 'Could not read VBO: $detail';
  }

  @override
  String coreVboUnreadable(String detail) {
    return '$detail';
  }

  @override
  String get coreVboNoData => 'VBO has no [data] rows.';

  @override
  String get coreVboNoValidRows =>
      'VBO contains no valid timestamped data rows.';

  @override
  String get coreVboFileSize =>
      'VBO exceeds the supported 128 MiB file size limit.';

  @override
  String get coreVboComplexity =>
      'VBO text exceeds the supported complexity limit.';

  @override
  String get coreVboTooManyValues =>
      'VBO has more values (rows x columns) than the supported 40 million.';

  @override
  String get coreVboLongLine =>
      'VBO contains a line longer than the supported 1 MiB limit.';

  @override
  String get coreVboTooManyLines => 'VBO contains too many lines.';

  @override
  String get coreVboLongSectionName =>
      'VBO contains a section name longer than the supported 256 characters.';

  @override
  String get coreVboTooManyRows => 'VBO contains too many data rows.';

  @override
  String get coreVboHeaderSize =>
      'VBO header metadata exceeds the supported size.';

  @override
  String get coreVboTooManyColumns => 'VBO contains too many columns.';

  @override
  String get coreVboLongField =>
      'VBO contains a field longer than the supported 64 KiB limit.';

  @override
  String coreRczUnreadable(String detail) {
    return 'RCZ: $detail';
  }

  @override
  String coreRczMissing(String name) {
    return 'Missing $name.';
  }

  @override
  String coreRczMemberTooLarge(String name) {
    return '$name exceeds its size limit.';
  }

  @override
  String get coreRczArchiveSize => 'Archive size is unsupported.';

  @override
  String get coreRczZip64 =>
      'Unsupported ZIP64, split archive or directory limits.';

  @override
  String get coreRczSymlinks => 'Symbolic links are unsupported.';

  @override
  String get coreRczDuplicateMember =>
      'Duplicate member or archive resource limit exceeded.';

  @override
  String get coreRczTruncated => 'Truncated archive.';

  @override
  String get coreRczMetadataNesting =>
      'Metadata nesting/string limit exceeded.';

  @override
  String get coreRczMetadataArray => 'Metadata array limit exceeded.';

  @override
  String get coreRczMetadataObject => 'Metadata object limit exceeded.';

  @override
  String get coreRczMultiSession =>
      'Multi-session or resumed archives are not supported; share one uninterrupted session.';

  @override
  String get coreRczSessionVersion => 'Unsupported session version.';

  @override
  String get coreRczResumed => 'Resumed sessions are not supported yet.';

  @override
  String get coreRczMultiplePositions =>
      'Multiple position channels are unsupported.';

  @override
  String coreRczMultipleSources(String channel) {
    return 'Multiple sources for $channel are unsupported.';
  }

  @override
  String get coreRczGpsMissing => 'Declared GPS channels are missing.';

  @override
  String get coreRczTimestamps =>
      'Timestamp channel is nonmonotonic or outside the supported 24-hour session.';

  @override
  String get coreRczChannelBudget => 'Decoded channel/sample budget exceeded.';

  @override
  String get coreRczGapBudget => 'Decoded gap/sample budget exceeded.';

  @override
  String get coreRczTooManyGates => 'Too many timing gates.';

  @override
  String get coreRczInvalidGate =>
      'Invalid timing gate coordinates or geometry.';

  @override
  String get coreRczInvalidGateEndpoint => 'Invalid timing gate endpoint.';

  @override
  String get coreSourceIdentitySize =>
      'Telemetry file exceeds the content identity size limit.';

  @override
  String get coreSourceCannotRead => 'Cannot read telemetry source.';

  @override
  String get coreSourceChangedWhileReading =>
      'Telemetry source changed while reading; retry with a stable file.';

  @override
  String get coreSourceReadFailed =>
      'Telemetry source read failed or was truncated.';

  @override
  String get coreDayTooManyRecordings => 'Too many recordings in this day.';

  @override
  String get coreDayLapSectionLimit =>
      'This day exceeds the 20,000 lap-section limit.';

  @override
  String get coreRouteTooManyTraces =>
      'Too many lap traces for route inference.';

  @override
  String get coreRouteTooManyRuns => 'Too many runs for route grouping.';

  @override
  String get coreProgressionTooMany =>
      'Too many runs or lap sections for progression.';

  @override
  String get coreRecordingTooManyLapSections =>
      'Too many lap sections in this recording.';

  @override
  String get coreDayTooManyLapSections => 'Too many lap sections in this day.';

  @override
  String get coreRankingTooMany =>
      'Too many laps or exclusions to rank this day.';

  @override
  String get coreTooManyPasses =>
      'Lap detector produced too many accepted passes.';

  @override
  String get coreTooManyGpsPoints => 'Lap traces contain too many GPS points.';

  @override
  String get additionAlreadyInDay => 'already in this day.';

  @override
  String additionSameDriveKept(String session) {
    return 'the same drive as $session in the other format; kept as its alternative source.';
  }

  @override
  String additionSameDriveNotAdded(String session) {
    return 'the same drive as $session in the other format; not added again.';
  }
}
