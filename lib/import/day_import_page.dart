import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';

import '../day/day_results_controller.dart';
import '../day/day_results_page.dart';
import '../day/document_pickers.dart';
import '../day/recovery_store.dart';
import '../format.dart';
import '../settings_dialog.dart';
import 'day_import_controller.dart';
import 'file_access.dart';
import 'import_runner.dart' show DayAppender, IsolateDayAppender;
import 'incoming_recordings.dart';

export '../format.dart' show displayTime;

/// Opens the platform pickers. Replaced by a fake in widget tests.
abstract interface class RecordingPickers {
  Future<List<String>> pickRecordings();

  /// Null when the user closed the dialog.
  Future<String?> pickFolder();
}

/// The picker filter for VBO and RCZ recordings on [platform].
///
/// iOS filters by uniform type identifier only, and a .vbo or .rcz file can
/// carry a type declared by another app (RaceChrono), so iOS shows every
/// file; the scan reports what is not a recording. Desktops filter by
/// extension. Android does not use this, see [PlatformRecordingPickers].
XTypeGroup recordingTypeGroup(TargetPlatform platform) =>
    platform == TargetPlatform.iOS
    ? const XTypeGroup(
        label: 'VBO and RCZ recordings',
        uniformTypeIdentifiers: ['public.data'],
      )
    : const XTypeGroup(
        label: 'VBO and RCZ recordings',
        extensions: ['vbo', 'rcz', 'VBO', 'RCZ'],
      );

/// Desktops accept dropped recordings and offer a folder picker. Phones and
/// tablets pick recordings only: on iOS file_selector has no folder picker,
/// and on Android it returns a storage path the app may not be allowed to
/// read.
bool isDesktopPlatform(TargetPlatform platform) =>
    !kIsWeb &&
    switch (platform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };

/// The Android host's file picker; see MainActivity.kt.
const androidPickerChannel = MethodChannel(
  'com.flappedear.telemetry/recording_picker',
);

/// file_selector pickers, except for recordings on Android. On macOS the
/// sandbox grants read access to what the user picks or drops, and nothing
/// else. On iOS the picker copies the chosen files into the app's temporary
/// folder.
///
/// On Android file_selector names its copy after the type the provider
/// reports, and a .vbo file is reported as application/octet-stream, so it
/// arrived as a .bin file that was not imported. The host's own picker keeps
/// each file's name.
final class PlatformRecordingPickers implements RecordingPickers {
  const PlatformRecordingPickers();

  @override
  Future<List<String>> pickRecordings() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final paths = await androidPickerChannel.invokeListMethod<String>('pick');
      return paths ?? const [];
    }
    final paths = [
      for (final file in await openFiles(
        acceptedTypeGroups: [recordingTypeGroup(defaultTargetPlatform)],
      ))
        file.path,
    ];
    await const PlatformFileAccess().remember(paths);
    return paths;
  }

  @override
  Future<String?> pickFolder() async {
    final folder = await getDirectoryPath(
      confirmButtonText: 'Import this folder',
    );
    if (folder != null) await const PlatformFileAccess().remember([folder]);
    return folder;
  }
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

/// [time] as local "2026-10-03 06:30".
String _when(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

/// Import a day: pick recordings or a folder, or drop them on the window.
class DayImportPage extends StatefulWidget {
  const DayImportPage({
    super.key,
    this.controller,
    this.pickers = const PlatformRecordingPickers(),
    this.documents = const PlatformDocumentPickers(),
    this.recovery = const PlatformRecoveryStore(),
    this.acceptsDrops,
    this.picksFolders,
    this.incoming,
    this.fileAccess = const PlatformFileAccess(),
    this.appender = const IsolateDayAppender(),
  });

  /// Prepares recordings added to an open day.
  final DayAppender appender;

  final DocumentPickers documents;

  /// Keeps chosen recordings readable after the app restarts (macOS).
  final FileAccess fileAccess;

  /// Keeps the day being worked on until it is saved.
  final RecoveryStore recovery;

  /// Recordings shared from another app; by default the iOS and Android host.
  final IncomingRecordings? incoming;

  /// Whether "Choose a folder…" is offered; by default on desktop only.
  final bool? picksFolders;

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
  static bool get _isDesktop => isDesktopPlatform(defaultTargetPlatform);

  bool get _acceptsDrops => widget.acceptsDrops ?? _isDesktop;

  bool get _picksFolders => widget.picksFolders ?? _isDesktop;

  late final DayImportController _controller =
      widget.controller ?? DayImportController();
  bool _includeSubfolders = false;
  bool _dragging = false;
  bool _opening = false;

  /// An unsaved day kept from before, offered for restoring.
  DayRecovery? _recovered;
  late final StreamSubscription<List<String>> _incoming;

  @override
  void initState() {
    super.initState();
    _incoming = (widget.incoming ?? PlatformIncomingRecordings.instance)
        .received
        .listen(_receive);
    _controller.addListener(_imported);
    _checkRecovery();
  }

  /// Whether the import running was started by recordings shared from
  /// another app; its day then opens by itself.
  bool _showWhenImported = false;

  void _imported() {
    if (!_showWhenImported || _controller.isWorking || !mounted) return;
    _showWhenImported = false;
    if (_controller.state case DayImportFinished(:final runs, :final analysis?)
        when ModalRoute.of(context)?.isCurrent ?? false) {
      unawaited(
        _show(
          DayResultsController(
            runs: runs,
            analysis: analysis,
            recovery: widget.recovery,
            appender: widget.appender,
          ),
        ),
      );
    }
  }

  Future<void> _checkRecovery() async {
    final recovered = await queueRecovery(widget.recovery.load);
    if (mounted) setState(() => _recovered = recovered);
  }

  /// The day shown on top of this page, which recordings shared to the app
  /// are added to; null while none is.
  DayResultsController? _shownDay;

  /// Shows the day of [controller], then checks again for an unsaved day
  /// left behind.
  Future<void> _show(DayResultsController controller) async {
    _shownDay = controller;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DayResultsPage.controller(
            controller: controller,
            documents: widget.documents,
            pickers: widget.pickers,
            recovery: widget.recovery,
          ),
        ),
      );
    } finally {
      if (identical(_shownDay, controller)) _shownDay = null;
    }
    await _checkRecovery();
  }

  // Built outside the state so the isolate's closure holds only the snapshot.
  static OpenedDay Function() _recoverJob(DayRecovery recovery) =>
      () => openRecoveredDay(recovery);

  Future<void> _restore(DayRecovery recovery) async {
    setState(() => _opening = true);
    try {
      await widget.fileAccess.restore();
      final day = await Isolate.run(_recoverJob(recovery));
      if (!mounted) return;
      if (day.analysis == null) {
        await _cannotOpen(day, searchable: false);
        return;
      }
      await _show(
        DayResultsController.recovered(
          day,
          recovery,
          recovery: widget.recovery,
          appender: widget.appender,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The day could not be restored: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _discard(DayRecovery recovery) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Discard the changes to ${recovery.name}?'),
        content: const Text(
          'The unsaved changes are lost. Recordings and saved days are not touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    try {
      await queueRecovery(widget.recovery.clear);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Not discarded: $error')));
      }
    }
    await _checkRecovery();
  }

  /// Says why none of [day]'s recordings could be used. When [searchable],
  /// offers to look for them in a folder; returns whether the user chose to.
  Future<bool> _cannotOpen(OpenedDay day, {bool searchable = true}) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('${day.name} could not be opened'),
          content: Text(
            [
              'None of its recordings could be used:',
              for (final recording in day.missing)
                '${recording.name}: ${recording.path} · ${recording.reason}',
              if (searchable) ...[
                '',
                'Choose the folder the recordings are in to use them, also '
                    'when they have not moved.',
              ],
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Close'),
            ),
            if (searchable)
              TextButton(
                key: const ValueKey('cannotOpenFindRecordings'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Find recordings in a folder…'),
              ),
          ],
        ),
      ) ==
      true;

  @override
  void dispose() {
    _incoming.cancel();
    _controller.removeListener(_imported);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// Recordings shared from another app are added to the day open on top of
  /// this page, as its next sessions; the day page says what was added.
  /// Without an open day they start an import here.
  void _receive(List<String> paths) {
    if (!mounted) return;
    final day = _shownDay;
    if (day != null) {
      unawaited(day.addRecordings(paths));
      return;
    }
    final waiting = _waiting;
    if (waiting != null) {
      waiting.addAll(paths);
      return;
    }
    final behind = ModalRoute.of(context)?.isCurrent == false;
    if (!behind && !_controller.isWorking && !_opening) {
      unawaited(_continueToday(paths));
      return;
    }
    final started = !_controller.isWorking;
    _start(paths);
    if (behind && started) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Importing the shared recordings. Go back to Import a day to see them.',
          ),
        ),
      );
    }
  }

  /// Shared recordings that arrived while today's day was being opened;
  /// null when none is.
  List<String>? _waiting;

  /// Adds recordings shared while no day is shown to today's day, as the
  /// driver does after each session even when the system closed the app in
  /// between: the unsaved day kept for recovery, else the day saved last in
  /// the app, when every recording started on its date. The day then opens
  /// and says what was added. Otherwise the recordings start an import.
  Future<void> _continueToday(List<String> paths) async {
    final waiting = _waiting = [];
    setState(() => _opening = true);
    DayResultsController? today;
    try {
      today = await _todayWith(paths);
    } finally {
      _waiting = null;
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) {
      today?.dispose();
      return;
    }
    if (today == null) {
      _showWhenImported = !_controller.isWorking;
      _start([...paths, ...waiting]);
      return;
    }
    final shown = _show(today);
    if (waiting.isNotEmpty) unawaited(today.addRecordings(waiting));
    await shown;
  }

  // Only a day worked on in the last day can be today's: older ones are not
  // opened (reading all their recordings) just to be refused.
  static bool _recent(DateTime time) =>
      DateTime.now().difference(time) < const Duration(hours: 24);

  /// The first day that takes [paths] as recordings of its date, with them
  /// added; null when none does.
  Future<DayResultsController?> _todayWith(List<String> paths) async {
    final candidates = <Future<DayResultsController?> Function()>[
      () async {
        final recovery = await queueRecovery(widget.recovery.load);
        if (recovery == null || !_recent(recovery.timestamp)) return null;
        await widget.fileAccess.restore();
        final day = await Isolate.run(_recoverJob(recovery));
        return day.analysis == null
            ? null
            : DayResultsController.recovered(
                day,
                recovery,
                recovery: widget.recovery,
                appender: widget.appender,
              );
      },
      () async {
        final saved = await widget.documents.savedDays();
        if (saved.isEmpty || !_recent(File(saved.first).lastModifiedSync())) {
          return null;
        }
        await widget.fileAccess.restore();
        final day = await Isolate.run(_openJob(saved.first));
        return day.analysis == null
            ? null
            : DayResultsController.opened(
                day,
                recovery: widget.recovery,
                appender: widget.appender,
              );
      },
    ];
    for (final candidate in candidates) {
      DayResultsController? day;
      try {
        day = await candidate();
        if (day == null) continue;
        final addition = await day.addRecordings(paths, sameDayOnly: true);
        if (!addition.otherDay && addition.error.isEmpty) return day;
      } on Exception catch (error) {
        debugPrint('Today\'s day not continued: $error');
      }
      day?.dispose();
    }
    return null;
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

  // Built outside the state so the isolate's closure holds only the path.
  static OpenedDay Function() _openJob(String path) =>
      () => openDay(path);

  // Built outside the state so the isolate's closure holds only its inputs.
  static OpenedDay Function() _relinkJob(
    String path,
    String folder,
    List<MissingRecording> missing,
  ) =>
      () => openDay(path, relinked: findMovedRecordings(folder, missing).found);

  /// The day to open: on phones from the days saved in the app, else from
  /// the open dialog.
  Future<String?> _chooseDocument() async {
    final saved = await widget.documents.savedDays();
    if (saved.isEmpty || !mounted) return widget.documents.pickDocument();
    const other = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Open a saved day'),
        children: [
          for (final path in saved)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: Text(p.basenameWithoutExtension(path)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, other),
            child: const Text('Another file…'),
          ),
        ],
      ),
    );
    if (choice == other) return widget.documents.pickDocument();
    return choice;
  }

  Future<void> _openDay() async {
    final path = await _chooseDocument();
    if (path == null || !mounted) return;
    setState(() => _opening = true);
    try {
      await widget.fileAccess.restore();
      var day = await Isolate.run(_openJob(path));
      if (!mounted) return;
      // None of its recordings could be read: look for them in a folder the
      // user chooses, which also gives the app access to them, until some
      // are found or the user gives up.
      while (day.analysis == null) {
        if (!await _cannotOpen(day) || !mounted) return;
        final folder = await widget.documents.pickFolder();
        if (folder == null || !mounted) return;
        day = await Isolate.run(_relinkJob(path, folder, day.missing));
        if (!mounted) return;
      }
      await _show(DayResultsController.opened(day, recovery: widget.recovery));
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('The day could not be opened: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

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
      appBar: AppBar(
        title: const Text('Import a day'),
        actions: const [SettingsButton()],
      ),
      body: !_acceptsDrops
          ? content
          : DropTarget(
              onDragEntered: (_) => setState(() => _dragging = true),
              onDragExited: (_) => setState(() => _dragging = false),
              onDragDone: (details) {
                setState(() => _dragging = false);
                final paths = [for (final file in details.files) file.path];
                unawaited(widget.fileAccess.remember(paths));
                _start(paths);
              },
              child: content,
            ),
    );
  }

  List<Widget> _choices(BuildContext context) {
    final enabled = !_controller.isWorking;
    final recovered = _recovered;
    return [
      if (recovered != null) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${recovered.name} has unsaved changes from '
                  '${_when(recovered.timestamp)}.',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.tonal(
                      onPressed: enabled && !_opening
                          ? () => _restore(recovered)
                          : null,
                      child: const Text('Restore'),
                    ),
                    TextButton(
                      onPressed: enabled && !_opening
                          ? () => _discard(recovered)
                          : null,
                      child: const Text('Discard…'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
      Text(
        _acceptsDrops
            ? 'Choose the day\'s VBO and RCZ recordings or a folder, or drop them here.'
            : _picksFolders
            ? 'Choose the day\'s VBO and RCZ recordings or a folder.'
            : 'Choose the day\'s VBO and RCZ recordings.',
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
          if (_picksFolders)
            OutlinedButton.icon(
              onPressed: enabled ? _pickFolder : null,
              icon: const Icon(Icons.folder_open_outlined),
              label: const Text('Choose a folder…'),
            ),
          OutlinedButton.icon(
            onPressed: enabled && !_opening ? _openDay : null,
            icon: const Icon(Icons.history),
            label: Text(_opening ? 'Opening…' : 'Open a saved day…'),
          ),
          if (_picksFolders)
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
      case DayImportFinished(
        :final runs,
        :final analysis,
        notes: final finishedNotes,
      ):
        return [
          Text(
            '${runs.length} ${runs.length == 1 ? 'session' : 'sessions'} imported',
            style: theme.textTheme.titleMedium,
          ),
          if (analysis != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _show(
                  DayResultsController(
                    runs: runs,
                    analysis: analysis,
                    recovery: widget.recovery,
                    appender: widget.appender,
                  ),
                ),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Show the day\'s results'),
              ),
            ),
          ],
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
