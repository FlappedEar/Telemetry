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
  String get noMissingRecordingFound =>
      'W tym folderze nie znaleziono brakujących nagrań.';

  @override
  String differentRecordingsNotUsed(int count, String files) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$files w tym folderze to inne nagrania, więc ich nie użyto.',
      one: '$files w tym folderze to inne nagranie, więc go nie użyto.',
    );
    return '$_temp0';
  }

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
  String get compareTwoLaps => 'Porównaj dwa okrążenia';

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
  String get tbAvailable => 'Do zyskania';

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
    return '$segment · za: $corner';
  }

  @override
  String timeLossSegmentAfterTheCorner(String segment) {
    return '$segment · za zakrętem';
  }

  @override
  String timeLossSegmentStraight(String number) {
    return 'Prosta $number';
  }

  @override
  String timeLossSegmentCorner(String number) {
    return 'Zakręt $number';
  }

  @override
  String timeLossSegmentCorners(String first, String last) {
    return 'Zakręty $first–$last';
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
    return 'Odcinek: $segment';
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
    return 'Twoje najlepsze okrążenie ($bestLap) było o $gap s wolniejsze na odcinku $segment niż $sourceLap, najszybsze zarejestrowane tam.';
  }

  @override
  String focusHypothesisSectorGap(String segment) {
    return 'Porównanie obu okrążeń na odcinku $segment może pokazać, gdzie uciekł czas: gdzie zaczyna się hamowanie, jaka jest prędkość minimalna i kiedy wraca gaz.';
  }

  @override
  String focusObservationRepeatedLoss(
    String count,
    String total,
    String segment,
    String reference,
    String median,
  ) {
    return 'Na $count z $total porównanych okrążeń straciłeś czas na odcinku $segment względem $reference (mediana $median s).';
  }

  @override
  String focusHypothesisRepeatedLoss(String reference, String segment) {
    return 'Ponieważ to się powtarza, porównanie typowego okrążenia z $reference na odcinku $segment może pokazać wzorzec, a nie jednorazowy przypadek.';
  }

  @override
  String focusObservationBrakingSpread(
    String segment,
    String spread,
    String count,
  ) {
    return 'Punkt hamowania na odcinku $segment zmienia się o $spread m w środkowej połowie z $count okrążeń (zmierzony z sygnału hamulca).';
  }

  @override
  String focusHypothesisBrakingSpread(String segment) {
    return 'Warto sprawdzić bardziej powtarzalny punkt odniesienia do hamowania na odcinku $segment. To nie pokazuje, czy wcześniejsze czy późniejsze hamowanie jest szybsze lub bezpieczne; porównaj najwcześniejszy i najpóźniejszy przykład.';
  }

  @override
  String focusObservationMinimumSpeedSpread(
    String segment,
    String spread,
    String count,
    String median,
  ) {
    return 'Prędkość minimalna na odcinku $segment zmienia się o $spread w środkowej połowie z $count okrążeń (mediana $median).';
  }

  @override
  String get focusObservationRecordingUnits =>
      'Prędkości są w jednostkach z nagrania.';

  @override
  String focusHypothesisMinimumSpeedSpread(String segment) {
    return 'Porównanie najwolniejszego i najszybszego przykładu na odcinku $segment może pokazać, co się różni; wyższa prędkość minimalna sama w sobie nie jest lepsza.';
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
}
