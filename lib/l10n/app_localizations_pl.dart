// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Polish (`pl`).
class AppLocalizationsPl extends AppLocalizations {
  AppLocalizationsPl([String locale = 'pl']) : super(locale);

  @override
  String get appTitle => 'FlappedEar Telemetry';

  @override
  String get directionClockwise => 'Zgodnie z ruchem wskazówek zegara';

  @override
  String get directionCounterclockwise =>
      'Przeciwnie do ruchu wskazówek zegara';

  @override
  String get directionClockwiseInSentence =>
      'zgodnie z ruchem wskazówek zegara';

  @override
  String get directionCounterclockwiseInSentence =>
      'przeciwnie do ruchu wskazówek zegara';

  @override
  String trackDialogTitle(String session) {
    return '$session';
  }

  @override
  String trackDialogNoRoute(String reason) {
    return 'Nie wykryto trasy: $reason';
  }

  @override
  String get trackDialogNoLaps => 'brak okrążeń';

  @override
  String trackDialogDetectedRoute(String length, String direction) {
    return 'Wykryta trasa: $length m, $direction (na podstawie GPS).';
  }

  @override
  String trackDialogWholeTrace(String session) {
    return 'Cały ślad GPS sesji $session';
  }

  @override
  String get trackDialogLayoutName => 'Konfiguracja toru';

  @override
  String get trackDialogLayoutHint => 'Jastrząb, pełna pętla';

  @override
  String trackDialogSameRoute(String sessions) {
    return 'Także dla sesji na tej samej trasie: $sessions';
  }

  @override
  String get trackDialogUseDetected => 'Użyj wykrytej trasy';

  @override
  String get routeReasonTooFewLaps =>
      'Za mało powtarzalnych, pełnych okrążeń GPS, aby automatycznie rozpoznać trasę.';

  @override
  String get routeReasonConflictingLaps =>
      'Pełne okrążenia prowadzą różnymi trasami; sprawdź konfigurację toru w tym nagraniu.';

  @override
  String get routeReasonSeveralGroups =>
      'Trasa GPS pasuje do kilku niezgodnych grup; sprawdź konfigurację toru w tym nagraniu.';

  @override
  String sessionName(int number) {
    return 'Sesja $number';
  }

  @override
  String get cancel => 'Anuluj';

  @override
  String get save => 'Zapisz';

  @override
  String get settingsAbout => 'O aplikacji';

  @override
  String get settingsLicences => 'Licencje open source';

  @override
  String get licencesLegalese =>
      'FlappedEar Telemetry jest udostępniana na licencji Apache License 2.0.\nMapy © współtwórcy OpenStreetMap (ODbL) i © MapTiler.';

  @override
  String channelFromSource(String format) {
    return 'z $format';
  }

  @override
  String fusionAdded(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Połączono z $format: dodano $count kanału',
      many: 'Połączono z $format: dodano $count kanałów',
      few: 'Połączono z $format: dodano $count kanały',
      one: 'Połączono z $format: dodano 1 kanał',
      zero: 'Połączono z $format: nie dodano kanałów',
    );
    return '$_temp0';
  }

  @override
  String fusionConflict(String channel, String primary, String alternative) {
    return '$channel: $primary i $alternative się różnią';
  }

  @override
  String fusionKeepPrimary(String format) {
    return 'Zostaw $format';
  }

  @override
  String get fusionFillGaps => 'Uzupełnij luki';

  @override
  String fusionUseAlternative(String format) {
    return 'Użyj $format';
  }

  @override
  String fusionNotCombined(String format, String reason) {
    return 'Nie połączono z $format: $reason';
  }

  @override
  String get fusionReasonNoSpeed => 'jedno z nagrań nie ma prędkości';

  @override
  String get fusionReasonShortOverlap => 'nagrania pokrywają się zbyt krótko';

  @override
  String get fusionReasonAmbiguous =>
      'przebiegi prędkości nie pokrywają się jednoznacznie';

  @override
  String get fusionReasonClockDisagrees =>
      'zegary nagrań nie zgadzają się z przebiegami prędkości';

  @override
  String get fusionReasonInsufficient => 'za mało danych, by je dopasować';

  @override
  String get fusionReasonNotFound => 'nie znaleziono nagrania';

  @override
  String get fusionReasonDifferent => 'znaleziony plik to inne nagranie';

  @override
  String get fusionReasonUnreadable => 'nie udało się go odczytać';
}
