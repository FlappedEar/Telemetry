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
