// The track notebook (FET-231, idea 16 of FET-217): what the driver writes
// down about a circuit for the next visit. General notes, a note per corner
// (on the track's own corners, the same on every visit) and things to try,
// ticked off when done. Kept on the track in the driver profile, so every
// day on the track shares it and a profile export carries it.
part of 'driver_profile.dart';

/// The most things to try a notebook holds.
const maximumNotebookItems = 256;

/// One thing to try at the track.
final class NotebookItem {
  NotebookItem({
    required this.id,
    required this.text,
    this.done = false,
    Map<String, Object?> unknown = const {},
  }) : unknown = Map.unmodifiable(unknown);

  final String id;
  final String text;
  final bool done;
  final Map<String, Object?> unknown;

  NotebookItem copyWith({String? text, bool? done}) =>
      NotebookItem(id: id, text: text ?? this.text, done: done ?? this.done, unknown: unknown);
}

/// A track's notebook.
final class TrackNotebook {
  TrackNotebook({
    this.notes = '',
    Map<String, String> cornerNotes = const {},
    List<NotebookItem> toTry = const [],
    Map<String, Object?> unknown = const {},
    Map<String, Map<String, Object?>> unknownCorners = const {},
  }) : cornerNotes = Map.unmodifiable(cornerNotes),
       toTry = List.unmodifiable(toTry),
       unknown = Map.unmodifiable(unknown),
       unknownCorners = Map.unmodifiable(unknownCorners);

  /// About the track as a whole.
  final String notes;

  /// By the id of one of the track's corners ([ProfileTrack.corners]).
  final Map<String, String> cornerNotes;

  /// In the order added.
  final List<NotebookItem> toTry;
  final Map<String, Object?> unknown;

  /// Each corner note's keys this version does not know, by corner id, so
  /// a re-save keeps them.
  final Map<String, Map<String, Object?>> unknownCorners;

  bool get isEmpty =>
      notes.trim().isEmpty &&
      cornerNotes.isEmpty &&
      toTry.isEmpty &&
      unknown.isEmpty &&
      unknownCorners.isEmpty;

  /// The things to try not ticked off yet.
  List<NotebookItem> get open => [
    for (final item in toTry)
      if (!item.done) item,
  ];
}

/// A note as the profile keeps it: trimmed at the end, bounded, and
/// without NUL characters.
String _note(String value) {
  final text = value.replaceAll('\u0000', '').trimRight();
  return text.length > maximumProfileTextCharacters
      ? text.substring(0, maximumProfileTextCharacters)
      : text;
}

/// [profile] with [notebook] as track [trackId]'s. Notes are bounded as
/// every profile text is; blank corner notes and blank things to try are
/// left out, unless they carry keys a newer version wrote. Unchanged when
/// the track is not in the profile; throws [ProfileFormatError] when the
/// notebook is past the profile's limits.
DriverProfile setProfileTrackNotebook(
  DriverProfile profile,
  String trackId,
  TrackNotebook notebook,
) {
  if (profile.track(trackId) == null) return profile;
  final items = <NotebookItem>[];
  final ids = <String>{};
  for (final item in notebook.toTry) {
    final text = _note(item.text);
    // A blank thing to try goes, unless a newer version keeps more on it.
    if ((text.trim().isEmpty && item.unknown.isEmpty) ||
        !ids.add(item.id) ||
        items.length >= maximumNotebookItems) {
      continue;
    }
    items.add(item.copyWith(text: text));
  }
  final cleaned = TrackNotebook(
    notes: _note(notebook.notes),
    cornerNotes: {
      for (final MapEntry(:key, :value) in notebook.cornerNotes.entries)
        if (_note(value).trim().isNotEmpty) key: _note(value),
    },
    toTry: items,
    unknown: notebook.unknown,
    unknownCorners: notebook.unknownCorners,
  );
  return profile._copy(
    tracks: [
      for (final track in profile.tracks)
        track.id == trackId
            ? _verified(_encodeTrack(track.copyWith(notebook: cleaned)), _track)
            : track,
    ],
  );
}

/// A new id for a thing to try.
String newNotebookItemId([Random? random]) => newEventId(random);

/// [mine] with what [theirs] adds (an imported profile's notebook for the
/// same track), and whether anything of theirs did not fit. Their notes
/// follow mine when mine do not hold them; a note on a corner both have
/// follows mine the same way; a note on a corner of theirs that is not one
/// of this track's ([ids] maps their corner ids to this track's) joins the
/// general notes under the corner's name ([names]); their things to try not
/// already here (by id or text) follow mine. Nothing of mine is replaced,
/// and text past the profile's limits is left out, never cut.
(TrackNotebook, bool) _mergeNotebook(
  TrackNotebook mine,
  TrackNotebook theirs, {
  required Map<String, String> ids,
  required Map<String, String> names,
}) {
  var cut = false;
  String joined(String here, String there, String between) {
    final text = _note(there).trim();
    if (text.isEmpty || here.contains(text)) return here;
    if (here.trim().isEmpty) return text;
    final both = '$here$between$text';
    if (both.length > maximumProfileTextCharacters) {
      cut = true;
      return here;
    }
    return both;
  }

  var notes = joined(mine.notes, theirs.notes, '\n\n');
  final cornerNotes = {...mine.cornerNotes};
  final unknownCorners = {...mine.unknownCorners};
  for (final key in {...theirs.cornerNotes.keys, ...theirs.unknownCorners.keys}) {
    final value = theirs.cornerNotes[key] ?? '';
    final id = ids[key];
    if (id == null) {
      if (value.trim().isNotEmpty) {
        notes = joined(notes, '${names[key] ?? key}: $value', '\n\n');
      }
      continue;
    }
    if (!cornerNotes.containsKey(id) &&
        !unknownCorners.containsKey(id) &&
        {...cornerNotes.keys, ...unknownCorners.keys}.length >= maximumProfileCorners) {
      cut = true;
      continue;
    }
    if (value.trim().isNotEmpty) cornerNotes[id] = joined(cornerNotes[id] ?? '', value, '\n');
    if (theirs.unknownCorners[key] case final unknown? when !unknownCorners.containsKey(id)) {
      unknownCorners[id] = unknown;
    }
  }
  final itemIds = {for (final item in mine.toTry) item.id};
  final texts = {for (final item in mine.toTry) item.text.trim().toLowerCase()};
  final toTry = [...mine.toTry];
  for (final item in theirs.toTry) {
    final text = _note(item.text);
    if (itemIds.contains(item.id) || texts.contains(text.trim().toLowerCase())) continue;
    if (text.trim().isEmpty && item.unknown.isEmpty) continue;
    if (toTry.length >= maximumNotebookItems) {
      cut = true;
      break;
    }
    toTry.add(item.copyWith(text: text));
    itemIds.add(item.id);
    texts.add(text.trim().toLowerCase());
  }
  return (
    TrackNotebook(
      notes: notes,
      cornerNotes: cornerNotes,
      toTry: toTry,
      unknown: {...theirs.unknown, ...mine.unknown},
      unknownCorners: unknownCorners,
    ),
    cut,
  );
}

Map<String, Object?> _encodeNotebook(TrackNotebook notebook) => {
  ...notebook.unknown,
  if (notebook.notes.isNotEmpty) 'notes': notebook.notes,
  if (notebook.cornerNotes.isNotEmpty || notebook.unknownCorners.isNotEmpty)
    'corners': [
      // A corner whose note was cleared keeps what a newer version wrote.
      for (final key in {...notebook.cornerNotes.keys, ...notebook.unknownCorners.keys})
        {
          ...?notebook.unknownCorners[key],
          'cornerId': key,
          'note': notebook.cornerNotes[key] ?? '',
        },
    ],
  if (notebook.toTry.isNotEmpty)
    'toTry': [
      for (final item in notebook.toTry)
        {...item.unknown, 'id': item.id, 'text': item.text, 'done': item.done},
    ],
};

TrackNotebook _notebook(Object? value) {
  final json = _map(value, 'track notebook');
  final corners = _list(json['corners'], 'notebook corners', maximumProfileCorners, (value) {
    final corner = _map(value, 'notebook corner');
    return (
      id: _string(corner['cornerId'], 'notebook corner id', allowEmpty: false),
      note: _string(corner['note'], 'notebook corner note'),
      unknown: _without(corner, const ['cornerId', 'note']),
    );
  });
  _unique([for (final corner in corners) corner.id], 'notebook corner');
  final items = _list(json['toTry'], 'things to try', maximumNotebookItems, (value) {
    final item = _map(value, 'thing to try');
    final done = item['done'] ?? false;
    if (done is! bool) throw const ProfileFormatError('A thing to try is not done or not.');
    return NotebookItem(
      id: _string(item['id'], 'thing to try id', allowEmpty: false),
      text: _string(item['text'], 'thing to try'),
      done: done,
      unknown: _without(item, const ['id', 'text', 'done']),
    );
  });
  _unique([for (final item in items) item.id], 'thing to try');
  return TrackNotebook(
    notes: _string(json['notes'] ?? '', 'track notes'),
    cornerNotes: {
      for (final corner in corners)
        if (corner.note.isNotEmpty) corner.id: corner.note,
    },
    toTry: items,
    unknown: _without(json, const ['notes', 'corners', 'toTry']),
    unknownCorners: {
      for (final corner in corners)
        if (corner.unknown.isNotEmpty) corner.id: corner.unknown,
    },
  );
}
