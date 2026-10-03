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

  /// Settings button tooltip and dialog title.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Heading of the speed unit setting.
  ///
  /// In en, this message translates to:
  /// **'Unit for unlabelled speeds'**
  String get settingsSpeedUnitHeading;

  /// Explains the speed unit setting.
  ///
  /// In en, this message translates to:
  /// **'Used only for recordings that do not say their speed unit. A unit a recording declares is always shown as declared. Values are never converted.'**
  String get settingsSpeedUnitHelp;

  /// Speed unit setting: assume no unit for unlabelled speeds.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get speedUnitNone;

  /// Shown in settings when no track day is open.
  ///
  /// In en, this message translates to:
  /// **'No day open yet.'**
  String get settingsNoDayOpen;

  /// The speed units the open day's recordings declare.
  ///
  /// In en, this message translates to:
  /// **'The open day\'s recordings declare {units}.'**
  String settingsDeclaredUnits(String units);

  /// Joins two speed units: 'km/h and mph'. Keep the spaces.
  ///
  /// In en, this message translates to:
  /// **' and '**
  String get unitsAnd;

  /// None of the open day's recordings declares a speed unit.
  ///
  /// In en, this message translates to:
  /// **'Its recordings do not say their speed unit.'**
  String get settingsAllUnlabelled;

  /// Some of the open day's recordings declare no speed unit.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 of its recordings does not say its speed unit.} other{{count} of its recordings do not say their speed unit.}}'**
  String settingsSomeUnlabelled(int count);

  /// Button that closes a dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

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

  /// Link to Apple Maps' legal notices, shown on the Apple Maps background.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get appleMapLegal;

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

  /// Title of the list for changing lap B of a comparison.
  ///
  /// In en, this message translates to:
  /// **'Lap B'**
  String get lapB;

  /// Under the suggested lap in the lap picker.
  ///
  /// In en, this message translates to:
  /// **'Suggested: the fastest'**
  String get suggestedFastest;

  /// Lap picker with nothing to pick.
  ///
  /// In en, this message translates to:
  /// **'No other ranked lap of this group to compare with.'**
  String get noOtherRankedLap;

  /// Adding recordings to the day was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Adding was cancelled.'**
  String get addingCancelled;

  /// Recordings were not added because the day was closed.
  ///
  /// In en, this message translates to:
  /// **'The day was closed.'**
  String get dayClosed;

  /// Adding recordings failed; the error follows.
  ///
  /// In en, this message translates to:
  /// **'Nothing was added: {error}'**
  String nothingAddedError(String error);

  /// Title of the diagnostics page and its entry in the overflow menu.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get diagnosticsTitle;

  /// Tooltip of the diagnostics page button that reads the figures again.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get diagnosticsRefresh;

  /// Heading of the diagnostics page section about the last import.
  ///
  /// In en, this message translates to:
  /// **'Last import'**
  String get diagnosticsLastImport;

  /// Diagnostics page, shown when no day was imported yet.
  ///
  /// In en, this message translates to:
  /// **'No day imported since the app started.'**
  String get diagnosticsNoImport;

  /// Diagnostics row: how many recordings the last import read.
  ///
  /// In en, this message translates to:
  /// **'Recordings read'**
  String get diagnosticsRecordingsRead;

  /// Diagnostics row: how many sessions the imported day has.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get diagnosticsSessions;

  /// Diagnostics row: how many samples (rows of the recordings) the sessions have.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get diagnosticsSamples;

  /// Diagnostics row: how many values of all channels the sessions have.
  ///
  /// In en, this message translates to:
  /// **'Channel values'**
  String get diagnosticsChannelValues;

  /// Heading of the diagnostics page section about the app's memory.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get diagnosticsMemory;

  /// Diagnostics row: the app's memory now.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get diagnosticsCurrentMemory;

  /// Diagnostics row: the app's highest memory since it started.
  ///
  /// In en, this message translates to:
  /// **'Peak'**
  String get diagnosticsPeakMemory;

  /// Diagnostics value when the system does not report the memory.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get diagnosticsNotAvailable;

  /// Explanation under the diagnostics page's memory figures.
  ///
  /// In en, this message translates to:
  /// **'Resident memory of the app as the system reports it; the peak is since the app started. Times are wall time on this device.'**
  String get diagnosticsMemoryNote;

  /// Diagnostics step: finding the recordings to import.
  ///
  /// In en, this message translates to:
  /// **'Find recordings'**
  String get diagnosticsStepScan;

  /// Diagnostics step: reading and importing the recordings.
  ///
  /// In en, this message translates to:
  /// **'Parse and import'**
  String get diagnosticsStepParse;

  /// Diagnostics step: analysing the day.
  ///
  /// In en, this message translates to:
  /// **'Day analysis'**
  String get diagnosticsStepAnalysis;

  /// Diagnostics step: the whole import, from start until the results show.
  ///
  /// In en, this message translates to:
  /// **'Import, start to results'**
  String get diagnosticsStepImportTotal;

  /// Diagnostics step: computing the theoretical best lap and its segments.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best and segments'**
  String get diagnosticsStepTheoreticalBest;

  /// Diagnostics step: summarising the channels (temperatures, heart rate) of the day.
  ///
  /// In en, this message translates to:
  /// **'Channel summaries'**
  String get diagnosticsStepChannelSummaries;

  /// Day report heading when no group of laps is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose a group of compatible laps on the results page.'**
  String get reportGroupNone;

  /// A day report result that is being calculated.
  ///
  /// In en, this message translates to:
  /// **'Calculating…'**
  String get reportCalculating;

  /// A day report result that has not been calculated.
  ///
  /// In en, this message translates to:
  /// **'Not calculated yet.'**
  String get reportNotCalculated;

  /// A day report result made stale by an analysis change.
  ///
  /// In en, this message translates to:
  /// **'Out of date after an analysis change.'**
  String get reportOutOfDate;

  /// A day report result that is unavailable, without a reason.
  ///
  /// In en, this message translates to:
  /// **'Unavailable.'**
  String get reportUnavailable;

  /// A result missing from the day report document.
  ///
  /// In en, this message translates to:
  /// **'Not in this report.'**
  String get reportNotInReport;

  /// Why there is no best lap: no group of compatible laps is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose a compatibility group.'**
  String get reportChooseGroup;

  /// Why there is no best lap in the day report.
  ///
  /// In en, this message translates to:
  /// **'No eligible lap in this group.'**
  String get reportNoEligibleLap;

  /// Why the day report has no sessions.
  ///
  /// In en, this message translates to:
  /// **'No session in this group.'**
  String get reportNoSession;

  /// Why the day report has no consistency summary.
  ///
  /// In en, this message translates to:
  /// **'No eligible laps to summarize.'**
  String get reportNoEligibleLaps;

  /// Why the day report has no heart rate.
  ///
  /// In en, this message translates to:
  /// **'No heart rate recorded.'**
  String get reportNoHeartRate;

  /// Why the day report has no temperatures.
  ///
  /// In en, this message translates to:
  /// **'No temperature recorded.'**
  String get reportNoTemperature;

  /// Heading of the day report card with the best lap and the theoretical best.
  ///
  /// In en, this message translates to:
  /// **'Best lap and what is left'**
  String get reportBestTitle;

  /// Label above the best lap time of the day.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get reportBestLap;

  /// Label above the theoretical best time.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best'**
  String get reportTheoreticalBest;

  /// Time left between the best lap and the theoretical best.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s available across the approved segments'**
  String reportTheoreticalAvailable(String seconds);

  /// Why the theoretical best has no total.
  ///
  /// In en, this message translates to:
  /// **'Some segments have no timed lap; no total.'**
  String get reportTheoreticalNoTotal;

  /// Button opening the best lap of the day.
  ///
  /// In en, this message translates to:
  /// **'Open best lap'**
  String get reportOpenBestLap;

  /// Introduction of the focus areas in the day report.
  ///
  /// In en, this message translates to:
  /// **'Each starts with what was measured. The line under it is a hypothesis to check in the laps, not a cause or an instruction.'**
  String get reportFocusIntro;

  /// Row opening a comparison of two laps through a segment.
  ///
  /// In en, this message translates to:
  /// **'Compare {lap} with {other} at {segment}'**
  String reportFocusCompare(String lap, String other, String segment);

  /// Heading of the day report card with the largest time losses.
  ///
  /// In en, this message translates to:
  /// **'Largest time losses'**
  String get reportLossesTitle;

  /// Introduction of the time losses in the day report.
  ///
  /// In en, this message translates to:
  /// **'Against {reference} · {count, plural, =1{1 lap compared} other{{count} laps compared}}. An observed loss is not a guaranteed or necessarily safe gain.'**
  String reportLossesIntro(String reference, int count);

  /// Heading of the day report card with each session.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get reportSessionsTitle;

  /// A session without an eligible lap.
  ///
  /// In en, this message translates to:
  /// **'no eligible lap'**
  String get reportNoEligibleLapShort;

  /// A session's best lap time.
  ///
  /// In en, this message translates to:
  /// **'best {time}'**
  String reportSessionBest(String time);

  /// A session's best lap equal to the previous session's.
  ///
  /// In en, this message translates to:
  /// **'same as the previous session'**
  String get reportSameAsPrevious;

  /// A session's best lap against the previous session's.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s faster than the previous session'**
  String reportFasterThanPrevious(String seconds);

  /// A session's best lap against the previous session's.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s slower than the previous session'**
  String reportSlowerThanPrevious(String seconds);

  /// How many of a session's laps are eligible.
  ///
  /// In en, this message translates to:
  /// **'{eligible} of {count, plural, =1{1 lap} other{{count} laps}} eligible'**
  String reportEligibleLaps(int eligible, int count);

  /// A session's median lap time.
  ///
  /// In en, this message translates to:
  /// **'median {time}'**
  String reportMedian(String time);

  /// The day's lap time consistency: median and interquartile range.
  ///
  /// In en, this message translates to:
  /// **'Typical lap {time} · middle half within {spread} s · {count, plural, =1{1 lap} other{{count} laps}}'**
  String reportConsistencyDay(String time, String spread, int count);

  /// Why the day has no lap time spread.
  ///
  /// In en, this message translates to:
  /// **'{minimum, plural, =1{Fewer than 1 eligible lap; no spread.} other{Fewer than {minimum} eligible laps; no spread.}}'**
  String reportConsistencyTooFew(int minimum);

  /// The highest temperature of a channel across the day and its session.
  ///
  /// In en, this message translates to:
  /// **'{channel} · peak {value} in {session}'**
  String reportCarPeak(String channel, String value, String session);

  /// How many cooling intervals a temperature channel recorded.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recorded cooling interval} other{{count} recorded cooling intervals}}'**
  String reportCoolingIntervals(int count);

  /// A temperature channel without cooling intervals.
  ///
  /// In en, this message translates to:
  /// **'no recorded cooling'**
  String get reportNoCooling;

  /// The day report has no valid temperature.
  ///
  /// In en, this message translates to:
  /// **'No valid temperature samples.'**
  String get reportNoTemperatureSamples;

  /// A session's heart rate: mean, minimum and maximum.
  ///
  /// In en, this message translates to:
  /// **'mean {mean} bpm · {minimum} – {maximum}'**
  String reportHeartRateSummary(String mean, String minimum, String maximum);

  /// How much of a session the heart rate covers.
  ///
  /// In en, this message translates to:
  /// **'{percent}% covered'**
  String reportCovered(int percent);

  /// Title of the segment editor page.
  ///
  /// In en, this message translates to:
  /// **'Edit segments'**
  String get segmentEditorTitle;

  /// Tooltip of the button that undoes the last segment edit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get segmentEditorUndo;

  /// Tooltip of the button that redoes the last undone segment edit.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get segmentEditorRedo;

  /// Shown while the segment editor calculates the theoretical best.
  ///
  /// In en, this message translates to:
  /// **'Timing every lap on one track axis…'**
  String get segmentEditorTiming;

  /// Accessibility label of the segment editor map.
  ///
  /// In en, this message translates to:
  /// **'Best lap trace with the segment boundaries'**
  String get segmentEditorMapLabel;

  /// Accessibility label of the segment editor map with a segment selected.
  ///
  /// In en, this message translates to:
  /// **'Best lap trace with the segment boundaries, {segment} highlighted'**
  String segmentEditorMapLabelHighlighted(String segment);

  /// The segments are the automatic proposals.
  ///
  /// In en, this message translates to:
  /// **'Automatic segments'**
  String get segmentEditorAutomatic;

  /// The driver corrected the segments.
  ///
  /// In en, this message translates to:
  /// **'Edited segments'**
  String get segmentEditorEdited;

  /// The theoretical best time (or a dash) and the number of segments.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best {time} · {count, plural, =1{1 segment} other{{count} segments}}'**
  String segmentEditorSummary(String time, int count);

  /// Button that goes back to the automatic segments.
  ///
  /// In en, this message translates to:
  /// **'Restore automatic'**
  String get segmentEditorRestoreAutomatic;

  /// Hint under automatic segments; lap is a lap name.
  ///
  /// In en, this message translates to:
  /// **'Proposed from {lap}. Tap a segment to correct it.'**
  String segmentEditorProposedFrom(String lap);

  /// Hint under automatic segments when the best lap is unknown.
  ///
  /// In en, this message translates to:
  /// **'Proposed from the best lap. Tap a segment to correct it.'**
  String get segmentEditorProposedFromBestLap;

  /// Hint under edited segments.
  ///
  /// In en, this message translates to:
  /// **'Your corrections are saved with the day and are never replaced by automatic segments.'**
  String get segmentEditorCorrectionsSaved;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Corner'**
  String get segmentEditorTypeCorner;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Straight'**
  String get segmentEditorTypeStraight;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get segmentEditorTypeSector;

  /// A segment row: its type, start and end along the track and its length, in metres.
  ///
  /// In en, this message translates to:
  /// **'{type} · {start}–{end} m · {length} m'**
  String segmentEditorRow(String type, String start, String end, String length);

  /// A segment row of a segment the driver changed.
  ///
  /// In en, this message translates to:
  /// **'{row} · edited'**
  String segmentEditorRowEdited(String row);

  /// Title of the dialog confirming the automatic segments are restored.
  ///
  /// In en, this message translates to:
  /// **'Restore automatic segments?'**
  String get segmentEditorRestoreTitle;

  /// Body of the dialog confirming the automatic segments are restored.
  ///
  /// In en, this message translates to:
  /// **'Your corrections to this track layout\'s segments are replaced by the segments proposed from the best lap.'**
  String get segmentEditorRestoreBody;

  /// Confirms restoring the automatic segments.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get segmentEditorRestore;

  /// Label of the segment name field.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get segmentEditorName;

  /// Label of the segment start boundary.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get segmentEditorStart;

  /// Label of the segment end boundary.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get segmentEditorEnd;

  /// Switch: a moved boundary moves the neighbouring segment too.
  ///
  /// In en, this message translates to:
  /// **'Move the neighbouring segment too'**
  String get segmentEditorKeepJoined;

  /// Applies the segment changes.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get segmentEditorApply;

  /// Discards the segment changes not applied yet.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get segmentEditorReset;

  /// Where the segment is split, in metres along the track.
  ///
  /// In en, this message translates to:
  /// **'Split at {meters} m'**
  String segmentEditorSplitAt(String meters);

  /// Splits the segment at the chosen point.
  ///
  /// In en, this message translates to:
  /// **'Split here'**
  String get segmentEditorSplitHere;

  /// Merges the segment with the next one.
  ///
  /// In en, this message translates to:
  /// **'Merge with next'**
  String get segmentEditorMergeWithNext;

  /// Merges the segment with the next one, named by its short name.
  ///
  /// In en, this message translates to:
  /// **'Merge with {segment}'**
  String segmentEditorMergeWith(String segment);

  /// Removes the segment.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get segmentEditorRemove;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'The day is being saved.'**
  String get segmentEditorErrorSaving;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'The segments can be edited once the theoretical best is calculated.'**
  String get segmentEditorErrorNotCalculated;

  /// Why restoring the automatic segments did nothing.
  ///
  /// In en, this message translates to:
  /// **'The segments are already the automatic ones.'**
  String get segmentEditorErrorAlreadyAutomatic;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'This edit is not possible.'**
  String get segmentEditorErrorNotPossible;

  /// Why the last segment cannot be removed.
  ///
  /// In en, this message translates to:
  /// **'The theoretical best needs at least one segment. Restore the automatic segments instead.'**
  String get segmentEditorErrorLastSegment;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'This segment is no longer approved.'**
  String get segmentEditorErrorNoLongerApproved;

  /// Why undo did nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to undo.'**
  String get segmentEditorErrorNothingToUndo;

  /// Why redo did nothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to redo.'**
  String get segmentEditorErrorNothingToRedo;

  /// Why undo or redo did nothing.
  ///
  /// In en, this message translates to:
  /// **'The segments changed outside this editor, so the edit history was cleared.'**
  String get segmentEditorErrorHistoryCleared;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'The stored approved segments are invalid.'**
  String get segmentEditorErrorInvalidStored;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'Segments approved for a different track configuration must be discarded first.'**
  String get segmentEditorErrorOtherConfiguration;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'“{segment}” would become empty.'**
  String segmentEditorErrorWouldBeEmpty(String segment);

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'“{segment}” would be invalid.'**
  String segmentEditorErrorWouldBeInvalid(String segment);

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'“{segment}” would overlap “{other}”.'**
  String segmentEditorErrorWouldOverlap(String segment, String other);

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{At most 1 segment can be approved.} other{At most {count} segments can be approved.}}'**
  String segmentEditorErrorTooMany(int count);

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'Only one segment may cross the start/finish line.'**
  String get segmentEditorErrorCrossesGate;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'Choose corner, straight or sector.'**
  String get segmentEditorErrorChooseType;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'The track axis is unavailable.'**
  String get segmentEditorErrorNoAxis;

  /// Why a split is refused.
  ///
  /// In en, this message translates to:
  /// **'Split inside the segment, away from its ends.'**
  String get segmentEditorErrorSplitInside;

  /// Why a split is refused.
  ///
  /// In en, this message translates to:
  /// **'Enter a name of 1–160 characters for the new segment.'**
  String get segmentEditorErrorSplitName;

  /// Why a merge is refused.
  ///
  /// In en, this message translates to:
  /// **'Choose two different approved segments.'**
  String get segmentEditorErrorMergeSame;

  /// Why a merge is refused.
  ///
  /// In en, this message translates to:
  /// **'Only segments that share a boundary can be merged.'**
  String get segmentEditorErrorMergeNotAdjacent;

  /// Why a merge is refused.
  ///
  /// In en, this message translates to:
  /// **'Merging would cover the whole lap; a segment needs distinct start and end.'**
  String get segmentEditorErrorMergeWholeLap;

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'Enter a name of 1–160 characters.'**
  String get segmentEditorErrorName;

  /// Why a segment edit is refused; length is the track axis length.
  ///
  /// In en, this message translates to:
  /// **'Bounds must lie between 0 and {length} m.'**
  String segmentEditorErrorBounds(String length);

  /// Why a segment edit is refused.
  ///
  /// In en, this message translates to:
  /// **'A segment cannot be empty.'**
  String get segmentEditorErrorEmpty;

  /// A day report result computed before the analysis decisions changed.
  ///
  /// In en, this message translates to:
  /// **'The analysis decisions changed after this result was computed.'**
  String get reportStale;

  /// Says a channel's samples come, in whole or in part, from the session's other recording, such as 'from RCZ'; shown next to a channel's name. {format} is a recording format such as RCZ.
  ///
  /// In en, this message translates to:
  /// **'from {format}'**
  String channelFromSource(String format);

  /// A session's VBO recording was combined with its RCZ of the same drive; count is how many channels only the RCZ recorded were added. {format} is the other recording's format, such as RCZ.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{Combined with its {format}: no channel added} =1{Combined with its {format}: 1 channel added} other{Combined with its {format}: {count} channels added}}'**
  String fusionAdded(int count, String format);

  /// A channel both recordings of a session measured, whose values differ; the buttons below choose which to use. {primary} and {alternative} are formats such as VBO and RCZ.
  ///
  /// In en, this message translates to:
  /// **'{channel}: the {primary} and the {alternative} disagree'**
  String fusionConflict(String channel, String primary, String alternative);

  /// Button: keep the session's own recording (such as the VBO) for a channel both recordings disagree on.
  ///
  /// In en, this message translates to:
  /// **'Keep {format}'**
  String fusionKeepPrimary(String format);

  /// Button: keep the session's own recording for a channel and fill its gaps from the other recording.
  ///
  /// In en, this message translates to:
  /// **'Fill gaps'**
  String get fusionFillGaps;

  /// Button: use the other recording (such as the RCZ) for a channel both recordings disagree on, the session's own where it has none.
  ///
  /// In en, this message translates to:
  /// **'Use {format}'**
  String fusionUseAlternative(String format);

  /// A session's other recording (such as its RCZ) was not combined with it; reason says why.
  ///
  /// In en, this message translates to:
  /// **'Not combined with its {format}: {reason}'**
  String fusionNotCombined(String format, String reason);

  /// Why two recordings could not be lined up in time.
  ///
  /// In en, this message translates to:
  /// **'a recording has no speed'**
  String get fusionReasonNoSpeed;

  /// Why two recordings could not be lined up in time.
  ///
  /// In en, this message translates to:
  /// **'the recordings overlap too little'**
  String get fusionReasonShortOverlap;

  /// Why two recordings could not be lined up in time: their speed traces match weakly or in several places.
  ///
  /// In en, this message translates to:
  /// **'their speed traces do not line up clearly'**
  String get fusionReasonAmbiguous;

  /// Why two recordings could not be lined up in time: the loggers' start times and the speed traces give different offsets.
  ///
  /// In en, this message translates to:
  /// **'their clocks disagree with their speed traces'**
  String get fusionReasonClockDisagrees;

  /// Why two recordings could not be lined up in time.
  ///
  /// In en, this message translates to:
  /// **'not enough data to line them up'**
  String get fusionReasonInsufficient;

  /// Why a session's other recording could not be used when the day was opened.
  ///
  /// In en, this message translates to:
  /// **'the recording was not found'**
  String get fusionReasonNotFound;

  /// Why a session's other recording could not be used: a file is at its place, but with other content.
  ///
  /// In en, this message translates to:
  /// **'the file found is a different recording'**
  String get fusionReasonDifferent;

  /// Why a session's other recording could not be used.
  ///
  /// In en, this message translates to:
  /// **'it could not be read'**
  String get fusionReasonUnreadable;

  /// Quiet line under a session while its other recording (such as its RCZ) is being aligned with it in the background; the results already show.
  ///
  /// In en, this message translates to:
  /// **'Lining up with its {format}…'**
  String fusionPending(String format);

  /// Quiet line under a session whose other recording (such as its RCZ) was aligned with it but has no channel to add and no disagreement. offset is the clock offset found, such as −0.14 s.
  ///
  /// In en, this message translates to:
  /// **'Lined up with its {format} ({offset}); nothing to add'**
  String fusionLinedUp(String format, String offset);

  /// After adding recordings: an RCZ was added to existing sessions as their other recording. sessions is a list of session names such as "Session 2, Session 3".
  ///
  /// In en, this message translates to:
  /// **'{format} added to {sessions}.'**
  String fusionCombinedWith(String format, String sessions);

  /// Title of the card listing sessions whose other recording (such as the RCZ) was not found or is another recording; a button below looks for them in a folder.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The {format} of 1 session could not be used} other{The {format} of {count} sessions could not be used}}'**
  String fusionMissingTitle(int count, String format);

  /// One line of the card of other recordings that could not be used: the session, the path the day names and why.
  ///
  /// In en, this message translates to:
  /// **'{session}: {path} · {reason}'**
  String fusionMissingLine(String session, String path, String reason);

  /// A channel both recordings of a session measured: the speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get fusionChannelSpeed;

  /// A channel both recordings of a session measured: the GPS latitude.
  ///
  /// In en, this message translates to:
  /// **'Latitude'**
  String get fusionChannelLatitude;

  /// A channel both recordings of a session measured: the GPS longitude.
  ///
  /// In en, this message translates to:
  /// **'Longitude'**
  String get fusionChannelLongitude;

  /// A channel both recordings of a session measured: the number of GPS satellites.
  ///
  /// In en, this message translates to:
  /// **'Satellites'**
  String get fusionChannelSatellites;

  /// After Find recordings in a folder: a session's RCZ found there only by its file name is another drive's recording, so it was not used. files is the file name or names.
  ///
  /// In en, this message translates to:
  /// **'Not used, a different recording: {files}.'**
  String fusionRelinkDifferent(String files);

  /// After adding recordings: aligning an RCZ added to existing sessions failed. sessions is a list of session names.
  ///
  /// In en, this message translates to:
  /// **'{format} added to {sessions}, but it could not be combined; it is kept and tried again when the day opens.'**
  String fusionAddedNotCombined(String format, String sessions);

  /// Why a session's other recording was not combined: aligning it stopped with an error.
  ///
  /// In en, this message translates to:
  /// **'lining them up failed'**
  String get fusionReasonFailed;

  /// After Find recordings in a folder: files named like missing recordings that hold other recordings. files is the file names.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{files} in that folder is a different recording and was not used.} other{{files} in that folder are different recordings and were not used.}}'**
  String relinkDifferentRecordings(int count, String files);

  /// After Find recordings in a folder: none of the missing recordings was there.
  ///
  /// In en, this message translates to:
  /// **'No missing recording was found in that folder.'**
  String get relinkNothingFound;

  /// Button: place this segment boundary by tapping the track on the map.
  ///
  /// In en, this message translates to:
  /// **'Pick on map'**
  String get segmentPickOnMap;

  /// The pick button while waiting for a tap on the map; pressing it again cancels.
  ///
  /// In en, this message translates to:
  /// **'Tap the map… (cancel)'**
  String get segmentPickActive;

  /// Shown on the map while it waits for the segment's start.
  ///
  /// In en, this message translates to:
  /// **'Tap the track line to place the start'**
  String get segmentPickBannerStart;

  /// Shown on the map while it waits for the segment's end.
  ///
  /// In en, this message translates to:
  /// **'Tap the track line to place the end'**
  String get segmentPickBannerEnd;

  /// Shown on the map while it waits for where to split the segment.
  ///
  /// In en, this message translates to:
  /// **'Tap the track line to place the split'**
  String get segmentPickBannerSplit;

  /// A tap near a crossing or a parallel stretch of track: the place along the lap is unclear.
  ///
  /// In en, this message translates to:
  /// **'Another part of the track passes close by here. Set the distance with the buttons instead.'**
  String get segmentPickAmbiguous;

  /// A tap too far from the lap's trace.
  ///
  /// In en, this message translates to:
  /// **'Tap on the lap\'s track line.'**
  String get segmentPickFar;

  /// The best lap has no trace to pick a place on.
  ///
  /// In en, this message translates to:
  /// **'The lap trace is not available for picking.'**
  String get segmentPickNoTrace;

  /// The place tapped for a split is outside the segment.
  ///
  /// In en, this message translates to:
  /// **'Pick a point inside this segment to split it.'**
  String get segmentPickOutside;

  /// Heading of the theoretical best card's per-corner variability list.
  ///
  /// In en, this message translates to:
  /// **'Lap to lap in each corner'**
  String get variabilityHeading;

  /// Explains the corner variability list.
  ///
  /// In en, this message translates to:
  /// **'How much each corner changes from lap to lap over the group\'s laps: typical is the median, spread the middle half of the laps (interquartile range), from at least 3 laps. Observations, not causes.'**
  String get variabilityIntro;

  /// No corner has variability results.
  ///
  /// In en, this message translates to:
  /// **'No corner was measured on enough laps.'**
  String get variabilityNone;

  /// A corner without any measured metric.
  ///
  /// In en, this message translates to:
  /// **'Not measured on these laps.'**
  String get variabilityNotMeasured;

  /// How many laps a figure is from.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap} other{{count} laps}}'**
  String variabilityLaps(int count);

  /// A braking point or throttle pickup read from the recorded brake or throttle.
  ///
  /// In en, this message translates to:
  /// **'measured'**
  String get variabilityMeasured;

  /// A braking point or throttle pickup inferred from speed.
  ///
  /// In en, this message translates to:
  /// **'inferred'**
  String get variabilityInferred;

  /// A position metric's spread across laps.
  ///
  /// In en, this message translates to:
  /// **'{label}: spread {spread} · {tail}'**
  String variabilitySpread(String label, String spread, String tail);

  /// A speed's typical value and spread across laps.
  ///
  /// In en, this message translates to:
  /// **'{label}: typical {typical} · spread {spread} · {tail}'**
  String variabilityTypical(
    String label,
    String typical,
    String spread,
    String tail,
  );

  /// Fewer than three laps measured this metric.
  ///
  /// In en, this message translates to:
  /// **'{label}: too few laps ({tail})'**
  String variabilityTooFew(String label, String tail);

  /// Label: where braking starts.
  ///
  /// In en, this message translates to:
  /// **'Braking point'**
  String get variabilityBraking;

  /// Label: speed at the corner's apex.
  ///
  /// In en, this message translates to:
  /// **'Apex speed'**
  String get variabilityApex;

  /// Label: the lowest speed in the corner.
  ///
  /// In en, this message translates to:
  /// **'Minimum speed'**
  String get variabilityMinimum;

  /// Label: speed at the corner's exit.
  ///
  /// In en, this message translates to:
  /// **'Exit speed'**
  String get variabilityExit;

  /// Label: where the driver goes back on the throttle.
  ///
  /// In en, this message translates to:
  /// **'Throttle pickup'**
  String get variabilityPickup;

  /// How far apart the laps' lines are at the apex.
  ///
  /// In en, this message translates to:
  /// **'Line: spread {spread} m · {accuracy}'**
  String variabilityLine(String spread, String accuracy);

  /// The recording's typical GPS accuracy.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy about {meters} m'**
  String variabilityGpsAccuracy(String meters);

  /// The recording does not state its GPS accuracy.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy not recorded'**
  String get variabilityGpsUnknown;

  /// Appended when the line spread is no larger than the GPS accuracy.
  ///
  /// In en, this message translates to:
  /// **' · not distinguishable from GPS error'**
  String get variabilityLineUnresolved;

  /// Button: run the theoretical best calculation again after it failed or had nothing to use.
  ///
  /// In en, this message translates to:
  /// **'Calculate again'**
  String get calculateAgain;

  /// Button: open the sessions' recordings again from where the day says they are.
  ///
  /// In en, this message translates to:
  /// **'Retry recordings'**
  String get retryRecordings;

  /// The retry button while the recordings are read again.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get retryRecordingsLooking;

  /// The day has unsaved changes, so it cannot be opened again from its file.
  ///
  /// In en, this message translates to:
  /// **'Save the day first, then try the recordings again.'**
  String get retryRecordingsSaveFirst;

  /// Retrying found no more recordings.
  ///
  /// In en, this message translates to:
  /// **'The recordings are still not where the day says.'**
  String get retryRecordingsStill;

  /// Heading of the day page's list of sessions with their conditions, setup changes and notes.
  ///
  /// In en, this message translates to:
  /// **'Session details'**
  String get sessionDetailsHeading;

  /// Shown under a session that has no conditions, setup changes or notes.
  ///
  /// In en, this message translates to:
  /// **'No conditions, setup changes or notes'**
  String get sessionDetailsNone;

  /// Title of the dialog that edits a session's name, conditions, setup changes and notes.
  ///
  /// In en, this message translates to:
  /// **'Details of {session}'**
  String sessionDetailsTitle(String session);

  /// Text field label: the session's name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sessionDetailsName;

  /// Shown under an empty session name.
  ///
  /// In en, this message translates to:
  /// **'A session needs a name.'**
  String get sessionDetailsNameRequired;

  /// Text field label and list label: the weather and track conditions of a session.
  ///
  /// In en, this message translates to:
  /// **'Conditions'**
  String get sessionDetailsConditions;

  /// Example conditions in the empty text field.
  ///
  /// In en, this message translates to:
  /// **'Dry, 18 °C'**
  String get sessionDetailsConditionsHint;

  /// Text field label and list label: what was changed on the car before the session.
  ///
  /// In en, this message translates to:
  /// **'Setup changes'**
  String get sessionDetailsSetup;

  /// Example setup change in the empty text field. Keep the decimal point.
  ///
  /// In en, this message translates to:
  /// **'Tyres +0.1 bar'**
  String get sessionDetailsSetupHint;

  /// Text field label and list label: the driver's notes on a session.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get sessionDetailsNotes;

  /// Explains where a session's details are kept.
  ///
  /// In en, this message translates to:
  /// **'Kept in the day\'s file, which FlappedEar Overlays reads too.'**
  String get sessionDetailsSaved;

  /// Shown when an entered name or text contains characters that cannot be saved.
  ///
  /// In en, this message translates to:
  /// **'This text cannot be saved.'**
  String get detailsInvalid;

  /// Menu item that opens the dialog renaming the day.
  ///
  /// In en, this message translates to:
  /// **'Rename day…'**
  String get renameDayMenu;

  /// Title of the dialog that renames the day.
  ///
  /// In en, this message translates to:
  /// **'Rename day'**
  String get renameDayTitle;

  /// Text field label: the day's name.
  ///
  /// In en, this message translates to:
  /// **'Day name'**
  String get renameDayName;

  /// Shown under an empty day name.
  ///
  /// In en, this message translates to:
  /// **'A day needs a name.'**
  String get renameDayRequired;

  /// Retrying while recordings are still being added.
  ///
  /// In en, this message translates to:
  /// **'Wait until the recordings are added, then retry.'**
  String get retryRecordingsWaitAdding;

  /// Recordings were added to the day while it was being opened again.
  ///
  /// In en, this message translates to:
  /// **'Recordings were added meanwhile. Retry the recordings again.'**
  String get retryRecordingsAddedMeanwhile;

  /// Retrying opened none of the day's recordings.
  ///
  /// In en, this message translates to:
  /// **'None of the day\'s recordings could be opened, so the day stays as it is.'**
  String get retryRecordingsNone;

  /// Retrying could not read the day's document; reason is the error, in English.
  ///
  /// In en, this message translates to:
  /// **'The day could not be opened again: {reason}'**
  String retryRecordingsFailed(String reason);

  /// The day was edited while its recordings were being read again.
  ///
  /// In en, this message translates to:
  /// **'The day was changed meanwhile. Save it, then retry the recordings.'**
  String get retryRecordingsChangedMeanwhile;

  /// Button above the lap list that asks for lap A, then lap B, and compares them.
  ///
  /// In en, this message translates to:
  /// **'Compare two laps'**
  String get lapsCompareTwo;

  /// Button above the lap list that opens the two laps last compared, with the range and charts they were left with (saved with the day).
  ///
  /// In en, this message translates to:
  /// **'Last comparison'**
  String get lapsLastComparison;

  /// Why background work (such as reading the recordings again) failed when it gave no reason.
  ///
  /// In en, this message translates to:
  /// **'The work stopped.'**
  String get taskStopped;

  /// Why background work (such as reading the recordings again) failed when it ended without a result.
  ///
  /// In en, this message translates to:
  /// **'The work stopped unexpectedly.'**
  String get taskStoppedUnexpectedly;

  /// Button in the segment editor that opens the optional review of the automatic segment proposals.
  ///
  /// In en, this message translates to:
  /// **'Review proposals'**
  String get segmentReviewOpen;

  /// Title of the segment proposal review screen.
  ///
  /// In en, this message translates to:
  /// **'Segment proposals'**
  String get segmentReviewTitle;

  /// Undoes the last change of the segments or of a review decision.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get segmentReviewUndo;

  /// Redoes the last undone change of the segments or of a review decision.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get segmentReviewRedo;

  /// Explains that the review is optional and what rejecting does.
  ///
  /// In en, this message translates to:
  /// **'Segments are approved automatically, so this review is optional. A rejected proposal stays out of Approve all and is saved with the day.'**
  String get segmentReviewIntro;

  /// How many proposals there are and the lap they were made from.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 proposal from {lap}} other{{count} proposals from {lap}}}'**
  String segmentReviewSummary(int count, String lap);

  /// Approves every open proposal (rejected ones stay out).
  ///
  /// In en, this message translates to:
  /// **'Approve all'**
  String get segmentReviewApproveAll;

  /// Computes the proposals again from the lap.
  ///
  /// In en, this message translates to:
  /// **'Recompute'**
  String get segmentReviewRecompute;

  /// Shown after Approve all.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 proposal approved} other{{count} proposals approved}}'**
  String segmentReviewApproved(int count);

  /// Approve all found nothing it could approve.
  ///
  /// In en, this message translates to:
  /// **'No proposal could be approved.'**
  String get segmentReviewNoneApproved;

  /// Rejects this proposal.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get segmentReviewReject;

  /// Takes back the rejection of this proposal.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get segmentReviewRestore;

  /// State of a proposal awaiting a decision.
  ///
  /// In en, this message translates to:
  /// **'Proposed'**
  String get segmentReviewStateProposed;

  /// State of a proposal that is an approved segment.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get segmentReviewStateApproved;

  /// State of a proposal the driver rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get segmentReviewStateRejected;

  /// State of a proposal that overlaps an approved segment that came from an edit.
  ///
  /// In en, this message translates to:
  /// **'Overlaps approved'**
  String get segmentReviewStateSuperseded;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Corner'**
  String get segmentReviewCorner;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Straight'**
  String get segmentReviewStraight;

  /// Segment type.
  ///
  /// In en, this message translates to:
  /// **'Sector'**
  String get segmentReviewSector;

  /// A corner's total heading change, turning left.
  ///
  /// In en, this message translates to:
  /// **'{degrees}° left'**
  String segmentReviewTurnLeft(String degrees);

  /// A corner's total heading change, turning right.
  ///
  /// In en, this message translates to:
  /// **'{degrees}° right'**
  String segmentReviewTurnRight(String degrees);

  /// A proposal's start and end in metres from the line with their tolerance, and its length.
  ///
  /// In en, this message translates to:
  /// **'{start} m ±{startTolerance} → {end} m ±{endTolerance} ({length} m)'**
  String segmentReviewBounds(
    String start,
    String startTolerance,
    String end,
    String endTolerance,
    String length,
  );

  /// The proposal runs across the start/finish line.
  ///
  /// In en, this message translates to:
  /// **'Crosses start/finish'**
  String get segmentReviewCrossesLine;

  /// Why the proposal's start is uncertain.
  ///
  /// In en, this message translates to:
  /// **'Start uncertain: {reasons}'**
  String segmentReviewStartUncertain(String reasons);

  /// Why the proposal's end is uncertain.
  ///
  /// In en, this message translates to:
  /// **'End uncertain: {reasons}'**
  String segmentReviewEndUncertain(String reasons);

  /// Uncertainty: no straight between two corners.
  ///
  /// In en, this message translates to:
  /// **'Corners connect without a straight'**
  String get segmentReviewConnectedCorners;

  /// Uncertainty: the straight next to this boundary is short.
  ///
  /// In en, this message translates to:
  /// **'Short straight'**
  String get segmentReviewShortStraight;

  /// Uncertainty: the lap has no GPS near this boundary.
  ///
  /// In en, this message translates to:
  /// **'Near a GPS gap in this lap'**
  String get segmentReviewGpsGap;

  /// Where the corner turns most, from the track's shape (not from speed).
  ///
  /// In en, this message translates to:
  /// **'Geometric apex {at} m ±{tolerance} m'**
  String segmentReviewApex(String at, String tolerance);

  /// The corner has more than one apex, so none is proposed.
  ///
  /// In en, this message translates to:
  /// **'Multiple apexes — review manually'**
  String get segmentReviewApexMultiple;

  /// No apex: the corner runs across the timing gate.
  ///
  /// In en, this message translates to:
  /// **'Corner crosses the timing gate'**
  String get segmentReviewApexCrossesGate;

  /// No apex could be found for this corner.
  ///
  /// In en, this message translates to:
  /// **'Apex unresolved'**
  String get segmentReviewApexUnresolved;

  /// Shown while the theoretical best is calculated before the review.
  ///
  /// In en, this message translates to:
  /// **'Timing every lap on one track axis…'**
  String get segmentReviewWaiting;

  /// Shown while the proposals are computed.
  ///
  /// In en, this message translates to:
  /// **'Finding corners and straights…'**
  String get segmentReviewComputing;

  /// No proposals: the lap or its recording is missing.
  ///
  /// In en, this message translates to:
  /// **'The lap the segments are measured on is not available.'**
  String get segmentReviewNoLap;

  /// No proposals: the lap's GPS trace is unusable.
  ///
  /// In en, this message translates to:
  /// **'This lap\'s GPS trace cannot be made into a track axis.'**
  String get segmentReviewNoAxis;

  /// No proposals: unsplittable geometry.
  ///
  /// In en, this message translates to:
  /// **'No automatic proposal: this lap turns continuously, with no straight between corners.'**
  String get segmentReviewContinuousCorner;

  /// No proposals: no corners.
  ///
  /// In en, this message translates to:
  /// **'No automatic proposal: no corner was detected on this lap.'**
  String get segmentReviewNoCorners;

  /// No proposals: too many segments.
  ///
  /// In en, this message translates to:
  /// **'No automatic proposal: the lap would split into more than {count} segments.'**
  String segmentReviewTooMany(int count);

  /// The proposals failed.
  ///
  /// In en, this message translates to:
  /// **'The proposals could not be computed.'**
  String get segmentReviewFailed;

  /// A review action, undo or redo was not done because the day is being saved.
  ///
  /// In en, this message translates to:
  /// **'The day is being saved. Try again in a moment.'**
  String get segmentReviewSaving;

  /// A change was not done because the theoretical best is not calculated yet.
  ///
  /// In en, this message translates to:
  /// **'The segments can be changed once the theoretical best is calculated.'**
  String get segmentReviewSegmentsUnavailable;

  /// A review action was not done because the proposals are still being computed.
  ///
  /// In en, this message translates to:
  /// **'The proposals are not ready yet.'**
  String get segmentReviewNotReady;

  /// The proposal changed before the action was done.
  ///
  /// In en, this message translates to:
  /// **'This proposal is no longer available.'**
  String get segmentReviewNoLongerAvailable;

  /// Rejecting was refused: the proposal is approved or overlaps an approved segment.
  ///
  /// In en, this message translates to:
  /// **'Only open proposals can be rejected.'**
  String get segmentReviewNotOpen;

  /// The rejection could not be written in the day's document.
  ///
  /// In en, this message translates to:
  /// **'The rejection cannot be stored.'**
  String get segmentReviewNotStored;

  /// Undo found no change to undo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to undo.'**
  String get segmentReviewNothingToUndo;

  /// Redo found no change to redo.
  ///
  /// In en, this message translates to:
  /// **'Nothing to redo.'**
  String get segmentReviewNothingToRedo;

  /// Undo or redo was refused because the segments changed elsewhere; the history was cleared.
  ///
  /// In en, this message translates to:
  /// **'The segments changed outside this editor, so the edit history was cleared.'**
  String get segmentReviewHistoryCleared;

  /// An uncertainty reason this version of the app does not know.
  ///
  /// In en, this message translates to:
  /// **'Uncertain boundary'**
  String get segmentReviewUncertainOther;
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
