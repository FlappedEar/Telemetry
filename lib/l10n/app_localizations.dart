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

  /// Link to Apple Maps' legal notices, shown on the Apple Maps background.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get appleMapLegal;

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
