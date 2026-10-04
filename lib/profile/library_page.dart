import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';
import 'profile_library.dart';

/// Every day kept in the driver profile, as Car > Year > Track > Date >
/// sessions. Tapping a day opens it with [open].
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.library, required this.open});

  final ProfileLibrary library;

  /// Opens the day saved at the path given.
  final ValueChanged<String> open;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  @override
  void initState() {
    super.initState();
    widget.library.load();
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.libraryTitle)),
      body: ListenableBuilder(
        listenable: widget.library,
        builder: (context, _) {
          final profile = widget.library.profile;
          if (profile == null) {
            return Center(
              child: widget.library.folder == null
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
                        : IconButton(
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
      trailing: IconButton(
        tooltip: l10n.libraryChangeCar,
        icon: const Icon(Icons.swap_horiz),
        onPressed: () => _chooseCar(profile, day),
      ),
    );
  }
}

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
