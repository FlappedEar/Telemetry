import 'dart:convert';
import 'dart:math';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

/// A profile with one day on a circle, its track given two corners.
DriverProfile _profile({int seed = 1, String eventId = 'a'}) {
  final session = circuitSession(radius: 100, speeds: const [30, 29, 31, 30]);
  final profile = addDayToProfile(
    DriverProfile.empty(Random(seed)),
    ProfileDayInput.fromAnalysis(
      eventId: eventId,
      file: 'Days/$eventId.fetproject',
      name: 'Day $eventId',
      analysis: analyzeDay([
        DayRunInput(
          runId: 'run1',
          name: 'Session 1',
          contentSha256: 'a' * 64,
          session: session,
          laps: deriveSourceLapSession(session),
        ),
      ]),
    ),
    defaultCarName: 'My car',
    defaultTrackName: 'Track',
    random: Random(seed),
  );
  final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
  final track = (json['tracks'] as List).single as Map<String, Object?>;
  track['corners'] = [
    {'id': 'c1', 'name': 'Corner 1', 'start': 0.1, 'end': 0.2},
    {'id': 'c2', 'name': 'Corner 2', 'start': 0.5, 'end': 0.6},
  ];
  return decodeDriverProfile(jsonEncode(json));
}

Map<String, Object?> _trackJson(DriverProfile profile) =>
    ((jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>)['tracks'] as List).single
        as Map<String, Object?>;

DriverProfile _withTrackJson(DriverProfile profile, void Function(Map<String, Object?>) edit) {
  final json = jsonDecode(encodeDriverProfile(profile)) as Map<String, Object?>;
  edit((json['tracks'] as List).single as Map<String, Object?>);
  return decodeDriverProfile(jsonEncode(json));
}

void main() {
  test('a track starts with an empty notebook, which is not written', () {
    final profile = _profile();
    expect(profile.tracks.single.notebook.isEmpty, isTrue);
    expect(_trackJson(profile).containsKey('notebook'), isFalse);
  });

  test('a notebook is kept and reads back the same', () {
    final profile = _profile();
    final trackId = profile.tracks.single.id;
    final next = setProfileTrackNotebook(
      profile,
      trackId,
      TrackNotebook(
        notes: 'Bumpy on the outside of T1.\n',
        cornerNotes: {'c1': 'Brake at the 100 board', 'c2': '  '},
        toTry: [
          NotebookItem(id: 'i1', text: 'Third gear in Corner 2'),
          NotebookItem(id: 'i2', text: ' ', done: true),
          NotebookItem(id: 'i3', text: 'Later turn-in', done: true),
          NotebookItem(id: 'i1', text: 'The same id again'),
        ],
      ),
    );
    final notebook = next.tracks.single.notebook;
    expect(notebook.notes, 'Bumpy on the outside of T1.');
    // Blank corner notes and blank or repeated things to try are left out.
    expect(notebook.cornerNotes, {'c1': 'Brake at the 100 board'});
    expect(
      [for (final item in notebook.toTry) (item.id, item.text, item.done)],
      [('i1', 'Third gear in Corner 2', false), ('i3', 'Later turn-in', true)],
    );
    expect([for (final item in notebook.open) item.id], ['i1']);
    expect(_trackJson(next)['notebook'], {
      'notes': 'Bumpy on the outside of T1.',
      'corners': [
        {'cornerId': 'c1', 'note': 'Brake at the 100 board'},
      ],
      'toTry': [
        {'id': 'i1', 'text': 'Third gear in Corner 2', 'done': false},
        {'id': 'i3', 'text': 'Later turn-in', 'done': true},
      ],
    });
    final read = decodeDriverProfile(encodeDriverProfile(next)).tracks.single.notebook;
    expect(read.notes, notebook.notes);
    expect(read.cornerNotes, notebook.cornerNotes);
    expect([for (final item in read.toTry) item.text], ['Third gear in Corner 2', 'Later turn-in']);
    // Emptied, the notebook is no longer written.
    expect(
      _trackJson(setProfileTrackNotebook(next, trackId, TrackNotebook())).containsKey('notebook'),
      isFalse,
    );
    // Another track id changes nothing.
    expect(setProfileTrackNotebook(next, 'nope', TrackNotebook()), same(next));
  });

  test('keys this version does not know are kept, and through an edit', () {
    final profile = _withTrackJson(_profile(), (track) {
      track['notebook'] = {
        'notes': 'Dry line',
        'markers': ['board'],
        'corners': [
          {'cornerId': 'c1', 'note': 'Late apex', 'gear': 3},
        ],
        'toTry': [
          {'id': 'i1', 'text': 'Kerb on exit', 'done': false, 'priority': 1},
        ],
      };
    });
    final notebook = profile.tracks.single.notebook;
    final edited = setProfileTrackNotebook(
      profile,
      profile.tracks.single.id,
      TrackNotebook(
        notes: 'Dry line, damp under the trees',
        cornerNotes: notebook.cornerNotes,
        toTry: [for (final item in notebook.toTry) item.copyWith(done: true)],
        unknown: notebook.unknown,
        unknownCorners: notebook.unknownCorners,
      ),
    );
    expect(_trackJson(edited)['notebook'], {
      'markers': ['board'],
      'notes': 'Dry line, damp under the trees',
      'corners': [
        {'gear': 3, 'cornerId': 'c1', 'note': 'Late apex'},
      ],
      'toTry': [
        {'priority': 1, 'id': 'i1', 'text': 'Kerb on exit', 'done': true},
      ],
    });
  });

  test('a malformed notebook is not read', () {
    for (final notebook in <Object?>[
      'notes',
      {'notes': 3},
      {
        'toTry': [
          {'id': 'i1', 'text': 'x', 'done': 'yes'},
        ],
      },
      {
        'toTry': [
          {'id': 'i1', 'text': 'x'},
          {'id': 'i1', 'text': 'y'},
        ],
      },
      {
        'corners': [
          {'cornerId': '', 'note': 'x'},
        ],
      },
      {
        'toTry': [
          for (var i = 0; i <= maximumNotebookItems; ++i) {'id': 'i$i', 'text': 'x'},
        ],
      },
      {'notes': 'x' * (maximumProfileTextCharacters + 1)},
    ]) {
      expect(
        () => _withTrackJson(_profile(), (track) => track['notebook'] = notebook),
        throwsA(isA<ProfileFormatError>()),
        reason: '$notebook',
      );
    }
  });

  test('a long note is cut to the profile limit', () {
    final profile = _profile();
    final next = setProfileTrackNotebook(
      profile,
      profile.tracks.single.id,
      TrackNotebook(notes: 'x' * (maximumProfileTextCharacters + 10)),
    );
    expect(next.tracks.single.notebook.notes.length, maximumProfileTextCharacters);
  });

  group('importing a profile', () {
    test('a new track brings its notebook', () {
      final there = _profile(seed: 2, eventId: 'b');
      final noted = setProfileTrackNotebook(
        there,
        there.tracks.single.id,
        TrackNotebook(notes: 'Their notes'),
      );
      final merged = mergeDriverProfile(DriverProfile.empty(Random(3)), noted);
      expect(merged.profile.tracks.single.notebook.notes, 'Their notes');
    });

    test('the same track joins both notebooks, replacing nothing of mine', () {
      final here = _profile();
      final mine = setProfileTrackNotebook(
        here,
        here.tracks.single.id,
        TrackNotebook(
          notes: 'My notes',
          cornerNotes: {'c1': 'Mine'},
          toTry: [NotebookItem(id: 'i1', text: 'Mine to try')],
        ),
      );
      // The same track, the same corners, on another device.
      final away = _profile(eventId: 'b');
      final theirs = setProfileTrackNotebook(
        away,
        away.tracks.single.id,
        TrackNotebook(
          notes: 'Their notes',
          cornerNotes: {'c1': 'Theirs', 'c2': 'Theirs too'},
          toTry: [
            NotebookItem(id: 'i1', text: 'Mine to try'),
            NotebookItem(id: 'i9', text: 'mine to try '),
            NotebookItem(id: 'i2', text: 'Theirs to try'),
          ],
        ),
      );
      final merged = mergeDriverProfile(mine, theirs).profile;
      expect(merged.tracks, hasLength(1));
      final notebook = merged.tracks.single.notebook;
      expect(notebook.notes, 'My notes\n\nTheir notes');
      // Their note on a corner I have a note on follows mine.
      expect(notebook.cornerNotes, {'c1': 'Mine\nTheirs', 'c2': 'Theirs too'});
      expect([for (final item in notebook.toTry) item.text], ['Mine to try', 'Theirs to try']);
      // Importing again adds nothing more, though the merge runs again.
      final repeat = mergeDriverProfile(merged, theirs);
      expect(repeat.alreadyHere, ['b']);
      expect(repeat.notebooks, isEmpty);
      final again = repeat.profile.tracks.single.notebook;
      expect(again.notes, notebook.notes);
      expect(again.cornerNotes, notebook.cornerNotes);
      expect(again.toTry, hasLength(2));
    });

    test('notebooks join when both devices already have the same days', () {
      final here = _profile();
      final away = _profile();
      final theirs = setProfileTrackNotebook(
        away,
        away.tracks.single.id,
        TrackNotebook(
          notes: 'Their notes',
          toTry: [NotebookItem(id: 'i1', text: 'Try')],
        ),
      );
      final merge = mergeDriverProfile(here, theirs);
      expect(merge.added, isEmpty);
      expect(merge.alreadyHere, ['a']);
      expect(merge.notebooks, [here.tracks.single.id]);
      expect(merge.notebookCut, isFalse);
      expect(merge.profile.tracks.single.notebook.notes, 'Their notes');
      expect(merge.profile.tracks.single.notebook.toTry.single.text, 'Try');
      // Even when no day of the track is chosen.
      expect(
        mergeDriverProfile(here, theirs, only: const {}).profile.tracks.single.notebook.notes,
        'Their notes',
      );
    });

    test("a note on a corner this track does not have joins the notes, by the corner's name", () {
      final here = _profile();
      final away = _withTrackJson(_profile(), (track) {
        (track['corners'] as List).add({'id': 'c3', 'name': 'Corner 3', 'start': 0.8, 'end': 0.9});
      });
      final theirs = setProfileTrackNotebook(
        away,
        away.tracks.single.id,
        TrackNotebook(cornerNotes: {'c2': 'Second', 'c3': 'Third'}),
      );
      final notebook = mergeDriverProfile(here, theirs).profile.tracks.single.notebook;
      expect(notebook.cornerNotes, {'c2': 'Second'});
      expect(notebook.notes, 'Corner 3: Third');
      expect(here.tracks.single.corners, hasLength(2));
    });

    test('what does not fit is left out whole and reported', () {
      final here = _profile();
      final mine = setProfileTrackNotebook(
        here,
        here.tracks.single.id,
        TrackNotebook(
          notes: 'm' * 3000,
          toTry: [
            for (var i = 0; i < maximumNotebookItems - 1; ++i)
              NotebookItem(id: 'm$i', text: 'Mine $i'),
          ],
        ),
      );
      final away = _profile();
      final theirs = setProfileTrackNotebook(
        away,
        away.tracks.single.id,
        TrackNotebook(
          notes: 't' * 3000,
          cornerNotes: {'c1': 'Fits'},
          toTry: [
            NotebookItem(id: 't1', text: 'Theirs 1'),
            NotebookItem(id: 't2', text: 'Theirs 2'),
          ],
        ),
      );
      final merge = mergeDriverProfile(mine, theirs);
      expect(merge.notebookCut, isTrue);
      final notebook = merge.profile.tracks.single.notebook;
      expect(notebook.notes, 'm' * 3000);
      expect(notebook.cornerNotes, {'c1': 'Fits'});
      expect(notebook.toTry, hasLength(maximumNotebookItems));
      expect(notebook.toTry.last.text, 'Theirs 1');
    });
  });

  test('a cleared note or blank thing to try keeps what a newer version wrote on it', () {
    final profile = _withTrackJson(_profile(), (track) {
      track['notebook'] = {
        'corners': [
          {'cornerId': 'c1', 'note': 'Late apex', 'gear': 3},
          {'cornerId': 'c2', 'note': '', 'marker': 'board'},
        ],
        'toTry': [
          {'id': 'i1', 'text': '', 'done': false, 'sketch': 'x'},
          {'id': 'i2', 'text': ' ', 'done': false},
        ],
      };
    });
    final notebook = profile.tracks.single.notebook;
    expect(notebook.cornerNotes, {'c1': 'Late apex'});
    final edited = setProfileTrackNotebook(
      profile,
      profile.tracks.single.id,
      TrackNotebook(
        cornerNotes: {'c1': ''},
        toTry: notebook.toTry,
        unknown: notebook.unknown,
        unknownCorners: notebook.unknownCorners,
      ),
    );
    expect(_trackJson(edited)['notebook'], {
      'corners': [
        {'gear': 3, 'cornerId': 'c1', 'note': ''},
        {'marker': 'board', 'cornerId': 'c2', 'note': ''},
      ],
      'toTry': [
        {'sketch': 'x', 'id': 'i1', 'text': '', 'done': false},
      ],
    });
  });

  test('a notebook past the limits is refused, not written', () {
    final profile = _profile();
    expect(
      () => setProfileTrackNotebook(
        profile,
        profile.tracks.single.id,
        TrackNotebook(cornerNotes: {for (var i = 0; i <= maximumProfileCorners; ++i) 'k$i': 'x'}),
      ),
      throwsA(isA<ProfileFormatError>()),
    );
  });
}
