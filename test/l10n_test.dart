import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
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
            expect(
              translated[key],
              contains('{$name}'),
              reason: '$language $key',
            );
          }
        }
      });
    }
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

    testWidgets('Polish uses a decimal comma', (tester) async {
      await tester.pumpWidget(probe(all, locale: const Locale('pl')));
      expect(
        find.text('1:49,898 | 28,662 s | −1,340 s | 12,5 | Zgodnie z zegarem'),
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
