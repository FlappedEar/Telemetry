import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:telemetry/day/theoretical_best_card.dart'
    show TheoreticalBestText, shortSegmentName;
import 'package:telemetry/format.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

Map<String, dynamic> arb(String language) =>
    jsonDecode(File('lib/l10n/app_$language.arb').readAsStringSync())
        as Map<String, dynamic>;

/// Shows what [show] returns for the app's language.
Widget probe(String Function(BuildContext) show, {Locale? locale}) =>
    TelemetryApp(
      locale: locale,
      home: Builder(builder: (context) => Text(show(context))),
    );

void main() {
  tearDown(() => Intl.defaultLocale = null);

  group('language', () {
    test('the first language the device prefers that the app speaks', () {
      expect(resolveAppLocale(const [Locale('pl', 'PL')]), const Locale('pl'));
      expect(resolveAppLocale(const [Locale('en', 'GB')]), const Locale('en'));
      expect(
        resolveAppLocale(const [Locale('de', 'DE'), Locale('pl', 'PL')]),
        const Locale('pl'),
      );
    });

    test('English when the device prefers no language the app speaks', () {
      expect(resolveAppLocale(const [Locale('de', 'DE')]), const Locale('en'));
      expect(resolveAppLocale(const []), const Locale('en'));
      expect(resolveAppLocale(null), const Locale('en'));
    });

    test('the generated localizations offer exactly these languages', () {
      expect(
        AppLocalizations.supportedLocales.toSet(),
        supportedLocales.toSet(),
      );
    });

    testWidgets('follows the device language', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pl', 'PL')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe((context) => context.l10n.cancel));
      expect(find.text('Anuluj'), findsOneWidget);
    });

    testWidgets('falls back to English on other devices', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await tester.pumpWidget(probe((context) => context.l10n.cancel));
      expect(find.text('Cancel'), findsOneWidget);
    });
  });

  group('translations', () {
    final english = arb('en');
    final keys = english.keys.where((key) => !key.startsWith('@')).toSet();
    for (final language in ['pl']) {
      final translated = arb(language);
      test('$language has every English text and no other', () {
        expect(
          translated.keys.where((key) => !key.startsWith('@')).toSet(),
          keys,
        );
      });
      test('$language keeps every placeholder', () {
        for (final key in keys) {
          final placeholders =
              ((english['@$key'] as Map?)?['placeholders'] as Map?)?.keys ??
              const [];
          for (final name in placeholders) {
            // Used in the text, or as the selector of a plural.
            expect(
              translated[key],
              anyOf(contains('{$name}'), contains('{$name,')),
              reason: '$language $key',
            );
          }
        }
      });
    }
  });

  test('every missing-recording reason from telemetry_core is translated', () {
    final source = File('packages/telemetry_core/lib/src/day/day_document.dart')
        .readAsStringSync();
    final polish = lookupAppLocalizations(const Locale('pl'));
    for (final reason in [
      'Recording not found.',
      'The same recording as another session of this day.',
      'The file found is a different recording.',
    ]) {
      expect(source, contains("'$reason'"));
      expect(polish.missingReason(reason), isNot(reason));
    }
    expect(polish.missingReason('Read error.'), 'Read error.');
  });

  test('background work failures are translated', () {
    final source = File('lib/day/background_task.dart').readAsStringSync();
    final polish = lookupAppLocalizations(const Locale('pl'));
    final english = lookupAppLocalizations(const Locale('en'));
    for (final message in [
      'The work stopped.',
      'The work stopped unexpectedly.',
    ]) {
      expect(source, contains("'$message'"));
      expect(polish.taskFailure(message), isNot(message));
      expect(english.taskFailure(message), message);
    }
    expect(polish.taskFailure('Disk full.'), 'Disk full.');
  });

  test('errors from adding recordings are translated', () {
    final source = File('lib/day/day_results_controller.dart')
        .readAsStringSync();
    final polish = lookupAppLocalizations(const Locale('pl'));
    for (final error in ['Adding was cancelled.', 'The day was closed.']) {
      expect(source, contains("'$error'"));
      expect(polish.additionError(error), isNot(error));
    }
    expect(source, contains("'Nothing was added: \$error'"));
    expect(
      polish.additionError('Nothing was added: disk full'),
      'Nic nie dodano: disk full',
    );
    expect(polish.additionError('Odd error'), 'Odd error');
  });

  test('segment names: automatic ones are translated, typed ones kept', () {
    final polish = lookupAppLocalizations(const Locale('pl'));
    expect(polish.tbSegmentName('Corner 4'), 'Zakręt 4');
    expect(polish.tbSegmentName('Corners 2–3'), 'Zakręty 2–3');
    expect(polish.tbSegmentName('Straight 1'), 'Prosta 1');
    expect(polish.tbSegmentName('Corner Bus-stop'), 'Corner Bus-stop');
    expect(polish.tbSegmentName('Corner 3 (2)'), 'Zakręt 3 (2)');
    expect(polish.tbSegmentName('Hairpin (2)'), 'Hairpin (2)');
    // Short names of names as written are unchanged.
    for (final (name, short) in [
      ('Corner 1', 'C1'),
      ('Corners 3–4', 'C3–4'),
      ('La-Source hairpin', 'La-Source hairpin'),
      ('Écurie 2', 'Écurie 2'),
    ]) {
      expect(shortSegmentName(name), short);
    }
  });

  test('every route reason from telemetry_core has a translation', () {
    // The reasons route detection writes, read from its source so a new or
    // reworded reason fails here instead of showing English in Polish.
    final source = File(
      'packages/telemetry_core/lib/src/day/track_inference.dart',
    ).readAsStringSync().replaceAll(RegExp(r'''['"]\s*\n\s*['"]'''), '');
    final reasons = {
      for (final match in RegExp(
        r'''(?:reason:|reasons\[id\] =)\s*(['"])(.+?)\1[,;]''',
      ).allMatches(source))
        match.group(2)!,
    };
    expect(reasons, hasLength(3));
    final polish = lookupAppLocalizations(const Locale('pl'));
    for (final reason in reasons) {
      expect(polish.routeReason(reason), isNot(reason), reason: reason);
    }
  });

  test('session names are translated, other run names kept', () {
    final polish = lookupAppLocalizations(const Locale('pl'));
    final english = lookupAppLocalizations(const Locale('en'));
    expect(polish.session('Session 2'), 'Sesja 2');
    expect(polish.session('Session 12'), 'Sesja 12');
    expect(english.session('Session 2'), 'Session 2');
    expect(polish.session('Session 2b'), 'Session 2b');
    expect(polish.session('Morning run'), 'Morning run');
  });

  group('numbers and dates', () {
    String all(BuildContext context) => [
      displayTime(109.898),
      displayTime(28.6624),
      displayDelta(-1.34),
      fixed(12.5, 1),
      context.l10n.direction(TrackDirection.clockwise),
    ].join(' | ');

    testWidgets('English uses a decimal point', (tester) async {
      await tester.pumpWidget(probe(all, locale: const Locale('en')));
      expect(
        find.text('1:49.898 | 28.662 s | −1.340 s | 12.5 | Clockwise'),
        findsOneWidget,
      );
    });

    testWidgets('Polish also uses a decimal point', (tester) async {
      await tester.pumpWidget(probe(all, locale: const Locale('pl')));
      expect(
        find.text(
          '1:49.898 | 28.662 s | −1.340 s | 12.5 | Zgodnie z ruchem wskazówek zegara',
        ),
        findsOneWidget,
      );
    });

    testWidgets('dates follow the language', (tester) async {
      final time = DateTime(2026, 10, 3, 6, 30);
      await tester.pumpWidget(
        probe((_) => displayDateTime(time), locale: const Locale('pl')),
      );
      expect(find.text('3 paź 2026, 06:30'), findsOneWidget);
      await tester.pumpWidget(
        probe((_) => displayDateTime(time), locale: const Locale('en')),
      );
      expect(find.text('Oct 3, 2026, 06:30'), findsOneWidget);
    });
  });
}
