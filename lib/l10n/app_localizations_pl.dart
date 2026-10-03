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
  String get settings => 'Ustawienia';

  @override
  String get settingsSpeedUnitHeading =>
      'Jednostka dla prędkości bez oznaczenia';

  @override
  String get settingsSpeedUnitHelp =>
      'Używana tylko dla nagrań, które nie podają jednostki prędkości. Jednostka podana w nagraniu jest zawsze pokazywana tak, jak ją zapisano. Wartości nigdy nie są przeliczane.';

  @override
  String get speedUnitNone => 'Brak';

  @override
  String get settingsNoDayOpen => 'Nie otwarto jeszcze żadnego dnia.';

  @override
  String settingsDeclaredUnits(String units) {
    return 'Nagrania otwartego dnia podają $units.';
  }

  @override
  String get unitsAnd => ' i ';

  @override
  String get settingsAllUnlabelled =>
      'Jego nagrania nie podają jednostki prędkości.';

  @override
  String settingsSomeUnlabelled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count z jego nagrań nie podaje jednostki prędkości.',
      few: '$count z jego nagrań nie podają jednostki prędkości.',
      one: '1 z jego nagrań nie podaje jednostki prędkości.',
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
      'FlappedEar Telemetry jest udostępniana na licencji Apache License 2.0.\nMapy © współtwórcy OpenStreetMap (ODbL) i © MapTiler.';

  @override
  String get coachTitle => 'Następna sesja';

  @override
  String coachSubtitle(String session) {
    return 'Wskazówki dla: $session, na tle szybszych okrążeń dnia';
  }

  @override
  String get coachLoading => 'Przygotowywane po idealnym okrążeniu…';

  @override
  String coachFailed(String error) {
    return 'Nie udało się uruchomić trenera: $error';
  }

  @override
  String get coachNoTheoreticalBest =>
      'Trener potrzebuje idealnego okrążenia, którego nie udało się obliczyć.';

  @override
  String get coachSpeedHidden =>
      'Prędkości nie są pokazane: jednostki prędkości w nagraniach się różnią lub trener przeliczył je na km/h, a prędkości nigdy nie są pokazywane po przeliczeniu ani w różnych jednostkach naraz.';

  @override
  String get coachLabel => 'Sugestia trenera';

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
      'Sugestie trenera opierają się na regułach DrivingCoach i wskazują możliwość, a nie obiecany zysk. Obszary poniżej to obserwacje.';

  @override
  String get coachKindEarlyLift => 'Spróbuj później odjąć gaz';

  @override
  String get coachKindExcessiveCoasting => 'Mniej jazdy bez pedałów';

  @override
  String get coachKindLowMinimumSpeed =>
      'Zachowaj więcej prędkości w najwolniejszym punkcie';

  @override
  String get coachKindLateThrottle => 'Wcześniej wróć na gaz';

  @override
  String get coachKindImproving => 'Utrzymaj obecny sposób jazdy';

  @override
  String coachItemTitle(String segment, String label) {
    return '$segment · $label';
  }

  @override
  String get coachActionEarlyLift =>
      'Spróbuj odjąć gaz nieco później, w ramach dojazdu, który już się sprawdził. Nie zmieniaj punktu hamowania.';

  @override
  String get coachActionExcessiveCoasting =>
      'Skróć odcinek bez wciśniętego pedału. Skup się na płynnym przejściu między pedałami. Nie zmieniaj punktu hamowania.';

  @override
  String get coachActionLowMinimumSpeed =>
      'Powtórz tor jazdy i dojazd z szybszych okrążeń, celując w płynniejszą fazę najmniejszej prędkości. Sprawdzaj się po wyjściu z zakrętu.';

  @override
  String get coachActionLateThrottle =>
      'Dąż do płynnego, nieco wcześniejszego powrotu na gaz po najwolniejszym punkcie, wzorując się na szybszych okrążeniach.';

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
  String coachMeasuredImproving(String metric, String before, String after) {
    return '$metric: poprawa na trzech kolejnych okrążeniach, z $before do $after, bez utraty prędkości na wyjściu.';
  }

  @override
  String get coachMetricLiftPoint => 'Punkt odjęcia gazu';

  @override
  String get coachMetricLongestCoast => 'Najdłuższa jazda bez pedałów';

  @override
  String get coachMetricMinimumSpeed => 'Najmniejsza prędkość';

  @override
  String get coachMetricThrottleReturn => 'Powrót na gaz';

  @override
  String get coachMetricSegmentTime => 'Czas odcinka';

  @override
  String get coachMetricExitSpeed => 'Prędkość na wyjściu';

  @override
  String get coachMetricBrakingStart => 'Początek hamowania';

  @override
  String get coachMetricCoastDistance => 'Dystans bez pedałów';

  @override
  String get coachReasonReady =>
      'Na następny wyjazd wybierz jedną rzecz naraz.';

  @override
  String get coachReasonNoSegments =>
      'Trener najpierw potrzebuje odcinków i czasów sektorów dnia.';

  @override
  String coachReasonNoLapInGroup(String session) {
    return '$session nie ma mierzonego okrążenia wśród porównywanych okrążeń.';
  }

  @override
  String get coachReasonNoCorners =>
      'Porównywane okrążenia nie mają zatwierdzonego zakrętu.';

  @override
  String coachReasonNoRecording(String session) {
    return 'Nagranie $session jest niedostępne, więc trener nie może jej ocenić.';
  }

  @override
  String coachReasonNoCornerMeasurements(String session) {
    return 'Żadnego okrążenia $session nie udało się zmierzyć w zakręcie.';
  }

  @override
  String coachReasonNoFasterLap(String session) {
    return 'Żadne okrążenie $session nie ma szybszego okrążenia dnia do porównania.';
  }

  @override
  String get coachReasonNoPedals =>
      'Gaz i hamulec nie są rejestrowane, więc nie da się porównać odjęcia gazu, jazdy bez pedałów i powrotu na gaz, a prędkości nie pokazują powtarzalnego wzorca.';

  @override
  String get coachReasonNoPattern =>
      'Na tle szybszych okrążeń nie wyróżnia się żaden wzorzec.';

  @override
  String coachReasonTooFewLaps(String session) {
    return 'Wzorzec pojawił się na mniej niż trzech okrążeniach $session, to za mało do planu.';
  }

  @override
  String get coachReasonBelowThreshold =>
      'Żaden powtarzalny wzorzec nie jest na tyle wyraźny, by sugerować zmianę.';

  @override
  String get coachWhyAffected => 'Okrążenia tej sesji';

  @override
  String get coachWhyFaster => 'Porównane szybsze okrążenia';

  @override
  String get coachWhyBefore => 'Pierwsze z trzech okrążeń';

  @override
  String coachWhyValues(String observed, String reference) {
    return '$observed wobec $reference';
  }

  @override
  String coachWhySupport(String score) {
    return 'Wsparcie $score z 0.9. Ostrożna ocena, jak dobrze okrążenia potwierdzają wzorzec, a nie prawdopodobieństwo.';
  }

  @override
  String coachWhyMap(String segment) {
    return 'Ślad najlepszego okrążenia z wyróżnionym: $segment';
  }

  @override
  String get appleMapLegal => 'Informacje prawne';

  @override
  String get daySectionDay => 'Dzień';

  @override
  String get daySectionLaps => 'Okrążenia';

  @override
  String get daySectionCompare => 'Porównaj';

  @override
  String get compareIntro =>
      'Dwa okrążenia obok siebie: gdzie jedno zyskuje, a gdzie traci czas, segment po segmencie i zakręt po zakręcie.';

  @override
  String get compareNeedsTwoLaps =>
      'Do porównania potrzebne są dwa sklasyfikowane okrążenia jednego toru.';

  @override
  String get comparePickTwoLaps => 'Wybierz dwa okrążenia';

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
  String get theoreticalBestLabel => 'Teoretycznie najlepsze';

  @override
  String get theoreticalBestHint => 'Najszybszy czas każdego segmentu';

  @override
  String get dayResultsTitle => 'Wyniki dnia';

  @override
  String get addRecordings => 'Dodaj nagrania';

  @override
  String get dayReport => 'Raport dnia';

  @override
  String get moreActions => 'Więcej';

  @override
  String get saveAs => 'Zapisz jako…';

  @override
  String get addingRecordings => 'Dodawanie nagrań';

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
      'Poczekaj, aż nagrania zostaną dodane, a potem wyszukaj pozostałe.';

  @override
  String get saveThenFindRecordings =>
      'Najpierw zapisz dzień, a potem wyszukaj jego nagrania.';

  @override
  String get recordingsAddedMeanwhile =>
      'W międzyczasie dodano nagrania. Wyszukaj nagrania ponownie.';

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
  String get findRecordingsInFolder => 'Znajdź nagrania w folderze…';

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
  String get tapToOpenLap => 'Dotknij, aby otworzyć okrążenie.';

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
    return 'typowo $time';
  }

  @override
  String get circuitNotIdentified =>
      'Nie udało się rozpoznać toru, więc jej okrążenia nie są porównywane.';

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
  String get bestOfDay => 'Najlepsze z dnia';

  @override
  String bestOfSession(String session) {
    return 'Najlepsze: $session';
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
  String get noStartFinishPass => 'Brak przejazdu przez linię start/meta';

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
    return '$session · WYJAZD';
  }

  @override
  String inLapName(String session) {
    return '$session · ZJAZD';
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
      'Brak daty i godziny nagrania; pokazano je po nagraniach z datą, w kolejności importu.';

  @override
  String get noteNoPasses =>
      'Brak pewnych przejazdów przez linię start/meta; rodzaj okrążenia jest nieznany.';

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
  String get lapIssueIncompleteGps => 'Niepełny GPS';

  @override
  String get lapIssueInvalidGps => 'Błędny GPS';

  @override
  String get lapIssueUserExclusion => 'Wykluczone przez użytkownika';

  @override
  String get lapIssueNotTimedLap =>
      'To nie jest pełne okrążenie z pomiarem czasu';

  @override
  String get lapIssueStaleSource =>
      'Źródło się zmieniło; wczytaj nagranie ponownie';

  @override
  String get lapIssueIneligibleLap => 'Okrążenie się nie kwalifikuje';

  @override
  String get lapIssueDifferentRoute =>
      'Okrążenie zjeżdża z trasy pozostałych okrążeń (wyjazd poza tor, objazd lub aleja serwisowa)';

  @override
  String get tbTiming => 'Pomiar czasu każdego okrążenia na wspólnej osi toru…';

  @override
  String tbIntro(int segments, int laps) {
    String _temp0 = intl.Intl.pluralLogic(
      segments,
      locale: localeName,
      other: '$segments segmentów',
      one: '1 segmentu',
    );
    String _temp1 = intl.Intl.pluralLogic(
      laps,
      locale: localeName,
      other: '$laps okrążeniach',
      one: '1 okrążeniu',
    );
    return 'Najszybszy czas każdego z $_temp0 na $_temp1. Łączy fragmenty różnych okrążeń, więc nie dowodzi, że całe okrążenie da się przejechać tak szybko.';
  }

  @override
  String get tbSegmentsProposed =>
      'Segmenty zaproponowano na podstawie najlepszego okrążenia; zapisanie dnia je zachowa.';

  @override
  String get tbSegmentsCorrected => 'Segmenty uwzględniają Twoje poprawki.';

  @override
  String get tbEditSegments => 'Edytuj segmenty';

  @override
  String get tbWhereTimeGoes => 'Gdzie ucieka czas';

  @override
  String tbMarkedBest(String text) {
    return '$text · najlepsze';
  }

  @override
  String tbMapLabel(String lap) {
    return 'Ślad najlepszego okrążenia, każdy segment pokolorowany według czasu, jaki traci tam $lap';
  }

  @override
  String get tbTapCorner =>
      'Dotknij zakrętu, aby zobaczyć prędkości, hamowanie i powrót do gazu na tle najlepszego okrążenia.';

  @override
  String get tbCompareHint =>
      'Przycisk porównania otwiera to okrążenie na tle najlepszego okrążenia w danym segmencie w Analizatorze zakrętów.';

  @override
  String get tbOpenInAnalyzer => 'Otwórz w Analizatorze zakrętów';

  @override
  String get tbSectorTimes => 'Czasy sektorów';

  @override
  String get tbSectorHint =>
      'Najszybszy czas każdego segmentu jest wyróżniony. Dotknij okrążenia, aby pokazać jego straty na mapie.';

  @override
  String tbNotCovered(String time) {
    return 'Nie w pełni pokryty na tym okrążeniu · najszybciej $time';
  }

  @override
  String tbFastestHere(String time) {
    return 'Najszybciej tutaj · $time';
  }

  @override
  String tbFastestBy(String time, String lap) {
    return 'Najszybciej $time · $lap';
  }

  @override
  String get tbLapUnavailable => 'okrążenie niedostępne';

  @override
  String get tbBestLap => 'Najlepsze okrążenie';

  @override
  String get tbBestLapSameSegments => 'Najlepsze okrążenie, te same segmenty';

  @override
  String get tbAvailable => 'Rezerwa';

  @override
  String get tbLapColumn => 'Okrążenie';

  @override
  String get tbTimeColumn => 'Czas';

  @override
  String get tbFastestRow => 'Najszybciej';

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
      'Potwierdź zgodną konfigurację toru, aby obliczyć teoretycznie najlepsze okrążenie.';

  @override
  String get tbNoEligibleLaps =>
      'W tej grupie nie ma okrążeń, z których można obliczyć teoretycznie najlepsze okrążenie.';

  @override
  String get tbNoApprovedRun =>
      'Żadna sesja w tej grupie nie ma jeszcze zatwierdzonych segmentów. Najpierw zatwierdź segmenty dla co najmniej jednej sesji.';

  @override
  String get tbNoApprovedSegments =>
      'Brak zatwierdzonych segmentów, według których można mierzyć sektory.';

  @override
  String get tbIncompleteCoverage =>
      'Co najmniej jeden sektor nie ma w pełni pokrytego czasu na żadnym okrążeniu, więc suma nie jest pokazana.';

  @override
  String get tbCancelled =>
      'Obliczanie teoretycznie najlepszego okrążenia zostało przerwane.';

  @override
  String get consistencyHeading => 'Powtarzalność';

  @override
  String consistencyIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count okrążeń',
      one: '1 okrążenia',
    );
    return 'Typowy czas to mediana; rozrzut to rozstęp międzykwartylowy, czyli szerokość środkowej połowy okrążeń, więc jedno wolne lub szybkie okrążenie go nie zdominuje. Potrzeba co najmniej $_temp0.';
  }

  @override
  String get consistencyLapTimes => 'Czasy okrążeń';

  @override
  String get consistencyAllSessions => 'Wszystkie sesje';

  @override
  String get consistencySegmentTimes => 'Czasy segmentów';

  @override
  String get consistencyMeasuring =>
      'Mierzone razem z teoretycznie najlepszym okrążeniem…';

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
    return '$time · rozrzut $spread s';
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
  String get timeLossLoading => 'Liczone razem z teoretycznie najlepszym…';

  @override
  String get timeLossScopeSessionBest => 'Najlepsze każdej sesji';

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
    return 'pominięte bez pełnego pomiaru: $count';
  }

  @override
  String get timeLossExplanation =>
      'Każda strata to dodatkowy czas, jaki jedno okrążenie potrzebowało na jeden segment w porównaniu z najlepszym okrążeniem; oba mierzone na jednej osi toru. Prosta tuż za zakrętem jest osobnym segmentem, więc czas stracony na wyjściu nie jest liczony w zakręcie. Zaobserwowana strata to nie gwarantowany ani koniecznie bezpieczny zysk.';

  @override
  String get timeLossNone =>
      'Żadne okrążenie nie straciło czasu do najlepszego okrążenia w żadnym zmierzonym segmencie.';

  @override
  String timeLossShowAll(int count) {
    return 'Pokaż wszystkie ($count)';
  }

  @override
  String get timeLossReasonNoReference =>
      'Najlepszego okrążenia nie udało się zmierzyć na segmentach.';

  @override
  String get timeLossReasonBestLapUntimed =>
      'Najlepszego okrążenia grupy nie udało się zmierzyć na zatwierdzonych segmentach.';

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
    return '$segment: od $start m do $end m za linią start/meta.';
  }

  @override
  String timeLossGap(String start, String end) {
    return 'Różnica do najlepszego okrążenia: $start na początku segmentu, $end na jego końcu.';
  }

  @override
  String get timeLossNoGps => 'Na jednym z okrążeń część segmentu nie ma GPS.';

  @override
  String timeLossMapLabel(String segment) {
    return 'Ślad najlepszego okrążenia z wyróżnionym segmentem $segment';
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
  String get focusLoading => 'Wybierane razem z teoretycznie najlepszym…';

  @override
  String get focusNone =>
      'Żadna strata, różnica w sektorze ani rozrzut nie są na tyle duże, by je wyróżnić.';

  @override
  String get focusIntro =>
      'Każdy obszar zaczyna się od tego, co zmierzono. Linia pod spodem to hipoteza do sprawdzenia na okrążeniach, a nie przyczyna ani instrukcja.';

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
    return 'Zmierzono: $text';
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
    return 'Segment: $segment';
  }

  @override
  String get focusNotTimed => 'bez czasu';

  @override
  String get focusBrakingNotMeasured => 'punkt hamowania niezmierzony';

  @override
  String focusBrakingStarts(int meters) {
    return 'hamowanie zaczyna się na $meters m';
  }

  @override
  String get focusLowestSpeedNotMeasured => 'prędkość minimalna niezmierzona';

  @override
  String focusLowestSpeed(String speed) {
    return 'prędkość minimalna $speed';
  }

  @override
  String get focusDisclaimer =>
      'Zmierzone tylko na tych okrążeniach. Nie mówi, który sposób jest szybszy ani bezpieczny.';

  @override
  String get focusCompareAB => 'Porównaj okrążenia A i B';

  @override
  String focusObservationSectorGap(
    String bestLap,
    String gap,
    String segment,
    String sourceLap,
  ) {
    return 'Twoje najlepsze okrążenie ($bestLap) było o $gap s wolniejsze w segmencie $segment niż $sourceLap, najszybsze zarejestrowane tam.';
  }

  @override
  String focusHypothesisSectorGap(String segment) {
    return 'Porównanie obu okrążeń w segmencie $segment może pokazać, gdzie uciekł czas: gdzie zaczyna się hamowanie, jaka jest prędkość minimalna i kiedy wraca gaz.';
  }

  @override
  String focusObservationRepeatedLoss(
    String count,
    String total,
    String segment,
    String reference,
    String median,
  ) {
    return 'Na $count z $total porównanych okrążeń czas uciekał w segmencie $segment względem $reference (mediana $median s).';
  }

  @override
  String focusHypothesisRepeatedLoss(String reference, String segment) {
    return 'Ponieważ to się powtarza, porównanie typowego okrążenia z $reference w segmencie $segment może pokazać wzorzec, a nie jednorazowy przypadek.';
  }

  @override
  String focusObservationBrakingSpread(
    String segment,
    String spread,
    String count,
  ) {
    return 'Punkt hamowania w segmencie $segment zmienia się o $spread m w środkowej połowie z $count okrążeń (zmierzony z sygnału hamulca).';
  }

  @override
  String focusHypothesisBrakingSpread(String segment) {
    return 'Warto sprawdzić bardziej powtarzalny punkt odniesienia do hamowania w segmencie $segment. To nie pokazuje, czy wcześniejsze czy późniejsze hamowanie jest szybsze lub bezpieczne; porównaj najwcześniejszy i najpóźniejszy przykład.';
  }

  @override
  String focusObservationMinimumSpeedSpread(
    String segment,
    String spread,
    String count,
    String median,
  ) {
    return 'Prędkość minimalna w segmencie $segment zmienia się o $spread w środkowej połowie z $count okrążeń (mediana $median).';
  }

  @override
  String get focusObservationRecordingUnits =>
      'Prędkości są w jednostkach z nagrania.';

  @override
  String focusHypothesisMinimumSpeedSpread(String segment) {
    return 'Porównanie najwolniejszego i najszybszego przykładu w segmencie $segment może pokazać, co się różni; wyższa prędkość minimalna sama w sobie nie jest lepsza.';
  }

  @override
  String get progressionTitle => 'Postęp';

  @override
  String get progressionBySession => 'Według sesji';

  @override
  String get progressionBySegment => 'Według segmentów';

  @override
  String get progressionSessionsIntro =>
      'Sesje w kolejności nagrania; sesje bez czasu nagrania są na końcu, w kolejności dodania. Pasek biegnie od najszybszego do najwolniejszego sklasyfikowanego okrążenia na jednej skali czasu; środkowa połowa jest zaznaczona prostokątem, a typowe okrążenie kreską.';

  @override
  String get progressionNoSession => 'Brak sesji do porównania.';

  @override
  String get progressionRecordingTimeUnavailable => 'Brak czasu nagrania';

  @override
  String progressionRecordingClock(String time, String date) {
    return '$time UTC, $date';
  }

  @override
  String get progressionNoRecordedLaps => 'Brak nagranych okrążeń';

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
    return 'Typowo $time';
  }

  @override
  String progressionTypicalNeedsLaps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Typowe okrążenie wymaga co najmniej $count sklasyfikowanych okrążeń',
      one: 'Typowe okrążenie wymaga co najmniej 1 sklasyfikowanego okrążenia',
    );
    return '$_temp0';
  }

  @override
  String progressionBestAgainst(String delta, String session) {
    return 'Najlepsze $delta w porównaniu z: $session';
  }

  @override
  String progressionConditions(String conditions) {
    return 'Warunki: $conditions';
  }

  @override
  String progressionSetup(String setup) {
    return 'Ustawienia: $setup';
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
  String get progressionMeasuring => 'Liczone razem z teoretycznie najlepszym…';

  @override
  String progressionSegmentsIntro(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego segmentu w każdej sesji. Najszybszy typowy czas segmentu jest wyróżniony. Mniej niż $count okrążeń: brak statystyk. Dotknij komórki, aby zobaczyć jej okrążenia.',
      few:
          'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego segmentu w każdej sesji. Najszybszy typowy czas segmentu jest wyróżniony. Mniej niż $count okrążenia: brak statystyk. Dotknij komórki, aby zobaczyć jej okrążenia.',
      one: 'Typowy czas (mediana) i rozrzut (środkowa połowa) każdego segmentu w każdej sesji. Najszybszy typowy czas segmentu jest wyróżniony. Mniej niż 1 okrążenie: brak statystyk. Dotknij komórki, aby zobaczyć jej okrążenia.',
    );
    return '$_temp0';
  }

  @override
  String get progressionLapUnavailable => 'Okrążenie niedostępne';

  @override
  String get progressionNoTimedSegments =>
      'Żadna sesja nie ma zmierzonych segmentów.';

  @override
  String progressionSpread(String seconds) {
    return 'rozrzut $seconds s';
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
  String get channelOil => 'Olej';

  @override
  String get channelCoolant => 'Płyn chłodzący';

  @override
  String get channelIntakeAir => 'Powietrze dolotowe';

  @override
  String get channelGearbox => 'Skrzynia biegów';

  @override
  String get channelExhaust => 'Spaliny';

  @override
  String get channelAmbient => 'Otoczenie';

  @override
  String get channelNotRecorded => 'Nie nagrano';

  @override
  String get channelNoValidSamples => 'Brak poprawnych próbek';

  @override
  String channelSummary(
    String mean,
    String minimum,
    String maximum,
    int coverage,
  ) {
    return 'średnio $mean · $minimum – $maximum · pokrycie $coverage%';
  }

  @override
  String channelImplausibleLeftOut(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieprawdopodobnych odczytów pominiętych',
      few: '$count nieprawdopodobne odczyty pominięte',
      one: '1 nieprawdopodobny odczyt pominięty',
    );
    return '$_temp0';
  }

  @override
  String get channelOutLap => 'wyjazd';

  @override
  String get channelInLap => 'zjazd';

  @override
  String channelLapSection(int number) {
    return 'okr. $number';
  }

  @override
  String get channelUnknownSection => 'nieznany odcinek';

  @override
  String get channelCoolingNone => 'brak';

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
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$metric: temperatura (lub miara) nie zmieniała się w $count okrążeniach.',
      one: '$metric: temperatura (lub miara) nie zmieniała się w 1 okrążeniu.',
    );
    return '$_temp0';
  }

  @override
  String channelAssociationTooFew(String metric, int count, int minimum) {
    return '$metric: porównywalne okrążenia z tą temperaturą: $count; potrzeba co najmniej $minimum.';
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
  String get channelMeaningQuicker => 'cieplejsze okrążenia były szybsze';

  @override
  String get channelMeaningSlower => 'cieplejsze okrążenia były wolniejsze';

  @override
  String get channelMeaningHarder =>
      'na cieplejszych okrążeniach przyspieszanie było mocniejsze';

  @override
  String get channelMeaningLess =>
      'na cieplejszych okrążeniach przyspieszanie było słabsze';

  @override
  String get channelCarTitle => 'Samochód';

  @override
  String get channelCarReading =>
      'Odczytywanie temperatur nagranych w każdej sesji…';

  @override
  String get channelCarNoChannels =>
      'Żadne nagranie nie zawiera kanału temperatury.';

  @override
  String get channelCarIntro =>
      'Każda sesja osobno, w kolejności nagrania. Przerwy w nagraniu nigdy nie są uzupełniane; nieprawdopodobne odczyty i zastępcze zera są pomijane i liczone. Chłodzenie to ciągle nagrany spadek o co najmniej 5° w ciągu co najmniej 30 s.';

  @override
  String get channelUnitsNotDeclared => 'nagranie nie podaje jednostki';

  @override
  String get channelConfounded =>
      'Temperatura zmieniała się też w ciągu dnia, więc nie da się tego oddzielić od wszystkiego innego, co się zmieniło: kierowcy, opon, toru i paliwa.';

  @override
  String get channelHeartRateIntro =>
      'Zaobserwowane wartości z nagrania, nie ocena.';

  @override
  String get channelEverySectionIntro => 'Każdy nagrany odcinek każdej sesji.';

  @override
  String get channelWithLapPerformance => 'Związek z osiągami na okrążeniu';

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
    return 'Korelacja rang Spearmana dla porównywanych okrążeń dnia, w których czujnik objął co najmniej $coverage% okrążenia. Pominięte z powodu niskiego pokrycia: $lowCoverage, bez poprawnego odczytu: $notRecorded. Opisuje, jak obie wielkości zmieniały się razem tego dnia; nie wyznacza temperatury krytycznej ani przyczyny.';
  }

  @override
  String get channelDriverTitle => 'Kierowca';

  @override
  String get channelDriverReading =>
      'Odczytywanie tętna nagranego w każdej sesji…';

  @override
  String get channelDriverNoHeartRate => 'Nie nagrano tętna.';

  @override
  String get channelDriverIntro =>
      'Tętno z nagrań: zaobserwowane wartości, nie ocena. Dla okrążenia: średnie bpm; dotknij okrążenia, aby je otworzyć.';

  @override
  String get channelHeartRate => 'Tętno';

  @override
  String get channelEverySection => 'Każdy odcinek…';

  @override
  String channelLapMean(int number, String mean) {
    return 'OKR. $number · $mean';
  }

  @override
  String get channelRecordingUnavailable => 'Nagranie niedostępne.';

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
    return 'hamowanie $where';
  }

  @override
  String cornerSummaryBrakesWithBest(String where, String position) {
    return 'hamowanie $where ($position)';
  }

  @override
  String cornerBeforeEntry(int metres) {
    return '$metres m przed';
  }

  @override
  String cornerIntoCorner(int metres) {
    return '$metres m w zakręcie';
  }

  @override
  String get cornerSamePosition => 'w tym samym miejscu';

  @override
  String cornerLater(int metres) {
    return '$metres m później';
  }

  @override
  String cornerEarlier(int metres) {
    return '$metres m wcześniej';
  }

  @override
  String get missingRecordingNotFound => 'Nie znaleziono nagrania.';

  @override
  String get missingRecordingDuplicate =>
      'To samo nagranie co inna sesja tego dnia.';

  @override
  String get missingRecordingDifferent => 'Znaleziony plik to inne nagranie.';

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
  String get diagnosticsRecordingsRead => 'Odczytane nagrania';

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
  String get diagnosticsStepScan => 'Wyszukiwanie nagrań';

  @override
  String get diagnosticsStepParse => 'Odczyt i import';

  @override
  String get diagnosticsStepAnalysis => 'Analiza dnia';

  @override
  String get diagnosticsStepImportTotal => 'Import, od startu do wyników';

  @override
  String get diagnosticsStepTheoreticalBest => 'Segmenty i czas teoretyczny';

  @override
  String get diagnosticsStepChannelSummaries => 'Podsumowania kanałów';

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
  String get reportNoHeartRate => 'Nie nagrano tętna.';

  @override
  String get reportNoTemperature => 'Nie nagrano temperatury.';

  @override
  String get reportBestTitle => 'Najlepsze okrążenie i co zostało';

  @override
  String get reportBestLap => 'Najlepsze okrążenie';

  @override
  String get reportTheoreticalBest => 'Teoretycznie najlepsze';

  @override
  String reportTheoreticalAvailable(String seconds) {
    return '$seconds s rezerwy na zatwierdzonych segmentach';
  }

  @override
  String get reportTheoreticalNoTotal =>
      'Część segmentów nie ma zmierzonego okrążenia; brak sumy.';

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
    return 'najlepsze $time';
  }

  @override
  String get reportSameAsPrevious => 'tak samo jak w poprzedniej sesji';

  @override
  String reportFasterThanPrevious(String seconds) {
    return '$seconds s szybciej niż w poprzedniej sesji';
  }

  @override
  String reportSlowerThanPrevious(String seconds) {
    return '$seconds s wolniej niż w poprzedniej sesji';
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
    return 'Typowe okrążenie $time · środkowa połowa w granicach $spread s · $_temp0';
  }

  @override
  String reportConsistencyTooFew(int minimum) {
    String _temp0 = intl.Intl.pluralLogic(
      minimum,
      locale: localeName,
      other: 'Mniej niż $minimum kwalifikujących się okrążeń; brak rozrzutu.',
      few: 'Mniej niż $minimum kwalifikujące się okrążenia; brak rozrzutu.',
      one: 'Mniej niż 1 kwalifikujące się okrążenie; brak rozrzutu.',
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
      other: '$count nagranych okresów chłodzenia',
      few: '$count nagrane okresy chłodzenia',
      one: '1 nagrany okres chłodzenia',
    );
    return '$_temp0';
  }

  @override
  String get reportNoCooling => 'brak nagranego chłodzenia';

  @override
  String get reportNoTemperatureSamples =>
      'Brak poprawnych próbek temperatury.';

  @override
  String reportHeartRateSummary(String mean, String minimum, String maximum) {
    return 'średnio $mean bpm · $minimum – $maximum';
  }

  @override
  String reportCovered(int percent) {
    return 'pokrycie $percent%';
  }

  @override
  String get segmentEditorTitle => 'Edytuj segmenty';

  @override
  String get segmentEditorUndo => 'Cofnij';

  @override
  String get segmentEditorRedo => 'Ponów';

  @override
  String get segmentEditorTiming =>
      'Mierzenie czasu każdego okrążenia na jednej osi toru…';

  @override
  String get segmentEditorMapLabel =>
      'Ślad najlepszego okrążenia z granicami segmentów';

  @override
  String segmentEditorMapLabelHighlighted(String segment) {
    return 'Ślad najlepszego okrążenia z granicami segmentów, wyróżniono: $segment';
  }

  @override
  String get segmentEditorAutomatic => 'Segmenty automatyczne';

  @override
  String get segmentEditorEdited => 'Poprawione segmenty';

  @override
  String segmentEditorSummary(String time, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count segmentów',
      few: '$count segmenty',
      one: '1 segment',
    );
    return 'Teoretycznie najlepsze $time · $_temp0';
  }

  @override
  String get segmentEditorRestoreAutomatic => 'Przywróć automatyczne';

  @override
  String segmentEditorProposedFrom(String lap) {
    return 'Zaproponowane na podstawie: $lap. Dotknij segmentu, aby go poprawić.';
  }

  @override
  String get segmentEditorProposedFromBestLap =>
      'Zaproponowane na podstawie najlepszego okrążenia. Dotknij segmentu, aby go poprawić.';

  @override
  String get segmentEditorCorrectionsSaved =>
      'Twoje poprawki są zapisywane z dniem i nigdy nie są zastępowane segmentami automatycznymi.';

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
    return '$type · $start–$end m · $length m';
  }

  @override
  String segmentEditorRowEdited(String row) {
    return '$row · poprawiony';
  }

  @override
  String get segmentEditorRestoreTitle => 'Przywrócić segmenty automatyczne?';

  @override
  String get segmentEditorRestoreBody =>
      'Twoje poprawki segmentów tego układu toru zostaną zastąpione segmentami zaproponowanymi na podstawie najlepszego okrążenia.';

  @override
  String get segmentEditorRestore => 'Przywróć';

  @override
  String get segmentEditorName => 'Nazwa';

  @override
  String get segmentEditorStart => 'Początek';

  @override
  String get segmentEditorEnd => 'Koniec';

  @override
  String get segmentEditorKeepJoined => 'Przesuń też sąsiedni segment';

  @override
  String get segmentEditorApply => 'Zastosuj';

  @override
  String get segmentEditorReset => 'Resetuj';

  @override
  String segmentEditorSplitAt(String meters) {
    return 'Podział w punkcie $meters m';
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
      'Segmenty można edytować, gdy teoretycznie najlepsze okrążenie zostanie obliczone.';

  @override
  String get segmentEditorErrorAlreadyAutomatic =>
      'Segmenty są już automatyczne.';

  @override
  String get segmentEditorErrorNotPossible => 'Ta zmiana nie jest możliwa.';

  @override
  String get segmentEditorErrorLastSegment =>
      'Teoretycznie najlepsze okrążenie wymaga co najmniej jednego segmentu. Zamiast tego przywróć segmenty automatyczne.';

  @override
  String get segmentEditorErrorNoLongerApproved =>
      'Ten segment nie jest już zatwierdzony.';

  @override
  String get segmentEditorErrorNothingToUndo => 'Nie ma czego cofnąć.';

  @override
  String get segmentEditorErrorNothingToRedo => 'Nie ma czego ponowić.';

  @override
  String get segmentEditorErrorHistoryCleared =>
      'Segmenty zmieniły się poza tym edytorem, więc historia zmian została wyczyszczona.';

  @override
  String get segmentEditorErrorInvalidStored =>
      'Zapisane zatwierdzone segmenty są nieprawidłowe.';

  @override
  String get segmentEditorErrorOtherConfiguration =>
      'Najpierw trzeba odrzucić segmenty zatwierdzone dla innej konfiguracji toru.';

  @override
  String segmentEditorErrorWouldBeEmpty(String segment) {
    return 'Segment „$segment” byłby pusty.';
  }

  @override
  String segmentEditorErrorWouldBeInvalid(String segment) {
    return 'Segment „$segment” byłby nieprawidłowy.';
  }

  @override
  String segmentEditorErrorWouldOverlap(String segment, String other) {
    return 'Segment „$segment” nachodziłby na „$other”.';
  }

  @override
  String segmentEditorErrorTooMany(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Można zatwierdzić najwyżej $count segmentów.',
      few: 'Można zatwierdzić najwyżej $count segmenty.',
      one: 'Można zatwierdzić najwyżej 1 segment.',
    );
    return '$_temp0';
  }

  @override
  String get segmentEditorErrorCrossesGate =>
      'Tylko jeden segment może przecinać linię startu/mety.';

  @override
  String get segmentEditorErrorChooseType =>
      'Wybierz zakręt, prostą lub sektor.';

  @override
  String get segmentEditorErrorNoAxis => 'Oś toru jest niedostępna.';

  @override
  String get segmentEditorErrorSplitInside =>
      'Dziel wewnątrz segmentu, z dala od jego końców.';

  @override
  String get segmentEditorErrorSplitName =>
      'Wpisz nazwę nowego segmentu (1–160 znaków).';

  @override
  String get segmentEditorErrorMergeSame =>
      'Wybierz dwa różne zatwierdzone segmenty.';

  @override
  String get segmentEditorErrorMergeNotAdjacent =>
      'Połączyć można tylko segmenty o wspólnej granicy.';

  @override
  String get segmentEditorErrorMergeWholeLap =>
      'Połączenie objęłoby całe okrążenie; segment musi mieć różny początek i koniec.';

  @override
  String get segmentEditorErrorName => 'Wpisz nazwę (1–160 znaków).';

  @override
  String segmentEditorErrorBounds(String length) {
    return 'Granice muszą leżeć między 0 a $length m.';
  }

  @override
  String get segmentEditorErrorEmpty => 'Segment nie może być pusty.';

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
      other: 'Nie można użyć $format $count sesji',
      many: 'Nie można użyć $format $count sesji',
      few: 'Nie można użyć $format $count sesji',
      one: 'Nie można użyć $format 1 sesji',
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
    return 'Nie użyto, to inne nagranie: $files.';
  }

  @override
  String fusionAddedNotCombined(String format, String sessions) {
    return 'Dodano $format do: $sessions, ale nie udało się go połączyć; zostaje zapisany i zostanie połączony przy otwarciu dnia.';
  }

  @override
  String get fusionReasonFailed => 'dopasowanie się nie powiodło';

  @override
  String relinkDifferentRecordings(int count, String files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count plików w tym folderze ($files) to inne nagrania i nie zostały użyte.',
      many:
          '$count plików w tym folderze ($files) to inne nagrania i nie zostały użyte.',
      few:
          '$count pliki w tym folderze ($files) to inne nagrania i nie zostały użyte.',
      one: '$files w tym folderze to inne nagranie i nie zostało użyte.',
    );
    return '$_temp0';
  }

  @override
  String get relinkNothingFound =>
      'W tym folderze nie znaleziono żadnego brakującego nagrania.';

  @override
  String get segmentPickOnMap => 'Wskaż na mapie';

  @override
  String get segmentPickActive => 'Dotknij mapy… (anuluj)';

  @override
  String get segmentPickBannerStart =>
      'Dotknij linii toru, aby ustawić początek';

  @override
  String get segmentPickBannerEnd => 'Dotknij linii toru, aby ustawić koniec';

  @override
  String get segmentPickBannerSplit =>
      'Dotknij linii toru, aby wskazać miejsce podziału';

  @override
  String get segmentPickAmbiguous =>
      'W pobliżu przebiega inny fragment toru. Ustaw odległość przyciskami.';

  @override
  String get segmentPickFar => 'Dotknij linii przejazdu okrążenia.';

  @override
  String get segmentPickNoTrace =>
      'Ślad okrążenia nie jest dostępny do wskazywania.';

  @override
  String get segmentPickOutside =>
      'Aby podzielić segment, wskaż punkt wewnątrz niego.';

  @override
  String get variabilityHeading => 'Powtarzalność w zakrętach';

  @override
  String get variabilityIntro =>
      'Jak bardzo każdy zakręt zmienia się z okrążenia na okrążenie w okrążeniach grupy: typowa to mediana, rozrzut to środkowa połowa okrążeń (rozstęp ćwiartkowy), z co najmniej 3 okrążeń. To obserwacje, nie przyczyny.';

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
  String get variabilityInferred => 'wywnioskowany';

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
  String get variabilityBraking => 'Punkt hamowania';

  @override
  String get variabilityApex => 'Prędkość na wierzchołku';

  @override
  String get variabilityMinimum => 'Prędkość minimalna';

  @override
  String get variabilityExit => 'Prędkość na wyjściu';

  @override
  String get variabilityPickup => 'Powrót do gazu';

  @override
  String variabilityLine(String spread, String accuracy) {
    return 'Linia: rozrzut $spread m · $accuracy';
  }

  @override
  String variabilityGpsAccuracy(String meters) {
    return 'dokładność GPS około $meters m';
  }

  @override
  String get variabilityGpsUnknown => 'dokładność GPS nie jest zapisana';

  @override
  String get variabilityLineUnresolved => ' · nie do odróżnienia od błędu GPS';

  @override
  String get calculateAgain => 'Oblicz ponownie';

  @override
  String get retryRecordings => 'Ponów odczyt nagrań';

  @override
  String get retryRecordingsLooking => 'Otwieranie…';

  @override
  String get retryRecordingsSaveFirst =>
      'Najpierw zapisz dzień, potem ponów odczyt nagrań.';

  @override
  String get retryRecordingsStill =>
      'Nagrania nadal nie są tam, gdzie wskazuje dzień.';

  @override
  String get sessionDetailsHeading => 'Szczegóły sesji';

  @override
  String get sessionDetailsNone =>
      'Brak warunków, zmian w ustawieniach i notatek';

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
  String get sessionDetailsConditionsHint => 'Sucho, 18 °C';

  @override
  String get sessionDetailsSetup => 'Zmiany w ustawieniach';

  @override
  String get sessionDetailsSetupHint => 'Opony +0.1 bar';

  @override
  String get sessionDetailsNotes => 'Notatki';

  @override
  String get sessionDetailsSaved =>
      'Zapisywane w pliku dnia, który czyta też FlappedEar Overlays.';

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
      'Poczekaj, aż nagrania zostaną dodane, i spróbuj ponownie.';

  @override
  String get retryRecordingsAddedMeanwhile =>
      'W międzyczasie dodano nagrania. Ponów odczyt nagrań jeszcze raz.';

  @override
  String get retryRecordingsNone =>
      'Nie udało się otworzyć żadnego nagrania dnia, więc dzień pozostaje bez zmian.';

  @override
  String retryRecordingsFailed(String reason) {
    return 'Nie udało się ponownie otworzyć dnia: $reason';
  }

  @override
  String get retryRecordingsChangedMeanwhile =>
      'W międzyczasie zmieniono dzień. Zapisz go i ponów odczyt nagrań.';

  @override
  String get lapsCompareTwo => 'Porównaj dwa okrążenia';

  @override
  String get lapsLastComparison => 'Ostatnie porównanie';

  @override
  String get taskStopped => 'Praca została przerwana.';

  @override
  String get taskStoppedUnexpectedly => 'Praca nieoczekiwanie się przerwała.';

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
      'Odcinki są zatwierdzane automatycznie, więc ten przegląd jest opcjonalny. Odrzucona propozycja jest pomijana przez Zatwierdź wszystkie i zapisuje się z dniem.';

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
    return '$start m ±$startTolerance → $end m ±$endTolerance ($length m)';
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
    return 'Geometryczny wierzchołek $at m ±$tolerance m';
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
      'Brak automatycznej propozycji: to okrążenie skręca bez przerwy, bez prostej między zakrętami.';

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
      'Odcinki można zmienić, gdy teoretycznie najlepsze okrążenie zostanie obliczone.';

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
    return 'Wczytywanie $format jako nagrania tej sesji…';
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
    return 'Dryf zegara: $ppm ppm';
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
    return 'Zegary rejestratorów podają $offset';
  }

  @override
  String get clockNoDeclared => 'Nie oba rejestratory podają czas startu';

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
    return 'Nie udało się wczytać $format jako nagrania tej sesji.';
  }

  @override
  String get recordingsBusyFind =>
      'Poczekaj na zakończenie sprawdzania lub zmiany nagrań sesji, a potem znajdź pozostałe.';

  @override
  String get recordingsBusyRetry =>
      'Poczekaj na zakończenie sprawdzania lub zmiany nagrań sesji, a potem spróbuj ponownie.';

  @override
  String get recordingsBusyLeave =>
      'Poczekaj na zakończenie sprawdzania lub zmiany nagrań sesji.';

  @override
  String get recordingsUnsaved =>
      'Zapisz dzień przed zmianą głównego nagrania.';

  @override
  String get recordingsBusyAdd =>
      'Poczekaj na zakończenie sprawdzania lub zmiany nagrań sesji, a potem dodaj nagrania.';

  @override
  String get reviewImportTitle => 'Przejrzyj import';

  @override
  String get reviewImportIntro =>
      'Wybierz, co stanie się z każdym nagraniem. Nic nie zostanie zaimportowane, dopóki nie potwierdzisz.';

  @override
  String get reviewBeforeImport => 'Przejrzyj pliki przed importem';

  @override
  String get addAndReviewRecordings => 'Dodaj i przejrzyj nagrania…';

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
      'Dwa eksporty tej samej sesji? Wybierz „Ta sama sesja co”. Okrążenia sesji pochodzą z pliku, który wskażesz; drugi plik zostaje przy niej jako nagranie alternatywne.';

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
      'Sesja może mieć najwyżej jedno dodatkowe nagranie.';

  @override
  String get reviewProblemNothing =>
      'Wybierz co najmniej jeden plik do importu.';

  @override
  String get reviewChoicesRefused =>
      'Tych wyborów nie można dodać, więc niczego nie dodano. Przejrzyj nagrania ponownie.';

  @override
  String get waitUntilRecordingsSaved =>
      'Poczekaj, aż nagrania zostaną dopasowane, a dzień zapisany.';

  @override
  String get reviewChanged =>
      'Nagrania zmieniły się po przeglądzie, więc niczego nie zaimportowano. Przejrzyj je ponownie.';

  @override
  String get reviewPreparing => 'Przygotowywanie przeglądu…';

  @override
  String get importBusy =>
      'Najpierw dokończ bieżący import. Niczego nie zaimportowano.';
}
