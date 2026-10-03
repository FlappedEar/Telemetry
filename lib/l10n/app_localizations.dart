import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pl.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pl'),
  ];

  /// The app's name, shown in the task switcher and window title. Not translated.
  ///
  /// In en, this message translates to:
  /// **'FlappedEar Telemetry'**
  String get appTitle;

  /// A circuit driven clockwise; button label.
  ///
  /// In en, this message translates to:
  /// **'Clockwise'**
  String get directionClockwise;

  /// A circuit driven counterclockwise; button label.
  ///
  /// In en, this message translates to:
  /// **'Counterclockwise'**
  String get directionCounterclockwise;

  /// Clockwise, inside a sentence such as 'Detected route: 1,830 m, clockwise'.
  ///
  /// In en, this message translates to:
  /// **'clockwise'**
  String get directionClockwiseInSentence;

  /// Counterclockwise, inside a sentence such as 'Detected route: 1,830 m, counterclockwise'.
  ///
  /// In en, this message translates to:
  /// **'counterclockwise'**
  String get directionCounterclockwiseInSentence;

  /// Title of the dialog that corrects a session's circuit.
  ///
  /// In en, this message translates to:
  /// **'Circuit of {session}'**
  String trackDialogTitle(String session);

  /// The circuit could not be found from GPS; reason explains why.
  ///
  /// In en, this message translates to:
  /// **'No route was detected: {reason}'**
  String trackDialogNoRoute(String reason);

  /// Reason shown when a session has no laps.
  ///
  /// In en, this message translates to:
  /// **'no laps'**
  String get trackDialogNoLaps;

  /// The circuit found from GPS: its length in metres and direction.
  ///
  /// In en, this message translates to:
  /// **'Detected route: {length} m, {direction} (inferred from GPS).'**
  String trackDialogDetectedRoute(String length, String direction);

  /// Screen reader label of the map showing a session's GPS trace.
  ///
  /// In en, this message translates to:
  /// **'Whole GPS trace of {session}'**
  String trackDialogWholeTrace(String session);

  /// Text field label: the circuit layout's name.
  ///
  /// In en, this message translates to:
  /// **'Layout name'**
  String get trackDialogLayoutName;

  /// Example layout name in the empty text field.
  ///
  /// In en, this message translates to:
  /// **'Jastrząb full circuit'**
  String get trackDialogLayoutHint;

  /// Checkbox: apply the change to other sessions on the same route.
  ///
  /// In en, this message translates to:
  /// **'Also for the sessions on the same route: {sessions}'**
  String trackDialogSameRoute(String sessions);

  /// Button: drop the manual circuit and use the one found from GPS.
  ///
  /// In en, this message translates to:
  /// **'Use the detected route'**
  String get trackDialogUseDetected;

  /// Why no circuit was found from GPS: too few complete laps.
  ///
  /// In en, this message translates to:
  /// **'Not enough repeated, complete GPS laps to identify a route automatically.'**
  String get routeReasonTooFewLaps;

  /// Why no circuit was found from GPS: the laps disagree.
  ///
  /// In en, this message translates to:
  /// **'Complete laps follow conflicting routes; review this recording\'s layout.'**
  String get routeReasonConflictingLaps;

  /// Why no circuit was found from GPS: the route fits several different circuits.
  ///
  /// In en, this message translates to:
  /// **'GPS route matches more than one incompatible group; review this recording\'s layout.'**
  String get routeReasonSeveralGroups;

  /// A session's name: sessions are numbered in recording-time order.
  ///
  /// In en, this message translates to:
  /// **'Session {number}'**
  String sessionName(int number);

  /// Button that closes a dialog without changes.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Button that keeps a dialog's changes.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Heading of the Settings dialog's section about the app.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// Button in Settings that opens the licences of the app and the software it uses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licences'**
  String get settingsLicences;

  /// Shown at the top of the licences page: the app's own licence and the map credits. Keep 'Apache License 2.0', 'OpenStreetMap', 'ODbL' and 'MapTiler' as written.
  ///
  /// In en, this message translates to:
  /// **'FlappedEar Telemetry is released under the Apache License 2.0.\nMaps © OpenStreetMap contributors (ODbL) and © MapTiler.'**
  String get licencesLegalese;

  /// Heading of the coach card on the day page.
  ///
  /// In en, this message translates to:
  /// **'Next session'**
  String get coachTitle;

  /// Under the coach card's heading: the session coached.
  ///
  /// In en, this message translates to:
  /// **'Coaching {session} against the day\'s faster laps'**
  String coachSubtitle(String session);

  /// While the coach's plan is being prepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared after the theoretical best…'**
  String get coachLoading;

  /// When the coach failed; the error is technical text.
  ///
  /// In en, this message translates to:
  /// **'The coach could not run: {error}'**
  String coachFailed(String error);

  /// When the theoretical best failed, so the coach cannot run.
  ///
  /// In en, this message translates to:
  /// **'The coach needs the theoretical best, which could not be computed.'**
  String get coachNoTheoreticalBest;

  /// Under coach items when speeds are hidden: the recordings' units disagree or the coach converted them; values are never shown converted.
  ///
  /// In en, this message translates to:
  /// **'Speeds are not shown: the recordings\' speed units differ, or the coach converted them to km/h, and speeds are never shown converted or mixed.'**
  String get coachSpeedHidden;

  /// Label on each coach item, marking it as a suggestion from the coach rules, unlike the measured observations elsewhere on the page.
  ///
  /// In en, this message translates to:
  /// **'Coach suggestion'**
  String get coachLabel;

  /// Label before what was measured, in a coach item.
  ///
  /// In en, this message translates to:
  /// **'Measured'**
  String get coachMeasuredLabel;

  /// Label before what to try next, in a coach item.
  ///
  /// In en, this message translates to:
  /// **'Try'**
  String get coachTryLabel;

  /// Label before what to keep doing, in an improvement item.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get coachKeepLabel;

  /// Button opening the measured values behind a coach item.
  ///
  /// In en, this message translates to:
  /// **'Why?'**
  String get coachWhy;

  /// Note under the coach items. DrivingCoach is a name; do not translate.
  ///
  /// In en, this message translates to:
  /// **'Coach suggestions follow DrivingCoach\'s rules and suggest an opportunity, not a promised gain. The areas below are observations.'**
  String get coachFooter;

  /// Coach item title: lifting off the throttle earlier than on faster laps.
  ///
  /// In en, this message translates to:
  /// **'Try a later lift'**
  String get coachKindEarlyLift;

  /// Coach item title: time with neither pedal pressed.
  ///
  /// In en, this message translates to:
  /// **'Reduce coasting'**
  String get coachKindExcessiveCoasting;

  /// Coach item title: lower minimum speed than on faster laps.
  ///
  /// In en, this message translates to:
  /// **'Keep more speed through the slow point'**
  String get coachKindLowMinimumSpeed;

  /// Coach item title: throttle back on later than on faster laps.
  ///
  /// In en, this message translates to:
  /// **'Return to throttle sooner'**
  String get coachKindLateThrottle;

  /// Coach item title: an improvement over the last laps to keep.
  ///
  /// In en, this message translates to:
  /// **'Keep current approach'**
  String get coachKindImproving;

  /// A coach item's heading: the corner and what to do.
  ///
  /// In en, this message translates to:
  /// **'{segment} · {label}'**
  String coachItemTitle(String segment, String label);

  /// What to try for an early lift.
  ///
  /// In en, this message translates to:
  /// **'Try a slightly later lift within the approach you have already repeated successfully. Keep the braking point unchanged.'**
  String get coachActionEarlyLift;

  /// What to try for too much coasting.
  ///
  /// In en, this message translates to:
  /// **'Reduce the gap with neither pedal engaged. Focus on smoother pedal transitions. Keep the braking point unchanged.'**
  String get coachActionExcessiveCoasting;

  /// What to try for a low minimum speed.
  ///
  /// In en, this message translates to:
  /// **'Repeat the line and approach from your faster laps, aiming for a smoother minimum-speed phase. Keep the exit as your check.'**
  String get coachActionLowMinimumSpeed;

  /// What to try for a late throttle return.
  ///
  /// In en, this message translates to:
  /// **'Work toward a smooth, slightly earlier throttle return after the slow point, using your faster laps as a reference.'**
  String get coachActionLateThrottle;

  /// What to keep for an improvement.
  ///
  /// In en, this message translates to:
  /// **'Keep the approach from your latest laps. Repeat it before making another change.'**
  String get coachActionImproving;

  /// What was measured, compared with one faster lap.
  ///
  /// In en, this message translates to:
  /// **'{metric}: {observed} on this session\'s laps, {reference} on your faster lap.'**
  String coachMeasuredOne(String metric, String observed, String reference);

  /// What was measured, compared with several faster laps (their median).
  ///
  /// In en, this message translates to:
  /// **'{metric}: {observed} on this session\'s laps, {reference} on your faster laps.'**
  String coachMeasuredMany(String metric, String observed, String reference);

  /// What was measured for an improvement.
  ///
  /// In en, this message translates to:
  /// **'{metric} improved on three laps in a row, from {before} to {after}, without losing exit speed.'**
  String coachMeasuredImproving(String metric, String before, String after);

  /// Where the driver lifts off the throttle, in metres along the lap.
  ///
  /// In en, this message translates to:
  /// **'Lift point'**
  String get coachMetricLiftPoint;

  /// The longest time with neither pedal pressed.
  ///
  /// In en, this message translates to:
  /// **'Longest coast'**
  String get coachMetricLongestCoast;

  /// The lowest speed through a corner.
  ///
  /// In en, this message translates to:
  /// **'Minimum speed'**
  String get coachMetricMinimumSpeed;

  /// Where the throttle is applied again after the slow point, in metres along the lap.
  ///
  /// In en, this message translates to:
  /// **'Throttle return'**
  String get coachMetricThrottleReturn;

  /// The time through the corner's segment.
  ///
  /// In en, this message translates to:
  /// **'Segment time'**
  String get coachMetricSegmentTime;

  /// The speed at the corner's exit.
  ///
  /// In en, this message translates to:
  /// **'Exit speed'**
  String get coachMetricExitSpeed;

  /// Where braking starts, in metres along the lap.
  ///
  /// In en, this message translates to:
  /// **'Braking start'**
  String get coachMetricBrakingStart;

  /// The distance driven with neither pedal pressed.
  ///
  /// In en, this message translates to:
  /// **'Coast distance'**
  String get coachMetricCoastDistance;

  /// Above the coach items.
  ///
  /// In en, this message translates to:
  /// **'Choose one focus at a time for your next run.'**
  String get coachReasonReady;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'The coach needs the day\'s segments and sector times first.'**
  String get coachReasonNoSegments;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'{session} has no timed lap in the laps compared.'**
  String coachReasonNoLapInGroup(String session);

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'The laps compared have no approved corner.'**
  String get coachReasonNoCorners;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'The recording of {session} is not available, so it cannot be coached.'**
  String coachReasonNoRecording(String session);

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'No lap of {session} could be measured through a corner.'**
  String coachReasonNoCornerMeasurements(String session);

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'No lap of {session} has a faster lap of the day to compare with.'**
  String coachReasonNoFasterLap(String session);

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'Throttle and brake are not recorded, so lift, coasting and throttle return cannot be compared, and the speeds show no repeated pattern.'**
  String get coachReasonNoPedals;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'Compared with your faster laps, no pattern stands out.'**
  String get coachReasonNoPattern;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'A pattern was seen on fewer than three laps of {session}, too few to plan from.'**
  String coachReasonTooFewLaps(String session);

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'No repeated pattern is clear enough to suggest a change.'**
  String get coachReasonBelowThreshold;

  /// Heading of the laps the pattern was seen on.
  ///
  /// In en, this message translates to:
  /// **'This session\'s laps'**
  String get coachWhyAffected;

  /// Heading of the faster laps used as reference.
  ///
  /// In en, this message translates to:
  /// **'Faster laps compared'**
  String get coachWhyFaster;

  /// Heading of the lap an improvement started from.
  ///
  /// In en, this message translates to:
  /// **'First of the three laps'**
  String get coachWhyBefore;

  /// One measured value of this session against the faster laps'.
  ///
  /// In en, this message translates to:
  /// **'{observed} against {reference}'**
  String coachWhyValues(String observed, String reference);

  /// The finding's confidence score.
  ///
  /// In en, this message translates to:
  /// **'Support {score} of 0.9. A conservative score for how well the laps back the pattern, not a probability.'**
  String coachWhySupport(String score);

  /// Screen-reader label of the map.
  ///
  /// In en, this message translates to:
  /// **'Best lap trace with {segment} highlighted'**
  String coachWhyMap(String segment);

  /// Section of the day page with the best lap and the analysis; bottom bar and side rail label.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get daySectionDay;

  /// Section of the day page listing every lap; bottom bar label.
  ///
  /// In en, this message translates to:
  /// **'Laps'**
  String get daySectionLaps;

  /// Section of the day page for comparing two laps; bottom bar and side rail label, and its heading.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get daySectionCompare;

  /// Explains the Compare section under its heading.
  ///
  /// In en, this message translates to:
  /// **'Two laps side by side: where one gains and loses time, segment by segment and corner by corner.'**
  String get compareIntro;

  /// Shown in the Compare section when the day has fewer than two comparable laps.
  ///
  /// In en, this message translates to:
  /// **'Comparing needs two ranked laps of one circuit.'**
  String get compareNeedsTwoLaps;

  /// Button that asks for lap A, then lap B, and opens their comparison.
  ///
  /// In en, this message translates to:
  /// **'Pick two laps'**
  String get comparePickTwoLaps;

  /// Heading over suggested comparisons: each session's best lap against the day's best lap.
  ///
  /// In en, this message translates to:
  /// **'Against the best of the day'**
  String get compareAgainstBest;

  /// Chip with lap A's time in a suggested comparison; A is the session's best lap.
  ///
  /// In en, this message translates to:
  /// **'A {time}'**
  String compareLapA(String time);

  /// Chip with lap B's time in a suggested comparison; B is the best lap of the day.
  ///
  /// In en, this message translates to:
  /// **'B {time}'**
  String compareLapB(String time);

  /// Label of the day's best lap, at the top of the day page.
  ///
  /// In en, this message translates to:
  /// **'Best day'**
  String get dayBestLabel;

  /// Label of the theoretical best: the fastest time of each segment added up.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best'**
  String get theoreticalBestLabel;

  /// Under the theoretical best label: what it is made of.
  ///
  /// In en, this message translates to:
  /// **'Fastest of every segment'**
  String get theoreticalBestHint;

  /// Title of the day page before the day is saved.
  ///
  /// In en, this message translates to:
  /// **'Day results'**
  String get dayResultsTitle;

  /// Button on the day page that adds recordings to the open day.
  ///
  /// In en, this message translates to:
  /// **'Add recordings'**
  String get addRecordings;

  /// Button on the day page that opens the day report.
  ///
  /// In en, this message translates to:
  /// **'Day report'**
  String get dayReport;

  /// Tooltip of the menu with more actions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// Menu item that saves the day under a new name.
  ///
  /// In en, this message translates to:
  /// **'Save as…'**
  String get saveAs;

  /// Screen reader label of the progress bar while recordings are added.
  ///
  /// In en, this message translates to:
  /// **'Adding recordings'**
  String get addingRecordings;

  /// Shown when leaving the day page while a session is being added.
  ///
  /// In en, this message translates to:
  /// **'Wait until the session is added.'**
  String get waitUntilSessionAdded;

  /// After adding recordings: none was added.
  ///
  /// In en, this message translates to:
  /// **'Nothing was added.'**
  String get nothingAdded;

  /// After adding recordings: the new sessions' names.
  ///
  /// In en, this message translates to:
  /// **'{sessions} added to the day.'**
  String addedToDay(String sessions);

  /// After saving the day: its file name.
  ///
  /// In en, this message translates to:
  /// **'Saved as {file}.'**
  String savedAs(String file);

  /// After saving the day when it changed during the save.
  ///
  /// In en, this message translates to:
  /// **'Saved as {file}. Changes made while saving are not saved yet.'**
  String savedAsChangesPending(String file);

  /// Saving the day failed; the error follows.
  ///
  /// In en, this message translates to:
  /// **'Not saved: {error}'**
  String notSaved(String error);

  /// Finding missing recordings while others are being added.
  ///
  /// In en, this message translates to:
  /// **'Wait until the recordings are added, then find the others.'**
  String get waitThenFindRecordings;

  /// Finding missing recordings of a day with unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Save the day first, then find its recordings.'**
  String get saveThenFindRecordings;

  /// The day changed while missing recordings were searched for.
  ///
  /// In en, this message translates to:
  /// **'Recordings were added meanwhile. Find the recordings again.'**
  String get recordingsAddedMeanwhile;

  /// Searching a folder for missing recordings found none.
  ///
  /// In en, this message translates to:
  /// **'No missing recording was found in that folder.'**
  String get noMissingRecordingFound;

  /// Files named like the missing recordings but with different content.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{files} in that folder is a different recording and was not used.} other{{files} in that folder are different recordings and were not used.}}'**
  String differentRecordingsNotUsed(int count, String files);

  /// Opening the day again with the found recordings failed.
  ///
  /// In en, this message translates to:
  /// **'The day could not be opened again: {error}'**
  String dayReopenFailed(String error);

  /// Heading over the sessions whose recordings are missing.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session could not be opened} other{{count} sessions could not be opened}}'**
  String sessionsNotOpened(int count);

  /// Under the missing sessions.
  ///
  /// In en, this message translates to:
  /// **'They stay in the day when it is saved, but are not shown.'**
  String get missingSessionsKept;

  /// Button text while missing recordings are searched for.
  ///
  /// In en, this message translates to:
  /// **'Looking…'**
  String get lookingForRecordings;

  /// Button that searches a folder for the missing recordings.
  ///
  /// In en, this message translates to:
  /// **'Find recordings in a folder…'**
  String get findRecordingsInFolder;

  /// Several laps tie for the best time of the day.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap has this time.} other{{count} laps share this time; the earliest is shown.}}'**
  String lapsShareBestTime(int count);

  /// Screen reader label of the map of the best lap.
  ///
  /// In en, this message translates to:
  /// **'Trace of the best lap, coloured by speed'**
  String get bestLapTrace;

  /// Under the map of the best lap.
  ///
  /// In en, this message translates to:
  /// **'Tap to open the lap.'**
  String get tapToOpenLap;

  /// Heading of the choice of which circuit group's laps are ranked.
  ///
  /// In en, this message translates to:
  /// **'Compared laps'**
  String get comparedLaps;

  /// A circuit group in the group choice, with its ranked and all laps.
  ///
  /// In en, this message translates to:
  /// **'{group} · {eligible}/{count} laps'**
  String groupLapCount(String group, int eligible, int count);

  /// How many laps of a group or session are ranked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{eligible} of 1 lap ranked} other{{eligible} of {count} laps ranked}}'**
  String lapsRanked(int count, int eligible);

  /// Heading of the list of each session's best lap.
  ///
  /// In en, this message translates to:
  /// **'Best lap of each session'**
  String get bestLapOfEachSession;

  /// A session without a ranked lap, with its number of laps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{No ranked lap · 1 lap} other{No ranked lap · {count} laps}}'**
  String noRankedLap(int count);

  /// A session's typical (median) lap time.
  ///
  /// In en, this message translates to:
  /// **'typical {time}'**
  String typicalTime(String time);

  /// Under a group whose circuit is unknown.
  ///
  /// In en, this message translates to:
  /// **'Its circuit could not be identified, so its laps are not compared.'**
  String get circuitNotIdentified;

  /// Heading of the list of each session's circuit.
  ///
  /// In en, this message translates to:
  /// **'Circuits'**
  String get circuits;

  /// Heading of the analysis notes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notes;

  /// A session's circuit is unknown.
  ///
  /// In en, this message translates to:
  /// **'Not identified'**
  String get circuitNotIdentifiedShort;

  /// A circuit found from the GPS route, with no known layout name.
  ///
  /// In en, this message translates to:
  /// **'Detected route'**
  String get detectedRoute;

  /// A session's driving direction is unknown.
  ///
  /// In en, this message translates to:
  /// **'direction unknown'**
  String get directionUnknown;

  /// The session's circuit was set by the user.
  ///
  /// In en, this message translates to:
  /// **'set by you'**
  String get circuitSetByYou;

  /// The session's circuit was inferred from GPS.
  ///
  /// In en, this message translates to:
  /// **'inferred from GPS'**
  String get circuitInferredFromGps;

  /// Why there is no best lap.
  ///
  /// In en, this message translates to:
  /// **'No best lap: no session has enough complete GPS laps to identify its circuit.'**
  String get noBestLapNoCircuit;

  /// Why there is no best lap.
  ///
  /// In en, this message translates to:
  /// **'No best lap: no lap of this group can be ranked.'**
  String get noBestLapNoRankable;

  /// Button in the lap list that starts a comparison.
  ///
  /// In en, this message translates to:
  /// **'Compare two laps'**
  String get compareTwoLaps;

  /// Mark of the day's best lap in the lap list.
  ///
  /// In en, this message translates to:
  /// **'Best of the day'**
  String get bestOfDay;

  /// Mark of a session's best lap in the lap list.
  ///
  /// In en, this message translates to:
  /// **'Best of {session}'**
  String bestOfSession(String session);

  /// A lap the user excluded, with the reason they gave.
  ///
  /// In en, this message translates to:
  /// **'Excluded: {reason}'**
  String lapExcluded(String reason);

  /// A lap the user excluded without a reason.
  ///
  /// In en, this message translates to:
  /// **'Excluded'**
  String get lapExcludedNoReason;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Not ranked: {issue}'**
  String lapNotRanked(String issue);

  /// A recording part that never crossed the start/finish line.
  ///
  /// In en, this message translates to:
  /// **'No start/finish pass'**
  String get noStartFinishPass;

  /// An out or in lap.
  ///
  /// In en, this message translates to:
  /// **'Not timed'**
  String get notTimed;

  /// Title of the list for picking the first lap to compare.
  ///
  /// In en, this message translates to:
  /// **'Lap A'**
  String get pickLapA;

  /// Title of the list for picking the second lap to compare.
  ///
  /// In en, this message translates to:
  /// **'Compare {lap} with'**
  String pickLapB(String lap);

  /// A timed lap's name, as on a timing screen.
  ///
  /// In en, this message translates to:
  /// **'{session} · LAP {number}'**
  String lapName(String session, int number);

  /// The part from the start of a recording to the first start/finish pass.
  ///
  /// In en, this message translates to:
  /// **'{session} · OUT'**
  String outLapName(String session);

  /// The part from the last start/finish pass to the end of a recording.
  ///
  /// In en, this message translates to:
  /// **'{session} · IN'**
  String inLapName(String session);

  /// A whole recording with no start/finish pass.
  ///
  /// In en, this message translates to:
  /// **'{session} · UNKNOWN'**
  String unknownLapName(String session);

  /// A group of sessions on one circuit.
  ///
  /// In en, this message translates to:
  /// **'Group {number} · {layout} · {direction}'**
  String circuitGroup(int number, String layout, String direction);

  /// A session whose circuit is unknown, as its own group.
  ///
  /// In en, this message translates to:
  /// **'Unresolved · {session}'**
  String circuitGroupUnresolved(String session);

  /// Analysis note about a recording without a clock.
  ///
  /// In en, this message translates to:
  /// **'Recording date and time unavailable; listed after the dated recordings in import order.'**
  String get noteUndated;

  /// Analysis note about a recording without start/finish passes.
  ///
  /// In en, this message translates to:
  /// **'No reliable start/finish passes; lap type is unknown.'**
  String get noteNoPasses;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Layout needs confirmation'**
  String get lapIssueLayoutUnresolved;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Direction needs confirmation'**
  String get lapIssueDirectionUnresolved;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Timing gates unresolved'**
  String get lapIssueTimingGateUnresolved;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Different layout'**
  String get lapIssueChangedLayout;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Opposite direction'**
  String get lapIssueOppositeDirection;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Different timing gates'**
  String get lapIssueChangedTimingGate;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Incomplete GPS'**
  String get lapIssueIncompleteGps;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Invalid GPS'**
  String get lapIssueInvalidGps;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'User exclusion'**
  String get lapIssueUserExclusion;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Not a complete timed lap'**
  String get lapIssueNotTimedLap;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Source changed; reload recording'**
  String get lapIssueStaleSource;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Lap is not eligible'**
  String get lapIssueIneligibleLap;

  /// Why a lap is not ranked.
  ///
  /// In en, this message translates to:
  /// **'Lap leaves the route the other laps took (off track, a detour or the pit lane)'**
  String get lapIssueDifferentRoute;

  /// Theoretical best card while it is calculated.
  ///
  /// In en, this message translates to:
  /// **'Timing every lap on one track axis…'**
  String get tbTiming;

  /// Explains the theoretical best: the fastest time of every segment over all timed laps.
  ///
  /// In en, this message translates to:
  /// **'The fastest time of each of the {segments, plural, =1{1 segment} other{{segments} segments}} across {laps, plural, =1{1 lap} other{{laps} laps}}. It combines parts of different laps, so it does not show that the whole lap can be driven that fast.'**
  String tbIntro(int segments, int laps);

  /// After the theoretical best explanation when the segments were proposed automatically.
  ///
  /// In en, this message translates to:
  /// **'Segments proposed from the best lap; saving the day keeps them.'**
  String get tbSegmentsProposed;

  /// After the theoretical best explanation when the user edited the segments.
  ///
  /// In en, this message translates to:
  /// **'The segments include your corrections.'**
  String get tbSegmentsCorrected;

  /// Button opening the segment editor.
  ///
  /// In en, this message translates to:
  /// **'Edit segments'**
  String get tbEditSegments;

  /// Heading of the loss map and the list of each segment's time loss.
  ///
  /// In en, this message translates to:
  /// **'Where the time goes'**
  String get tbWhereTimeGoes;

  /// A lap in the lap choice or the sector table marked as the best lap of the day.
  ///
  /// In en, this message translates to:
  /// **'{text} · best'**
  String tbMarkedBest(String text);

  /// Screen reader label of the loss map.
  ///
  /// In en, this message translates to:
  /// **'Best lap trace, each segment coloured by the time {lap} loses there'**
  String tbMapLabel(String lap);

  /// Hint above the list of segment losses.
  ///
  /// In en, this message translates to:
  /// **'Tap a corner for its speeds, braking and pickup against the best lap.'**
  String get tbTapCorner;

  /// Hint above the list of segment losses when laps can be compared.
  ///
  /// In en, this message translates to:
  /// **'The compare button opens this lap against the best lap through the segment in the Corner Analyzer.'**
  String get tbCompareHint;

  /// Tooltip of the button comparing a lap with the best lap through one segment.
  ///
  /// In en, this message translates to:
  /// **'Open in the Corner Analyzer'**
  String get tbOpenInAnalyzer;

  /// Heading of the table of every lap's segment times.
  ///
  /// In en, this message translates to:
  /// **'Sector times'**
  String get tbSectorTimes;

  /// Explains the sector table.
  ///
  /// In en, this message translates to:
  /// **'The fastest time of each segment is highlighted. Tap a lap to show its losses on the map.'**
  String get tbSectorHint;

  /// A segment the chosen lap has no full time through, with the fastest time.
  ///
  /// In en, this message translates to:
  /// **'Not fully covered on this lap · fastest {time}'**
  String tbNotCovered(String time);

  /// A segment where the chosen lap set the fastest time.
  ///
  /// In en, this message translates to:
  /// **'Fastest here · {time}'**
  String tbFastestHere(String time);

  /// A segment's fastest time and the lap that set it.
  ///
  /// In en, this message translates to:
  /// **'Fastest {time} · {lap}'**
  String tbFastestBy(String time, String lap);

  /// In place of the lap that set a segment's fastest time when it is not found.
  ///
  /// In en, this message translates to:
  /// **'lap unavailable'**
  String get tbLapUnavailable;

  /// Label of the best lap's time on the theoretical best card.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get tbBestLap;

  /// Label of the best lap's time over the segments only, when they do not cover the whole lap.
  ///
  /// In en, this message translates to:
  /// **'Best lap, same segments'**
  String get tbBestLapSameSegments;

  /// Label of the time the best lap leaves: best lap minus theoretical best.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get tbAvailable;

  /// Sector table column header.
  ///
  /// In en, this message translates to:
  /// **'Lap'**
  String get tbLapColumn;

  /// Sector table column header: the lap time.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get tbTimeColumn;

  /// Sector table last row: the fastest time of each segment.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get tbFastestRow;

  /// An automatically named corner segment.
  ///
  /// In en, this message translates to:
  /// **'Corner {number}'**
  String tbSegmentCorner(String number);

  /// An automatically named segment of linked corners.
  ///
  /// In en, this message translates to:
  /// **'Corners {numbers}'**
  String tbSegmentCorners(String numbers);

  /// An automatically named straight segment.
  ///
  /// In en, this message translates to:
  /// **'Straight {number}'**
  String tbSegmentStraight(String number);

  /// Why there is no theoretical best.
  ///
  /// In en, this message translates to:
  /// **'Confirm a compatible track configuration before calculating a theoretical best.'**
  String get tbNoConfiguration;

  /// Why there is no theoretical best.
  ///
  /// In en, this message translates to:
  /// **'No eligible laps in this group to calculate a theoretical best from.'**
  String get tbNoEligibleLaps;

  /// Why there is no theoretical best.
  ///
  /// In en, this message translates to:
  /// **'No run in this group has an approved segment review yet. Approve segments for at least one run first.'**
  String get tbNoApprovedRun;

  /// Why there is no theoretical best.
  ///
  /// In en, this message translates to:
  /// **'No approved segments to measure sectors against.'**
  String get tbNoApprovedSegments;

  /// Why the theoretical best total, or a segment's fastest time, is not shown.
  ///
  /// In en, this message translates to:
  /// **'At least one sector has no fully covered time on any eligible lap, so no total is shown.'**
  String get tbIncompleteCoverage;

  /// Why there is no theoretical best.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best calculation was cancelled.'**
  String get tbCancelled;

  /// Heading of the card on how repeatable lap and segment times are.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get consistencyHeading;

  /// Explains the consistency card.
  ///
  /// In en, this message translates to:
  /// **'Typical time is the median; the spread is the interquartile range, the width of the middle half of the laps, so one slow or quick lap does not dominate it. At least {count, plural, =1{1 lap is} other{{count} laps are}} needed.'**
  String consistencyIntro(int count);

  /// Consistency card heading of the lap times.
  ///
  /// In en, this message translates to:
  /// **'Lap times'**
  String get consistencyLapTimes;

  /// Consistency of the lap times over the whole day.
  ///
  /// In en, this message translates to:
  /// **'All sessions'**
  String get consistencyAllSessions;

  /// Consistency card heading of the segment times.
  ///
  /// In en, this message translates to:
  /// **'Segment times'**
  String get consistencySegmentTimes;

  /// Consistency card while the segment times are calculated.
  ///
  /// In en, this message translates to:
  /// **'Measured with the theoretical best…'**
  String get consistencyMeasuring;

  /// In place of a consistency with too few laps.
  ///
  /// In en, this message translates to:
  /// **'Needs at least {count, plural, =1{1 lap} other{{count} laps}}'**
  String consistencyNeedsLaps(int count);

  /// A typical (median) time and its spread (interquartile range) in seconds.
  ///
  /// In en, this message translates to:
  /// **'{time} · spread {spread} s'**
  String consistencyValue(String time, String spread);

  /// How many laps a consistency is measured over.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap} other{{count} laps}}'**
  String consistencyLapCount(int count);

  /// Heading of the card listing the day's largest time losses.
  ///
  /// In en, this message translates to:
  /// **'Time losses'**
  String get timeLossTitle;

  /// Shown on the time-loss card while the theoretical best is calculated.
  ///
  /// In en, this message translates to:
  /// **'Measured with the theoretical best…'**
  String get timeLossLoading;

  /// Choice: compare only each session's best lap with the best lap.
  ///
  /// In en, this message translates to:
  /// **'Each session\'s best'**
  String get timeLossScopeSessionBest;

  /// Choice: compare every lap with the best lap.
  ///
  /// In en, this message translates to:
  /// **'Every lap'**
  String get timeLossScopeEveryLap;

  /// First part of the time-loss summary: the lap every loss is measured against.
  ///
  /// In en, this message translates to:
  /// **'Against {lap}'**
  String timeLossAgainst(String lap);

  /// Part of the time-loss summary: how many laps were compared with the best lap.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap compared} other{{count} laps compared}}'**
  String timeLossLapsCompared(int count);

  /// Part of the time-loss summary: how many time losses were found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 loss observed} other{{count} losses observed}}'**
  String timeLossLossesObserved(int count);

  /// Part of the time-loss summary: segments left out because a lap has no complete time through them.
  ///
  /// In en, this message translates to:
  /// **'{count} not fully covered left out'**
  String timeLossUntimedLeftOut(int count);

  /// Explains what a time loss is, under the time-loss summary.
  ///
  /// In en, this message translates to:
  /// **'Each loss is the extra time one lap took through one segment compared with the best lap, both timed on one track axis. A straight right after a corner is its own segment, so time lost on the exit is not counted in the corner. An observed loss is not a guaranteed or necessarily safe gain.'**
  String get timeLossExplanation;

  /// Shown when no lap lost time anywhere.
  ///
  /// In en, this message translates to:
  /// **'No lap lost time to the best lap in any timed segment.'**
  String get timeLossNone;

  /// Button that shows every time loss instead of the first ones.
  ///
  /// In en, this message translates to:
  /// **'Show all {count}'**
  String timeLossShowAll(int count);

  /// Why there is no time-loss list: the best lap has no time on the segments.
  ///
  /// In en, this message translates to:
  /// **'The best lap could not be timed against the segments.'**
  String get timeLossReasonNoReference;

  /// Why there are no time losses or focus areas: the group's best lap has no time on the approved segments.
  ///
  /// In en, this message translates to:
  /// **'The group\'s best lap could not be timed against the approved segments.'**
  String get timeLossReasonBestLapUntimed;

  /// Name of a straight right after a corner, measured on its own.
  ///
  /// In en, this message translates to:
  /// **'{segment} · after {corner}'**
  String timeLossSegmentAfterCorner(String segment, String corner);

  /// Name of a straight right after a corner whose name is unknown.
  ///
  /// In en, this message translates to:
  /// **'{segment} · after the corner'**
  String timeLossSegmentAfterTheCorner(String segment);

  /// In place of a lap's name when the lap cannot be found.
  ///
  /// In en, this message translates to:
  /// **'Lap unavailable'**
  String get timeLossLapUnavailable;

  /// Heading of one opened time loss: the lap that lost time and the best lap.
  ///
  /// In en, this message translates to:
  /// **'{lap} against the best lap, {best}'**
  String timeLossAgainstBestLap(String lap, String best);

  /// In place of a lap's name inside a sentence when the lap cannot be found.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get timeLossUnavailable;

  /// Label of this lap's time through the segment.
  ///
  /// In en, this message translates to:
  /// **'This lap'**
  String get timeLossThisLap;

  /// Label of the best lap's time through the segment.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get timeLossBestLap;

  /// Label of the time difference between the two laps through the segment.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get timeLossDifference;

  /// Where the segment of a time loss is on the track.
  ///
  /// In en, this message translates to:
  /// **'Through {segment}, from {start} m to {end} m after the line.'**
  String timeLossThrough(String segment, int start, int end);

  /// The running gap to the best lap at both ends of the segment.
  ///
  /// In en, this message translates to:
  /// **'Gap to the best lap: {start} at the start of the segment, {end} at its end.'**
  String timeLossGap(String start, String end);

  /// Warning that the comparison is incomplete.
  ///
  /// In en, this message translates to:
  /// **'Part of the segment has no GPS on one of the laps.'**
  String get timeLossNoGps;

  /// Accessibility label of the map showing the segment.
  ///
  /// In en, this message translates to:
  /// **'Best lap trace with {segment} highlighted'**
  String timeLossMapLabel(String segment);

  /// Caution under an opened time loss.
  ///
  /// In en, this message translates to:
  /// **'An observed difference between two laps, not a guaranteed or necessarily safe gain.'**
  String get timeLossDisclaimer;

  /// Button that opens a lap.
  ///
  /// In en, this message translates to:
  /// **'Open {lap}'**
  String timeLossOpenLap(String lap);

  /// Button that compares the lap with the best lap.
  ///
  /// In en, this message translates to:
  /// **'Compare with {lap}'**
  String timeLossCompareWith(String lap);

  /// Heading of the card of focus areas: where the driver may find time.
  ///
  /// In en, this message translates to:
  /// **'Where to look next'**
  String get focusTitle;

  /// Shown on the focus-area card while the theoretical best is calculated.
  ///
  /// In en, this message translates to:
  /// **'Selected with the theoretical best…'**
  String get focusLoading;

  /// Shown when there is no focus area.
  ///
  /// In en, this message translates to:
  /// **'No loss, sector gap or spread is large enough to single out.'**
  String get focusNone;

  /// Explains how a focus area reads.
  ///
  /// In en, this message translates to:
  /// **'Each starts with what was measured. The line under it is a hypothesis to check in the laps, not a cause or an instruction.'**
  String get focusIntro;

  /// Kind of focus area: the best lap was slower through a sector than another lap.
  ///
  /// In en, this message translates to:
  /// **'Best lap against the fastest sector'**
  String get focusKindSectorGap;

  /// Kind of focus area: time lost in the same segment on several laps.
  ///
  /// In en, this message translates to:
  /// **'Repeated loss'**
  String get focusKindRepeatedLoss;

  /// Kind of focus area: the braking point varies from lap to lap.
  ///
  /// In en, this message translates to:
  /// **'Braking-point spread'**
  String get focusKindBrakingSpread;

  /// Kind of focus area: the lowest speed in a corner varies from lap to lap.
  ///
  /// In en, this message translates to:
  /// **'Lowest-speed spread'**
  String get focusKindMinimumSpeedSpread;

  /// What a focus area measured.
  ///
  /// In en, this message translates to:
  /// **'Observed: {text}'**
  String focusObserved(String text);

  /// What may be worth checking in a focus area; never a cause.
  ///
  /// In en, this message translates to:
  /// **'Hypothesis: {text}'**
  String focusHypothesis(String text);

  /// The two laps a focus area suggests comparing.
  ///
  /// In en, this message translates to:
  /// **'Compare {lap} with {other}'**
  String focusCompareLaps(String lap, String other);

  /// In place of a lap's name inside a sentence when the lap cannot be found.
  ///
  /// In en, this message translates to:
  /// **'a lap unavailable'**
  String get focusLapUnavailable;

  /// Heading of the two laps' measurements through the segment.
  ///
  /// In en, this message translates to:
  /// **'Through {segment}'**
  String focusThrough(String segment);

  /// A lap has no time through the segment.
  ///
  /// In en, this message translates to:
  /// **'not timed'**
  String get focusNotTimed;

  /// A lap's braking point could not be measured.
  ///
  /// In en, this message translates to:
  /// **'braking point not measured'**
  String get focusBrakingNotMeasured;

  /// Where braking starts on a lap, in meters along the lap.
  ///
  /// In en, this message translates to:
  /// **'braking starts at {meters} m'**
  String focusBrakingStarts(int meters);

  /// A lap's lowest speed could not be measured.
  ///
  /// In en, this message translates to:
  /// **'lowest speed not measured'**
  String get focusLowestSpeedNotMeasured;

  /// A lap's lowest speed through the corner, with its unit.
  ///
  /// In en, this message translates to:
  /// **'lowest speed {speed}'**
  String focusLowestSpeed(String speed);

  /// Caution under an opened focus area.
  ///
  /// In en, this message translates to:
  /// **'Measured on these laps only. It does not say which way is faster or safe.'**
  String get focusDisclaimer;

  /// Button that compares the focus area's two laps.
  ///
  /// In en, this message translates to:
  /// **'Compare laps A and B'**
  String get focusCompareAB;

  /// What a sector-gap focus area measured.
  ///
  /// In en, this message translates to:
  /// **'Your best lap ({bestLap}) was {gap} s slower through {segment} than {sourceLap}, the fastest recorded there.'**
  String focusObservationSectorGap(
    String bestLap,
    String gap,
    String segment,
    String sourceLap,
  );

  /// What a sector-gap focus area suggests checking; never a cause.
  ///
  /// In en, this message translates to:
  /// **'Comparing the two laps through {segment} may show where the time went: where braking starts, the lowest speed, and when the throttle comes back.'**
  String focusHypothesisSectorGap(String segment);

  /// What a repeated-loss focus area measured.
  ///
  /// In en, this message translates to:
  /// **'In {count} of {total} compared laps you lost time through {segment} against {reference} (median {median} s).'**
  String focusObservationRepeatedLoss(
    String count,
    String total,
    String segment,
    String reference,
    String median,
  );

  /// What a repeated-loss focus area suggests checking; never a cause.
  ///
  /// In en, this message translates to:
  /// **'Because it repeats, comparing a typical lap with {reference} through {segment} may show a pattern rather than a one-off.'**
  String focusHypothesisRepeatedLoss(String reference, String segment);

  /// What a braking-spread focus area measured.
  ///
  /// In en, this message translates to:
  /// **'Where braking starts for {segment} varies by {spread} m across the middle half of {count} laps (measured from the brake signal).'**
  String focusObservationBrakingSpread(
    String segment,
    String spread,
    String count,
  );

  /// What a braking-spread focus area suggests checking; never a cause.
  ///
  /// In en, this message translates to:
  /// **'A more repeatable braking reference for {segment} may be worth checking. This does not show whether earlier or later braking is faster or safe; compare the earliest and the latest example.'**
  String focusHypothesisBrakingSpread(String segment);

  /// What a lowest-speed-spread focus area measured; the speeds carry their unit when recorded.
  ///
  /// In en, this message translates to:
  /// **'The lowest speed through {segment} varies by {spread} across the middle half of {count} laps (median {median}).'**
  String focusObservationMinimumSpeedSpread(
    String segment,
    String spread,
    String count,
    String median,
  );

  /// Added after a lowest-speed spread when the recording gives no speed unit.
  ///
  /// In en, this message translates to:
  /// **'Speeds are in the recording\'s own units.'**
  String get focusObservationRecordingUnits;

  /// What a lowest-speed-spread focus area suggests checking; never a cause.
  ///
  /// In en, this message translates to:
  /// **'Comparing the slowest and the fastest example through {segment} may show what differs; a higher minimum speed is not by itself better.'**
  String focusHypothesisMinimumSpeedSpread(String segment);

  /// Heading of the card showing how the day went session by session.
  ///
  /// In en, this message translates to:
  /// **'Progression'**
  String get progressionTitle;

  /// Progression view: one entry per session.
  ///
  /// In en, this message translates to:
  /// **'By session'**
  String get progressionBySession;

  /// Progression view: a table of segments by session.
  ///
  /// In en, this message translates to:
  /// **'By segment'**
  String get progressionBySegment;

  /// Explains the progression by session.
  ///
  /// In en, this message translates to:
  /// **'Sessions in recording order; sessions without a recording time follow in import order. The bar runs from the quickest to the slowest ranked lap on one time scale, the middle half boxed and the typical lap marked.'**
  String get progressionSessionsIntro;

  /// Progression card without sessions.
  ///
  /// In en, this message translates to:
  /// **'No session to compare.'**
  String get progressionNoSession;

  /// A session whose recording has no date and time.
  ///
  /// In en, this message translates to:
  /// **'Recording time unavailable'**
  String get progressionRecordingTimeUnavailable;

  /// When a session was recorded, from the recording's clock.
  ///
  /// In en, this message translates to:
  /// **'{time} UTC on {date}'**
  String progressionRecordingClock(String time, String date);

  /// A session without laps.
  ///
  /// In en, this message translates to:
  /// **'No recorded laps'**
  String get progressionNoRecordedLaps;

  /// A session none of whose laps is ranked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{No ranked lap · 0 of 1 lap} other{No ranked lap · 0 of {count} laps}}'**
  String progressionNoRankedLap(int count);

  /// How many of a session's laps are ranked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{eligible} of 1 lap ranked} other{{eligible} of {count} laps ranked}}'**
  String progressionLapsRanked(int count, int eligible);

  /// A session's typical (median) lap time.
  ///
  /// In en, this message translates to:
  /// **'Typical {time}'**
  String progressionTypical(String time);

  /// Why a session has no typical lap.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Typical lap needs at least 1 ranked lap} other{Typical lap needs at least {count} ranked laps}}'**
  String progressionTypicalNeedsLaps(int count);

  /// A session's best lap compared with the previous session's.
  ///
  /// In en, this message translates to:
  /// **'Best {delta} against {session}'**
  String progressionBestAgainst(String delta, String session);

  /// The conditions the driver noted for a session.
  ///
  /// In en, this message translates to:
  /// **'Conditions: {conditions}'**
  String progressionConditions(String conditions);

  /// The setup changes the driver noted for a session.
  ///
  /// In en, this message translates to:
  /// **'Setup: {setup}'**
  String progressionSetup(String setup);

  /// The driver's notes for a session.
  ///
  /// In en, this message translates to:
  /// **'Notes: {notes}'**
  String progressionNotes(String notes);

  /// A session's best lap, as on a timing screen.
  ///
  /// In en, this message translates to:
  /// **'Best: LAP {number}'**
  String progressionBestLap(int number);

  /// The progression by segment while the theoretical best is calculated.
  ///
  /// In en, this message translates to:
  /// **'Measured with the theoretical best…'**
  String get progressionMeasuring;

  /// Explains the progression by segment.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Each segment\'s typical time (median) and spread (middle half) per session. The quickest typical time of each segment is highlighted. Fewer than 1 lap: no statistics. Tap a cell for its laps.} other{Each segment\'s typical time (median) and spread (middle half) per session. The quickest typical time of each segment is highlighted. Fewer than {count} laps: no statistics. Tap a cell for its laps.}}'**
  String progressionSegmentsIntro(int count);

  /// A lap of a segment cell that can no longer be found.
  ///
  /// In en, this message translates to:
  /// **'Lap unavailable'**
  String get progressionLapUnavailable;

  /// Progression by segment without timed segments.
  ///
  /// In en, this message translates to:
  /// **'No session has timed segments.'**
  String get progressionNoTimedSegments;

  /// A segment's spread (interquartile range) in a session.
  ///
  /// In en, this message translates to:
  /// **'spread {seconds} s'**
  String progressionSpread(String seconds);

  /// A segment cell with too few laps for statistics.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap} other{{count} laps}}'**
  String progressionLapCount(int count);

  /// An oil temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Oil'**
  String get channelOil;

  /// A coolant temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Coolant'**
  String get channelCoolant;

  /// An intake air temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Intake air'**
  String get channelIntakeAir;

  /// A gearbox temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Gearbox'**
  String get channelGearbox;

  /// An exhaust gas temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Exhaust'**
  String get channelExhaust;

  /// An ambient temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Ambient'**
  String get channelAmbient;

  /// A channel missing from a session.
  ///
  /// In en, this message translates to:
  /// **'Not recorded'**
  String get channelNotRecorded;

  /// A channel without a usable reading.
  ///
  /// In en, this message translates to:
  /// **'No valid samples'**
  String get channelNoValidSamples;

  /// A channel's mean, range and how much of the time it was recorded.
  ///
  /// In en, this message translates to:
  /// **'mean {mean} · {minimum} – {maximum} · {coverage}% covered'**
  String channelSummary(
    String mean,
    String minimum,
    String maximum,
    int coverage,
  );

  /// Readings of a channel left out as implausible.
  ///
  /// In en, this message translates to:
  /// **'{count} implausible left out'**
  String channelImplausibleLeftOut(int count);

  /// Section of a recording before the first start/finish pass.
  ///
  /// In en, this message translates to:
  /// **'out lap'**
  String get channelOutLap;

  /// Section of a recording after the last start/finish pass.
  ///
  /// In en, this message translates to:
  /// **'in lap'**
  String get channelInLap;

  /// A timed lap as a section of a recording.
  ///
  /// In en, this message translates to:
  /// **'lap {number}'**
  String channelLapSection(int number);

  /// A section of a recording of unknown type.
  ///
  /// In en, this message translates to:
  /// **'unknown section'**
  String get channelUnknownSection;

  /// No cooling in a channel.
  ///
  /// In en, this message translates to:
  /// **'none recorded'**
  String get channelCoolingNone;

  /// A continuously recorded temperature drop and how long it took.
  ///
  /// In en, this message translates to:
  /// **'−{drop} in {duration}'**
  String channelCoolingDrop(String drop, String duration);

  /// A session's cooling of a temperature channel.
  ///
  /// In en, this message translates to:
  /// **'Cooling: {cooling}'**
  String channelCooling(String cooling);

  /// Lap time as a metric associated with a temperature.
  ///
  /// In en, this message translates to:
  /// **'Lap time'**
  String get channelLapTime;

  /// Strong acceleration as a metric associated with a temperature.
  ///
  /// In en, this message translates to:
  /// **'Strong acceleration'**
  String get channelStrongAcceleration;

  /// No association: nothing varied.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{metric}: the temperature (or the metric) did not vary over 1 lap.} other{{metric}: the temperature (or the metric) did not vary over {count} laps.}}'**
  String channelAssociationNoSpread(String metric, int count);

  /// No association: too few laps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{metric}: 1 comparable lap with this temperature; at least {minimum} are needed.} other{{metric}: {count} comparable laps with this temperature; at least {minimum} are needed.}}'**
  String channelAssociationTooFew(String metric, int count, int minimum);

  /// A temperature's rank correlation with a metric over the compared laps. Never a cause.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{metric}: ρ {rho} · {strength} · 1 lap — {meaning}} other{{metric}: ρ {rho} · {strength} · {count} laps — {meaning}}}'**
  String channelAssociation(
    String metric,
    String rho,
    String strength,
    int count,
    String meaning,
  );

  /// Strength of a correlation.
  ///
  /// In en, this message translates to:
  /// **'weak'**
  String get channelStrengthWeak;

  /// Strength of a correlation.
  ///
  /// In en, this message translates to:
  /// **'moderate'**
  String get channelStrengthModerate;

  /// Strength of a correlation.
  ///
  /// In en, this message translates to:
  /// **'strong'**
  String get channelStrengthStrong;

  /// What a weak correlation means.
  ///
  /// In en, this message translates to:
  /// **'little association'**
  String get channelMeaningLittle;

  /// What a correlation of temperature with lap time means.
  ///
  /// In en, this message translates to:
  /// **'hotter laps were quicker'**
  String get channelMeaningQuicker;

  /// What a correlation of temperature with lap time means.
  ///
  /// In en, this message translates to:
  /// **'hotter laps were slower'**
  String get channelMeaningSlower;

  /// What a correlation of temperature with acceleration means.
  ///
  /// In en, this message translates to:
  /// **'hotter laps accelerated harder'**
  String get channelMeaningHarder;

  /// What a correlation of temperature with acceleration means.
  ///
  /// In en, this message translates to:
  /// **'hotter laps accelerated less'**
  String get channelMeaningLess;

  /// Heading of the card with the car's recorded temperatures.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get channelCarTitle;

  /// Car card while temperatures are read.
  ///
  /// In en, this message translates to:
  /// **'Reading each session\'s recorded temperatures…'**
  String get channelCarReading;

  /// Car card without temperature channels.
  ///
  /// In en, this message translates to:
  /// **'None of the recordings contain a temperature channel.'**
  String get channelCarNoChannels;

  /// Explains the car card.
  ///
  /// In en, this message translates to:
  /// **'Each session on its own, in recording order. Gaps in a recording are never bridged; implausible readings and placeholder zeros are left out and counted. Cooling is a continuously recorded drop of at least 5° over at least 30 s.'**
  String get channelCarIntro;

  /// A channel whose recording gives no unit.
  ///
  /// In en, this message translates to:
  /// **'units not declared by the recording'**
  String get channelUnitsNotDeclared;

  /// Why a temperature association is not a cause.
  ///
  /// In en, this message translates to:
  /// **'The temperature also changed through the day, so this cannot be told apart from everything else that changed: the driver, tyres, track and fuel.'**
  String get channelConfounded;

  /// Heart rate page intro.
  ///
  /// In en, this message translates to:
  /// **'Observed values from the recording, not an assessment.'**
  String get channelHeartRateIntro;

  /// Channel page intro.
  ///
  /// In en, this message translates to:
  /// **'Every recorded section of each session.'**
  String get channelEverySectionIntro;

  /// Heading of a temperature's association with lap performance.
  ///
  /// In en, this message translates to:
  /// **'With lap performance'**
  String get channelWithLapPerformance;

  /// Why a temperature association is not a cause.
  ///
  /// In en, this message translates to:
  /// **'The temperature also rose through the day (ρ {rho} with the order of laps), so this cannot be told apart from everything else that changed over the day: the driver, tyres, track and fuel.'**
  String channelConfoundedRose(String rho);

  /// Why a temperature association is not a cause.
  ///
  /// In en, this message translates to:
  /// **'The temperature also fell through the day (ρ {rho} with the order of laps), so this cannot be told apart from everything else that changed over the day: the driver, tyres, track and fuel.'**
  String channelConfoundedFell(String rho);

  /// How a temperature association is calculated.
  ///
  /// In en, this message translates to:
  /// **'Spearman rank correlation over the day\'s compared laps whose sensor covered at least {coverage}% of the lap. {lowCoverage} left out for low coverage, {notRecorded} without a valid reading. It describes how the two moved together on this day; it does not establish a critical temperature or a cause.'**
  String channelSpearman(int coverage, int lowCoverage, int notRecorded);

  /// Heading of the card with the driver's heart rate.
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get channelDriverTitle;

  /// Driver card while heart rate is read.
  ///
  /// In en, this message translates to:
  /// **'Reading each session\'s recorded heart rate…'**
  String get channelDriverReading;

  /// Driver card without heart rate.
  ///
  /// In en, this message translates to:
  /// **'No heart rate recorded.'**
  String get channelDriverNoHeartRate;

  /// Explains the driver card.
  ///
  /// In en, this message translates to:
  /// **'Heart rate from the recordings: observed values, not an assessment. Per lap: mean bpm; tap a lap to open it.'**
  String get channelDriverIntro;

  /// Title of the heart rate page.
  ///
  /// In en, this message translates to:
  /// **'Heart rate'**
  String get channelHeartRate;

  /// Button opening the heart rate of every section.
  ///
  /// In en, this message translates to:
  /// **'Every section…'**
  String get channelEverySection;

  /// A lap's mean heart rate, as on a timing screen.
  ///
  /// In en, this message translates to:
  /// **'LAP {number} · {mean}'**
  String channelLapMean(int number, String mean);

  /// A session whose recording cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Recording unavailable.'**
  String get channelRecordingUnavailable;

  /// Channel summaries stopped before they finished.
  ///
  /// In en, this message translates to:
  /// **'Channel summaries were cancelled.'**
  String get channelSummariesCancelled;

  /// Corner line under a loss row: the lap's minimum speed with its unit.
  ///
  /// In en, this message translates to:
  /// **'Min {speed}'**
  String cornerSummaryMin(String speed);

  /// Corner line: the lap's minimum speed and the best lap's.
  ///
  /// In en, this message translates to:
  /// **'Min {speed} (best lap {best})'**
  String cornerSummaryMinWithBest(String speed, String best);

  /// Corner line: where the lap starts braking.
  ///
  /// In en, this message translates to:
  /// **'brakes {where}'**
  String cornerSummaryBrakes(String where);

  /// Corner line: where the lap starts braking, against the best lap.
  ///
  /// In en, this message translates to:
  /// **'brakes {where} ({position})'**
  String cornerSummaryBrakesWithBest(String where, String position);

  /// A braking point before the corner's start.
  ///
  /// In en, this message translates to:
  /// **'{metres} m before'**
  String cornerBeforeEntry(int metres);

  /// A braking point inside the corner.
  ///
  /// In en, this message translates to:
  /// **'{metres} m into the corner'**
  String cornerIntoCorner(int metres);

  /// A braking point at the same place as on the best lap.
  ///
  /// In en, this message translates to:
  /// **'same'**
  String get cornerSamePosition;

  /// A braking point later than on the best lap.
  ///
  /// In en, this message translates to:
  /// **'{metres} m later'**
  String cornerLater(int metres);

  /// A braking point earlier than on the best lap.
  ///
  /// In en, this message translates to:
  /// **'{metres} m earlier'**
  String cornerEarlier(int metres);

  /// Why a session of a saved day could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Recording not found.'**
  String get missingRecordingNotFound;

  /// Why a session of a saved day could not be opened.
  ///
  /// In en, this message translates to:
  /// **'The same recording as another session of this day.'**
  String get missingRecordingDuplicate;

  /// Why a session of a saved day could not be opened.
  ///
  /// In en, this message translates to:
  /// **'The file found is a different recording.'**
  String get missingRecordingDifferent;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pl'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pl':
      return AppLocalizationsPl();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
