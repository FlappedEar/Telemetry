import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:telemetry/day/day_results_controller.dart';
import 'package:telemetry/day/day_results_page.dart';
import 'package:telemetry/import/import_runner.dart';
import 'package:telemetry/main.dart';
import 'package:telemetry/profile/library_page.dart';
import 'package:telemetry/profile/profile_library.dart';
import 'package:telemetry/profile/track_notebook_page.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/day_results_page_test.dart' show FakeDocuments, circuitVbo;

final _route = RouteShape(
  origin: const GeoCoordinate(50.0, 19.0),
  points: [
    for (var i = 0; i < 256; ++i)
      MetricPoint(
        100 * math.cos(i * math.pi / 128),
        100 * math.sin(i * math.pi / 128),
      ),
  ],
  lengthMeters: 628,
  direction: TrackDirection.clockwise,
);

void main() {
  late Directory folder;
  setUp(() => folder = Directory.systemTemp.createTempSync('notebook'));
  tearDown(() => folder.deleteSync(recursive: true));

  Future<ProfileLibrary> library({TrackNotebook? notebook}) async {
    final profile = DriverProfile(
      driverId: 'driver',
      cars: [ProfileCar(id: 'clio', name: 'Clio')],
      tracks: [
        ProfileTrack(
          id: 'jastrzab',
          name: 'Jastrząb',
          route: _route,
          corners: [
            TrackCorner(id: 'k1', name: 'Corner 1', start: 0.1, end: 0.15),
            TrackCorner(id: 'k2', name: 'Corner 2', start: 0.4, end: 0.45),
          ],
          notebook: notebook,
        ),
      ],
      days: [
        ProfileDay(
          eventId: 'a',
          file: 'Days/a.fetproject',
          name: 'Day a',
          carId: 'clio',
          trackId: 'jastrzab',
          startMilliseconds: 1756454400000,
        ),
      ],
    );
    File('${folder.path}/$profileFileName')
        .writeAsStringSync(encodeDriverProfile(profile));
    final shelf = ProfileLibrary(
      store: FolderProfileStore(folder.path),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: <R>(FutureOr<R> Function() computation) async =>
          computation(),
    );
    await shelf.load();
    return shelf;
  }

  // The notebook as written to the profile file.
  TrackNotebook saved() => decodeDriverProfile(
    File('${folder.path}/$profileFileName').readAsStringSync(),
  ).track('jastrzab')!.notebook;

  testWidgets('opens from the library and keeps what is written', (
    tester,
  ) async {
    final shelf = await library();
    await tester.pumpWidget(
      TelemetryApp(
        home: LibraryPage(library: shelf, open: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trackNotebook jastrzab')));
    await tester.pumpAndSettle();
    expect(find.text('Notebook: Jastrząb'), findsOneWidget);
    expect(find.text('Nothing to try yet.'), findsOneWidget);

    // Two things to try, one ticked off, one removed.
    for (final text in ['Third gear in Corner 2', 'Later turn-in']) {
      await tester.enterText(
        find.byKey(const ValueKey('notebookNewItem')),
        text,
      );
      await tester.tap(find.byKey(const ValueKey('notebookAdd')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byKey(const ValueKey('notebookNewItem')), ' ');
    await tester.tap(find.byKey(const ValueKey('notebookAdd')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    await tester.tap(find.text('Third gear in Corner 2'));
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pumpAndSettle();

    // Notes and a corner's note, saved after typing pauses.
    await tester.enterText(
      find.byKey(const ValueKey('notebookNotes')),
      'Bumpy braking into Corner 1',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notebookCorner k2')),
      'Kerb on exit is fine',
    );
    await tester.pump(const Duration(seconds: 1));
    await shelf.flush();

    final notebook = shelf.profile!.track('jastrzab')!.notebook;
    expect(notebook.notes, 'Bumpy braking into Corner 1');
    expect(notebook.cornerNotes, {'k2': 'Kerb on exit is fine'});
    expect(
      [for (final item in notebook.toTry) (item.text, item.done)],
      [('Third gear in Corner 2', true)],
    );
    final written = saved();
    expect(written.notes, notebook.notes);
    expect(written.cornerNotes, notebook.cornerNotes);
    expect(
      [for (final item in written.toTry) item.text],
      ['Third gear in Corner 2'],
    );
  });

  testWidgets('leaving before typing pauses still keeps the note', (
    tester,
  ) async {
    final shelf = await library();
    await tester.pumpWidget(
      TelemetryApp(
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notebookCorner k1')),
      'Brake at the 100 board',
    );
    await tester.pumpWidget(const SizedBox());
    await shelf.flush();
    expect(saved().cornerNotes, {'k1': 'Brake at the 100 board'});
  });

  testWidgets('shows what the notebook holds, keeping what it does not show', (
    tester,
  ) async {
    final shelf = await library(
      notebook: TrackNotebook(
        notes: 'Dry line',
        cornerNotes: {'k1': 'Late apex', 'gone': 'A corner no longer listed'},
        toTry: [NotebookItem(id: 'i1', text: 'Kerb on exit', done: true)],
      ),
    );
    await tester.pumpWidget(
      TelemetryApp(
        locale: const Locale('pl'),
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notatnik: Jastrząb'), findsOneWidget);
    expect(find.text('Zrobione'), findsOneWidget);
    expect(find.text('Dry line'), findsOneWidget);
    expect(find.text('Late apex'), findsOneWidget);
    // Corner names in Polish.
    expect(find.text('Zakręt 1'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('notebookNotes')),
      'Dry line, damp under the trees',
    );
    await tester.pump(const Duration(seconds: 1));
    await shelf.flush();
    expect(saved().cornerNotes, {
      'k1': 'Late apex',
      'gone': 'A corner no longer listed',
    });
    expect(saved().notes, 'Dry line, damp under the trees');
  });

  testWidgets('what the library gains while the page is open joins it', (
    tester,
  ) async {
    final shelf = await library(
      notebook: TrackNotebook(
        toTry: [NotebookItem(id: 'i1', text: 'Kerb on exit')],
      ),
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('notebookCorner k1')),
      'Typed here',
    );
    // An import while the page is open: notes and a thing to try.
    final live = shelf.profile!.track('jastrzab')!.notebook;
    shelf.setTrackNotebook(
      'jastrzab',
      TrackNotebook(
        notes: 'Imported notes',
        cornerNotes: {'k2': 'Imported corner'},
        toTry: [
          ...live.toTry,
          NotebookItem(id: 'i2', text: 'Imported to try'),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Imported notes'), findsOneWidget);
    expect(find.text('Imported corner'), findsOneWidget);
    expect(find.text('Imported to try'), findsOneWidget);
    expect(find.text('Typed here'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await shelf.flush();
    final written = saved();
    expect(written.notes, 'Imported notes');
    expect(written.cornerNotes, {'k1': 'Typed here', 'k2': 'Imported corner'});
    expect(
      [for (final item in written.toTry) item.text],
      ['Kerb on exit', 'Imported to try'],
    );
  });

  testWidgets('a full list says so instead of offering to add', (tester) async {
    final shelf = await library(
      notebook: TrackNotebook(
        toTry: [
          for (var i = 0; i < maximumNotebookItems; ++i)
            NotebookItem(id: 'i$i', text: 'Item $i', done: true),
        ],
      ),
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('notebookNewItem')), findsNothing);
    expect(
      find.text(
        'The notebook holds at most 256 things to try. '
        'Remove some to add more.',
      ),
      findsOneWidget,
    );
  });

  testWidgets("opens from a day's menu on the day's track", (tester) async {
    final path = '${folder.path}/a.vbo';
    File(path).writeAsStringSync(circuitVbo([30, 28, 31]));
    final day = runDayImport((paths: [path], includeSubfolders: false));
    final shelf = ProfileLibrary(
      store: FolderProfileStore('${folder.path}/Profile'),
      defaultCarName: 'My car',
      defaultTrackName: (number) => 'Track $number',
      background: <R>(FutureOr<R> Function() computation) async =>
          computation(),
    );
    await shelf.load();
    final controller = DayResultsController(
      runs: day.runs,
      analysis: day.analysis!,
      // Written on the test's thread, so its fake clock can run it.
      writer: (path, document) async =>
          File(path).writeAsStringSync(jsonEncode(document)),
    );
    await tester.pumpWidget(
      TelemetryApp(
        home: DayResultsPage.controller(
          controller: controller,
          documents: FakeDocuments(location: '${folder.path}/d.fetproject'),
          library: shelf,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(shelf.profile?.day(controller.eventId)?.trackId, isNotNull);
    await tester.tap(find.byKey(const ValueKey('moreMenu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('trackNotebookMenuItem')));
    await tester.pumpAndSettle();
    expect(find.byType(TrackNotebookPage), findsOneWidget);
    expect(find.text('Notebook: Track 1'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await shelf.flush();
  });

  testWidgets('an import while typing joins what is typed', (tester) async {
    final shelf = await library(notebook: TrackNotebook(notes: 'Mine'));
    await tester.pumpWidget(
      TelemetryApp(
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    // Kept without the line break the field still holds.
    await tester.enterText(
      find.byKey(const ValueKey('notebookNotes')),
      'Mine\n',
    );
    await tester.pump(const Duration(seconds: 1));
    expect(shelf.profile!.track('jastrzab')!.notebook.notes, 'Mine');
    shelf.setTrackNotebook(
      'jastrzab',
      TrackNotebook(notes: 'Mine\n\nImported', cornerNotes: {'k1': 'Theirs'}),
    );
    await tester.pumpAndSettle();
    // The line break typed after the note stays.
    expect(find.text('Mine\n\nImported\n'), findsOneWidget);
    // Typing not kept yet, when an import adds to the same note.
    await tester.enterText(
      find.byKey(const ValueKey('notebookCorner k1')),
      'Theirs, and mine',
    );
    await tester.enterText(
      find.byKey(const ValueKey('notebookNotes')),
      'Mine, longer',
    );
    shelf.setTrackNotebook(
      'jastrzab',
      TrackNotebook(
        notes: 'Mine\n\nImported\n\nMore',
        cornerNotes: {'k1': 'Theirs'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mine, longer\n\nMore'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await shelf.flush();
    expect(saved().notes, 'Mine, longer\n\nMore');
    expect(saved().cornerNotes, {'k1': 'Theirs, and mine'});
  });

  testWidgets('saving leaves the field as typed, save after save', (
    tester,
  ) async {
    final shelf = await library();
    await tester.pumpWidget(
      TelemetryApp(
        home: TrackNotebookPage(library: shelf, trackId: 'jastrzab'),
      ),
    );
    await tester.pumpAndSettle();
    final notes = find.byKey(const ValueKey('notebookNotes'));
    final corner = find.byKey(const ValueKey('notebookCorner k1'));
    String text(Finder field) =>
        tester.widget<TextField>(field).controller!.text;
    await tester.enterText(notes, 'Brake');
    await tester.enterText(corner, 'Apex');
    await tester.pump(const Duration(seconds: 1));
    expect(text(notes), 'Brake');
    expect(text(corner), 'Apex');
    await tester.enterText(notes, 'Brake late');
    await tester.enterText(corner, 'Apex late');
    await tester.pump(const Duration(seconds: 1));
    expect(text(notes), 'Brake late');
    expect(text(corner), 'Apex late');
    // Another write: a thing to try.
    await tester.enterText(
      find.byKey(const ValueKey('notebookNewItem')),
      'Third gear',
    );
    await tester.tap(find.byKey(const ValueKey('notebookAdd')));
    await tester.pumpAndSettle();
    expect(text(notes), 'Brake late');
    await shelf.flush();
    expect(saved().notes, 'Brake late');
    expect(saved().cornerNotes, {'k1': 'Apex late'});
  });
}
