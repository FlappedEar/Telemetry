import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

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
import '../day/save_journal.dart';
import '../diagnostics/diagnostics_page.dart';
import '../format.dart';
import '../l10n.dart';
import '../profile/library_page.dart';
import '../profile/profile_library.dart';
import '../settings_dialog.dart';
import '../ui/theme.dart';
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
///
/// [label] is the filter's name in the picker.
XTypeGroup recordingTypeGroup(
  TargetPlatform platform, {
  String label = 'VBO and RCZ recordings',
}) => platform == TargetPlatform.iOS
    ? XTypeGroup(label: label, uniformTypeIdentifiers: const ['public.data'])
    : XTypeGroup(label: label, extensions: const ['vbo', 'rcz', 'VBO', 'RCZ']);

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
        acceptedTypeGroups: [
          recordingTypeGroup(
            defaultTargetPlatform,
            label: deviceL10n().importPageRecordingTypes,
          ),
        ],
      ))
        file.path,
    ];
    await const PlatformFileAccess().remember(paths);
    return paths;
  }

  @override
  Future<String?> pickFolder() async {
    final folder = await getDirectoryPath(
      confirmButtonText: deviceL10n().importPageImportThisFolder,
    );
    if (folder != null) await const PlatformFileAccess().remember([folder]);
    return folder;
  }
}

String _lapSummary(AppLocalizations l10n, _SessionRow row) {
  // Lap detection looks for the start/finish line before GPS; without GPS
  // the line is not what is missing.
  if (row.status != LapSessionStatus.available && !row.hasGps) {
    return l10n.importPageNoGps;
  }
  switch (row.status) {
    case LapSessionStatus.available:
      return l10n.importPageLaps(row.lapCount);
    case LapSessionStatus.noSourceStartGate:
      return l10n.importPageNoGate;
    case LapSessionStatus.ambiguousSourceStartGate:
      return l10n.importPageSeveralGates;
    case LapSessionStatus.invalidGate:
      return l10n.importPageInvalidGate;
    case LapSessionStatus.noUsableGps:
      return l10n.importPageNoGps;
    case LapSessionStatus.noAcceptedPasses:
    case LapSessionStatus.insufficientPasses:
      return l10n.importPageTooFewPasses;
  }
}

// A session's fastest timed lap, in seconds; null without one.
double? _bestSeconds(LapSession laps) {
  if (laps.status != LapSessionStatus.available) return null;
  final fastest = laps.fastestLapIndex;
  return fastest == null ? null : laps.timedLaps[fastest].durationSeconds;
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
    this.library,
  });

  /// The driver profile days are kept in; when null, there is no library
  /// and days are saved where [documents] says.
  final ProfileLibrary? library;

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

  /// The day shown last and closed, with its sessions, so coming back here
  /// still shows them and offers to open the day again; null before a day
  /// was shown, or once its unsaved changes were discarded.
  _ClosedDay? _lastDay;
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

  /// Recordings shared and imported here whose day has not been shown,
  /// such as when another day's unsaved work waits to be restored.
  List<String> _unopenedShares = const [];

  /// Shows the day of a finished import. The import is then forgotten, so
  /// the day is not built afresh from it later, without what was added or
  /// changed since.
  DayResultsController _showImported(
    List<NamedRun> runs,
    DayAnalysis analysis,
  ) {
    final state = _controller.state;
    final day = DayResultsController(
      runs: runs,
      analysis: analysis,
      alternatives: state is DayImportFinished ? state.alternatives : const {},
      recovery: widget.recovery,
      appender: widget.appender,
    );
    _controller.clearFinished();
    _unopenedShares = const [];
    unawaited(_show(day));
    // What was skipped or grouped is said over the day, which shows at once.
    final notes = state is DayImportFinished ? state.notes : const <String>[];
    if (notes.isNotEmpty) {
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          key: const ValueKey('importNotes'),
          duration: const Duration(seconds: 10),
          showCloseIcon: true,
          content: Text(
            [l10n.importPageNotes, ...notes.map(l10n.coreText)].join('\n'),
          ),
        ),
      );
    }
    return day;
  }

  /// Recordings shared while an import ran; they go to its day when it
  /// opens by itself, otherwise they are received once it ends.
  List<String>? _afterImport;

  void _imported() {
    if (_controller.isWorking || !mounted) return;
    // A share import that was cancelled or failed is not tried again with
    // the next share.
    if (_controller.state is DayImportCancelled ||
        _controller.state is DayImportFailed) {
      _unopenedShares = const [];
    }
    final pending = _afterImport ?? const <String>[];
    _afterImport = null;
    final show = _showWhenImported;
    _showWhenImported = false;
    if (show) {
      if (_controller.state
          case DayImportFinished(:final runs, :final analysis?)
          when ModalRoute.of(context)?.isCurrent ?? false) {
        final day = _showImported(runs, analysis);
        if (pending.isNotEmpty) _addTo(day, pending);
        return;
      }
    }
    if (pending.isNotEmpty) _receive(pending);
  }

  /// Starts importing [paths], reviewed on a day shown here, as a new day,
  /// which opens by itself when imported. Returns false, changing nothing,
  /// while another import runs or waits for its review.
  bool _startNewDay(List<String> paths, ImportChoices choices) {
    if (!mounted ||
        !_controller.start(paths, includeSubfolders: false, choices: choices)) {
      return false;
    }
    _unopenedShares = const [];
    _showWhenImported = true;
    return true;
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
    // A day opened again with its recordings found elsewhere is shown in
    // its place, and takes the recordings shared from then on.
    DayResultsController? next = controller;
    DayResultsController? last;
    while (next != null && mounted) {
      final shown = next!;
      next = null;
      _shownDay = shown;
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DayResultsPage.controller(
              controller: shown,
              documents: widget.documents,
              pickers: widget.pickers,
              recovery: widget.recovery,
              replace: (day) => next = day,
              startNewDay: _startNewDay,
              library: widget.library,
            ),
          ),
        );
      } finally {
        if (identical(_shownDay, shown)) _shownDay = null;
      }
      last = shown;
    }
    if (!mounted) {
      next?.dispose();
      return;
    }
    // What the day held when it was left, listed here with its recovery
    // snapshot, written first: the page may not have closed it yet.
    final closed = last == null ? null : _ClosedDay.of(last);
    await last?.flushRecovery();
    final recovered = await queueRecovery(widget.recovery.load);
    if (!mounted) return;
    setState(() {
      _recovered = recovered;
      if (closed != null) _lastDay = closed;
    });
  }

  // Built outside the state so the isolate's closure holds only the snapshot.
  static OpenedDay Function() _recoverJob(DayRecovery recovery) =>
      () => openRecoveredDay(recovery);

  Future<void> _restore(DayRecovery _) async {
    _waiting = [];
    setState(() => _opening = true);
    try {
      // The snapshot as it is now: the day closed last may have written a
      // newer one after this card was shown.
      final recovery = await queueRecovery(widget.recovery.load);
      if (recovery == null) {
        // Saved meanwhile: there is nothing left to restore.
        await _checkRecovery();
        return;
      }
      await widget.fileAccess.restore();
      final day = await Isolate.run(_recoverJob(recovery));
      if (!mounted) return;
      if (day.analysis == null) {
        await _cannotOpen(day, searchable: false);
        return;
      }
      await _showOpened(
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
          SnackBar(content: Text(context.l10n.importPageNotRestored('$error'))),
        );
      }
    } finally {
      _openingDone();
    }
  }

  Future<void> _discard(DayRecovery recovery) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.importPageDiscardTitle(recovery.name)),
        content: Text(context.l10n.importPageDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.importPageKeep),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.importPageDiscard),
          ),
        ],
      ),
    );
    if (discard != true) return;
    if (_lastDay?.eventId == recovery.eventId) {
      setState(() => _lastDay = null);
    }
    try {
      await queueRecovery(widget.recovery.clear);
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.importPageNotDiscarded('$error')),
          ),
        );
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
          title: Text(context.l10n.importPageCannotOpenTitle(day.name)),
          content: Text(
            [
              context.l10n.importPageNoneUsable,
              for (final recording in day.missing)
                '${context.l10n.session(recording.name)}: ${recording.path} · '
                    '${context.l10n.missingReason(recording.reason)}',
              if (searchable) ...['', context.l10n.importPageChooseFolderHint],
            ].join('\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.l10n.close),
            ),
            if (searchable)
              TextButton(
                key: const ValueKey('cannotOpenFindRecordings'),
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.findRecordingsInFolder),
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
      _addTo(day, paths);
      return;
    }
    final waiting = _waiting;
    if (waiting != null) {
      waiting.addAll(paths);
      return;
    }
    final behind = ModalRoute.of(context)?.isCurrent == false;
    // Also with a dialog or another page over this one: today's day is
    // continued, and shown over them.
    if (!_controller.isWorking && !_opening) {
      unawaited(_continueToday(paths));
      return;
    }
    if (_controller.isWorking) {
      // Not refused: they follow the import running now.
      (_afterImport ??= []).addAll(paths);
      return;
    }
    _start(paths);
    if (behind) _tellImportingBehind();
  }

  void _tellImportingBehind() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.importPageImportingBehind)),
    );
  }

  /// Adds shared [paths] to [day]; when the day is closed before they are
  /// added, they are received again here, so none is dropped.
  void _addTo(DayResultsController day, List<String> paths) {
    unawaited(
      day.addRecordings(paths).then((addition) {
        if (addition.closed && mounted) _receive(paths);
      }),
    );
  }

  /// Shared recordings that arrived while a day was being opened; null when
  /// none is.
  List<String>? _waiting;

  /// Shows a day the user opened or restored, with the recordings shared
  /// while it was opened added to it.
  Future<void> _showOpened(DayResultsController controller) {
    final waiting = _waiting;
    _waiting = null;
    final shown = _show(controller);
    if (waiting != null && waiting.isNotEmpty) {
      _addTo(controller, waiting);
    }
    return shown;
  }

  /// Ends opening a day; recordings shared meanwhile that no day took are
  /// imported here.
  void _openingDone() {
    final waiting = _waiting;
    _waiting = null;
    if (!mounted) return;
    setState(() => _opening = false);
    if (waiting != null && waiting.isNotEmpty) _receive(waiting);
  }

  /// Adds recordings shared while no day is shown to today's day, as the
  /// driver does after each session even when the system closed the app in
  /// between: the unsaved day kept for recovery, else the day saved last in
  /// the app, when every recording started on its date. The day then opens
  /// and says what was added. Otherwise the recordings start an import.
  Future<void> _continueToday(List<String> paths) async {
    final waiting = _waiting = [];
    setState(() => _opening = true);
    DayResultsController? today;
    var snapshotLeft = true;
    try {
      (day: today, :snapshotLeft) = await _todayWith(paths);
    } on Exception catch (error) {
      // Today's day could not be looked for: the recordings are imported.
      debugPrint('Today\'s day not looked for: $error');
    } finally {
      _waiting = null;
      if (mounted) setState(() => _opening = false);
    }
    if (!mounted) {
      today?.dispose();
      return;
    }
    if (today == null) {
      // Opening the imported day would replace an unsaved day kept for
      // recovery: the import stays here, next to the offer to restore it.
      _showWhenImported = !_controller.isWorking && !snapshotLeft;
      final behind = ModalRoute.of(context)?.isCurrent == false;
      final started = !_controller.isWorking;
      // Shares imported here and not opened stay one day: a later share is
      // imported together with them, not instead of them.
      if (!started) {
        // An import started meanwhile (a folder): these follow it.
        (_afterImport ??= []).addAll([...paths, ...waiting]);
        return;
      }
      final all = [..._unopenedShares, ...paths, ...waiting];
      // Until their day is shown (cleared then), also when it cannot open by
      // itself because another page is on top.
      _unopenedShares = all;
      _start(all);
      if (behind && started) _tellImportingBehind();
      return;
    }
    final shown = _show(today);
    if (waiting.isNotEmpty) _addTo(today, waiting);
    await shown;
  }

  // Only a day worked on in the last day can be today's: older ones are not
  // opened (reading all their recordings) just to be refused.
  static bool _recent(DateTime time) =>
      DateTime.now().difference(time) < const Duration(hours: 24);

  /// The first day that takes [paths] as recordings of its date, with them
  /// added; null when none does. [snapshotLeft] says an unsaved day kept for
  /// recovery was not that day: it is left for the user to restore, so no
  /// other day is opened, which would replace it.
  Future<({DayResultsController? day, bool snapshotLeft})> _todayWith(
    List<String> paths,
  ) async {
    // From the share, opening the day included (see the diagnostics).
    final clock = Stopwatch()..start();
    final recovery = await queueRecovery(widget.recovery.load);
    if (recovery != null) {
      if (!_recent(recovery.timestamp)) return (day: null, snapshotLeft: true);
      final day = await _added(paths, clock, () async {
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
      });
      return (day: day, snapshotLeft: day == null);
    }
    // No unsaved work waits, so a saved day may open: the one just left
    // here, saved anywhere (on desktop the app keeps no list of saved days),
    // else the day saved last in the app.
    final closed = _lastDay;
    final closedPath = closed?.documentPath;
    if (closed != null && !closed.dirty && closedPath != null) {
      final day = await _added(paths, clock, () => _openSaved(closedPath));
      if (day != null) return (day: day, snapshotLeft: false);
    }
    final day = await _added(paths, clock, () async {
      final saved = await _savedDays();
      return saved.isEmpty ? null : _openSaved(saved.first);
    });
    return (day: day, snapshotLeft: false);
  }

  /// The day saved at [path] when it was saved in the last day; null
  /// otherwise or when none of its recordings can be read.
  Future<DayResultsController?> _openSaved(String path) async {
    if (!_recent(File(path).lastModifiedSync())) return null;
    await widget.fileAccess.restore();
    await completeInterruptedDaySave(path);
    final day = await Isolate.run(_openJob(path));
    return day.analysis == null
        ? null
        : DayResultsController.opened(
            day,
            recovery: widget.recovery,
            appender: widget.appender,
          );
  }

  /// The day [open] gives with [paths] added as recordings of its date;
  /// null when it gives none or does not take them. A day not taken is
  /// discarded as it was: its recovery snapshot is not written again.
  Future<DayResultsController?> _added(
    List<String> paths,
    Stopwatch clock,
    Future<DayResultsController?> Function() open,
  ) async {
    DayResultsController? day;
    try {
      day = await open();
      if (day == null) return null;
      final addition = await day.addRecordings(
        paths,
        sameDayOnly: true,
        since: clock,
      );
      if (!addition.otherDay && addition.error.isEmpty) return day;
    } on Exception catch (error) {
      debugPrint('Today\'s day not continued: $error');
    }
    day?.discard();
    return null;
  }

  /// Imports [paths].
  void _start(List<String> paths) {
    if (paths.isEmpty) return;
    if (!_controller.start(paths, includeSubfolders: _includeSubfolders)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.importBusy)));
    }
  }

  /// Imports a folder as a new day, which opens by itself, unless a day's
  /// unsaved work waits for recovery: opening the new day would replace it,
  /// so the import then stays here, next to the offer to restore that work.
  Future<void> _startDay(List<String> paths) async {
    if (paths.isEmpty || !mounted) return;
    if (_controller.isWorking || _opening) {
      _start(paths);
      return;
    }
    var nothingKept = false;
    try {
      nothingKept = await queueRecovery(widget.recovery.load) == null;
    } on Exception catch (error) {
      debugPrint('Recovery not checked before importing a folder: $error');
    }
    if (!mounted) return;
    if (_controller.isWorking || _opening) {
      _start(paths);
      return;
    }
    _unopenedShares = const [];
    _showWhenImported = nothingKept;
    _start(paths);
  }

  /// Recordings the user picked or dropped are the next sessions of today's
  /// day, as when shared from another app: added to it and shown, or
  /// imported as a new day that opens by itself.
  Future<void> _pickRecordings() async {
    final paths = await widget.pickers.pickRecordings();
    if (paths.isEmpty || !mounted) return;
    _unopenedShares = const [];
    _receive(paths);
  }

  /// Days saved in the app and in the library, the latest changed first.
  Future<List<String>> _savedDays() async {
    final days = [...await widget.documents.savedDays()];
    final library = widget.library;
    if (library != null) {
      await library.load();
      for (final day in library.profile?.days ?? const <ProfileDay>[]) {
        final path = library.pathOf(day);
        if (path != null && !days.contains(path) && File(path).existsSync()) {
          days.add(path);
        }
      }
    }
    final modified = <String, DateTime>{};
    for (final path in days) {
      try {
        modified[path] = File(path).lastModifiedSync();
      } on FileSystemException {
        // Gone meanwhile: not listed.
      }
    }
    return modified.keys.toList()
      ..sort((a, b) => modified[b]!.compareTo(modified[a]!));
  }

  /// Shows the library; a day chosen there opens here.
  Future<void> _openLibrary() async {
    final library = widget.library;
    if (library == null) return;
    final chosen = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => LibraryPage(
          library: library,
          open: (path) => Navigator.of(context).pop(path),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    // Changes to that day not saved yet (the app ended before its save)
    // are opened with it, as Restore does, so its next save keeps them.
    final eventId = [
      for (final day in library.profile?.days ?? const <ProfileDay>[])
        if (library.pathOf(day) == chosen) day.eventId,
    ].firstOrNull;
    final recovered = await queueRecovery(widget.recovery.load);
    if (!mounted) return;
    if (eventId != null && recovered?.eventId == eventId) {
      await _restore(recovered!);
    } else {
      await _openDay(chosen);
    }
  }

  // Built outside the state so the isolate's closure holds only the path.
  static OpenedDay Function() _openJob(String path) =>
      () => openDay(path);

  // Built outside the state so the isolate's closure holds only its inputs.
  static RelinkedDay Function() _relinkJob(
    String path,
    String folder,
    List<MissingRecording> missing,
    List<MissingRecording> alternatives,
  ) =>
      () => relinkDay(path, folder, missing, missingAlternatives: alternatives);

  /// The day to open: on phones from the days saved in the app, else from
  /// the open dialog.
  Future<String?> _chooseDocument() async {
    final saved = await widget.documents.savedDays();
    if (saved.isEmpty || !mounted) return widget.documents.pickDocument();
    const other = '';
    final choice = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.importPageOpenSavedTitle),
        children: [
          for (final path in saved)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, path),
              child: Text(p.basenameWithoutExtension(path)),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, other),
            child: Text(context.l10n.importPageAnotherFile),
          ),
        ],
      ),
    );
    if (choice == other) return widget.documents.pickDocument();
    return choice;
  }

  /// Opens the day saved at [chosen], or one the user chooses.
  Future<void> _openDay([String? chosen]) async {
    final path = chosen ?? await _chooseDocument();
    if (path == null || !mounted) return;
    if (_opening || _shownDay != null) {
      // A shared recording opened a day while the choice was made.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPageAnotherOpening)),
      );
      return;
    }
    _waiting = [];
    setState(() => _opening = true);
    try {
      await widget.fileAccess.restore();
      await completeInterruptedDaySave(path);
      var day = await Isolate.run(_openJob(path));
      if (!mounted) return;
      // None of its recordings could be read: look for them in a folder the
      // user chooses, which also gives the app access to them, until some
      // are found or the user gives up.
      while (day.analysis == null) {
        if (!await _cannotOpen(day) || !mounted) return;
        final folder = await widget.documents.pickFolder();
        if (folder == null || !mounted) return;
        final relinked = await Isolate.run(
          _relinkJob(path, folder, day.missing, day.missingAlternatives),
        );
        if (!mounted) return;
        day = relinked.day;
        // An RCZ found only by its name that is another drive: not used.
        final different = [
          for (final file in relinked.differentAlternatives.values)
            p.basename(file),
        ];
        if (different.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.fusionRelinkDifferent(different.join(', ')),
              ),
            ),
          );
        }
      }
      await _showOpened(
        DayResultsController.opened(
          day,
          recovery: widget.recovery,
          appender: widget.appender,
        ),
      );
    } on Exception catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.importPageNotOpened('$error'))),
        );
      }
    } finally {
      _openingDone();
    }
  }

  Future<void> _pickFolder() async {
    final folder = await widget.pickers.pickFolder();
    if (folder == null) return;
    await _startDay([folder]);
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
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.primary,
          ),
        ),
        // At most 840 wide, centred: on a large screen the buttons and the
        // sessions stay together.
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: EdgeInsets.symmetric(
              horizontal: math.max(16, (constraints.maxWidth - 840) / 2),
              vertical: 16,
            ),
            children: [
              ..._choices(context),
              const SizedBox(height: 16),
              ..._status(context),
            ],
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.importPageTitle),
        actions: const [SettingsButton(), DiagnosticsMenu()],
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
                if (paths.isEmpty) return;
                // A folder is a day; recordings are its next sessions.
                if (paths.any(FileSystemEntity.isDirectorySync)) {
                  unawaited(_startDay(paths));
                } else {
                  _unopenedShares = const [];
                  _receive(paths);
                }
              },
              child: content,
            ),
    );
  }

  List<Widget> _choices(BuildContext context) {
    final enabled = !_controller.isWorking;
    final recovered = _recovered;
    return [
      if (_lastDay case final day?)
        ..._dayCard(context, day, enabled: enabled)
      else if (recovered != null)
        ..._recoveryCard(context, recovered, enabled: enabled),
      // Where a day starts: the recordings, a folder or a saved day, in one
      // panel the recordings can also be dropped on.
      Card(
        key: const ValueKey('importChoices'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _acceptsDrops
                        ? Icons.file_download_outlined
                        : Icons.insert_drive_file_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _acceptsDrops
                          ? context.l10n.importPageIntroDrop
                          : _picksFolders
                          ? context.l10n.importPageIntroFolder
                          : context.l10n.importPageIntro,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: enabled && !_opening ? _pickRecordings : null,
                    icon: const Icon(Icons.insert_drive_file_outlined),
                    label: Text(context.l10n.importPageChooseRecordings),
                  ),
                  if (_picksFolders)
                    OutlinedButton.icon(
                      onPressed: enabled && !_opening ? _pickFolder : null,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: Text(context.l10n.importPageChooseFolder),
                    ),
                  OutlinedButton.icon(
                    onPressed: enabled && !_opening ? _openDay : null,
                    icon: const Icon(Icons.history),
                    label: Text(
                      _opening
                          ? context.l10n.importPageOpening
                          : context.l10n.importPageOpenSaved,
                    ),
                  ),
                  if (widget.library != null)
                    OutlinedButton.icon(
                      key: const ValueKey('openLibrary'),
                      onPressed: enabled && !_opening ? _openLibrary : null,
                      icon: const Icon(Icons.collections_bookmark_outlined),
                      label: Text(context.l10n.importPageLibrary),
                    ),
                  if (_picksFolders)
                    _option(
                      key: const ValueKey('includeSubfolders'),
                      value: _includeSubfolders,
                      label: context.l10n.importPageIncludeSubfolders,
                      onChanged: enabled
                          ? (value) =>
                                setState(() => _includeSubfolders = value)
                          : null,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  /// The unsaved day kept from before, to restore or discard.
  List<Widget> _recoveryCard(
    BuildContext context,
    DayRecovery recovered, {
    required bool enabled,
  }) => [
    Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.importPageUnsaved(
                recovered.name,
                _when(recovered.timestamp),
              ),
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
                  child: Text(context.l10n.importPageRestore),
                ),
                TextButton(
                  onPressed: enabled && !_opening
                      ? () => _discard(recovered)
                      : null,
                  child: Text(context.l10n.importPageDiscardEllipsis),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    const SizedBox(height: 16),
  ];

  /// The day closed last, with its sessions: opened again from its unsaved
  /// changes or its file. Unsaved changes of another day are offered too.
  List<Widget> _dayCard(
    BuildContext context,
    _ClosedDay day, {
    required bool enabled,
  }) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final recovered = _recovered;
    final own = recovered != null && recovered.eventId == day.eventId;
    final path = day.documentPath;
    final VoidCallback? open = own
        ? () => _restore(recovered)
        : path == null
        ? null
        : () => _openDay(path);
    return [
      if (recovered != null && !own)
        ..._recoveryCard(context, recovered, enabled: enabled),
      Card(
        key: const ValueKey('lastDay'),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(day.name, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                own
                    ? l10n.importPageDayUnsaved(_when(recovered.timestamp))
                    : day.dirty
                    ? l10n.importPageDayNotKept
                    : widget.library?.holds(path!) ?? false
                    ? l10n.savedToLibrary
                    : l10n.importPageDaySaved(p.basename(path!)),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (open != null)
                    FilledButton.icon(
                      key: const ValueKey('openLastDay'),
                      onPressed: enabled && !_opening ? open : null,
                      icon: const Icon(Icons.flag_outlined),
                      label: Text(l10n.importPageShowResults),
                    ),
                  if (own)
                    TextButton(
                      onPressed: enabled && !_opening
                          ? () => _discard(recovered)
                          : null,
                      child: Text(l10n.importPageDiscardEllipsis),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      _sessions(context, day.rows, day.ranking),
      const SizedBox(height: 16),
    ];
  }

  /// A checkbox whose label toggles it too, and wraps in a narrow window.
  Widget _option({
    required Key key,
    Key? checkboxKey,
    required bool value,
    required String label,
    required ValueChanged<bool>? onChanged,
  }) => MergeSemantics(
    child: InkWell(
      key: key,
      borderRadius: BorderRadius.circular(4),
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // One focus stop per option: the row takes the focus.
            ExcludeFocus(
              child: Checkbox(
                key: checkboxKey,
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (checked) => onChanged(checked ?? false),
              ),
            ),
            Flexible(child: Text(label)),
          ],
        ),
      ),
    ),
  );

  /// A failed or cancelled import: what happened and, for a failure, what
  /// to do next.
  Widget _banner(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required Color color,
    required String text,
    String? next,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: key,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: theme.textTheme.bodyLarge?.copyWith(color: color),
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      next,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _status(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    List<Widget> notes(List<String> notes) => [
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(l10n.importPageNotes, style: theme.textTheme.titleSmall),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l10n.coreText(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ];
    switch (_controller.state) {
      case DayImportIdle() when _opening:
        // Opening a day, or adding recordings to today's day before it shows.
        return [Text(l10n.importPageOpeningDay)];
      case DayImportIdle():
        return const [];
      case DayImportWorking(:final processed, :final total):
        return [
          Text(
            total == 0
                ? l10n.importPageLooking
                : l10n.importPagePreparing(
                    processed < total ? processed + 1 : total,
                    total,
                  ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: total == 0 ? null : processed / total,
            semanticsLabel: l10n.importPageProgress,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _controller.cancel,
              child: Text(l10n.cancel),
            ),
          ),
        ];
      case DayImportCancelled():
        return [
          _banner(
            context,
            key: const ValueKey('importCancelled'),
            icon: Icons.info_outline,
            color: theme.colorScheme.onSurfaceVariant,
            text: l10n.importPageCancelled,
          ),
        ];
      case DayImportFailed(
        :final message,
        notes: final failedNotes,
        :final reviewChanged,
      ):
        return [
          _banner(
            context,
            key: const ValueKey('importFailed'),
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            text: reviewChanged ? l10n.reviewChanged : l10n.coreText(message),
            next: reviewChanged ? null : l10n.importPageChooseAgain,
          ),
          ...notes(failedNotes),
        ];
      case DayImportFinished(
        :final runs,
        :final analysis,
        notes: final finishedNotes,
      ):
        return [
          Text(
            l10n.importPageSessionsImported(runs.length),
            style: theme.textTheme.titleMedium,
          ),
          if (analysis != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => _showImported(runs, analysis),
                icon: const Icon(Icons.flag_outlined),
                label: Text(l10n.importPageShowResults),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _sessions(context, [
            for (final named in runs) _SessionRow.of(named),
          ], analysis?.ranking),
          ...notes(finishedNotes),
        ];
    }
  }

  // The imported sessions as a timing table: each session's laps, and its
  // best time on the right. A session the day ranks shows its best ranked
  // lap, and the session of the best lap of the day is purple and bold, as
  // on the day page; a session outside the ranking (another layout) shows
  // its recording's fastest lap.
  Widget _sessions(
    BuildContext context,
    List<_SessionRow> runs,
    DayRanking? ranking,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final bests = [
      for (final row in runs)
        switch (ranking?.runs.where((run) => run.runId == row.runId)) {
          final ranked? when ranked.isNotEmpty =>
            ranked.first.bestLap?.durationSeconds,
          _ => row.fastest,
        },
    ];
    final dayBestRun = ranking?.bestOfDay?.runId;
    // A ranked session with laps but none ranked says so, as on the day page.
    String summary(int i) {
      final row = runs[i];
      final ranked = ranking?.runs.where((run) => run.runId == row.runId);
      return ranked != null &&
              ranked.isNotEmpty &&
              bests[i] == null &&
              row.status == LapSessionStatus.available &&
              row.lapCount > 0
          ? l10n.noRankedLap(row.lapCount)
          : _lapSummary(l10n, row);
    }

    return Card(
      key: const ValueKey('importSessions'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < runs.length; ++i) ...[
            if (i > 0) const Divider(height: 1),
            Padding(
              key: ValueKey('importSession ${runs[i].name}'),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.session(runs[i].name),
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          summary(i),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (bests[i] case final seconds?)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          l10n.importPageBest,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          displayTime(seconds),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFamily: FetTheme.mono,
                            fontWeight: runs[i].runId == dayBestRun
                                ? FontWeight.w700
                                : null,
                            color: runs[i].runId == dayBestRun
                                ? colors.dayBest
                                : null,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// What a day held when its page closed: its sessions for the import page,
/// and where to open it again.
final class _ClosedDay {
  _ClosedDay.of(DayResultsController day)
    : eventId = day.eventId,
      name = day.name,
      rows = [for (final named in day.runs) _SessionRow.of(named)],
      ranking = day.ranking,
      documentPath = day.documentPath,
      dirty = day.dirty;

  final String eventId;
  final String name;

  /// The sessions as listed; not their telemetry, which the day keeps.
  final List<_SessionRow> rows;
  final DayRanking? ranking;

  /// Where the day was saved or opened from; null when never saved.
  final String? documentPath;

  /// Whether it had changes not in [documentPath], kept for recovery.
  final bool dirty;
}

/// What the import page lists of a session.
final class _SessionRow {
  _SessionRow.of(NamedRun named)
    : name = named.name,
      runId = named.run.id,
      status = named.run.laps.status,
      lapCount = named.run.laps.status == LapSessionStatus.available
          ? named.run.laps.timedLaps.length
          : 0,
      fastest = _bestSeconds(named.run.laps),
      hasGps =
          named.run.laps.status == LapSessionStatus.available ||
          hasGpsPositions(named.run.telemetry, named.run.laps);

  final String name;
  final String runId;
  final LapSessionStatus status;

  /// Timed laps; 0 without laps.
  final int lapCount;

  /// The recording's fastest timed lap, in seconds; null without one.
  final double? fastest;
  final bool hasGps;
}
