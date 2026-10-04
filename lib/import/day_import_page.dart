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
import '../diagnostics/diagnostics_page.dart';
import '../format.dart';
import '../l10n.dart';
import '../settings_dialog.dart';
import '../ui/theme.dart';
import 'day_import_controller.dart';
import 'file_access.dart';
import 'import_review_page.dart';
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

String _lapSummary(
  AppLocalizations l10n,
  LapSession laps,
  TelemetrySession session,
) {
  // Lap detection looks for the start/finish line before GPS; without GPS
  // the line is not what is missing.
  if (laps.status != LapSessionStatus.available &&
      !hasGpsPositions(session, laps)) {
    return l10n.importPageNoGps;
  }
  switch (laps.status) {
    case LapSessionStatus.available:
      return l10n.importPageLaps(laps.timedLaps.length);
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

// What the import says (`DayImportFailed.message`, the notes of a scan and
// a plan) as written in `import_runner.dart`, `day_import_controller.dart`
// and `telemetry_core`'s folder scan.
final _folderTooMany = RegExp(
  r'^The folder holds (\d+) recordings; import at most (\d+) at a time\. '
  r'Choose a smaller folder\.$',
);
final _tooMany = RegExp(
  r'^That is (\d+) recordings; import at most (\d+) at a time\.$',
);
final _stoppedAfter = RegExp(
  r'^Stopped after (\d+) files and folders; recordings beyond that were '
  r'not scanned\.$',
);
final _tooDeep = RegExp(
  r'^(\d+) folder\(s\) deeper than (\d+) levels were not scanned\.$',
);
final _links = RegExp(r'^(\d+) link\(s\) were not followed\.$');
final _others = RegExp(
  r'^(\d+) other file\(s\) were ignored; only VBO and RCZ recordings are '
  r'imported\.$',
);
final _sameContent = RegExp(r'^same content as (.+); imported once\.$');
// Not the note of adding to a day, "... as Session 2 in the other format;
// kept as ...".
final _sameDrive = RegExp(
  r'^the same drive as ((?:(?! in the other format;).)+); kept as its '
  r'alternative source\.$',
);

/// The import's errors and notes in the app's language.
extension ImportMessageText on AppLocalizations {
  /// An error or a note of an import, also one about a file or folder
  /// ("a.vbo: not found; not imported."), in the app's language; one the
  /// app does not know, such as a reading error, is shown as written.
  String importMessage(String message) {
    if (_importMessage(message) case final known?) return known;
    // "name: text", the name being the part before the first ": " whose
    // text is known.
    for (
      var at = message.indexOf(': ');
      at >= 0;
      at = message.indexOf(': ', at + 2)
    ) {
      if (_importMessage(message.substring(at + 2)) case final known?) {
        return '${message.substring(0, at)}: $known';
      }
    }
    return message;
  }

  String? _importMessage(String message) {
    int number(Match match, int group) => int.parse(match.group(group)!);
    if (message.startsWith(unexpectedFileError)) {
      return importUnexpectedError(
        message.substring(unexpectedFileError.length),
      );
    }
    const failed = 'The import failed: ';
    if (message.startsWith(failed)) {
      return importPageImportFailed(
        importMessage(message.substring(failed.length)),
      );
    }
    if (_folderTooMany.firstMatch(message) case final match?) {
      return importPageFolderTooMany(number(match, 1), number(match, 2));
    }
    if (_tooMany.firstMatch(message) case final match?) {
      return importPageTooMany(number(match, 1), number(match, 2));
    }
    if (_stoppedAfter.firstMatch(message) case final match?) {
      return importPageStoppedAfter(number(match, 1));
    }
    if (_tooDeep.firstMatch(message) case final match?) {
      return importPageTooDeep(number(match, 1), number(match, 2));
    }
    if (_links.firstMatch(message) case final match?) {
      return importPageLinksSkipped(number(match, 1));
    }
    if (_others.firstMatch(message) case final match?) {
      return importPageOtherFilesSkipped(number(match, 1));
    }
    if (_sameContent.firstMatch(message) case final match?) {
      return importPageSameContent(match.group(1)!);
    }
    if (_sameDrive.firstMatch(message) case final match?) {
      return importPageSameDrive(match.group(1)!);
    }
    return switch (message) {
      'No recording could be imported.' => importPageNoRecording,
      'Import failed.' => importPageFailed,
      'Bad state: The import stopped unexpectedly.' =>
        importPageStoppedUnexpectedly,
      'The folder does not exist or is not a folder.' => importPageNoFolder,
      'Choose the folder itself, not a link to it.' => importPageFolderLink,
      'No VBO or RCZ recordings were found.' => importPageNoneFound,
      'No VBO or RCZ recordings were found (subfolders were not included).' =>
        importPageNoneFoundNoSubfolders,
      'No VBO or RCZ recordings to import.' => importPageNothingToImport,
      'not found; not imported.' => importPageFileNotFound,
      'a macOS metadata file, not a recording; not imported.' =>
        importPageMetadataFile,
      'a link; not followed.' => importPageFileLink,
      'not a VBO or RCZ recording; not imported.' => importPageNotRecording,
      'Choose a VBO or RaceChrono RCZ telemetry file.' => importPageChooseFile,
      'Telemetry source is not an existing regular file.' =>
        importPageNotRegularFile,
      'Too many files in one import; select a smaller batch.' =>
        importPageTooManyFiles,
      'Telemetry source path is too long.' => importPagePathTooLong,
      'Telemetry file is empty or exceeds the per-file import limit.' =>
        importPageFileSize,
      'Batch input-byte limit exceeded; import fewer recordings.' =>
        importPageBatchBytes,
      'Identical file content already present in this batch.' =>
        importPageIdenticalContent,
      'Telemetry source changed during import; retry with a stable file.' =>
        importPageSourceChanged,
      'Telemetry source has an invalid time range.' =>
        importPageInvalidTimeRange,
      'Telemetry source has mismatched channel timestamps and values.' =>
        importPageMismatchedChannels,
      'Batch decoded-sample limit exceeded; import fewer recordings.' =>
        importPageBatchSamples,
      'Source grouping exceeds the import limit.' => importPageGroupingLimit,
      _ => null,
    };
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

  /// The next import the user starts stops at a review of the recordings
  /// found (FET-58). Off by default and again after each review, so the
  /// next session needs no approval; recordings shared from another app are
  /// never reviewed.
  bool _review = false;

  // Whether the review of the import waiting for it is shown.
  bool _reviewShown = false;
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
    return day;
  }

  /// Recordings shared while an import ran; they go to its day when it
  /// opens by itself, otherwise they are received once it ends.
  List<String>? _afterImport;

  void _imported() {
    if (_controller.isWorking || !mounted) return;
    if (_controller.state case final DayImportReviewing review) {
      unawaited(_openReview(review));
      return;
    }
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

  /// Shows the review of [review]'s recordings; the import goes on as the
  /// user confirms, or ends with nothing imported.
  Future<void> _openReview(DayImportReviewing review) async {
    if (_reviewShown) return;
    _reviewShown = true;
    setState(() => _review = false);
    ImportReviewResult? result;
    try {
      result = await showImportReview(
        context,
        plan: review.plan,
        automatic: automaticImportChoices(review.plan),
      );
    } finally {
      _reviewShown = false;
    }
    if (!identical(_controller.state, review)) return;
    if (result == null || !_controller.confirm(result.choices)) {
      _controller.cancel();
    }
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
            ),
          ),
        );
      } finally {
        if (identical(_shownDay, shown)) _shownDay = null;
      }
    }
    if (!mounted) {
      next?.dispose();
      return;
    }
    await _checkRecovery();
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
    if (!_controller.isWorking && !_controller.isReviewing && !_opening) {
      unawaited(_continueToday(paths));
      return;
    }
    if (_controller.isWorking || _controller.isReviewing) {
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
    final day = await _added(paths, clock, () async {
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
    });
    return (day: day, snapshotLeft: false);
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

  /// Imports [paths]; with [review], after the user's review of what was
  /// found.
  void _start(List<String> paths, {bool review = false}) {
    if (paths.isEmpty) return;
    final started = review
        ? _controller.review(paths, includeSubfolders: _includeSubfolders)
        : _controller.start(paths, includeSubfolders: _includeSubfolders);
    if (!started) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.importPageFinishFirst)),
      );
    }
  }

  Future<void> _pickRecordings() async {
    final paths = await widget.pickers.pickRecordings();
    if (paths.isNotEmpty) _unopenedShares = const [];
    _start(paths, review: _review);
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

  Future<void> _openDay() async {
    final path = await _chooseDocument();
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
    _unopenedShares = const [];
    _start([folder], review: _review);
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
                _start(paths, review: _review);
              },
              child: content,
            ),
    );
  }

  List<Widget> _choices(BuildContext context) {
    final enabled = !_controller.isWorking && !_controller.isReviewing;
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
      ],
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
                      onPressed: enabled ? _pickFolder : null,
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
                  if (_picksFolders)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _includeSubfolders,
                          onChanged: enabled
                              ? (value) => setState(
                                  () => _includeSubfolders = value ?? false,
                                )
                              : null,
                        ),
                        Text(context.l10n.importPageIncludeSubfolders),
                      ],
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        key: const ValueKey('reviewBeforeImport'),
                        value: _review,
                        onChanged: enabled
                            ? (value) =>
                                  setState(() => _review = value ?? false)
                            : null,
                      ),
                      Flexible(child: Text(context.l10n.reviewBeforeImport)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
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
              l10n.importMessage(note),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    ];
    switch (_controller.state) {
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
          LinearProgressIndicator(value: total == 0 ? null : processed / total),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _controller.cancel,
              child: Text(l10n.cancel),
            ),
          ),
        ];
      case DayImportReviewing():
        return const [];
      case DayImportCancelled():
        return [Text(l10n.importPageCancelled)];
      case DayImportFailed(
        :final message,
        notes: final failedNotes,
        :final reviewChanged,
      ):
        return [
          Text(
            reviewChanged ? l10n.reviewChanged : l10n.importMessage(message),
            style: TextStyle(color: theme.colorScheme.error),
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
          _sessions(context, runs, analysis),
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
    List<NamedRun> runs,
    DayAnalysis? analysis,
  ) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final colors = FetColors.of(context);
    final ranking = analysis?.ranking;
    final bests = [
      for (final named in runs)
        switch (ranking?.runs.where((run) => run.runId == named.run.id)) {
          final ranked? when ranked.isNotEmpty =>
            ranked.first.bestLap?.durationSeconds,
          _ => _bestSeconds(named.run.laps),
        },
    ];
    final dayBestRun = ranking?.bestOfDay?.runId;
    // A ranked session with laps but none ranked says so, as on the day page.
    String summary(int i) {
      final laps = runs[i].run.laps;
      final ranked = ranking?.runs.where((run) => run.runId == runs[i].run.id);
      return ranked != null &&
              ranked.isNotEmpty &&
              bests[i] == null &&
              laps.status == LapSessionStatus.available &&
              laps.timedLaps.isNotEmpty
          ? l10n.noRankedLap(laps.timedLaps.length)
          : _lapSummary(l10n, laps, runs[i].run.telemetry);
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
                            fontWeight: runs[i].run.id == dayBestRun
                                ? FontWeight.w700
                                : null,
                            color: runs[i].run.id == dayBestRun
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
