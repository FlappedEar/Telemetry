import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'profile_bundle_pickers.dart';
import 'profile_library.dart';
import 'track_notebook_page.dart';

/// Every day kept in the driver profile, as Car > Year > Track > Date >
/// sessions. Tapping a day opens it with [open]; each day's menu moves it
/// to another car or deletes it. The page's menu exports the profile to one
/// file and imports one exported on another device.
class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.library,
    required this.open,
    this.pickers = const PlatformProfileBundlePickers(),
    this.closeDay,
  });

  /// Closes the day of the event id given wherever the app keeps it open,
  /// before it is deleted, so nothing saves it again; false when it is
  /// shown and cannot be closed.
  final Future<bool> Function(String eventId)? closeDay;

  final ProfileLibrary library;

  final ProfileBundlePickers pickers;

  /// Opens the day saved at the path given.
  final ValueChanged<String> open;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _menu = GlobalKey();

  /// What the export or import under way is doing; null when there is none.
  String? _working;

  @override
  void initState() {
    super.initState();
    widget.library.load();
  }

  Future<void> _export() async {
    final l10n = context.l10n;
    final pickers = widget.pickers;
    final messenger = ScaffoldMessenger.of(context);
    // The iPad's share sheet points at the menu, or the page.
    final box =
        (_menu.currentContext?.findRenderObject() ?? context.findRenderObject())
            as RenderBox?;
    final origin = box == null || !box.hasSize
        ? const Rect.fromLTWH(0, 0, 1, 1)
        : box.localToGlobal(Offset.zero) & box.size;
    final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final fileName =
        '${l10n.libraryExportFileName(date)}$profileBundleExtension';
    String? location;
    if (!pickers.shares) {
      location = await pickers.saveLocation(fileName);
      if (location == null || !mounted) return;
    }
    setState(() => _working = l10n.libraryExporting);
    var copying = false;
    try {
      // Written in the app's own folder first: a sandboxed app may write
      // only the file the user chose, not a temporary one beside it.
      final work = await pickers.workFile(fileName);
      final export = await widget.library.exportBundle(work);
      if (export == null) throw StateError('No profile to export.');
      if (location != null) {
        copying = true;
        await File(work).copy(location);
        copying = false;
        try {
          await File(work).delete();
        } on Object {
          // Removed with the next export's.
        }
      } else if (!await pickers.share(work, origin)) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            [
              l10n.libraryExported(export.days),
              if (export.daysMissing.isNotEmpty)
                l10n.libraryExportDaysMissing(export.daysMissing.length),
              if (export.recordingsMissing > 0)
                l10n.libraryExportMissing(export.recordingsMissing),
              if (export.referencesMissing > 0)
                l10n.libraryExportReferencesMissing(export.referencesMissing),
            ].join(' '),
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('Profile not exported: $error');
      // A copy cut short is no profile: it is not left where the user
      // chose.
      if (copying && location != null) {
        try {
          await File(location).delete();
        } on Object {
          // Never written.
        }
      }
      messenger.showSnackBar(SnackBar(content: Text(l10n.libraryExportFailed)));
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  Future<void> _import() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final path = await widget.pickers.pickBundle();
    if (path == null || !mounted) return;
    setState(() => _working = l10n.libraryImporting);
    String message;
    try {
      final read = await widget.library.importBundle(path);
      if (read == null) throw StateError('No profile to import into.');
      message = [
        l10n.libraryImported(read.added.length),
        if (read.notAdded.isNotEmpty)
          l10n.libraryImportNotAdded(read.notAdded.length),
        if (read.notebooks.isNotEmpty)
          l10n.libraryImportNotebooks(read.notebooks.length),
        if (read.notebookCut) l10n.libraryImportNotebookCut,
        if (read.referencesNotKept.isNotEmpty)
          l10n.libraryImportReferencesNotKept(read.referencesNotKept.length),
        if (read.referencesMissing > 0)
          l10n.libraryImportReferencesMissing(read.referencesMissing),
      ].join(' ');
    } on ProfileNotSaved catch (error) {
      message = l10n.libraryImportNotSaved(error.import.added.length);
    } on Object catch (error) {
      debugPrint('Profile not imported: $error');
      message = l10n.libraryImportFailed;
    } finally {
      await widget.pickers.release(path);
      if (mounted) setState(() => _working = null);
    }
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  PreferredSizeWidget? _progress() {
    final working = _working;
    if (working == null) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(32),
      child: Column(
        key: const ValueKey('libraryWorking'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(working),
            ),
          ),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }

  Future<void> _rename({
    required String title,
    required String current,
    required ValueChanged<String> rename,
  }) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(title: title, initial: current),
    );
    if (name != null && name.trim().isNotEmpty) rename(name);
  }

  /// Moves [day] to another car, or to a new one.
  Future<void> _chooseCar(DriverProfile profile, ProfileDay day) async {
    const newCar = '';
    final l10n = context.l10n;
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.libraryChooseCar(day.name)),
        children: [
          for (final car in profile.cars)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, car.id),
              child: Row(
                children: [
                  Expanded(child: Text(car.name)),
                  if (car.id == day.carId) const Icon(Icons.check, size: 18),
                ],
              ),
            ),
          SimpleDialogOption(
            key: const ValueKey('libraryNewCar'),
            onPressed: () => Navigator.pop(context, newCar),
            child: Text(l10n.libraryNewCar),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    if (choice != newCar) {
      widget.library.setDayCar(day.eventId, choice);
      return;
    }
    await _rename(
      title: l10n.libraryNewCar,
      current: '',
      rename: (name) {
        final id = widget.library.addCar(name);
        if (id != null) widget.library.setDayCar(day.eventId, id);
      },
    );
  }

  /// Deletes [day] once the driver confirms: see [ProfileLibrary.deleteDay].
  Future<void> _deleteDay(ProfileDay day) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.libraryDeleteDayTitle(day.name)),
        content: Text(l10n.libraryDeleteDayBody(day.sessions.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('libraryDeleteDayConfirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.libraryDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _working = l10n.libraryDeleteDay);
    try {
      if (!(await widget.closeDay?.call(day.eventId) ?? true)) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.libraryDeleteDayOpen)),
        );
        return;
      }
      await widget.library.deleteDay(day.eventId);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryDayDeleted(day.name))),
      );
    } on Object catch (error) {
      debugPrint('Day not deleted: $error');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.libraryDayDeleteFailed('$error'))),
      );
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.libraryTitle),
        bottom: _progress(),
        actions: [
          ListenableBuilder(
            listenable: widget.library,
            builder: (context, _) {
              final profile = widget.library.profile;
              final idle = _working == null && widget.library.available;
              return PopupMenuButton<VoidCallback>(
                key: _menu,
                enabled: idle,
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    key: const ValueKey('libraryExport'),
                    value: _export,
                    enabled: profile != null && profile.days.isNotEmpty,
                    child: ListTile(
                      leading: const Icon(Icons.ios_share),
                      title: Text(l10n.libraryExport),
                    ),
                  ),
                  PopupMenuItem(
                    key: const ValueKey('libraryImport'),
                    value: _import,
                    child: ListTile(
                      leading: const Icon(Icons.file_open_outlined),
                      title: Text(l10n.libraryImport),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final profile = widget.library.profile;
          if (profile == null) {
            return Center(
              child: widget.library.loaded
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(l10n.libraryUnavailable),
                    )
                  : const CircularProgressIndicator(),
            );
          }
          final tree = profileTree(profile);
          if (tree.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.libraryEmpty,
                  key: const ValueKey('libraryEmpty'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            key: const ValueKey('libraryList'),
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [for (final car in tree) _car(context, profile, car)],
          );
        },
      ),
    );
  }

  Widget _car(
    BuildContext context,
    DriverProfile profile,
    ProfileCarNode node,
  ) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.directions_car_outlined),
          title: Text(node.car.name, style: theme.textTheme.titleLarge),
          trailing: IconButton(
            tooltip: l10n.libraryRenameCar,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _rename(
              title: l10n.libraryRenameCar,
              current: node.car.name,
              rename: (name) => widget.library.renameCar(node.car.id, name),
            ),
          ),
        ),
        for (final year in node.years) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              year.year?.toString() ?? l10n.libraryUndated,
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final track in year.tracks)
            Card(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.route_outlined),
                    title: Text(track.track?.name ?? l10n.libraryUnknownTrack),
                    trailing: track.track == null
                        ? null
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: ValueKey(
                                  'trackNotebook ${track.track!.id}',
                                ),
                                tooltip: l10n.notebookTitle,
                                icon: const Icon(Icons.menu_book_outlined),
                                onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => TrackNotebookPage(
                                      library: widget.library,
                                      trackId: track.track!.id,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: l10n.libraryRenameTrack,
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () => _rename(
                                  title: l10n.libraryRenameTrack,
                                  current: track.track!.name,
                                  rename: (name) => widget.library.renameTrack(
                                    track.track!.id,
                                    name,
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                  for (final date in track.dates)
                    for (final day in date.days) _day(context, profile, day),
                ],
              ),
            ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _day(BuildContext context, DriverProfile profile, ProfileDay day) {
    final l10n = context.l10n;
    final start = day.startMilliseconds;
    final date = start == null
        ? l10n.libraryUndated
        : DateFormat.yMMMd().format(DateTime.fromMillisecondsSinceEpoch(start));
    final best = day.bestLapSeconds;
    final path = widget.library.pathOf(day);
    return ListTile(
      key: ValueKey('libraryDay-${day.eventId}'),
      minVerticalPadding: 12,
      title: Text('$date · ${day.name}'),
      subtitle: Text(
        [
          l10n.librarySessions(day.sessions.length),
          if (best != null) l10n.libraryBestLap(displayTime(best)),
        ].join(' · '),
      ),
      onTap: path == null ? null : () => widget.open(path),
      trailing: PopupMenuButton<_DayAction>(
        key: ValueKey('libraryDayMenu-${day.eventId}'),
        tooltip: l10n.libraryDayActions,
        enabled: _working == null,
        onSelected: (action) => switch (action) {
          _DayAction.changeCar => _chooseCar(profile, day),
          _DayAction.delete => _deleteDay(day),
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            key: const ValueKey('libraryChangeCar'),
            value: _DayAction.changeCar,
            child: ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: Text(l10n.libraryChangeCar),
            ),
          ),
          PopupMenuItem(
            key: const ValueKey('libraryDeleteDay'),
            value: _DayAction.delete,
            child: ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.libraryDeleteDay),
            ),
          ),
        ],
      ),
    );
  }
}

/// What a day's menu in the library does.
enum _DayAction { changeCar, delete }

/// Asks for a name; pops it, or null when cancelled.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      key: const ValueKey('libraryRenameField'),
      controller: _controller,
      autofocus: true,
      maxLength: 160,
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(context.l10n.save),
      ),
    ],
  );
}
