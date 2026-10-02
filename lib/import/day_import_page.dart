import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import 'day_import_controller.dart';

/// Opens the platform pickers. Replaced by a fake in widget tests.
abstract interface class RecordingPickers {
  Future<List<String>> pickRecordings();

  /// Null when the user closed the dialog.
  Future<String?> pickFolder();
}

/// file_selector pickers. On macOS the sandbox grants read access to what the
/// user picks or drops, and nothing else.
final class PlatformRecordingPickers implements RecordingPickers {
  const PlatformRecordingPickers();

  static const _recordings = XTypeGroup(
    label: 'VBO and RCZ recordings',
    extensions: ['vbo', 'rcz', 'VBO', 'RCZ'],
  );

  @override
  Future<List<String>> pickRecordings() async => [
    for (final file in await openFiles(acceptedTypeGroups: [_recordings]))
      file.path,
  ];

  @override
  Future<String?> pickFolder() =>
      getDirectoryPath(confirmButtonText: 'Import this folder');
}

/// A time as the app shows it: "28.662 s" below a minute, "1:49.898" from one
/// minute, "—" when there is no finite value. Rounded before minutes are
/// split.
String displayTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) return '—';
  final milliseconds = (seconds * 1000).round();
  if (milliseconds < 60000) {
    return '${(milliseconds / 1000).toStringAsFixed(3)} s';
  }
  return formatLapTime(milliseconds / 1000, 3) ?? '—';
}

String _lapSummary(LapSession laps) {
  switch (laps.status) {
    case LapSessionStatus.available:
      final count = laps.timedLaps.length;
      final fastest = laps.fastestLapIndex;
      final best = fastest == null
          ? ''
          : ' · best ${displayTime(laps.timedLaps[fastest].durationSeconds)}';
      return '$count ${count == 1 ? 'lap' : 'laps'}$best';
    case LapSessionStatus.noSourceStartGate:
      return 'No laps: the recording has no start/finish line.';
    case LapSessionStatus.ambiguousSourceStartGate:
      return 'No laps: the recording has more than one start/finish line.';
    case LapSessionStatus.invalidGate:
      return 'No laps: the start/finish line is not valid.';
    case LapSessionStatus.noUsableGps:
      return 'No laps: the recording has no usable GPS.';
    case LapSessionStatus.noAcceptedPasses:
    case LapSessionStatus.insufficientPasses:
      return 'No complete laps: the start/finish line was not crossed often enough.';
  }
}

/// Import a day: pick recordings or a folder, or drop them on the window.
class DayImportPage extends StatefulWidget {
  const DayImportPage({
    super.key,
    this.controller,
    this.pickers = const PlatformRecordingPickers(),
    this.acceptsDrops,
  });

  /// Whether recordings and folders can be dropped on the window; by default
  /// on desktop only.
  final bool? acceptsDrops;

  /// Defaults to one running imports in a background isolate.
  final DayImportController? controller;
  final RecordingPickers pickers;

  @override
  State<DayImportPage> createState() => _DayImportPageState();
}

class _DayImportPageState extends State<DayImportPage> {
  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  bool get _acceptsDrops => widget.acceptsDrops ?? _isDesktop;

  late final DayImportController _controller =
      widget.controller ?? DayImportController();
  bool _includeSubfolders = false;
  bool _dragging = false;

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _start(List<String> paths) {
    if (paths.isEmpty) return;
    if (!_controller.start(paths, includeSubfolders: _includeSubfolders)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Finish the current import first. Nothing was imported.',
          ),
        ),
      );
    }
  }

  Future<void> _pickRecordings() async =>
      _start(await widget.pickers.pickRecordings());

  Future<void> _pickFolder() async {
    final folder = await widget.pickers.pickFolder();
    if (folder != null) _start([folder]);
  }

  @override
  Widget build(BuildContext context) {
    final content = ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(
            width: 3,
            color: !_dragging
                ? Colors.transparent
                : _controller.isWorking
                ? Colors.amber
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ..._choices(context),
            const SizedBox(height: 16),
            ..._status(context),
          ],
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Import a day')),
      body: !_acceptsDrops
          ? content
          : DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) {
                setState(() => _dragging = false);
                _start([for (final file in details.files) file.path]);
              },
              child: content,
            ),
    );
  }

  List<Widget> _choices(BuildContext context) {
    final enabled = !_controller.isWorking;
    return [
      Text(
        _acceptsDrops
            ? 'Choose the day\'s VBO and RCZ recordings or a folder, or drop them here.'
            : 'Choose the day\'s VBO and RCZ recordings or a folder.',
        style: Theme.of(context).textTheme.bodyLarge,
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.icon(
            onPressed: enabled ? _pickRecordings : null,
            icon: const Icon(Icons.insert_drive_file_outlined),
            label: const Text('Choose recordings…'),
          ),
          OutlinedButton.icon(
            onPressed: enabled ? _pickFolder : null,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Choose a folder…'),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: _includeSubfolders,
                onChanged: enabled
                    ? (value) =>
                          setState(() => _includeSubfolders = value ?? false)
                    : null,
              ),
              const Text('Include subfolders'),
            ],
          ),
        ],
      ),
    ];
  }

  List<Widget> _status(BuildContext context) {
    final theme = Theme.of(context);
    List<Widget> notes(List<String> notes) => [
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Import notes', style: theme.textTheme.titleSmall),
        for (final note in notes)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(note)),
      ],
    ];
    switch (_controller.state) {
      case DayImportIdle():
        return const [];
      case DayImportWorking(:final processed, :final total):
        return [
          Text(
            total == 0
                ? 'Looking for recordings…'
                : 'Preparing recording ${processed < total ? processed + 1 : total} of $total…',
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: total == 0 ? null : processed / total),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _controller.cancel,
              child: const Text('Cancel'),
            ),
          ),
        ];
      case DayImportCancelled():
        return const [Text('Import cancelled. Nothing was imported.')];
      case DayImportFailed(:final message, notes: final failedNotes):
        return [
          Text(message, style: TextStyle(color: theme.colorScheme.error)),
          ...notes(failedNotes),
        ];
      case DayImportFinished(:final runs, notes: final finishedNotes):
        return [
          Text(
            '${runs.length} ${runs.length == 1 ? 'session' : 'sessions'} imported',
            style: theme.textTheme.titleMedium,
          ),
          for (final named in runs)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(named.name),
              subtitle: Text(_lapSummary(named.run.laps)),
            ),
          ...notes(finishedNotes),
        ];
    }
  }
}
