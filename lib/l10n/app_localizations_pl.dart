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
  String get mapTilesUnavailable =>
      'Tło mapy wymaga połączenia z internetem; ślad jest rysowany bez niego.';

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
    return 'Wykryta trasa: $length m, $direction (na podstawie GPS).';
  }

  @override
  String trackDialogWholeTrace(String session) {
    return 'Cały ślad GPS sesji $session';
  }

  @override
  String get trackDialogLayoutName => 'Nazwa konfiguracji toru';

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
      'Za mało powtarzalnych, pełnych okrążeń z danymi GPS, aby automatycznie rozpoznać trasę.';

  @override
  String get routeReasonConflictingLaps =>
      'Pełne okrążenia prowadzą różnymi trasami; sprawdź konfigurację toru w tym zapisie.';

  @override
  String get routeReasonSeveralGroups =>
      'Trasa GPS pasuje do kilku niezgodnych grup; sprawdź konfigurację toru w tym zapisie.';

  @override
  String sessionName(int number) {
    return 'Sesja $number';
  }

  @override
  String get settings => 'Ustawienia';

  @override
  String get settingsSpeedUnitHeading =>
      'Jednostka dla prędkości bez oznaczenia';

  @override
  String get settingsSpeedUnitHelp =>
      'Używana tylko dla zapisów, które nie podają jednostki prędkości. Jednostka podana w zapisie jest zawsze pokazywana tak, jak ją podano. Wartości nigdy nie są przeliczane.';

  @override
  String get speedUnitNone => 'Brak';

  @override
  String get settingsNoDayOpen => 'Nie otwarto jeszcze żadnego dnia.';

  @override
  String settingsDeclaredUnits(String units) {
    return 'Zapisy otwartego dnia podają $units.';
  }

  @override
  String get unitsAnd => ' i ';

  @override
  String get settingsAllUnlabelled =>
      'Jego zapisy nie podają jednostki prędkości.';

  @override
  String settingsSomeUnlabelled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count z jego zapisów nie podaje jednostki prędkości.',
      few: '$count z jego zapisów nie podają jednostki prędkości.',
      one: '1 z jego zapisów nie podaje jednostki prędkości.',
    );
    return '$_temp0';
  }

  @override
  String get close => 'Zamknij';

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
      'FlappedEar Telemetry jest udostępniana na licencji Apache License 2.0.\nMapy © współtwórcy OpenStreetMap (ODbL) i © MapTiler.\nDane pogodowe: Open-Meteo.com (CC BY 4.0).';

  @override
  String get coachTitle => 'Następna sesja';

  @override
  String coachSubtitle(String session) {
    return 'Wskazówki dla: $session, na tle szybszych okrążeń dnia';
  }

  @override
  String get coachLoading =>
      'Przygotowywanie wskazówek po obliczeniu teoretycznego czasu okrążenia…';

  @override
  String coachFailed(String error) {
    return 'Nie udało się uruchomić trenera: $error';
  }

  @override
  String get coachNoTheoreticalBest =>
      'Nie udało się obliczyć teoretycznego czasu okrążenia. Bez tego wyniku nie można przygotować wskazówek.';

  @override
  String get coachSpeedHidden =>
      'Prędkości nie są pokazane: jednostki prędkości w zapisach się różnią lub trener przeliczył je na km/h, a prędkości nigdy nie są pokazywane po przeliczeniu ani w różnych jednostkach naraz.';

  @override
  String get coachLabel => 'Sugestia trenera';

  @override
  String get coachFocusLabel => 'Główny cel';

  @override
  String get coachLaterLabel => 'Gdy to już wychodzi';

  @override
  String get coachMeasuredLabel => 'Zmierzono';

  @override
  String get coachTryLabel => 'Spróbuj';

  @override
  String get coachKeepLabel => 'Utrzymaj';

  @override
  String get coachWhy => 'Dlaczego?';

  @override
  String get coachFooter =>
      'Wskazówki trenera wynikają z reguł DrivingCoach i wskazują możliwości poprawy, a nie gwarantowany zysk. Obszary w Przeglądzie przedstawiają obserwacje.';

  @override
  String get coachKindEarlyLift => 'Spróbuj później odjąć gaz';

  @override
  String get coachKindExcessiveCoasting => 'Skróć jazdę bez gazu i hamulca';

  @override
  String get coachKindLowMinimumSpeed =>
      'Utrzymaj wyższą prędkość w najwolniejszym punkcie';

  @override
  String get coachKindEarlyThrottle => 'Dodaj gaz raz';

  @override
  String get coachKindLateThrottle => 'Wcześniej wróć na gaz';

  @override
  String get coachKindInconsistentBraking =>
      'Hamuj w tym samym miejscu na każdym okrążeniu';

  @override
  String get coachKindImproving => 'Utrzymaj obecny sposób jazdy';

  @override
  String coachItemTitle(String segment, String label) {
    return '$segment · $label';
  }

  @override
  String get coachActionEarlyLift =>
      'Spróbuj odjąć gaz nieco później, zachowując sposób dojazdu do zakrętu, który udało Ci się już powtarzać. Nie zmieniaj punktu hamowania.';

  @override
  String get coachActionExcessiveCoasting =>
      'Skróć fragmenty jazdy bez użycia gazu ani hamulca. Skup się na płynnym przechodzeniu między użyciem gazu a hamowaniem. Nie zmieniaj punktu hamowania.';

  @override
  String get coachActionLowMinimumSpeed =>
      'Powtórz tor jazdy i sposób dojazdu do zakrętu z szybszych okrążeń. Staraj się płynniej przejechać najwolniejszy fragment zakrętu. Oceń efekt na wyjściu z zakrętu.';

  @override
  String get coachActionEarlyThrottle =>
      'Dodaj gaz dopiero wtedy, gdy możesz go już utrzymać: jedno płynne dodanie od najwolniejszego punktu, jak na Twoich szybszych okrążeniach.';

  @override
  String get coachActionLateThrottle =>
      'Pracuj nad płynnym, nieco wcześniejszym ponownym dodaniem gazu po najwolniejszym punkcie. Wzoruj się na swoich szybszych okrążeniach.';

  @override
  String get coachActionInconsistentBraking =>
      'Wybierz jeden punkt odniesienia do hamowania i hamuj przy nim na każdym okrążeniu. Przesuń go dopiero, gdy trafiasz w niego regularnie.';

  @override
  String get coachActionImproving =>
      'Utrzymaj sposób jazdy z ostatnich okrążeń. Powtórz go, zanim zmienisz coś innego.';

  @override
  String coachMeasuredOne(String metric, String observed, String reference) {
    return '$metric: $observed na okrążeniach tej sesji, $reference na Twoim szybszym okrążeniu.';
  }

  @override
  String coachMeasuredMany(String metric, String observed, String reference) {
    return '$metric: $observed na okrążeniach tej sesji, $reference na Twoich szybszych okrążeniach.';
  }

  @override
  String coachMeasuredFastest(
    String metric,
    String observed,
    String reference,
  ) {
    return '$metric: $observed na okrążeniach tej sesji, $reference na Twoich trzech najszybszych okrążeniach dnia.';
  }

  @override
  String coachMeasuredImproving(String metric, String before, String after) {
    return '$metric: poprawa na trzech kolejnych okrążeniach, z $before do $after, bez utraty prędkości na wyjściu.';
  }

  @override
  String get coachMetricLiftPoint => 'Punkt odjęcia gazu';

  @override
  String get coachMetricLongestCoast =>
      'Najdłuższa faza jazdy bez gazu i hamulca';

  @override
  String get coachMetricMinimumSpeed => 'Prędkość minimalna';

  @override
  String get coachMetricFirstThrottle => 'Pierwsze dodanie gazu';

  @override
  String get coachMetricEarlyThrottleShare =>
      'Okrążenia z przedwczesnym dodaniem gazu';

  @override
  String get coachMetricCombinedG => 'Średnie łączne przeciążenie';

  @override
  String get coachMetricHighestCombinedG =>
      'Najwyższe tutaj: ta sesja wobec całego dnia';

  @override
  String get coachMetricThrottleReturn => 'Ponowne dodanie gazu';

  @override
  String get coachMetricSegmentTime => 'Czas odcinka';

  @override
  String get coachMetricExitSpeed => 'Prędkość na wyjściu';

  @override
  String get coachMetricBrakingStart => 'Punkt rozpoczęcia hamowania';

  @override
  String get coachMetricCoastDistance => 'Dystans jazdy bez gazu i hamulca';

  @override
  String get coachMetricBrakingSpread => 'Zakres punktów hamowania';

  @override
  String get coachMetricNextStraightTime => 'Prosta za zakrętem';

  @override
  String coachGoalLabel(String session) {
    return 'Główny cel po sesji: $session';
  }

  @override
  String coachGoalMeasured(String metric, String before, String now) {
    return '$metric: w poprzedniej sesji $before, w tej $now.';
  }

  @override
  String coachGoalMeasuredAt(String segment) {
    return 'Zmierzono na odcinku $segment, według dzisiejszego podziału toru.';
  }

  @override
  String get coachGoalNoCorner =>
      'Nie zmierzono: tego zakrętu nie ma w dzisiejszym podziale toru.';

  @override
  String coachMapThis(String metric) {
    return '$metric: okrążenia tej sesji';
  }

  @override
  String coachMapFaster(String metric) {
    return '$metric: Twoje szybsze okrążenia';
  }

  @override
  String coachMapFastest(String metric) {
    return '$metric: Twoje trzy najszybsze okrążenia dnia';
  }

  @override
  String get coachGoalBetter => 'Lepiej.';

  @override
  String get coachGoalUnchanged => 'Mniej więcej bez zmian.';

  @override
  String get coachGoalWorse => 'Gorzej.';

  @override
  String get coachGoalNotMeasured => 'Nie udało się tego zmierzyć w tej sesji.';

  @override
  String get coachReasonReady =>
      'Najpierw pracuj nad głównym celem. Po pozostałe sięgnij dopiero, gdy on już wychodzi.';

  @override
  String get coachReasonNoSegments =>
      'Trener najpierw potrzebuje odcinków i czasów sektorów dnia.';

  @override
  String coachReasonNoLapInGroup(String session) {
    return '$session: wśród porównywanych okrążeń nie ma żadnego okrążenia tej sesji z pomiarem czasu.';
  }

  @override
  String get coachReasonNoCorners =>
      'Porównywane okrążenia nie mają zatwierdzonego zakrętu.';

  @override
  String coachReasonNoRecording(String session) {
    return 'Dane sesji $session są niedostępne, więc nie można przygotować wskazówek.';
  }

  @override
  String coachReasonNoCornerMeasurements(String session) {
    return 'Nie udało się wyznaczyć parametrów przejazdu zakrętu dla żadnego okrążenia sesji $session.';
  }

  @override
  String coachReasonNoFasterLap(String session) {
    return 'Dla żadnego okrążenia sesji $session nie ma szybszego okrążenia z tego dnia do porównania.';
  }

  @override
  String get coachReasonNoPedals =>
      'Nie zarejestrowano sygnałów gazu i hamulca, więc nie można porównać odjęcia gazu, jazdy bez gazu i hamulca ani ponownego dodania gazu. Dane prędkości nie pokazują powtarzalnego wzorca.';

  @override
  String get coachReasonNoPattern =>
      'Na tle szybszych okrążeń nie wyróżnia się żaden wzorzec.';

  @override
  String get coachReasonTooFewLaps =>
      'Wzorzec wystąpił dziś na mniej niż trzech okrążeniach. To za mało, aby przygotować plan.';

  @override
  String get coachReasonBelowThreshold =>
      'Żaden powtarzalny wzorzec nie jest na tyle wyraźny, by sugerować zmianę.';

  @override
  String get coachReasonNotInSession =>
      'Wzorce widoczne wcześniej dziś nie powtarzają się na większości okrążeń tej sesji.';

  @override
  String coachSlowLaps(String laps) {
    return 'Pominięte jako znacznie wolniejsze od typowego okrążenia swojej sesji (ruch na torze, rozgrzewka lub schładzanie): $laps.';
  }

  @override
  String get coachWhyAffected => 'Okrążenia tej sesji';

  @override
  String get coachWhyEarlier =>
      'Wcześniejsze dzisiejsze okrążenia z tym wzorcem';

  @override
  String get coachWhyFaster => 'Porównane szybsze okrążenia';

  @override
  String get coachWhyFastest => 'Twoje trzy najszybsze okrążenia dnia';

  @override
  String get coachWhyBefore => 'Pierwsze z trzech okrążeń';

  @override
  String coachWhyValues(String observed, String reference) {
    return '$observed wobec $reference';
  }

  @override
  String coachWhySupport(String score) {
    return 'Potwierdzenie wzorca: $score / 0.9. Ostrożna ocena zgodności okrążeń z wykrytym wzorcem; nie jest prawdopodobieństwem.';
  }

  @override
  String coachWhyMap(String segment) {
    return 'Ślad najlepszego okrążenia z wyróżnionym odcinkiem: $segment';
  }

  @override
  String get coachCornerMap =>
      'Ślad najlepszego okrążenia z ponumerowanymi zakrętami dnia';

  @override
  String coachCornerMapSelected(String segment) {
    return 'Ślad najlepszego okrążenia z ponumerowanymi zakrętami dnia, wyróżniono: $segment';
  }

  @override
  String get coachCornerMapNote =>
      'Zakręty są ponumerowane tak, jak nazywa je trener.';

  @override
  String get coachCornerMapNoteSelect =>
      'Zakręty są ponumerowane tak, jak nazywa je trener. Dotknij sugestii, aby pokazać jej zakręt.';

  @override
  String get coachShowOnMap => 'pokaż jej zakręt na mapie';

  @override
  String get appleMapLegal => 'Informacje prawne';

  @override
  String get daySectionOverview => 'Przegląd';

  @override
  String get daySectionReport => 'Raport';

  @override
  String get daySectionLaps => 'Okrążenia';

  @override
  String get daySectionCompare => 'Porównaj';

  @override
  String get compareIntro =>
      'Dwa okrążenia obok siebie: gdzie jedno zyskuje, a gdzie traci czas, odcinek po odcinku i zakręt po zakręcie.';

  @override
  String get compareNeedsTwoLaps =>
      'Do porównania potrzebne są dwa sklasyfikowane okrążenia jednego toru.';

  @override
  String get comparePickTwoLaps => 'Porównaj dwa okrążenia';

  @override
  String get compareAgainstBest => 'Względem najlepszego okrążenia dnia';

  @override
  String compareLapA(String time) {
    return 'A $time';
  }

  @override
  String compareLapB(String time) {
    return 'B $time';
  }

  @override
  String get dayBestLabel => 'Najlepsze okrążenie dnia';

  @override
  String get theoreticalBestLabel => 'Teoretyczny czas okrążenia';

  @override
  String get theoreticalBestHint => 'Suma najlepszych czasów odcinków';

  @override
  String get dayResultsTitle => 'Wyniki dnia';

  @override
  String get addRecordings => 'Dodaj zapisy telemetrii';

  @override
  String get dayReport => 'Raport dnia';

  @override
  String get reportShare => 'Udostępnij jako obraz';

  @override
  String get reportImageType => 'Obraz PNG';

  @override
  String get reportShareSaved => 'Raport zapisano jako obraz.';

  @override
  String get reportImageTooLong => 'Raport jest za długi na jeden obraz.';

  @override
  String reportShareFailed(String error) {
    return 'Nie udało się utworzyć obrazu raportu: $error';
  }

  @override
  String get moreActions => 'Więcej';

  @override
  String get saveAs => 'Zapisz jako…';

  @override
  String get addingRecordings => 'Dodawanie zapisów telemetrii';

  @override
  String get waitUntilSessionAdded => 'Poczekaj, aż sesja zostanie dodana.';

  @override
  String get nothingAdded => 'Nic nie dodano.';

  @override
  String addedToDay(String sessions) {
    return 'Dodano do dnia: $sessions.';
  }

  @override
  String savedAs(String file) {
    return 'Zapisano jako $file.';
  }

  @override
  String savedAsChangesPending(String file) {
    return 'Zapisano jako $file. Zmiany wprowadzone podczas zapisywania nie są jeszcze zapisane.';
  }

  @override
  String notSaved(String error) {
    return 'Nie zapisano: $error';
  }

  @override
  String get waitThenFindRecordings =>
      'Poczekaj, aż zapisy zostaną dodane, a potem wyszukaj pozostałe.';

  @override
  String get saveThenFindRecordings =>
      'Najpierw zapisz dzień, a potem wyszukaj jego zapisy danych.';

  @override
  String get recordingsAddedMeanwhile =>
      'W międzyczasie dodano zapisy. Wyszukaj zapisy ponownie.';

  @override
  String dayReopenFailed(String error) {
    return 'Nie udało się ponownie otworzyć dnia: $error';
  }

  @override
  String sessionsNotOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nie udało się otworzyć $count sesji',
      one: 'Nie udało się otworzyć 1 sesji',
    );
    return '$_temp0';
  }

  @override
  String get missingSessionsKept =>
      'Zostają w dniu po zapisaniu, ale nie są pokazywane.';

  @override
  String get lookingForRecordings => 'Szukam…';

  @override
  String get findRecordingsInFolder => 'Znajdź zapisy w folderze…';

  @override
  String lapsShareBestTime(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń ma ten czas; pokazano najwcześniejsze.',
      few: '$count okrążenia mają ten czas; pokazano najwcześniejsze.',
      one: '1 okrążenie ma ten czas.',
    );
    return '$_temp0';
  }

  @override
  String get bestLapTrace =>
      'Ślad najlepszego okrążenia, pokolorowany według prędkości';

  @override
  String get tapToOpenLap => 'Wybierz, aby otworzyć okrążenie.';

  @override
  String get comparedLaps => 'Porównywane okrążenia';

  @override
  String groupLapCount(String group, int eligible, int count) {
    return '$group · $eligible/$count okr.';
  }

  @override
  String lapsRanked(int count, int eligible) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sklasyfikowano $eligible z $count okrążeń',
      one: 'sklasyfikowano $eligible z 1 okrążenia',
    );
    return '$_temp0';
  }

  @override
  String get bestLapOfEachSession => 'Najlepsze okrążenie każdej sesji';

  @override
  String noRankedLap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Brak sklasyfikowanego okrążenia · $count okrążeń',
      few: 'Brak sklasyfikowanego okrążenia · $count okrążenia',
      one: 'Brak sklasyfikowanego okrążenia · 1 okrążenie',
    );
    return '$_temp0';
  }

  @override
  String typicalTime(String time) {
    return 'typowy czas $time';
  }

  @override
  String get circuitNotIdentified =>
      'Nie udało się rozpoznać toru tej sesji, dlatego jej okrążenia nie są porównywane.';

  @override
  String get setCircuit => 'Ustaw tor…';

  @override
  String get circuits => 'Tory';

  @override
  String get notes => 'Uwagi';

  @override
  String get circuitNotIdentifiedShort => 'Nie rozpoznano';

  @override
  String get detectedRoute => 'Wykryta trasa';

  @override
  String get directionUnknown => 'kierunek nieznany';

  @override
  String get circuitSetByYou => 'ustawione przez ciebie';

  @override
  String get circuitInferredFromGps => 'wywnioskowane z GPS';

  @override
  String get noBestLapNoCircuit =>
      'Brak najlepszego okrążenia: żadna sesja nie ma dość pełnych okrążeń GPS, aby rozpoznać tor.';

  @override
  String get noBestLapNoRankable =>
      'Brak najlepszego okrążenia: żadnego okrążenia tej grupy nie można sklasyfikować.';

  @override
  String get bestOfDay => 'Najlepsze okrążenie dnia';

  @override
  String bestOfSession(String session) {
    return 'Najlepsze okrążenie: $session';
  }

  @override
  String lapExcluded(String reason) {
    return 'Wykluczone: $reason';
  }

  @override
  String get lapExcludedNoReason => 'Wykluczone';

  @override
  String lapNotRanked(String issue) {
    return 'Niesklasyfikowane: $issue';
  }

  @override
  String get noStartFinishPass => 'Brak przejazdu przez linię startu/mety';

  @override
  String get notTimed => 'Bez pomiaru czasu';

  @override
  String get pickLapA => 'Okrążenie A';

  @override
  String pickLapB(String lap) {
    return 'Porównaj $lap z';
  }

  @override
  String lapName(String session, int number) {
    return '$session · OKR. $number';
  }

  @override
  String outLapName(String session) {
    return '$session · OKR. WYJAZDOWE';
  }

  @override
  String inLapName(String session) {
    return '$session · OKR. ZJAZDOWE';
  }

  @override
  String unknownLapName(String session) {
    return '$session · NIEZNANE';
  }

  @override
  String circuitGroup(int number, String layout, String direction) {
    return 'Grupa $number · $layout · $direction';
  }

  @override
  String circuitGroupUnresolved(String session) {
    return 'Nierozpoznane · $session';
  }

  @override
  String get noteUndated =>
      'Brak daty i godziny zapisu; pokazano go po zapisach z datą, w kolejności importu.';

  @override
  String get noteNoPasses =>
      'Brak pewnych przejazdów przez linię startu/mety; rodzaj okrążenia jest nieznany.';

  @override
  String get noteNoGps =>
      'Ten zapis nie ma pozycji GPS; nie da się zmierzyć okrążeń.';

  @override
  String get lapIssueLayoutUnresolved => 'Konfiguracja toru do potwierdzenia';

  @override
  String get lapIssueDirectionUnresolved => 'Kierunek do potwierdzenia';

  @override
  String get lapIssueTimingGateUnresolved => 'Nieustalone bramki pomiaru czasu';

  @override
  String get lapIssueChangedLayout => 'Inna konfiguracja toru';

  @override
  String get lapIssueOppositeDirection => 'Przeciwny kierunek';

  @override
  String get lapIssueChangedTimingGate => 'Inne bramki pomiaru czasu';

  @override
  String get lapIssueIncompleteGps => 'Niepełne dane GPS';

  @override
  String get lapIssueInvalidGps => 'Nieprawidłowe dane GPS';

  @override
  String get lapIssueUserExclusion => 'Wykluczone przez użytkownika';

  @override
  String get lapIssueNotTimedLap =>
      'To nie jest pełne okrążenie z pomiarem czasu';

  @override
  String get lapIssueStaleSource =>
      'Źródło się zmieniło; wczytaj zapis ponownie';

  @override
  String get lapIssueIneligibleLap => 'Okrążenie się nie kwalifikuje';

  @override
  String get lapIssueDifferentRoute =>
      'Okrążenie zjeżdża z trasy pozostałych okrążeń (wyjazd poza tor, objazd lub aleja serwisowa)';

  @override
  String get lapIssueImplausibleLap =>
      'Czas lub długość okrążenia są niewiarygodne dla tego toru';

  @override
  String get tbFailedElsewhere =>
      'Niedostępne: nie udało się obliczyć teoretycznego czasu okrążenia.';

  @override
  String get tbTiming => 'Pomiar czasu każdego okrążenia na wspólnej osi toru…';

  @override
  String tbIntro(int segments, int laps) {
    String _temp0 = intl.Intl.pluralLogic(
      segments,
      locale: localeName,
      other: '$segments odcinków',
      one: '1 odcinka',
    );
    String _temp1 = intl.Intl.pluralLogic(
      laps,
      locale: localeName,
      other: '$laps okrążeń',
      one: '1 okrążenia',
    );
    return 'Dla każdego z $_temp0 wybierany jest najlepszy czas spośród $_temp1. Suma czasów odcinków daje teoretyczny czas okrążenia. Wynik łączy fragmenty różnych okrążeń i nie oznacza, że całe okrążenie można przejechać w takim czasie.';
  }

  @override
  String get tbSegmentsProposed =>
      'Odcinki zaproponowano na podstawie najlepszego okrążenia; zapisanie dnia je zachowa.';

  @override
  String get tbSegmentsCorrected => 'Odcinki uwzględniają Twoje poprawki.';

  @override
  String get tbEditSegments => 'Edytuj odcinki';

  @override
  String get tbWhereTimeGoes => 'Gdzie ucieka czas';

  @override
  String tbMarkedBest(String text) {
    return '$text · najlepsze';
  }

  @override
  String tbMapLabel(String lap) {
    return 'Ślad najlepszego okrążenia, każdy odcinek pokolorowany według czasu, jaki traci tam $lap';
  }

  @override
  String get tbTapCorner =>
      'Wybierz zakręt, aby porównać prędkości, hamowanie i ponowne dodanie gazu z najlepszym okrążeniem.';

  @override
  String get tbCompareHint =>
      'Przycisk porównania otwiera to okrążenie na tle najlepszego okrążenia w danym odcinku w Analizatorze zakrętów.';

  @override
  String get tbOpenInAnalyzer => 'Otwórz w Analizatorze zakrętów';

  @override
  String get tbSectorTimes => 'Czasy odcinków';

  @override
  String get tbSectorHint =>
      'Najlepszy czas każdego odcinka jest wyróżniony. Wybierz okrążenie, aby zobaczyć jego straty czasu na mapie.';

  @override
  String tbNotCovered(String time) {
    return 'Brak pełnego pomiaru czasu odcinka na tym okrążeniu · najlepszy czas $time';
  }

  @override
  String tbFastestHere(String time) {
    return 'Najlepszy czas tego odcinka · $time';
  }

  @override
  String tbFastestBy(String time, String lap) {
    return 'Najlepszy czas $time · $lap';
  }

  @override
  String get tbLapUnavailable => 'okrążenie niedostępne';

  @override
  String get tbBestLap => 'Najlepsze okrążenie';

  @override
  String get tbBestLapSameSegments => 'Najlepsze okrążenie, te same odcinki';

  @override
  String get tbAvailable => 'Różnica do czasu teoretycznego';

  @override
  String get tbLapColumn => 'Okrążenie';

  @override
  String get tbTimeColumn => 'Czas';

  @override
  String get tbFastestRow => 'Najlepsze czasy';

  @override
  String tbCellLabel(String column, String value) {
    return '$column: $value';
  }

  @override
  String tbFastestCell(String value) {
    return '$value, najlepszy czas';
  }

  @override
  String tbSegmentCorner(String number) {
    return 'Zakręt $number';
  }

  @override
  String tbSegmentCorners(String numbers) {
    return 'Zakręty $numbers';
  }

  @override
  String tbSegmentStraight(String number) {
    return 'Prosta $number';
  }

  @override
  String get tbNoConfiguration =>
      'Potwierdź zgodną konfigurację toru, aby obliczyć teoretyczny czas okrążenia.';

  @override
  String get tbNoEligibleLaps =>
      'W tej grupie nie ma okrążeń, które można uwzględnić w obliczeniu teoretycznego czasu okrążenia.';

  @override
  String get tbNoApprovedRun =>
      'Żadna sesja w tej grupie nie ma jeszcze zatwierdzonych odcinków. Najpierw zatwierdź odcinki dla co najmniej jednej sesji.';

  @override
  String get tbBestLapOffLine =>
      'Linia GPS najlepszego okrążenia jest gdzieś daleko od większości pozostałych okrążeń, więc odcinki nie zostały wyznaczone automatycznie. Wyklucz z rankingu okrążenia z błędną linią.';

  @override
  String get tbNoApprovedSegments =>
      'Brak zatwierdzonych odcinków potrzebnych do pomiaru czasów.';

  @override
  String get tbIncompleteCoverage =>
      'Co najmniej jeden odcinek nie ma pełnego pomiaru czasu na żadnym okrążeniu uwzględnianym w obliczeniach, dlatego nie pokazano sumy.';

  @override
  String get tbCancelled =>
      'Obliczanie teoretycznego czasu okrążenia zostało anulowane.';

  @override
  String get consistencyHeading => 'Powtarzalność';

  @override
  String consistencyIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return 'Typowy czas to mediana czasów okrążeń. Rozrzut to rozstęp międzykwartylowy, czyli różnica między górnym a dolnym kwartylem i szerokość zakresu obejmującego środkowe 50% czasów. Pojedyncze bardzo wolne lub szybkie okrążenie nie dominuje wyniku. Wymagane minimum: $_temp0.';
  }

  @override
  String get consistencyLapTimes => 'Czasy okrążeń';

  @override
  String get consistencyAllSessions => 'Wszystkie sesje';

  @override
  String get consistencySegmentTimes => 'Czasy odcinków';

  @override
  String get consistencyMeasuring =>
      'Obliczanie powtarzalności wraz z teoretycznym czasem okrążenia…';

  @override
  String consistencyNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Potrzeba co najmniej $_temp0';
  }

  @override
  String consistencyValue(String time, String spread) {
    return '$time · rozrzut $spread s';
  }

  @override
  String consistencyLapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return '$_temp0';
  }

  @override
  String get timeLossTitle => 'Straty czasu';

  @override
  String get timeLossLoading =>
      'Obliczanie strat czasu wraz z teoretycznym czasem okrążenia…';

  @override
  String get timeLossScopeSessionBest => 'Najlepsze okrążenia sesji';

  @override
  String get timeLossScopeEveryLap => 'Każde okrążenie';

  @override
  String timeLossAgainst(String lap) {
    return 'Względem: $lap';
  }

  @override
  String timeLossLapsCompared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń porównanych',
      few: '$count okrążenia porównane',
      one: '1 okrążenie porównane',
    );
    return '$_temp0';
  }

  @override
  String timeLossLossesObserved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zaobserwowanych strat',
      few: '$count zaobserwowane straty',
      one: '1 zaobserwowana strata',
    );
    return '$_temp0';
  }

  @override
  String timeLossUntimedLeftOut(int count) {
    return 'Pominięte odcinki bez pełnego pomiaru czasu: $count';
  }

  @override
  String get timeLossExplanation =>
      'Strata czasu to dodatkowy czas przejazdu danego odcinka względem najlepszego okrążenia. Oba okrążenia mierzone są na wspólnej osi odniesienia wzdłuż toru. Prosta bezpośrednio za zakrętem jest osobnym odcinkiem, dlatego czas stracony na niej nie jest doliczany do straty w zakręcie. Zaobserwowana strata nie oznacza gwarantowanego ani koniecznie bezpiecznego zysku.';

  @override
  String get timeLossNone =>
      'Żadne okrążenie nie straciło czasu do najlepszego okrążenia w żadnym zmierzonym odcinku.';

  @override
  String get timeLossOnlySessionBest =>
      'Przy jednej sesji jej najlepsze okrążenie jest najlepszym okrążeniem dnia, więc nie ma czego porównać. Wybierz Każde okrążenie, aby porównać wszystkie.';

  @override
  String get timeLossNoOtherLap =>
      'Nie udało się porównać żadnego innego okrążenia z najlepszym.';

  @override
  String timeLossShowAll(int count) {
    return 'Pokaż wszystkie ($count)';
  }

  @override
  String get timeLossReasonNoReference =>
      'Nie udało się wyznaczyć czasów odcinków dla najlepszego okrążenia.';

  @override
  String get timeLossReasonBestLapUntimed =>
      'Nie udało się wyznaczyć czasów zatwierdzonych odcinków dla najlepszego okrążenia tej grupy.';

  @override
  String timeLossSegmentAfterCorner(String segment, String corner) {
    return '$segment · po: $corner';
  }

  @override
  String timeLossSegmentAfterTheCorner(String segment) {
    return '$segment · po zakręcie';
  }

  @override
  String get timeLossLapUnavailable => 'Okrążenie niedostępne';

  @override
  String timeLossAgainstBestLap(String lap, String best) {
    return '$lap względem najlepszego okrążenia, $best';
  }

  @override
  String get timeLossUnavailable => 'niedostępne';

  @override
  String get timeLossThisLap => 'To okrążenie';

  @override
  String get timeLossBestLap => 'Najlepsze okrążenie';

  @override
  String get timeLossDifference => 'Różnica';

  @override
  String timeLossThrough(String segment, int start, int end) {
    return '$segment: od $start m do $end m za linią startu/mety.';
  }

  @override
  String timeLossGap(String start, String end) {
    return 'Różnica czasu względem najlepszego okrążenia: $start na początku odcinka, $end na jego końcu.';
  }

  @override
  String get timeLossNoGps => 'Na jednym z okrążeń część odcinka nie ma GPS.';

  @override
  String timeLossMapLabel(String segment) {
    return 'Ślad najlepszego okrążenia z wyróżnionym odcinkiem $segment';
  }

  @override
  String get timeLossDisclaimer =>
      'Zaobserwowana różnica między dwoma okrążeniami, a nie gwarantowany ani koniecznie bezpieczny zysk.';

  @override
  String timeLossOpenLap(String lap) {
    return 'Otwórz $lap';
  }

  @override
  String timeLossCompareWith(String lap) {
    return 'Porównaj z $lap';
  }

  @override
  String get focusTitle => 'Co sprawdzić dalej';

  @override
  String get focusLoading =>
      'Wybieranie obszarów do analizy wraz z obliczaniem teoretycznego czasu okrążenia…';

  @override
  String get focusNone =>
      'Żadna strata, różnica w sektorze ani rozrzut nie są na tyle duże, by je wyróżnić.';

  @override
  String get focusIntro =>
      'Każdy obszar zaczyna się od opisu zmierzonych wyników. Tekst poniżej przedstawia hipotezę do sprawdzenia na okrążeniach, a nie ustaloną przyczynę ani instrukcję.';

  @override
  String get focusKindSectorGap => 'Najlepsze okrążenie a najszybszy sektor';

  @override
  String get focusKindRepeatedLoss => 'Powtarzająca się strata';

  @override
  String get focusKindBrakingSpread => 'Rozrzut punktu hamowania';

  @override
  String get focusKindMinimumSpeedSpread => 'Rozrzut prędkości minimalnej';

  @override
  String focusObserved(String text) {
    return 'Zaobserwowano: $text';
  }

  @override
  String focusHypothesis(String text) {
    return 'Hipoteza: $text';
  }

  @override
  String focusCompareLaps(String lap, String other) {
    return 'Porównaj $lap z $other';
  }

  @override
  String get focusLapUnavailable => 'niedostępne okrążenie';

  @override
  String focusThrough(String segment) {
    return 'Odcinek: $segment';
  }

  @override
  String get focusNotTimed => 'bez pomiaru czasu';

  @override
  String get focusBrakingNotMeasured => 'punkt hamowania niezmierzony';

  @override
  String focusBrakingStarts(int meters) {
    return 'hamowanie zaczyna się na $meters m';
  }

  @override
  String get focusLowestSpeedNotMeasured => 'prędkość minimalna niezmierzona';

  @override
  String focusLowestSpeed(String speed) {
    return 'prędkość minimalna $speed';
  }

  @override
  String get focusDisclaimer =>
      'Wyniki dotyczą wyłącznie tych okrążeń. Nie wskazują, który sposób jazdy jest szybszy lub bezpieczny.';

  @override
  String get focusCompareAB => 'Porównaj okrążenia A i B';

  @override
  String focusBeforeLost(int lost, int measured, String corner, String date) {
    String _temp0 = intl.Intl.pluralLogic(
      measured,
      locale: localeName,
      other: '$measured wizyt',
      one: '1 wizyty',
    );
    return 'Wcześniejsze wizyty tutaj ($corner): ten zakręt kosztował czas na $lost z $_temp0, ostatnio $date.';
  }

  @override
  String focusBeforeNotLastTwo(int lost, int measured, String corner) {
    String _temp0 = intl.Intl.pluralLogic(
      measured,
      locale: localeName,
      other: '$measured wizyt',
      one: '1 wizyty',
    );
    return 'Wcześniejsze wizyty tutaj ($corner): ten zakręt kosztował czas na $lost z $_temp0, ale nie na 2 ostatnich wizytach, na których go zmierzono.';
  }

  @override
  String focusBeforeNever(int measured, String corner) {
    String _temp0 = intl.Intl.pluralLogic(
      measured,
      locale: localeName,
      other: '$measured wizytach',
      one: '1 wizycie',
    );
    return 'Wcześniejsze wizyty tutaj ($corner): ten zakręt zmierzono na $_temp0 i ani razu nie był wśród najkosztowniejszych zakrętów.';
  }

  @override
  String focusBeforeNone(String corner) {
    return 'Wcześniejsze wizyty tutaj ($corner): w Twojej bibliotece brak wizyt tym samochodem.';
  }

  @override
  String focusBeforeNotMeasured(String corner) {
    return 'Wcześniejsze wizyty tutaj ($corner): ten zakręt nie był wcześniej mierzony.';
  }

  @override
  String get focusBeforeNotCorner =>
      'Wcześniejsze wizyty tutaj: w Twojej bibliotece to miejsce nie jest jeszcze żadnym z zakrętów tego toru.';

  @override
  String focusObservationSectorGap(
    String bestLap,
    String gap,
    String segment,
    String sourceLap,
  ) {
    return 'Na Twoim najlepszym okrążeniu ($bestLap) przejazd odcinka $segment trwał o $gap s dłużej niż na okrążeniu $sourceLap, na którym uzyskano najlepszy czas tego odcinka.';
  }

  @override
  String focusHypothesisSectorGap(String segment) {
    return 'Porównanie obu okrążeń na odcinku $segment może pokazać, gdzie stracono czas: w którym miejscu zaczyna się hamowanie, jaka jest prędkość minimalna i kiedy kierowca ponownie dodaje gazu.';
  }

  @override
  String focusObservationRepeatedLoss(
    String count,
    String total,
    String segment,
    String reference,
    String median,
  ) {
    return 'Na $count z $total porównywanych okrążeń odnotowano stratę czasu na odcinku $segment względem $reference (mediana $median s).';
  }

  @override
  String focusHypothesisRepeatedLoss(String reference, String segment) {
    return 'Ponieważ to się powtarza, porównanie typowego okrążenia z $reference w odcinku $segment może pokazać wzorzec, a nie jednorazowy przypadek.';
  }

  @override
  String focusObservationBrakingSpread(
    String segment,
    String spread,
    String count,
  ) {
    return 'Dla odcinka $segment rozrzut punktów rozpoczęcia hamowania wynosi $spread m (środkowe 50% wyników z $count okrążeń; pomiar z sygnału hamulca).';
  }

  @override
  String focusHypothesisBrakingSpread(String segment) {
    return 'Warto sprawdzić bardziej powtarzalny punkt odniesienia do hamowania w odcinku $segment. To nie pokazuje, czy wcześniejsze czy późniejsze hamowanie jest szybsze lub bezpieczne; porównaj najwcześniejszy i najpóźniejszy przykład.';
  }

  @override
  String focusObservationMinimumSpeedSpread(
    String segment,
    String spread,
    String count,
    String median,
  ) {
    return 'Dla odcinka $segment rozrzut prędkości minimalnej wynosi $spread (środkowe 50% wyników z $count okrążeń; mediana $median).';
  }

  @override
  String get focusObservationRecordingUnits =>
      'Prędkości są w jednostkach z zapisu.';

  @override
  String focusHypothesisMinimumSpeedSpread(String segment) {
    return 'Porównanie najwolniejszego i najszybszego przykładu w odcinku $segment może pokazać, co się różni; wyższa prędkość minimalna sama w sobie nie jest lepsza.';
  }

  @override
  String get progressionTitle => 'Postęp';

  @override
  String get progressionBySession => 'Według sesji';

  @override
  String get progressionBySegment => 'Według odcinków';

  @override
  String get progressionSessionsIntro =>
      'Sesje w kolejności zapisu; sesje bez daty i godziny zapisu znajdują się na końcu, w kolejności importu. Pasek pokazuje zakres od najszybszego do najwolniejszego sklasyfikowanego okrążenia na wspólnej skali czasu. Prostokąt obejmuje środkowe 50% czasów, a kreska wskazuje medianę.';

  @override
  String get progressionNoSession => 'Brak sesji do porównania.';

  @override
  String get progressionRecordingTimeUnavailable =>
      'Brak daty i godziny zapisu';

  @override
  String progressionRecordingClock(String time, String date) {
    return '$time UTC, $date';
  }

  @override
  String get progressionNoRecordedLaps => 'Brak zarejestrowanych okrążeń';

  @override
  String progressionNoRankedLap(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Brak sklasyfikowanego okrążenia · 0 z $count okrążeń',
      one: 'Brak sklasyfikowanego okrążenia · 0 z 1 okrążenia',
    );
    return '$_temp0';
  }

  @override
  String progressionLapsRanked(int count, int eligible) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sklasyfikowano $eligible z $count okrążeń',
      one: 'sklasyfikowano $eligible z 1 okrążenia',
    );
    return '$_temp0';
  }

  @override
  String progressionTypical(String time) {
    return 'Typowy czas $time';
  }

  @override
  String progressionTypicalNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sklasyfikowanych okrążeń',
      one: '1 sklasyfikowanego okrążenia',
    );
    return 'Do obliczenia typowego czasu potrzeba co najmniej $_temp0';
  }

  @override
  String progressionBestAgainst(String delta, String session) {
    return 'Różnica najlepszego czasu względem $session: $delta';
  }

  @override
  String progressionConditions(String conditions) {
    return 'Warunki: $conditions';
  }

  @override
  String progressionSetup(String setup) {
    return 'Zmiany ustawień: $setup';
  }

  @override
  String progressionNotes(String notes) {
    return 'Uwagi: $notes';
  }

  @override
  String progressionBestLap(int number) {
    return 'Najlepsze: OKR. $number';
  }

  @override
  String get progressionMeasuring =>
      'Obliczanie postępu wraz z teoretycznym czasem okrążenia…';

  @override
  String progressionSegmentsIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego odcinka w każdej sesji. Najszybszy typowy czas odcinka jest wyróżniony. Mniej niż $count okrążeń: brak statystyk. Wybierz komórkę, aby zobaczyć jej okrążenia.',
      few:
          'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego odcinka w każdej sesji. Najszybszy typowy czas odcinka jest wyróżniony. Mniej niż $count okrążenia: brak statystyk. Wybierz komórkę, aby zobaczyć jej okrążenia.',
      one: 'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego odcinka w każdej sesji. Najszybszy typowy czas odcinka jest wyróżniony. Mniej niż 1 okrążenie: brak statystyk. Wybierz komórkę, aby zobaczyć jej okrążenia.',
    );
    return '$_temp0';
  }

  @override
  String get progressionLapUnavailable => 'Okrążenie niedostępne';

  @override
  String get progressionNoTimedSegments =>
      'Żadna sesja nie ma zmierzonych odcinków.';

  @override
  String progressionSpread(String seconds) {
    return 'rozrzut $seconds s';
  }

  @override
  String progressionLapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return '$_temp0';
  }

  @override
  String get channelOil => 'Temperatura oleju';

  @override
  String get channelCoolant => 'Temperatura płynu chłodzącego';

  @override
  String get channelIntakeAir => 'Temperatura powietrza dolotowego';

  @override
  String get channelGearbox => 'Temperatura skrzyni biegów';

  @override
  String get channelExhaust => 'Temperatura spalin';

  @override
  String get channelAmbient => 'Temperatura otoczenia';

  @override
  String get channelNotRecorded => 'Nie zarejestrowano';

  @override
  String get channelNoValidSamples => 'Brak poprawnych próbek';

  @override
  String channelSummary(
    String mean,
    String minimum,
    String maximum,
    int coverage,
  ) {
    return 'średnio $mean · zakres $minimum–$maximum · dane przez $coverage% czasu';
  }

  @override
  String channelImplausibleLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pominięto $count niewiarygodnych odczytów',
      few: 'Pominięto $count niewiarygodne odczyty',
      one: 'Pominięto 1 niewiarygodny odczyt',
    );
    return '$_temp0';
  }

  @override
  String get channelOutLap => 'okrążenie wyjazdowe';

  @override
  String get channelInLap => 'okrążenie zjazdowe';

  @override
  String channelLapSection(int number) {
    return 'okr. $number';
  }

  @override
  String get channelUnknownSection => 'nieznany fragment zapisu';

  @override
  String get channelCoolingNone => 'nie zarejestrowano';

  @override
  String channelCoolingDrop(String drop, String duration) {
    return '−$drop w $duration';
  }

  @override
  String channelCooling(String cooling) {
    return 'Chłodzenie: $cooling';
  }

  @override
  String get channelLapTime => 'Czas okrążenia';

  @override
  String get channelStrongAcceleration => 'Mocne przyspieszanie';

  @override
  String channelAssociationNoSpread(String metric, int count) {
    return '$metric: brak zróżnicowania temperatury lub analizowanego parametru w tej grupie okrążeń (liczba okrążeń: $count).';
  }

  @override
  String channelAssociationTooFew(String metric, int count, int minimum) {
    return '$metric: liczba porównywalnych okrążeń z danymi temperatury: $count; wymagane minimum: $minimum.';
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
      other: '$metric: ρ $rho · $strength · $count okrążeń — $meaning',
      few: '$metric: ρ $rho · $strength · $count okrążenia — $meaning',
      one: '$metric: ρ $rho · $strength · 1 okrążenie — $meaning',
    );
    return '$_temp0';
  }

  @override
  String get channelStrengthWeak => 'słaba';

  @override
  String get channelStrengthModerate => 'umiarkowana';

  @override
  String get channelStrengthStrong => 'silna';

  @override
  String get channelMeaningLittle => 'niewielki związek';

  @override
  String get channelMeaningQuicker =>
      'przy wyższej temperaturze rejestrowano krótsze czasy okrążeń';

  @override
  String get channelMeaningSlower =>
      'przy wyższej temperaturze rejestrowano dłuższe czasy okrążeń';

  @override
  String get channelMeaningHarder =>
      'na okrążeniach z wyższą temperaturą przyspieszanie było mocniejsze';

  @override
  String get channelMeaningLess =>
      'na okrążeniach z wyższą temperaturą przyspieszanie było słabsze';

  @override
  String get channelCarTitle => 'Samochód';

  @override
  String get channelCarReading =>
      'Odczytywanie temperatur zarejestrowanych w każdej sesji…';

  @override
  String get channelCarNoChannels =>
      'Żaden zapis nie zawiera kanału temperatury.';

  @override
  String get channelCarIntro =>
      'Każda sesja analizowana jest osobno, w kolejności zapisu. Luki w danych nie są uzupełniane; niewiarygodne odczyty i zera zastępujące brak danych są pomijane i zliczane. Za okres chłodzenia uznaje się spadek temperatury o co najmniej 5° w okresie trwającym co najmniej 30 s, z ciągłym zapisem danych.';

  @override
  String get channelUnitsNotDeclared => 'zapis nie podaje jednostki';

  @override
  String get channelConfounded =>
      'Temperatura zmieniała się też w ciągu dnia, więc nie da się tego oddzielić od wszystkiego innego, co się zmieniło: kierowcy, opon, toru i paliwa.';

  @override
  String get channelHeartRateIntro =>
      'Zaobserwowane wartości z zapisu, nie ocena.';

  @override
  String get channelEverySectionIntro =>
      'Każdy zarejestrowany fragment każdej sesji.';

  @override
  String get channelWithLapPerformance =>
      'Związek z wynikami przejazdu okrążeń';

  @override
  String channelConfoundedRose(String rho) {
    return 'Temperatura rosła też w ciągu dnia (ρ $rho z kolejnością okrążeń), więc nie da się tego oddzielić od wszystkiego innego, co zmieniło się w ciągu dnia: kierowcy, opon, toru i paliwa.';
  }

  @override
  String channelConfoundedFell(String rho) {
    return 'Temperatura spadała też w ciągu dnia (ρ $rho z kolejnością okrążeń), więc nie da się tego oddzielić od wszystkiego innego, co zmieniło się w ciągu dnia: kierowcy, opon, toru i paliwa.';
  }

  @override
  String channelSpearman(int coverage, int lowCoverage, int notRecorded) {
    return 'Korelacja rang Spearmana dla porównywanych okrążeń z tego dnia, dla których dane z czujnika obejmują co najmniej $coverage% okrążenia. Pominięte z powodu zbyt małej dostępności danych: $lowCoverage; bez poprawnego odczytu: $notRecorded. Opisuje wspólne zmiany obu wielkości tego dnia; nie wyznacza temperatury krytycznej ani przyczyny.';
  }

  @override
  String get channelDriverTitle => 'Kierowca';

  @override
  String get channelDriverReading =>
      'Odczytywanie tętna zarejestrowanego w każdej sesji…';

  @override
  String get channelDriverNoHeartRate => 'Nie zarejestrowano tętna.';

  @override
  String get channelDriverIntro =>
      'Tętno z zapisów: zaobserwowane wartości, nie ocena. Dla każdego okrążenia podano średnie tętno w bpm. Wybierz okrążenie, aby je otworzyć.';

  @override
  String get channelHeartRate => 'Tętno';

  @override
  String get channelEverySection => 'Każdy odcinek…';

  @override
  String channelLapMean(int number, String mean) {
    return 'OKR. $number · $mean';
  }

  @override
  String get channelRecordingUnavailable => 'Zapis niedostępny.';

  @override
  String get channelSummariesCancelled =>
      'Obliczanie podsumowań kanałów anulowano.';

  @override
  String cornerSummaryMin(String speed) {
    return 'Min $speed';
  }

  @override
  String cornerSummaryMinWithBest(String speed, String best) {
    return 'Min $speed (najlepsze okrążenie $best)';
  }

  @override
  String cornerSummaryBrakes(String where) {
    return 'początek hamowania $where';
  }

  @override
  String cornerSummaryBrakesWithBest(String where, String position) {
    return 'początek hamowania $where ($position)';
  }

  @override
  String cornerBeforeEntry(int metres) {
    return '$metres m przed wejściem w zakręt';
  }

  @override
  String cornerIntoCorner(int metres) {
    return '$metres m od wejścia w zakręt';
  }

  @override
  String get cornerSamePosition => 'w tym samym miejscu';

  @override
  String cornerLater(int metres) {
    return '$metres m później';
  }

  @override
  String cornerEarlier(int metres) {
    return '$metres m wcześniej';
  }

  @override
  String get missingRecordingNotFound => 'Nie znaleziono zapisu.';

  @override
  String get missingRecordingDuplicate =>
      'Ten sam zapis co inna sesja tego dnia.';

  @override
  String get missingRecordingDifferent => 'Znaleziony plik to inny zapis.';

  @override
  String get lapB => 'Okrążenie B';

  @override
  String get suggestedFastest => 'Propozycja: najszybsze';

  @override
  String get noOtherRankedLap =>
      'W tej grupie nie ma innego sklasyfikowanego okrążenia do porównania.';

  @override
  String get addingCancelled => 'Anulowano dodawanie.';

  @override
  String get dayClosed => 'Dzień został zamknięty.';

  @override
  String nothingAddedError(String error) {
    return 'Nic nie dodano: $error';
  }

  @override
  String get diagnosticsTitle => 'Diagnostyka';

  @override
  String get diagnosticsRefresh => 'Odśwież';

  @override
  String get diagnosticsLastImport => 'Ostatni import';

  @override
  String get diagnosticsNoImport =>
      'Od uruchomienia aplikacji nie zaimportowano żadnego dnia.';

  @override
  String get diagnosticsRecordingsRead => 'Odczytane zapisy';

  @override
  String get diagnosticsSessions => 'Sesje';

  @override
  String get diagnosticsSamples => 'Próbki';

  @override
  String get diagnosticsChannelValues => 'Wartości kanałów';

  @override
  String get diagnosticsMemory => 'Pamięć';

  @override
  String get diagnosticsCurrentMemory => 'Bieżąca';

  @override
  String get diagnosticsPeakMemory => 'Szczytowa';

  @override
  String get diagnosticsNotAvailable => 'Niedostępne';

  @override
  String get diagnosticsMemoryNote =>
      'Pamięć rezydentna aplikacji według systemu; szczytowa liczona od uruchomienia aplikacji. Czasy to rzeczywisty czas na tym urządzeniu.';

  @override
  String get diagnosticsStepScan => 'Wyszukiwanie zapisów';

  @override
  String get diagnosticsStepParse => 'Odczyt i import';

  @override
  String get diagnosticsStepAnalysis => 'Analiza dnia';

  @override
  String get diagnosticsStepImportTotal => 'Import, od startu do wyników';

  @override
  String get diagnosticsStepTheoreticalBest =>
      'Odcinki i teoretyczny czas okrążenia';

  @override
  String get diagnosticsStepChannelSummaries => 'Podsumowania kanałów';

  @override
  String get diagnosticsStepFusion => 'Dopasowanie i połączenie VBO z RCZ';

  @override
  String get diagnosticsStepAddSession => 'Dodanie sesji';

  @override
  String get diagnosticsStepCoach => 'Trener';

  @override
  String get diagnosticsStepAddToCoach => 'Dodanie sesji, aż do planu trenera';

  @override
  String get reportGroupNone =>
      'Wybierz grupę zgodnych okrążeń na stronie wyników.';

  @override
  String get reportCalculating => 'Obliczanie…';

  @override
  String get reportNotCalculated => 'Jeszcze nie obliczono.';

  @override
  String get reportOutOfDate => 'Nieaktualne po zmianie analizy.';

  @override
  String get reportUnavailable => 'Niedostępne.';

  @override
  String get reportNotInReport => 'Brak w tym raporcie.';

  @override
  String get reportChooseGroup => 'Wybierz grupę zgodności.';

  @override
  String get reportNoEligibleLap =>
      'W tej grupie nie ma kwalifikującego się okrążenia.';

  @override
  String get reportNoSession => 'W tej grupie nie ma sesji.';

  @override
  String get reportNoEligibleLaps =>
      'Brak kwalifikujących się okrążeń do podsumowania.';

  @override
  String get reportNoHeartRate => 'Nie zarejestrowano tętna.';

  @override
  String get reportNoTemperature => 'Nie zarejestrowano temperatury.';

  @override
  String get reportBestTitle =>
      'Najlepsze okrążenie i różnica do czasu teoretycznego';

  @override
  String get reportBestLap => 'Najlepsze okrążenie';

  @override
  String get reportTheoreticalBest => 'Teoretyczny czas okrążenia';

  @override
  String reportTheoreticalAvailable(String seconds) {
    return '$seconds s różnicy do czasu teoretycznego na zatwierdzonych odcinkach';
  }

  @override
  String get reportTheoreticalNoTotal =>
      'Dla części odcinków brakuje pełnego pomiaru czasu; nie można obliczyć sumy.';

  @override
  String get reportOpenBestLap => 'Otwórz najlepsze okrążenie';

  @override
  String get reportFocusIntro =>
      'Każda pozycja zaczyna się od tego, co zmierzono. Wiersz pod spodem to hipoteza do sprawdzenia na okrążeniach, a nie przyczyna ani polecenie.';

  @override
  String reportFocusCompare(String lap, String other, String segment) {
    return 'Porównaj $lap z $other ($segment)';
  }

  @override
  String get reportLossesTitle => 'Największe straty czasu';

  @override
  String reportLossesIntro(String reference, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'porównano $count okrążeń',
      few: 'porównano $count okrążenia',
      one: 'porównano 1 okrążenie',
    );
    return 'Względem $reference · $_temp0. Zaobserwowana strata nie oznacza gwarantowanego ani koniecznie bezpiecznego zysku.';
  }

  @override
  String get reportSessionsTitle => 'Sesje';

  @override
  String get reportNoEligibleLapShort => 'brak kwalifikującego się okrążenia';

  @override
  String reportSessionBest(String time) {
    return 'najlepszy czas $time';
  }

  @override
  String get reportSameAsPrevious => 'tak samo jak w poprzedniej sesji';

  @override
  String reportFasterThanPrevious(String seconds) {
    return '$seconds s szybciej niż w poprzedniej sesji';
  }

  @override
  String reportSlowerThanPrevious(String seconds) {
    return '$seconds s wolniej niż w poprzedniej sesji';
  }

  @override
  String reportEligibleLaps(int eligible, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    String _temp1 = intl.Intl.pluralLogic(
      eligible,
      locale: localeName,
      other: 'kwalifikuje się',
      few: 'kwalifikują się',
    );
    return '$eligible z $_temp0 $_temp1';
  }

  @override
  String reportMedian(String time) {
    return 'mediana $time';
  }

  @override
  String reportConsistencyDay(String time, String spread, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return 'Typowy czas okrążenia $time · rozstęp międzykwartylowy $spread s · $_temp0';
  }

  @override
  String reportConsistencyTooFew(int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      minimum,
      locale: localeName,
      other:
          'Mniej niż $minimum okrążeń kwalifikujących się do analizy; brak rozrzutu.',
      few:
          'Mniej niż $minimum okrążenia kwalifikujące się do analizy; brak rozrzutu.',
      one: 'Mniej niż 1 okrążenie kwalifikujące się do analizy; brak rozrzutu.',
    );
    return '$_temp0';
  }

  @override
  String reportCarPeak(String channel, String value, String session) {
    return '$channel · maksimum $value ($session)';
  }

  @override
  String reportCoolingIntervals(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count zarejestrowanych okresów chłodzenia',
      few: '$count zarejestrowane okresy chłodzenia',
      one: '1 zarejestrowany okres chłodzenia',
    );
    return '$_temp0';
  }

  @override
  String get reportNoCooling => 'nie zarejestrowano okresu chłodzenia';

  @override
  String get reportNoTemperatureSamples =>
      'Brak poprawnych próbek temperatury.';

  @override
  String reportHeartRateSummary(String mean, String minimum, String maximum) {
    return 'średnio $mean bpm · $minimum – $maximum';
  }

  @override
  String reportCovered(int percent) {
    return 'dane przez $percent% czasu sesji';
  }

  @override
  String get segmentEditorTitle => 'Edytuj odcinki';

  @override
  String get segmentEditorUndo => 'Cofnij';

  @override
  String get segmentEditorRedo => 'Ponów';

  @override
  String get segmentEditorTiming =>
      'Mierzenie czasu każdego okrążenia na jednej osi toru…';

  @override
  String get segmentEditorMapLabel =>
      'Ślad najlepszego okrążenia z granicami odcinków';

  @override
  String segmentEditorMapLabelHighlighted(String segment) {
    return 'Ślad najlepszego okrążenia z granicami odcinków, wyróżniono: $segment';
  }

  @override
  String get segmentEditorAutomatic => 'Automatycznie wyznaczone odcinki';

  @override
  String get segmentEditorEdited => 'Zmienione odcinki';

  @override
  String segmentEditorSummary(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count odcinków',
      few: '$count odcinki',
      one: '1 odcinek',
    );
    return 'Teoretyczny czas okrążenia $time · $_temp0';
  }

  @override
  String get segmentEditorRestoreAutomatic => 'Przywróć automatyczny podział';

  @override
  String segmentEditorProposedFrom(String lap) {
    return 'Zaproponowane na podstawie: $lap. Wybierz odcinek, aby go poprawić.';
  }

  @override
  String get segmentEditorProposedFromBestLap =>
      'Zaproponowane na podstawie najlepszego okrążenia. Wybierz odcinek, aby go poprawić.';

  @override
  String get segmentEditorCorrectionsSaved =>
      'Twoje poprawki są zapisywane wraz z danymi dnia i nie są zastępowane odcinkami wyznaczonymi automatycznie.';

  @override
  String get segmentEditorTypeCorner => 'Zakręt';

  @override
  String get segmentEditorTypeStraight => 'Prosta';

  @override
  String get segmentEditorTypeSector => 'Sektor';

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
    return '$row · zmieniony';
  }

  @override
  String get segmentEditorRestoreTitle =>
      'Przywrócić automatyczny podział toru?';

  @override
  String get segmentEditorRestoreBody =>
      'Twoje zmiany podziału tej konfiguracji toru zostaną zastąpione odcinkami zaproponowanymi na podstawie najlepszego okrążenia.';

  @override
  String get segmentEditorRestore => 'Przywróć';

  @override
  String get segmentEditorName => 'Nazwa';

  @override
  String get segmentEditorStart => 'Początek';

  @override
  String get segmentEditorEnd => 'Koniec';

  @override
  String get segmentEditorKeepJoined =>
      'Przesuń też granicę sąsiedniego odcinka';

  @override
  String get segmentEditorApply => 'Zastosuj';

  @override
  String get segmentEditorReset => 'Resetuj';

  @override
  String segmentEditorSplitAt(String meters) {
    return 'Podział w punkcie $meters m';
  }

  @override
  String get segmentEditorSplitHere => 'Podziel tutaj';

  @override
  String get segmentEditorMergeWithNext => 'Połącz z następnym';

  @override
  String segmentEditorMergeWith(String segment) {
    return 'Połącz z $segment';
  }

  @override
  String get segmentEditorRemove => 'Usuń';

  @override
  String get segmentEditorErrorSaving => 'Dzień jest właśnie zapisywany.';

  @override
  String get segmentEditorErrorNotCalculated =>
      'Odcinki można edytować po obliczeniu teoretycznego czasu okrążenia.';

  @override
  String get segmentEditorErrorAlreadyAutomatic =>
      'Odcinki są już automatyczne.';

  @override
  String get segmentEditorErrorNotPossible => 'Ta zmiana nie jest możliwa.';

  @override
  String get segmentEditorErrorLastSegment =>
      'Obliczenie teoretycznego czasu okrążenia wymaga co najmniej jednego odcinka. Przywróć automatyczny podział toru.';

  @override
  String get segmentEditorErrorNoLongerApproved =>
      'Ten odcinek nie jest już zatwierdzony.';

  @override
  String get segmentEditorErrorNothingToUndo => 'Nie ma czego cofnąć.';

  @override
  String get segmentEditorErrorNothingToRedo => 'Nie ma czego ponowić.';

  @override
  String get segmentEditorErrorHistoryCleared =>
      'Odcinki zmieniły się poza tym edytorem, więc historia zmian została wyczyszczona.';

  @override
  String get segmentEditorErrorInvalidStored =>
      'Zapisane zatwierdzone odcinki są nieprawidłowe.';

  @override
  String get segmentEditorErrorOtherConfiguration =>
      'Najpierw trzeba odrzucić odcinki zatwierdzone dla innej konfiguracji toru.';

  @override
  String segmentEditorErrorWouldBeEmpty(String segment) {
    return 'Odcinek „$segment” byłby pusty.';
  }

  @override
  String segmentEditorErrorWouldBeInvalid(String segment) {
    return 'Odcinek „$segment” byłby nieprawidłowy.';
  }

  @override
  String segmentEditorErrorWouldOverlap(String segment, String other) {
    return 'Odcinek „$segment” nachodziłby na „$other”.';
  }

  @override
  String segmentEditorErrorTooMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Można zatwierdzić najwyżej $count odcinków.',
      few: 'Można zatwierdzić najwyżej $count odcinki.',
      one: 'Można zatwierdzić najwyżej 1 odcinek.',
    );
    return '$_temp0';
  }

  @override
  String get segmentEditorErrorCrossesGate =>
      'Tylko jeden odcinek może przecinać linię startu/mety.';

  @override
  String get segmentEditorErrorChooseType =>
      'Wybierz zakręt, prostą lub sektor.';

  @override
  String get segmentEditorErrorNoAxis => 'Oś toru jest niedostępna.';

  @override
  String get segmentEditorErrorSplitInside =>
      'Dziel wewnątrz odcinka, z dala od jego końców.';

  @override
  String get segmentEditorErrorSplitName =>
      'Wpisz nazwę nowego odcinka (1–160 znaków).';

  @override
  String get segmentEditorErrorMergeSame =>
      'Wybierz dwa różne zatwierdzone odcinki.';

  @override
  String get segmentEditorErrorMergeNotAdjacent =>
      'Połączyć można tylko odcinki o wspólnej granicy.';

  @override
  String get segmentEditorErrorMergeWholeLap =>
      'Połączenie objęłoby całe okrążenie; odcinek musi mieć różny początek i koniec.';

  @override
  String get segmentEditorErrorName => 'Wpisz nazwę (1–160 znaków).';

  @override
  String segmentEditorErrorBounds(String length) {
    return 'Granice muszą leżeć między 0 a $length m.';
  }

  @override
  String get segmentEditorErrorEmpty => 'Odcinek nie może być pusty.';

  @override
  String get reportStale =>
      'Ustawienia analizy zmieniły się po obliczeniu tego wyniku.';

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
  String get fusionReasonNoSpeed => 'jeden z zapisów nie ma prędkości';

  @override
  String get fusionReasonShortOverlap => 'zapisy pokrywają się zbyt krótko';

  @override
  String get fusionReasonAmbiguous =>
      'przebiegi prędkości nie pokrywają się jednoznacznie';

  @override
  String get fusionReasonClockDisagrees =>
      'zegary zapisów nie zgadzają się z przebiegami prędkości';

  @override
  String get fusionReasonInsufficient => 'za mało danych, by je dopasować';

  @override
  String get fusionReasonNotFound => 'nie znaleziono zapisu';

  @override
  String get fusionReasonDifferent => 'znaleziony plik to inny zapis';

  @override
  String get fusionReasonUnreadable => 'nie udało się go odczytać';

  @override
  String fusionPending(String format) {
    return 'Dopasowywanie do $format…';
  }

  @override
  String fusionLinedUp(String format, String offset) {
    return 'Dopasowano do $format ($offset); nic do dodania';
  }

  @override
  String fusionCombinedWith(String format, String sessions) {
    return 'Dodano $format do: $sessions.';
  }

  @override
  String fusionMissingTitle(int count, String format) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nie można użyć plików $format dla $count sesji',
      many: 'Nie można użyć plików $format dla $count sesji',
      few: 'Nie można użyć plików $format dla $count sesji',
      one: 'Nie można użyć pliku $format dla 1 sesji',
    );
    return '$_temp0';
  }

  @override
  String fusionMissingLine(String session, String path, String reason) {
    return '$session: $path · $reason';
  }

  @override
  String get fusionChannelSpeed => 'Prędkość';

  @override
  String get fusionChannelLatitude => 'Szerokość geograficzna';

  @override
  String get fusionChannelLongitude => 'Długość geograficzna';

  @override
  String get fusionChannelSatellites => 'Satelity';

  @override
  String fusionRelinkDifferent(String files) {
    return 'Nie użyto, to inny zapis: $files.';
  }

  @override
  String fusionAddedNotCombined(String format, String sessions) {
    return 'Dodano $format do: $sessions, ale nie udało się połączyć danych. Plik pozostaje zapisany; przy ponownym otwarciu dnia aplikacja ponowi próbę połączenia.';
  }

  @override
  String get fusionReasonFailed => 'dopasowanie się nie powiodło';

  @override
  String relinkDifferentRecordings(int count, String files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count plików w tym folderze ($files) to inne zapisy i nie zostały użyte.',
      many:
          '$count plików w tym folderze ($files) to inne zapisy i nie zostały użyte.',
      few:
          '$count pliki w tym folderze ($files) to inne zapisy i nie zostały użyte.',
      one: '$files w tym folderze to inny zapis i nie został użyty.',
    );
    return '$_temp0';
  }

  @override
  String get relinkNothingFound =>
      'W tym folderze nie znaleziono żadnego brakującego zapisu.';

  @override
  String get segmentPickOnMap => 'Wskaż na mapie';

  @override
  String get segmentPickActive => 'Wskaż punkt na mapie… (anuluj)';

  @override
  String get segmentPickBannerStart =>
      'Wskaż punkt na śladzie przejazdu, aby ustawić początek';

  @override
  String get segmentPickBannerEnd =>
      'Wskaż punkt na śladzie przejazdu, aby ustawić koniec';

  @override
  String get segmentPickBannerSplit =>
      'Wskaż punkt na śladzie przejazdu, aby ustawić miejsce podziału';

  @override
  String get segmentPickAmbiguous =>
      'W pobliżu przebiega inny fragment toru. Ustaw odległość przyciskami.';

  @override
  String get segmentPickFar =>
      'Wskaż punkt na śladzie przejazdu tego okrążenia.';

  @override
  String get segmentPickNoTrace =>
      'Nie można wskazać punktu: ślad tego okrążenia jest niedostępny.';

  @override
  String get segmentPickOutside =>
      'Aby podzielić odcinek, wskaż punkt wewnątrz niego.';

  @override
  String get variabilityHeading => 'Powtarzalność w zakrętach';

  @override
  String get variabilityIntro =>
      'Porównanie parametrów przejazdu każdego zakrętu na kolejnych okrążeniach tej grupy. Wartość typowa to mediana, a rozrzut to rozstęp międzykwartylowy, czyli szerokość zakresu obejmującego środkowe 50% wartości. Obliczenia wymagają co najmniej 3 okrążeń. To obserwacje, a nie wyjaśnienie przyczyn.';

  @override
  String get variabilityNone =>
      'Żaden zakręt nie został zmierzony na wystarczającej liczbie okrążeń.';

  @override
  String get variabilityNotMeasured => 'Nie zmierzono na tych okrążeniach.';

  @override
  String variabilityLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążenia',
      many: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return '$_temp0';
  }

  @override
  String get variabilityMeasured => 'zmierzony';

  @override
  String get variabilityInferred => 'wyznaczony pośrednio';

  @override
  String variabilitySpread(String label, String spread, String tail) {
    return '$label: rozrzut $spread · $tail';
  }

  @override
  String variabilityTypical(
    String label,
    String typical,
    String spread,
    String tail,
  ) {
    return '$label: typowa $typical · rozrzut $spread · $tail';
  }

  @override
  String variabilityTooFew(String label, String tail) {
    return '$label: za mało okrążeń ($tail)';
  }

  @override
  String get variabilityBraking => 'Punkt rozpoczęcia hamowania';

  @override
  String get variabilityApex => 'Prędkość na wierzchołku';

  @override
  String get variabilityMinimum => 'Prędkość minimalna';

  @override
  String get variabilityExit => 'Prędkość na wyjściu';

  @override
  String get variabilityPickup => 'Punkt ponownego dodania gazu';

  @override
  String variabilityGpsAccuracy(String meters) {
    return 'dokładność GPS około $meters m';
  }

  @override
  String get variabilityGpsUnknown => 'dokładność GPS nie jest zapisana';

  @override
  String get calculateAgain => 'Oblicz ponownie';

  @override
  String get retryRecordings => 'Ponów odczyt zapisów';

  @override
  String get retryRecordingsLooking => 'Otwieranie…';

  @override
  String get retryRecordingsSaveFirst =>
      'Najpierw zapisz dzień, potem ponów odczyt zapisów danych.';

  @override
  String get retryRecordingsStill =>
      'Zapisy nadal nie są tam, gdzie wskazuje dzień.';

  @override
  String get sessionDetailsHeading => 'Szczegóły sesji';

  @override
  String get sessionDetailsNone =>
      'Brak warunków, ustawień, zmian w ustawieniach i notatek';

  @override
  String sessionDetailsTitle(String session) {
    return 'Szczegóły: $session';
  }

  @override
  String get sessionDetailsName => 'Nazwa';

  @override
  String get sessionDetailsNameRequired => 'Sesja musi mieć nazwę.';

  @override
  String get sessionDetailsConditions => 'Warunki';

  @override
  String get sessionDetailsConditionsHint => 'Sucho, 18 °C';

  @override
  String get sessionDetailsSetup => 'Zmiany ustawień samochodu';

  @override
  String get sessionDetailsSetupHint => 'Ciśnienie w oponach +0.1 bar';

  @override
  String get sessionDetailsNotes => 'Notatki';

  @override
  String get sessionDetailsSaved =>
      'Zapisywane w pliku dnia, obsługiwanym także przez FlappedEar Overlays.';

  @override
  String get detailsInvalid => 'Tego tekstu nie można zapisać.';

  @override
  String get renameDayMenu => 'Zmień nazwę dnia…';

  @override
  String get renameDayTitle => 'Zmiana nazwy dnia';

  @override
  String get renameDayName => 'Nazwa dnia';

  @override
  String get renameDayRequired => 'Dzień musi mieć nazwę.';

  @override
  String get retryRecordingsWaitAdding =>
      'Poczekaj, aż zapisy zostaną dodane, i spróbuj ponownie.';

  @override
  String get retryRecordingsAddedMeanwhile =>
      'W międzyczasie dodano zapisy. Ponów odczyt zapisów jeszcze raz.';

  @override
  String get retryRecordingsNone =>
      'Nie udało się otworzyć żadnego zapisu dnia, więc dzień pozostaje bez zmian.';

  @override
  String retryRecordingsFailed(String reason) {
    return 'Nie udało się ponownie otworzyć dnia: $reason';
  }

  @override
  String get retryRecordingsChangedMeanwhile =>
      'W międzyczasie zmieniono dzień. Zapisz go i ponów odczyt zapisów danych.';

  @override
  String get lapsCompareTwo => 'Porównaj dwa okrążenia';

  @override
  String get lapsLastComparison => 'Ostatnie porównanie';

  @override
  String get taskStopped => 'Praca została przerwana.';

  @override
  String get taskStoppedUnexpectedly => 'Praca nieoczekiwanie się przerwała.';

  @override
  String get lapPageChannels => 'Kanały';

  @override
  String get lapPageCursorHintTouch =>
      'Stuknij wykres lub przeciągnij po nim w bok, aby przesunąć kursor; biała kropka pokazuje go na mapie. Dwoma palcami powiększasz i przesuwasz mapę.';

  @override
  String get lapPageCursorHint =>
      'Przeciągnij po wykresie, aby przesunąć kursor; biała kropka pokazuje go na mapie.';

  @override
  String get lapPageNoChannel => 'Nie pokazano żadnego kanału.';

  @override
  String get lapPageBestOfDay => 'Najlepsze okrążenie dnia';

  @override
  String lapPageBestOfSession(String session) {
    return 'Najlepsze okrążenie – $session';
  }

  @override
  String lapPageNotRankedExcluded(String reason) {
    return 'Niesklasyfikowane: wykluczone („$reason”)';
  }

  @override
  String get lapPageExclude => 'Wyklucz z rankingu…';

  @override
  String get lapPageInclude => 'Przywróć do rankingu';

  @override
  String get lapPageCompareWith => 'Porównaj z…';

  @override
  String get lapPageNoGps => 'Brak zapisu GPS dla tego odcinka.';

  @override
  String lapPageTraceLabel(String lap) {
    return 'Ślad: $lap, w kolorach prędkości';
  }

  @override
  String get lapPageSpeed => 'Prędkość';

  @override
  String lapPageShowBest(String lap) {
    return 'Pokaż najlepsze okrążenie ($lap) na szaro';
  }

  @override
  String get lapPageExcludeTitle => 'Wyklucz to okrążenie';

  @override
  String get lapPageReason => 'Powód';

  @override
  String get lapPageReasonHint => 'Ruch na torze, żółta flaga…';

  @override
  String get lapPageExcludeAction => 'Wyklucz';

  @override
  String get compareTitle => 'Porównanie okrążeń';

  @override
  String get compareLayerNotRecordedEither =>
      'Nie zapisano na żadnym okrążeniu.';

  @override
  String compareLayerNotRecordedOn(String lap) {
    return 'Nie zapisano na okrążeniu $lap.';
  }

  @override
  String compareLayerNoSamples(String lap) {
    return 'Brak użytecznych próbek na okrążeniu $lap.';
  }

  @override
  String get compareNoSharedPosition =>
      'Ta para okrążeń nie ma wspólnej pozycji na torze.';

  @override
  String compareLapDelta(String delta) {
    return 'Różnica czasu okrążenia: $delta';
  }

  @override
  String get compareDeltaExplained =>
      'Δ to różnica czasu A − B. Wartość dodatnia oznacza stratę A względem B; ujemna — przewagę A.';

  @override
  String get compareSwap => 'Zamień A i B';

  @override
  String compareBestOfSessionAsB(String session) {
    return 'B: najlepsze okrążenie – $session';
  }

  @override
  String get compareBestOfDayAsB => 'B: najlepsze okrążenie dnia';

  @override
  String get compareLayerLine => 'Tor jazdy: A / B';

  @override
  String compareLayerOptionNotRecorded(String layer) {
    return '$layer · nie zapisano';
  }

  @override
  String get compareLayerSpeed => 'Prędkość';

  @override
  String get compareLayerDelta => 'Δ czasu (A−B)';

  @override
  String get compareLayerLateralG => 'Przeciążenie poprzeczne';

  @override
  String get compareLayerLongitudinalG => 'Przeciążenie wzdłużne';

  @override
  String get compareLayerThrottle => 'Gaz';

  @override
  String get compareLayerBrake => 'Hamulec (zmierzony)';

  @override
  String get compareLayerTemperature => 'Temperatura';

  @override
  String get compareLayerAAhead => 'A z przewagą nad B';

  @override
  String get compareLayerABehind => 'A ze stratą do B';

  @override
  String get compareLayerBraking => 'hamowanie';

  @override
  String get compareLayerAccelerating => 'przyspieszanie';

  @override
  String compareLegendLap(String layer, String lap) {
    return '$layer · okrążenie $lap';
  }

  @override
  String get compareLegendCalculated => 'obliczone';

  @override
  String get compareChannelsByPosition => 'Kanały według pozycji na torze';

  @override
  String get compareCursorHintTouch =>
      'Oba okrążenia w tym samym miejscu toru. Stuknij wykres lub przeciągnij po nim w bok, aby przesunąć kursor; kropki pokazują oba okrążenia na mapie, którą dwoma palcami powiększasz i przesuwasz.';

  @override
  String get compareCursorHint =>
      'Oba okrążenia w tym samym miejscu toru. Przeciągnij po wykresie, aby przesunąć kursor; kropki pokazują oba okrążenia na mapie.';

  @override
  String get compareDeltaChart => 'Δ czasu (A − B)';

  @override
  String get compareDeltaNote => '+ = A ze stratą do B';

  @override
  String compareOpenLapHere(String lap) {
    return 'Otwórz okrążenie $lap w tym miejscu';
  }

  @override
  String get compareDisclaimer =>
      'Zaobserwowane różnice między dwoma okrążeniami, nie instrukcje.';

  @override
  String get compareRecordingsUnavailable =>
      'Zapisy tych okrążeń są niedostępne.';

  @override
  String get compareNoGps => 'Brak danych GPS na tym odcinku';

  @override
  String get compareMapLabel => 'Okrążenia A i B na jednej mapie';

  @override
  String get chartReasonNotRecorded => 'nie zapisano';

  @override
  String get chartReasonInvalidRange => 'nieprawidłowy zakres';

  @override
  String get chartReasonUnreadable => 'nie udało się odczytać';

  @override
  String get chartNoDataInRange => 'brak danych w tym zakresie';

  @override
  String get chartNoData => 'Brak danych w tym zakresie';

  @override
  String chartNotAvailable(String reasons) {
    return 'Niedostępne · $reasons';
  }

  @override
  String get chartBrakingUp => 'Hamowanie na wykresie: w górę';

  @override
  String chartRemove(String channel) {
    return 'Usuń $channel';
  }

  @override
  String chartSemantics(String channel) {
    return 'Wykres: $channel';
  }

  @override
  String chartSemanticsRange(String line, String low, String high) {
    return '${line}od $low do $high';
  }

  @override
  String get chartZoomOut => 'Pomniejsz';

  @override
  String get chartZoomIn => 'Powiększ wokół kursora';

  @override
  String get chartWholeLap => 'Całe okrążenie';

  @override
  String chartAtMost(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Najwyżej $count wykresów',
      few: 'Najwyżej $count wykresy',
      one: 'Najwyżej 1 wykres',
    );
    return '$_temp0';
  }

  @override
  String get chartAddChannel => 'Dodaj kanał';

  @override
  String chartChangeChannel(String channel) {
    return 'Zmień $channel';
  }

  @override
  String chartRecordedAs(String channel) {
    return 'w zapisie: $channel';
  }

  @override
  String get channelNamesTitle => 'Nazwy kanałów';

  @override
  String get channelNamesHelp =>
      'Nadaj zapisanemu kanałowi nazwę, którą pokazuje aplikacja, np. Gaz dla accelerator_pos-obd. Zostaw pole puste, aby pokazać nazwę z zapisu. Pliki zapisów i zapisane dni zachowują oryginalne nazwy.';

  @override
  String get channelNamesNoDay =>
      'Otwórz dzień, aby zobaczyć tu wszystkie jego kanały. Poniżej są kanały, którym nadano nazwę lub które oznaczono gwiazdką.';

  @override
  String get channelNamesRecordedName => 'Nazwa z zapisu';

  @override
  String channelNamesShownAs(String name) {
    return 'Pokazywany jako $name';
  }

  @override
  String get channelNamesClear => 'Pokaż nazwę z zapisu';

  @override
  String get settingsChannelNamesHelp =>
      'Nazwy pokazywane dla zapisanych kanałów, np. Gaz zamiast accelerator_pos-obd, oraz gwiazdki, które ograniczają menu wykresów do używanych kanałów.';

  @override
  String get settingsChannelNamesOpen => 'Nazwij kanały';

  @override
  String get chartAllChannels => 'Wszystkie kanały…';

  @override
  String get chartChooseChannel => 'Wybierz kanał';

  @override
  String get channelNamesListedHelp =>
      'Oznacz gwiazdką kanały, których używasz najczęściej: menu wykresów pokażą wtedy tylko je, a pozostałe w pozycji Wszystkie kanały…';

  @override
  String get channelListedOn =>
      'Na liście w menu wykresów (dotknij, aby usunąć gwiazdkę)';

  @override
  String get channelListedOff => 'Oznacz gwiazdką, aby był w menu wykresów';

  @override
  String get channelListedClear => 'Usuń wszystkie gwiazdki';

  @override
  String get coastingTitle => 'Jazda bez gazu i hamulca';

  @override
  String get coastingBySegment => 'Według odcinków';

  @override
  String get coastingBySegmentLoading =>
      'Analiza jazdy bez gazu i hamulca dla poszczególnych odcinków będzie dostępna po obliczeniu podziału toru…';

  @override
  String get coastingBySegmentNeedsSegments =>
      'Analiza jazdy bez gazu i hamulca dla poszczególnych odcinków wymaga podziału toru w grupie tego okrążenia.';

  @override
  String get coastingEpisodes =>
      'Fragmenty jazdy bez gazu i hamulca · wybierz fragment, aby go zobaczyć';

  @override
  String coastingIntoLap(String seconds) {
    return '$seconds s od początku okrążenia';
  }

  @override
  String get drivingGgNoLongitudinal =>
      'Nie zarejestrowano przeciążenia wzdłużnego';

  @override
  String get drivingGgNoLateral =>
      'Nie zarejestrowano przeciążenia poprzecznego';

  @override
  String get drivingGgUnsupportedUnit =>
      'Nieobsługiwana jednostka przyspieszenia';

  @override
  String get drivingGgNoSamples => 'Brak próbek na tym odcinku';

  @override
  String get drivingNoCoverage => 'Nie obejmuje tego odcinka';

  @override
  String get drivingNotAvailable => 'Niedostępne';

  @override
  String get drivingMeasured => 'zmierzone';

  @override
  String get drivingCalculatedFromGps => 'obliczone z GPS';

  @override
  String get drivingInferred => 'wyznaczone pośrednio';

  @override
  String get drivingUnexpectedUnit => 'nieoczekiwana jednostka';

  @override
  String get drivingNotRecorded => 'nie zapisano';

  @override
  String get drivingPedalsUnknown =>
      'brak danych o użyciu pedału gazu i hamulca';

  @override
  String get drivingNoSpeed => 'brak prędkości';

  @override
  String get drivingBrakeMeasuredLateralGps =>
      'sygnał hamulca z pomiaru, przeciążenie poprzeczne obliczone z GPS';

  @override
  String drivingUnexpectedUnitChannel(String channel) {
    return '$channel ma nieoczekiwaną jednostkę';
  }

  @override
  String get drivingScaleUnknown => 'nieznana skala pedału';

  @override
  String drivingScaleUnknownChannel(String channel) {
    return 'nie wiadomo, w jakiej skali (0–1 czy %) jest $channel';
  }

  @override
  String get drivingNoBrakeChannel => 'brak kanału hamulca';

  @override
  String get drivingNoAcceleratorChannel => 'brak kanału gazu';

  @override
  String get drivingBrakeRecorded => 'zapisano pedał hamulca';

  @override
  String get drivingBrakingInferred =>
      'hamowanie wyznaczone pośrednio z przeciążenia wzdłużnego (brak kanału hamulca)';

  @override
  String get drivingAcceleratorRecorded => 'zapisano pedał gazu';

  @override
  String get drivingAcceleratingInferred =>
      'przyspieszanie wyznaczone pośrednio z przeciążenia wzdłużnego (brak kanału gazu)';

  @override
  String get drivingLateralMeasured => 'zmierzono przeciążenie poprzeczne';

  @override
  String get drivingLateralCalculated =>
      'przeciążenie poprzeczne obliczone przez rejestrator z danych GPS';

  @override
  String get drivingNoLateral => 'brak danych przeciążenia poprzecznego';

  @override
  String get drivingCoastingMeasured =>
      'Zmierzone: z zapisanych pedałów hamulca i gazu.';

  @override
  String get drivingCoastingInferred =>
      'Wyznaczone pośrednio z przeciążenia wzdłużnego: w zapisie brakuje kanału pedału hamulca lub gazu.';

  @override
  String get drivingCoastingNoPedals =>
      'Nie można określić: zapis nie zawiera ani kanałów pedału gazu i hamulca, ani przeciążenia wzdłużnego.';

  @override
  String get drivingCoastingNoSpeed =>
      'Nie da się określić: zapis nie ma prędkości.';

  @override
  String get drivingCoastingUnitMismatch =>
      'Nie da się określić: kanał pedału lub prędkości ma nieoczekiwaną jednostkę.';

  @override
  String get drivingCoastingUnavailable =>
      'Analiza jazdy bez gazu i hamulca jest niedostępna dla tego odcinka.';

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
      other: '$count fragmentach',
      one: '1 fragmencie',
    );
    return '$seconds s · $meters m w $_temp0 ($share % czasu okrążenia)';
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
      other: '$count fragmentach',
      one: '1 fragmencie',
    );
    return '$seconds s · $meters m w $_temp0 ($share % czasu wybranego odcinka)';
  }

  @override
  String get drivingCoastingNote =>
      'Jazda bez gazu i hamulca to ruch samochodu bez użycia pedału gazu ani hamulca. Sama w sobie nie jest błędem: odjęcie gazu może ustabilizować samochód albo wynikać z ruchu na torze.';

  @override
  String get drivingCoastingEpisodesHint =>
      'Dla każdego fragmentu podano miejsce jego początku na torze. Wybierz fragment, aby przesunąć tam kursor.';

  @override
  String drivingSelectedStretch(String meters) {
    return 'Wybrany odcinek · $meters m';
  }

  @override
  String get drivingWholeLap => 'Całe okrążenie';

  @override
  String get drivingGgCalculated => 'obliczone przez rejestrator z GPS';

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
    return 'Okrążenie $lap';
  }

  @override
  String drivingGgSemantics(String a, String b) {
    return 'Diagram G–G okrążeń A i B: maksymalne łączne przeciążenie $a i $b';
  }

  @override
  String get drivingPeakLateral => 'Maks. przeciążenie poprzeczne';

  @override
  String get drivingPeakBraking => 'Maks. hamowanie';

  @override
  String get drivingPeakAccelerating => 'Maks. przyspieszenie';

  @override
  String get drivingPeakCombined => 'Maks. łączne przeciążenie';

  @override
  String get drivingSamples => 'Próbki';

  @override
  String get drivingGgNote =>
      'Zaobserwowane przyspieszenia nie określają procentu wykorzystania dostępnej przyczepności. Okręgi co 0.5 g; kółko oznacza maksima każdego okrążenia.';

  @override
  String get drivingGgAccelerating => 'przyspieszanie';

  @override
  String get drivingGgBraking => 'hamowanie';

  @override
  String get drivingGgLeft => 'lewo';

  @override
  String get drivingGgRight => 'prawo';

  @override
  String drivingStripLabel(String lap) {
    return 'Okrążenie $lap wzdłuż toru';
  }

  @override
  String get drivingStripHint =>
      'Wskaż miejsce na pasku, aby przesunąć tam kursor';

  @override
  String get drivingStatesTitle => 'Stany jazdy';

  @override
  String get drivingBraking => 'Hamowanie';

  @override
  String get drivingTrailBraking => 'Hamowanie w zakręcie';

  @override
  String get drivingCornering => 'Jazda w zakręcie';

  @override
  String get drivingAccelerating => 'Przyspieszanie';

  @override
  String get drivingCoasting => 'Jazda bez gazu i hamulca';

  @override
  String get drivingStatesNote =>
      'Udziały obliczane są osobno dla każdego okrążenia, względem czasu przejazdu wybranego fragmentu. Stany mogą się nakładać: jeździe w zakręcie może towarzyszyć hamowanie, przyspieszanie lub jazda bez gazu i hamulca. Wskaż miejsce na pasku, aby przesunąć tam kursor. Dłuższe hamowanie w zakręcie nie jest samo w sobie lepsze ani bezpieczniejsze.';

  @override
  String get cornerDetailsReasonNotMeasured => 'nie zmierzono';

  @override
  String get cornerDetailsReasonNoBraking => 'nie wykryto hamowania';

  @override
  String get cornerDetailsReasonNoBrakeOrDeceleration =>
      'brak kanału hamulca i przeciążenia wzdłużnego';

  @override
  String get cornerDetailsReasonNoBrakeChannel => 'brak kanału hamulca';

  @override
  String get cornerDetailsReasonNoDecelerationChannel =>
      'brak kanału przeciążenia wzdłużnego';

  @override
  String get cornerDetailsReasonApproachClipped =>
      'analizowany dojazd do zakrętu jest ucięty na linii startu/mety';

  @override
  String get cornerDetailsReasonApproachInPreviousCorner =>
      'dojazd zaczyna się w poprzednim zakręcie';

  @override
  String get cornerDetailsReasonAlreadyBraking =>
      'hamowanie trwało już przed dojazdem';

  @override
  String get cornerDetailsReasonBrakingGap =>
      'luka w danych uniemożliwia prześledzenie całego hamowania';

  @override
  String get cornerDetailsReasonNoSamplesHere => 'brak próbek w tym miejscu';

  @override
  String get cornerDetailsReasonNoThrottleOrAcceleration =>
      'brak kanału gazu i przyspieszenia';

  @override
  String get cornerDetailsReasonNoLift =>
      'brak odjęcia gazu przed ponownym dodaniem gazu';

  @override
  String get cornerDetailsReasonNoPickup =>
      'nie wykryto ponownego dodania gazu';

  @override
  String get cornerDetailsReasonAfterGap => 'po luce w zapisie';

  @override
  String get cornerDetailsReasonCutAtLapEnd => 'ucięte na końcu okrążenia';

  @override
  String get cornerDetailsReasonNotCovered =>
      'okrążenie nie jest tu w pełni pokryte danymi';

  @override
  String get cornerDetailsReasonCrossesGate => 'przecina linię startu/mety';

  @override
  String get cornerDetailsReasonUnitNotSupported =>
      'nieobsługiwana jednostka kanału';

  @override
  String get cornerDetailsReasonUnitNotRecorded =>
      'jednostka kanału nie jest zapisana';

  @override
  String get cornerDetailsReasonScaleUnknown =>
      'nieznana skala pedału (0–1 czy %)';

  @override
  String get cornerDetailsReasonScaleInferred => 'pedał odczytany w skali 0–1';

  @override
  String get cornerDetailsReasonNoSpeedChannel => 'brak kanału prędkości';

  @override
  String get cornerDetailsReasonMixedProvenance =>
      'parametr wyznaczono różnymi metodami na A i B';

  @override
  String get cornerDetailsReasonSegmentsDiffer =>
      'odcinki różnią się między okrążeniami';

  @override
  String get cornerDetailsReasonDoubleApex =>
      'podwójny wierzchołek: brak jednego jednoznacznego punktu';

  @override
  String get cornerDetailsReasonFlatSpeed =>
      'brak jednoznacznego minimum prędkości (stała prędkość)';

  @override
  String get cornerDetailsReasonUnclearGeometry =>
      'geometria zakrętu jest zbyt niejednoznaczna do wyznaczenia punktu';

  @override
  String get cornerDetailsReasonInvalidInput =>
      'nie udało się zmierzyć zakrętu';

  @override
  String get cornerDetailsReasonBroadApex =>
      'wierzchołek obejmuje długi odcinek łuku';

  @override
  String get cornerDetailsReasonAtBoundary => 'na skraju zakrętu';

  @override
  String get cornerDetailsReasonNotACorner => 'to nie jest zakręt';

  @override
  String get cornerDetailsReasonSparseSamples => 'za mało próbek';

  @override
  String get cornerDetailsReasonSegmentNotFound =>
      'nie znaleziono odcinka na tym okrążeniu';

  @override
  String get cornerDetailsReasonNotRecorded => 'nie zapisano';

  @override
  String get cornerDetailsReasonNoValidSamples => 'brak poprawnych próbek';

  @override
  String get cornerDetailsReasonNoReference => 'brak okrążenia odniesienia';

  @override
  String get cornerDetailsReasonNotTimed => 'bez pomiaru czasu';

  @override
  String get cornerDetailsReasonNoApprovedSegments =>
      'brak zatwierdzonych odcinków';

  @override
  String get cornerDetailsReasonDrivingStateUnknown => 'stan jazdy nieznany';

  @override
  String get cornerDetailsReasonNotAvailable => 'niedostępne';

  @override
  String get cornerDetailsFromDeceleration =>
      'Wyznaczone pośrednio z przeciążenia przy hamowaniu';

  @override
  String get cornerDetailsFromDecelerationBrakeUnused =>
      'Wyznaczone pośrednio z przeciążenia przy hamowaniu: kanał hamulca nie pokazuje hamowania';

  @override
  String get cornerDetailsFromDecelerationBrakeScaleUnknown =>
      'Wyznaczone pośrednio z przeciążenia przy hamowaniu: nie wiadomo, w jakiej skali (0–1 czy %) jest kanał hamulca';

  @override
  String get cornerDetailsReasonBrakeChannelNotUsed =>
      'kanał hamulca nie pokazuje hamowania';

  @override
  String get cornerDetailsFromBrakeChannel => 'Z kanału hamulca';

  @override
  String get cornerDetailsFromAcceleration =>
      'Wyznaczone pośrednio z przyspieszenia';

  @override
  String get cornerDetailsFromThrottleChannel => 'Z kanału gazu';

  @override
  String cornerDetailsBestMeasuredDifferently(String how) {
    return '$how; na najlepszym okrążeniu parametr wyznaczono inną metodą';
  }

  @override
  String get cornerDetailsBestSpeedDifferent =>
      'Prędkość najlepszego okrążenia zapisano inaczej';

  @override
  String cornerDetailsMinimumMissing(String reason) {
    return 'Prędkość minimalna: $reason';
  }

  @override
  String get cornerDetailsHighestMinimumSpeed => 'Najwyższa prędkość minimalna';

  @override
  String get cornerDetailsHighestExitSpeed => 'Najwyższa prędkość na wyjściu';

  @override
  String get cornerDetailsLatestBrakingPoint => 'Najpóźniejszy punkt hamowania';

  @override
  String get cornerDetailsEarliestPickup =>
      'Najwcześniejsze ponowne dodanie gazu';

  @override
  String cornerDetailsMetresIn(int metres) {
    return '$metres m od wejścia';
  }

  @override
  String cornerDetailsIsBestLap(String lap) {
    return '$lap · najlepsze okrążenie';
  }

  @override
  String cornerDetailsAgainstBestLap(String lap, String best) {
    return '$lap na tle najlepszego okrążenia, $best';
  }

  @override
  String get cornerDetailsBestLapUnavailable => 'niedostępne';

  @override
  String get cornerDetailsThisLap => 'To okrążenie';

  @override
  String get cornerDetailsBestLap => 'Najlepsze okrążenie';

  @override
  String cornerDetailsEntrySpeed(String unit) {
    return 'Prędkość na wejściu$unit';
  }

  @override
  String cornerDetailsMinimumSpeed(String unit) {
    return 'Prędkość minimalna$unit';
  }

  @override
  String cornerDetailsExitSpeed(String unit) {
    return 'Prędkość na wyjściu$unit';
  }

  @override
  String get cornerDetailsBrakingPoint =>
      'Punkt rozpoczęcia hamowania (przed zakrętem)';

  @override
  String get cornerDetailsBrakingTime => 'Czas hamowania';

  @override
  String cornerDetailsPeakDeceleration(String unit) {
    return 'Maksymalne hamowanie$unit';
  }

  @override
  String get cornerDetailsPickup => 'Punkt ponownego dodania gazu (w zakręcie)';

  @override
  String cornerDetailsBestOfLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Najlepsze z $count okrążeń',
      few: 'Najlepsze z $count okrążeń',
      one: 'Najlepsze z 1 okrążenia',
    );
    return '$_temp0';
  }

  @override
  String get cornerDetailsExplanation =>
      'Punkt rozpoczęcia hamowania i punkt ponownego dodania gazu określają odległości od początku zakrętu na wspólnej osi odniesienia wzdłuż toru. Późniejsze hamowanie lub wcześniejsze dodanie gazu nie oznaczają automatycznie szybszego przejazdu. Okrążenia, na których parametry wyznaczono różnymi metodami, nie są porównywane.';

  @override
  String cornerDetailsNotMeasured(String corner) {
    return '$corner: tego okrążenia tu nie zmierzono.';
  }

  @override
  String get cornerAnalyzerTypeCorner => 'zakręt';

  @override
  String get cornerAnalyzerTypeStraight => 'prosta';

  @override
  String get cornerAnalyzerTypeSector => 'sektor';

  @override
  String cornerAnalyzerNoteProposed(String lap) {
    return 'Odcinki zaproponowano na podstawie: $lap. Są też używane do obliczania teoretycznego czasu okrążenia; zapisanie dnia je zatwierdza. Granice określa się jako odległości wzdłuż osi odniesienia tego okrążenia, dlatego na porównywanych okrążeniach mogą przesunąć się o kilka metrów.';
  }

  @override
  String cornerAnalyzerNoteApproved(String session) {
    return 'Odcinki zatwierdzono dla: $session. Są też używane do obliczania teoretycznego czasu okrążenia. Granice określa się jako odległości wzdłuż osi odniesienia tej sesji, dlatego na porównywanych okrążeniach mogą przesunąć się o kilka metrów.';
  }

  @override
  String get cornerAnalyzerSummarySame => 'A i B mają tu ten sam czas.';

  @override
  String cornerAnalyzerSummaryFaster(String lap, String time) {
    return '$lap jest tu szybsze o $time.';
  }

  @override
  String cornerAnalyzerSummaryEntry(String lap, String time, String speed) {
    return '$lap jest tu szybsze o $time i ma o $speed wyższą prędkość na wejściu.';
  }

  @override
  String cornerAnalyzerSummaryMinimum(String lap, String time, String speed) {
    return '$lap jest tu szybsze o $time i ma o $speed wyższą prędkość minimalną.';
  }

  @override
  String cornerAnalyzerSummaryLowest(String lap, String time, String speed) {
    return '$lap jest tu szybsze o $time i ma o $speed wyższą najniższą prędkość.';
  }

  @override
  String cornerAnalyzerSummaryExit(String lap, String time, String speed) {
    return '$lap jest tu szybsze o $time i ma o $speed wyższą prędkość na wyjściu.';
  }

  @override
  String get cornerAnalyzerTitle => 'Analizator zakrętów';

  @override
  String get cornerAnalyzerEmpty =>
      'Te dwa okrążenia nie mają wspólnych zatwierdzonych odcinków. Zatwierdź ten sam podział toru na obu, aby użyć Analizatora zakrętów.';

  @override
  String get cornerAnalyzerUseTheoreticalBest =>
      'Użyj odcinków z obliczenia teoretycznego czasu okrążenia';

  @override
  String get cornerAnalyzerPrevious => 'Poprzedni odcinek';

  @override
  String get cornerAnalyzerNext => 'Następny odcinek';

  @override
  String get cornerAnalyzerNoChart =>
      'Brak wykresu prędkości: ten odcinek przecina linię startu/mety.';

  @override
  String get cornerAnalyzerNoFigures => 'Brak danych dla tego odcinka.';

  @override
  String cornerAnalyzerHeartRateNote(String a, String b) {
    return 'Tętno: średnia w tym odcinku · A $a · B $b. Tylko zaobserwowane wartości.';
  }

  @override
  String cornerAnalyzerCoverage(int count, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count próbek',
      few: '$count próbki',
      one: '1 próbka',
    );
    return '$_temp0 · dane przez $percent% czasu odcinka';
  }

  @override
  String get cornerAnalyzerExplanation =>
      'Δ to A − B, w kolorze okrążenia, które jest szybsze lub ma wyższą prędkość. To zaobserwowane różnice, nie instrukcje.';

  @override
  String get cornerAnalyzerExplanationWithBraking =>
      'Δ to A − B, w kolorze okrążenia, które jest szybsze lub ma wyższą prędkość. Punkt rozpoczęcia hamowania i punkt ponownego dodania gazu określają odległości od wejścia w zakręt. Późniejsze hamowanie lub wcześniejsze dodanie gazu nie oznaczają automatycznie szybszego przejazdu. To zaobserwowane różnice, nie instrukcje.';

  @override
  String get cornerAnalyzerZoom => 'Przybliż odcinek';

  @override
  String cornerAnalyzerOpenLap(String lap) {
    return 'Okrążenie $lap w tym miejscu';
  }

  @override
  String get cornerAnalyzerGroupTime => 'Czas';

  @override
  String get cornerAnalyzerGroupBraking => 'Hamowanie';

  @override
  String get cornerAnalyzerGroupCorner => 'Zakręt';

  @override
  String get cornerAnalyzerGroupSpeed => 'Prędkość';

  @override
  String get cornerAnalyzerGroupExit => 'Wyjście';

  @override
  String get cornerAnalyzerGroupDriver => 'Kierowca';

  @override
  String get cornerAnalyzerTimeThroughCorner => 'Czas przejazdu zakrętu';

  @override
  String get cornerAnalyzerSectorTime => 'Czas sektora';

  @override
  String get cornerAnalyzerBrakingPoint =>
      'Punkt rozpoczęcia hamowania (przed wejściem w zakręt)';

  @override
  String get cornerAnalyzerBrakingTime => 'Czas hamowania';

  @override
  String get cornerAnalyzerPeakDeceleration => 'Maksymalne hamowanie';

  @override
  String get cornerAnalyzerEntrySpeed => 'Prędkość na wejściu';

  @override
  String get cornerAnalyzerApexSpeed => 'Prędkość na wierzchołku';

  @override
  String get cornerAnalyzerMinimumSpeed => 'Prędkość minimalna w zakręcie';

  @override
  String get cornerAnalyzerTopSpeed => 'Prędkość maksymalna';

  @override
  String get cornerAnalyzerLowestSpeed => 'Najniższa prędkość na odcinku';

  @override
  String get cornerAnalyzerExitSpeed => 'Prędkość na wyjściu';

  @override
  String get cornerAnalyzerPickup =>
      'Punkt ponownego dodania gazu (po wejściu w zakręt)';

  @override
  String get cornerAnalyzerHeartRate => 'Tętno';

  @override
  String get cornerAnalyzerAHigher => 'A: wyższa prędkość';

  @override
  String get cornerAnalyzerBHigher => 'B: wyższa prędkość';

  @override
  String get cornerAnalyzerAFaster => 'A szybsze';

  @override
  String get cornerAnalyzerBFaster => 'B szybsze';

  @override
  String get cornerAnalyzerABrakesEarlier => 'A hamuje wcześniej';

  @override
  String get cornerAnalyzerABrakesLater => 'A hamuje później';

  @override
  String get cornerAnalyzerALonger => 'A dłużej';

  @override
  String get cornerAnalyzerAShorter => 'A krócej';

  @override
  String get cornerAnalyzerAHarder => 'A mocniej';

  @override
  String get cornerAnalyzerASofter => 'A słabiej';

  @override
  String get cornerAnalyzerALater => 'A później';

  @override
  String get cornerAnalyzerAEarlier => 'A wcześniej';

  @override
  String get cornerAnalyzerSame => 'tak samo';

  @override
  String get cornerAnalyzerInferred => 'pośrednio';

  @override
  String cornerAnalyzerBothLaps(String reason) {
    return '$reason (oba okrążenia)';
  }

  @override
  String cornerAnalyzerNotCompared(String reason) {
    return 'Nie porównano: $reason';
  }

  @override
  String get cornerAnalyzerUnitNoteSpeed =>
      'Ten zapis nie podaje jednostki prędkości: wartości pokazano bez zmian, bez jednostki.';

  @override
  String get cornerAnalyzerUnitNoteDeceleration =>
      'Ten zapis nie podaje jednostki hamowania (przeciążenia wzdłużnego): wartości pokazano bez zmian, bez jednostki.';

  @override
  String get cornerAnalyzerUnitNoteBoth =>
      'Ten zapis nie podaje jednostek prędkości i hamowania (przeciążenia wzdłużnego): wartości pokazano bez zmian, bez jednostki.';

  @override
  String get cornerAnalyzerChartNoSpeed =>
      'Na żadnym okrążeniu nie zapisano prędkości: brak wykresu prędkości.';

  @override
  String cornerAnalyzerChartNoSamples(String segment) {
    return 'Żadne okrążenie nie ma próbek prędkości w odcinku $segment.';
  }

  @override
  String cornerAnalyzerChartTitle(String segment) {
    return 'Prędkość · $segment';
  }

  @override
  String cornerAnalyzerChartLabel(String segment) {
    return 'Wykres prędkości · $segment';
  }

  @override
  String cornerAnalyzerCursor(String offset) {
    return 'Kursor $offset m: ';
  }

  @override
  String get cornerAnalyzerEntry => 'Wejście';

  @override
  String get cornerAnalyzerExit => 'Wyjście';

  @override
  String get cornerAnalyzerStart => 'Początek';

  @override
  String get cornerAnalyzerEnd => 'Koniec';

  @override
  String get cornerAnalyzerSpeedAxis => 'prędkość';

  @override
  String get cornerAnalyzerApex => 'Wierzchołek';

  @override
  String get cornerAnalyzerAxisCorner =>
      'Odległość od wejścia w zakręt (m) · zacieniowano: zakręt';

  @override
  String get cornerAnalyzerAxisSegment =>
      'Odległość od początku odcinka (m) · zacieniowano: odcinek';

  @override
  String cornerAnalyzerAxisNoUnit(String axis) {
    return '$axis · zapis nie podaje jednostki prędkości';
  }

  @override
  String get cornerAnalyzerLegendBraking => 'Początek hamowania';

  @override
  String get cornerAnalyzerLegendPickup => 'Ponowne dodanie gazu';

  @override
  String get cornerAnalyzerLegendMinimum => 'Prędkość minimalna';

  @override
  String importPageLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return '$_temp0';
  }

  @override
  String get importPageNoGate =>
      'Brak okrążeń: zapis nie ma linii startu/mety.';

  @override
  String get importPageSeveralGates =>
      'Brak okrążeń: zapis ma więcej niż jedną linię startu/mety.';

  @override
  String get importPageInvalidGate =>
      'Brak okrążeń: linia startu/mety jest nieprawidłowa.';

  @override
  String get importPageNoGps =>
      'Brak okrążeń: zapis nie ma użytecznego sygnału GPS.';

  @override
  String get importPageTooFewPasses =>
      'Brak pełnych okrążeń: linię startu/mety przecięto zbyt mało razy.';

  @override
  String importPageImportFailed(String error) {
    return 'Import nie powiódł się: $error';
  }

  @override
  String importPageFolderTooMany(int count, int maximum) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Folder zawiera $count zapisów; importuj najwyżej $maximum naraz. Wybierz mniejszy folder.',
      few:
          'Folder zawiera $count zapisy; importuj najwyżej $maximum naraz. Wybierz mniejszy folder.',
      one:
          'Folder zawiera 1 zapis; importuj najwyżej $maximum naraz. Wybierz mniejszy folder.',
    );
    return '$_temp0';
  }

  @override
  String importPageTooMany(int count, int maximum) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'To $count zapisów; importuj najwyżej $maximum naraz.',
      few: 'To $count zapisy; importuj najwyżej $maximum naraz.',
      one: 'To 1 zapis; importuj najwyżej $maximum naraz.',
    );
    return '$_temp0';
  }

  @override
  String importPageStoppedAfter(int count) {
    return 'Przerwano po $count plikach i folderach; dalszych zapisów nie przeszukano.';
  }

  @override
  String importPageTooDeep(int count, int depth) {
    return 'Nie przeszukano folderów poniżej poziomu $depth: $count.';
  }

  @override
  String importPageLinksSkipped(int count) {
    return 'Pominięto łącza: $count.';
  }

  @override
  String importPageOtherFilesSkipped(int count) {
    return 'Pominięto inne pliki: $count; importowane są tylko zapisy VBO i RCZ.';
  }

  @override
  String importPageSameContent(String other) {
    return 'ta sama zawartość co $other; zaimportowano raz.';
  }

  @override
  String importPageSameDrive(String other) {
    return 'ten sam przejazd co $other; zachowano jako jego alternatywne źródło.';
  }

  @override
  String get importPageNoRecording =>
      'Nie udało się zaimportować żadnego zapisu.';

  @override
  String get importPageFailed => 'Import nie powiódł się.';

  @override
  String get importPageStoppedUnexpectedly =>
      'Import nieoczekiwanie się zatrzymał.';

  @override
  String get importPageNoFolder => 'Folder nie istnieje lub nie jest folderem.';

  @override
  String get importPageFolderLink =>
      'Wybierz sam folder, a nie łącze do niego.';

  @override
  String get importPageNoneFound => 'Nie znaleziono zapisów VBO ani RCZ.';

  @override
  String get importPageNoneFoundNoSubfolders =>
      'Nie znaleziono zapisów VBO ani RCZ (bez podfolderów).';

  @override
  String get importPageNothingToImport =>
      'Brak zapisów VBO ani RCZ do zaimportowania.';

  @override
  String get importPageFileNotFound => 'nie znaleziono; nie zaimportowano.';

  @override
  String get importPageMetadataFile =>
      'plik metadanych macOS, a nie zapis danych; nie zaimportowano.';

  @override
  String get importPageFileLink => 'łącze; pominięto.';

  @override
  String get importPageNotRecording =>
      'to nie jest zapis VBO ani RCZ; nie zaimportowano.';

  @override
  String importPageNotRestored(String error) {
    return 'Nie udało się przywrócić dnia: $error';
  }

  @override
  String importPageDiscardTitle(String day) {
    return 'Odrzucić zmiany w dniu $day?';
  }

  @override
  String get importPageDiscardBody =>
      'Niezapisane zmiany zostaną utracone. Pliki z danymi i zapisane dni pozostaną nietknięte.';

  @override
  String get importPageKeep => 'Zachowaj';

  @override
  String get importPageDiscard => 'Odrzuć';

  @override
  String importPageNotDiscarded(String error) {
    return 'Nie odrzucono: $error';
  }

  @override
  String importPageCannotOpenTitle(String day) {
    return 'Nie udało się otworzyć dnia $day';
  }

  @override
  String get importPageNoneUsable =>
      'Nie udało się użyć żadnego z jego zapisów:';

  @override
  String get importPageChooseFolderHint =>
      'Wybierz folder z zapisami, aby ich użyć, także gdy nie zostały przeniesione.';

  @override
  String get importPageImportingBehind =>
      'Importuję udostępnione zapisy. Wróć do ekranu Importuj sesje, aby je zobaczyć.';

  @override
  String get importPageOpenSavedTitle => 'Otwórz zapisany dzień';

  @override
  String get importPageAnotherFile => 'Inny plik…';

  @override
  String get importPageAnotherOpening =>
      'Otwierany jest inny dzień. Spróbuj ponownie, gdy się otworzy.';

  @override
  String importPageNotOpened(String error) {
    return 'Nie udało się otworzyć dnia: $error';
  }

  @override
  String get importPageTitle => 'Importuj sesje';

  @override
  String importPageUnsaved(String day, String time) {
    return '$day: niezapisane zmiany z $time.';
  }

  @override
  String get importPageRestore => 'Przywróć';

  @override
  String get importPageDiscardEllipsis => 'Odrzuć…';

  @override
  String get importPageIntroDrop =>
      'Wybierz zapis VBO lub RCZ każdej sesji, gdy jeździsz, albo folder z całym dniem, lub upuść je tutaj. Sesje z tej samej daty co dzień otwarty ostatnio, w ciągu ostatnich 24 godzin, są do niego dodawane.';

  @override
  String get importPageIntroFolder =>
      'Wybierz zapis VBO lub RCZ każdej sesji, gdy jeździsz, albo folder z całym dniem. Sesje z tej samej daty co dzień otwarty ostatnio, w ciągu ostatnich 24 godzin, są do niego dodawane.';

  @override
  String get importPageIntro =>
      'Wybierz zapis VBO lub RCZ każdej sesji, gdy jeździsz. Sesje z tej samej daty co dzień otwarty ostatnio, w ciągu ostatnich 24 godzin, są do niego dodawane.';

  @override
  String get importPageChooseRecordings => 'Importuj sesje…';

  @override
  String get importPageChooseFolder => 'Wybierz folder…';

  @override
  String get importPageOpening => 'Otwieranie…';

  @override
  String get importPageOpenSaved => 'Otwórz zapisany dzień…';

  @override
  String get importPageProgress => 'Importowanie zapisów telemetrii';

  @override
  String get importPageChooseAgain =>
      'Wybierz ponownie te same lub inne zapisy telemetrii.';

  @override
  String get importPageIncludeSubfolders => 'Uwzględnij podfoldery';

  @override
  String get importPageNotes => 'Uwagi do importu';

  @override
  String get importPageLooking => 'Wyszukiwanie zapisów telemetrii…';

  @override
  String importPagePreparing(int number, int total) {
    return 'Przygotowywanie zapisu $number z $total…';
  }

  @override
  String get importPageCancelled => 'Import anulowano. Nic nie zaimportowano.';

  @override
  String importPageSessionsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zaimportowano $count sesji',
      few: 'Zaimportowano $count sesje',
      one: 'Zaimportowano 1 sesję',
    );
    return '$_temp0';
  }

  @override
  String get importPageShowResults => 'Otwórz dzień';

  @override
  String importPageDayUnsaved(String time) {
    return 'Jeszcze niezapisany; zmiany zachowane z $time.';
  }

  @override
  String importPageDaySaved(String file) {
    return 'Zapisany jako $file.';
  }

  @override
  String get importPageDayNotKept => 'Niezapisany.';

  @override
  String get importPageOpeningDay => 'Otwieranie dnia…';

  @override
  String get importPageRecordingTypes => 'Pliki telemetrii VBO i RCZ';

  @override
  String get importPageImportThisFolder => 'Importuj ten folder';

  @override
  String get importPageChooseFile =>
      'Wybierz plik telemetrii VBO lub RaceChrono RCZ.';

  @override
  String get importPageNotRegularFile =>
      'Wybrany plik nie istnieje albo nie jest zwykłym plikiem.';

  @override
  String get importPageTooManyFiles =>
      'Za dużo plików w jednym imporcie; wybierz mniej.';

  @override
  String get importPagePathTooLong =>
      'Ścieżka do pliku z zapisem jest za długa.';

  @override
  String get importPageFileSize =>
      'Plik z zapisem jest pusty albo przekracza limit rozmiaru pliku.';

  @override
  String get importPageBatchBytes =>
      'Przekroczono limit rozmiaru importu; zaimportuj mniej zapisów.';

  @override
  String get importPageIdenticalContent =>
      'Plik o tej samej zawartości jest już w tym imporcie.';

  @override
  String get importPageSourceChanged =>
      'Zapis zmienił się podczas importu; spróbuj ponownie, gdy plik przestanie się zmieniać.';

  @override
  String get importPageInvalidTimeRange =>
      'Zapis ma nieprawidłowy zakres czasu.';

  @override
  String get importPageMismatchedChannels =>
      'W zapisie znaczniki czasu kanałów nie pasują do wartości.';

  @override
  String get importPageBatchSamples =>
      'Przekroczono limit liczby próbek w imporcie; zaimportuj mniej zapisów.';

  @override
  String get importPageGroupingLimit =>
      'Grupowanie zapisów przekracza limit importu.';

  @override
  String get segmentReviewOpen => 'Przejrzyj propozycje';

  @override
  String get segmentReviewTitle => 'Propozycje odcinków';

  @override
  String get segmentReviewUndo => 'Cofnij';

  @override
  String get segmentReviewRedo => 'Ponów';

  @override
  String get segmentReviewIntro =>
      'Odcinki są zatwierdzane automatycznie, więc ten przegląd jest opcjonalny. Odrzucone propozycje nie zostaną uwzględnione po wybraniu „Zatwierdź wszystkie”. Informacja o odrzuceniu jest zapisywana wraz z dniem.';

  @override
  String segmentReviewSummary(int count, String lap) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count propozycji z $lap',
      many: '$count propozycji z $lap',
      few: '$count propozycje z $lap',
      one: '1 propozycja z $lap',
    );
    return '$_temp0';
  }

  @override
  String get segmentReviewApproveAll => 'Zatwierdź wszystkie';

  @override
  String get segmentReviewRecompute => 'Przelicz';

  @override
  String segmentReviewApproved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zatwierdzono $count propozycji',
      many: 'Zatwierdzono $count propozycji',
      few: 'Zatwierdzono $count propozycje',
      one: 'Zatwierdzono 1 propozycję',
    );
    return '$_temp0';
  }

  @override
  String get segmentReviewNoneApproved =>
      'Nie udało się zatwierdzić żadnej propozycji.';

  @override
  String get segmentReviewReject => 'Odrzuć';

  @override
  String get segmentReviewRestore => 'Przywróć';

  @override
  String get segmentReviewStateProposed => 'Proponowana';

  @override
  String get segmentReviewStateApproved => 'Zatwierdzona';

  @override
  String get segmentReviewStateRejected => 'Odrzucona';

  @override
  String get segmentReviewStateSuperseded => 'Nachodzi na zatwierdzony odcinek';

  @override
  String get segmentReviewCorner => 'Zakręt';

  @override
  String get segmentReviewStraight => 'Prosta';

  @override
  String get segmentReviewSector => 'Sektor';

  @override
  String segmentReviewTurnLeft(String degrees) {
    return '$degrees° w lewo';
  }

  @override
  String segmentReviewTurnRight(String degrees) {
    return '$degrees° w prawo';
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
  String get segmentReviewCrossesLine => 'Przecina linię startu/mety';

  @override
  String segmentReviewStartUncertain(String reasons) {
    return 'Niepewny początek: $reasons';
  }

  @override
  String segmentReviewEndUncertain(String reasons) {
    return 'Niepewny koniec: $reasons';
  }

  @override
  String get segmentReviewConnectedCorners => 'Zakręty łączą się bez prostej';

  @override
  String get segmentReviewShortStraight => 'Krótka prosta';

  @override
  String get segmentReviewGpsGap => 'W pobliżu luki GPS na tym okrążeniu';

  @override
  String segmentReviewApex(String at, String tolerance) {
    return 'Geometryczny wierzchołek zakrętu: $at m ±$tolerance m';
  }

  @override
  String get segmentReviewApexMultiple =>
      'Kilka wierzchołków — sprawdź ręcznie';

  @override
  String get segmentReviewApexCrossesGate =>
      'Zakręt przecina bramkę pomiaru czasu';

  @override
  String get segmentReviewApexUnresolved => 'Nie wyznaczono wierzchołka';

  @override
  String get segmentReviewWaiting =>
      'Mierzenie czasu każdego okrążenia na jednej osi toru…';

  @override
  String get segmentReviewComputing => 'Wyszukiwanie zakrętów i prostych…';

  @override
  String get segmentReviewNoLap =>
      'Okrążenie, na którym mierzone są odcinki, jest niedostępne.';

  @override
  String get segmentReviewNoAxis =>
      'Ze śladu GPS tego okrążenia nie da się zbudować osi toru.';

  @override
  String get segmentReviewContinuousCorner =>
      'Brak automatycznej propozycji: ślad okrążenia wykazuje ciągłą zmianę kierunku, bez prostej między zakrętami.';

  @override
  String get segmentReviewNoCorners =>
      'Brak automatycznej propozycji: na tym okrążeniu nie wykryto zakrętu.';

  @override
  String segmentReviewTooMany(int count) {
    return 'Brak automatycznej propozycji: okrążenie podzieliłoby się na więcej niż $count odcinków.';
  }

  @override
  String get segmentReviewFailed => 'Nie udało się obliczyć propozycji.';

  @override
  String get segmentReviewSaving => 'Dzień jest zapisywany. Spróbuj za chwilę.';

  @override
  String get segmentReviewSegmentsUnavailable =>
      'Odcinki można zmieniać po obliczeniu teoretycznego czasu okrążenia.';

  @override
  String get segmentReviewNotReady => 'Propozycje nie są jeszcze gotowe.';

  @override
  String get segmentReviewNoLongerAvailable =>
      'Ta propozycja nie jest już dostępna.';

  @override
  String get segmentReviewNotOpen => 'Odrzucić można tylko otwarte propozycje.';

  @override
  String get segmentReviewNotStored => 'Nie można zapisać odrzucenia.';

  @override
  String get segmentReviewNothingToUndo => 'Nie ma czego cofnąć.';

  @override
  String get segmentReviewNothingToRedo => 'Nie ma czego ponowić.';

  @override
  String get segmentReviewHistoryCleared =>
      'Odcinki zmieniły się poza tym edytorem, więc historię zmian wyczyszczono.';

  @override
  String get segmentReviewUncertainOther => 'Niepewna granica';

  @override
  String recordingsKeptApart(String format) {
    return 'Plik $format jest zachowany obok i nie jest łączony';
  }

  @override
  String recordingsKeptApartUntilReopened(String format) {
    return 'Plik $format jest zachowany obok i nie jest łączony do ponownego otwarcia dnia';
  }

  @override
  String get recordingsCheckClock => 'Sprawdź zegar';

  @override
  String recordingsMakePrimary(String format) {
    return 'Ustaw $format jako główny';
  }

  @override
  String get recordingsDontCombine => 'Nie łącz';

  @override
  String recordingsChangingPrimary(String format) {
    return 'Wczytywanie $format jako zapisu tej sesji…';
  }

  @override
  String clockChecking(String primary, String alternative) {
    return 'Porównywanie zegarów $primary i $alternative…';
  }

  @override
  String get clockAligned => 'Zegary są zgrane.';

  @override
  String clockNotAligned(String reason) {
    return 'Nie da się zgrać zegarów: $reason.';
  }

  @override
  String clockMeasured(
    String primary,
    String alternative,
    String offset,
    String uncertainty,
  ) {
    return 'Zmierzono z przebiegów prędkości: czas $primary = czas $alternative $offset ± $uncertainty';
  }

  @override
  String clockDrift(String ppm) {
    return 'Dryf zegara: $ppm ppm';
  }

  @override
  String clockCorrelation(
    String correlation,
    String overlap,
    int used,
    int windows,
  ) {
    return 'Korelacja prędkości $correlation na $overlap wspólnego zapisu; zgodne odcinki: $used z $windows';
  }

  @override
  String clockDeclared(String offset) {
    return 'Różnica czasów rozpoczęcia zapisu podanych przez rejestratory: $offset';
  }

  @override
  String get clockNoDeclared =>
      'Co najmniej jeden rejestrator nie podaje czasu rozpoczęcia zapisu.';

  @override
  String get clockAccept => 'Akceptuj i połącz';

  @override
  String get clockRefuse => 'Odrzuć';

  @override
  String clockRefuseNote(String primary, String alternative) {
    return 'Odrzucenie zachowuje $alternative obok sesji bez łączenia; jej analiza korzysta wtedy tylko z $primary.';
  }

  @override
  String clockReopenNote(String alternative) {
    return 'Ta sesja korzysta z VBO i zachowuje RCZ, a plik dnia nie zapamiętuje odrzucenia dla takiej sesji: po ponownym otwarciu dnia $alternative zostanie znów dopasowany i połączony.';
  }

  @override
  String get recordingsClockFailed =>
      'Nie udało się porównać zegarów. Spróbuj ponownie.';

  @override
  String recordingsPrimaryMissing(String format) {
    return 'Pliku $format nie ma już tam, skąd go wczytano. Przywróć go tam, a potem ustaw jako główny.';
  }

  @override
  String recordingsPrimaryChanged(String format) {
    return 'Plik $format zmienił się od wczytania. Otwórz dzień ponownie, a potem ustaw go jako główny.';
  }

  @override
  String recordingsPrimaryFailed(String format) {
    return 'Nie udało się wczytać $format jako zapisu tej sesji.';
  }

  @override
  String get recordingsBusyFind =>
      'Poczekaj na zakończenie sprawdzania lub zmiany zapisów sesji, a potem znajdź pozostałe.';

  @override
  String get recordingsBusyRetry =>
      'Poczekaj na zakończenie sprawdzania lub zmiany zapisów sesji, a potem spróbuj ponownie.';

  @override
  String get recordingsBusyLeave =>
      'Poczekaj na zakończenie sprawdzania lub zmiany zapisów sesji.';

  @override
  String get recordingsUnsaved =>
      'Zapisz dzień przed zmianą głównego zapisu danych.';

  @override
  String get recordingsBusyAdd =>
      'Poczekaj na zakończenie sprawdzania lub zmiany zapisów sesji, a potem dodaj zapisy.';

  @override
  String get lapPageThisLap => 'To okrążenie';

  @override
  String lapPageGapToBest(String delta) {
    return 'Różnica względem najlepszego okrążenia dnia: $delta';
  }

  @override
  String get importPageBest => 'Najlepsze';

  @override
  String get mapBackgroundMenu => 'Tło mapy';

  @override
  String get mapBackgroundStreets => 'Ulice';

  @override
  String get mapBackgroundSatellite => 'Satelita';

  @override
  String get mapBackgroundApple => 'Apple Maps';

  @override
  String get mapBackgroundPlain => 'Bez tła';

  @override
  String get documentPickerDays => 'Dzień FlappedEar';

  @override
  String get documentPickerLookInFolder => 'Szukaj w tym folderze';

  @override
  String get speedLegendNoSpeed =>
      'Nie zapisano prędkości; ślad jest w jednym kolorze.';

  @override
  String get appErrorNotice =>
      'Coś poszło nie tak. Szczegóły są w Diagnostyce.';

  @override
  String get appErrorPart => 'Nie udało się wyświetlić tej części.';

  @override
  String get diagnosticsErrors => 'Błędy';

  @override
  String get diagnosticsNoErrors => 'Brak błędów od uruchomienia aplikacji.';

  @override
  String get diagnosticsCopyErrors => 'Kopiuj błędy';

  @override
  String get diagnosticsErrorsCopied =>
      'Skopiowano błędy. Wklej je do zgłoszenia błędu.';

  @override
  String diagnosticsErrorsDropped(int count) {
    return 'Wcześniejsze błędy, których nie zachowano: $count';
  }

  @override
  String importUnexpectedError(String error) {
    return 'Nieoczekiwany błąd podczas odczytu tego pliku: $error';
  }

  @override
  String noteUnexpectedError(String error) {
    return 'Nieoczekiwany błąd podczas analizy tej sesji: $error';
  }

  @override
  String diagnosticsErrorCount(int count) {
    return 'Liczba wystąpień: $count';
  }

  @override
  String get reviewImportTitle => 'Przejrzyj import';

  @override
  String get reviewImportIntro =>
      'Wybierz, co stanie się z każdym zapisem. Nic nie zostanie zaimportowane, dopóki nie potwierdzisz.';

  @override
  String get addAndReviewRecordings => 'Dodaj i przejrzyj zapisy…';

  @override
  String get reviewChoiceNewSession => 'Importuj jako nową sesję';

  @override
  String get reviewChoiceSkip => 'Pomiń ten plik';

  @override
  String reviewChoiceSameRunAs(String name) {
    return 'Ta sama sesja co $name';
  }

  @override
  String reviewRecordingSummary(String duration, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pełnego okrążenia',
      many: '$count pełnych okrążeń',
      few: '$count pełne okrążenia',
      one: '1 pełne okrążenie',
      zero: 'brak pełnych okrążeń',
    );
    return '$duration · $_temp0';
  }

  @override
  String reviewDuplicate(String name) {
    return 'Ta sama zawartość co $name; zaimportowano raz.';
  }

  @override
  String reviewFailed(String reason) {
    return 'Nie zaimportowano: $reason';
  }

  @override
  String get reviewAlreadyInDay => 'Już jest w tym dniu; pominięto.';

  @override
  String reviewPossibleSameRun(String name) {
    return 'Możliwe, że to ta sama sesja co $name: ślady GPS się zgadzają.';
  }

  @override
  String get reviewDestinationAppend => 'Dodaj do tego dnia';

  @override
  String get reviewDestinationNewDay => 'Zacznij nowy dzień';

  @override
  String get reviewNewDayNeedsSave => 'Zapisz ten dzień, zanim zaczniesz nowy.';

  @override
  String get reviewSameRunHint =>
      'Dwa eksporty tej samej sesji? Wybierz „Ta sama sesja co”. Okrążenia sesji pochodzą z pliku, który wskażesz; drugi plik zostaje przy niej jako zapis alternatywny.';

  @override
  String get reviewConfirmImport => 'Importuj';

  @override
  String get reviewConfirmAdd => 'Dodaj do dnia';

  @override
  String get reviewConfirmNewDay => 'Zacznij nowy dzień';

  @override
  String reviewSessionCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nowej sesji',
      many: '$count nowych sesji',
      few: '$count nowe sesje',
      one: '1 nowa sesja',
      zero: 'Brak nowej sesji',
    );
    return '$_temp0';
  }

  @override
  String get reviewProblemTarget =>
      'Plik należy do tej samej sesji co plik, który nie jest importowany jako osobna sesja.';

  @override
  String get reviewProblemTooMany =>
      'Sesja może mieć najwyżej jeden dodatkowy zapis.';

  @override
  String get reviewProblemNothing =>
      'Wybierz co najmniej jeden plik do importu.';

  @override
  String get reviewChoicesRefused =>
      'Tych wyborów nie można dodać, więc niczego nie dodano. Przejrzyj zapisy ponownie.';

  @override
  String get waitUntilRecordingsSaved =>
      'Poczekaj, aż zapisy zostaną dopasowane, a dzień zapisany.';

  @override
  String get reviewChanged =>
      'Zapisy zmieniły się po przeglądzie, więc niczego nie zaimportowano. Przejrzyj je ponownie.';

  @override
  String get reviewPreparing => 'Przygotowywanie przeglądu…';

  @override
  String get importBusy =>
      'Najpierw dokończ bieżący import. Niczego nie zaimportowano.';

  @override
  String coreVboOpenFailed(String detail) {
    return 'Nie można otworzyć pliku VBO: $detail';
  }

  @override
  String coreVboReadFailed(String detail) {
    return 'Nie można odczytać pliku VBO: $detail';
  }

  @override
  String coreVboUnreadable(String detail) {
    return 'Nie można odczytać pliku VBO: $detail';
  }

  @override
  String get coreVboNoData => 'Plik VBO nie ma wierszy w sekcji [data].';

  @override
  String get coreVboNoValidRows =>
      'Plik VBO nie zawiera prawidłowych wierszy danych ze znacznikiem czasu.';

  @override
  String get coreVboNoTimeColumn =>
      'Plik VBO nie ma kolumny czasu (time, timestamp ani utc_time), więc jego próbek nie da się umieścić w czasie.';

  @override
  String get coreVboFileSize =>
      'Plik VBO przekracza obsługiwany limit rozmiaru 128 MiB.';

  @override
  String get coreVboComplexity =>
      'Tekst pliku VBO przekracza obsługiwany limit złożoności.';

  @override
  String get coreVboTooManyValues =>
      'Plik VBO ma więcej wartości (wiersze × kolumny) niż obsługiwane 40 milionów.';

  @override
  String get coreVboLongLine =>
      'Plik VBO zawiera linię dłuższą niż obsługiwany limit 1 MiB.';

  @override
  String get coreVboTooManyLines => 'Plik VBO ma za dużo linii.';

  @override
  String get coreVboLongSectionName =>
      'Plik VBO zawiera nazwę sekcji dłuższą niż obsługiwane 256 znaków.';

  @override
  String get coreVboTooManyRows => 'Plik VBO ma za dużo wierszy danych.';

  @override
  String get coreVboHeaderSize =>
      'Metadane nagłówka pliku VBO przekraczają obsługiwany rozmiar.';

  @override
  String get coreVboTooManyColumns => 'Plik VBO ma za dużo kolumn.';

  @override
  String get coreVboLongField =>
      'Plik VBO zawiera pole dłuższe niż obsługiwany limit 64 KiB.';

  @override
  String coreRczUnreadable(String detail) {
    return 'Nie można odczytać pliku RCZ: $detail';
  }

  @override
  String coreRczMissing(String name) {
    return 'W archiwum brakuje pliku $name.';
  }

  @override
  String coreRczMemberTooLarge(String name) {
    return 'Plik $name w archiwum przekracza swój limit rozmiaru.';
  }

  @override
  String get coreRczArchiveSize => 'Rozmiar archiwum nie jest obsługiwany.';

  @override
  String get coreRczZip64 =>
      'Archiwa ZIP64, dzielone lub przekraczające limity katalogu nie są obsługiwane.';

  @override
  String get coreRczSymlinks =>
      'Dowiązania symboliczne w archiwum nie są obsługiwane.';

  @override
  String get coreRczDuplicateMember =>
      'Powtórzony plik w archiwum albo przekroczony limit zasobów archiwum.';

  @override
  String get coreRczTruncated => 'Archiwum jest ucięte.';

  @override
  String get coreRczMetadataNesting =>
      'Przekroczono limit zagnieżdżenia lub długości tekstu w metadanych.';

  @override
  String get coreRczMetadataArray =>
      'Przekroczono limit długości listy w metadanych.';

  @override
  String get coreRczMetadataObject =>
      'Przekroczono limit liczby pól w metadanych.';

  @override
  String get coreRczMultiSession =>
      'Archiwa z kilkoma sesjami lub wznowione nie są obsługiwane; udostępnij jedną nieprzerwaną sesję.';

  @override
  String get coreRczSessionVersion => 'Ta wersja sesji nie jest obsługiwana.';

  @override
  String get coreRczResumed => 'Wznowione sesje nie są jeszcze obsługiwane.';

  @override
  String get coreRczMultiplePositions =>
      'Zapisy z kilkoma kanałami pozycji nie są obsługiwane.';

  @override
  String coreRczMultipleSources(String channel) {
    return 'Zapisy z kilkoma źródłami kanału $channel nie są obsługiwane.';
  }

  @override
  String get coreRczGpsMissing => 'Brakuje zadeklarowanych kanałów GPS.';

  @override
  String get coreRczTimestamps =>
      'Znaczniki czasu nie rosną monotonicznie albo wykraczają poza obsługiwaną 24-godzinną sesję.';

  @override
  String get coreRczChannelBudget =>
      'Przekroczono limit liczby kanałów lub próbek.';

  @override
  String get coreRczGapBudget => 'Przekroczono limit liczby przerw lub próbek.';

  @override
  String get coreRczTooManyGates => 'Za dużo bramek pomiaru czasu.';

  @override
  String get coreRczInvalidGate =>
      'Nieprawidłowe współrzędne lub kształt bramki pomiaru czasu.';

  @override
  String get coreRczInvalidGateEndpoint =>
      'Nieprawidłowy koniec bramki pomiaru czasu.';

  @override
  String get coreSourceIdentitySize =>
      'Plik z zapisem przekracza limit rozmiaru przy sprawdzaniu zawartości.';

  @override
  String get coreSourceCannotRead => 'Nie można odczytać zapisu.';

  @override
  String get coreSourceChangedWhileReading =>
      'Zapis zmienił się podczas odczytu; spróbuj ponownie, gdy plik przestanie się zmieniać.';

  @override
  String get coreSourceReadFailed =>
      'Odczyt zapisu nie powiódł się albo plik jest ucięty.';

  @override
  String get coreDayTooManyRecordings => 'Za dużo zapisów w tym dniu.';

  @override
  String get coreDayLapSectionLimit =>
      'Ten dzień przekracza limit 20 000 okrążeń (z wyjazdami i zjazdami).';

  @override
  String get coreRouteTooManyTraces =>
      'Za dużo śladów okrążeń do rozpoznania trasy.';

  @override
  String get coreRouteTooManyRuns =>
      'Za dużo sesji, by pogrupować je według trasy.';

  @override
  String get coreProgressionTooMany =>
      'Za dużo sesji lub okrążeń (z wyjazdami i zjazdami), by ocenić postęp.';

  @override
  String get coreRecordingTooManyLapSections =>
      'Za dużo okrążeń (z wyjazdami i zjazdami) w tym zapisie.';

  @override
  String get coreDayTooManyLapSections =>
      'Za dużo okrążeń (z wyjazdami i zjazdami) w tym dniu.';

  @override
  String get coreRankingTooMany =>
      'Za dużo okrążeń lub wykluczeń, by ułożyć ranking tego dnia.';

  @override
  String get coreTooManyPasses =>
      'Wykrywanie okrążeń znalazło za dużo przecięć linii startu/mety.';

  @override
  String get coreTooManyGpsPoints =>
      'Ślady okrążeń zawierają za dużo punktów GPS.';

  @override
  String get additionAlreadyInDay => 'już jest w tym dniu.';

  @override
  String additionSameDriveKept(String session) {
    return 'ten sam przejazd co $session w drugim formacie; zachowano jako jego alternatywne źródło.';
  }

  @override
  String additionSameDriveNotAdded(String session) {
    return 'ten sam przejazd co $session w drugim formacie; nie dodano ponownie.';
  }

  @override
  String progressionWeather(String weather) {
    return 'Pogoda: $weather';
  }

  @override
  String get weatherCredit => 'Dane pogodowe: Open-Meteo.com';

  @override
  String get weatherModelled =>
      'Model pogody dla okolicy toru w czasie sesji, nie pomiar na torze.';

  @override
  String weatherTemperature(String value) {
    return '$value °C';
  }

  @override
  String weatherTemperatureRange(String low, String high) {
    return '$low–$high °C';
  }

  @override
  String get weatherClear => 'bezchmurnie';

  @override
  String get weatherPartlyCloudy => 'częściowe zachmurzenie';

  @override
  String get weatherOvercast => 'pochmurno';

  @override
  String get weatherFog => 'mgła';

  @override
  String get weatherDrizzle => 'mżawka';

  @override
  String get weatherRain => 'deszcz';

  @override
  String get weatherSnow => 'śnieg';

  @override
  String get weatherShowers => 'przelotne opady';

  @override
  String get weatherThunderstorm => 'burza';

  @override
  String weatherPrecipitation(String amount) {
    return '$amount mm opadu';
  }

  @override
  String get weatherNoPrecipitation => 'bez opadów';

  @override
  String weatherWind(String direction, String speed) {
    return 'wiatr $direction $speed km/h';
  }

  @override
  String weatherWindNoDirection(String speed) {
    return 'wiatr $speed km/h';
  }

  @override
  String weatherGusts(String speed) {
    return 'porywy do $speed km/h';
  }

  @override
  String weatherHumidity(String value) {
    return 'wilgotność $value%';
  }

  @override
  String weatherCloudCover(String value) {
    return 'zachmurzenie $value%';
  }

  @override
  String weatherPressure(String value) {
    return 'ciśnienie $value hPa';
  }

  @override
  String weatherAirTemperature(String temperature) {
    return 'powietrze $temperature';
  }

  @override
  String weatherSky(String condition) {
    return 'niebo: $condition';
  }

  @override
  String get weatherFetching => 'Pobieranie pogody…';

  @override
  String get weatherOff => 'Pobieranie pogody jest wyłączone w ustawieniach.';

  @override
  String get weatherUnavailable =>
      'Niedostępna: brak połączenia z serwisem pogodowym albo brak danych dla tej sesji.';

  @override
  String get weatherNone =>
      'Niedostępna: zapis nie ma daty i godziny albo pozycji GPS.';

  @override
  String get weatherRetry => 'Spróbuj ponownie';

  @override
  String get sessionDetailsWeather => 'Pogoda';

  @override
  String get settingsWeatherHeading => 'Pogoda w sesjach';

  @override
  String get settingsWeatherSwitch => 'Pobieraj pogodę dla każdej sesji';

  @override
  String get settingsWeatherHelp =>
      'Wysyła do Open-Meteo.com pozycję sesji zaokrągloną do około 1 km i jej datę. Nic innego z Twoich zapisów nie opuszcza urządzenia.';

  @override
  String get weatherKept =>
      'Zachowana bez zmian: pogodę w tym dniu zapisała nowsza wersja aplikacji.';

  @override
  String get savedToLibrary => 'Zapisano w bibliotece.';

  @override
  String get savedToLibraryChangesPending =>
      'Zapisano w bibliotece. Zmiany wprowadzone w trakcie zapisu nie są jeszcze zapisane.';

  @override
  String get exportForOverlays => 'Eksportuj do Overlays…';

  @override
  String exportedAs(String file) {
    return 'Wyeksportowano jako $file.';
  }

  @override
  String get exportNotInLibrary =>
      'Nie wyeksportowano: wybierz miejsce poza biblioteką.';

  @override
  String replaceDayFileTitle(String file) {
    return 'Zastąpić $file?';
  }

  @override
  String get replaceDayFileBody =>
      'Plik o tej nazwie już jest w tym folderze. Zastąpienia nie można cofnąć.';

  @override
  String get replaceDayFile => 'Zastąp';

  @override
  String get notSavedInLibrary =>
      'Nie zapisano: wybierz miejsce poza biblioteką.';

  @override
  String notExported(String error) {
    return 'Nie wyeksportowano: $error';
  }

  @override
  String get importPageLibrary => 'Biblioteka';

  @override
  String get libraryTitle => 'Biblioteka';

  @override
  String get libraryUnavailable =>
      'Nie można teraz użyć biblioteki, na przykład dlatego, że utworzyła ją nowsza wersja aplikacji. Do tego czasu dni są zapisywane jako pliki.';

  @override
  String get libraryEmpty =>
      'Tutaj trafiają zaimportowane dni, według samochodu, roku i toru.';

  @override
  String get libraryRenameCar => 'Zmień nazwę samochodu';

  @override
  String get libraryRenameTrack => 'Zmień nazwę toru';

  @override
  String get libraryUndated => 'Bez daty';

  @override
  String get libraryUnknownTrack => 'Nie rozpoznano toru';

  @override
  String librarySessions(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sesji',
      many: '$count sesji',
      few: '$count sesje',
      one: '1 sesja',
    );
    return '$_temp0';
  }

  @override
  String libraryBestLap(String time) {
    return 'Najlepsze okrążenie $time';
  }

  @override
  String get libraryChangeCar => 'Zmień samochód';

  @override
  String libraryChooseCar(String day) {
    return 'Samochód dla: $day';
  }

  @override
  String get libraryNewCar => 'Nowy samochód…';

  @override
  String get libraryDefaultCar => 'Mój samochód';

  @override
  String libraryDefaultTrack(int number) {
    return 'Tor $number';
  }

  @override
  String lapsShowUnranked(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pokaż $count niesklasyfikowanych okrążeń',
      few: 'Pokaż $count niesklasyfikowane okrążenia',
      one: 'Pokaż 1 niesklasyfikowane okrążenie',
    );
    return '$_temp0';
  }

  @override
  String get lapsHideUnranked => 'Ukryj niesklasyfikowane okrążenia';

  @override
  String get navHome => 'Start';

  @override
  String get navLibrary => 'Biblioteka';

  @override
  String get navDay => 'Dzień';

  @override
  String get navCoach => 'Trener';

  @override
  String get navProfile => 'Profil';

  @override
  String get profileEmpty =>
      'Brak dni. Każdy zaimportowany dzień trafia do profilu, a jego sumy, rekordy i umiejętności pojawiają się tutaj.';

  @override
  String get profileTotals => 'Wszystkie dni';

  @override
  String get profileDays => 'Dni';

  @override
  String get profileSessions => 'Sesje';

  @override
  String get profileLaps => 'Okrążenia z czasem';

  @override
  String get profileDistance => 'Dystans';

  @override
  String get profileDrivingTime => 'Czas na torze';

  @override
  String get profileTracks => 'Tory';

  @override
  String get profileCars => 'Samochody';

  @override
  String profileMeasured(int measured, int sessions) {
    String _temp0 = intl.Intl.pluralLogic(
      sessions,
      locale: localeName,
      other: '$sessions sesji',
      one: '1 sesji',
    );
    return 'Dystans i czas obejmują $measured z $_temp0: dzień zapisany przed tą wersją doda je po ponownym otwarciu.';
  }

  @override
  String get profileSkills => 'Umiejętności';

  @override
  String get profileSkillsIntro =>
      'Każda umiejętność z ostatnich 3 dni, w których ją zmierzono, według stałych progów wyznaczonych przez to, co szybki, doświadczony kierowca powtarza okrążenie po okrążeniu: poziom 5 oznacza jazdę na limicie. Poziom 5 wymaga 15 sklasyfikowanych okrążeń, a poziom 4 – 5. Pewność wynika z liczby zmierzonych sklasyfikowanych okrążeń.';

  @override
  String skillName(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'liftTiming': 'Moment odpuszczenia gazu',
      'brakePointConsistency': 'Powtarzalność punktu hamowania',
      'brakeReleaseTiming': 'Moment zwalniania hamulca',
      'brakingEffectiveness': 'Skuteczność hamowania',
      'turnInConsistency': 'Powtarzalność wejścia w zakręt',
      'minimumSpeedControl': 'Kontrola prędkości minimalnej',
      'lineConsistency': 'Powtarzalność toru jazdy',
      'throttleReapplication': 'Ponowne otwieranie gazu',
      'throttleCommitment': 'Zdecydowanie na gazie',
      'exitSpeedExecution': 'Prędkość na wyjściu',
      'cornerSequenceManagement': 'Prowadzenie sekwencji zakrętów',
      'paceConsistency': 'Powtarzalność tempa',
      'other': '$id',
    });
    return '$_temp0';
  }

  @override
  String skillGroup(String group) {
    String _temp0 = intl.Intl.selectLogic(group, {
      'braking': 'Hamowanie',
      'corner': 'Zakręt',
      'exit': 'Wyjście',
      'lap': 'Okrążenie',
      'other': '$group',
    });
    return '$_temp0';
  }

  @override
  String skillMeasured(String id, String value) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'brakePointConsistency': 'Rozrzut punktu hamowania: $value',
      'minimumSpeedControl': 'Prędkość minimalna poniżej najlepszej: $value',
      'exitSpeedExecution': 'Prędkość na wyjściu poniżej najlepszej: $value',
      'paceConsistency': 'Rozrzut czasów okrążeń: $value',
      'liftTiming': 'Od odjęcia gazu do hamowania: $value',
      'brakeReleaseTiming': 'Rozrzut końca hamowania: $value',
      'brakingEffectiveness': 'Hamowanie słabsze od najlepszego: $value',
      'turnInConsistency': 'Rozrzut prędkości wejścia w zakręt: $value',
      'lineConsistency': 'Rozrzut toru jazdy w zakręcie: $value',
      'throttleReapplication': 'Rozrzut ponownego dodania gazu: $value',
      'throttleCommitment':
          'Gaz dodany i znów odjęty przed najwolniejszym punktem: $value przejazdów',
      'cornerSequenceManagement':
          'Strata tuż za zakrętem przy szybszych przejazdach: $value',
      'other': '$value',
    });
    return '$_temp0';
  }

  @override
  String skillLevel(int level) {
    return 'Poziom $level z 5';
  }

  @override
  String skillConfidence(String confidence) {
    String _temp0 = intl.Intl.selectLogic(confidence, {
      'low': 'Niska pewność',
      'medium': 'Średnia pewność',
      'high': 'Wysoka pewność',
      'other': '$confidence',
    });
    return '$_temp0';
  }

  @override
  String skillEvidence(int laps, int days) {
    String _temp0 = intl.Intl.pluralLogic(
      laps,
      locale: localeName,
      other: '$laps sklasyfikowanego okrążenia',
      many: '$laps sklasyfikowanych okrążeń',
      few: '$laps sklasyfikowane okrążenia',
      one: '1 sklasyfikowane okrążenie',
    );
    String _temp1 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dni',
      one: '1 dnia',
    );
    return '$_temp0 z $_temp1';
  }

  @override
  String skillTrend(String trend) {
    String _temp0 = intl.Intl.selectLogic(trend, {
      'improving': 'Poprawa',
      'steady': 'Bez zmian',
      'declining': 'Pogorszenie',
      'other': '$trend',
    });
    return '$_temp0';
  }

  @override
  String get skillNeedsEvidence => 'Potrzeba więcej danych';

  @override
  String get skillNotMeasured => 'Aplikacja jeszcze tego nie mierzy';

  @override
  String profileDrivenOn(int days, String distance, String time) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dni',
      one: '1 dzień',
    );
    return '$_temp0 · $distance · $time';
  }

  @override
  String profileVisits(int visits) {
    String _temp0 = intl.Intl.pluralLogic(
      visits,
      locale: localeName,
      other: '$visits wizyty',
      many: '$visits wizyt',
      few: '$visits wizyty',
      one: '1 wizyta',
    );
    return '$_temp0';
  }

  @override
  String profileBestLap(String time, String when) {
    return 'Najlepsze okrążenie: $time · $when';
  }

  @override
  String profileTheoreticalBest(String time, String when) {
    return 'Najlepszy teoretyczny czas okrążenia: $time · $when';
  }

  @override
  String profileTypicalLap(String time, String when) {
    return 'Najlepsze typowe okrążenie: $time · $when';
  }

  @override
  String profileFaster(String time) {
    return 'Ostatnia wizyta: najlepsze okrążenie o $time szybsze niż na poprzedniej';
  }

  @override
  String profileSlower(String time) {
    return 'Ostatnia wizyta: najlepsze okrążenie o $time wolniejsze niż na poprzedniej';
  }

  @override
  String get profileUndated => 'Bez daty';

  @override
  String get profileRepeated => 'Zakręty, które ciągle kosztują czas';

  @override
  String profileRepeatedLoss(String loss, int visits) {
    String _temp0 = intl.Intl.pluralLogic(
      visits,
      locale: localeName,
      other: '$visits wizytach',
      one: '1 wizycie',
    );
    return 'średnio $loss straty, na $_temp0';
  }

  @override
  String profileRepeatedState(String state) {
    String _temp0 = intl.Intl.selectLogic(state, {
      'active': 'Nadal kosztuje czas',
      'fading': 'Słabnie: niezmierzony na dwóch ostatnich wizytach',
      'fixed': 'Bez straty na dwóch ostatnich wizytach',
      'other': '$state',
    });
    return '$_temp0';
  }

  @override
  String get profileRepeatedNone =>
      'Żaden zakręt nie był jeszcze wśród najkosztowniejszych na dwóch wizytach.';

  @override
  String profileDrivenOnUnmeasured(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dni',
      one: '1 dzień',
    );
    return '$_temp0 · dystans i czas jeszcze niezmierzone';
  }

  @override
  String get profileTracksNone =>
      'W Twoich dniach nie rozpoznano jeszcze toru.';

  @override
  String get settingsLookHeading => 'Wygląd';

  @override
  String get lookDark => 'Ciemny';

  @override
  String get lookSunlight => 'Słoneczny';

  @override
  String get settingsLookHelp =>
      'Wygląd słoneczny: czarny tekst na białym tle i mocniejsze kolory, łatwiejsze do odczytania w ostrym słońcu.';

  @override
  String get settingsKeepScreenOnSwitch =>
      'Nie wygaszaj ekranu, gdy widoczny jest Trener';

  @override
  String get settingsKeepScreenOnHelp =>
      'Karta następnej sesji pozostaje czytelna między sesjami. W innych miejscach aplikacji i gdy nie jest ona na wierzchu, ekran wygasa jak zwykle.';

  @override
  String get lastTimeHereTitle => 'Ostatnio tutaj';

  @override
  String get lastTimeHereBestLap => 'Najlepsze okrążenie';

  @override
  String get lastTimeHereTheoreticalBest => 'Teoretyczny czas okrążenia';

  @override
  String get lastTimeHereNote =>
      'Dziś minus poprzednio: wartość ujemna to dziś szybciej. Warunki mogły być inne.';

  @override
  String get lastTimeHereMissing =>
      '— oznacza, że tego dnia nie ma takiego czasu: brak sklasyfikowanego okrążenia albo nie udało się wyznaczyć teoretycznego czasu okrążenia.';

  @override
  String get lastTimeHereOtherCar =>
      'Podano inny samochód, bo tym samochodem nie jeżdżono tu wcześniej.';

  @override
  String lastTimeHereThenToday(String then, String today) {
    return '$then poprzednio · $today dziś';
  }

  @override
  String get lastTimeHereCorners => 'Strata czasu na zakrętach';

  @override
  String get lastTimeHereCornersNote =>
      'Okrążenia każdego dnia porównane z najszybszym przejazdem tego dnia przez zakręt, uśrednione po jego sesjach: mniejszy czas oznacza równiejszy dzień w tym miejscu, a nie szybszy zakręt. Początek i koniec zakrętu mogą się nieco różnić między dniami. Pokazane są tylko zakręty zmierzone w oba dni.';

  @override
  String get lastTimeHereCornersNone =>
      'Strata czasu na zakrętach: żaden zakręt nie został zmierzony w oba dni.';

  @override
  String get lastTimeHereWeather => 'Pogoda';

  @override
  String lastTimeHereWeatherThen(String session, String weather) {
    return 'Poprzednio ($session): $weather';
  }

  @override
  String lastTimeHereWeatherToday(String session, String weather) {
    return 'Dziś ($session): $weather';
  }

  @override
  String lastTimeHereWeatherBestLapSession(String session) {
    return '$session, najlepsze okrążenie';
  }

  @override
  String lastTimeHereWeatherBestHadNone(String session) {
    return '$session; sesja z najlepszym okrążeniem nie ma pogody';
  }

  @override
  String lastTimeHereWeatherFirstSession(String session) {
    return '$session, pierwsza z pogodą';
  }

  @override
  String get lastTimeHereWeatherUnknownCondition =>
      'warunki nieznane tej wersji';

  @override
  String get lastTimeHereWeatherThenNone =>
      'Poprzednio: — brak danych pogodowych dla tamtego dnia: pobieranie pogody było wyłączone, jego zapisy nie mają czasu lub pozycji albo dzień dodano, zanim biblioteka zapisywała pogodę.';

  @override
  String get lastTimeHereWeatherTodayNone =>
      'Dziś: — biblioteka nie ma jeszcze dzisiejszej pogody.';

  @override
  String lastTimeHereWeatherTodayFetching(String session) {
    return 'Dziś ($session): pobieranie pogody…';
  }

  @override
  String lastTimeHereWeatherTodayOff(String session) {
    return 'Dziś ($session): — pobieranie pogody jest wyłączone w ustawieniach.';
  }

  @override
  String lastTimeHereWeatherTodayUnavailable(String session) {
    return 'Dziś ($session): — nie udało się połączyć z serwisem pogodowym albo nie miał danych.';
  }

  @override
  String lastTimeHereWeatherTodayNoPosition(String session) {
    return 'Dziś ($session): — brak danych pogodowych dla tej sesji: zapis nie ma czasu ani pozycji GPS.';
  }

  @override
  String lastTimeHereWeatherTodayPending(String session) {
    return 'Dziś ($session): — widoczna na tej stronie; trafi do biblioteki po zapisaniu dnia.';
  }

  @override
  String lastTimeHereWeatherTodayKept(String session) {
    return 'Dziś ($session): — zapisana przez nowszą wersję aplikacji i tu nieodczytywana.';
  }

  @override
  String get lastTimeHereWeatherNote =>
      'Pogoda każdego dnia to pogoda sesji z najlepszym okrążeniem, a gdy ta sesja nie ma pogody – pierwszej sesji, która ją ma.';

  @override
  String get lastTimeHereSetup => 'Ustawienia';

  @override
  String lastTimeHereSetupThen(String session, String setup) {
    return 'Poprzednio ($session): $setup';
  }

  @override
  String lastTimeHereSetupToday(String session, String setup) {
    return 'Dziś ($session): $setup';
  }

  @override
  String lastTimeHereSetupBestHadNone(String session) {
    return '$session; sesja z najlepszym okrążeniem nie ma ustawień';
  }

  @override
  String lastTimeHereSetupFirstSession(String session) {
    return '$session, pierwsza z ustawieniami';
  }

  @override
  String get lastTimeHereSetupThenNone =>
      'Poprzednio: — dla tamtego dnia nie wpisano ustawień albo dzień dodano, zanim biblioteka zaczęła zapisywać ustawienia.';

  @override
  String get lastTimeHereSetupTodayNoSessions =>
      'Dziś: — nie wpisano ustawień.';

  @override
  String lastTimeHereSetupThenMissing(String session, String reason) {
    return 'Poprzednio ($session): — $reason';
  }

  @override
  String lastTimeHereSetupTodayMissing(String session, String reason) {
    return 'Dziś ($session): — $reason';
  }

  @override
  String get lastTimeHereSetupReasonNone => 'nie wpisano ustawień';

  @override
  String get lastTimeHereSetupReasonNewer =>
      'ustawienia z innej wersji aplikacji';

  @override
  String get lastTimeHereSetupReasonUnreadable =>
      'ta wersja nie potrafi ich odczytać';

  @override
  String get lastTimeHereSetupReasonUnsaved =>
      'wpisane na tej stronie; trafią do biblioteki po zapisaniu dnia';

  @override
  String get lastTimeHereSetupReasonPending =>
      'zapisane razem z dniem; jeszcze nie ma ich w bibliotece';

  @override
  String lastTimeHereSetupDifference(String difference) {
    return 'Różnica (dziś − poprzednio): $difference';
  }

  @override
  String get lastTimeHereSetupUnits =>
      'Różne jednostki ciśnienia, bez porównania.';

  @override
  String get lastTimeHereSetupNote =>
      'Ustawienia każdego dnia to ustawienia sesji z najlepszym okrążeniem, a gdy ta sesja ich nie ma – pierwszej sesji, która je ma. Pokazane tak, jak je wpisano; wyższe lub niższe ciśnienie nie jest ani lepsze, ani gorsze.';

  @override
  String get settingsUpdatesHeading => 'Aktualizacje';

  @override
  String get settingsUpdateSwitch =>
      'Sprawdzaj przy uruchomieniu, czy jest nowa wersja';

  @override
  String get settingsUpdateHelp =>
      'Przy uruchomieniu, najwyżej raz dziennie, aplikacja pyta GitHub o swoje najnowsze wydanie i listę torów. Żadne Twoje zapisy ani ustawienia nie są wysyłane.';

  @override
  String get settingsUpdateCheckNow => 'Sprawdź aktualizacje';

  @override
  String get updateTitle => 'Aktualizacje aplikacji';

  @override
  String get updateChecking => 'Szukam nowszej wersji na GitHubie…';

  @override
  String get updateUpToDate => 'Masz najnowszą wersję.';

  @override
  String updateInstalledVersion(String version) {
    return 'Ta aplikacja: wersja $version';
  }

  @override
  String get updateVersionUnknown => 'nieznana';

  @override
  String updateAvailable(String newVersion, String installed) {
    return 'Dostępna jest wersja $newVersion. Masz $installed.';
  }

  @override
  String updateAvailableMessage(String newVersion) {
    return 'Dostępna jest wersja FlappedEar Telemetry $newVersion.';
  }

  @override
  String get updateDetails => 'Szczegóły';

  @override
  String get updateAndroidHelp =>
      'Aplikacja pobierze plik APK, sprawdzi go z sumami kontrolnymi wydania i otworzy instalator Androida. Zapisane dni pozostaną.';

  @override
  String get updateMacHelp =>
      'Aplikacja pobierze plik zip, sprawdzi go z sumami kontrolnymi wydania i pokaże go w Finderze. Otwórz go i przenieś FlappedEar Telemetry do Aplikacji, zastępując starą wersję. Przy pierwszym uruchomieniu macOS odmówi jak po pierwszej instalacji: zezwól w ten sam sposób.';

  @override
  String get updateNoDownloadHere =>
      'Wydanie nie zawiera pliku dla tego urządzenia. Jego strona na GitHubie opisuje zmiany.';

  @override
  String get updateDownloadInstall => 'Pobierz i zainstaluj';

  @override
  String get updateDownload => 'Pobierz';

  @override
  String get updateWhatsNew => 'Co nowego';

  @override
  String get updateOpenReleases => 'Strona wydań';

  @override
  String updateDownloading(String newVersion, int percent) {
    return 'Pobieranie wersji $newVersion: $percent %';
  }

  @override
  String get updateNeedsPermission =>
      'Android prosi o zgodę na instalowanie aplikacji przez FlappedEar Telemetry. Włącz ją w otwartych ustawieniach, wróć i dotknij Dalej. Jeśli aplikacja uruchomiła się od nowa, otwórz Ustawienia i dotknij Sprawdź aktualizacje.';

  @override
  String get updateContinue => 'Dalej';

  @override
  String get updateInstallAgain => 'Otwórz instalator ponownie';

  @override
  String get updateInstalling =>
      'Pobrano i sprawdzono. Instalator Androida jest otwarty: potwierdź w nim aktualizację.';

  @override
  String updateSaved(String path) {
    return 'Pobrano i sprawdzono: $path. Otwórz plik i przenieś FlappedEar Telemetry do Aplikacji, zastępując starą wersję. Przy pierwszym uruchomieniu macOS odmówi jak po pierwszej instalacji: zezwól w ten sam sposób.';
  }

  @override
  String get updateShowInFinder => 'Pokaż w Finderze';

  @override
  String get updateFailedOffline =>
      'Nie udało się połączyć z GitHubem. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get updateFailedRateLimited =>
      'GitHub pozwala na kilka sprawdzeń na godzinę z jednej sieci. Spróbuj później.';

  @override
  String get updateFailedNotVerifiable =>
      'Wydanie nie podaje sumy kontrolnej tego pliku, więc go nie zachowano.';

  @override
  String get updateFailedChecksum =>
      'Pobrany plik nie zgadza się z sumą kontrolną wydania i został usunięty. Spróbuj ponownie.';

  @override
  String get updateFailedNotSaved =>
      'Nie udało się zapisać pliku. Spróbuj ponownie albo, na komputerze, wybierz inny folder.';

  @override
  String get updateFailedUnexpected =>
      'Aktualizacja się nie udała. Spróbuj ponownie albo otwórz stronę wydań.';

  @override
  String get updateTryAgain => 'Spróbuj ponownie';

  @override
  String get libraryExport => 'Eksportuj profil';

  @override
  String get libraryImport => 'Importuj profil';

  @override
  String libraryExportFileName(String date) {
    return 'Profil kierowcy $date';
  }

  @override
  String get libraryExporting => 'Zapisywanie pliku profilu…';

  @override
  String get libraryImporting => 'Dodawanie dni z pliku…';

  @override
  String libraryExported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Wyeksportowano profil z $count dniami.',
      one: 'Wyeksportowano profil z 1 dniem.',
    );
    return '$_temp0';
  }

  @override
  String libraryExportMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count zapisów nie zostało znalezionych na tym urządzeniu, więc nie ma ich w pliku.',
      few:
          '$count zapisy nie zostały znalezione na tym urządzeniu, więc nie ma ich w pliku.',
      one: 'Nie znaleziono 1 zapisu na tym urządzeniu, więc nie ma go w pliku.',
    );
    return '$_temp0';
  }

  @override
  String libraryExportReferencesMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count zapisów odniesienia nie zostało znalezionych w profilu, więc nie ma ich w pliku.',
      few:
          '$count zapisy odniesienia nie zostały znalezione w profilu, więc nie ma ich w pliku.',
      one: 'Nie znaleziono 1 zapisu odniesienia w profilu, więc nie ma go w pliku.',
    );
    return '$_temp0';
  }

  @override
  String get libraryExportFailed => 'Nie udało się wyeksportować profilu.';

  @override
  String libraryImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Dodano $count dni.',
      one: 'Dodano 1 dzień.',
      zero: 'W pliku nie ma dni, których tu jeszcze nie ma.',
    );
    return '$_temp0';
  }

  @override
  String libraryImportNotAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Nie dodano $count dni: brak ich w pliku albo biblioteka jest pełna.',
      one: 'Nie dodano 1 dnia: brak go w pliku albo biblioteka jest pełna.',
    );
    return '$_temp0';
  }

  @override
  String get libraryImportFailed =>
      'Nie można zaimportować tego pliku. To nie jest profil wyeksportowany z tej aplikacji, pochodzi z nowszej wersji albo jest uszkodzony.';

  @override
  String get profileBundleType => 'Profile kierowcy';

  @override
  String libraryExportDaysMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Nie znaleziono $count dni na tym urządzeniu, więc nie ma ich w pliku.',
      one: 'Nie znaleziono 1 dnia na tym urządzeniu, więc nie ma go w pliku.',
    );
    return '$_temp0';
  }

  @override
  String libraryImportNotSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Skopiowano $count dni, ale nie udało się zapisać biblioteki. Pojawią się w niej ponownie, w ostatnim samochodzie, przy następnym uruchomieniu aplikacji.',
      one: 'Skopiowano 1 dzień, ale nie udało się zapisać biblioteki. Pojawi się w niej ponownie, w ostatnim samochodzie, przy następnym uruchomieniu aplikacji.',
    );
    return '$_temp0';
  }

  @override
  String get sessionSetupHeading => 'Ustawienia';

  @override
  String get sessionSetupPressures => 'Ciśnienie w oponach';

  @override
  String get pressureUnitBar => 'bar';

  @override
  String get pressureUnitPsi => 'psi';

  @override
  String get setupWheelFl => 'LP';

  @override
  String get setupWheelFr => 'PP';

  @override
  String get setupWheelRl => 'LT';

  @override
  String get setupWheelRr => 'PT';

  @override
  String get setupWheelFlName => 'lewe przednie';

  @override
  String get setupWheelFrName => 'prawe przednie';

  @override
  String get setupWheelRlName => 'lewe tylne';

  @override
  String get setupWheelRrName => 'prawe tylne';

  @override
  String get sessionSetupCold => 'Na zimno';

  @override
  String get sessionSetupHot => 'Na ciepło';

  @override
  String sessionSetupPressureField(String row, String wheel) {
    return '$row, $wheel';
  }

  @override
  String sessionSetupPressureRange(String unit, String min, String max) {
    return 'Ciśnienie ($unit): od $min do $max, najwyżej dwie cyfry po kropce.';
  }

  @override
  String get sessionSetupKeptAsEntered =>
      'Zapisane tak, jak wpisano: zmiana jednostki nie przelicza liczb.';

  @override
  String get sessionSetupTyre => 'Opony';

  @override
  String get sessionSetupTyreHint => 'Pirelli SC2';

  @override
  String get sessionSetupFuel => 'Paliwo na starcie (l)';

  @override
  String get sessionSetupFuelRange => '0–200 l, najwyżej dwie cyfry po kropce';

  @override
  String sessionSetupSameAs(String session) {
    return 'Skopiuj z: $session';
  }

  @override
  String get sessionSetupReadOnly =>
      'Zapisane przez nowszą wersję aplikacji: pokazane bez zmian i nie do edycji tutaj.';

  @override
  String setupCold(String pressures, String unit) {
    return 'Na zimno $pressures $unit';
  }

  @override
  String setupHot(String pressures, String unit) {
    return 'Na ciepło $pressures $unit';
  }

  @override
  String setupTyres(String tyre) {
    return 'Opony $tyre';
  }

  @override
  String setupFuel(String litres) {
    return 'Paliwo $litres l';
  }

  @override
  String sessionSetupLine(String setup) {
    return 'Ustawienia: $setup';
  }

  @override
  String get sessionSetupReplaceTitle => 'Zastąpić ustawienia?';

  @override
  String sessionSetupReplaceBody(String session) {
    return 'Pola ustawień zostaną wypełnione ustawieniami z: $session zamiast obecnych wartości. Nic nie jest zapisywane przed naciśnięciem Zapisz.';
  }

  @override
  String get sessionSetupReplace => 'Zastąp';

  @override
  String get libraryMeasureAgain => 'Przelicz ponownie wszystkie dni';

  @override
  String get libraryStopMeasuring => 'Zatrzymaj';

  @override
  String libraryMeasuring(int done, int total) {
    return 'Ponowne przeliczanie dni: $done z $total…';
  }

  @override
  String libraryMeasured(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Przeliczono ponownie $count dni.',
      one: 'Przeliczono ponownie 1 dzień.',
    );
    return '$_temp0';
  }

  @override
  String libraryMeasureFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Nie udało się przeliczyć $count dni: brakuje pliku lub nagrania albo nie da się go odczytać. Zostają poprzednie pomiary.',
      one: 'Nie udało się przeliczyć 1 dnia: brakuje jego pliku lub jednego z nagrań albo nie da się go odczytać. Zostają poprzednie pomiary.',
    );
    return '$_temp0';
  }

  @override
  String trackDialogCircuit(String name) {
    return 'Tor: $name';
  }

  @override
  String get trackDialogCircuitUnknown =>
      'Tego miejsca nie ma na liście torów.';

  @override
  String get trackDialogNameCircuit => 'Nazwij ten tor…';

  @override
  String get circuitNameTitle => 'Nazwa toru';

  @override
  String get circuitNameHelp =>
      'Pokazywana dla każdego dnia na tym torze. Zapisana na tym urządzeniu.';

  @override
  String get settingsCircuitsHeading => 'Tory';

  @override
  String settingsCircuitsCount(int count) {
    return 'Torów na liście: $count';
  }

  @override
  String get settingsCircuitsHelp =>
      'Tor jest rozpoznawany po miejscu, w którym zaczyna się trasa. Lista pochodzi z Wikidanych (CC0) i jest aktualizowana razem ze sprawdzaniem aktualizacji aplikacji.';

  @override
  String get settingsCircuitsUpdate => 'Zaktualizuj listę torów';

  @override
  String get settingsCircuitsUpdated => 'Lista torów została zaktualizowana.';

  @override
  String get settingsCircuitsUpToDate => 'Lista torów jest aktualna.';

  @override
  String get settingsCircuitsFailed =>
      'Nie udało się pobrać listy torów. Sprawdź połączenie i spróbuj ponownie.';

  @override
  String get settingsCircuitsMine => 'Twoje nazwy torów';

  @override
  String settingsCircuitsRenamed(String name) {
    return 'Na liście: $name';
  }

  @override
  String get settingsCircuitsAdded => 'Dodany przez Ciebie';

  @override
  String get settingsCircuitsForget => 'Usuń tę nazwę';

  @override
  String summaryTitle(String session) {
    return '$session w 30 sekund';
  }

  @override
  String get summaryIntro =>
      'Obserwacje z Twoich okrążeń, nie przyczyny. Typowy czas to mediana z co najmniej 3 okrążeń.';

  @override
  String summaryNotShown(String session) {
    return '$session nie ma mierzonych okrążeń na pokazanym torze.';
  }

  @override
  String get summaryBestLap => 'Najlepsze okrążenie';

  @override
  String summaryBestNew(String time, String delta) {
    return '$time · nowy najlepszy czas dnia ($delta)';
  }

  @override
  String summaryBestBehind(String time, String delta, String session) {
    return '$time · $delta do najlepszego okrążenia ($session)';
  }

  @override
  String summaryBestFirst(String time) {
    return '$time · pierwsza sesja dnia';
  }

  @override
  String get summaryNoBest => 'Brak sklasyfikowanego okrążenia';

  @override
  String get summarySpread => 'Rozrzut czasów okrążeń';

  @override
  String summarySpreadValue(String spread) {
    return '$spread s';
  }

  @override
  String summarySpreadThen(String spread, String session, String previous) {
    return '$spread s ($session: $previous s)';
  }

  @override
  String get summaryGain => 'Największy zysk';

  @override
  String get summaryLoss => 'Największa strata';

  @override
  String summaryChange(String segment, String delta) {
    return '$segment $delta';
  }

  @override
  String summaryNoChange(String seconds) {
    return 'Brak zmian o $seconds s lub więcej';
  }

  @override
  String get summaryFirstSession => 'Pierwsza sesja: brak porównania';

  @override
  String get summaryNotCompared =>
      'Potrzeba 3 przejazdów odcinka w obu sesjach';

  @override
  String summaryAgainst(String session) {
    return 'Zyski i straty: typowe czasy odcinków w porównaniu z poprzednią sesją ($session).';
  }

  @override
  String get summaryGap => 'Największa rezerwa';

  @override
  String summaryGapValue(String segment, String delta) {
    return '$segment $delta do najszybszego typowego czasu';
  }

  @override
  String get summaryCar => 'Auto, najwyższe temperatury';

  @override
  String summaryTemperature(String channel, String value) {
    return '$channel $value';
  }

  @override
  String summaryTemperatureThen(
    String channel,
    String value,
    String session,
    String previous,
  ) {
    return '$channel $value ($session: $previous)';
  }

  @override
  String summaryGoal(String session) {
    return 'Cel po sesji: $session';
  }

  @override
  String get summaryWorking => 'Obliczanie…';

  @override
  String summaryBestNoEarlier(String time) {
    return '$time · żadna wcześniejsza sesja nie ma sklasyfikowanego okrążenia';
  }

  @override
  String summaryBestEqual(String time, String session) {
    return '$time · tyle samo co najlepsze okrążenie ($session)';
  }

  @override
  String get summaryNoEarlierRanked =>
      'Żadna wcześniejsza sesja nie ma sklasyfikowanego okrążenia';

  @override
  String get summarySegments => 'Odcinki';

  @override
  String get summarySegmentsUnavailable =>
      'Niedostępne bez teoretycznego czasu okrążenia';

  @override
  String get summaryGoalBefore => 'Cel po poprzedniej sesji';

  @override
  String get summaryNoFocus => 'Nie było zmiany do przećwiczenia';

  @override
  String get summaryCoachFailed => 'Trener nie mógł przeanalizować sesji';

  @override
  String summaryGapNone(String seconds) {
    return 'W granicach $seconds s od najszybszego typowego czasu na każdym zmierzonym odcinku';
  }

  @override
  String get summaryGapNeedsLaps => 'Potrzeba 3 przejazdów odcinka';

  @override
  String get summaryOnlySession => 'Brak innej sesji do porównania';

  @override
  String get removeSession => 'Usuń sesję';

  @override
  String get removeSessionMenu => 'Usuń sesję…';

  @override
  String get removeSessionChoose => 'Którą sesję usunąć?';

  @override
  String removeSessionTitle(String session) {
    return 'Usunąć z dnia: $session?';
  }

  @override
  String get removeSessionBody =>
      'Jej okrążenia znikną z dnia: najlepsze okrążenie, teoretyczny czas okrążenia, trener i Twój profil zostaną przeliczone bez nich. Sam plik zapisu nie zostanie usunięty.';

  @override
  String get removeSessionConfirm => 'Usuń';

  @override
  String get removeSessionLast =>
      'Dzień musi mieć co najmniej jedną sesję. Aby usunąć cały dzień, usuń go w bibliotece.';

  @override
  String get removeSessionBusy =>
      'Poczekaj, aż dzień skończy zapisywanie lub pracę nad zapisami, i spróbuj ponownie.';

  @override
  String get removeSessionNotSaved =>
      'Nie udało się zapisać dnia, więc sesja nie została usunięta.';

  @override
  String get removeSessionChangedMeanwhile =>
      'Dzień w międzyczasie się zmienił, więc sesja nie została usunięta. Spróbuj ponownie.';

  @override
  String removeSessionFailed(String error) {
    return 'Sesja nie została usunięta: $error';
  }

  @override
  String sessionRemoved(String session) {
    return 'Usunięto z dnia: $session.';
  }

  @override
  String get sessionRemovedUndo => 'Cofnij';

  @override
  String sessionRestored(String session) {
    return 'Przywrócono do dnia: $session.';
  }

  @override
  String get sessionRestoreRefused =>
      'Dzień zmienił się od tego czasu, więc nie można przywrócić sesji.';

  @override
  String get libraryDayActions => 'Opcje dnia';

  @override
  String get libraryDeleteDay => 'Usuń dzień';

  @override
  String libraryDeleteDayTitle(String day) {
    return 'Usunąć dzień „$day”?';
  }

  @override
  String libraryDeleteDayBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Dzień i jego $count sesji znikną z profilu, a zapisany plik dnia zostanie usunięty. Kopie zapisów zrobione dla niego przez aplikację też zostaną usunięte; Twoje własne pliki zapisów zostaną tam, gdzie są. Tego nie można cofnąć.',
      many:
          'Dzień i jego $count sesji znikną z profilu, a zapisany plik dnia zostanie usunięty. Kopie zapisów zrobione dla niego przez aplikację też zostaną usunięte; Twoje własne pliki zapisów zostaną tam, gdzie są. Tego nie można cofnąć.',
      few:
          'Dzień i jego $count sesje znikną z profilu, a zapisany plik dnia zostanie usunięty. Kopie zapisów zrobione dla niego przez aplikację też zostaną usunięte; Twoje własne pliki zapisów zostaną tam, gdzie są. Tego nie można cofnąć.',
      one: 'Dzień i jego sesja znikną z profilu, a zapisany plik dnia zostanie usunięty. Kopie zapisów zrobione dla niego przez aplikację też zostaną usunięte; Twoje własne pliki zapisów zostaną tam, gdzie są. Tego nie można cofnąć.',
    );
    return '$_temp0';
  }

  @override
  String get libraryDeleteConfirm => 'Usuń';

  @override
  String libraryDayDeleted(String day) {
    return 'Usunięto: $day.';
  }

  @override
  String libraryDayDeleteFailed(String error) {
    return 'Dzień nie został usunięty: $error';
  }

  @override
  String get removeSessionCorners =>
      'Jeśli zakręty dnia zostały wyznaczone w tej sesji, zostaną wyznaczone ponownie na najlepszym pozostałym okrążeniu, a nadane im nazwy przepadną.';

  @override
  String get removeSessionNothingLeft =>
      'Zapisów żadnej z pozostałych sesji nie da się otworzyć, więc dzień nie miałby nic do pokazania. Sesja nie została usunięta.';

  @override
  String get libraryDeleteDayOpen => 'Najpierw zamknij dzień, potem go usuń.';

  @override
  String get ownGoalsTitle => 'Twoje cele na następną sesję';

  @override
  String get ownGoalsIntro =>
      'Sprawdzane względem tej sesji po dodaniu następnej.';

  @override
  String ownGoalsNone(int count) {
    return 'Ustaw do $count rzeczy do poprawy, każdą w jednym zakręcie. Następna sesja zostanie porównana z tą.';
  }

  @override
  String get ownGoalsReadOnly =>
      'Zapisane w formie, której ta wersja aplikacji nie edytuje, więc nie są tu zmieniane.';

  @override
  String get ownGoalsNeedCorners =>
      'Cele można ustawić, gdy zakręty dnia są gotowe.';

  @override
  String get ownGoalsAdd => 'Dodaj cel';

  @override
  String get ownGoalsRemove => 'Usuń cel';

  @override
  String get ownGoalsCorner => 'Zakręt';

  @override
  String get ownGoalsChange => 'Co poprawić';

  @override
  String get ownGoalsTaken => 'Ten cel jest już ustawiony.';

  @override
  String get ownGoalsSave => 'Dodaj';

  @override
  String summaryOwnGoal(String goal) {
    return 'Twój cel: $goal';
  }

  @override
  String get ownGoalsNotSaved => 'Nie udało się zapisać celów.';

  @override
  String ownGoalsNeedLaps(String session) {
    return 'Cele wymagają, by $session miała okrążenia wśród porównywanych.';
  }

  @override
  String summaryOwnGoalNoLaps(String session) {
    return 'Nie zmierzono: $session i ta sesja potrzebują okrążeń wśród porównywanych';
  }

  @override
  String get summaryOwnGoalOtherGroup =>
      'Nie zmierzono: ustawiony dla innych porównywanych okrążeń';

  @override
  String get ownGoalsOtherGroup =>
      'Te cele ustawiono dla innych porównywanych okrążeń. Usuń je, aby ustawić nowe.';

  @override
  String get briefingTitle => 'Przed wyjazdem';

  @override
  String briefingFrom(String session) {
    return 'Na podstawie: $session';
  }

  @override
  String get briefingGoals => 'Twoje cele';

  @override
  String get briefingNoGoals =>
      'Brak: dodaj je w sekcji Twoje cele na następną sesję';

  @override
  String get briefingChance => 'Największa szansa';

  @override
  String get summaryCarWatch => 'Auto, ostatnie okrążenia';

  @override
  String summaryCarRise(
    String channel,
    String from,
    String to,
    String fromLap,
    String toLap,
  ) {
    return '$channel nadal rośnie: $from → $to (okrążenia $fromLap–$toLap)';
  }

  @override
  String summaryCarFall(
    String percent,
    String fromLap,
    String toLap,
    String from,
    String to,
  ) {
    return 'Mocne przyspieszenie niższe o $percent% od okrążenia $fromLap do $toLap ($from → $to)';
  }

  @override
  String summaryCarFallWith(
    String fall,
    String channel,
    String from,
    String to,
  ) {
    return '$fall; w tym czasie $channel $from → $to';
  }

  @override
  String get summaryCarSettledTemperatures =>
      'Żadna temperatura nie rośnie na końcu';

  @override
  String get summaryCarSettledAcceleration => 'Mocne przyspieszenie bez spadku';

  @override
  String summaryCarTemperaturesNeedLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Temperatury: potrzeba $count sklasyfikowanych okrążeń',
      many: 'Temperatury: potrzeba $count sklasyfikowanych okrążeń',
      few: 'Temperatury: potrzeba $count sklasyfikowanych okrążeń',
      one: 'Temperatury: potrzeba 1 sklasyfikowanego okrążenia',
    );
    return '$_temp0';
  }

  @override
  String summaryCarAccelerationNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Mocne przyspieszenie: potrzeba $count sklasyfikowanych okrążeń',
      many: 'Mocne przyspieszenie: potrzeba $count sklasyfikowanych okrążeń',
      few: 'Mocne przyspieszenie: potrzeba $count sklasyfikowanych okrążeń',
      one: 'Mocne przyspieszenie: potrzeba 1 sklasyfikowanego okrążenia',
    );
    return '$_temp0';
  }

  @override
  String summaryCarTemperaturesMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Temperatury: brak zapisu na którymś z ostatnich $count sklasyfikowanych okrążeń',
      many:
          'Temperatury: brak zapisu na którymś z ostatnich $count sklasyfikowanych okrążeń',
      few:
          'Temperatury: brak zapisu na którymś z ostatnich $count sklasyfikowanych okrążeń',
      one: 'Temperatury: brak zapisu na ostatnim sklasyfikowanym okrążeniu',
    );
    return '$_temp0';
  }

  @override
  String get summaryCarAccelerationMissing =>
      'Mocne przyspieszenie: brak odczytu na ostatnim sklasyfikowanym okrążeniu';

  @override
  String get summaryCarFallNote =>
      'Ruch na torze i inna linia też je obniżają.';

  @override
  String summaryCarAccelerationOnLaps(int count, int ranked, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Mocne przyspieszenie: odczyt na $count z $ranked sklasyfikowanych okrążeń, potrzeba $needed',
      many:
          'Mocne przyspieszenie: odczyt na $count z $ranked sklasyfikowanych okrążeń, potrzeba $needed',
      few:
          'Mocne przyspieszenie: odczyt na $count z $ranked sklasyfikowanych okrążeń, potrzeba $needed',
      one:
          'Mocne przyspieszenie: odczyt na 1 z $ranked sklasyfikowanych okrążeń, potrzeba $needed',
    );
    return '$_temp0';
  }

  @override
  String get briefingLastLap => 'Ostatnie sklasyfikowane okrążenie';

  @override
  String get briefingDayBest => 'Najlepsze okrążenie dnia';

  @override
  String get briefingDelta => 'Różnica do najlepszego';

  @override
  String get briefingCar => 'Auto';

  @override
  String briefingNoRankedLap(String session) {
    return '$session nie ma sklasyfikowanego okrążenia na pokazanym torze.';
  }

  @override
  String changesButton(int count, String session) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Odcinki ($count) w porównaniu z: $session',
      one: '1 odcinek w porównaniu z: $session',
    );
    return '$_temp0';
  }

  @override
  String changesTitle(String session) {
    return 'Zmiany od: $session';
  }

  @override
  String changesIntro(String session, String threshold) {
    return 'Typowy (mediana) czas każdego odcinka w porównaniu z: $session, z rozrzutem środkowej połowy czasów. Zmiany poniżej $threshold s nie są liczone. Obserwacje z Twoich okrążeń, nie przyczyny.';
  }

  @override
  String get changesQuicker => 'Szybciej';

  @override
  String get changesSlower => 'Wolniej';

  @override
  String changesNoneQuicker(String threshold) {
    return 'Żaden odcinek nie jest szybszy o $threshold s lub więcej.';
  }

  @override
  String changesNoneSlower(String threshold) {
    return 'Żaden odcinek nie jest wolniejszy o $threshold s lub więcej.';
  }

  @override
  String changesSame(String threshold, String session) {
    return 'W granicach $threshold s względem: $session';
  }

  @override
  String changesTypical(String now, String session, String before) {
    return 'Typowo $now ($session: $before)';
  }

  @override
  String changesSpread(String now, String session, String before) {
    return 'Rozrzut $now s ($session: $before s)';
  }

  @override
  String get changesTitleNone => 'Zmiany na odcinkach';

  @override
  String get cornerPhasesTitle => 'Skąd wziął się czas';

  @override
  String get cornerPhaseEntry => 'Wejście';

  @override
  String get cornerPhaseMiddle => 'Środek';

  @override
  String get cornerPhaseExit => 'Wyjście';

  @override
  String get cornerPhasesNote =>
      'Wejście trwa do miejsca, w którym zakręt jest najciaśniejszy, środek obejmuje tę część, a wyjście sięga do końca zakrętu. Podział wynika z kształtu toru, więc oba okrążenia są mierzone na tych samych metrach, a trzy czasy sumują się do czasu zakrętu.';

  @override
  String cornerPhasesUnavailable(String reason) {
    return 'Nie podzielono: $reason';
  }

  @override
  String get cornerPhasesMoreThanOneTightPart =>
      'więcej niż jedna najciaśniejsza część';

  @override
  String cornerPhasesBestNotTimed(String reason) {
    return 'Najlepsze okrążenie nie zostało zmierzone w częściach: $reason';
  }

  @override
  String get spreadMapHeading => 'Gdzie okrążenia się różnią';

  @override
  String get spreadMapIntro =>
      'Każdy odcinek najlepszego okrążenia pokolorowany według rozrzutu w sesji: szerokości środkowej połowy jego czasów. Zielony: okrążenia powtarzalne; czerwony: tu różnią się najbardziej.';

  @override
  String spreadMapLabel(String session) {
    return 'Mapa najlepszego okrążenia, rozrzut każdego odcinka: $session';
  }

  @override
  String spreadBandAtMost(String value) {
    return 'Do $value s';
  }

  @override
  String spreadBandBetween(String from, String to) {
    return '$from–$to s';
  }

  @override
  String spreadBandAbove(String value) {
    return 'Ponad $value s';
  }

  @override
  String get spreadOutsideSegments => 'Poza odcinkami';

  @override
  String get tbThreeTitle => 'Trzy sposoby liczenia';

  @override
  String get tbRawLabel => 'Najszybsze odcinki';

  @override
  String get tbRawNote =>
      'Najszybszy czas każdego odcinka z dowolnego okrążenia.';

  @override
  String get tbRealisticLabel => 'Odcinki, które się łączą';

  @override
  String tbRealisticNote(String tolerance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Szacunek: najszybsze odcinki, których prędkości różnią się najwyżej o $tolerance km/h wszędzie tam, gdzie spotykają się dwa okrążenia, bo samochód nie zmienia prędkości skokowo. Złożony z $_temp0.';
  }

  @override
  String get tbRealisticNoSpeed =>
      'Nie pokazano: żadne okrążenie nie ma prędkości w znanej jednostce, więc nie da się połączyć dwóch okrążeń.';

  @override
  String get tbRealisticIncomplete =>
      'Nie pokazano: jeden z odcinków nie ma czasu na żadnym okrążeniu.';

  @override
  String get tbRepeatableLabel => 'Najlepszy typowy czas';

  @override
  String get tbRepeatableNote =>
      'Najszybszy typowy czas (mediana) każdego odcinka w jednej sesji: to, co robisz tam zwykle, a nie raz.';

  @override
  String tbRepeatableNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążenia',
      many: '$count okrążeń',
      few: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Nie pokazano: potrzeba co najmniej $_temp0 przez każdy odcinek w jednej sesji.';
  }

  @override
  String get tbRealisticNoJoin =>
      'Nie pokazano: każdy odcinek ma czas, ale żadne okrążenia nie łączą się z prędkością, jaką miał samochód na każdej granicy między nimi.';

  @override
  String get notebookTitle => 'Notatnik toru';

  @override
  String notebookTitleOf(String track) {
    return 'Notatnik: $track';
  }

  @override
  String get notebookIntro =>
      'Przechowywany z torem w bibliotece, więc każda wizyta na nim pokazuje ten sam notatnik. Zapisywany na bieżąco.';

  @override
  String get notebookToTry => 'Do wypróbowania';

  @override
  String get notebookNothingToTry => 'Na razie nic do wypróbowania.';

  @override
  String get notebookAddHint => 'Coś do wypróbowania następnym razem';

  @override
  String get notebookAdd => 'Dodaj';

  @override
  String get notebookRemove => 'Usuń';

  @override
  String get notebookDone => 'Zrobione';

  @override
  String get notebookNotes => 'Notatki';

  @override
  String get notebookNotesHint =>
      'Przyczepność, tarki, punkty orientacyjne, zagrożenia, ustawienia…';

  @override
  String get notebookCorners => 'Zakręty';

  @override
  String get notebookNoCorners =>
      'Zakręty toru pojawią się tutaj po zmierzeniu pierwszego dnia na tym torze.';

  @override
  String get notebookNoTrack => 'Tego toru nie ma już w bibliotece.';

  @override
  String libraryImportNotebooks(int count) {
    return 'Notatniki torów uzupełnione notatkami z pliku: $count.';
  }

  @override
  String get libraryImportNotebookCut =>
      'Część notatek z pliku nie zmieściła się w notatniku i została pominięta.';

  @override
  String libraryImportReferencesNotKept(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięto okrążenia odniesienia $count dni: ich zapisy nie zmieściły się w limicie zapisów odniesienia w profilu albo był tu już inny plik o tej samej nazwie.',
      few:
          'Pominięto okrążenia odniesienia $count dni: ich zapisy nie zmieściły się w limicie zapisów odniesienia w profilu albo był tu już inny plik o tej samej nazwie.',
      one: 'Pominięto okrążenie odniesienia 1 dnia: jego zapis nie zmieścił się w limicie zapisów odniesienia w profilu albo był tu już inny plik o tej samej nazwie.',
    );
    return '$_temp0';
  }

  @override
  String libraryImportReferencesMissing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count zapisów odniesienia nie było w pliku: te odniesienia powiedzą, że nie znaleziono zapisu.',
      few:
          '$count zapisy odniesienia nie były w pliku: te odniesienia powiedzą, że nie znaleziono zapisu.',
      one: '1 zapisu odniesienia nie było w pliku: to odniesienie powie, że nie znaleziono zapisu.',
    );
    return '$_temp0';
  }

  @override
  String notebookFull(int count) {
    return 'Notatnik mieści najwyżej $count rzeczy do wypróbowania. Usuń którąś, aby dodać kolejną.';
  }

  @override
  String get notebookNotSaved =>
      'Nie udało się zapisać ostatniej zmiany: notatnik przekracza to, co mieści biblioteka.';

  @override
  String variabilityLineParts(String parts, String accuracy) {
    return 'Rozrzut toru jazdy: $parts · $accuracy';
  }

  @override
  String variabilityLineEntry(String spread) {
    return 'na wejściu $spread m';
  }

  @override
  String variabilityLineApex(String spread) {
    return 'na wierzchołku $spread m';
  }

  @override
  String variabilityLineExit(String spread) {
    return 'na wyjściu $spread m';
  }

  @override
  String get variabilityLineEntryName => 'wejście';

  @override
  String get variabilityLineApexName => 'wierzchołek';

  @override
  String get variabilityLineExitName => 'wyjście';

  @override
  String variabilityLinePartsUnresolved(String parts) {
    return ' · $parts: nie do odróżnienia od błędu GPS';
  }

  @override
  String get ggEnvelopeTitle => 'Obwiednia G–G';

  @override
  String get ggEnvelopeIntro =>
      'Jak mocno każda sesja obciążała samochód w każdym kierunku (łączne przeciążenie): 95. percentyl łącznego przeciążenia na jej sklasyfikowanych okrążeniach, więc pojedynczy skok go nie wyznacza. Okrążenia wyjazdowe, zjazdowe i wykluczone są pominięte.';

  @override
  String get ggEnvelopeCalculating => 'Obliczanie obwiedni G–G…';

  @override
  String ggEnvelopeFailed(String error) {
    return 'Nie udało się obliczyć obwiedni G–G: $error';
  }

  @override
  String get ggEnvelopeNone =>
      'Żadna sesja nie ma dość danych o przeciążeniach, by wyznaczyć obwiednię.';

  @override
  String get ggEnvelopeDirection => 'Kierunek';

  @override
  String get ggEnvelopeBestOfDay => 'Najlepsza dnia';

  @override
  String ggEnvelopeLatest(String session) {
    return '$session, ostatnia';
  }

  @override
  String ggEnvelopeBestValue(String value, String session) {
    return '$value · $session';
  }

  @override
  String get ggDirectionAccelerating => 'Przyspieszanie';

  @override
  String get ggDirectionAcceleratingLeft => 'Przyspieszanie + skręt w lewo';

  @override
  String get ggDirectionLeft => 'Skręt w lewo';

  @override
  String get ggDirectionBrakingLeft => 'Hamowanie + skręt w lewo';

  @override
  String get ggDirectionBraking => 'Hamowanie';

  @override
  String get ggDirectionBrakingRight => 'Hamowanie + skręt w prawo';

  @override
  String get ggDirectionRight => 'Skręt w prawo';

  @override
  String get ggDirectionAcceleratingRight => 'Przyspieszanie + skręt w prawo';

  @override
  String ggEnvelopeUnused(String session, String directions) {
    return '$session, niewykorzystana obwiednia: $directions.';
  }

  @override
  String ggEnvelopeUnusedItem(
    String direction,
    String latest,
    String best,
    String session,
  ) {
    return '$direction $latest wobec $best ($session)';
  }

  @override
  String ggEnvelopeAllUsed(String session, String margin) {
    return '$session: mniej niż $margin poniżej najlepszej obwiedni dnia w każdym kierunku, w którym ma wartość.';
  }

  @override
  String get ggEnvelopeOneSession =>
      'Tylko jedna sesja ma obwiednię, więc nie ma jeszcze z czym jej porównać.';

  @override
  String ggEnvelopeLatestNone(String session) {
    return '$session: brak obwiedni, więc nie ma porównania.';
  }

  @override
  String ggEnvelopeSessionUnavailable(String session, String reason) {
    return '$session: $reason';
  }

  @override
  String ggEnvelopeTooFewSamples(int count) {
    return 'Za mało danych: mniej niż $count próbek w każdym kierunku';
  }

  @override
  String ggEnvelopeMissingNote(int count) {
    return '— oznacza mniej niż $count próbek w tym kierunku.';
  }

  @override
  String ggEnvelopeNote(String margin) {
    return 'Zaobserwowane przyspieszenia nie określają procentu wykorzystania dostępnej przyczepności. Niewykorzystana oznacza co najmniej $margin poniżej najlepszej obwiedni dnia. Okręgi co 0.5 g; linia przerywana to najlepsza obwiednia dnia, gruba linia to ostatnia sesja.';
  }

  @override
  String get ggEnvelopeSemantics =>
      'Obwiednia G–G każdej sesji na tle najlepszej obwiedni dnia';

  @override
  String ggEnvelopeOutliers(String session, int count, String limit) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count próbki',
      many: '$count próbek',
      few: '$count próbki',
      one: '1 próbkę',
    );
    return '$session: $_temp0 powyżej $limit pominięto jako nieprawdopodobne';
  }

  @override
  String get profileTrends => 'Dzień po dniu';

  @override
  String get profileTrendsIntro =>
      'Każdy tor w każdym samochodzie osobno: wartości zależą od obu, więc dzień porównuje się tylko z dniami na tym samym torze w tym samym samochodzie. Przy rozrzucie punktu hamowania, prędkości minimalnej poniżej najlepszej, czasie od odjęcia gazu do hamowania i rozrzucie czasów okrążeń mniej znaczy lepiej. Każda z tych wartości to mediana z zakrętów zmierzonych danego dnia, więc dni mogą się różnić zakrętami, z których pochodzi. Prędkość minimalna jest liczona względem Twojej najlepszej w każdym zakręcie tego toru, więc nowa najlepsza zmienia też wartości wcześniejszych dni.';

  @override
  String get profileTrendsWetDry =>
      'Nie zapisuje się, czy tor był mokry, czy suchy. Pokazana pogoda pochodzi z modelu pogody dla okolicy w czasie każdej sesji, a nie z nawierzchni toru, więc dni nie są dzielone na mokre i suche.';

  @override
  String profileTrendsGroup(String track, String direction, String car) {
    return '$track · $direction · $car';
  }

  @override
  String profileTrendsTooFew(int days, int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dnia z datą',
      many: '$days dni z datą',
      few: '$days dni z datą',
      one: '1 dzień z datą',
      zero: 'Brak dni z datą',
    );
    return '$_temp0 na tym torze w tym samochodzie: trend wymaga co najmniej $minimum dni.';
  }

  @override
  String profileTrendsShowingLast(int shown, int total) {
    return 'Ostatnie $shown z $total dni na tym torze.';
  }

  @override
  String profileTrendsBestLap(String time) {
    return 'Najlepsze okrążenie $time';
  }

  @override
  String get profileTrendsPersonalBest =>
      'nowy rekord tego toru w tym samochodzie';

  @override
  String profileTrendsTypicalLap(String time) {
    return 'Typowe okrążenie $time';
  }

  @override
  String get profileTrendsNoLapTimes =>
      'Brak zapisanego czasu okrążenia dla tego dnia.';

  @override
  String get profileTrendsNotMeasured =>
      'Brak wartości zakrętów i okrążeń dla tego dnia: dodano go, zanim biblioteka mierzyła sesje, albo jego sesje nie miały sklasyfikowanych okrążeń ani zakrętów do zmierzenia.';

  @override
  String profileTrendsWeather(String weather) {
    return 'Model pogody: $weather';
  }

  @override
  String get profileTrendsNoWeather => 'Brak zapisanej pogody dla tego dnia.';

  @override
  String get profileTrendsChanges => 'Od pierwszego do ostatniego dnia';

  @override
  String profileTrendsMeasure(String id) {
    String _temp0 = intl.Intl.selectLogic(id, {
      'bestLap': 'Najlepsze okrążenie',
      'typicalLap': 'Typowe okrążenie',
      'brakePointConsistency': 'Rozrzut punktu hamowania',
      'minimumSpeedControl': 'Prędkość minimalna poniżej najlepszej',
      'liftTiming': 'Od odjęcia gazu do hamowania',
      'paceConsistency': 'Rozrzut czasów okrążeń',
      'other': '$id',
    });
    return '$_temp0';
  }

  @override
  String profileTrendsChange(
    String measure,
    String first,
    String firstDate,
    String last,
    String lastDate,
    int days,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dnia',
      many: '$days dniach',
      few: '$days dniach',
      one: '1 dniu',
    );
    return '$measure: $first ($firstDate) → $last ($lastDate), zmierzone w $_temp0';
  }

  @override
  String profileTrendsRain(String amount) {
    return 'do $amount mm opadu w sesji';
  }

  @override
  String profileTrendsFigureTooFew(String measure, int measured, int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      measured,
      locale: localeName,
      other: 'w $measured dnia z datą',
      many: 'w $measured dniach z datą',
      few: 'w $measured dniach z datą',
      one: 'w 1 dniu z datą',
      zero: 'w żadnym dniu z datą',
    );
    return '$measure: zmierzone $_temp0; trend wymaga wartości z co najmniej $minimum dni.';
  }

  @override
  String get profileTrendsUndated =>
      'Dni bez daty są na końcu listy i nie wchodzą do trendu ani do rekordu.';

  @override
  String profileTrendsWeatherSome(int sessions, int total) {
    return '($sessions z $total sesji)';
  }

  @override
  String get progressionByLap => 'Według okrążeń';

  @override
  String get evolutionIntro =>
      'Mierzone okrążenia każdej sesji po kolei, liczone od początku jej pierwszego mierzonego okrążenia (zapis może zacząć się w parku maszyn, więc okrążenie wyjazdowe nie jest liczone). Każda linia ma podpis sesji i własny znacznik; bledsze linie to wcześniejsze sesje. Wybierz okrążenie, aby je otworzyć.';

  @override
  String get evolutionChartLabel =>
      'Czas okrążenia według numeru okrążenia, jedna linia na sesję';

  @override
  String evolutionLap(int number) {
    return 'OKR. $number';
  }

  @override
  String evolutionSinceFirstLap(String time) {
    return '+$time';
  }

  @override
  String get evolutionNotRanked => 'niesklasyfikowane';

  @override
  String evolutionPaceExplained(int count) {
    return 'Środkowa połowa sesji to środkowe 50% czasów jej sklasyfikowanych okrążeń; potrzeba co najmniej $count sklasyfikowanych okrążeń. Szare okrążenia były przed pierwszym okrążeniem w środkowej połowie lub szybszym.';
  }

  @override
  String evolutionPaceFrom(int number, int before) {
    String _temp0 = intl.Intl.pluralLogic(
      before,
      locale: localeName,
      other:
          'Pierwsze okrążenie w środkowej połowie sesji lub szybsze: OKR. $number, po $before okrążeniach',
      one:
          'Pierwsze okrążenie w środkowej połowie sesji lub szybsze: OKR. $number, po 1 okrążeniu',
      zero:
          'Pierwsze okrążenie w środkowej połowie sesji lub szybsze: OKR. $number, pierwsze mierzone okrążenie',
    );
    return '$_temp0';
  }

  @override
  String evolutionPaceNotCounted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count okrążeń przed tym okrążeniem nie jest sklasyfikowanych, więc nie wiadomo, czy były wolniejsze',
      few:
          '$count okrążenia przed tym okrążeniem nie są sklasyfikowane, więc nie wiadomo, czy były wolniejsze',
      one: '1 okrążenie przed tym okrążeniem nie jest sklasyfikowane, więc nie wiadomo, czy było wolniejsze',
    );
    return '$_temp0';
  }

  @override
  String evolutionPaceNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Do wyznaczenia środkowej połowy sesji potrzeba co najmniej $count sklasyfikowanych okrążeń',
      one: 'Do wyznaczenia środkowej połowy sesji potrzeba co najmniej 1 sklasyfikowanego okrążenia',
    );
    return '$_temp0';
  }

  @override
  String evolutionSameLaps(String session, String delta, int count) {
    return 'Względem $session na tych samych okrążeniach: typowa różnica $delta z $count okrążeń';
  }

  @override
  String evolutionSameLapsTooFew(String session, int count, int minimum) {
    return 'Względem $session na tych samych okrążeniach: $count z $minimum potrzebnych okrążeń';
  }

  @override
  String evolutionAir(String temperature) {
    return 'Powietrze (model): $temperature';
  }

  @override
  String get evolutionCaveat =>
      'To obserwacje, nie przyczyny: opony, tor i Twoja znajomość toru zmieniają się razem w trakcie sesji i całego dnia, a ta analiza nie potrafi ich rozdzielić. Temperatura nawierzchni toru nie jest rejestrowana.';

  @override
  String get evolutionNoLaps => 'Żadna sesja nie ma mierzonych okrążeń.';

  @override
  String evolutionQuickerLater(int number, String gain, int first) {
    return 'Najszybsze okrążenie przyszło później: OKR. $number, o $gain szybsze niż OKR. $first.';
  }

  @override
  String get cornerClassTitle => 'Rodzaj zakrętu';

  @override
  String get cornerClassShape => 'Kształt · z toru';

  @override
  String get cornerClassApproach => 'Hamowanie · z okrążeń tego dnia';

  @override
  String get cornerClassSpeed => 'Prędkość · z okrążeń tego dnia';

  @override
  String get cornerShapeSingleApex => 'Jeden wierzchołek';

  @override
  String get cornerShapeLateApex => 'Późny wierzchołek';

  @override
  String get cornerShapeDecreasingRadius => 'Zacieśniający się';

  @override
  String get cornerShapeIncreasingRadius => 'Otwierający się';

  @override
  String get cornerShapeDoubleApex => 'Podwójny wierzchołek';

  @override
  String get cornerShapeComplex => 'Kombinacja zakrętów';

  @override
  String get cornerApproachHeavyBraking => 'Mocne hamowanie';

  @override
  String get cornerApproachBraking => 'Hamowanie';

  @override
  String get cornerApproachLift => 'Odjęcie gazu';

  @override
  String get cornerApproachFlat => 'Pełny gaz';

  @override
  String get cornerSpeedSlow => 'Wolny zakręt';

  @override
  String get cornerSpeedMedium => 'Średnio szybki zakręt';

  @override
  String get cornerSpeedFast => 'Szybki zakręt';

  @override
  String get cornerShapeNoteSingle =>
      'Jedna najciaśniejsza część, nie późno w zakręcie; zakręt nie zacieśnia się do końca ani nie otwiera od początku.';

  @override
  String get cornerShapeNoteLate =>
      'Jedna najciaśniejsza część, późno w zakręcie, który potem znów się otwiera.';

  @override
  String cornerShapeNoteDecreasing(String ratio) {
    return 'Zacieśnia się: druga połowa skręca $ratio× mocniej niż pierwsza.';
  }

  @override
  String cornerShapeNoteIncreasing(String ratio) {
    return 'Otwiera się: pierwsza połowa skręca $ratio× mocniej niż druga.';
  }

  @override
  String get cornerShapeNoteDouble =>
      'Dwie oddzielne ciasne części, mierzone jako jeden zakręt.';

  @override
  String cornerShapeNoteComplex(int count) {
    return 'Ciasne części w tym odcinku: $count, klasyfikowane razem jako jeden zakręt.';
  }

  @override
  String get cornerShapeNoteDirection =>
      'Skręca w jedną stronę, potem w drugą: więcej niż jeden zakręt w tym odcinku, klasyfikowane razem.';

  @override
  String get cornerClassFromBrakePedal => 'pedał hamulca';

  @override
  String get cornerClassFromDeceleration => 'wywnioskowane z opóźnienia';

  @override
  String cornerApproachNoteShed(String shed, String how, int braked, int laps) {
    return 'W najwolniejszym miejscu zwykle o $shed wolniej niż tam, gdzie zaczyna się hamowanie. Hamowanie na $braked z $laps okrążeń ($how).';
  }

  @override
  String cornerApproachNoteNoShed(String how, int braked, int laps) {
    return 'Hamowanie na $braked z $laps okrążeń ($how). Spadek prędkości od początku hamowania do najwolniejszego miejsca nie jest znany na co najmniej trzech okrążeniach, więc nie wiadomo, czy hamowanie jest mocne.';
  }

  @override
  String cornerApproachNoteNoBraking(
    String loss,
    String how,
    int none,
    int laps,
  ) {
    return 'Bez hamowania na $none z $laps okrążeń ($how). W najwolniejszym miejscu zwykle o $loss wolniej niż na początku zakrętu.';
  }

  @override
  String cornerApproachNoteNoBrakingNoSpeed(String how, int none, int laps) {
    return 'Bez hamowania na $none z $laps okrążeń ($how).';
  }

  @override
  String cornerSpeedNote(String speed, int laps) {
    return 'Typowa prędkość minimalna $speed z $laps okrążeń.';
  }

  @override
  String cornerClassUnavailable(String reason) {
    return 'Nieznane: $reason';
  }

  @override
  String get cornerClassReasonTooFewLaps =>
      'zmierzono tu mniej niż trzy okrążenia';

  @override
  String get cornerClassReasonSpeedUnit => 'nieznana jednostka prędkości';

  @override
  String get cornerClassNote =>
      'Kształt wynika z krzywizny toru na linii okrążenia, z którego zbudowano oś toru, w tej części odcinka, która skręca; hamowanie i prędkość to typowe (mediana) wartości okrążeń tego dnia w tym miejscu, z kanału prędkości. Progi są takie same na każdym torze: mocne hamowanie to co najmniej 40 km/h mniej w najwolniejszym miejscu niż tam, gdzie zaczyna się hamowanie; odjęcie gazu to utrata co najmniej 5 % prędkości z początku zakrętu bez hamowania, mniej to pełny gaz; wolny zakręt to poniżej 80 km/h, szybki od 130 km/h. Odcinek z kilkoma zakrętami jest klasyfikowany jako całość.';

  @override
  String get cornerApproachBrakingHeavyUnknown => 'Hamowanie (siła nieznana)';

  @override
  String cornerClassOtherUnits(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięto prędkości $count okrążenia zapisanego w innej jednostce.',
      many: 'Pominięto prędkości $count okrążeń zapisanych w innej jednostce.',
      few: 'Pominięto prędkości $count okrążeń zapisanych w innej jednostce.',
      one: 'Pominięto prędkości 1 okrążenia zapisanego w innej jednostce.',
    );
    return '$_temp0';
  }

  @override
  String get cornerClassAssumedKmh => 'km/h (przyjęte)';

  @override
  String get cornerClassReasonTooFewLapsWithoutBraking =>
      'mniej niż trzy okrążenia bez hamowania';

  @override
  String cornerApproachNoteNoShedReason(
    String how,
    int braked,
    int laps,
    String reason,
  ) {
    return 'Hamowanie na $braked z $laps okrążeń ($how). Nie wiadomo, czy hamowanie jest mocne: $reason.';
  }

  @override
  String get gripHeading => 'Przyczepność i balans';

  @override
  String get gripInferredBadge => 'Wnioskowane';

  @override
  String gripIntro(int count) {
    return 'Wnioskowane z zapisanych przyspieszeń, prędkości i, jeśli nagranie ją ma, prędkości odchylenia (yaw) samochodu na okrążeniach w rankingu. Nie są zapisywane ani kąt skrętu kierownicy, ani dane opon czy kół, więc te liczby mówią, jak mocno samochód pracował, a nie ile przyczepności zostało. Typowa wartość to mediana okrążeń (co najmniej $count); szczyt to najwyższa wartość spośród okrążeń.';
  }

  @override
  String get gripWorking => 'Obliczanie przyczepności i balansu…';

  @override
  String get gripUnavailable =>
      'Nieznane, dopóki okrążenia dnia nie zostaną zmierzone w segmentach.';

  @override
  String get gripBySession => 'Według sesji, przy porównywalnej prędkości';

  @override
  String gripSessionLaps(String session, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążenia w rankingu',
      many: '$count okrążeń w rankingu',
      few: '$count okrążenia w rankingu',
      one: '1 okrążenie w rankingu',
    );
    return '$session · $_temp0';
  }

  @override
  String get gripSpeedColumn => 'Prędkość';

  @override
  String get gripCornering => 'W zakręcie';

  @override
  String get gripBraking => 'Hamowanie';

  @override
  String get gripAccelerating => 'Przyspieszanie';

  @override
  String get gripExit => 'Przyspieszenie na wyjściu';

  @override
  String get gripBalance => 'Balans';

  @override
  String gripBandBelow(String speed) {
    return 'poniżej $speed';
  }

  @override
  String gripBandBetween(String low, String high) {
    return '$low–$high';
  }

  @override
  String gripBandAbove(String speed) {
    return '$speed i więcej';
  }

  @override
  String gripPeak(String value) {
    return 'szczyt $value';
  }

  @override
  String get gripTableNote =>
      'Każda komórka: typowa z najwyższych wartości okrążeń w tym zakresie prędkości oraz najwyższa wartość spośród okrążeń.';

  @override
  String gripUnitNote(String what, String unit) {
    return '$what: jednostka $unit.';
  }

  @override
  String gripAssumedNote(String what) {
    return '$what: nagranie nie podaje jednostki; przyjęto g.';
  }

  @override
  String gripFromSpeedNote(String what) {
    return '$what: ze zmiany prędkości (brak zapisanego przyspieszenia wzdłużnego), w g.';
  }

  @override
  String gripFromSpeedAssumedNote(String what) {
    return '$what: ze zmiany prędkości, w g; prędkość nie ma podanej jednostki, więc przyjęto km/h.';
  }

  @override
  String gripAnd(String first, String second) {
    return '$first i $second';
  }

  @override
  String gripNotKnownLine(String what, String reason) {
    return '$what: nieznane: $reason.';
  }

  @override
  String gripTypicalNeedsLaps(int count) {
    return 'Typowe wartości wymagają co najmniej $count okrążeń zmierzonych tak samo; gdy jest ich mniej, pokazano tylko szczyt.';
  }

  @override
  String gripLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Pominięto $count okrążenia zmierzone inaczej.',
      many: 'Pominięto $count okrążeń zmierzonych inaczej.',
      few: 'Pominięto $count okrążenia zmierzone inaczej.',
      one: 'Pominięto 1 okrążenie zmierzone inaczej.',
    );
    return '$_temp0';
  }

  @override
  String get gripByCorner => 'Według zakrętu';

  @override
  String gripCornerSummary(String what, String value) {
    return '$what $value';
  }

  @override
  String gripTypicalPeak(String typical, String peak, String lap) {
    return 'typowo $typical · szczyt $peak ($lap)';
  }

  @override
  String gripPeakOnly(String peak, String lap, int count) {
    return 'szczyt $peak ($lap); typowa wymaga $count okrążeń';
  }

  @override
  String gripBalanceTypical(String ratio) {
    return 'typowo $ratio (prędkość odchylenia ÷ to, czego wymaga zakręt)';
  }

  @override
  String gripLapCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'z $count okrążeń',
      one: 'z 1 okrążenia',
    );
    return '$_temp0';
  }

  @override
  String gripAssumedUnit(String value) {
    return '$value (przyjęto g)';
  }

  @override
  String get gripMeaningHeading => 'Co oznaczają liczby';

  @override
  String get gripMeaningCornering =>
      'W zakręcie: najwyższe przyspieszenie boczne, jakie osiągnęło każde okrążenie, w zakręcie lub w zakresie prędkości.';

  @override
  String get gripMeaningBraking =>
      'Hamowanie: najwyższe opóźnienie od punktu hamowania do najwolniejszego miejsca zakrętu (według sesji: gdziekolwiek w zakresie prędkości).';

  @override
  String get gripMeaningExit =>
      'Przyspieszenie na wyjściu: średnie przyspieszenie od najwolniejszego miejsca do końca zakrętu; poniżej zera samochód wciąż zwalniał.';

  @override
  String gripMeaningBalance(String g, String speed) {
    return 'Balans: prędkość odchylenia samochodu podzielona przez prędkość odchylenia, której wymagają siła w zakręcie i prędkość, od $g g i $speed m/s. W ustalonym zakręcie wynosi około 1 niezależnie od tego, czy samochód jest pod-, czy nadsterowny: rozróżnienie wymaga kąta skrętu kierownicy, który nie jest zapisywany. Powyżej 1 samochód obracał się szybciej, niż zakrzywiał się tor (kąt znoszenia rósł); poniżej 1 wolniej. Próbki, w których odchylenie jest przeciwne do kierunku zakrętu, są pomijane. Wymaga kanału prędkości odchylenia samego samochodu i jest wnioskowany.';
  }

  @override
  String gripReasonTooFewLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'mniej niż $count okrążenia',
      many: 'mniej niż $count okrążeń',
      few: 'mniej niż $count okrążenia',
    );
    return '$_temp0';
  }

  @override
  String get gripReasonTooFewSamples =>
      'na żadnym okrążeniu nie ma dość próbek';

  @override
  String get gripReasonNoLateral => 'nagranie nie ma przyspieszenia bocznego';

  @override
  String get gripReasonNoSpeed => 'nagranie nie ma prędkości';

  @override
  String get gripReasonUnsupportedUnit =>
      'aplikacja nie odczytuje jednostki tego kanału';

  @override
  String get gripReasonSpeedUnit => 'jednostka prędkości to nie km/h ani mph';

  @override
  String get gripReasonNoYaw => 'nagranie nie ma kanału prędkości odchylenia';

  @override
  String get gripReasonDeviceAxes =>
      'żyroskop w nagraniu mierzy osie samego rejestratora, a nie odchylenie samochodu';

  @override
  String get gripReasonYawUnit =>
      'jednostka prędkości odchylenia nie jest zapisana lub nieznana';

  @override
  String get gripReasonNotTimed => 'okrążenia nie są zmierzone w tym zakręcie';

  @override
  String get gripReasonNoMinimum =>
      'nie znaleziono najwolniejszego miejsca w zakręcie';

  @override
  String get gripReasonNoRecording => 'nagranie nie jest wczytane';

  @override
  String get gripReasonOther => 'niedostępne';

  @override
  String get gripSummary =>
      'Jak mocno samochód pracował w zakrętach, przy hamowaniu i przyspieszaniu, według sesji i zakrętu.';

  @override
  String get gripShow => 'Pokaż';

  @override
  String get gripHide => 'Ukryj';

  @override
  String gripFromSpeedValue(String value) {
    return '$value z prędkości';
  }

  @override
  String gripFromSpeedValueAssumed(String value) {
    return '$value z prędkości (przyjęto km/h)';
  }

  @override
  String gripBalanceUnitsAssumed(String text) {
    return '$text; jednostki przyjęte';
  }

  @override
  String gripBandSpeedAssumed(String band) {
    return '$band (przyjęto km/h)';
  }

  @override
  String gripCornerSummaryPeak(String what, String value) {
    return '$what szczyt $value';
  }

  @override
  String gripNoValueLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążenia w rankingu nie mają wartości',
      many: '$count okrążeń w rankingu nie ma wartości',
      few: '$count okrążenia w rankingu nie mają wartości',
      one: '1 okrążenie w rankingu nie ma wartości',
    );
    return '$_temp0';
  }

  @override
  String get gripReasonNoBraking => 'brak hamowania na żadnym okrążeniu';

  @override
  String get gripReasonNoAcceleration =>
      'brak przyspieszania na żadnym okrążeniu';

  @override
  String get gripReasonAllZero =>
      'kanał zawiera same zera (wypełniacz, a nie pomiar)';

  @override
  String get referenceTitle => 'Okrążenie odniesienia';

  @override
  String get referenceIntro =>
      'Porównaj swoje okrążenia z okrążeniem spoza tego dnia: z zapisu znajomego lub instruktora albo z jednego z Twoich wcześniejszych dni. Jest mierzone na dzisiejszej linii start/meta i trzymane osobno: nie wchodzi do rankingu, teoretycznego czasu okrążenia, postępów ani porad trenera i nie jest zapisywane w pliku dnia. Twój profil kierowcy zapamiętuje je dla tego dnia: plik zapisu jest kopiowany do profilu, a okrążenie z wcześniejszego dnia jest zapamiętywane przez ten dzień.';

  @override
  String get referenceLoadFile => 'Wczytaj zapis';

  @override
  String get referenceLoadDay => 'Z wcześniejszego dnia';

  @override
  String get referenceNeedsLap =>
      'Odniesienie jest mierzone na linii najlepszego dzisiejszego okrążenia, więc dzień potrzebuje najpierw sklasyfikowanego okrążenia.';

  @override
  String referenceLoading(String source) {
    return 'Mierzenie czasu $source na dzisiejszej linii start/meta…';
  }

  @override
  String referenceLabel(String source, int lap, String time) {
    return 'Odniesienie: $source, okrążenie $lap, $time';
  }

  @override
  String referenceDaySession(String day, String session) {
    return '$day · $session';
  }

  @override
  String referenceRefusedWrongTrack(String distance) {
    return 'Nie użyto: ten zapis pochodzi z innego toru. Jego GPS nie zbliża się do dzisiejszej linii start/meta na mniej niż $distance.';
  }

  @override
  String get referenceRefusedNoGps =>
      'Nie użyto: zapis nie ma użytecznej pozycji GPS, więc nie da się go zmierzyć na dzisiejszej linii.';

  @override
  String get referenceRefusedNoLap =>
      'Nie użyto: zapis przebiega w pobliżu dzisiejszej linii start/meta, ale żadne pełne okrążenie jej nie przecina.';

  @override
  String get referenceRefusedGate =>
      'Nie użyto: dzisiejsza linia start/meta jest nieprawidłowa.';

  @override
  String referenceFailed(String reason) {
    return 'Nie udało się odczytać odniesienia: $reason';
  }

  @override
  String get referenceDayNoRecordings =>
      'Nie znaleziono żadnego zapisu z tego dnia.';

  @override
  String get referenceCompare => 'Porównaj z najlepszym dzisiejszym okrążeniem';

  @override
  String get referenceChooseLap => 'Wybierz okrążenie';

  @override
  String get referenceClear => 'Usuń odniesienie';

  @override
  String get referenceNotSaved =>
      'Trzymane, dopóki ten dzień jest otwarty; nie jest zapamiętywane, bo ten dzień nie jest w Twoim profilu kierowcy.';

  @override
  String get referenceSaved =>
      'Zapamiętane dla tego dnia w Twoim profilu kierowcy.';

  @override
  String get referenceSavedCopy =>
      'Zapamiętane dla tego dnia w Twoim profilu kierowcy, razem z kopią zapisu.';

  @override
  String get referenceSaving => 'Zapisywanie w Twoim profilu kierowcy…';

  @override
  String referenceKeepFailed(String reason) {
    return 'Nie zapamiętano: $reason Odniesienie zostaje, dopóki ten dzień jest otwarty.';
  }

  @override
  String get referenceForgetFailed =>
      'Nie udało się usunąć odniesienia z Twojego profilu kierowcy, więc wróci po ponownym otwarciu tego dnia.';

  @override
  String get referenceKeepRetry => 'Spróbuj ponownie';

  @override
  String referenceKeepTooManyFiles(int count) {
    return 'Twój profil przechowuje już $count zapisów odniesienia. Najpierw usuń odniesienie z innego dnia.';
  }

  @override
  String referenceKeepTooMuch(int megabytes) {
    return 'Zapisy odniesienia zajęłyby w Twoim profilu ponad $megabytes MiB.';
  }

  @override
  String referenceKeepFileTooLarge(int megabytes) {
    return 'Zapis jest większy niż $megabytes MiB, czyli maksimum dla odniesienia.';
  }

  @override
  String get referenceKeepFileEmpty => 'Zapis jest pusty.';

  @override
  String get referenceKeepFileType =>
      'Można zapamiętać tylko zapis VBO lub RCZ.';

  @override
  String get referenceKeepUnreadable =>
      'Nie udało się skopiować zapisu do Twojego profilu.';

  @override
  String get referenceKeepNotWritten =>
      'Nie udało się zapisać Twojego profilu kierowcy.';

  @override
  String get referenceKeepOther =>
      'Twój profil kierowcy nie mógł tego zachować.';

  @override
  String get referenceFileMissing =>
      'Zapis zapamiętany dla tego odniesienia nie został znaleziony w Twoim profilu kierowcy. Usuń odniesienie albo wczytaj zapis ponownie.';

  @override
  String get referenceFileChanged =>
      'Zapis zapamiętany dla tego odniesienia nie jest tym plikiem, który zapisano (zmienił się). Usuń odniesienie albo wczytaj zapis ponownie.';

  @override
  String get referenceDayMissing =>
      'Dnia, z którego pochodzi to odniesienie, nie ma już w Twoim profilu kierowcy. Usuń odniesienie albo wybierz inny dzień.';

  @override
  String get referencePickDay => 'Wybierz wcześniejszy dzień';

  @override
  String get referenceNoDays => 'Twój profil nie ma jeszcze innego dnia.';

  @override
  String get referencePickLap => 'Wybierz okrążenie odniesienia';

  @override
  String referenceLapOption(String source, int lap) {
    return '$source, okrążenie $lap';
  }

  @override
  String get referenceCompareTitle => 'Względem odniesienia';

  @override
  String get referenceShort => 'Odn.';

  @override
  String get referenceDeltaExplained =>
      'Δ to A − odniesienie: wartość dodatnia oznacza stratę A.';

  @override
  String get referenceDeltaNote => '+ = A traci do odniesienia';

  @override
  String get referenceKeptApart =>
      'Odniesienie nie jest częścią tego dnia: nie wchodzi do rankingu i nie jest zapisywane w pliku dnia.';

  @override
  String get referenceGone => 'Nie wybrano okrążenia odniesienia.';

  @override
  String referenceUnits(String a, String b) {
    return 'Jednostki: A $a · odniesienie $b';
  }

  @override
  String referenceUnitAssumed(String unit) {
    return '$unit (przyjęta)';
  }

  @override
  String get referenceUnitNone => 'brak jednostki';

  @override
  String get referenceUnitsApart =>
      'Różne jednostki: pokazane osobno, nigdy nie odejmowane.';

  @override
  String referenceChartOf(String channel, String lap) {
    return '$channel · $lap';
  }

  @override
  String get referenceSegmentsTitle => 'Odcinki względem odniesienia';

  @override
  String get referenceSegmentsNone =>
      'Dzisiejsze okrążenie nie ma jeszcze odcinków do zmierzenia: zatwierdź je w przeglądzie odcinków albo poczekaj na teoretyczny czas okrążenia.';

  @override
  String get referenceSegmentsBorrowed =>
      'Odcinki teoretycznego czasu okrążenia; ich granice mogą przesunąć się o kilka metrów na tych okrążeniach.';

  @override
  String get referenceColumnSegment => 'Odcinek';

  @override
  String referenceSegmentNotTimed(String segment, String reason) {
    return '$segment: nie zmierzono na jednym z okrążeń ($reason)';
  }

  @override
  String get referenceRefusedDirection =>
      'Nie użyto: jego okrążenia na dzisiejszym torze są przejechane w przeciwnym kierunku.';

  @override
  String get referenceRefusedLayout =>
      'Nie użyto: jego okrążenia przecinają dzisiejszą linię start/meta, ale należą do innej konfiguracji toru.';

  @override
  String get referenceRefusedExcluded =>
      'Wszystkie jego okrążenia na dzisiejszym torze wykluczono w dniu, z którego pochodzą. Wybierz okrążenie, aby mimo to użyć jednego z nich.';

  @override
  String referenceLapExcluded(String reason) {
    return 'Wykluczone tamtego dnia: $reason';
  }

  @override
  String get referenceLapExcludedNoReason => 'Wykluczone tamtego dnia';

  @override
  String referenceOnlyFirstFile(String name) {
    return 'Odniesienie to jeden zapis: użyto tylko $name.';
  }

  @override
  String get referenceStale =>
      'Zmierzone na innej linii start/meta: dzisiejsza linia od tego czasu się zmieniła. Wczytaj je ponownie, aby porównać.';

  @override
  String get referenceReload => 'Wczytaj ponownie';

  @override
  String get referenceLapAOtherLine =>
      'Okrążenie A zmierzono na innej linii start/meta niż odniesienie, więc nie ma Δ okrążenia. Wybierz inne okrążenie A.';

  @override
  String referenceLowCoverage(int percent) {
    return 'Brak Δ okrążenia: okrążenie odniesienia pokrywa tylko $percent % linii okrążenia A.';
  }

  @override
  String get referenceRouteUnchecked =>
      'Dzisiejsze okrążenie nie ma trasy do porównania, więc nie sprawdzono trasy ani kierunku odniesienia: tylko dzisiejszą linię start/meta.';

  @override
  String get bpHeading => 'Optymalne fazy zakrętów';

  @override
  String get bpSummary =>
      'Najszybsze wejście, środek i wyjście z każdego zakrętu w ciągu dnia, złożone w optymalny przejazd.';

  @override
  String bpSummaryTime(String time) {
    return 'Najszybsze wejście, środek i wyjście z każdego zakrętu w ciągu dnia, złożone w optymalny przejazd: $time.';
  }

  @override
  String get bpWorking =>
      'Obliczanie wraz z teoretycznie najlepszym okrążeniem…';

  @override
  String bpUnavailable(String reason) {
    return 'Niedostępne: $reason';
  }

  @override
  String get bpIntro =>
      'Każdy zakręt jest dzielony na wejście, środek i wyjście wokół jego najciaśniejszego miejsca. Każda faza pochodzi z tego okrążenia w rankingu, na którym została przejechana najszybciej. Proste oraz zakręty, których nie można podzielić na fazy, są brane w całości z najszybszego przejazdu danego odcinka. Okrążenia spoza rankingu są pomijane.';

  @override
  String get bpIncomplete =>
      'Nie można obliczyć sumy: dla co najmniej jednej fazy brakuje czasu ze wszystkich okrążeń w rankingu.';

  @override
  String get bpLoses => 'Strata';

  @override
  String get bpBestsTitle => 'Porównanie z teoretycznym optimum';

  @override
  String bpTotalNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Suma najszybszych czasów poszczególnych faz, pochodzących z $_temp0. Nie wszystkie przejścia między fazami muszą być fizycznie możliwe.';
  }

  @override
  String get bpRawNote =>
      'Ta sama metoda, ale z użyciem całych odcinków zamiast faz zakrętów.';

  @override
  String get bpJoinedLabel => 'Realistyczne optimum faz';

  @override
  String bpJoinedNote(String tolerance, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Szacowany czas złożony z najszybszych faz, dla których prędkość na przejściu między dwoma okrążeniami różni się najwyżej o $tolerance. Warunek jest sprawdzany także na granicach faz wewnątrz zakrętów. Złożone z $_temp0.';
  }

  @override
  String get bpJoinedNoJoin =>
      'Niedostępne: wszystkie fazy mają zmierzony czas, ale nie da się ich połączyć z zachowaniem zgodnej prędkości na granicach.';

  @override
  String get bpRealisticNote =>
      'Ta sama metoda, ale z użyciem całych odcinków zamiast faz zakrętów.';

  @override
  String get bpTypicalNote =>
      'Inna metoda: najszybszy typowy czas każdego odcinka w pojedynczej sesji, liczony jako mediana. Pokazuje to, co zwykle osiągasz w danym miejscu, a nie pojedynczy najlepszy przejazd. Zakręty nie są dzielone na fazy.';

  @override
  String get bpJoinsTitle => 'Ciągłość między fazami';

  @override
  String get bpJoinsNone =>
      'Wszystkie fazy pochodzą z jednego okrążenia — nie ma przejść między różnymi okrążeniami do sprawdzenia.';

  @override
  String bpJoinsAll(int count, String tolerance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'wszystkich $count granicach',
      one: 'jedynej granicy',
    );
    return 'Na $_temp0 między fazami pochodzącymi z różnych okrążeń różnica prędkości nie przekracza $tolerance.';
  }

  @override
  String bpJoinsApart(int apart, int count, String tolerance) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count granic',
      one: '1 granicy',
    );
    return 'Na $apart z $_temp0 między fazami pochodzącymi z różnych okrążeń różnica prędkości przekracza $tolerance. W tych miejscach złożone optimum nie odpowiada przejazdowi, który samochód mógłby wykonać w tej postaci.';
  }

  @override
  String bpJoinApart(String where, String difference) {
    return '$where: różnica prędkości $difference';
  }

  @override
  String bpJoinsUnknown(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count granic',
      one: 'Jednej granicy',
    );
    return '$_temp0 nie można było sprawdzić, ponieważ na jednym z okrążeń brakuje prędkości w znanej jednostce.';
  }

  @override
  String get bpJoinsNote =>
      'Zgodna prędkość na granicy faz jest warunkiem koniecznym, ale nie gwarantuje, że fazy da się połączyć w rzeczywistym przejeździe — dwa okrążenia mogą mieć tę samą prędkość, ale inną linię jazdy.';

  @override
  String get bpByPart => 'Faza po fazie';

  @override
  String bpBest(String time, String lap) {
    return 'Najlepiej: $time s · $lap';
  }

  @override
  String get bpNoTime => 'Brak zmierzonego czasu na tym odcinku';

  @override
  String bpLapTime(String time) {
    return 'To okrążenie: $time s';
  }

  @override
  String get bpLapSetIt => 'Najlepszy czas tej fazy pochodzi z tego okrążenia';

  @override
  String get bpLapNotTimed => 'Brak czasu tej fazy na tym okrążeniu';

  @override
  String bpDoesNotJoin(String difference) {
    return 'Brak ciągłości z poprzednią fazą: różnica prędkości $difference';
  }

  @override
  String get bpWhole => 'Cały odcinek';

  @override
  String get bpPiecesNote =>
      'Optymalne fazy pochodzą z różnych okrążeń, więc nie tworzą jednego rzeczywiście zarejestrowanego okrążenia. Z tego powodu są porównywane faza po fazie i nie mogą służyć jako okrążenie odniesienia.';

  @override
  String get bpRawNever =>
      'Optimum z faz nigdy nie będzie wolniejsze: wejście, środek i wyjście zakrętu mogą pochodzić z trzech różnych okrążeń.';

  @override
  String get bpJoinedNever =>
      'Realistyczne optimum faz nigdy nie będzie wolniejsze od wariantu złożonego z całych, zgodnych odcinków.';

  @override
  String get bpSpeedAssumed =>
      'Prędkości bez zapisanej jednostki są interpretowane jako km/h.';

  @override
  String get brakingTechniqueTitle => 'Technika hamowania';

  @override
  String brakingTechniqueFromG(String rate) {
    return 'Na podstawie kanału przyspieszenia wzdłużnego ($rate Hz) z klasyfikowanych okrążeń tego dnia.';
  }

  @override
  String brakingTechniqueFromGAssumed(String rate) {
    return 'Na podstawie kanału przyspieszenia wzdłużnego ($rate Hz, bez zapisanej jednostki — przyjęto g) z klasyfikowanych okrążeń tego dnia.';
  }

  @override
  String brakingTechniqueFromSpeed(String rate, String why) {
    return 'Na podstawie prędkości ($rate Hz); jej zmiana jest wygładzana w oknie 0,5 s. Dane z klasyfikowanych okrążeń tego dnia: $why. Wartości nie są bezpośrednio porównywalne z wyznaczonymi z kanału przeciążenia.';
  }

  @override
  String get brakingTechniqueNoGChannel =>
      'brak kanału przyspieszenia wzdłużnego';

  @override
  String get brakingTechniqueGChannelEmpty =>
      'kanał przyspieszenia wzdłużnego nie zawiera danych';

  @override
  String get brakingTechniqueHit => 'Tempo narastania hamowania';

  @override
  String get brakingTechniquePeak => 'Maksymalne opóźnienie';

  @override
  String get brakingTechniqueTrail => 'Trail braking · wyznaczone pośrednio';

  @override
  String get brakingTechniqueRelease => 'Tempo odpuszczania hamulca';

  @override
  String get brakingTechniqueBrakeToThrottle => 'Przejście z hamulca na gaz';

  @override
  String get brakingTechniquePedal => 'Praca pedałem hamulca';

  @override
  String brakingTechniqueThisLap(String value) {
    return 'To okrążenie: $value';
  }

  @override
  String brakingTechniqueThisLapUnknown(String reason) {
    return 'To okrążenie: brak danych ($reason)';
  }

  @override
  String brakingTechniqueTypical(String value, int laps) {
    String _temp0 = intl.Intl.pluralLogic(
      laps,
      locale: localeName,
      other: 'typowo $value ($laps okrążenia)',
      many: 'typowo $value ($laps okrążeń)',
      few: 'typowo $value ($laps okrążenia)',
      one: 'typowo $value (1 okrążenie)',
    );
    return '$_temp0';
  }

  @override
  String brakingTechniqueTypicalUnknown(String reason) {
    return 'typowo: brak danych ($reason)';
  }

  @override
  String brakingTechniquePeakWhere(String after, String zone) {
    return 'Maksymalne opóźnienie po $after s od początku hamowania; cała strefa hamowania trwa $zone s.';
  }

  @override
  String get brakingTechniquePeakEarly =>
      'Maksymalne opóźnienie zwykle pojawia się w pierwszej 1/3 czasu hamowania.';

  @override
  String get brakingTechniquePeakMiddle =>
      'Maksymalne opóźnienie zwykle pojawia się w środkowej 1/3 czasu hamowania.';

  @override
  String get brakingTechniquePeakLate =>
      'Maksymalne opóźnienie zwykle pojawia się w ostatniej 1/3 czasu hamowania.';

  @override
  String get brakingTechniqueTrailNote =>
      'Hamowanie utrzymywane przy przeciążeniu bocznym co najmniej 0,3 g. Wyznaczone pośrednio, ponieważ zapis nie zawiera kąta skrętu kierownicy.';

  @override
  String brakingTechniqueThrottleNote(String rate, String error) {
    return 'Czas od końca hamowania do ponownego dodania gazu. Pomiar kończy się przy kolejnym hamowaniu lub po maksymalnie 4 s. Kanał gazu jest zapisywany z częstotliwością $rate Hz, więc moment dodania gazu ma dokładność około $error s.';
  }

  @override
  String brakingTechniquePedalSlow(String rate) {
    return 'Brak wiarygodnej wartości: kanał hamulca ma zbyt niską częstotliwość ($rate Hz). Pozwala określić, kiedy hamowanie trwa, ale nie tempo ruchu pedału, dlatego wartości narastania i odpuszczania wyżej są wyznaczane z opóźnienia samochodu.';
  }

  @override
  String brakingTechniqueUnavailable(String reason) {
    return 'Brak danych: $reason';
  }

  @override
  String brakingTechniqueBrakingLaps(int braked, int laps) {
    return 'Hamowanie wystąpiło na $braked z $laps okrążeń.';
  }

  @override
  String brakingTechniqueOtherSource(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięto $count okrążenia zmierzonego inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      many:
          'Pominięto $count okrążeń zmierzonych inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      few:
          'Pominięto $count okrążenia zmierzone inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      one: 'Pominięto 1 okrążenie zmierzone inaczej (z kanału G lub z prędkości albo w innej jednostce).',
    );
    return '$_temp0';
  }

  @override
  String get brakingTechniqueNote =>
      'Początek i koniec hamowania są wyznaczane względem opóźnienia 0,15 g, po wcześniejszym wykryciu hamowania od 0,30 g. Tempo narastania mierzy wzrost opóźnienia do 85% wartości maksymalnej, licząc od ostatniej chwili poniżej 25% maksimum (ale nie mniej niż 0,15 g). Dzięki temu toczenie lub lekkie odjęcie gazu przed właściwym hamowaniem nie zawyża wyniku. Tempo odpuszczania jest liczone analogicznie podczas spadku od 85% maksimum. Obie metryki wymagają maksymalnego opóźnienia co najmniej 0,40 g i kanału o częstotliwości około 10 Hz lub większej. Przy wyznaczaniu z prędkości wartości szybsze, niż pozwala wykazać wygładzanie 0,5 s, są oznaczane jako „co najmniej”. Wartość typowa to mediana z co najmniej trzech okrążeń.';

  @override
  String brakingTechniqueReasonTooSlow(String rate) {
    return 'kanał zbyt wolny ($rate Hz)';
  }

  @override
  String brakingTechniqueReasonBrakeTooSlow(String rate) {
    return 'kanał hamulca zbyt wolny ($rate Hz)';
  }

  @override
  String brakingTechniqueReasonLateralTooSlow(String rate) {
    return 'kanał przeciążenia bocznego zbyt wolny ($rate Hz)';
  }

  @override
  String get brakingTechniqueReasonNoDeceleration =>
      'brak zapisu przyspieszenia wzdłużnego i prędkości';

  @override
  String get brakingTechniqueReasonNoBraking => 'brak hamowania w tym miejscu';

  @override
  String get brakingTechniqueReasonGap => 'przerwa w zapisie';

  @override
  String get brakingTechniqueReasonTruncated =>
      'hamowanie trwa dłużej niż zapis';

  @override
  String get brakingTechniqueReasonTooLight =>
      'maksymalne opóźnienie poniżej 0,40 g';

  @override
  String get brakingTechniqueReasonTooQuick =>
      'zmiana zbyt szybka względem częstotliwości próbkowania';

  @override
  String get brakingTechniqueReasonNoLateral =>
      'brak kanału przeciążenia bocznego';

  @override
  String get brakingTechniqueReasonLateralEmpty =>
      'kanał przeciążenia bocznego nie zawiera danych';

  @override
  String get brakingTechniqueReasonNoThrottle => 'brak kanału gazu';

  @override
  String get brakingTechniqueReasonNoBrake => 'brak kanału pedału hamulca';

  @override
  String get brakingTechniqueDayTitle => 'Technika hamowania';

  @override
  String brakingTechniqueDaySummary(
    int corners,
    String source,
    String figures,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      corners,
      locale: localeName,
      other: 'Typowe wartości z $corners zakrętów',
      one: 'Typowa wartość z 1 zakrętu',
    );
    return '$_temp0, $source: $figures.';
  }

  @override
  String get brakingTechniqueDayFromG => 'z przyspieszenia wzdłużnego';

  @override
  String get brakingTechniqueDayFromSpeed => 'z prędkości';

  @override
  String brakingTechniqueDayHit(String value) {
    return 'narastanie $value';
  }

  @override
  String brakingTechniqueDayRelease(String value) {
    return 'odpuszczanie $value';
  }

  @override
  String brakingTechniqueDayTrail(String value) {
    return 'trail braking $value (wyznaczone pośrednio)';
  }

  @override
  String brakingTechniqueDayThrottle(String value) {
    return 'hamulec → gaz $value';
  }

  @override
  String get brakingTechniqueDayNote =>
      'Wybierz zakręt powyżej, aby zobaczyć hamowanie na poszczególnych okrążeniach.';

  @override
  String brakingTechniqueFromSpeedAssumed(
    String rate,
    String unit,
    String why,
  ) {
    return 'Na podstawie prędkości ($rate Hz, bez zapisanej jednostki — przyjęto $unit); jej zmiana jest wygładzana w oknie 0,5 s. Dane z klasyfikowanych okrążeń tego dnia: $why. Wartości nie są bezpośrednio porównywalne z wyznaczonymi z kanału przeciążenia.';
  }

  @override
  String brakingTechniqueAtLeast(String value) {
    return 'co najmniej $value';
  }

  @override
  String brakingTechniqueAbout(String value) {
    return 'około $value';
  }

  @override
  String get brakingTechniqueLateralAssumed =>
      'Kanał przeciążenia bocznego nie ma zapisanej jednostki — przyjęto g.';

  @override
  String get brakingTechniqueThrottleAssumed =>
      'Kanał gazu nie ma zapisanej jednostki — przyjęto %.';

  @override
  String get brakingTechniqueThrottleScaleInferred =>
      'Kanał gazu ma zakres 0–1 — został przeliczony na 0–100%.';

  @override
  String get brakingTechniqueBrakeAssumed =>
      'Kanał hamulca nie ma zapisanej jednostki — przyjęto %.';

  @override
  String get brakingTechniqueBrakeScaleInferred =>
      'Kanał hamulca ma zakres 0–1 — został przeliczony na 0–100%.';

  @override
  String get brakingTechniqueReasonBrakingAgain =>
      'kolejne hamowanie przed ponownym dodaniem gazu';

  @override
  String get brakingTechniqueReasonCoasting =>
      'brak ponownego dodania gazu w ciągu 4 s od końca hamowania';

  @override
  String get brakingTechniqueReasonBrakeResampled =>
      'kanał hamulca z OBD został przeliczony do częstotliwości zapisu; jego rzeczywista częstotliwość próbkowania jest nieznana';

  @override
  String get brakingTechniqueDayFromGAssumed =>
      'z przyspieszenia wzdłużnego (bez zapisanej jednostki: odczytane jako g)';

  @override
  String brakingTechniqueDayFromSpeedAssumed(String unit) {
    return 'z prędkości (bez zapisanej jednostki: odczytane jako $unit)';
  }

  @override
  String brakingTechniqueDayOtherSource(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięto $count zakrętu zmierzonego inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      many:
          'Pominięto $count zakrętów zmierzonych inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      few:
          'Pominięto $count zakręty zmierzone inaczej (z kanału G lub z prędkości albo w innej jednostce).',
      one: 'Pominięto 1 zakręt zmierzony inaczej (z kanału G lub z prędkości albo w innej jednostce).',
    );
    return '$_temp0';
  }

  @override
  String brakingTechniqueSpeedAssumed(String unit) {
    return 'Prędkość nie ma zapisanej jednostki — odległości są wyznaczane przy założeniu $unit.';
  }

  @override
  String brakingTechniqueSubsetBraked(int laps, int braking) {
    return 'Wartość dostępna dla $laps z $braking okrążeń z hamowaniem; na pozostałych wystąpiło kolejne hamowanie przed dodaniem gazu albo samochód pozostał bez gazu.';
  }

  @override
  String brakingTechniqueSubsetOther(int laps, int braking, String reason) {
    return 'Wartość dostępna dla $laps z $braking okrążeń z hamowaniem; dla pozostałych brak wyniku: $reason.';
  }

  @override
  String brakingTechniqueDayMinority(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Pominięto $count zakrętu w wartości opartej na mniej niż połowie jego okrążeń z hamowaniem.',
      many:
          'Pominięto $count zakrętów w wartości opartej na mniej niż połowie ich okrążeń z hamowaniem.',
      few:
          'Pominięto $count zakręty w wartości opartej na mniej niż połowie ich okrążeń z hamowaniem.',
      one: 'Pominięto 1 zakręt w wartości opartej na mniej niż połowie jego okrążeń z hamowaniem.',
    );
    return '$_temp0';
  }

  @override
  String get lapStylesHeading => 'Style jazdy';

  @override
  String get lapStylesInferredBadge => 'Wyznaczone';

  @override
  String get lapStylesSummary =>
      'Okrążenia z rankingu pogrupowane według sposobu hamowania i operowania gazem, wraz z najlepszym okrążeniem każdej grupy.';

  @override
  String get lapStylesShow => 'Pokaż';

  @override
  String get lapStylesHide => 'Ukryj';

  @override
  String lapStylesIntro(int count) {
    return 'Każde okrążenie z rankingu jest porównywane z typowym przejazdem dnia w każdym zakręcie: punktem rozpoczęcia hamowania, punktem ponownego dodania gazu oraz prędkością w zakręcie. Grupa opisuje, jak dane okrążenia były przejeżdżane względem pozostałych, ale nie wskazuje przyczyny lepszego czasu — sama przynależność do stylu nie oznacza, że ten styl był szybszy. Wartość typowa jest medianą z okrążeń dnia i wymaga co najmniej $count okrążeń.';
  }

  @override
  String get lapStylesWorking => 'Analizowanie stylów jazdy…';

  @override
  String get lapStylesUnavailable =>
      'Niedostępne, dopóki okrążenia dnia nie zostaną zmierzone na odcinkach.';

  @override
  String lapStylesTooFewLaps(int count) {
    return 'Analiza stylu jazdy wymaga co najmniej $count okrążeń w rankingu.';
  }

  @override
  String lapStylesTooFewCorners(int count) {
    return 'W mniej niż $count zakrętach punkt hamowania lub ponownego dodania gazu jest dostępny na wystarczającej liczbie okrążeń. Za mało danych, aby pogrupować okrążenia według stylu jazdy.';
  }

  @override
  String lapStylesBasis(int grouped, int timed, int corners) {
    return 'Pogrupowano $grouped z $timed mierzonych okrążeń. Pominięto okrążenia wyjazdowe, zjazdowe, wykluczone oraz zawierające problemy z danymi. Porównane zakręty: $corners.';
  }

  @override
  String get lapStylesFewLaps =>
      'W poszczególnych grupach jest mało okrążeń, a wraz z poznawaniem toru tempo w ciągu dnia może rosnąć. Grupy mogą więc mieszać rzeczywisty styl jazdy z efektem nauki toru. Traktuj je jako wskazówkę do analizy, nie jako ocenę skuteczności danego stylu.';

  @override
  String lapStylesBestLine(String lap, String time, String style) {
    return 'Najlepsze okrążenie dnia — $lap ($time) — należy do grupy „$style”.';
  }

  @override
  String get lapStyleConservative => 'Wcześniejsze hamowanie, późniejszy gaz';

  @override
  String get lapStyleLateBraking => 'Późne hamowanie';

  @override
  String get lapStyleEarlyThrottle => 'Wczesny gaz';

  @override
  String get lapStyleMixed => 'Styl mieszany';

  @override
  String get lapStyleTypical => 'Styl typowy';

  @override
  String get lapStyleOutlier => 'Okrążenia nietypowe';

  @override
  String get lapStylesRulesHeading => 'Zasady klasyfikacji';

  @override
  String get lapStylesRuleConservative =>
      'Wcześniejsze hamowanie, późniejszy gaz: w większości zakrętów hamowanie zaczyna się wcześniej, a gaz jest ponownie dodawany później niż typowo.';

  @override
  String get lapStylesRuleLateBraking =>
      'Późne hamowanie: w większości zakrętów hamowanie zaczyna się później niż typowo.';

  @override
  String get lapStylesRuleEarlyThrottle =>
      'Wczesny gaz: w większości zakrętów gaz jest ponownie dodawany wcześniej niż typowo.';

  @override
  String get lapStylesRuleMixed =>
      'Styl mieszany: połączenie późnego hamowania i wczesnego gazu albo niespójny wzorzec między zakrętami — np. późniejsze hamowanie z późniejszym gazem, wczesny gaz z wcześniejszym hamowaniem lub tylko jedna z cech stylu zachowawczego.';

  @override
  String get lapStylesRuleTypical =>
      'Styl typowy: żaden z pozostałych wzorców nie dominuje.';

  @override
  String get lapStylesRuleOutlier =>
      'Okrążenia nietypowe: punkty hamowania lub dodania gazu wyraźnie odbiegają od typowych w większości zakrętów albo dostępnych jest za mało zmierzonych zakrętów do wiarygodnej klasyfikacji — minimum to 3 lub połowa porównywanych zakrętów, jeśli ta liczba jest większa.';

  @override
  String lapStylesRuleThresholds(
    String brake,
    String throttle,
    String speed,
    String factor,
    int corners,
  ) {
    return '„Wcześniej” lub „później” oznacza różnicę większą niż $brake m dla punktu hamowania i $throttle m dla punktu dodania gazu. Kanał gazu z OBD odświeża się około dwa razy na sekundę. „Szybciej” lub „wolniej” oznacza różnicę większą niż $speed% typowej prędkości. „Większość” oznacza ponad połowę zmierzonych zakrętów i co najmniej $corners. „Wyraźnie odbiega” oznacza $factor razy większą różnicę od podanych progów. Sama prędkość nie decyduje o klasyfikacji stylu, ponieważ zależy również od ogólnego tempa okrążenia.';
  }

  @override
  String lapStylesGroupTitle(String style, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążenia',
      many: '$count okrążeń',
      few: '$count okrążenia',
      one: '1 okrążenie',
    );
    return '$style · $_temp0';
  }

  @override
  String lapStylesGroupBest(String lap, String time) {
    return 'Najlepsze: $lap · $time';
  }

  @override
  String get lapStylesGroupIsDayBest => 'najlepsze okrążenie dnia';

  @override
  String lapStylesGroupBehind(String delta) {
    return '$delta względem najlepszego okrążenia dnia';
  }

  @override
  String lapStylesGroupTypical(String time) {
    return 'typowy czas: $time';
  }

  @override
  String lapStylesGroupTypicalNeeds(int count) {
    return 'typowy czas wymaga co najmniej $count okrążeń';
  }

  @override
  String lapStylesGroupQuickerHalf(int count, int total) {
    return '$count z $total okrążeń należy do szybszej połowy dnia';
  }

  @override
  String lapStylesBestAgainst(String lap) {
    return '$lap względem typowych wartości dnia w każdym zakręcie';
  }

  @override
  String get lapStylesLapsHeading => 'Okrążenia w tej grupie';

  @override
  String get lapStylesBrakeName => 'Punkt hamowania';

  @override
  String get lapStylesThrottleName => 'Punkt ponownego dodania gazu';

  @override
  String get lapStylesMinimumName => 'Prędkość minimalna';

  @override
  String get lapStylesExitName => 'Prędkość na wyjściu';

  @override
  String lapStylesNotMeasured(String what) {
    return '$what: brak pomiaru na tym okrążeniu';
  }

  @override
  String lapStylesBrakeLine(
    int earlier,
    int later,
    int measured,
    String median,
  ) {
    return 'Punkt hamowania: wcześniej w $earlier, później w $later z $measured zakrętów; mediana: $median';
  }

  @override
  String lapStylesThrottleLine(
    int earlier,
    int later,
    int measured,
    String median,
  ) {
    return 'Ponowne dodanie gazu: wcześniej w $earlier, później w $later z $measured zakrętów; mediana: $median';
  }

  @override
  String lapStylesSpeedLine(
    String what,
    int faster,
    int slower,
    int measured,
    String median,
  ) {
    return '$what: szybciej w $faster, wolniej w $slower z $measured zakrętów; mediana: $median';
  }

  @override
  String lapStylesMedianMetresEarlier(int count) {
    return '$count m wcześniej';
  }

  @override
  String lapStylesMedianMetresLater(int count) {
    return '$count m później';
  }

  @override
  String lapStylesMedianFaster(String value) {
    return '$value szybciej';
  }

  @override
  String lapStylesMedianSlower(String value) {
    return '$value wolniej';
  }

  @override
  String get lapStylesMedianSame => 'bez istotnej różnicy';

  @override
  String lapStylesOutlierUnlike(int extreme, int compared) {
    return 'Okrążenie wyraźnie różni się od pozostałych: punkt hamowania lub dodania gazu mocno odbiega od typowego w $extreme z $compared zakrętów.';
  }

  @override
  String lapStylesOutlierFew(int compared, int needed) {
    String _temp0 = intl.Intl.pluralLogic(
      compared,
      locale: localeName,
      other: 'w $compared zakrętach',
      one: 'w 1 zakręcie',
    );
    return 'Dane dostępne tylko $_temp0; do oceny stylu jazdy potrzeba co najmniej $needed.';
  }

  @override
  String get lapStylesBrakeNote =>
      'Punkty hamowania są wyznaczane z przyspieszenia wzdłużnego, a gdy go brakuje — ze zmian prędkości. Kanał pedału hamulca nie jest do tego używany, ponieważ zapis z OBD odświeża się tylko około dwa razy na sekundę.';

  @override
  String get lapStylesNoBraking =>
      'Nie można wyznaczyć punktu hamowania: zapis nie zawiera przyspieszenia wzdłużnego ani prędkości w znanej jednostce. Kanał pedału hamulca nie jest używany do klasyfikacji stylu jazdy.';

  @override
  String lapStylesBrakeUnitAssumed(String units) {
    return 'Przyspieszenie lub prędkość użyte do wyznaczenia punktów hamowania nie mają zapisanej jednostki — przyjęto $units.';
  }

  @override
  String get lapStylesSpeedUnitMissing =>
      'Kanał prędkości nie ma zapisanej jednostki, dlatego wartości są wyświetlane bez jednostki.';

  @override
  String lapStylesSpeedUnitAssumed(String units) {
    return 'Kanał prędkości nie ma zapisanej jednostki — użyto jednostki ustawionej w aplikacji: $units.';
  }

  @override
  String lapStylesTypicalNote(int count) {
    return 'Typowa wartość dla zakrętu to mediana z co najmniej $count pogrupowanych okrążeń zmierzonych w ten sam sposób. Porównywane okrążenie również wchodzi do tej mediany, dlatego jego różnica względem wartości typowej jest nieznacznie zmniejszona. Okrążenia z sesji, w których dany kanał lub jednostka zostały zapisane inaczej, nie są łączone z pozostałymi, więc wartość typowa może bazować na mniejszej liczbie okrążeń niż cała grupa. „Szybsza połowa” obejmuje szybszą połowę pogrupowanych okrążeń, zaokrągloną w górę, wraz z okrążeniami o czasie równym ostatniemu zakwalifikowanemu.';
  }
}
