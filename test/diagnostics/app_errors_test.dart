import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/diagnostics/app_errors.dart';
import 'package:telemetry/diagnostics/diagnostics_page.dart';
import 'package:telemetry/l10n.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry_core/telemetry_core.dart';

void main() {
  group('AppErrors', () {
    test('keeps the newest errors with their context and stack', () {
      final errors = AppErrors(
        capacity: 2,
        clock: () => DateTime.utc(2026, 10, 4, 6),
      );
      errors.record(StateError('first'), null);
      errors.record(
        StateError('second\nmore'),
        StackTrace.fromString('#0 main (file.dart:1)'),
        context: 'Saving the day',
      );
      errors.record(ArgumentError('third'), null);

      expect(errors.records.map((record) => record.summary), [
        'Saving the day: Bad state: second',
        'Invalid argument(s): third',
      ]);
      expect(errors.dropped, 1);
      expect(errors.records.first.details, contains('#0 main (file.dart:1)'));
      expect(errors.report(), startsWith('(1 earlier error not kept)'));
      expect(errors.report(), contains('2026-10-04T06:00:00.000Z'));

      errors.clear();
      expect(errors.records, isEmpty);
      expect(errors.dropped, 0);
    });

    test('counts a repeated error instead of pushing out the first', () {
      var now = DateTime.utc(2026, 10, 4, 6);
      final errors = AppErrors(capacity: 2, clock: () => now);
      errors.record(StateError('root cause'), StackTrace.fromString('#0 a'));
      for (var i = 0; i < 50; ++i) {
        now = now.add(const Duration(seconds: 1));
        errors.record(StateError('repeating'), StackTrace.fromString('#0 b'));
      }
      expect(errors.records.map((record) => record.summary), [
        'Bad state: root cause',
        'Bad state: repeating',
      ]);
      expect(errors.records.last.count, 50);
      expect(errors.dropped, 0);
      expect(
        errors.report(),
        contains(
          '2026-10-04T06:00:50.000Z (50 times since 2026-10-04T06:00:01',
        ),
      );
    });

    test('cuts a very long message to one line of 300 characters', () {
      final errors = AppErrors()..record('x' * 1000, null);
      expect(errors.records.single.summary, hasLength(301));
    });
  });

  testWidgets('an unhandled error is kept and points to Diagnostics', (
    tester,
  ) async {
    final errors = AppErrors();
    final messenger = GlobalKey<ScaffoldMessengerState>();
    final reporter = AppErrorReporter(errors, messenger);
    await tester.pumpWidget(
      MaterialApp(
        scaffoldMessengerKey: messenger,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: supportedLocales,
        home: const Scaffold(body: SizedBox()),
      ),
    );

    expect(
      reporter.platformError(StateError('lost'), StackTrace.empty),
      isTrue,
    );
    expect(errors.records.single.summary, 'Bad state: lost');
    await tester.pump(); // The message is shown after this frame,
    await tester.pump(); // and built in the next.
    expect(
      find.text('Something went wrong. Details are in Diagnostics.'),
      findsOneWidget,
    );

    // A build error keeps what the app was doing.
    reporter.flutterError(
      FlutterErrorDetails(
        exception: StateError('drawn'),
        context: ErrorDescription('while painting'),
      ),
    );
    expect(errors.records.last.summary, 'while painting: Bad state: drawn');
    expect(errors.records, hasLength(2));
    await tester.pumpAndSettle(const Duration(seconds: 10));
  });

  test('keeps the defects telemetry_core caught, with their traces', () {
    final errors = AppErrors();
    final reporter = AppErrorReporter(
      errors,
      GlobalKey<ScaffoldMessengerState>(),
    );
    reporter.coreDefects(
      plan: TelemetryImportPlan(
        runs: [],
        files: const [
          TelemetryImportFileResult(
            requestedPath: '/day/a.vbo',
            status: TelemetryImportFileStatus.error,
            message: '${unexpectedFileError}RangeError: index 9',
            detail: '#0 parse (vbo_parser.dart:1)',
          ),
          TelemetryImportFileResult(
            requestedPath: '/day/b.vbo',
            status: TelemetryImportFileStatus.error,
            message: 'Telemetry file is empty.',
          ),
        ],
        possibleSameRuns: [],
      ),
      messages: const [
        DayMessage(
          'run:1',
          '${unexpectedRunError}Null check operator',
          detail: '#0 laps (day_laps.dart:2)',
        ),
        DayMessage(
          'run:2',
          'No reliable start/finish passes; lap type is unknown.',
        ),
      ],
      notes: ['c.vbo: ${unexpectedFileError}TypeError'],
    );
    expect(errors.records.map((record) => record.summary), [
      'Adding recordings: c.vbo: ${unexpectedFileError}TypeError',
      'Reading a.vbo: RangeError: index 9',
      'Analysing run run:1: Null check operator',
    ]);
    expect(errors.records[1].details, contains('vbo_parser.dart:1'));
    expect(errors.records[2].details, contains('day_laps.dart:2'));
  });

  testWidgets('installErrorHandlers keeps the previous handler', (
    tester,
  ) async {
    final flutterHandler = FlutterError.onError;
    final platformHandler = PlatformDispatcher.instance.onError;
    final errors = AppErrors();
    final passedOn = <FlutterErrorDetails>[];
    try {
      FlutterError.onError = passedOn.add;
      installErrorHandlers(
        reporter: AppErrorReporter(errors, GlobalKey<ScaffoldMessengerState>()),
      );
      FlutterError.onError!(
        FlutterErrorDetails(
          exception: StateError('drawn'),
          context: ErrorDescription('while painting'),
        ),
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('lost'),
          StackTrace.empty,
        ),
        isTrue,
      );
    } finally {
      FlutterError.onError = flutterHandler;
      PlatformDispatcher.instance.onError = platformHandler;
    }
    expect(passedOn, hasLength(1));
    expect(errors.records.map((record) => record.summary), [
      'while painting: Bad state: drawn',
      'Bad state: lost',
    ]);
  });

  test('defects are named in the app language', () {
    final pl = lookupAppLocalizations(const Locale('pl'));
    expect(
      pl.dayNote('${unexpectedRunError}boom'),
      'Nieoczekiwany błąd podczas analizy tej sesji: boom',
    );
  });

  group('FailedPart', () {
    Widget app(Widget child, {Locale locale = const Locale('en')}) =>
        MaterialApp(
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: supportedLocales,
          home: Scaffold(body: child),
        );

    testWidgets('says the part could not be shown, in the app language', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(const FailedPart(), locale: const Locale('pl')),
      );
      expect(
        find.textContaining('Nie udało się wyświetlić tej części.'),
        findsOneWidget,
      );
    });

    testWidgets('lays out where width or height is unbounded', (tester) async {
      await tester.pumpWidget(
        app(
          const SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                Row(children: [FailedPart()]),
                SizedBox(height: 0, width: 0, child: FailedPart()),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(FailedPart), findsNWidgets(2));
    });

    testWidgets('outside the app it falls back to the framework box', (
      tester,
    ) async {
      await tester.pumpWidget(const FailedPart());
      expect(find.byType(ErrorWidget), findsOneWidget);
    });
  });

  testWidgets('Diagnostics lists the errors and copies them', (tester) async {
    final errors = AppErrors()
      ..record(
        StateError('broken'),
        StackTrace.fromString('#0 frame'),
        context: 'Recovery snapshot not updated',
      );
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      TelemetryApp(
        home: DiagnosticsPage(
          errors: errors,
          memory: () => (current: null, peak: null),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('copyErrors')),
      100,
    );
    expect(
      find.text('Recovery snapshot not updated: Bad state: broken'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('copyErrors')));
    await tester.pump();
    expect(copied, contains('#0 frame'));
    expect(
      find.text('Errors copied. Paste them into a bug report.'),
      findsOneWidget,
    );
  });

  testWidgets('Diagnostics says when there were no errors', (tester) async {
    await tester.pumpWidget(
      TelemetryApp(
        home: DiagnosticsPage(
          errors: AppErrors(),
          memory: () => (current: null, peak: null),
        ),
      ),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('diagnosticsNoErrors')),
      100,
    );
    expect(find.text('No errors since the app started.'), findsOneWidget);
  });

  test('a session number too long for an int is shown as written', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    expect(
      l10n.session('Session 99999999999999999999'),
      'Session 99999999999999999999',
    );
    expect(l10n.session('Session 3'), 'Session 3');
  });
}
