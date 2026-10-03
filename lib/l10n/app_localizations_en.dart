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
    return '$time · spread $spread s';
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
    return 'Through $segment, from $start m to $end m after the line.';
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
    return 'braking starts at $meters m';
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
    return 'Your best lap ($bestLap) was $gap s slower through $segment than $sourceLap, the fastest recorded there.';
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
    return 'In $count of $total compared laps you lost time through $segment against $reference (median $median s).';
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
    return 'Where braking starts for $segment varies by $spread m across the middle half of $count laps (measured from the brake signal).';
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
    return 'spread $seconds s';
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
      'Each session on its own, in recording order. Gaps in a recording are never bridged; implausible readings and placeholder zeros are left out and counted. Cooling is a continuously recorded drop of at least 5° over at least 30 s.';

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
    return '$metres m before';
  }

  @override
  String cornerIntoCorner(int metres) {
    return '$metres m into the corner';
  }

  @override
  String get cornerSamePosition => 'same';

  @override
  String cornerLater(int metres) {
    return '$metres m later';
  }

  @override
  String cornerEarlier(int metres) {
    return '$metres m earlier';
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
}
