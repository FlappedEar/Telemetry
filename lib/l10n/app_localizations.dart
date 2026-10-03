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
