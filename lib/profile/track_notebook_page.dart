import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../day/theoretical_best_card.dart' show TheoreticalBestText;
import '../l10n.dart';
import 'profile_library.dart';

/// What the driver writes down about a track for the next visit (FET-231):
/// notes, a note per corner and things to try. Kept in the driver profile,
/// so every day on the track shares it. Saved as it is typed.
class TrackNotebookPage extends StatefulWidget {
  const TrackNotebookPage({
    super.key,
    required this.library,
    required this.trackId,
  });

  final ProfileLibrary library;
  final String trackId;

  @override
  State<TrackNotebookPage> createState() => _TrackNotebookPageState();
}

// Every note is kept to the profile's limit.
final _limit = LengthLimitingTextInputFormatter(maximumProfileTextCharacters);

class _TrackNotebookPageState extends State<TrackNotebookPage> {
  // How long typing pauses before the notebook is written.
  static const _saveDelay = Duration(milliseconds: 600);

  late final TextEditingController _notes;
  final _corners = <String, TextEditingController>{};
  final _newItem = TextEditingController();
  late List<NotebookItem> _items;
  // Things to try removed here, so the library's copy does not bring
  // them back before it is written.
  final _removed = <String>{};
  // The notebook as this page last read or wrote it.
  late TrackNotebook _saved;
  Timer? _save;
  bool _notSaved = false;
  bool _closing = false;
  // While the page writes: its own change is not one to join.
  bool _writing = false;
  late final AppLifecycleListener _lifecycle;

  ProfileTrack? get _track => widget.library.profile?.track(widget.trackId);

  TrackNotebook get _live => _track?.notebook ?? _saved;

  @override
  void initState() {
    super.initState();
    _saved = _track?.notebook ?? TrackNotebook();
    _notes = TextEditingController(text: _saved.notes);
    _items = [..._saved.toTry];
    widget.library.addListener(_libraryChanged);
    // A note typed just before the app goes to the background is kept.
    _lifecycle = AppLifecycleListener(
      onStateChange: (state) {
        if (state != AppLifecycleState.resumed) _flush();
      },
    );
  }

  @override
  void dispose() {
    _closing = true;
    widget.library.removeListener(_libraryChanged);
    _flush();
    _lifecycle.dispose();
    _notes.dispose();
    for (final controller in _corners.values) {
      controller.dispose();
    }
    _newItem.dispose();
    super.dispose();
  }

  // A corner's field, made when the corner is first shown: a corner
  // measured while the page is open gets one too.
  TextEditingController _corner(String id) => _corners.putIfAbsent(
    id,
    () => TextEditingController(text: _live.cornerNotes[id] ?? ''),
  );

  // What changed in the library while the page is open (an import, a day
  // measured) joins the page; what is being typed here is kept.
  void _libraryChanged() {
    if (!mounted) return;
    final live = _track?.notebook;
    if (live == null) return setState(() {});
    if (_writing) {
      _saved = live;
      return;
    }
    setState(() {
      _rebase(_notes, _saved.notes, live.notes);
      for (final MapEntry(:key, :value) in _corners.entries) {
        _rebase(
          value,
          _saved.cornerNotes[key] ?? '',
          live.cornerNotes[key] ?? '',
        );
      }
      final ids = {for (final item in _items) item.id};
      _items = [
        for (final item in _items)
          live.toTry.firstWhere(
            (candidate) =>
                candidate.id == item.id && candidate.text == item.text,
            orElse: () => item,
          ),
        for (final item in live.toTry)
          if (!ids.contains(item.id) && !_removed.contains(item.id)) item,
      ];
      _saved = live;
    });
  }

  // [field] after its note changed in the library from [before] to [after]:
  // the new note when the field holds what was kept (the profile drops
  // trailing spaces), else the field with what was added after its note,
  // so neither the typing nor the addition is lost.
  static void _rebase(
    TextEditingController field,
    String before,
    String after,
  ) {
    if (after == before) return;
    final text = field.text.trimRight();
    final String next;
    if (text == before) {
      // What the user typed after the kept note stays.
      next = after + field.text.substring(text.length);
    } else if (after.startsWith(before)) {
      next = text + after.substring(before.length);
    } else {
      return;
    }
    final selection = field.selection;
    field.value = TextEditingValue(
      text: next,
      selection: selection.isValid
          ? TextSelection(
              baseOffset: selection.baseOffset.clamp(0, next.length),
              extentOffset: selection.extentOffset.clamp(0, next.length),
            )
          : TextSelection.collapsed(offset: next.length),
    );
  }

  void _changed() {
    _save?.cancel();
    _save = Timer(_saveDelay, _write);
  }

  void _flush() {
    if (_save?.isActive ?? false) _write();
    _save?.cancel();
  }

  void _write() {
    _save?.cancel();
    final live = _live;
    final notebook = TrackNotebook(
      notes: _notes.text,
      cornerNotes: {
        // Notes the page does not show are kept.
        ...live.cornerNotes,
        for (final MapEntry(:key, :value) in _corners.entries) key: value.text,
      },
      toTry: _items,
      unknown: live.unknown,
      unknownCorners: live.unknownCorners,
    );
    _writing = true;
    final bool kept;
    try {
      kept = widget.library.setTrackNotebook(widget.trackId, notebook);
    } finally {
      _writing = false;
    }
    if (kept) _saved = _track?.notebook ?? notebook;
    if (!_closing && kept == _notSaved) setState(() => _notSaved = !kept);
  }

  void _add() {
    final text = _newItem.text.trim();
    if (text.isEmpty || _items.length >= maximumNotebookItems) return;
    setState(() {
      _items = [..._items, NotebookItem(id: newNotebookItemId(), text: text)];
      _newItem.clear();
    });
    _write();
  }

  void _toggle(NotebookItem item, bool done) {
    setState(() {
      _items = [
        for (final candidate in _items)
          candidate.id == item.id ? candidate.copyWith(done: done) : candidate,
      ];
    });
    _write();
  }

  void _remove(NotebookItem item) {
    setState(() {
      _removed.add(item.id);
      _items = [
        for (final candidate in _items)
          if (candidate.id != item.id) candidate,
      ];
    });
    _write();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final track = _track;
    if (track == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.notebookTitle)),
        body: Center(child: Text(l10n.notebookNoTrack)),
      );
    }
    final open = [
      for (final item in _items)
        if (!item.done) item,
    ];
    final done = [
      for (final item in _items)
        if (item.done) item,
    ];
    Widget item(NotebookItem item) => CheckboxListTile(
      key: ValueKey('notebookItem ${item.id}'),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      value: item.done,
      onChanged: (value) => _toggle(item, value ?? false),
      title: Text(
        item.text,
        style: item.done
            ? theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.outline,
                decoration: TextDecoration.lineThrough,
              )
            : null,
      ),
      secondary: IconButton(
        tooltip: l10n.notebookRemove,
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _remove(item),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notebookTitleOf(track.name))),
      body: ListView(
        key: const ValueKey('notebookList'),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l10n.notebookIntro, style: theme.textTheme.bodySmall),
          if (_notSaved)
            Padding(
              key: const ValueKey('notebookNotSaved'),
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.notebookNotSaved,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Text(l10n.notebookToTry, style: theme.textTheme.titleMedium),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.notebookNothingToTry),
            ),
          for (final entry in open) item(entry),
          if (_items.length >= maximumNotebookItems)
            Padding(
              key: const ValueKey('notebookFull'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.notebookFull(maximumNotebookItems)),
            )
          else
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('notebookNewItem'),
                    controller: _newItem,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [_limit],
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(hintText: l10n.notebookAddHint),
                  ),
                ),
                IconButton(
                  key: const ValueKey('notebookAdd'),
                  tooltip: l10n.notebookAdd,
                  icon: const Icon(Icons.add),
                  onPressed: _add,
                ),
              ],
            ),
          if (done.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l10n.notebookDone, style: theme.textTheme.titleSmall),
            for (final entry in done) item(entry),
          ],
          const SizedBox(height: 24),
          Text(l10n.notebookNotes, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('notebookNotes'),
            controller: _notes,
            minLines: 3,
            maxLines: null,
            inputFormatters: [_limit],
            onChanged: (_) => _changed(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: l10n.notebookNotesHint,
            ),
          ),
          const SizedBox(height: 16),
          Text(l10n.notebookCorners, style: theme.textTheme.titleMedium),
          if (track.corners.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(l10n.notebookNoCorners),
            ),
          for (final corner in track.corners)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextField(
                key: ValueKey('notebookCorner ${corner.id}'),
                controller: _corner(corner.id),
                minLines: 1,
                maxLines: null,
                inputFormatters: [_limit],
                onChanged: (_) => _changed(),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.tbSegmentName(corner.name),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
