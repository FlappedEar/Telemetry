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

  /// Note on a map while map tiles fail to load, such as at a track without signal.
  ///
  /// In en, this message translates to:
  /// **'The map background needs a connection; the trace is drawn without it.'**
  String get mapTilesUnavailable;

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
  /// **'Detected route: {length} m, {direction} (inferred from GPS).'**
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
  /// **'FlappedEar Telemetry is released under the Apache License 2.0.\nMaps © OpenStreetMap contributors (ODbL) and © MapTiler.\nWeather data by Open-Meteo.com (CC BY 4.0).'**
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

  /// Label on the first coach item: the one thing to work on in the next run.
  ///
  /// In en, this message translates to:
  /// **'Main focus'**
  String get coachFocusLabel;

  /// Label on the coach items after the main focus: to try only once the main focus feels settled.
  ///
  /// In en, this message translates to:
  /// **'Once that feels settled'**
  String get coachLaterLabel;

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
  /// **'Coach suggestions follow DrivingCoach\'s rules and suggest an opportunity, not a promised gain. The Overview\'s areas are observations.'**
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

  /// Coach item title: the throttle was picked up before the slow point and released again.
  ///
  /// In en, this message translates to:
  /// **'Pick up the throttle once'**
  String get coachKindEarlyThrottle;

  /// Coach item title: throttle back on later than on faster laps.
  ///
  /// In en, this message translates to:
  /// **'Return to throttle sooner'**
  String get coachKindLateThrottle;

  /// Coach item heading: the session's braking points at a corner are spread out.
  ///
  /// In en, this message translates to:
  /// **'Brake at the same point every lap'**
  String get coachKindInconsistentBraking;

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

  /// What to try when the throttle is picked up early and released again.
  ///
  /// In en, this message translates to:
  /// **'Wait to pick up the throttle until you can keep it on: one smooth pickup from the slow point, as on your faster laps.'**
  String get coachActionEarlyThrottle;

  /// What to try for a late throttle return.
  ///
  /// In en, this message translates to:
  /// **'Work toward a smooth, slightly earlier throttle return after the slow point, using your faster laps as a reference.'**
  String get coachActionLateThrottle;

  /// What to try when the braking points at a corner are spread out. A marker is a fixed point beside the track (a board, a cone, a kerb).
  ///
  /// In en, this message translates to:
  /// **'Pick one braking marker and brake at it every lap. Move it only once you hit it consistently.'**
  String get coachActionInconsistentBraking;

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

  /// What was measured for braking consistency, compared with the day's three fastest laps (which can include this session's).
  ///
  /// In en, this message translates to:
  /// **'{metric}: {observed} on this session\'s laps, {reference} on your three fastest laps today.'**
  String coachMeasuredFastest(String metric, String observed, String reference);

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

  /// Where the throttle was first picked up after the braking, in metres along the lap; on the session's laps it was released again before the slow point.
  ///
  /// In en, this message translates to:
  /// **'First throttle pickup'**
  String get coachMetricFirstThrottle;

  /// The share of a session's laps (in percent) that picked up the throttle after the braking and released it again before the slow point.
  ///
  /// In en, this message translates to:
  /// **'Laps picking up the throttle early'**
  String get coachMetricEarlyThrottleShare;

  /// The mean of the longitudinal and lateral acceleration combined through a corner, in g: how hard the car was worked there, not a share of the grip available.
  ///
  /// In en, this message translates to:
  /// **'Mean combined G'**
  String get coachMetricCombinedG;

  /// The highest mean combined G at the corner on this session's laps, against the highest of the day's laps so far there (slow laps left out). Shown as '0.74 g against 0.80 g'.
  ///
  /// In en, this message translates to:
  /// **'Highest here: this session against today'**
  String get coachMetricHighestCombinedG;

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

  /// How far apart the braking starts at a corner are, from the earliest to the latest.
  ///
  /// In en, this message translates to:
  /// **'Braking point range'**
  String get coachMetricBrakingSpread;

  /// Time through the straight right after the corner; a slow exit loses time there too.
  ///
  /// In en, this message translates to:
  /// **'Straight after it'**
  String get coachMetricNextStraightTime;

  /// Heading of the check of the main focus the coach gave for the session before.
  ///
  /// In en, this message translates to:
  /// **'Main focus from {session}'**
  String coachGoalLabel(String session);

  /// The focus's measure in the session before and in this one: the median of each session's laps at that corner (the range, for braking points).
  ///
  /// In en, this message translates to:
  /// **'{metric}: {before} then, {now} in this session.'**
  String coachGoalMeasured(String metric, String before, String now);

  /// The focus's corner was drawn differently when it was given; today's corner overlapping it most was measured.
  ///
  /// In en, this message translates to:
  /// **'Measured at {segment}, as today\'s corners divide the track.'**
  String coachGoalMeasuredAt(String segment);

  /// No corner of today's segments overlaps the focus's corner as it was drawn then.
  ///
  /// In en, this message translates to:
  /// **'Not measured: today\'s corners no longer include it.'**
  String get coachGoalNoCorner;

  /// Map legend: the amber mark is the point (median) on this session's laps.
  ///
  /// In en, this message translates to:
  /// **'{metric}: this session\'s laps'**
  String coachMapThis(String metric);

  /// Map legend: the blue mark is the point (median) on the faster laps compared.
  ///
  /// In en, this message translates to:
  /// **'{metric}: your faster laps'**
  String coachMapFaster(String metric);

  /// Map legend for the braking marker: the blue mark is the point on the day's three fastest laps.
  ///
  /// In en, this message translates to:
  /// **'{metric}: your three fastest laps today'**
  String coachMapFastest(String metric);

  /// The focus's measure improved since the session before.
  ///
  /// In en, this message translates to:
  /// **'Better.'**
  String get coachGoalBetter;

  /// The focus's measure changed too little to tell.
  ///
  /// In en, this message translates to:
  /// **'About the same.'**
  String get coachGoalUnchanged;

  /// The focus's measure got worse since the session before.
  ///
  /// In en, this message translates to:
  /// **'Worse.'**
  String get coachGoalWorse;

  /// Too few laps of either session have the focus's measure at that corner.
  ///
  /// In en, this message translates to:
  /// **'Not measured in this session.'**
  String get coachGoalNotMeasured;

  /// Above the coach items.
  ///
  /// In en, this message translates to:
  /// **'Work on the main focus first. Try the others only once it feels settled.'**
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

  /// Why there is no plan: laps of every session of the day so far count.
  ///
  /// In en, this message translates to:
  /// **'A pattern was seen on fewer than three laps today, too few to plan from.'**
  String get coachReasonTooFewLaps;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'No repeated pattern is clear enough to suggest a change.'**
  String get coachReasonBelowThreshold;

  /// Why there is no plan.
  ///
  /// In en, this message translates to:
  /// **'Patterns seen earlier today do not repeat on most of this session\'s laps.'**
  String get coachReasonNotInSession;

  /// Laps the coach did not read for patterns because they are more than 5% slower than their session's median lap.
  ///
  /// In en, this message translates to:
  /// **'Left out as much slower than their session\'s typical lap (traffic, warm-up or cool-down): {laps}.'**
  String coachSlowLaps(String laps);

  /// Heading of the coached session's laps the pattern was seen on; the values shown come from them.
  ///
  /// In en, this message translates to:
  /// **'This session\'s laps'**
  String get coachWhyAffected;

  /// Heading of the laps of earlier sessions of the day the pattern was also seen on.
  ///
  /// In en, this message translates to:
  /// **'Earlier laps showing it today'**
  String get coachWhyEarlier;

  /// Heading of the faster laps used as reference.
  ///
  /// In en, this message translates to:
  /// **'Faster laps compared'**
  String get coachWhyFaster;

  /// Heading of the laps compared for braking consistency: the day's three fastest laps.
  ///
  /// In en, this message translates to:
  /// **'Your three fastest laps today'**
  String get coachWhyFastest;

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

  /// Tab of the day page with the best lap, the coach and the analysis.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get daySectionOverview;

  /// Tab of the day page with the day report: the day's results, each leading to its evidence.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get daySectionReport;

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
  /// **'Compare two laps'**
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

  /// Label of the day's best lap, at the top of the day page and on the lap page's blue bar.
  ///
  /// In en, this message translates to:
  /// **'Best lap of the day'**
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

  /// Day report button: shares (phones) or saves (desktop) the report as one PNG image.
  ///
  /// In en, this message translates to:
  /// **'Share as image'**
  String get reportShare;

  /// File type in the save dialog for the report image.
  ///
  /// In en, this message translates to:
  /// **'PNG image'**
  String get reportImageType;

  /// After the report image was saved on desktop.
  ///
  /// In en, this message translates to:
  /// **'Report saved as an image.'**
  String get reportShareSaved;

  /// Why the report image could not be made: taller than an image may be.
  ///
  /// In en, this message translates to:
  /// **'The report is too long for one image.'**
  String get reportImageTooLong;

  /// Drawing or writing the report image failed.
  ///
  /// In en, this message translates to:
  /// **'The report image could not be made: {error}'**
  String reportShareFailed(String error);

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

  /// Button under "No best lap": opens the circuit dialog of a session whose circuit could not be identified.
  ///
  /// In en, this message translates to:
  /// **'Set the circuit…'**
  String get setCircuit;

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

  /// Analysis note about a recording without GPS positions.
  ///
  /// In en, this message translates to:
  /// **'No GPS positions in this recording; laps cannot be timed.'**
  String get noteNoGps;

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

  /// Why a lap is not ranked: its time, GPS path length or average speed cannot be a lap of the circuit (for example a fake crossing of the line).
  ///
  /// In en, this message translates to:
  /// **'Lap time or length is not plausible for this circuit'**
  String get lapIssueImplausibleLap;

  /// In a card built on the theoretical best when its calculation failed; the error and Calculate again are on the Theoretical best card.
  ///
  /// In en, this message translates to:
  /// **'Not available: the theoretical best could not be calculated.'**
  String get tbFailedElsewhere;

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

  /// One cell of a sector table row, as a screen reader says it.
  ///
  /// In en, this message translates to:
  /// **'{column}: {value}'**
  String tbCellLabel(String column, String value);

  /// A sector table time that is the segment's fastest, as a screen reader says it.
  ///
  /// In en, this message translates to:
  /// **'{value}, the fastest'**
  String tbFastestCell(String value);

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
  /// **'{time} · spread {spread} s'**
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

  /// Time losses with the Each session's best scope on a one-session day: no lap is compared.
  ///
  /// In en, this message translates to:
  /// **'With one session, its best lap is the best lap of the day, so there is nothing to compare. Choose Every lap to compare all the laps.'**
  String get timeLossOnlySessionBest;

  /// Time losses when no lap gave a comparison: none other, or none timed through the segments.
  ///
  /// In en, this message translates to:
  /// **'No other lap could be compared with the best lap.'**
  String get timeLossNoOtherLap;

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
  /// **'Through {segment}, from {start} m to {end} m after the line.'**
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
  /// **'braking starts at {meters} m'**
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

  /// Under a focus area at one of the track's corners, with the track corner's name: on earlier visits to this track in this car, on how many of those that measured the corner it was among the day's costliest corners, and the date of the latest. An observation, not a cause.
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here ({corner}): it cost time on {lost} of {measured, plural, =1{1 visit} other{{measured} visits}}, last on {date}.'**
  String focusBeforeLost(int lost, int measured, String corner, String date);

  /// Under a focus area at one of the track's corners, with the track corner's name: it was among the day's costliest corners on earlier visits in this car, but not on the last two visits that measured it.
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here ({corner}): it cost time on {lost} of {measured, plural, =1{1 visit} other{{measured} visits}}, but not on the last 2 visits that measured it.'**
  String focusBeforeNotLastTwo(int lost, int measured, String corner);

  /// Under a focus area at one of the track's corners, with the track corner's name: measured on earlier visits in this car, never among a day's costliest corners.
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here ({corner}): measured on {measured, plural, =1{1 visit} other{{measured} visits}}, never among the corners that cost the most time.'**
  String focusBeforeNever(int measured, String corner);

  /// Under a focus area at one of the track's corners, with the track corner's name: the library has no earlier day at this track in this car (other cars may have driven it).
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here ({corner}): none in this car in your library.'**
  String focusBeforeNone(String corner);

  /// Under a focus area at one of the track's corners, with the track corner's name: earlier days at this track in this car did not measure it.
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here ({corner}): this corner was not measured before.'**
  String focusBeforeNotMeasured(String corner);

  /// Under a focus area whose segment does not match a corner the library keeps for this track, so it has no earlier visits to show.
  ///
  /// In en, this message translates to:
  /// **'Earlier visits here: this place is not one of the track\'s corners in your library yet.'**
  String get focusBeforeNotCorner;

  /// What a sector-gap focus area measured.
  ///
  /// In en, this message translates to:
  /// **'Your best lap ({bestLap}) was {gap} s slower through {segment} than {sourceLap}, the fastest recorded there.'**
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
  /// **'In {count} of {total} compared laps you lost time through {segment} against {reference} (median {median} s).'**
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
  /// **'Where braking starts for {segment} varies by {spread} m across the middle half of {count} laps (measured from the brake signal).'**
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

  /// The setup changes the driver noted for a session (free text).
  ///
  /// In en, this message translates to:
  /// **'Setup changes: {setup}'**
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
  /// **'spread {seconds} s'**
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
  /// **'Each session on its own, in recording order. Gaps in a recording are never bridged; implausible readings and placeholder zeros are left out and counted. Cooling is a continuously recorded drop of at least 5° over at least 30 s.'**
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
  /// **'{metres} m before'**
  String cornerBeforeEntry(int metres);

  /// A braking point inside the corner.
  ///
  /// In en, this message translates to:
  /// **'{metres} m into the corner'**
  String cornerIntoCorner(int metres);

  /// A braking point at the same place as on the best lap.
  ///
  /// In en, this message translates to:
  /// **'same'**
  String get cornerSamePosition;

  /// A braking point later than on the best lap.
  ///
  /// In en, this message translates to:
  /// **'{metres} m later'**
  String cornerLater(int metres);

  /// A braking point earlier than on the best lap.
  ///
  /// In en, this message translates to:
  /// **'{metres} m earlier'**
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

  /// Diagnostics step: aligning a session's VBO and RCZ recordings and combining their channels.
  ///
  /// In en, this message translates to:
  /// **'Align and combine VBO and RCZ'**
  String get diagnosticsStepFusion;

  /// Diagnostics step: from sharing a recording until the session is in today's day.
  ///
  /// In en, this message translates to:
  /// **'Add a session'**
  String get diagnosticsStepAddSession;

  /// Diagnostics step: the coach working out its advice.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get diagnosticsStepCoach;

  /// Diagnostics step: from sharing a recording until the Next session card has the coach's plan.
  ///
  /// In en, this message translates to:
  /// **'Add a session, until the coach\'s plan'**
  String get diagnosticsStepAddToCoach;

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
  /// **'{seconds} s available across the approved segments'**
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
  /// **'{seconds} s faster than the previous session'**
  String reportFasterThanPrevious(String seconds);

  /// A session's best lap against the previous session's.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s slower than the previous session'**
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
  /// **'Typical lap {time} · middle half within {spread} s · {count, plural, =1{1 lap} other{{count} laps}}'**
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
  /// **'mean {mean} bpm · {minimum} – {maximum}'**
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
  /// **'{type} · {start}–{end} m · {length} m'**
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

  /// Switch: moving a boundary also moves the neighbouring segment's shared boundary, so that segment grows or shrinks.
  ///
  /// In en, this message translates to:
  /// **'Move the neighbouring segment\'s boundary too'**
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
  /// **'Split at {meters} m'**
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
  /// **'Bounds must lie between 0 and {length} m.'**
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
  /// **'Line: spread {spread} m · {accuracy}'**
  String variabilityLine(String spread, String accuracy);

  /// The recording's typical GPS accuracy.
  ///
  /// In en, this message translates to:
  /// **'GPS accuracy about {meters} m'**
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

  /// Shown under a session that has no conditions, setup, setup changes or notes.
  ///
  /// In en, this message translates to:
  /// **'No conditions, setup, setup changes or notes'**
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
  /// **'Dry, 18 °C'**
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

  /// Heading of the charts on a lap page.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get lapPageChannels;

  /// How to move the cursor of a lap page on a touch screen.
  ///
  /// In en, this message translates to:
  /// **'Tap a chart or drag sideways across it to move the cursor; the white dot shows it on the map. Two fingers zoom and move the map.'**
  String get lapPageCursorHintTouch;

  /// How to move the cursor of a lap page with a mouse.
  ///
  /// In en, this message translates to:
  /// **'Drag across a chart to move the cursor; the white dot shows it on the map.'**
  String get lapPageCursorHint;

  /// A lap page whose charts were all removed.
  ///
  /// In en, this message translates to:
  /// **'No channel shown.'**
  String get lapPageNoChannel;

  /// Label of the lap page's time bar on the day's best lap.
  ///
  /// In en, this message translates to:
  /// **'Best lap of the day'**
  String get lapPageBestOfDay;

  /// Label of the lap page's time bar on a session's best lap.
  ///
  /// In en, this message translates to:
  /// **'Best lap of {session}'**
  String lapPageBestOfSession(String session);

  /// A lap the user excluded from the ranking, with the reason they gave.
  ///
  /// In en, this message translates to:
  /// **'Not ranked: excluded (“{reason}”)'**
  String lapPageNotRankedExcluded(String reason);

  /// Button that asks why to exclude the lap from the ranking.
  ///
  /// In en, this message translates to:
  /// **'Exclude from ranking…'**
  String get lapPageExclude;

  /// Button that puts an excluded lap back in the ranking.
  ///
  /// In en, this message translates to:
  /// **'Include in ranking'**
  String get lapPageInclude;

  /// Button that asks for a lap to compare this one with.
  ///
  /// In en, this message translates to:
  /// **'Compare with…'**
  String get lapPageCompareWith;

  /// A lap section without GPS, in place of its map.
  ///
  /// In en, this message translates to:
  /// **'No GPS recorded for this section.'**
  String get lapPageNoGps;

  /// Screen reader label of a lap's map.
  ///
  /// In en, this message translates to:
  /// **'Trace of {lap}, coloured by speed'**
  String lapPageTraceLabel(String lap);

  /// Label of the speed colour legend under the map.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get lapPageSpeed;

  /// Switch that draws the best lap under this one.
  ///
  /// In en, this message translates to:
  /// **'Show the best lap ({lap}) in grey'**
  String lapPageShowBest(String lap);

  /// Title of the dialog that excludes a lap from the ranking.
  ///
  /// In en, this message translates to:
  /// **'Exclude this lap'**
  String get lapPageExcludeTitle;

  /// Field for why a lap is excluded.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get lapPageReason;

  /// Example reasons in the empty reason field.
  ///
  /// In en, this message translates to:
  /// **'Traffic, yellow flag…'**
  String get lapPageReasonHint;

  /// Button that excludes the lap.
  ///
  /// In en, this message translates to:
  /// **'Exclude'**
  String get lapPageExcludeAction;

  /// Title of the page comparing two laps.
  ///
  /// In en, this message translates to:
  /// **'Compare laps'**
  String get compareTitle;

  /// A map layer neither lap recorded.
  ///
  /// In en, this message translates to:
  /// **'Not recorded on either lap.'**
  String get compareLayerNotRecordedEither;

  /// A map layer the lap shown did not record; lap is A or B.
  ///
  /// In en, this message translates to:
  /// **'Not recorded on lap {lap}.'**
  String compareLayerNotRecordedOn(String lap);

  /// A map layer without usable values; lap is A or B.
  ///
  /// In en, this message translates to:
  /// **'No usable samples on lap {lap}.'**
  String compareLayerNoSamples(String lap);

  /// Two laps that cannot be placed on one track axis.
  ///
  /// In en, this message translates to:
  /// **'No shared track position for this pair.'**
  String get compareNoSharedPosition;

  /// Difference of the two lap times, A − B.
  ///
  /// In en, this message translates to:
  /// **'Lap Δ {delta}'**
  String compareLapDelta(String delta);

  /// How to read the differences.
  ///
  /// In en, this message translates to:
  /// **'Δ is A − B: positive when A is behind.'**
  String get compareDeltaExplained;

  /// Button that swaps the two laps.
  ///
  /// In en, this message translates to:
  /// **'Swap A and B'**
  String get compareSwap;

  /// Button that makes B the best lap of A's session.
  ///
  /// In en, this message translates to:
  /// **'B: best of {session}'**
  String compareBestOfSessionAsB(String session);

  /// Button that makes B the best lap of the day.
  ///
  /// In en, this message translates to:
  /// **'B: best of the day'**
  String get compareBestOfDayAsB;

  /// Map layer choice that draws both laps in their colours.
  ///
  /// In en, this message translates to:
  /// **'Line: A / B'**
  String get compareLayerLine;

  /// A map layer choice neither lap recorded.
  ///
  /// In en, this message translates to:
  /// **'{layer} · not recorded'**
  String compareLayerOptionNotRecorded(String layer);

  /// Map layer: speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get compareLayerSpeed;

  /// Map layer: the time difference.
  ///
  /// In en, this message translates to:
  /// **'Δ time (A−B)'**
  String get compareLayerDelta;

  /// Map layer: lateral acceleration.
  ///
  /// In en, this message translates to:
  /// **'Lateral G'**
  String get compareLayerLateralG;

  /// Map layer: longitudinal acceleration.
  ///
  /// In en, this message translates to:
  /// **'Longitudinal G'**
  String get compareLayerLongitudinalG;

  /// Map layer: throttle.
  ///
  /// In en, this message translates to:
  /// **'Throttle'**
  String get compareLayerThrottle;

  /// Map layer: the recorded brake.
  ///
  /// In en, this message translates to:
  /// **'Brake (measured)'**
  String get compareLayerBrake;

  /// Map layer: a temperature, when neither lap recorded one.
  ///
  /// In en, this message translates to:
  /// **'Temperature'**
  String get compareLayerTemperature;

  /// Negative end of the time difference colour scale.
  ///
  /// In en, this message translates to:
  /// **'A ahead'**
  String get compareLayerAAhead;

  /// Positive end of the time difference colour scale.
  ///
  /// In en, this message translates to:
  /// **'A behind'**
  String get compareLayerABehind;

  /// Negative end of the longitudinal G colour scale.
  ///
  /// In en, this message translates to:
  /// **'braking'**
  String get compareLayerBraking;

  /// Positive end of the longitudinal G colour scale.
  ///
  /// In en, this message translates to:
  /// **'accelerating'**
  String get compareLayerAccelerating;

  /// Which lap the map layer colours; lap is A or B.
  ///
  /// In en, this message translates to:
  /// **'{layer} · lap {lap}'**
  String compareLegendLap(String layer, String lap);

  /// A map layer calculated rather than recorded.
  ///
  /// In en, this message translates to:
  /// **'calculated'**
  String get compareLegendCalculated;

  /// Heading of the comparison charts.
  ///
  /// In en, this message translates to:
  /// **'Channels by track position'**
  String get compareChannelsByPosition;

  /// How to read and move the comparison charts on a touch screen.
  ///
  /// In en, this message translates to:
  /// **'Both laps at the same place on the track. Tap a chart or drag sideways across it to move the cursor; the dots show both laps on the map, which two fingers zoom and move.'**
  String get compareCursorHintTouch;

  /// How to read and move the comparison charts with a mouse.
  ///
  /// In en, this message translates to:
  /// **'Both laps at the same place on the track. Drag across a chart to move the cursor; the dots show both laps on the map.'**
  String get compareCursorHint;

  /// Title of the time difference chart.
  ///
  /// In en, this message translates to:
  /// **'Δ time (A − B)'**
  String get compareDeltaChart;

  /// How to read the time difference chart.
  ///
  /// In en, this message translates to:
  /// **'+ = A behind'**
  String get compareDeltaNote;

  /// Button that opens lap A or B at the cursor.
  ///
  /// In en, this message translates to:
  /// **'Open lap {lap} here'**
  String compareOpenLapHere(String lap);

  /// Note at the end of the comparison.
  ///
  /// In en, this message translates to:
  /// **'Observed differences between two laps, not instructions.'**
  String get compareDisclaimer;

  /// The laps' recordings could not be read.
  ///
  /// In en, this message translates to:
  /// **'The recordings of these laps are not available.'**
  String get compareRecordingsUnavailable;

  /// A comparison map without GPS.
  ///
  /// In en, this message translates to:
  /// **'No GPS data in this section'**
  String get compareNoGps;

  /// Screen reader label of the comparison map.
  ///
  /// In en, this message translates to:
  /// **'Laps A and B on one map'**
  String get compareMapLabel;

  /// Why a chart line is missing: the channel is not recorded.
  ///
  /// In en, this message translates to:
  /// **'not recorded'**
  String get chartReasonNotRecorded;

  /// Why a chart line is missing: the range is not valid.
  ///
  /// In en, this message translates to:
  /// **'range not valid'**
  String get chartReasonInvalidRange;

  /// Why a chart line is missing: the channel could not be read.
  ///
  /// In en, this message translates to:
  /// **'could not be read'**
  String get chartReasonUnreadable;

  /// A chart line without data in the range shown (inside a list).
  ///
  /// In en, this message translates to:
  /// **'no data in this range'**
  String get chartNoDataInRange;

  /// A chart without data in the range shown.
  ///
  /// In en, this message translates to:
  /// **'No data in this range'**
  String get chartNoData;

  /// A chart whose lines failed, with why.
  ///
  /// In en, this message translates to:
  /// **'Not available · {reasons}'**
  String chartNotAvailable(String reasons);

  /// A chart of longitudinal G drawn with braking up.
  ///
  /// In en, this message translates to:
  /// **'braking drawn upward'**
  String get chartBrakingUp;

  /// Tooltip of the button that removes a chart.
  ///
  /// In en, this message translates to:
  /// **'Remove {channel}'**
  String chartRemove(String channel);

  /// Screen reader label of a chart.
  ///
  /// In en, this message translates to:
  /// **'{channel} chart'**
  String chartSemantics(String channel);

  /// Screen reader summary of one chart line: its lowest and highest value in the range shown. line is empty or a lap label with a colon, like 'A: '.
  ///
  /// In en, this message translates to:
  /// **'{line}from {low} to {high}'**
  String chartSemanticsRange(String line, String low, String high);

  /// Tooltip of the zoom out button of the charts.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get chartZoomOut;

  /// Tooltip of the zoom in button of the charts.
  ///
  /// In en, this message translates to:
  /// **'Zoom in around the cursor'**
  String get chartZoomIn;

  /// Tooltip of the button that shows the whole lap in the charts.
  ///
  /// In en, this message translates to:
  /// **'Whole lap'**
  String get chartWholeLap;

  /// No more charts can be added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{At most 1 chart} other{At most {count} charts}}'**
  String chartAtMost(int count);

  /// Button that adds a chart of a channel.
  ///
  /// In en, this message translates to:
  /// **'Add a channel'**
  String get chartAddChannel;

  /// Tooltip of a chart's title: opens the list of channels to show in its place.
  ///
  /// In en, this message translates to:
  /// **'Change {channel}'**
  String chartChangeChannel(String channel);

  /// Under a chart's title when the driver named the channel in settings: the channel's name in the recording.
  ///
  /// In en, this message translates to:
  /// **'recorded as {channel}'**
  String chartRecordedAs(String channel);

  /// Title of the settings page where recorded channels get the names the app shows, and its heading in settings.
  ///
  /// In en, this message translates to:
  /// **'Channel names'**
  String get channelNamesTitle;

  /// Introduction of the channel names page.
  ///
  /// In en, this message translates to:
  /// **'Give a recorded channel the name the app shows for it, such as Throttle for accelerator_pos-obd. Leave a field empty to show the recorded name. Recordings and saved days keep the recorded names.'**
  String get channelNamesHelp;

  /// Channel names page when no day is open.
  ///
  /// In en, this message translates to:
  /// **'Open a day to list all of its channels here. Channels you have named or starred are listed below.'**
  String get channelNamesNoDay;

  /// Helper text of a channel's name field when it has no name of its own.
  ///
  /// In en, this message translates to:
  /// **'Shown as recorded'**
  String get channelNamesRecordedName;

  /// Helper text of a channel's name field when it has a name.
  ///
  /// In en, this message translates to:
  /// **'Shown as {name}'**
  String channelNamesShownAs(String name);

  /// Tooltip of the button that removes a channel's name.
  ///
  /// In en, this message translates to:
  /// **'Show the recorded name'**
  String get channelNamesClear;

  /// Settings: what the channel names page is for.
  ///
  /// In en, this message translates to:
  /// **'Names shown for recorded channels, such as Throttle instead of accelerator_pos-obd, and stars that limit the chart menus to the channels you use.'**
  String get settingsChannelNamesHelp;

  /// Settings button that opens the channel names page.
  ///
  /// In en, this message translates to:
  /// **'Name channels'**
  String get settingsChannelNamesOpen;

  /// Last entry of a chart's channel menu when only starred channels are listed: lists every channel.
  ///
  /// In en, this message translates to:
  /// **'All channels…'**
  String get chartAllChannels;

  /// Title of the list of every channel a chart can show.
  ///
  /// In en, this message translates to:
  /// **'Choose a channel'**
  String get chartChooseChannel;

  /// Channel names page: what a channel's star does.
  ///
  /// In en, this message translates to:
  /// **'Star the channels you chart most: the chart menus then list only those, with All channels… for the rest.'**
  String get channelNamesListedHelp;

  /// Tooltip of a starred channel's star.
  ///
  /// In en, this message translates to:
  /// **'Listed in chart menus (tap to unstar)'**
  String get channelListedOn;

  /// Tooltip of an unstarred channel's star.
  ///
  /// In en, this message translates to:
  /// **'Star to list in chart menus'**
  String get channelListedOff;

  /// Button that takes every channel's star away, so chart menus list every channel again.
  ///
  /// In en, this message translates to:
  /// **'Unstar all'**
  String get channelListedClear;

  /// Title of a lap's coasting panel.
  ///
  /// In en, this message translates to:
  /// **'Coasting'**
  String get coastingTitle;

  /// Heading of a lap's coasting by segment.
  ///
  /// In en, this message translates to:
  /// **'By segment'**
  String get coastingBySegment;

  /// The day's segments are being calculated.
  ///
  /// In en, this message translates to:
  /// **'Coasting by segment follows once the day\'s segments are calculated…'**
  String get coastingBySegmentLoading;

  /// The lap's group has no segments.
  ///
  /// In en, this message translates to:
  /// **'Coasting by segment needs this lap\'s group to have segments.'**
  String get coastingBySegmentNeedsSegments;

  /// Heading of a lap's coasting episodes.
  ///
  /// In en, this message translates to:
  /// **'Episodes · select one to see it'**
  String get coastingEpisodes;

  /// Where an episode starts, outside any segment.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s into the lap'**
  String coastingIntoLap(String seconds);

  /// Why a lap has no G-G.
  ///
  /// In en, this message translates to:
  /// **'No longitudinal G recorded'**
  String get drivingGgNoLongitudinal;

  /// Why a lap has no G-G.
  ///
  /// In en, this message translates to:
  /// **'No lateral G recorded'**
  String get drivingGgNoLateral;

  /// Why a lap has no G-G.
  ///
  /// In en, this message translates to:
  /// **'G in an unsupported unit'**
  String get drivingGgUnsupportedUnit;

  /// Why a lap has no G-G.
  ///
  /// In en, this message translates to:
  /// **'No samples in this stretch'**
  String get drivingGgNoSamples;

  /// Why a lap has no driving states.
  ///
  /// In en, this message translates to:
  /// **'Does not cover this stretch'**
  String get drivingNoCoverage;

  /// A lap without driving states or coasting.
  ///
  /// In en, this message translates to:
  /// **'Not available'**
  String get drivingNotAvailable;

  /// How a driving state was obtained.
  ///
  /// In en, this message translates to:
  /// **'measured'**
  String get drivingMeasured;

  /// How a driving state was obtained.
  ///
  /// In en, this message translates to:
  /// **'calculated from GPS'**
  String get drivingCalculatedFromGps;

  /// How a driving state was obtained.
  ///
  /// In en, this message translates to:
  /// **'inferred'**
  String get drivingInferred;

  /// Why a driving state is unknown.
  ///
  /// In en, this message translates to:
  /// **'unexpected unit'**
  String get drivingUnexpectedUnit;

  /// Why a driving state is unknown.
  ///
  /// In en, this message translates to:
  /// **'not recorded'**
  String get drivingNotRecorded;

  /// Why a driving state is unknown.
  ///
  /// In en, this message translates to:
  /// **'pedals unknown'**
  String get drivingPedalsUnknown;

  /// Why a driving state is unknown.
  ///
  /// In en, this message translates to:
  /// **'no speed'**
  String get drivingNoSpeed;

  /// How braking while cornering was obtained.
  ///
  /// In en, this message translates to:
  /// **'brake measured, lateral G from GPS'**
  String get drivingBrakeMeasuredLateralGps;

  /// A pedal channel in an unexpected unit.
  ///
  /// In en, this message translates to:
  /// **'{channel} is in an unexpected unit'**
  String drivingUnexpectedUnitChannel(String channel);

  /// Why a pedal state is unknown: the pedal channel has no unit, stays within 0..1, and nothing shows whether it is a 0..1 fraction or a few percent.
  ///
  /// In en, this message translates to:
  /// **'pedal scale unknown'**
  String get drivingScaleUnknown;

  /// A pedal channel with no unit whose values stay within 0..1, and nothing shows whether that is a fraction or a few percent.
  ///
  /// In en, this message translates to:
  /// **'the scale of {channel} (0–1 or %) is not known'**
  String drivingScaleUnknownChannel(String channel);

  /// A lap without a brake pedal channel.
  ///
  /// In en, this message translates to:
  /// **'no brake channel'**
  String get drivingNoBrakeChannel;

  /// A lap without an accelerator pedal channel.
  ///
  /// In en, this message translates to:
  /// **'no accelerator channel'**
  String get drivingNoAcceleratorChannel;

  /// Where a lap's braking comes from.
  ///
  /// In en, this message translates to:
  /// **'brake pedal recorded'**
  String get drivingBrakeRecorded;

  /// Where a lap's braking comes from.
  ///
  /// In en, this message translates to:
  /// **'braking inferred from deceleration (no brake channel)'**
  String get drivingBrakingInferred;

  /// Where a lap's accelerating comes from.
  ///
  /// In en, this message translates to:
  /// **'accelerator pedal recorded'**
  String get drivingAcceleratorRecorded;

  /// Where a lap's accelerating comes from.
  ///
  /// In en, this message translates to:
  /// **'accelerating inferred from longitudinal G (no accelerator channel)'**
  String get drivingAcceleratingInferred;

  /// Where a lap's cornering comes from.
  ///
  /// In en, this message translates to:
  /// **'lateral G measured'**
  String get drivingLateralMeasured;

  /// Where a lap's cornering comes from.
  ///
  /// In en, this message translates to:
  /// **'lateral G calculated from GPS by the logger'**
  String get drivingLateralCalculated;

  /// Where a lap's cornering comes from.
  ///
  /// In en, this message translates to:
  /// **'no lateral G'**
  String get drivingNoLateral;

  /// Where a lap's coasting comes from.
  ///
  /// In en, this message translates to:
  /// **'Measured: from the recorded brake and accelerator pedals.'**
  String get drivingCoastingMeasured;

  /// Where a lap's coasting comes from.
  ///
  /// In en, this message translates to:
  /// **'Inferred from longitudinal G: this recording has no brake or no accelerator pedal channel.'**
  String get drivingCoastingInferred;

  /// Why a lap's coasting is unknown.
  ///
  /// In en, this message translates to:
  /// **'Cannot be told: the recording has neither pedal channels nor longitudinal G.'**
  String get drivingCoastingNoPedals;

  /// Why a lap's coasting is unknown.
  ///
  /// In en, this message translates to:
  /// **'Cannot be told: the recording has no speed.'**
  String get drivingCoastingNoSpeed;

  /// Why a lap's coasting is unknown.
  ///
  /// In en, this message translates to:
  /// **'Cannot be told: a pedal or speed channel is in an unexpected unit.'**
  String get drivingCoastingUnitMismatch;

  /// Why a lap's coasting is unknown.
  ///
  /// In en, this message translates to:
  /// **'Coasting is not available for this stretch.'**
  String get drivingCoastingUnavailable;

  /// A lap's coasting: its time, distance, episodes and share of the lap time.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s · {meters} m over {count, plural, =1{1 episode} other{{count} episodes}} ({share} % of the lap)'**
  String drivingCoastingSummaryLap(
    String seconds,
    String meters,
    int count,
    String share,
  );

  /// A lap's coasting over a zoomed stretch: its time, distance, episodes and share of the stretch time.
  ///
  /// In en, this message translates to:
  /// **'{seconds} s · {meters} m over {count, plural, =1{1 episode} other{{count} episodes}} ({share} % of the stretch)'**
  String drivingCoastingSummaryStretch(
    String seconds,
    String meters,
    int count,
    String share,
  );

  /// Coasting is an observation, never a verdict.
  ///
  /// In en, this message translates to:
  /// **'Coasting is time at speed with neither pedal pressed. It is not a mistake by itself: a lift can settle the car or be forced by traffic.'**
  String get drivingCoastingNote;

  /// Under the comparison's coasting episodes.
  ///
  /// In en, this message translates to:
  /// **'Each episode is listed by where it starts on the track; select one to move the cursor there.'**
  String get drivingCoastingEpisodesHint;

  /// The zoomed stretch a panel covers, with its length.
  ///
  /// In en, this message translates to:
  /// **'Selected stretch · {meters} m'**
  String drivingSelectedStretch(String meters);

  /// A panel covers the whole lap.
  ///
  /// In en, this message translates to:
  /// **'Whole lap'**
  String get drivingWholeLap;

  /// G channels the logger calculated from GPS.
  ///
  /// In en, this message translates to:
  /// **'calculated from GPS by the logger'**
  String get drivingGgCalculated;

  /// The G channels of lap A or B and how they were obtained.
  ///
  /// In en, this message translates to:
  /// **'{lap}: {longitudinal} / {lateral}, {provenance}'**
  String drivingGgSource(
    String lap,
    String longitudinal,
    String lateral,
    String provenance,
  );

  /// Legend entry of lap A or B.
  ///
  /// In en, this message translates to:
  /// **'Lap {lap}'**
  String drivingLap(String lap);

  /// Screen reader label of the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'G-G diagram of laps A and B: peak combined {a} and {b}'**
  String drivingGgSemantics(String a, String b);

  /// Row of the G-G table.
  ///
  /// In en, this message translates to:
  /// **'Peak lateral'**
  String get drivingPeakLateral;

  /// Row of the G-G table.
  ///
  /// In en, this message translates to:
  /// **'Peak braking'**
  String get drivingPeakBraking;

  /// Row of the G-G table.
  ///
  /// In en, this message translates to:
  /// **'Peak accelerating'**
  String get drivingPeakAccelerating;

  /// Row of the G-G table.
  ///
  /// In en, this message translates to:
  /// **'Peak combined'**
  String get drivingPeakCombined;

  /// Row of the G-G table: the number of G pairs.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get drivingSamples;

  /// Under the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'Observed accelerations, not a share of available grip. Rings every 0.5 g; a circle marks each lap\'s peaks.'**
  String get drivingGgNote;

  /// Top of the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'accelerating'**
  String get drivingGgAccelerating;

  /// Bottom of the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'braking'**
  String get drivingGgBraking;

  /// Left of the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'left'**
  String get drivingGgLeft;

  /// Right of the G-G diagram.
  ///
  /// In en, this message translates to:
  /// **'right'**
  String get drivingGgRight;

  /// Screen reader label of a driving-state strip.
  ///
  /// In en, this message translates to:
  /// **'Lap {lap} along the track'**
  String drivingStripLabel(String lap);

  /// Screen reader hint of a driving-state strip.
  ///
  /// In en, this message translates to:
  /// **'Tap to move the cursor there'**
  String get drivingStripHint;

  /// Title of the driving-state panel.
  ///
  /// In en, this message translates to:
  /// **'Driving states'**
  String get drivingStatesTitle;

  /// Driving state.
  ///
  /// In en, this message translates to:
  /// **'Braking'**
  String get drivingBraking;

  /// Driving state.
  ///
  /// In en, this message translates to:
  /// **'Braking while cornering'**
  String get drivingTrailBraking;

  /// Driving state.
  ///
  /// In en, this message translates to:
  /// **'Cornering'**
  String get drivingCornering;

  /// Driving state.
  ///
  /// In en, this message translates to:
  /// **'Accelerating'**
  String get drivingAccelerating;

  /// Driving state, and title of the comparison's coasting panel.
  ///
  /// In en, this message translates to:
  /// **'Coasting'**
  String get drivingCoasting;

  /// Under the driving-state table.
  ///
  /// In en, this message translates to:
  /// **'Each lap\'s share of its own time over this stretch. States overlap: cornering can come with braking, accelerating or coasting. Tap a strip to move the cursor there. Longer braking while cornering is not automatically better or safer.'**
  String get drivingStatesNote;

  /// Why a corner figure is missing, lower case: not measured.
  ///
  /// In en, this message translates to:
  /// **'not measured'**
  String get cornerDetailsReasonNotMeasured;

  /// Why a corner figure is missing, lower case: no braking detected.
  ///
  /// In en, this message translates to:
  /// **'no braking detected'**
  String get cornerDetailsReasonNoBraking;

  /// Why a corner figure is missing, lower case: no brake or deceleration channel.
  ///
  /// In en, this message translates to:
  /// **'no brake or deceleration channel'**
  String get cornerDetailsReasonNoBrakeOrDeceleration;

  /// Why a corner figure is missing, lower case: no brake channel.
  ///
  /// In en, this message translates to:
  /// **'no brake channel'**
  String get cornerDetailsReasonNoBrakeChannel;

  /// Why a corner figure is missing, lower case: no deceleration channel.
  ///
  /// In en, this message translates to:
  /// **'no deceleration channel'**
  String get cornerDetailsReasonNoDecelerationChannel;

  /// Why a corner figure is missing, lower case: approach cut off at the start/finish line.
  ///
  /// In en, this message translates to:
  /// **'approach cut off at the start/finish line'**
  String get cornerDetailsReasonApproachClipped;

  /// Why a corner figure is missing, lower case: approach runs into the previous corner.
  ///
  /// In en, this message translates to:
  /// **'approach runs into the previous corner'**
  String get cornerDetailsReasonApproachInPreviousCorner;

  /// Why a corner figure is missing, lower case: already braking before the approach.
  ///
  /// In en, this message translates to:
  /// **'already braking before the approach'**
  String get cornerDetailsReasonAlreadyBraking;

  /// Why a corner figure is missing, lower case: braking interrupted by a recording gap.
  ///
  /// In en, this message translates to:
  /// **'braking interrupted by a recording gap'**
  String get cornerDetailsReasonBrakingGap;

  /// Why a corner figure is missing, lower case: no samples here.
  ///
  /// In en, this message translates to:
  /// **'no samples here'**
  String get cornerDetailsReasonNoSamplesHere;

  /// Why a corner figure is missing, lower case: no throttle or acceleration channel.
  ///
  /// In en, this message translates to:
  /// **'no throttle or acceleration channel'**
  String get cornerDetailsReasonNoThrottleOrAcceleration;

  /// Why a corner figure is missing, lower case: no lift before the pickup.
  ///
  /// In en, this message translates to:
  /// **'no lift before the pickup'**
  String get cornerDetailsReasonNoLift;

  /// Why a corner figure is missing, lower case: no pickup detected.
  ///
  /// In en, this message translates to:
  /// **'no pickup detected'**
  String get cornerDetailsReasonNoPickup;

  /// Why a corner figure is missing, lower case: after a recording gap.
  ///
  /// In en, this message translates to:
  /// **'after a recording gap'**
  String get cornerDetailsReasonAfterGap;

  /// Why a corner figure is missing, lower case: cut off at the lap end.
  ///
  /// In en, this message translates to:
  /// **'cut off at the lap end'**
  String get cornerDetailsReasonCutAtLapEnd;

  /// Why a corner figure is missing, lower case: lap not fully covered here.
  ///
  /// In en, this message translates to:
  /// **'lap not fully covered here'**
  String get cornerDetailsReasonNotCovered;

  /// Why a corner figure is missing, lower case: crosses the start/finish line.
  ///
  /// In en, this message translates to:
  /// **'crosses the start/finish line'**
  String get cornerDetailsReasonCrossesGate;

  /// Why a corner figure is missing, lower case: channel unit not supported.
  ///
  /// In en, this message translates to:
  /// **'channel unit not supported'**
  String get cornerDetailsReasonUnitNotSupported;

  /// Why a corner figure is missing, lower case: channel unit not recorded.
  ///
  /// In en, this message translates to:
  /// **'channel unit not recorded'**
  String get cornerDetailsReasonUnitNotRecorded;

  /// Why a corner figure is missing, lower case: the pedal channel has no unit, stays within 0..1, and nothing shows its scale.
  ///
  /// In en, this message translates to:
  /// **'pedal scale (0–1 or %) not known'**
  String get cornerDetailsReasonScaleUnknown;

  /// A note on a corner figure, lower case: the pedal channel has no unit and was read as a 0..1 fraction, as the longitudinal G shows.
  ///
  /// In en, this message translates to:
  /// **'pedal read as 0–1'**
  String get cornerDetailsReasonScaleInferred;

  /// Why a corner figure is missing, lower case: no speed channel.
  ///
  /// In en, this message translates to:
  /// **'no speed channel'**
  String get cornerDetailsReasonNoSpeedChannel;

  /// Why a corner figure is missing, lower case: measured differently on A and B.
  ///
  /// In en, this message translates to:
  /// **'measured differently on A and B'**
  String get cornerDetailsReasonMixedProvenance;

  /// Why a corner figure is missing, lower case: segments differ between the laps.
  ///
  /// In en, this message translates to:
  /// **'segments differ between the laps'**
  String get cornerDetailsReasonSegmentsDiffer;

  /// Why a corner figure is missing, lower case: double apex: no single apex point.
  ///
  /// In en, this message translates to:
  /// **'double apex: no single apex point'**
  String get cornerDetailsReasonDoubleApex;

  /// Why a corner figure is missing, lower case: no lowest point (constant speed).
  ///
  /// In en, this message translates to:
  /// **'no lowest point (constant speed)'**
  String get cornerDetailsReasonFlatSpeed;

  /// Why a corner figure is missing, lower case: corner shape too unclear to place it.
  ///
  /// In en, this message translates to:
  /// **'corner shape too unclear to place it'**
  String get cornerDetailsReasonUnclearGeometry;

  /// Why a corner figure is missing, lower case: corner could not be measured.
  ///
  /// In en, this message translates to:
  /// **'corner could not be measured'**
  String get cornerDetailsReasonInvalidInput;

  /// Why a corner figure is missing, lower case: apex spread over a long arc.
  ///
  /// In en, this message translates to:
  /// **'apex spread over a long arc'**
  String get cornerDetailsReasonBroadApex;

  /// Why a corner figure is missing, lower case: at the edge of the corner.
  ///
  /// In en, this message translates to:
  /// **'at the edge of the corner'**
  String get cornerDetailsReasonAtBoundary;

  /// Why a corner figure is missing, lower case: not a corner.
  ///
  /// In en, this message translates to:
  /// **'not a corner'**
  String get cornerDetailsReasonNotACorner;

  /// Why a corner figure is missing, lower case: too few samples.
  ///
  /// In en, this message translates to:
  /// **'too few samples'**
  String get cornerDetailsReasonSparseSamples;

  /// Why a corner figure is missing, lower case: segment not found on this lap.
  ///
  /// In en, this message translates to:
  /// **'segment not found on this lap'**
  String get cornerDetailsReasonSegmentNotFound;

  /// Why a corner figure is missing, lower case: not recorded.
  ///
  /// In en, this message translates to:
  /// **'not recorded'**
  String get cornerDetailsReasonNotRecorded;

  /// Why a corner figure is missing, lower case: no valid samples.
  ///
  /// In en, this message translates to:
  /// **'no valid samples'**
  String get cornerDetailsReasonNoValidSamples;

  /// Why a corner figure is missing, lower case: no reference lap.
  ///
  /// In en, this message translates to:
  /// **'no reference lap'**
  String get cornerDetailsReasonNoReference;

  /// Why a corner figure is missing, lower case: not timed.
  ///
  /// In en, this message translates to:
  /// **'not timed'**
  String get cornerDetailsReasonNotTimed;

  /// Why a corner figure is missing, lower case: no approved segments.
  ///
  /// In en, this message translates to:
  /// **'no approved segments'**
  String get cornerDetailsReasonNoApprovedSegments;

  /// Why a corner figure is missing, lower case: driving state unknown.
  ///
  /// In en, this message translates to:
  /// **'driving state unknown'**
  String get cornerDetailsReasonDrivingStateUnknown;

  /// Why a corner figure is missing, lower case: not available.
  ///
  /// In en, this message translates to:
  /// **'not available'**
  String get cornerDetailsReasonNotAvailable;

  /// How a lap's braking point was found: from the deceleration, without a brake channel.
  ///
  /// In en, this message translates to:
  /// **'Inferred from deceleration'**
  String get cornerDetailsFromDeceleration;

  /// How a lap's braking point was found: from the deceleration, because the session's brake channel has no data or is not pressed in most hard brakings.
  ///
  /// In en, this message translates to:
  /// **'Inferred from deceleration: the brake channel does not show the braking'**
  String get cornerDetailsFromDecelerationBrakeUnused;

  /// How a lap's braking point was found: from the deceleration, because the brake channel has no unit, stays within 0..1, and nothing shows its scale.
  ///
  /// In en, this message translates to:
  /// **'Inferred from deceleration: the brake channel\'s scale (0–1 or %) is not known'**
  String get cornerDetailsFromDecelerationBrakeScaleUnknown;

  /// Why a corner figure is inferred, lower case: the session's brake channel has no data or is not pressed in most hard brakings.
  ///
  /// In en, this message translates to:
  /// **'the brake channel does not show the braking'**
  String get cornerDetailsReasonBrakeChannelNotUsed;

  /// How a lap's braking point was found: from the recorded brake channel.
  ///
  /// In en, this message translates to:
  /// **'From the brake channel'**
  String get cornerDetailsFromBrakeChannel;

  /// How a lap's throttle pickup was found: from the acceleration, without a throttle channel.
  ///
  /// In en, this message translates to:
  /// **'Inferred from acceleration'**
  String get cornerDetailsFromAcceleration;

  /// How a lap's throttle pickup was found: from the recorded throttle channel.
  ///
  /// In en, this message translates to:
  /// **'From the throttle channel'**
  String get cornerDetailsFromThrottleChannel;

  /// How a figure was found, when the best lap's was found another way, so they are not compared.
  ///
  /// In en, this message translates to:
  /// **'{how}; the best lap was measured differently'**
  String cornerDetailsBestMeasuredDifferently(String how);

  /// The corner speeds are not compared: the best lap's speed comes from another kind of channel.
  ///
  /// In en, this message translates to:
  /// **'The best lap’s speed was recorded differently'**
  String get cornerDetailsBestSpeedDifferent;

  /// Why the lap's minimum speed is missing.
  ///
  /// In en, this message translates to:
  /// **'Minimum: {reason}'**
  String cornerDetailsMinimumMissing(String reason);

  /// The best value of every lap of the group: highest minimum speed in the corner.
  ///
  /// In en, this message translates to:
  /// **'Highest minimum speed'**
  String get cornerDetailsHighestMinimumSpeed;

  /// The best value of every lap of the group: highest exit speed.
  ///
  /// In en, this message translates to:
  /// **'Highest exit speed'**
  String get cornerDetailsHighestExitSpeed;

  /// The best value of every lap of the group: latest braking point.
  ///
  /// In en, this message translates to:
  /// **'Latest braking point'**
  String get cornerDetailsLatestBrakingPoint;

  /// The best value of every lap of the group: earliest throttle pickup.
  ///
  /// In en, this message translates to:
  /// **'Earliest throttle pickup'**
  String get cornerDetailsEarliestPickup;

  /// A throttle pickup: metres after the corner's start.
  ///
  /// In en, this message translates to:
  /// **'{metres} m in'**
  String cornerDetailsMetresIn(int metres);

  /// Under the corner's name: the lap shown is the group's best lap.
  ///
  /// In en, this message translates to:
  /// **'{lap} · the best lap'**
  String cornerDetailsIsBestLap(String lap);

  /// Under the corner's name: the lap shown and the group's best lap it is compared with.
  ///
  /// In en, this message translates to:
  /// **'{lap} against the best lap, {best}'**
  String cornerDetailsAgainstBestLap(String lap, String best);

  /// In place of the best lap's name when there is none.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get cornerDetailsBestLapUnavailable;

  /// Column heading: the lap shown (lap A's colour).
  ///
  /// In en, this message translates to:
  /// **'This lap'**
  String get cornerDetailsThisLap;

  /// Column heading: the group's best lap (lap B's colour); a narrow column.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get cornerDetailsBestLap;

  /// Row label; unit is empty or ' (km/h)' with its leading space.
  ///
  /// In en, this message translates to:
  /// **'Entry speed{unit}'**
  String cornerDetailsEntrySpeed(String unit);

  /// Row label; unit is empty or ' (km/h)' with its leading space.
  ///
  /// In en, this message translates to:
  /// **'Minimum speed{unit}'**
  String cornerDetailsMinimumSpeed(String unit);

  /// Row label; unit is empty or ' (km/h)' with its leading space.
  ///
  /// In en, this message translates to:
  /// **'Exit speed{unit}'**
  String cornerDetailsExitSpeed(String unit);

  /// Row label: where braking starts, in metres before the corner.
  ///
  /// In en, this message translates to:
  /// **'Braking point, before the corner'**
  String get cornerDetailsBrakingPoint;

  /// Row label: how long the lap brakes.
  ///
  /// In en, this message translates to:
  /// **'Braking time'**
  String get cornerDetailsBrakingTime;

  /// Row label; unit is empty or ' (g)' with its leading space.
  ///
  /// In en, this message translates to:
  /// **'Peak deceleration{unit}'**
  String cornerDetailsPeakDeceleration(String unit);

  /// Row label: where the throttle comes back, in metres after the corner's start.
  ///
  /// In en, this message translates to:
  /// **'Throttle pickup, into the corner'**
  String get cornerDetailsPickup;

  /// Heading of the best values of every lap of the group.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Best of 1 lap} other{Best of {count} laps}}'**
  String cornerDetailsBestOfLaps(int count);

  /// Explains the corner's figures.
  ///
  /// In en, this message translates to:
  /// **'Braking point and pickup are distances from the corner’s start on the shared track axis. Later braking or an earlier pickup is not automatically faster. Laps measured another way are not compared.'**
  String get cornerDetailsExplanation;

  /// A corner without figures for the lap tapped.
  ///
  /// In en, this message translates to:
  /// **'{corner}: this lap was not measured here.'**
  String cornerDetailsNotMeasured(String corner);

  /// A segment's type in the segment picker, lower case.
  ///
  /// In en, this message translates to:
  /// **'corner'**
  String get cornerAnalyzerTypeCorner;

  /// A segment's type in the segment picker, lower case.
  ///
  /// In en, this message translates to:
  /// **'straight'**
  String get cornerAnalyzerTypeStraight;

  /// A segment's type in the segment picker, lower case.
  ///
  /// In en, this message translates to:
  /// **'sector'**
  String get cornerAnalyzerTypeSector;

  /// The Corner Analyzer uses segments proposed from another lap.
  ///
  /// In en, this message translates to:
  /// **'Segments proposed from {lap}, as used by the sector theoretical best; saving the day approves them. Boundaries are distances along that lap\'s axis, so they can shift by a few metres on these laps.'**
  String cornerAnalyzerNoteProposed(String lap);

  /// The Corner Analyzer uses segments approved on another session.
  ///
  /// In en, this message translates to:
  /// **'Segments approved on {session}, as used by the sector theoretical best. Boundaries are distances along that run\'s axis, so they can shift by a few metres on these laps.'**
  String cornerAnalyzerNoteApproved(String session);

  /// Summary: laps A and B are equally fast through the segment.
  ///
  /// In en, this message translates to:
  /// **'A and B take the same time here.'**
  String get cornerAnalyzerSummarySame;

  /// Summary: lap A or B is faster through the segment.
  ///
  /// In en, this message translates to:
  /// **'{lap} is {time} faster here.'**
  String cornerAnalyzerSummaryFaster(String lap, String time);

  /// Summary: the faster lap and the speed it gains most.
  ///
  /// In en, this message translates to:
  /// **'{lap} is {time} faster here and carries {speed} more entry speed.'**
  String cornerAnalyzerSummaryEntry(String lap, String time, String speed);

  /// Summary: the faster lap and the speed it gains most.
  ///
  /// In en, this message translates to:
  /// **'{lap} is {time} faster here and carries {speed} more minimum speed.'**
  String cornerAnalyzerSummaryMinimum(String lap, String time, String speed);

  /// Summary: the faster lap and the speed it gains most.
  ///
  /// In en, this message translates to:
  /// **'{lap} is {time} faster here and carries {speed} more lowest speed.'**
  String cornerAnalyzerSummaryLowest(String lap, String time, String speed);

  /// Summary: the faster lap and the speed it gains most.
  ///
  /// In en, this message translates to:
  /// **'{lap} is {time} faster here and carries {speed} more exit speed.'**
  String cornerAnalyzerSummaryExit(String lap, String time, String speed);

  /// Heading of the Corner Analyzer panel.
  ///
  /// In en, this message translates to:
  /// **'Corner Analyzer'**
  String get cornerAnalyzerTitle;

  /// The two laps share no approved segments.
  ///
  /// In en, this message translates to:
  /// **'No matching approved segments for these two laps. Approve the same track segmentation on both to use the Corner Analyzer.'**
  String get cornerAnalyzerEmpty;

  /// Button: analyze the laps with the theoretical best's segments.
  ///
  /// In en, this message translates to:
  /// **'Use the theoretical best’s segments'**
  String get cornerAnalyzerUseTheoreticalBest;

  /// Tooltip of the button to the previous segment.
  ///
  /// In en, this message translates to:
  /// **'Previous segment'**
  String get cornerAnalyzerPrevious;

  /// Tooltip of the button to the next segment.
  ///
  /// In en, this message translates to:
  /// **'Next segment'**
  String get cornerAnalyzerNext;

  /// Why a segment has no speed chart.
  ///
  /// In en, this message translates to:
  /// **'No speed chart: this segment crosses the start/finish line.'**
  String get cornerAnalyzerNoChart;

  /// The segment could not be analyzed.
  ///
  /// In en, this message translates to:
  /// **'No figures for this segment.'**
  String get cornerAnalyzerNoFigures;

  /// How each lap's heart rate was measured.
  ///
  /// In en, this message translates to:
  /// **'Heart rate: mean over this segment · A {a} · B {b}. Observed values only.'**
  String cornerAnalyzerHeartRateNote(String a, String b);

  /// Heart-rate samples of a lap in the segment and how much of it they cover.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 sample, {percent}% covered} other{{count} samples, {percent}% covered}}'**
  String cornerAnalyzerCoverage(int count, int percent);

  /// Explains the table's differences.
  ///
  /// In en, this message translates to:
  /// **'Δ is A − B, coloured by the lap that is faster or carries more speed. Observed differences, not instructions.'**
  String get cornerAnalyzerExplanation;

  /// Explains the table's differences, with braking or throttle pickup shown.
  ///
  /// In en, this message translates to:
  /// **'Δ is A − B, coloured by the lap that is faster or carries more speed. Braking and pickup are distances from the corner entry; braking later or picking up earlier is not automatically faster. Observed differences, not instructions.'**
  String get cornerAnalyzerExplanationWithBraking;

  /// Button: zoom the charts to the segment.
  ///
  /// In en, this message translates to:
  /// **'Zoom to segment'**
  String get cornerAnalyzerZoom;

  /// Button: open lap A or B at the segment.
  ///
  /// In en, this message translates to:
  /// **'Lap {lap} here'**
  String cornerAnalyzerOpenLap(String lap);

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get cornerAnalyzerGroupTime;

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Braking'**
  String get cornerAnalyzerGroupBraking;

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Corner'**
  String get cornerAnalyzerGroupCorner;

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get cornerAnalyzerGroupSpeed;

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get cornerAnalyzerGroupExit;

  /// Group of the table's rows (shown in capitals).
  ///
  /// In en, this message translates to:
  /// **'Driver'**
  String get cornerAnalyzerGroupDriver;

  /// Row label: the corner segment's time.
  ///
  /// In en, this message translates to:
  /// **'Time through the corner'**
  String get cornerAnalyzerTimeThroughCorner;

  /// Row label: the segment's time.
  ///
  /// In en, this message translates to:
  /// **'Sector time'**
  String get cornerAnalyzerSectorTime;

  /// Row label: metres before the corner entry where braking starts.
  ///
  /// In en, this message translates to:
  /// **'Braking starts, before entry'**
  String get cornerAnalyzerBrakingPoint;

  /// Row label: how long the lap brakes.
  ///
  /// In en, this message translates to:
  /// **'Time on the brakes'**
  String get cornerAnalyzerBrakingTime;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Peak deceleration'**
  String get cornerAnalyzerPeakDeceleration;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Entry speed'**
  String get cornerAnalyzerEntrySpeed;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Apex speed'**
  String get cornerAnalyzerApexSpeed;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Minimum speed'**
  String get cornerAnalyzerMinimumSpeed;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Top speed'**
  String get cornerAnalyzerTopSpeed;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Lowest speed'**
  String get cornerAnalyzerLowestSpeed;

  /// Row label.
  ///
  /// In en, this message translates to:
  /// **'Exit speed'**
  String get cornerAnalyzerExitSpeed;

  /// Row label: metres after the corner entry where the throttle comes back.
  ///
  /// In en, this message translates to:
  /// **'Throttle pickup, after entry'**
  String get cornerAnalyzerPickup;

  /// Row label: mean heart rate over the segment.
  ///
  /// In en, this message translates to:
  /// **'Heart rate'**
  String get cornerAnalyzerHeartRate;

  /// Under a speed difference: lap A's speed is higher.
  ///
  /// In en, this message translates to:
  /// **'A higher'**
  String get cornerAnalyzerAHigher;

  /// Under a speed difference: lap B's speed is higher.
  ///
  /// In en, this message translates to:
  /// **'B higher'**
  String get cornerAnalyzerBHigher;

  /// Under a time difference: lap A is faster.
  ///
  /// In en, this message translates to:
  /// **'A faster'**
  String get cornerAnalyzerAFaster;

  /// Under a time difference: lap B is faster.
  ///
  /// In en, this message translates to:
  /// **'B faster'**
  String get cornerAnalyzerBFaster;

  /// Under a braking point difference.
  ///
  /// In en, this message translates to:
  /// **'A brakes earlier'**
  String get cornerAnalyzerABrakesEarlier;

  /// Under a braking point difference.
  ///
  /// In en, this message translates to:
  /// **'A brakes later'**
  String get cornerAnalyzerABrakesLater;

  /// Under a braking time difference.
  ///
  /// In en, this message translates to:
  /// **'A longer'**
  String get cornerAnalyzerALonger;

  /// Under a braking time difference.
  ///
  /// In en, this message translates to:
  /// **'A shorter'**
  String get cornerAnalyzerAShorter;

  /// Under a peak deceleration difference.
  ///
  /// In en, this message translates to:
  /// **'A harder'**
  String get cornerAnalyzerAHarder;

  /// Under a peak deceleration difference.
  ///
  /// In en, this message translates to:
  /// **'A softer'**
  String get cornerAnalyzerASofter;

  /// Under a throttle pickup difference.
  ///
  /// In en, this message translates to:
  /// **'A later'**
  String get cornerAnalyzerALater;

  /// Under a throttle pickup difference.
  ///
  /// In en, this message translates to:
  /// **'A earlier'**
  String get cornerAnalyzerAEarlier;

  /// Under a difference that rounds to zero.
  ///
  /// In en, this message translates to:
  /// **'same'**
  String get cornerAnalyzerSame;

  /// Under a value inferred from another channel.
  ///
  /// In en, this message translates to:
  /// **'inferred'**
  String get cornerAnalyzerInferred;

  /// Why a value is missing on both laps.
  ///
  /// In en, this message translates to:
  /// **'{reason} (both laps)'**
  String cornerAnalyzerBothLaps(String reason);

  /// Why the laps' values are not compared.
  ///
  /// In en, this message translates to:
  /// **'Not compared: {reason}'**
  String cornerAnalyzerNotCompared(String reason);

  /// The recording has no speed unit.
  ///
  /// In en, this message translates to:
  /// **'This recording does not declare its speed unit: those values are shown as recorded, without a unit.'**
  String get cornerAnalyzerUnitNoteSpeed;

  /// The recording has no deceleration unit.
  ///
  /// In en, this message translates to:
  /// **'This recording does not declare its deceleration unit: those values are shown as recorded, without a unit.'**
  String get cornerAnalyzerUnitNoteDeceleration;

  /// The recording has no speed and no deceleration unit.
  ///
  /// In en, this message translates to:
  /// **'This recording does not declare its speed and deceleration units: those values are shown as recorded, without a unit.'**
  String get cornerAnalyzerUnitNoteBoth;

  /// Neither lap recorded speed.
  ///
  /// In en, this message translates to:
  /// **'No speed recorded on either lap: no speed chart.'**
  String get cornerAnalyzerChartNoSpeed;

  /// Neither lap has speed samples in the segment.
  ///
  /// In en, this message translates to:
  /// **'No speed samples on either lap through {segment}.'**
  String cornerAnalyzerChartNoSamples(String segment);

  /// Heading of the segment's speed chart.
  ///
  /// In en, this message translates to:
  /// **'Speed through {segment}'**
  String cornerAnalyzerChartTitle(String segment);

  /// Screen reader label of the speed chart.
  ///
  /// In en, this message translates to:
  /// **'Speed through {segment} chart'**
  String cornerAnalyzerChartLabel(String segment);

  /// Before both laps' speed at the cursor; offset is metres from the segment's start, with its sign. Keep the trailing space.
  ///
  /// In en, this message translates to:
  /// **'Cursor {offset} m: '**
  String cornerAnalyzerCursor(String offset);

  /// Chart label of the corner's entry line.
  ///
  /// In en, this message translates to:
  /// **'Entry'**
  String get cornerAnalyzerEntry;

  /// Chart label of the corner's exit line.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get cornerAnalyzerExit;

  /// Chart label of the segment's start line.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get cornerAnalyzerStart;

  /// Chart label of the segment's end line.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get cornerAnalyzerEnd;

  /// Name of the chart's speed axis when the recording declares no unit.
  ///
  /// In en, this message translates to:
  /// **'speed'**
  String get cornerAnalyzerSpeedAxis;

  /// The apex line on the chart and in its legend.
  ///
  /// In en, this message translates to:
  /// **'Apex'**
  String get cornerAnalyzerApex;

  /// Under the chart: its distance axis and shading.
  ///
  /// In en, this message translates to:
  /// **'Distance from the corner entry (m) · shaded: the corner'**
  String get cornerAnalyzerAxisCorner;

  /// Under the chart: its distance axis and shading.
  ///
  /// In en, this message translates to:
  /// **'Distance from the segment entry (m) · shaded: the segment'**
  String get cornerAnalyzerAxisSegment;

  /// Under the chart when the recording has no speed unit.
  ///
  /// In en, this message translates to:
  /// **'{axis} · speed unit not declared in the recording'**
  String cornerAnalyzerAxisNoUnit(String axis);

  /// Chart legend: the braking point marker.
  ///
  /// In en, this message translates to:
  /// **'Braking starts'**
  String get cornerAnalyzerLegendBraking;

  /// Chart legend: the throttle pickup marker.
  ///
  /// In en, this message translates to:
  /// **'Throttle pickup'**
  String get cornerAnalyzerLegendPickup;

  /// Chart legend: the marker of the corner's minimum speed (corners only).
  ///
  /// In en, this message translates to:
  /// **'Minimum speed'**
  String get cornerAnalyzerLegendMinimum;

  /// An imported session's timed laps.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 lap} other{{count} laps}}'**
  String importPageLaps(int count);

  /// Why an imported session has no laps.
  ///
  /// In en, this message translates to:
  /// **'No laps: the recording has no start/finish line.'**
  String get importPageNoGate;

  /// Why an imported session has no laps.
  ///
  /// In en, this message translates to:
  /// **'No laps: the recording has more than one start/finish line.'**
  String get importPageSeveralGates;

  /// Why an imported session has no laps.
  ///
  /// In en, this message translates to:
  /// **'No laps: the start/finish line is not valid.'**
  String get importPageInvalidGate;

  /// Why an imported session has no laps.
  ///
  /// In en, this message translates to:
  /// **'No laps: the recording has no usable GPS.'**
  String get importPageNoGps;

  /// Why an imported session has no laps.
  ///
  /// In en, this message translates to:
  /// **'No complete laps: the start/finish line was not crossed often enough.'**
  String get importPageTooFewPasses;

  /// The import stopped with an error.
  ///
  /// In en, this message translates to:
  /// **'The import failed: {error}'**
  String importPageImportFailed(String error);

  /// A folder holds too many recordings to import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{The folder holds {count} recordings; import at most {maximum} at a time. Choose a smaller folder.}}'**
  String importPageFolderTooMany(int count, int maximum);

  /// Too many recordings were chosen to import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{That is {count} recordings; import at most {maximum} at a time.}}'**
  String importPageTooMany(int count, int maximum);

  /// A folder scan stopped at its limit.
  ///
  /// In en, this message translates to:
  /// **'Stopped after {count} files and folders; recordings beyond that were not scanned.'**
  String importPageStoppedAfter(int count);

  /// Folders too deep to scan.
  ///
  /// In en, this message translates to:
  /// **'{count} folder(s) deeper than {depth} levels were not scanned.'**
  String importPageTooDeep(int count, int depth);

  /// Links in a folder were not followed.
  ///
  /// In en, this message translates to:
  /// **'{count} link(s) were not followed.'**
  String importPageLinksSkipped(int count);

  /// Files of a folder that are not recordings.
  ///
  /// In en, this message translates to:
  /// **'{count} other file(s) were ignored; only VBO and RCZ recordings are imported.'**
  String importPageOtherFilesSkipped(int count);

  /// After a file's name: it is a copy of another file.
  ///
  /// In en, this message translates to:
  /// **'same content as {other}; imported once.'**
  String importPageSameContent(String other);

  /// After a recording's name: another recording of the same drive.
  ///
  /// In en, this message translates to:
  /// **'the same drive as {other}; kept as its alternative source.'**
  String importPageSameDrive(String other);

  /// The import found nothing it could use.
  ///
  /// In en, this message translates to:
  /// **'No recording could be imported.'**
  String get importPageNoRecording;

  /// The import stopped with an unknown error.
  ///
  /// In en, this message translates to:
  /// **'Import failed.'**
  String get importPageFailed;

  /// The import's background work ended without a result.
  ///
  /// In en, this message translates to:
  /// **'Bad state: The import stopped unexpectedly.'**
  String get importPageStoppedUnexpectedly;

  /// A chosen folder cannot be scanned.
  ///
  /// In en, this message translates to:
  /// **'The folder does not exist or is not a folder.'**
  String get importPageNoFolder;

  /// A chosen folder is a link.
  ///
  /// In en, this message translates to:
  /// **'Choose the folder itself, not a link to it.'**
  String get importPageFolderLink;

  /// A folder holds no recordings.
  ///
  /// In en, this message translates to:
  /// **'No VBO or RCZ recordings were found.'**
  String get importPageNoneFound;

  /// A folder holds no recordings; its subfolders were not scanned.
  ///
  /// In en, this message translates to:
  /// **'No VBO or RCZ recordings were found (subfolders were not included).'**
  String get importPageNoneFoundNoSubfolders;

  /// Nothing chosen is a recording.
  ///
  /// In en, this message translates to:
  /// **'No VBO or RCZ recordings to import.'**
  String get importPageNothingToImport;

  /// After a file's name.
  ///
  /// In en, this message translates to:
  /// **'not found; not imported.'**
  String get importPageFileNotFound;

  /// After a file's name.
  ///
  /// In en, this message translates to:
  /// **'a macOS metadata file, not a recording; not imported.'**
  String get importPageMetadataFile;

  /// After a file's name.
  ///
  /// In en, this message translates to:
  /// **'a link; not followed.'**
  String get importPageFileLink;

  /// After a file's name.
  ///
  /// In en, this message translates to:
  /// **'not a VBO or RCZ recording; not imported.'**
  String get importPageNotRecording;

  /// Restoring an unsaved day failed.
  ///
  /// In en, this message translates to:
  /// **'The day could not be restored: {error}'**
  String importPageNotRestored(String error);

  /// Asks before discarding a day's unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard the changes to {day}?'**
  String importPageDiscardTitle(String day);

  /// Explains discarding unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'The unsaved changes are lost. Recordings and saved days are not touched.'**
  String get importPageDiscardBody;

  /// Button: keep the unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get importPageKeep;

  /// Button: discard the unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get importPageDiscard;

  /// Discarding unsaved changes failed.
  ///
  /// In en, this message translates to:
  /// **'Not discarded: {error}'**
  String importPageNotDiscarded(String error);

  /// A saved day none of whose recordings could be read.
  ///
  /// In en, this message translates to:
  /// **'{day} could not be opened'**
  String importPageCannotOpenTitle(String day);

  /// Before the day's recordings and why each could not be used.
  ///
  /// In en, this message translates to:
  /// **'None of its recordings could be used:'**
  String get importPageNoneUsable;

  /// How to find a day's recordings.
  ///
  /// In en, this message translates to:
  /// **'Choose the folder the recordings are in to use them, also when they have not moved.'**
  String get importPageChooseFolderHint;

  /// Recordings shared from another app are imported behind the page shown.
  ///
  /// In en, this message translates to:
  /// **'Importing the shared recordings. Go back to Import sessions to see them.'**
  String get importPageImportingBehind;

  /// Title of the list of saved days.
  ///
  /// In en, this message translates to:
  /// **'Open a saved day'**
  String get importPageOpenSavedTitle;

  /// Opens a file picker for a saved day not in the list.
  ///
  /// In en, this message translates to:
  /// **'Another file…'**
  String get importPageAnotherFile;

  /// A day was chosen while another is being opened.
  ///
  /// In en, this message translates to:
  /// **'Another day is being opened. Try again after it.'**
  String get importPageAnotherOpening;

  /// Opening a saved day failed.
  ///
  /// In en, this message translates to:
  /// **'The day could not be opened: {error}'**
  String importPageNotOpened(String error);

  /// Title of the import page, the app's first page.
  ///
  /// In en, this message translates to:
  /// **'Import sessions'**
  String get importPageTitle;

  /// A day with unsaved changes that can be restored, and when they were made.
  ///
  /// In en, this message translates to:
  /// **'{day} has unsaved changes from {time}.'**
  String importPageUnsaved(String day, String time);

  /// Button: restore the day with unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get importPageRestore;

  /// Button: asks before discarding the unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Discard…'**
  String get importPageDiscardEllipsis;

  /// Explains the import page on desktops.
  ///
  /// In en, this message translates to:
  /// **'Choose the VBO or RCZ recording of each session as you drive, or a folder with a whole day, or drop them here. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.'**
  String get importPageIntroDrop;

  /// Explains the import page when folders can be picked.
  ///
  /// In en, this message translates to:
  /// **'Choose the VBO or RCZ recording of each session as you drive, or a folder with a whole day. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.'**
  String get importPageIntroFolder;

  /// Explains the import page on phones.
  ///
  /// In en, this message translates to:
  /// **'Choose the VBO or RCZ recording of each session as you drive. Sessions of the same date as the day you worked on last, in the last 24 hours, are added to it.'**
  String get importPageIntro;

  /// Button: pick recordings to import.
  ///
  /// In en, this message translates to:
  /// **'Import sessions…'**
  String get importPageChooseRecordings;

  /// Button: pick a folder to import.
  ///
  /// In en, this message translates to:
  /// **'Choose a folder…'**
  String get importPageChooseFolder;

  /// A saved day is being opened.
  ///
  /// In en, this message translates to:
  /// **'Opening…'**
  String get importPageOpening;

  /// Button: open a saved day.
  ///
  /// In en, this message translates to:
  /// **'Open a saved day…'**
  String get importPageOpenSaved;

  /// Screen-reader label of the import's progress bar.
  ///
  /// In en, this message translates to:
  /// **'Importing recordings'**
  String get importPageProgress;

  /// Under a failed import: what to do next.
  ///
  /// In en, this message translates to:
  /// **'Choose the recordings again, or other ones, above.'**
  String get importPageChooseAgain;

  /// Checkbox: also import a folder's subfolders.
  ///
  /// In en, this message translates to:
  /// **'Include subfolders'**
  String get importPageIncludeSubfolders;

  /// Heading of what was skipped or failed.
  ///
  /// In en, this message translates to:
  /// **'Import notes'**
  String get importPageNotes;

  /// The import is looking for recordings.
  ///
  /// In en, this message translates to:
  /// **'Looking for recordings…'**
  String get importPageLooking;

  /// Import progress.
  ///
  /// In en, this message translates to:
  /// **'Preparing recording {number} of {total}…'**
  String importPagePreparing(int number, int total);

  /// The import was cancelled.
  ///
  /// In en, this message translates to:
  /// **'Import cancelled. Nothing was imported.'**
  String get importPageCancelled;

  /// Heading of a finished import.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session imported} other{{count} sessions imported}}'**
  String importPageSessionsImported(int count);

  /// Button: open an imported day, or the day closed last.
  ///
  /// In en, this message translates to:
  /// **'Open the day'**
  String get importPageShowResults;

  /// Under the day closed last: it has unsaved changes, kept since this time.
  ///
  /// In en, this message translates to:
  /// **'Not saved yet; changes kept from {time}.'**
  String importPageDayUnsaved(String time);

  /// Under the day closed last: the file it is saved in.
  ///
  /// In en, this message translates to:
  /// **'Saved as {file}.'**
  String importPageDaySaved(String file);

  /// Under the day closed last: it was neither saved nor kept for recovery.
  ///
  /// In en, this message translates to:
  /// **'Not saved.'**
  String get importPageDayNotKept;

  /// A day is being opened, or recordings added to today's day before it shows.
  ///
  /// In en, this message translates to:
  /// **'Opening the day…'**
  String get importPageOpeningDay;

  /// The file type shown in the file picker when choosing recordings.
  ///
  /// In en, this message translates to:
  /// **'VBO and RCZ recordings'**
  String get importPageRecordingTypes;

  /// The folder picker's confirm button.
  ///
  /// In en, this message translates to:
  /// **'Import this folder'**
  String get importPageImportThisFolder;

  /// A picked file is not a recording the app reads.
  ///
  /// In en, this message translates to:
  /// **'Choose a VBO or RaceChrono RCZ telemetry file.'**
  String get importPageChooseFile;

  /// A picked recording is missing or is not a regular file.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source is not an existing regular file.'**
  String get importPageNotRegularFile;

  /// An import was refused because it had too many files.
  ///
  /// In en, this message translates to:
  /// **'Too many files in one import; select a smaller batch.'**
  String get importPageTooManyFiles;

  /// A recording path is longer than the app accepts.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source path is too long.'**
  String get importPagePathTooLong;

  /// A recording is empty or too large.
  ///
  /// In en, this message translates to:
  /// **'Telemetry file is empty or exceeds the per-file import limit.'**
  String get importPageFileSize;

  /// The files of one import are too large together.
  ///
  /// In en, this message translates to:
  /// **'Batch input-byte limit exceeded; import fewer recordings.'**
  String get importPageBatchBytes;

  /// A recording is a copy of another file of the same import.
  ///
  /// In en, this message translates to:
  /// **'Identical file content already present in this batch.'**
  String get importPageIdenticalContent;

  /// A recording changed while it was being read.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source changed during import; retry with a stable file.'**
  String get importPageSourceChanged;

  /// A recording whose times are not valid.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source has an invalid time range.'**
  String get importPageInvalidTimeRange;

  /// A recording whose channel times and values do not match.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source has mismatched channel timestamps and values.'**
  String get importPageMismatchedChannels;

  /// The recordings of one import hold too many samples together.
  ///
  /// In en, this message translates to:
  /// **'Batch decoded-sample limit exceeded; import fewer recordings.'**
  String get importPageBatchSamples;

  /// The recordings of one import could not be grouped within the limit.
  ///
  /// In en, this message translates to:
  /// **'Source grouping exceeds the import limit.'**
  String get importPageGroupingLimit;

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
  /// **'{start} m ±{startTolerance} → {end} m ±{endTolerance} ({length} m)'**
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
  /// **'Geometric apex {at} m ±{tolerance} m'**
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

  /// Quiet line under a session whose other recording (such as its RCZ, or its VBO after the RCZ was made primary) is kept beside it without being combined: the session's analysis uses its own recording only.
  ///
  /// In en, this message translates to:
  /// **'Its {format} is kept beside it and not combined'**
  String recordingsKeptApart(String format);

  /// Like recordingsKeptApart, for a VBO session whose RCZ the user refused: the day's file cannot store that choice, so the RCZ is lined up and combined again automatically when the day is opened again.
  ///
  /// In en, this message translates to:
  /// **'Its {format} is kept beside it and not combined until the day is opened again'**
  String recordingsKeptApartUntilReopened(String format);

  /// Button under a session with two recordings (a VBO and an RCZ): measures again how the other recording's clock lines up with the session's, to accept or refuse.
  ///
  /// In en, this message translates to:
  /// **'Check clock'**
  String get recordingsCheckClock;

  /// Button under a session with two recordings: the other recording (such as the RCZ) becomes the session's primary recording; its laps and results are calculated again from it.
  ///
  /// In en, this message translates to:
  /// **'Make {format} primary'**
  String recordingsMakePrimary(String format);

  /// Button under a session combined with its other recording: keep the other recording beside it without combining it (refuse the alignment).
  ///
  /// In en, this message translates to:
  /// **'Don\'t combine'**
  String get recordingsDontCombine;

  /// Quiet line under a session while its other recording (such as the RCZ) is being read as its primary recording in the background.
  ///
  /// In en, this message translates to:
  /// **'Reading the {format} as this session\'s recording…'**
  String recordingsChangingPrimary(String format);

  /// Quiet line under a session while the clocks of its two recordings are being compared in the background.
  ///
  /// In en, this message translates to:
  /// **'Comparing the clocks of the {primary} and the {alternative}…'**
  String clockChecking(String primary, String alternative);

  /// Result of a session's clock check: the other recording's clock lines up with the session's recording.
  ///
  /// In en, this message translates to:
  /// **'The clocks line up.'**
  String get clockAligned;

  /// Result of a session's clock check when the recordings could not be lined up in time; reason is one of the fusionReason texts.
  ///
  /// In en, this message translates to:
  /// **'The clocks cannot be lined up: {reason}.'**
  String clockNotAligned(String reason);

  /// The clock offset measured between a session's two recordings. offset is signed, such as +0.10 s; uncertainty such as 0.02 s.
  ///
  /// In en, this message translates to:
  /// **'Measured from the speed traces: {primary} time = {alternative} time {offset} ± {uncertainty}'**
  String clockMeasured(
    String primary,
    String alternative,
    String offset,
    String uncertainty,
  );

  /// How fast the two recordings' clocks drift apart, in parts per million, as measured.
  ///
  /// In en, this message translates to:
  /// **'Clock drift: {ppm} ppm'**
  String clockDrift(String ppm);

  /// Evidence of a clock check: how closely the two speed traces match, over how long both recordings run, and how many stretches of that overlap give the same offset.
  ///
  /// In en, this message translates to:
  /// **'Speed correlation {correlation} over {overlap} of overlap; {used} of {windows} stretches agree'**
  String clockCorrelation(
    String correlation,
    String overlap,
    int used,
    int windows,
  );

  /// Evidence of a clock check: the offset the two loggers' own start times give, such as +0.10 s.
  ///
  /// In en, this message translates to:
  /// **'The loggers\' clocks say {offset}'**
  String clockDeclared(String offset);

  /// Evidence of a clock check: at least one recording has no start time of its own.
  ///
  /// In en, this message translates to:
  /// **'The loggers do not both state a start time'**
  String get clockNoDeclared;

  /// Button after a clock check whose clocks line up: combine the other recording with the session using the measured offset.
  ///
  /// In en, this message translates to:
  /// **'Accept and combine'**
  String get clockAccept;

  /// Button after a clock check: do not use the measured alignment; the other recording is kept beside the session without combining it.
  ///
  /// In en, this message translates to:
  /// **'Refuse'**
  String get clockRefuse;

  /// Explains the Refuse button of a clock check.
  ///
  /// In en, this message translates to:
  /// **'Refusing keeps the {alternative} beside the session without combining it; its analysis then uses the {primary} only.'**
  String clockRefuseNote(String primary, String alternative);

  /// Shown with the Refuse button of a VBO session's clock check: the shared file format has no place for a refusal, so the RCZ is combined again automatically the next time the day is opened.
  ///
  /// In en, this message translates to:
  /// **'This session reads its VBO and keeps its RCZ, and the day\'s file cannot keep a refusal for such a session: when the day is opened again, the {alternative} is lined up and combined again.'**
  String clockReopenNote(String alternative);

  /// Under a session: its clock check failed; nothing changed.
  ///
  /// In en, this message translates to:
  /// **'The clocks could not be compared. Try again.'**
  String get recordingsClockFailed;

  /// Under a session: Make primary was refused because the other recording's file is gone; nothing changed.
  ///
  /// In en, this message translates to:
  /// **'The {format} is no longer where it was read from. Put it back there, then make it primary.'**
  String recordingsPrimaryMissing(String format);

  /// Under a session: Make primary was refused because the other recording's file now has other content; nothing changed.
  ///
  /// In en, this message translates to:
  /// **'The {format} file has changed since it was read. Open the day again, then make it primary.'**
  String recordingsPrimaryChanged(String format);

  /// Under a session: Make primary failed while reading the other recording; nothing changed.
  ///
  /// In en, this message translates to:
  /// **'The {format} could not be read as this session\'s recording.'**
  String recordingsPrimaryFailed(String format);

  /// Find recordings was refused because a clock check or a primary change is running.
  ///
  /// In en, this message translates to:
  /// **'Wait until the session\'s recordings are checked or changed, then find the others.'**
  String get recordingsBusyFind;

  /// Retry recordings was refused because a clock check or a primary change is running.
  ///
  /// In en, this message translates to:
  /// **'Wait until the session\'s recordings are checked or changed, then retry.'**
  String get recordingsBusyRetry;

  /// Leaving the day was refused because a clock check or a primary change is running.
  ///
  /// In en, this message translates to:
  /// **'Wait until the session\'s recordings are checked or changed.'**
  String get recordingsBusyLeave;

  /// Under a session: Make primary was refused because the day has unsaved changes; the user saves first.
  ///
  /// In en, this message translates to:
  /// **'Save the day before changing the primary recording.'**
  String get recordingsUnsaved;

  /// Add recordings was refused because a clock check or a primary change is running.
  ///
  /// In en, this message translates to:
  /// **'Wait until the session\'s recordings are checked or changed, then add recordings.'**
  String get recordingsBusyAdd;

  /// Label of the lap page's time bar when the lap is not a best lap.
  ///
  /// In en, this message translates to:
  /// **'This lap'**
  String get lapPageThisLap;

  /// Under the lap page's two time bars: how far this lap is from the best lap of the day.
  ///
  /// In en, this message translates to:
  /// **'{delta} to the best of the day'**
  String lapPageGapToBest(String delta);

  /// Above an imported session's best lap time (its best ranked lap, or its fastest lap when the day does not rank it), in the list of imported sessions.
  ///
  /// In en, this message translates to:
  /// **'Best'**
  String get importPageBest;

  /// Tooltip of the button that chooses the map background.
  ///
  /// In en, this message translates to:
  /// **'Map background'**
  String get mapBackgroundMenu;

  /// Map background: street map.
  ///
  /// In en, this message translates to:
  /// **'Streets'**
  String get mapBackgroundStreets;

  /// Map background: satellite imagery.
  ///
  /// In en, this message translates to:
  /// **'Satellite'**
  String get mapBackgroundSatellite;

  /// Map background: Apple Maps (a product name, keep it).
  ///
  /// In en, this message translates to:
  /// **'Apple Maps'**
  String get mapBackgroundApple;

  /// Map background: no map, the track line only.
  ///
  /// In en, this message translates to:
  /// **'Plain'**
  String get mapBackgroundPlain;

  /// The file type shown in the file picker when opening or saving a day.
  ///
  /// In en, this message translates to:
  /// **'FlappedEar day'**
  String get documentPickerDays;

  /// The folder picker's confirm button when looking for a day's missing recordings.
  ///
  /// In en, this message translates to:
  /// **'Look in this folder'**
  String get documentPickerLookInFolder;

  /// Under the track map when the lap has no speed channel, so the trace has no speed colours.
  ///
  /// In en, this message translates to:
  /// **'No speed recorded; the trace is drawn in one colour.'**
  String get speedLegendNoSpeed;

  /// Short message shown at the bottom of any page after an unexpected error; Diagnostics is the page in the More menu.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Details are in Diagnostics.'**
  String get appErrorNotice;

  /// Shown in place of a part of a page that failed to display, in release builds.
  ///
  /// In en, this message translates to:
  /// **'This part could not be shown.'**
  String get appErrorPart;

  /// Heading of the diagnostics page section that lists unexpected errors since the app started.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get diagnosticsErrors;

  /// Shown in the diagnostics page's errors section when there were none.
  ///
  /// In en, this message translates to:
  /// **'No errors since the app started.'**
  String get diagnosticsNoErrors;

  /// Button on the diagnostics page that copies the errors and their details for a bug report.
  ///
  /// In en, this message translates to:
  /// **'Copy errors'**
  String get diagnosticsCopyErrors;

  /// Message after the errors were copied to the clipboard.
  ///
  /// In en, this message translates to:
  /// **'Errors copied. Paste them into a bug report.'**
  String get diagnosticsErrorsCopied;

  /// Line under the diagnostics page's errors when older ones were dropped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 earlier error not kept} other{{count} earlier errors not kept}}'**
  String diagnosticsErrorsDropped(int count);

  /// A file of an import hit a defect in the app (not a bad recording); error is the technical message, in English. Details are in Diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error while reading this file: {error}'**
  String importUnexpectedError(String error);

  /// A session's analysis hit a defect in the app; error is the technical message, in English.
  ///
  /// In en, this message translates to:
  /// **'Unexpected error while analysing this session: {error}'**
  String noteUnexpectedError(String error);

  /// After an error on the diagnostics page when it happened more than once.
  ///
  /// In en, this message translates to:
  /// **'{count} times'**
  String diagnosticsErrorCount(int count);

  /// Title of the page that lists every recording found before an import or an addition to a day is committed.
  ///
  /// In en, this message translates to:
  /// **'Review the import'**
  String get reviewImportTitle;

  /// Text at the top of the import review page.
  ///
  /// In en, this message translates to:
  /// **'Choose what happens to each recording. Nothing is imported until you confirm.'**
  String get reviewImportIntro;

  /// Menu item of a day: choose recordings to add and review what happens to each before they are added.
  ///
  /// In en, this message translates to:
  /// **'Add and review recordings…'**
  String get addAndReviewRecordings;

  /// Choice for a recording in the import review: it becomes a session of its own.
  ///
  /// In en, this message translates to:
  /// **'Import as a new session'**
  String get reviewChoiceNewSession;

  /// Choice for a recording in the import review: it is not imported.
  ///
  /// In en, this message translates to:
  /// **'Skip this file'**
  String get reviewChoiceSkip;

  /// Choice for a recording in the import review: it is another recording of the same run (for example the RCZ of a VBO) and is kept with that session. name is a file name or a session name.
  ///
  /// In en, this message translates to:
  /// **'Same run as {name}'**
  String reviewChoiceSameRunAs(String name);

  /// A recording in the import review: its length (minutes:seconds) and its complete laps.
  ///
  /// In en, this message translates to:
  /// **'{duration} · {count, plural, =0{no complete laps} =1{1 complete lap} other{{count} complete laps}}'**
  String reviewRecordingSummary(String duration, int count);

  /// A recording in the import review whose content is identical to another file of the same import.
  ///
  /// In en, this message translates to:
  /// **'Same content as {name}; imported once.'**
  String reviewDuplicate(String name);

  /// A recording in the import review that could not be read; reason says why (English from the reader).
  ///
  /// In en, this message translates to:
  /// **'Not imported: {reason}'**
  String reviewFailed(String reason);

  /// A recording in the review of an addition that the day already has.
  ///
  /// In en, this message translates to:
  /// **'Already in this day; skipped.'**
  String get reviewAlreadyInDay;

  /// Hint under a recording in the import review: another file's GPS trace matches it. Evidence, not an automatic choice.
  ///
  /// In en, this message translates to:
  /// **'Possibly the same run as {name}: the GPS traces agree.'**
  String reviewPossibleSameRun(String name);

  /// Destination in the review of an addition: the recordings become sessions of the open day.
  ///
  /// In en, this message translates to:
  /// **'Add to this day'**
  String get reviewDestinationAppend;

  /// Destination in the review of an addition: the recordings become a new day instead of the open one.
  ///
  /// In en, this message translates to:
  /// **'Start a new day'**
  String get reviewDestinationNewDay;

  /// Why 'Start a new day' is not available in the review: the open day has unsaved changes.
  ///
  /// In en, this message translates to:
  /// **'Save this day before starting a new one.'**
  String get reviewNewDayNeedsSave;

  /// Hint at the bottom of the import review page.
  ///
  /// In en, this message translates to:
  /// **'Two exports of the same run? Choose “Same run as”. The session\'s laps come from the file you link to; the other file is kept with it as its alternative recording.'**
  String get reviewSameRunHint;

  /// Button of the import review page that imports the recordings as chosen.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get reviewConfirmImport;

  /// Button of the review of an addition that adds the recordings as chosen.
  ///
  /// In en, this message translates to:
  /// **'Add to the day'**
  String get reviewConfirmAdd;

  /// Button of the review of an addition, with 'Start a new day' chosen.
  ///
  /// In en, this message translates to:
  /// **'Start the new day'**
  String get reviewConfirmNewDay;

  /// Summary at the bottom of the import review page: the sessions the choices create.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No new session} =1{1 new session} other{{count} new sessions}}'**
  String reviewSessionCount(int count);

  /// Why the import review cannot be confirmed.
  ///
  /// In en, this message translates to:
  /// **'A file is the same run as a file that is not imported as a session of its own.'**
  String get reviewProblemTarget;

  /// Why the import review cannot be confirmed: two files were made the same run as one session.
  ///
  /// In en, this message translates to:
  /// **'A session keeps one other recording at most.'**
  String get reviewProblemTooMany;

  /// Why the import review cannot be confirmed: every file is skipped.
  ///
  /// In en, this message translates to:
  /// **'Choose at least one file to import.'**
  String get reviewProblemNothing;

  /// Said when recordings were to be added to a day with choices the review does not accept (for example every file skipped).
  ///
  /// In en, this message translates to:
  /// **'These choices cannot be added, so nothing was added. Review the recordings again.'**
  String get reviewChoicesRefused;

  /// Said when leaving a day while its save waits for two recordings paired in the review to be lined up.
  ///
  /// In en, this message translates to:
  /// **'Wait until the recordings are lined up and the day is saved.'**
  String get waitUntilRecordingsSaved;

  /// An import or addition after a review found other recordings than the ones reviewed (a file changed or a folder has other files).
  ///
  /// In en, this message translates to:
  /// **'The recordings changed after the review, so nothing was imported. Review them again.'**
  String get reviewChanged;

  /// Shown on a day while the recordings chosen for 'Add and review recordings…' are read.
  ///
  /// In en, this message translates to:
  /// **'Preparing the review…'**
  String get reviewPreparing;

  /// An import was asked for while another runs or waits for its review; nothing was imported.
  ///
  /// In en, this message translates to:
  /// **'Finish the current import first. Nothing was imported.'**
  String get importBusy;

  /// A VBO recording could not be opened; the system's reason follows.
  ///
  /// In en, this message translates to:
  /// **'Could not open VBO: {detail}'**
  String coreVboOpenFailed(String detail);

  /// A VBO recording could not be read; the system's reason follows.
  ///
  /// In en, this message translates to:
  /// **'Could not read VBO: {detail}'**
  String coreVboReadFailed(String detail);

  /// A VBO recording is damaged or has a structure the app cannot read. The detail is the reader's own technical English text, kept as written; in English it is the whole message.
  ///
  /// In en, this message translates to:
  /// **'{detail}'**
  String coreVboUnreadable(String detail);

  /// A VBO recording holds no data. '[data]' is the file's section name, not translated.
  ///
  /// In en, this message translates to:
  /// **'VBO has no [data] rows.'**
  String get coreVboNoData;

  /// No data row of a VBO recording has a usable time.
  ///
  /// In en, this message translates to:
  /// **'VBO contains no valid timestamped data rows.'**
  String get coreVboNoValidRows;

  /// A VBO recording has no column holding the time of each row, so it is refused.
  ///
  /// In en, this message translates to:
  /// **'VBO has no time column (time, timestamp or utc_time), so its samples cannot be timed.'**
  String get coreVboNoTimeColumn;

  /// A VBO recording is too large to read.
  ///
  /// In en, this message translates to:
  /// **'VBO exceeds the supported 128 MiB file size limit.'**
  String get coreVboFileSize;

  /// A VBO recording's text is too complex to read.
  ///
  /// In en, this message translates to:
  /// **'VBO text exceeds the supported complexity limit.'**
  String get coreVboComplexity;

  /// A VBO recording holds too many values to read.
  ///
  /// In en, this message translates to:
  /// **'VBO has more values (rows x columns) than the supported 40 million.'**
  String get coreVboTooManyValues;

  /// A line of a VBO recording is too long to read.
  ///
  /// In en, this message translates to:
  /// **'VBO contains a line longer than the supported 1 MiB limit.'**
  String get coreVboLongLine;

  /// A VBO recording has too many lines to read.
  ///
  /// In en, this message translates to:
  /// **'VBO contains too many lines.'**
  String get coreVboTooManyLines;

  /// A section name of a VBO recording is too long.
  ///
  /// In en, this message translates to:
  /// **'VBO contains a section name longer than the supported 256 characters.'**
  String get coreVboLongSectionName;

  /// A VBO recording has too many data rows to read.
  ///
  /// In en, this message translates to:
  /// **'VBO contains too many data rows.'**
  String get coreVboTooManyRows;

  /// A VBO recording's header is too large to read.
  ///
  /// In en, this message translates to:
  /// **'VBO header metadata exceeds the supported size.'**
  String get coreVboHeaderSize;

  /// A VBO recording has too many columns to read.
  ///
  /// In en, this message translates to:
  /// **'VBO contains too many columns.'**
  String get coreVboTooManyColumns;

  /// A field of a VBO recording is too long to read.
  ///
  /// In en, this message translates to:
  /// **'VBO contains a field longer than the supported 64 KiB limit.'**
  String get coreVboLongField;

  /// A RaceChrono RCZ recording is damaged or has a structure the app cannot read. The detail is the reader's own technical English text, kept as written.
  ///
  /// In en, this message translates to:
  /// **'RCZ: {detail}'**
  String coreRczUnreadable(String detail);

  /// After 'RCZ: ': a file the RCZ archive must hold is missing.
  ///
  /// In en, this message translates to:
  /// **'Missing {name}.'**
  String coreRczMissing(String name);

  /// After 'RCZ: ': a file inside the RCZ archive is too large.
  ///
  /// In en, this message translates to:
  /// **'{name} exceeds its size limit.'**
  String coreRczMemberTooLarge(String name);

  /// After 'RCZ: ': the RCZ file is too small or too large.
  ///
  /// In en, this message translates to:
  /// **'Archive size is unsupported.'**
  String get coreRczArchiveSize;

  /// After 'RCZ: ': the RCZ archive is of a kind the app cannot read.
  ///
  /// In en, this message translates to:
  /// **'Unsupported ZIP64, split archive or directory limits.'**
  String get coreRczZip64;

  /// After 'RCZ: ': the RCZ archive holds a symbolic link.
  ///
  /// In en, this message translates to:
  /// **'Symbolic links are unsupported.'**
  String get coreRczSymlinks;

  /// After 'RCZ: ': the RCZ archive repeats a file or holds too much.
  ///
  /// In en, this message translates to:
  /// **'Duplicate member or archive resource limit exceeded.'**
  String get coreRczDuplicateMember;

  /// After 'RCZ: ': the RCZ file ends early, for example an unfinished copy.
  ///
  /// In en, this message translates to:
  /// **'Truncated archive.'**
  String get coreRczTruncated;

  /// After 'RCZ: ': the recording's metadata is too deep or a text in it too long.
  ///
  /// In en, this message translates to:
  /// **'Metadata nesting/string limit exceeded.'**
  String get coreRczMetadataNesting;

  /// After 'RCZ: ': a list in the recording's metadata is too long.
  ///
  /// In en, this message translates to:
  /// **'Metadata array limit exceeded.'**
  String get coreRczMetadataArray;

  /// After 'RCZ: ': an object in the recording's metadata has too many fields.
  ///
  /// In en, this message translates to:
  /// **'Metadata object limit exceeded.'**
  String get coreRczMetadataObject;

  /// After 'RCZ: ': the RCZ holds several sessions or a resumed one; the user should export one session.
  ///
  /// In en, this message translates to:
  /// **'Multi-session or resumed archives are not supported; share one uninterrupted session.'**
  String get coreRczMultiSession;

  /// After 'RCZ: ': the RCZ session was written by a version the app cannot read.
  ///
  /// In en, this message translates to:
  /// **'Unsupported session version.'**
  String get coreRczSessionVersion;

  /// After 'RCZ: ': the RCZ session was paused and resumed.
  ///
  /// In en, this message translates to:
  /// **'Resumed sessions are not supported yet.'**
  String get coreRczResumed;

  /// After 'RCZ: ': the RCZ has more than one position channel.
  ///
  /// In en, this message translates to:
  /// **'Multiple position channels are unsupported.'**
  String get coreRczMultiplePositions;

  /// After 'RCZ: ': the RCZ has a channel from more than one source. The channel name is the app's own, not translated.
  ///
  /// In en, this message translates to:
  /// **'Multiple sources for {channel} are unsupported.'**
  String coreRczMultipleSources(String channel);

  /// After 'RCZ: ': GPS channels the RCZ declares are not in it.
  ///
  /// In en, this message translates to:
  /// **'Declared GPS channels are missing.'**
  String get coreRczGpsMissing;

  /// After 'RCZ: ': the RCZ's times go backwards or span more than 24 hours.
  ///
  /// In en, this message translates to:
  /// **'Timestamp channel is nonmonotonic or outside the supported 24-hour session.'**
  String get coreRczTimestamps;

  /// After 'RCZ: ': the RCZ holds too many channels or samples.
  ///
  /// In en, this message translates to:
  /// **'Decoded channel/sample budget exceeded.'**
  String get coreRczChannelBudget;

  /// After 'RCZ: ': the RCZ holds too many gaps or samples.
  ///
  /// In en, this message translates to:
  /// **'Decoded gap/sample budget exceeded.'**
  String get coreRczGapBudget;

  /// After 'RCZ: ': the RCZ's track has too many timing gates.
  ///
  /// In en, this message translates to:
  /// **'Too many timing gates.'**
  String get coreRczTooManyGates;

  /// After 'RCZ: ': a timing gate of the RCZ's track is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid timing gate coordinates or geometry.'**
  String get coreRczInvalidGate;

  /// After 'RCZ: ': an end of a timing gate of the RCZ's track is invalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid timing gate endpoint.'**
  String get coreRczInvalidGateEndpoint;

  /// A recording is empty or too large to check its content.
  ///
  /// In en, this message translates to:
  /// **'Telemetry file exceeds the content identity size limit.'**
  String get coreSourceIdentitySize;

  /// A recording could not be opened.
  ///
  /// In en, this message translates to:
  /// **'Cannot read telemetry source.'**
  String get coreSourceCannotRead;

  /// A recording changed while it was read, for example while still being copied.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source changed while reading; retry with a stable file.'**
  String get coreSourceChangedWhileReading;

  /// A recording could not be read to its end.
  ///
  /// In en, this message translates to:
  /// **'Telemetry source read failed or was truncated.'**
  String get coreSourceReadFailed;

  /// A day holds more recordings than the app supports.
  ///
  /// In en, this message translates to:
  /// **'Too many recordings in this day.'**
  String get coreDayTooManyRecordings;

  /// A day holds more lap sections (laps, out-laps and in-laps) than the app supports.
  ///
  /// In en, this message translates to:
  /// **'This day exceeds the 20,000 lap-section limit.'**
  String get coreDayLapSectionLimit;

  /// A day has too many laps to recognise its track layout.
  ///
  /// In en, this message translates to:
  /// **'Too many lap traces for route inference.'**
  String get coreRouteTooManyTraces;

  /// A day has too many sessions to group them by track layout.
  ///
  /// In en, this message translates to:
  /// **'Too many runs for route grouping.'**
  String get coreRouteTooManyRuns;

  /// A day is too large to show progress across its sessions.
  ///
  /// In en, this message translates to:
  /// **'Too many runs or lap sections for progression.'**
  String get coreProgressionTooMany;

  /// A session's recording has more lap sections than the app supports.
  ///
  /// In en, this message translates to:
  /// **'Too many lap sections in this recording.'**
  String get coreRecordingTooManyLapSections;

  /// A day has more lap sections than the app supports.
  ///
  /// In en, this message translates to:
  /// **'Too many lap sections in this day.'**
  String get coreDayTooManyLapSections;

  /// A day is too large to rank its laps.
  ///
  /// In en, this message translates to:
  /// **'Too many laps or exclusions to rank this day.'**
  String get coreRankingTooMany;

  /// A session's recording crosses the start/finish line too many times.
  ///
  /// In en, this message translates to:
  /// **'Lap detector produced too many accepted passes.'**
  String get coreTooManyPasses;

  /// A session's laps hold too many GPS points.
  ///
  /// In en, this message translates to:
  /// **'Lap traces contain too many GPS points.'**
  String get coreTooManyGpsPoints;

  /// After a recording's name: adding it to a day did nothing, the day already has it.
  ///
  /// In en, this message translates to:
  /// **'already in this day.'**
  String get additionAlreadyInDay;

  /// After a recording's name, when adding to a day: it is the other format (VBO or RCZ) of a session of the day.
  ///
  /// In en, this message translates to:
  /// **'the same drive as {session} in the other format; kept as its alternative source.'**
  String additionSameDriveKept(String session);

  /// After a recording's name, when adding to a day: it is the other format (VBO or RCZ) of a session of the day, which already has one.
  ///
  /// In en, this message translates to:
  /// **'the same drive as {session} in the other format; not added again.'**
  String additionSameDriveNotAdded(String session);

  /// A session's weather in the day's progression.
  ///
  /// In en, this message translates to:
  /// **'Weather: {weather}'**
  String progressionWeather(String weather);

  /// The weather service's credit, required next to its data (CC BY 4.0).
  ///
  /// In en, this message translates to:
  /// **'Weather data by Open-Meteo.com'**
  String get weatherCredit;

  /// Says what the weather values are.
  ///
  /// In en, this message translates to:
  /// **'Modelled for the area around the track at the session\'s time, not measured at the track.'**
  String get weatherModelled;

  /// Air temperature.
  ///
  /// In en, this message translates to:
  /// **'{value} °C'**
  String weatherTemperature(String value);

  /// Air temperature range during a session.
  ///
  /// In en, this message translates to:
  /// **'{low}–{high} °C'**
  String weatherTemperatureRange(String low, String high);

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'clear'**
  String get weatherClear;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'partly cloudy'**
  String get weatherPartlyCloudy;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'overcast'**
  String get weatherOvercast;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'fog'**
  String get weatherFog;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'drizzle'**
  String get weatherDrizzle;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'rain'**
  String get weatherRain;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'snow'**
  String get weatherSnow;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'showers'**
  String get weatherShowers;

  /// Sky condition.
  ///
  /// In en, this message translates to:
  /// **'thunderstorm'**
  String get weatherThunderstorm;

  /// Rain during the session.
  ///
  /// In en, this message translates to:
  /// **'{amount} mm of rain'**
  String weatherPrecipitation(String amount);

  /// No rain during the session.
  ///
  /// In en, this message translates to:
  /// **'no rain'**
  String get weatherNoPrecipitation;

  /// Wind; direction is a compass point such as SW, where the wind comes from.
  ///
  /// In en, this message translates to:
  /// **'wind {direction} {speed} km/h'**
  String weatherWind(String direction, String speed);

  /// Wind without a direction.
  ///
  /// In en, this message translates to:
  /// **'wind {speed} km/h'**
  String weatherWindNoDirection(String speed);

  /// Strongest gust during the session.
  ///
  /// In en, this message translates to:
  /// **'gusts up to {speed} km/h'**
  String weatherGusts(String speed);

  /// Relative humidity.
  ///
  /// In en, this message translates to:
  /// **'humidity {value}%'**
  String weatherHumidity(String value);

  /// Cloud cover.
  ///
  /// In en, this message translates to:
  /// **'cloud cover {value}%'**
  String weatherCloudCover(String value);

  /// Surface air pressure.
  ///
  /// In en, this message translates to:
  /// **'pressure {value} hPa'**
  String weatherPressure(String value);

  /// Air temperature line in session details.
  ///
  /// In en, this message translates to:
  /// **'air {temperature}'**
  String weatherAirTemperature(String temperature);

  /// The worst weather during the session.
  ///
  /// In en, this message translates to:
  /// **'sky: {condition}'**
  String weatherSky(String condition);

  /// While the weather is fetched.
  ///
  /// In en, this message translates to:
  /// **'Looking up the weather…'**
  String get weatherFetching;

  /// Weather lookup turned off.
  ///
  /// In en, this message translates to:
  /// **'Weather lookup is off in settings.'**
  String get weatherOff;

  /// Weather lookup failed.
  ///
  /// In en, this message translates to:
  /// **'Not available: the weather service could not be reached or had no data for this session.'**
  String get weatherUnavailable;

  /// No weather can be looked up.
  ///
  /// In en, this message translates to:
  /// **'Not available: the recording has no date and time or no GPS position.'**
  String get weatherNone;

  /// Retries the weather lookup.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get weatherRetry;

  /// Heading of the weather in session details.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get sessionDetailsWeather;

  /// Settings heading.
  ///
  /// In en, this message translates to:
  /// **'Session weather'**
  String get settingsWeatherHeading;

  /// Settings switch.
  ///
  /// In en, this message translates to:
  /// **'Look up the weather for each session'**
  String get settingsWeatherSwitch;

  /// Explains what the weather lookup sends.
  ///
  /// In en, this message translates to:
  /// **'Sends each session\'s position, rounded to about 1 km, and its date to Open-Meteo.com. Nothing else from your recordings leaves the device.'**
  String get settingsWeatherHelp;

  /// The day keeps weather this version cannot read.
  ///
  /// In en, this message translates to:
  /// **'Kept as stored: this day\'s weather was saved by a newer version of the app.'**
  String get weatherKept;

  /// After saving the day in the driver profile's library.
  ///
  /// In en, this message translates to:
  /// **'Saved in your library.'**
  String get savedToLibrary;

  /// After saving the day in the library while it changed.
  ///
  /// In en, this message translates to:
  /// **'Saved in your library. Changes made while saving are not saved yet.'**
  String get savedToLibraryChangesPending;

  /// Menu item that writes a copy of the day as a .fetproject file for FlappedEar Overlays; the day stays in the library.
  ///
  /// In en, this message translates to:
  /// **'Export for Overlays…'**
  String get exportForOverlays;

  /// After exporting a copy of the day: its file name.
  ///
  /// In en, this message translates to:
  /// **'Exported as {file}.'**
  String exportedAs(String file);

  /// Export for Overlays refused a file inside the library's own days folder.
  ///
  /// In en, this message translates to:
  /// **'Not exported: choose a place outside the library.'**
  String get exportNotInLibrary;

  /// Title of the dialog asking before Save as… or Export for Overlays replaces a file the system save dialog did not warn about (the app added .fetproject to the typed name, or the dialog never asks, as on Linux).
  ///
  /// In en, this message translates to:
  /// **'Replace {file}?'**
  String replaceDayFileTitle(String file);

  /// Body of the dialog asking before an existing day file is replaced.
  ///
  /// In en, this message translates to:
  /// **'A file with this name is already in that folder. Replacing it cannot be undone.'**
  String get replaceDayFileBody;

  /// Button that replaces the existing day file.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get replaceDayFile;

  /// Save as… refused a file inside the library's own days folder.
  ///
  /// In en, this message translates to:
  /// **'Not saved: choose a place outside the library.'**
  String get notSavedInLibrary;

  /// Exporting a copy of the day failed; the error follows.
  ///
  /// In en, this message translates to:
  /// **'Not exported: {error}'**
  String notExported(String error);

  /// Button on the start page that opens the library of every day kept in the driver profile.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get importPageLibrary;

  /// Title of the page listing every day kept in the driver profile, by car, year, track and date.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get libraryTitle;

  /// Library page when the app has no folder for the driver profile.
  ///
  /// In en, this message translates to:
  /// **'The library cannot be used now, for example because a newer version of the app made it. Until then, days are saved as files.'**
  String get libraryUnavailable;

  /// Library page with no days yet.
  ///
  /// In en, this message translates to:
  /// **'Days you import are kept here, by car, year and track.'**
  String get libraryEmpty;

  /// Button and dialog title for renaming a car in the library.
  ///
  /// In en, this message translates to:
  /// **'Rename car'**
  String get libraryRenameCar;

  /// Button and dialog title for renaming a track in the library.
  ///
  /// In en, this message translates to:
  /// **'Rename track'**
  String get libraryRenameTrack;

  /// Year or date heading for days whose recordings have no date.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get libraryUndated;

  /// Heading for days whose track could not be recognised (no complete laps).
  ///
  /// In en, this message translates to:
  /// **'Track not recognised'**
  String get libraryUnknownTrack;

  /// How many sessions a day in the library has.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String librarySessions(int count);

  /// A day's best lap in the library.
  ///
  /// In en, this message translates to:
  /// **'Best {time}'**
  String libraryBestLap(String time);

  /// Button on a day in the library that moves it to another car.
  ///
  /// In en, this message translates to:
  /// **'Change car'**
  String get libraryChangeCar;

  /// Title of the dialog choosing the car a day was driven in.
  ///
  /// In en, this message translates to:
  /// **'Car for {day}'**
  String libraryChooseCar(String day);

  /// Option that adds a car and moves the day to it.
  ///
  /// In en, this message translates to:
  /// **'New car…'**
  String get libraryNewCar;

  /// Name of the first car, made when the first day is kept in the library.
  ///
  /// In en, this message translates to:
  /// **'My car'**
  String get libraryDefaultCar;

  /// Name of a track recognised for the first time; the user can rename it.
  ///
  /// In en, this message translates to:
  /// **'Track {number}'**
  String libraryDefaultTrack(int number);

  /// Button above the lap list that shows the hidden laps that are not ranked: out laps, in laps, laps the driver excluded and laps with an issue.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Show 1 lap not ranked} other{Show {count} laps not ranked}}'**
  String lapsShowUnranked(int count);

  /// Button above the lap list that hides the laps that are not ranked (out laps, in laps, excluded laps, laps with an issue). The day keeps them.
  ///
  /// In en, this message translates to:
  /// **'Hide laps not ranked'**
  String get lapsHideUnranked;

  /// Place in the app navigation (bottom bar or side rail): the start page.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// Place in the app navigation: the library of days kept in the driver profile.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get navLibrary;

  /// Place in the app navigation: the day open now.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get navDay;

  /// Place in the app navigation: the coach of the day open now, what to try in the next session.
  ///
  /// In en, this message translates to:
  /// **'Coach'**
  String get navCoach;

  /// Place in the app navigation: the driver's totals, records and progress across every day.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// Profile page with no day in the profile.
  ///
  /// In en, this message translates to:
  /// **'No days yet. Every day you import is added to your profile, and its totals, records and skills appear here.'**
  String get profileEmpty;

  /// Heading of the profile's totals over every day.
  ///
  /// In en, this message translates to:
  /// **'All days'**
  String get profileTotals;

  /// Totals: number of days.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get profileDays;

  /// Totals: number of sessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get profileSessions;

  /// Totals: number of timed laps.
  ///
  /// In en, this message translates to:
  /// **'Timed laps'**
  String get profileLaps;

  /// Totals: distance driven.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get profileDistance;

  /// Totals: time moving on track.
  ///
  /// In en, this message translates to:
  /// **'Time on track'**
  String get profileDrivingTime;

  /// Totals: number of tracks; also the heading of the per-track records.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get profileTracks;

  /// Totals: number of cars; also the heading of each car's mileage.
  ///
  /// In en, this message translates to:
  /// **'Cars'**
  String get profileCars;

  /// Totals note when some sessions have no measured distance and time.
  ///
  /// In en, this message translates to:
  /// **'Distance and time cover {measured} of {sessions, plural, =1{1 session} other{{sessions} sessions}}: a day saved before this version adds them when you open it again.'**
  String profileMeasured(int measured, int sessions);

  /// Heading of the skill levels, on the Profile and in the coach.
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get profileSkills;

  /// Explains how skill levels are worked out.
  ///
  /// In en, this message translates to:
  /// **'Each skill over your last 3 days that measured it, against fixed bands set by what a fast, experienced driver repeats lap after lap: level 5 means at the limit. Level 5 needs 15 ranked laps and level 4 needs 5. Confidence comes from the ranked laps measured.'**
  String get profileSkillsIntro;

  /// A driving skill's name, from the 12-skill model.
  ///
  /// In en, this message translates to:
  /// **'{id, select, liftTiming{Lift timing} brakePointConsistency{Brake point consistency} brakeReleaseTiming{Brake release timing} brakingEffectiveness{Braking effectiveness} turnInConsistency{Turn-in consistency} minimumSpeedControl{Minimum speed control} lineConsistency{Line consistency} throttleReapplication{Throttle reapplication} throttleCommitment{Throttle commitment} exitSpeedExecution{Exit speed execution} cornerSequenceManagement{Corner sequence management} paceConsistency{Pace consistency} other{{id}}}'**
  String skillName(String id);

  /// The group a skill belongs to.
  ///
  /// In en, this message translates to:
  /// **'{group, select, braking{Braking} corner{Corner} exit{Exit} lap{Lap} other{{group}}}'**
  String skillGroup(String group);

  /// What a skill's measured value is, with the value and its unit.
  ///
  /// In en, this message translates to:
  /// **'{id, select, brakePointConsistency{Braking-point spread: {value}} minimumSpeedControl{Minimum speed below your best: {value}} exitSpeedExecution{Exit speed below your best: {value}} paceConsistency{Lap time spread: {value}} liftTiming{Off the throttle to braking: {value}} brakeReleaseTiming{Brake-release spread: {value}} brakingEffectiveness{Braking below your best: {value}} turnInConsistency{Corner entry speed spread: {value}} lineConsistency{Line spread through the corner: {value}} throttleReapplication{Throttle pickup spread: {value}} throttleCommitment{Throttle picked up and lifted again before the slowest point: {value} of passes} cornerSequenceManagement{Lost right after the corner on your faster passes: {value}} other{{value}}}'**
  String skillMeasured(String id, String value);

  /// A skill's level.
  ///
  /// In en, this message translates to:
  /// **'Level {level} of 5'**
  String skillLevel(int level);

  /// How sure a skill level is, from the laps measured.
  ///
  /// In en, this message translates to:
  /// **'{confidence, select, low{Low confidence} medium{Medium confidence} high{High confidence} other{{confidence}}}'**
  String skillConfidence(String confidence);

  /// The evidence behind a skill level.
  ///
  /// In en, this message translates to:
  /// **'{laps, plural, =1{1 ranked lap} other{{laps} ranked laps}} over {days, plural, =1{1 day} other{{days} days}}'**
  String skillEvidence(int laps, int days);

  /// A skill level against the days before.
  ///
  /// In en, this message translates to:
  /// **'{trend, select, improving{Improving} steady{Steady} declining{Declining} other{{trend}}}'**
  String skillTrend(String trend);

  /// A measured skill with no lap measured yet.
  ///
  /// In en, this message translates to:
  /// **'Needs more evidence'**
  String get skillNeedsEvidence;

  /// A skill of the model the app has no measure for yet.
  ///
  /// In en, this message translates to:
  /// **'Not measured by the app yet'**
  String get skillNotMeasured;

  /// A car's or track's totals.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}} · {distance} · {time}'**
  String profileDrivenOn(int days, String distance, String time);

  /// How often a track was driven.
  ///
  /// In en, this message translates to:
  /// **'{visits, plural, =1{1 visit} other{{visits} visits}}'**
  String profileVisits(int visits);

  /// A track's personal best lap, its date and session.
  ///
  /// In en, this message translates to:
  /// **'Best lap: {time} · {when}'**
  String profileBestLap(String time, String when);

  /// A track's best theoretical lap time and its date.
  ///
  /// In en, this message translates to:
  /// **'Best theoretical: {time} · {when}'**
  String profileTheoreticalBest(String time, String when);

  /// A track's best median lap time of a visit, and its date.
  ///
  /// In en, this message translates to:
  /// **'Best typical lap: {time} · {when}'**
  String profileTypicalLap(String time, String when);

  /// The last visit's best lap against the visit before, faster.
  ///
  /// In en, this message translates to:
  /// **'Last visit: best lap {time} faster than the visit before'**
  String profileFaster(String time);

  /// The last visit's best lap against the visit before, slower.
  ///
  /// In en, this message translates to:
  /// **'Last visit: best lap {time} slower than the visit before'**
  String profileSlower(String time);

  /// A day with no recording time.
  ///
  /// In en, this message translates to:
  /// **'Undated'**
  String get profileUndated;

  /// Heading of the corners among a visit's costliest on two or more visits.
  ///
  /// In en, this message translates to:
  /// **'Corners that keep costing time'**
  String get profileRepeated;

  /// A repeated loss: the mean time lost and on how many visits.
  ///
  /// In en, this message translates to:
  /// **'{loss} lost on average, on {visits, plural, =1{1 visit} other{{visits} visits}}'**
  String profileRepeatedLoss(String loss, int visits);

  /// Whether a repeated loss is still there.
  ///
  /// In en, this message translates to:
  /// **'{state, select, active{Still costing time} fading{Fading: not measured on the last two visits} fixed{Not lost on the last two visits} other{{state}}}'**
  String profileRepeatedState(String state);

  /// No repeated loss across visits.
  ///
  /// In en, this message translates to:
  /// **'No corner has been among a visit\'s costliest on two visits yet.'**
  String get profileRepeatedNone;

  /// A car's days on the Profile page when no session of them has distance and time yet.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}} · distance and time not measured yet'**
  String profileDrivenOnUnmeasured(int days);

  /// Tracks card on the Profile page with no recognised track.
  ///
  /// In en, this message translates to:
  /// **'No track recognised yet in your days.'**
  String get profileTracksNone;

  /// Settings heading for the app's colours: dark, or sunlight for reading outdoors.
  ///
  /// In en, this message translates to:
  /// **'Look'**
  String get settingsLookHeading;

  /// Settings choice: the dark theme (default).
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get lookDark;

  /// Settings choice: a high-contrast light theme for reading in direct sun at the track.
  ///
  /// In en, this message translates to:
  /// **'Sunlight'**
  String get lookSunlight;

  /// Help under the look choice in settings.
  ///
  /// In en, this message translates to:
  /// **'Sunlight is black on white with stronger colours, easier to read outdoors in bright sun.'**
  String get settingsLookHelp;

  /// Settings switch: the screen does not sleep while the Coach place is on screen.
  ///
  /// In en, this message translates to:
  /// **'Keep the screen on while Coach is shown'**
  String get settingsKeepScreenOnSwitch;

  /// Help under the keep-screen-on switch in settings.
  ///
  /// In en, this message translates to:
  /// **'The next-session card stays readable between sessions. The screen sleeps as usual elsewhere in the app and when the app is not in front.'**
  String get settingsKeepScreenOnHelp;

  /// Day page card title: the previous visit to this track from the driver profile.
  ///
  /// In en, this message translates to:
  /// **'Last time here'**
  String get lastTimeHereTitle;

  /// Row label in the Last time here card.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get lastTimeHereBestLap;

  /// Row label in the Last time here card.
  ///
  /// In en, this message translates to:
  /// **'Theoretical best'**
  String get lastTimeHereTheoreticalBest;

  /// Note under the Last time here card.
  ///
  /// In en, this message translates to:
  /// **'Today minus last time: negative is faster today. Conditions may differ.'**
  String get lastTimeHereNote;

  /// Last time here card: why a time is shown as a dash.
  ///
  /// In en, this message translates to:
  /// **'— means that day has no such time: no ranked lap, or the theoretical best could not be worked out.'**
  String get lastTimeHereMissing;

  /// Last time here card: the previous visit was in another car.
  ///
  /// In en, this message translates to:
  /// **'That car is named because this car has not driven here before.'**
  String get lastTimeHereOtherCar;

  /// Last time here card: the previous visit's time and today's.
  ///
  /// In en, this message translates to:
  /// **'{then} then · {today} today'**
  String lastTimeHereThenToday(String then, String today);

  /// Last time here card: heading of the per-corner rows, then and today.
  ///
  /// In en, this message translates to:
  /// **'Time lost per corner'**
  String get lastTimeHereCorners;

  /// Last time here card: what the per-corner times mean.
  ///
  /// In en, this message translates to:
  /// **'Each day\'s laps against that day\'s fastest through the corner, averaged over its sessions: a smaller time means a more even day there, not a faster corner. Where a corner starts and ends can differ a little between days. Only corners measured on both days are listed.'**
  String get lastTimeHereCornersNote;

  /// Last time here card: why there are no per-corner rows (one of the days has no corner measurements, e.g. still being analysed).
  ///
  /// In en, this message translates to:
  /// **'Time lost per corner: no corner was measured on both days.'**
  String get lastTimeHereCornersNone;

  /// Last time here card: heading of the weather of the previous visit and of today.
  ///
  /// In en, this message translates to:
  /// **'Weather'**
  String get lastTimeHereWeather;

  /// Last time here card: the previous visit's weather. session is a label such as 'Session 2, best lap'; weather is a short weather line such as '21 °C, overcast, no rain, wind SW 12 km/h'.
  ///
  /// In en, this message translates to:
  /// **'Then ({session}): {weather}'**
  String lastTimeHereWeatherThen(String session, String weather);

  /// Last time here card: today's weather. session is a label such as 'Session 2, best lap'; weather is a short weather line.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): {weather}'**
  String lastTimeHereWeatherToday(String session, String weather);

  /// Last time here card: the session whose weather is shown set the day's best lap.
  ///
  /// In en, this message translates to:
  /// **'{session}, best lap'**
  String lastTimeHereWeatherBestLapSession(String session);

  /// Last time here card: the session that set the best lap has no weather, so this session, the first with weather, is shown.
  ///
  /// In en, this message translates to:
  /// **'{session}; the best-lap session had none'**
  String lastTimeHereWeatherBestHadNone(String session);

  /// Last time here card: no session matches the day's best lap, so the first session with weather is shown.
  ///
  /// In en, this message translates to:
  /// **'{session}, first with weather'**
  String lastTimeHereWeatherFirstSession(String session);

  /// Last time here card: part of a weather line for a sky condition saved by a newer version of the app.
  ///
  /// In en, this message translates to:
  /// **'conditions this version does not know'**
  String get lastTimeHereWeatherUnknownCondition;

  /// Last time here card: the previous visit has no weather in the library, and why.
  ///
  /// In en, this message translates to:
  /// **'Then: — no weather kept for that day: weather lookup was off, its recordings have no time or position, or the day was added before the library kept weather.'**
  String get lastTimeHereWeatherThenNone;

  /// Last time here card: today has no weather in the library, when the page's weather state is not known.
  ///
  /// In en, this message translates to:
  /// **'Today: — no weather kept for today yet.'**
  String get lastTimeHereWeatherTodayNone;

  /// Last time here card: today's weather is being looked up.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): looking up the weather…'**
  String lastTimeHereWeatherTodayFetching(String session);

  /// Last time here card: no weather today because weather lookup is turned off.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — weather lookup is off in settings.'**
  String lastTimeHereWeatherTodayOff(String session);

  /// Last time here card: today's weather lookup failed (offline or no data).
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — the weather service could not be reached or had no data.'**
  String lastTimeHereWeatherTodayUnavailable(String session);

  /// Last time here card: today's session cannot have weather.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — no weather for this session: its recording has no time or GPS position.'**
  String lastTimeHereWeatherTodayNoPosition(String session);

  /// Last time here card: the weather arrived but the day has unsaved changes, so the library gets it with the save.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — shown on this page; it reaches the library when the day is saved.'**
  String lastTimeHereWeatherTodayPending(String session);

  /// Last time here card: today's weather was stored by a newer app version.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — saved by a newer version of the app and not read here.'**
  String lastTimeHereWeatherTodayKept(String session);

  /// Last time here card: which session's weather stands for each visit.
  ///
  /// In en, this message translates to:
  /// **'Each visit\'s weather is that of the session that set its best lap, or, when that session has none, of its first session with weather.'**
  String get lastTimeHereWeatherNote;

  /// Last time here card: heading of the setup entered for a session of the previous visit and of today.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get lastTimeHereSetup;

  /// Last time here card: the previous visit's setup as entered. session is a label such as 'Session 2, best lap'; setup is a setup line such as 'Cold 2.1 / 2.1 / 2 / 2 bar · Tyres Pirelli SC2 · Fuel 8.5 l'.
  ///
  /// In en, this message translates to:
  /// **'Then ({session}): {setup}'**
  String lastTimeHereSetupThen(String session, String setup);

  /// Last time here card: today's setup as entered. session is a label such as 'Session 2, best lap'; setup is a setup line.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): {setup}'**
  String lastTimeHereSetupToday(String session, String setup);

  /// Last time here card: the session that set the best lap has no setup entered, so this session, the first with a setup, is shown.
  ///
  /// In en, this message translates to:
  /// **'{session}; the best-lap session had none'**
  String lastTimeHereSetupBestHadNone(String session);

  /// Last time here card: no session matches the day's best lap, so the first session with a setup is shown.
  ///
  /// In en, this message translates to:
  /// **'{session}, first with a setup'**
  String lastTimeHereSetupFirstSession(String session);

  /// Last time here card: no session of the previous visit has a setup in the library, and why.
  ///
  /// In en, this message translates to:
  /// **'Then: — no setup entered for that day, or the day was added before the library kept setups.'**
  String get lastTimeHereSetupThenNone;

  /// Last time here card: today has no setup in the library and no session to name.
  ///
  /// In en, this message translates to:
  /// **'Today: — no setup entered.'**
  String get lastTimeHereSetupTodayNoSessions;

  /// Last time here card: the previous visit's session has a setup that cannot be shown. session is a label such as 'Session 2, best lap'; reason is one of the lastTimeHereSetupReason texts.
  ///
  /// In en, this message translates to:
  /// **'Then ({session}): — {reason}'**
  String lastTimeHereSetupThenMissing(String session, String reason);

  /// Last time here card: today's session has no setup in the library to show, and why. session is a label such as 'Session 2, best lap'; reason is one of the lastTimeHereSetupReason texts.
  ///
  /// In en, this message translates to:
  /// **'Today ({session}): — {reason}'**
  String lastTimeHereSetupTodayMissing(String session, String reason);

  /// Last time here card: reason, no setup was entered for the session.
  ///
  /// In en, this message translates to:
  /// **'no setup entered'**
  String get lastTimeHereSetupReasonNone;

  /// Last time here card: reason, the setup was stored with a setup version this app does not know (usually a newer app), so it cannot show it.
  ///
  /// In en, this message translates to:
  /// **'set up in another version of the app'**
  String get lastTimeHereSetupReasonNewer;

  /// Last time here card: reason, the setup holds only values this version cannot read.
  ///
  /// In en, this message translates to:
  /// **'not readable by this version'**
  String get lastTimeHereSetupReasonUnreadable;

  /// Last time here card: reason, the setup was entered on the day page but the day is not saved yet.
  ///
  /// In en, this message translates to:
  /// **'entered on this page; it reaches the library when the day is saved'**
  String get lastTimeHereSetupReasonUnsaved;

  /// Last time here card: reason, the day was saved with this setup but the library has not recorded it yet.
  ///
  /// In en, this message translates to:
  /// **'saved with the day; not in the library yet'**
  String get lastTimeHereSetupReasonPending;

  /// Last time here card: today's pressures minus the previous visit's, wheel by wheel, in the unit both were entered in. difference is a line such as 'Cold +0.1 / 0 / −0.1 / — bar'; — is a wheel without a pressure on one of the visits.
  ///
  /// In en, this message translates to:
  /// **'Difference (today − then): {difference}'**
  String lastTimeHereSetupDifference(String difference);

  /// Last time here card: the two visits' pressures were entered in different units (bar and psi); they are never converted.
  ///
  /// In en, this message translates to:
  /// **'Different pressure units, not compared.'**
  String get lastTimeHereSetupUnits;

  /// Last time here card: which session's setup stands for each visit, and that the difference is no judgement.
  ///
  /// In en, this message translates to:
  /// **'Each visit\'s setup is that of the session that set its best lap, or, when that session has none, of its first session with a setup. Shown as entered; a higher or lower pressure is not better or worse.'**
  String get lastTimeHereSetupNote;

  /// Settings heading for checking GitHub for a newer version of the app.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get settingsUpdatesHeading;

  /// Settings switch: look for a newer release on GitHub at launch, at most once a day.
  ///
  /// In en, this message translates to:
  /// **'Check for a new version when the app starts'**
  String get settingsUpdateSwitch;

  /// Help under the update switch in Settings.
  ///
  /// In en, this message translates to:
  /// **'When the app starts, at most once a day, it asks GitHub for its newest release and circuit list. None of your recordings or settings are sent.'**
  String get settingsUpdateHelp;

  /// Settings button that looks for a newer version now.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get settingsUpdateCheckNow;

  /// Title of the dialog that checks for and downloads a newer version.
  ///
  /// In en, this message translates to:
  /// **'App updates'**
  String get updateTitle;

  /// Update dialog while asking GitHub.
  ///
  /// In en, this message translates to:
  /// **'Looking for a newer version on GitHub…'**
  String get updateChecking;

  /// Update dialog when no newer release exists.
  ///
  /// In en, this message translates to:
  /// **'You have the newest version.'**
  String get updateUpToDate;

  /// Update dialog: the running app's version and build.
  ///
  /// In en, this message translates to:
  /// **'This app: version {version}'**
  String updateInstalledVersion(String version);

  /// Stands for the running app's version when it could not be read.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get updateVersionUnknown;

  /// Update dialog when a newer release exists.
  ///
  /// In en, this message translates to:
  /// **'Version {newVersion} is available. You have {installed}.'**
  String updateAvailable(String newVersion, String installed);

  /// Message shown at launch when a newer release exists.
  ///
  /// In en, this message translates to:
  /// **'FlappedEar Telemetry {newVersion} is available.'**
  String updateAvailableMessage(String newVersion);

  /// Action on the new-version message that opens the update dialog.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get updateDetails;

  /// Update dialog on Android, before downloading.
  ///
  /// In en, this message translates to:
  /// **'The app downloads the APK, checks it against the release\'s checksums and opens Android\'s installer. Your saved days stay.'**
  String get updateAndroidHelp;

  /// Update dialog on a Mac, before downloading.
  ///
  /// In en, this message translates to:
  /// **'The app downloads the zip, checks it against the release\'s checksums and shows it in Finder. Open it and move FlappedEar Telemetry to Applications, replacing the old one. macOS refuses the first start as after the first install: allow it in the same way.'**
  String get updateMacHelp;

  /// Update dialog on iOS, Windows and Linux, where the release carries no file to install.
  ///
  /// In en, this message translates to:
  /// **'The release has no download for this device. Its page on GitHub says what changed.'**
  String get updateNoDownloadHere;

  /// Update dialog button on Android.
  ///
  /// In en, this message translates to:
  /// **'Download and install'**
  String get updateDownloadInstall;

  /// Update dialog button on a Mac.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateDownload;

  /// Update dialog button that opens the release's page on GitHub.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get updateWhatsNew;

  /// Update dialog button that opens the app's releases on GitHub.
  ///
  /// In en, this message translates to:
  /// **'Releases page'**
  String get updateOpenReleases;

  /// Update dialog while downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading version {newVersion}: {percent}%'**
  String updateDownloading(String newVersion, int percent);

  /// Update dialog on Android when the app may not install apps yet.
  ///
  /// In en, this message translates to:
  /// **'Android asks you to allow FlappedEar Telemetry to install apps. Turn it on in the settings that opened, come back and tap Continue. If the app started again, open Settings and tap Check for updates.'**
  String get updateNeedsPermission;

  /// Update dialog button on Android after the user allowed the app to install apps.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get updateContinue;

  /// Update dialog button while Android's installer is open.
  ///
  /// In en, this message translates to:
  /// **'Open the installer again'**
  String get updateInstallAgain;

  /// Update dialog after Android's installer opened.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and checked. Android\'s installer is open: confirm the update there.'**
  String get updateInstalling;

  /// Update dialog on a Mac after the zip was saved.
  ///
  /// In en, this message translates to:
  /// **'Downloaded and checked: {path}. Open it and move FlappedEar Telemetry to Applications, replacing the old one. macOS refuses the first start as after the first install: allow it in the same way.'**
  String updateSaved(String path);

  /// Update dialog button on a Mac.
  ///
  /// In en, this message translates to:
  /// **'Show in Finder'**
  String get updateShowInFinder;

  /// Update dialog when offline or GitHub timed out.
  ///
  /// In en, this message translates to:
  /// **'GitHub could not be reached. Check the connection and try again.'**
  String get updateFailedOffline;

  /// Update dialog when GitHub's rate limit for unauthenticated requests is reached.
  ///
  /// In en, this message translates to:
  /// **'GitHub allows only a few checks an hour from one network. Try again later.'**
  String get updateFailedRateLimited;

  /// Update dialog when SHA256SUMS.txt does not cover the download.
  ///
  /// In en, this message translates to:
  /// **'The release lists no checksum for this file, so it was not kept.'**
  String get updateFailedNotVerifiable;

  /// Update dialog when the downloaded file's SHA-256 or size differs.
  ///
  /// In en, this message translates to:
  /// **'The download does not match the release\'s checksum and was deleted. Try again.'**
  String get updateFailedChecksum;

  /// Update dialog when the file could not be written.
  ///
  /// In en, this message translates to:
  /// **'The download could not be saved. Try again, or choose another folder on a computer.'**
  String get updateFailedNotSaved;

  /// Update dialog for any other failure.
  ///
  /// In en, this message translates to:
  /// **'The update did not work. Try again, or open the releases page.'**
  String get updateFailedUnexpected;

  /// Update dialog button after a failure.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get updateTryAgain;

  /// Library page menu item: writes the driver profile, its days and their recordings to one file to move to another device.
  ///
  /// In en, this message translates to:
  /// **'Export profile'**
  String get libraryExport;

  /// Library page menu item: adds the days of a profile file exported on another device.
  ///
  /// In en, this message translates to:
  /// **'Import profile'**
  String get libraryImport;

  /// Suggested name of an exported profile file, without the extension; date is like 2026-10-05.
  ///
  /// In en, this message translates to:
  /// **'Driver profile {date}'**
  String libraryExportFileName(String date);

  /// Shown while the profile file is being written.
  ///
  /// In en, this message translates to:
  /// **'Writing the profile file…'**
  String get libraryExporting;

  /// Shown while a profile file is being imported.
  ///
  /// In en, this message translates to:
  /// **'Adding the days from the file…'**
  String get libraryImporting;

  /// After an export: how many days the file holds.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Profile exported with 1 day.} other{Profile exported with {count} days.}}'**
  String libraryExported(int count);

  /// After an export: recordings the file could not include.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording was not found on this device and is not in the file.} other{{count} recordings were not found on this device and are not in the file.}}'**
  String libraryExportMissing(int count);

  /// Export failed, for example because the disk is full.
  ///
  /// In en, this message translates to:
  /// **'The profile could not be exported.'**
  String get libraryExportFailed;

  /// After an import: how many days were added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{The file has no days that are not here already.} =1{1 day added.} other{{count} days added.}}'**
  String libraryImported(int count);

  /// After an import: days not added.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day could not be added: it is missing from the file or the library is full.} other{{count} days could not be added: they are missing from the file or the library is full.}}'**
  String libraryImportNotAdded(int count);

  /// Import of a file that is not a readable profile bundle.
  ///
  /// In en, this message translates to:
  /// **'This file cannot be imported. It is not a profile exported from this app, it comes from a newer version, or it is damaged.'**
  String get libraryImportFailed;

  /// Name of the file type in the save and open dialogs for exported profiles.
  ///
  /// In en, this message translates to:
  /// **'Driver profiles'**
  String get profileBundleType;

  /// After an export: days whose file was not found.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day was not found on this device and is not in the file.} other{{count} days were not found on this device and are not in the file.}}'**
  String libraryExportDaysMissing(int count);

  /// After an import whose days were copied but the library file could not be written.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day was copied, but the library could not be saved. It is listed again, in your last car, when the app next starts.} other{{count} days were copied, but the library could not be saved. They are listed again, in your last car, when the app next starts.}}'**
  String libraryImportNotSaved(int count);

  /// Heading of the structured setup (tyre pressures, tyres, fuel) in the session details dialog.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get sessionSetupHeading;

  /// Label next to the choice of the unit the tyre pressures are entered in.
  ///
  /// In en, this message translates to:
  /// **'Tyre pressures'**
  String get sessionSetupPressures;

  /// The pressure unit bar, as a choice and after numbers.
  ///
  /// In en, this message translates to:
  /// **'bar'**
  String get pressureUnitBar;

  /// The pressure unit psi (pounds per square inch), as a choice and after numbers.
  ///
  /// In en, this message translates to:
  /// **'psi'**
  String get pressureUnitPsi;

  /// Column heading, short: the front left wheel.
  ///
  /// In en, this message translates to:
  /// **'FL'**
  String get setupWheelFl;

  /// Column heading, short: the front right wheel.
  ///
  /// In en, this message translates to:
  /// **'FR'**
  String get setupWheelFr;

  /// Column heading, short: the rear left wheel.
  ///
  /// In en, this message translates to:
  /// **'RL'**
  String get setupWheelRl;

  /// Column heading, short: the rear right wheel.
  ///
  /// In en, this message translates to:
  /// **'RR'**
  String get setupWheelRr;

  /// Spoken name of the front left wheel's pressure field.
  ///
  /// In en, this message translates to:
  /// **'front left'**
  String get setupWheelFlName;

  /// Spoken name of the front right wheel's pressure field.
  ///
  /// In en, this message translates to:
  /// **'front right'**
  String get setupWheelFrName;

  /// Spoken name of the rear left wheel's pressure field.
  ///
  /// In en, this message translates to:
  /// **'rear left'**
  String get setupWheelRlName;

  /// Spoken name of the rear right wheel's pressure field.
  ///
  /// In en, this message translates to:
  /// **'rear right'**
  String get setupWheelRrName;

  /// Row label: tyre pressures set cold, before the session.
  ///
  /// In en, this message translates to:
  /// **'Cold'**
  String get sessionSetupCold;

  /// Row label: tyre pressures measured hot, after the session.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get sessionSetupHot;

  /// Spoken name of one tyre pressure field.
  ///
  /// In en, this message translates to:
  /// **'{row}, {wheel}'**
  String sessionSetupPressureField(String row, String wheel);

  /// Shown under the tyre pressures when one is out of range for the chosen unit.
  ///
  /// In en, this message translates to:
  /// **'Pressures in {unit} are from {min} to {max}, with at most two decimals.'**
  String sessionSetupPressureRange(String unit, String min, String max);

  /// Explains that the tyre pressures are stored in the unit chosen and never converted.
  ///
  /// In en, this message translates to:
  /// **'Kept as entered: switching the unit does not convert the numbers.'**
  String get sessionSetupKeptAsEntered;

  /// Text field label: the tyre's name or compound.
  ///
  /// In en, this message translates to:
  /// **'Tyres'**
  String get sessionSetupTyre;

  /// Example tyre in the empty text field.
  ///
  /// In en, this message translates to:
  /// **'Pirelli SC2'**
  String get sessionSetupTyreHint;

  /// Number field label: the fuel in the tank at the start of the session, in litres.
  ///
  /// In en, this message translates to:
  /// **'Fuel at start (l)'**
  String get sessionSetupFuel;

  /// Shown under the fuel field when the number cannot be saved.
  ///
  /// In en, this message translates to:
  /// **'0–200 l, at most two decimals'**
  String get sessionSetupFuelRange;

  /// Button: fills the setup fields from the previous session's setup; nothing is saved until Save.
  ///
  /// In en, this message translates to:
  /// **'Same as {session}'**
  String sessionSetupSameAs(String session);

  /// Shown instead of the setup fields when the setup was stored in a format this version does not edit.
  ///
  /// In en, this message translates to:
  /// **'Saved by a newer version of the app: shown as it is and not changed here.'**
  String get sessionSetupReadOnly;

  /// Part of a session's setup line: the cold tyre pressures FL / FR / RL / RR and their unit.
  ///
  /// In en, this message translates to:
  /// **'Cold {pressures} {unit}'**
  String setupCold(String pressures, String unit);

  /// Part of a session's setup line: the hot tyre pressures FL / FR / RL / RR and their unit.
  ///
  /// In en, this message translates to:
  /// **'Hot {pressures} {unit}'**
  String setupHot(String pressures, String unit);

  /// Part of a session's setup line: the tyre's name or compound.
  ///
  /// In en, this message translates to:
  /// **'Tyres {tyre}'**
  String setupTyres(String tyre);

  /// Part of a session's setup line: the fuel at the start in litres.
  ///
  /// In en, this message translates to:
  /// **'Fuel {litres} l'**
  String setupFuel(String litres);

  /// A session's structured setup on one line, in the session list and the progression.
  ///
  /// In en, this message translates to:
  /// **'Setup: {setup}'**
  String sessionSetupLine(String setup);

  /// Title of the question asked before the previous session's setup replaces values already in the fields.
  ///
  /// In en, this message translates to:
  /// **'Replace the setup?'**
  String get sessionSetupReplaceTitle;

  /// Explains what replacing the setup with the previous session's does.
  ///
  /// In en, this message translates to:
  /// **'The setup fields will hold {session}\'s setup instead of what is in them now. Nothing is saved until Save.'**
  String sessionSetupReplaceBody(String session);

  /// Button: replaces the setup fields with the previous session's setup.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get sessionSetupReplace;

  /// The circuit the route starts on, from the circuit list or named by the user.
  ///
  /// In en, this message translates to:
  /// **'Circuit: {name}'**
  String trackDialogCircuit(String name);

  /// The route's start is near no listed circuit.
  ///
  /// In en, this message translates to:
  /// **'This place is not in the circuit list.'**
  String get trackDialogCircuitUnknown;

  /// Button: opens the dialog that names the circuit at this route's start.
  ///
  /// In en, this message translates to:
  /// **'Name this circuit…'**
  String get trackDialogNameCircuit;

  /// Title of the dialog that names a circuit.
  ///
  /// In en, this message translates to:
  /// **'Circuit name'**
  String get circuitNameTitle;

  /// Under the circuit name field.
  ///
  /// In en, this message translates to:
  /// **'Shown for every day driven here. Kept on this device.'**
  String get circuitNameHelp;

  /// Settings heading: the circuit list.
  ///
  /// In en, this message translates to:
  /// **'Circuits'**
  String get settingsCircuitsHeading;

  /// How many circuits the circuit list holds.
  ///
  /// In en, this message translates to:
  /// **'Circuits in the list: {count}'**
  String settingsCircuitsCount(int count);

  /// Settings help about the circuit list.
  ///
  /// In en, this message translates to:
  /// **'A route\'s circuit is named from where it starts. The list comes from Wikidata (CC0) and is updated with the app\'s update check.'**
  String get settingsCircuitsHelp;

  /// Button: fetch the newest circuit list now.
  ///
  /// In en, this message translates to:
  /// **'Update the circuit list'**
  String get settingsCircuitsUpdate;

  /// Message after a newer circuit list was fetched.
  ///
  /// In en, this message translates to:
  /// **'The circuit list was updated.'**
  String get settingsCircuitsUpdated;

  /// Message when no newer circuit list was found.
  ///
  /// In en, this message translates to:
  /// **'The circuit list is up to date.'**
  String get settingsCircuitsUpToDate;

  /// Message when fetching the circuit list failed.
  ///
  /// In en, this message translates to:
  /// **'The circuit list could not be fetched. Check the connection and try again.'**
  String get settingsCircuitsFailed;

  /// Heading of the circuits the driver named.
  ///
  /// In en, this message translates to:
  /// **'Your circuit names'**
  String get settingsCircuitsMine;

  /// Under a circuit the driver renamed: its name in the list.
  ///
  /// In en, this message translates to:
  /// **'Listed as {name}'**
  String settingsCircuitsRenamed(String name);

  /// Under a circuit the driver added.
  ///
  /// In en, this message translates to:
  /// **'Added by you'**
  String get settingsCircuitsAdded;

  /// Tooltip: remove the driver's circuit name.
  ///
  /// In en, this message translates to:
  /// **'Forget this name'**
  String get settingsCircuitsForget;

  /// Heading of the session summary on the Coach place.
  ///
  /// In en, this message translates to:
  /// **'{session} in 30 seconds'**
  String summaryTitle(String session);

  /// Under the session summary heading.
  ///
  /// In en, this message translates to:
  /// **'Observed from your laps, not causes. Typical is the median of at least 3 laps.'**
  String get summaryIntro;

  /// Session summary when the latest session has no laps in the shown group.
  ///
  /// In en, this message translates to:
  /// **'{session} has no timed laps on the circuit shown.'**
  String summaryNotShown(String session);

  /// Session summary row label.
  ///
  /// In en, this message translates to:
  /// **'Best lap'**
  String get summaryBestLap;

  /// Best lap row when it beats every earlier session; delta is against the earlier best.
  ///
  /// In en, this message translates to:
  /// **'{time} · new best of the day ({delta})'**
  String summaryBestNew(String time, String delta);

  /// Best lap row when an earlier session was quicker.
  ///
  /// In en, this message translates to:
  /// **'{time} · {delta} on the best of {session}'**
  String summaryBestBehind(String time, String delta, String session);

  /// Best lap row for the day's first session.
  ///
  /// In en, this message translates to:
  /// **'{time} · first session of the day'**
  String summaryBestFirst(String time);

  /// Best lap row without an eligible lap.
  ///
  /// In en, this message translates to:
  /// **'No ranked lap'**
  String get summaryNoBest;

  /// Session summary row label: interquartile range of lap times.
  ///
  /// In en, this message translates to:
  /// **'Lap-time spread'**
  String get summarySpread;

  /// Lap-time spread without a previous session to compare.
  ///
  /// In en, this message translates to:
  /// **'{spread} s'**
  String summarySpreadValue(String spread);

  /// Lap-time spread with the previous session's.
  ///
  /// In en, this message translates to:
  /// **'{spread} s ({session}: {previous} s)'**
  String summarySpreadThen(String spread, String session, String previous);

  /// Session summary row label: segment whose typical time fell the most since the session before.
  ///
  /// In en, this message translates to:
  /// **'Biggest gain'**
  String get summaryGain;

  /// Session summary row label: segment whose typical time rose the most since the session before.
  ///
  /// In en, this message translates to:
  /// **'Biggest loss'**
  String get summaryLoss;

  /// A segment and its typical-time change.
  ///
  /// In en, this message translates to:
  /// **'{segment} {delta}'**
  String summaryChange(String segment, String delta);

  /// No segment's typical time changed by the threshold.
  ///
  /// In en, this message translates to:
  /// **'None by {seconds} s or more'**
  String summaryNoChange(String seconds);

  /// Gain/loss rows for the day's first session.
  ///
  /// In en, this message translates to:
  /// **'First session: nothing to compare with'**
  String get summaryFirstSession;

  /// No segment has a typical time in both sessions.
  ///
  /// In en, this message translates to:
  /// **'Needs 3 laps through a segment in both sessions'**
  String get summaryNotCompared;

  /// Footnote under gain and loss.
  ///
  /// In en, this message translates to:
  /// **'Gains and losses: typical segment times against {session}.'**
  String summaryAgainst(String session);

  /// Session summary row label: segment where the typical time is furthest from the quickest typical time of any session.
  ///
  /// In en, this message translates to:
  /// **'Biggest gap left'**
  String get summaryGap;

  /// Biggest gap row value.
  ///
  /// In en, this message translates to:
  /// **'{segment} {delta} to the quickest typical time there'**
  String summaryGapValue(String segment, String delta);

  /// Session summary row label: highest recorded temperatures.
  ///
  /// In en, this message translates to:
  /// **'Car, hottest'**
  String get summaryCar;

  /// One temperature's maximum.
  ///
  /// In en, this message translates to:
  /// **'{channel} {value}'**
  String summaryTemperature(String channel, String value);

  /// One temperature's maximum with the previous session's.
  ///
  /// In en, this message translates to:
  /// **'{channel} {value} ({session}: {previous})'**
  String summaryTemperatureThen(
    String channel,
    String value,
    String session,
    String previous,
  );

  /// Session summary row label: the coach's main focus from the session before.
  ///
  /// In en, this message translates to:
  /// **'Focus from {session}'**
  String summaryGoal(String session);

  /// A summary value still being calculated.
  ///
  /// In en, this message translates to:
  /// **'Working…'**
  String get summaryWorking;

  /// Best lap row when earlier sessions exist but none has a ranked lap.
  ///
  /// In en, this message translates to:
  /// **'{time} · no earlier session has a ranked lap'**
  String summaryBestNoEarlier(String time);

  /// Best lap row when it ties the earlier best.
  ///
  /// In en, this message translates to:
  /// **'{time} · equals the best of {session}'**
  String summaryBestEqual(String time, String session);

  /// Gain/loss rows when no earlier session has a ranked lap.
  ///
  /// In en, this message translates to:
  /// **'No earlier session has a ranked lap'**
  String get summaryNoEarlierRanked;

  /// Session summary row label when segment lines cannot be shown.
  ///
  /// In en, this message translates to:
  /// **'Segments'**
  String get summarySegments;

  /// Segment lines without a theoretical best result.
  ///
  /// In en, this message translates to:
  /// **'Not available without a theoretical best'**
  String get summarySegmentsUnavailable;

  /// Goal row label while the coach works or when no focus was given.
  ///
  /// In en, this message translates to:
  /// **'Focus from the session before'**
  String get summaryGoalBefore;

  /// Goal row when the coach gave no main focus after the session before.
  ///
  /// In en, this message translates to:
  /// **'No change to work on was given'**
  String get summaryNoFocus;

  /// Goal row when the coach failed.
  ///
  /// In en, this message translates to:
  /// **'The coach could not run'**
  String get summaryCoachFailed;

  /// Biggest gap row when the session is within the threshold of the quickest typical time in every segment it was timed in.
  ///
  /// In en, this message translates to:
  /// **'Within {seconds} s of the quickest typical time wherever timed'**
  String summaryGapNone(String seconds);

  /// Biggest gap row when the session has no typical time through any segment.
  ///
  /// In en, this message translates to:
  /// **'Needs 3 laps through a segment'**
  String get summaryGapNeedsLaps;

  /// Biggest gap row when only this session has timed segments.
  ///
  /// In en, this message translates to:
  /// **'No other session to compare with'**
  String get summaryOnlySession;

  /// Button in a session's details dialog that removes the session from the day.
  ///
  /// In en, this message translates to:
  /// **'Remove session'**
  String get removeSession;

  /// Day page menu item that chooses a session to remove from the day.
  ///
  /// In en, this message translates to:
  /// **'Remove a session…'**
  String get removeSessionMenu;

  /// Title of the dialog choosing the session to remove from the day.
  ///
  /// In en, this message translates to:
  /// **'Remove which session?'**
  String get removeSessionChoose;

  /// Title of the dialog confirming that a session leaves the day. session is a label such as 'Session 2'.
  ///
  /// In en, this message translates to:
  /// **'Remove {session}?'**
  String removeSessionTitle(String session);

  /// Body of the dialog confirming that a session leaves the day.
  ///
  /// In en, this message translates to:
  /// **'Its laps leave the day: the best lap, the theoretical best, the coach and your profile are worked out again without them. The recording file itself is not deleted.'**
  String get removeSessionBody;

  /// Button that confirms removing a session from the day.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeSessionConfirm;

  /// Said when the user tries to remove the day's only session.
  ///
  /// In en, this message translates to:
  /// **'A day keeps at least one session. To remove the whole day, delete it in the Library.'**
  String get removeSessionLast;

  /// Said when a session cannot be removed while recordings are being added or checked.
  ///
  /// In en, this message translates to:
  /// **'Wait until the day has finished saving or working on its recordings, then try again.'**
  String get removeSessionBusy;

  /// Said when the save before removing a session failed or was cancelled.
  ///
  /// In en, this message translates to:
  /// **'The day could not be saved, so the session was not removed.'**
  String get removeSessionNotSaved;

  /// Said when the day changed while a session was being removed.
  ///
  /// In en, this message translates to:
  /// **'The day changed meanwhile, so the session was not removed. Try again.'**
  String get removeSessionChangedMeanwhile;

  /// Said when removing a session failed.
  ///
  /// In en, this message translates to:
  /// **'The session was not removed: {error}'**
  String removeSessionFailed(String error);

  /// Said after a session was removed from the day. session is a label such as 'Session 2'.
  ///
  /// In en, this message translates to:
  /// **'{session} removed from the day.'**
  String sessionRemoved(String session);

  /// Action on the message after removing a session that puts it back.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get sessionRemovedUndo;

  /// Said after Undo put a removed session back. session is a label such as 'Session 2'.
  ///
  /// In en, this message translates to:
  /// **'{session} is back in the day.'**
  String sessionRestored(String session);

  /// Said when Undo cannot put a removed session back because the day changed since.
  ///
  /// In en, this message translates to:
  /// **'The day changed since, so the session cannot be put back.'**
  String get sessionRestoreRefused;

  /// Tooltip of the menu on a day in the library.
  ///
  /// In en, this message translates to:
  /// **'Day actions'**
  String get libraryDayActions;

  /// Menu item on a day in the library that deletes the day.
  ///
  /// In en, this message translates to:
  /// **'Delete day'**
  String get libraryDeleteDay;

  /// Title of the dialog confirming that a day is deleted. day is the day's name.
  ///
  /// In en, this message translates to:
  /// **'Delete {day}?'**
  String libraryDeleteDayTitle(String day);

  /// Body of the dialog confirming that a day is deleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{The day and its session leave your profile, and its saved file is deleted. Recording copies the app made for it are deleted too; your own recording files stay where they are. This cannot be undone.} other{The day and its {count} sessions leave your profile, and its saved file is deleted. Recording copies the app made for it are deleted too; your own recording files stay where they are. This cannot be undone.}}'**
  String libraryDeleteDayBody(int count);

  /// Button that confirms deleting a day.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get libraryDeleteConfirm;

  /// Said after a day was deleted from the library. day is the day's name.
  ///
  /// In en, this message translates to:
  /// **'{day} deleted.'**
  String libraryDayDeleted(String day);

  /// Said when deleting a day failed.
  ///
  /// In en, this message translates to:
  /// **'The day was not deleted: {error}'**
  String libraryDayDeleteFailed(String error);

  /// Added to the dialog confirming that a session leaves the day when the day's corners (segments) were measured on that session.
  ///
  /// In en, this message translates to:
  /// **'If the day\'s corners were measured on this session, they are measured again on the best lap left, and names you gave them are lost.'**
  String get removeSessionCorners;

  /// Said when removing a session would leave only sessions whose recordings cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'None of the other sessions\' recordings can be opened, so the day would have nothing to show. The session was not removed.'**
  String get removeSessionNothingLeft;

  /// Said when a day cannot be deleted from the library because it is open.
  ///
  /// In en, this message translates to:
  /// **'Close the day first, then delete it.'**
  String get libraryDeleteDayOpen;

  /// Heading of the driver's own goals on the Next session card.
  ///
  /// In en, this message translates to:
  /// **'Your goals for the next session'**
  String get ownGoalsTitle;

  /// Under the goals heading when goals are set.
  ///
  /// In en, this message translates to:
  /// **'Checked against this session once the next one is added.'**
  String get ownGoalsIntro;

  /// Under the goals heading when none are set.
  ///
  /// In en, this message translates to:
  /// **'Set up to {count} changes to work on, each at one corner. The next session is checked against this one.'**
  String ownGoalsNone(int count);

  /// Goals stored under another version, or in a form this app would not write itself.
  ///
  /// In en, this message translates to:
  /// **'Stored in a form this version of the app does not edit, so they are not changed here.'**
  String get ownGoalsReadOnly;

  /// Why no goal can be added: the day has no corners yet.
  ///
  /// In en, this message translates to:
  /// **'Goals need the day\'s corners.'**
  String get ownGoalsNeedCorners;

  /// Button and dialog title for adding a goal.
  ///
  /// In en, this message translates to:
  /// **'Add a goal'**
  String get ownGoalsAdd;

  /// Tooltip of a goal's remove button.
  ///
  /// In en, this message translates to:
  /// **'Remove goal'**
  String get ownGoalsRemove;

  /// Corner field of the add-goal dialog.
  ///
  /// In en, this message translates to:
  /// **'Corner'**
  String get ownGoalsCorner;

  /// Change field of the add-goal dialog.
  ///
  /// In en, this message translates to:
  /// **'Change to work on'**
  String get ownGoalsChange;

  /// The picked change at the picked corner is already a goal.
  ///
  /// In en, this message translates to:
  /// **'This goal is already set.'**
  String get ownGoalsTaken;

  /// Confirms the add-goal dialog.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get ownGoalsSave;

  /// Session summary row label for one of the driver's own goals; goal is 'Corner 3 · Reduce coasting'.
  ///
  /// In en, this message translates to:
  /// **'Your goal: {goal}'**
  String summaryOwnGoal(String goal);

  /// Shown when the goals the driver changed could not be stored.
  ///
  /// In en, this message translates to:
  /// **'The goals could not be saved.'**
  String get ownGoalsNotSaved;

  /// Why no goal can be added: the session has no lap in the group compared.
  ///
  /// In en, this message translates to:
  /// **'Goals need laps of {session} among the compared laps.'**
  String ownGoalsNeedLaps(String session);

  /// Own goal row when the session the goal was set after, or this one, has no lap in the group compared.
  ///
  /// In en, this message translates to:
  /// **'Not measured: needs laps of {session} and this session among the compared laps'**
  String summaryOwnGoalNoLaps(String session);

  /// Own goal row when the goal was set while another group of compared laps was shown.
  ///
  /// In en, this message translates to:
  /// **'Not measured: set on other compared laps'**
  String get summaryOwnGoalOtherGroup;

  /// Why no goal can be added: the goals already set were set while another group of compared laps was shown.
  ///
  /// In en, this message translates to:
  /// **'These goals were set on other compared laps. Remove them to set new ones.'**
  String get ownGoalsOtherGroup;

  /// Button beside the session summary's title, and the title of the page it opens: a briefing read at the car before the next session.
  ///
  /// In en, this message translates to:
  /// **'Before you go out'**
  String get briefingTitle;

  /// Under the briefing heading: the session the briefing comes from.
  ///
  /// In en, this message translates to:
  /// **'From {session}'**
  String briefingFrom(String session);

  /// Briefing line: the driver's own goals for the next session.
  ///
  /// In en, this message translates to:
  /// **'Your goals'**
  String get briefingGoals;

  /// Briefing goals line when the driver set no goals.
  ///
  /// In en, this message translates to:
  /// **'None set: add them under Your goals for the next session'**
  String get briefingNoGoals;

  /// Briefing line: the segment with the biggest gap to the quickest typical time.
  ///
  /// In en, this message translates to:
  /// **'Biggest chance'**
  String get briefingChance;

  /// Session summary row: what the car did over the session's timed laps (FET-228): a temperature still rising, strong acceleration falling. Observations, not a diagnosis.
  ///
  /// In en, this message translates to:
  /// **'Car, last laps'**
  String get summaryCarWatch;

  /// A temperature's lap maximum still rising over the session's last 3 timed laps.
  ///
  /// In en, this message translates to:
  /// **'{channel} still rising: {from} → {to} (laps {fromLap}–{toLap})'**
  String summaryCarRise(
    String channel,
    String from,
    String to,
    String fromLap,
    String toLap,
  );

  /// Strong acceleration (90th percentile of positive longitudinal G) on the last timed lap below the session's highest.
  ///
  /// In en, this message translates to:
  /// **'Strong acceleration {percent}% lower from lap {fromLap} to lap {toLap} ({from} → {to})'**
  String summaryCarFall(
    String percent,
    String fromLap,
    String toLap,
    String from,
    String to,
  );

  /// The fall in strong acceleration with the temperature that rose most over the same laps.
  ///
  /// In en, this message translates to:
  /// **'{fall}; meanwhile {channel} {from} → {to}'**
  String summaryCarFallWith(
    String fall,
    String channel,
    String from,
    String to,
  );

  /// Car, last laps when nothing was noted and only temperatures could be read.
  ///
  /// In en, this message translates to:
  /// **'No temperature still rising'**
  String get summaryCarSettledTemperatures;

  /// Car, last laps when nothing was noted and only strong acceleration could be read.
  ///
  /// In en, this message translates to:
  /// **'Strong acceleration held'**
  String get summaryCarSettledAcceleration;

  /// Car, last laps: too few ranked laps to read a temperature's rise.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Temperatures: needs 1 ranked lap} other{Temperatures: needs {count} ranked laps}}'**
  String summaryCarTemperaturesNeedLaps(int count);

  /// Car, last laps: too few ranked laps with strong acceleration.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Strong acceleration: needs 1 ranked lap} other{Strong acceleration: needs {count} ranked laps}}'**
  String summaryCarAccelerationNeedsLaps(int count);

  /// Car, last laps: every temperature is missing on one of the laps its rise is read over.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Temperatures: missing on the last ranked lap} other{Temperatures: missing on one of the last {count} ranked laps}}'**
  String summaryCarTemperaturesMissing(int count);

  /// Car, last laps: the last ranked lap has no strong acceleration (too few forward-G samples).
  ///
  /// In en, this message translates to:
  /// **'Strong acceleration: not read on the last ranked lap'**
  String get summaryCarAccelerationMissing;

  /// Under a fall in strong acceleration: it is an observation, not a diagnosis.
  ///
  /// In en, this message translates to:
  /// **'Traffic and a different line lower it too.'**
  String get summaryCarFallNote;

  /// Car, last laps: enough ranked laps, but too few of them have strong acceleration (too few forward-G samples).
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Strong acceleration: read on 1 of {ranked} ranked laps, needs {needed}} other{Strong acceleration: read on {count} of {ranked} ranked laps, needs {needed}}}'**
  String summaryCarAccelerationOnLaps(int count, int ranked, int needed);

  /// Trackside: the latest session's last ranked lap time, in large digits.
  ///
  /// In en, this message translates to:
  /// **'Last ranked lap'**
  String get briefingLastLap;

  /// Trackside: the best lap of the day on the circuit shown.
  ///
  /// In en, this message translates to:
  /// **'Best of the day'**
  String get briefingDayBest;

  /// Trackside: the last lap minus the best of the day (positive is slower).
  ///
  /// In en, this message translates to:
  /// **'To the best'**
  String get briefingDelta;

  /// Trackside: the hottest temperatures and what the car did over the last laps.
  ///
  /// In en, this message translates to:
  /// **'Car'**
  String get briefingCar;

  /// Before you go out, when the latest session has laps on the shown circuit but none ranked.
  ///
  /// In en, this message translates to:
  /// **'{session} has no ranked lap on the circuit shown.'**
  String briefingNoRankedLap(String session);
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
