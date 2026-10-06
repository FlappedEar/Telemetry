import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../l10n.dart';
import 'day_report_page.dart';

/// Where a day report image goes: the share sheet on phones, a file the
/// user chooses on desktop. Replaced by a fake in widget tests.
abstract interface class ReportSharer {
  /// Whether the image is handed to the share sheet (phones) rather than
  /// saved where the user chooses (desktop).
  bool get shares;

  /// Where the user saves the image [fileName]; null when cancelled.
  Future<String?> saveLocation(String fileName);

  /// A file in the app's own temporary folder the image is written to
  /// before it is shared, the last report's left there removed.
  Future<String> workFile(String fileName);

  /// Opens the share sheet with the image at [path], from [origin] (the
  /// iPad shows it there); false when the user closed it without sharing.
  Future<bool> share(String path, Rect origin);
}

bool get _desktop =>
    !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

/// The system save dialog on desktop; the share sheet on phones.
final class PlatformReportSharer implements ReportSharer {
  const PlatformReportSharer();

  @override
  bool get shares => !_desktop;

  @override
  Future<String?> saveLocation(String fileName) async {
    final location = await getSaveLocation(
      // The macOS panel adds the extension itself.
      suggestedName: Platform.isMacOS
          ? p.basenameWithoutExtension(fileName)
          : fileName,
      acceptedTypeGroups: [
        XTypeGroup(
          label: deviceL10n().reportImageType,
          extensions: const ['png'],
          mimeTypes: const ['image/png'],
          uniformTypeIdentifiers: const ['public.png'],
        ),
      ],
    );
    if (location == null) return null;
    final path = p.extension(location.path).toLowerCase() == '.png'
        ? location.path
        : '${location.path}.png';
    // A file the dialog did not ask about replacing (the extension was
    // added, or the Linux dialog, which never asks) is kept.
    if (path == location.path && !Platform.isLinux) return path;
    var free = path;
    for (var copy = 2; File(free).existsSync(); copy++) {
      free = p.join(
        p.dirname(path),
        '${p.basenameWithoutExtension(path)} ($copy).png',
      );
    }
    return free;
  }

  @override
  Future<String> workFile(String fileName) async {
    final folder = Directory(
      p.join((await getTemporaryDirectory()).path, 'report-share'),
    );
    if (folder.existsSync()) folder.deleteSync(recursive: true);
    folder.createSync(recursive: true);
    return p.join(folder.path, fileName);
  }

  @override
  Future<bool> share(String path, Rect origin) async {
    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'image/png')],
        sharePositionOrigin: origin,
      ),
    );
    return result.status != ShareResultStatus.dismissed;
  }
}

/// What became of a shared report.
enum ReportShareOutcome { shared, saved, cancelled }

/// The report is taller than one image may be.
final class ReportImageTooLong implements Exception {
  const ReportImageTooLong();

  @override
  String toString() => 'The report is too long for one image.';
}

/// The width of the report image in logical pixels; drawn at up to twice
/// that.
const double reportImageWidth = 600;

/// The tallest image drawn, in physical pixels: within what every GPU
/// accepts as one texture.
const int maximumReportImagePixels = 8192;

final _reservedWindowsNames = {
  'CON', 'PRN', 'AUX', 'NUL', //
  for (var i = 1; i <= 9; ++i) ...['COM$i', 'LPT$i'],
};

/// "Jastrząb 29 Aug 2026.png": [name] without characters a file name may
/// not hold, at most 100 characters, else "[fallback].png".
String reportFileName(String name, String fallback) {
  var clean = name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (clean.length > 100) clean = clean.substring(0, 100).trim();
  // Windows refuses a name ending in a dot or space, or a device name.
  clean = clean.replaceAll(RegExp(r'[. ]+$'), '');
  if (_reservedWindowsNames.contains(clean.toUpperCase())) clean = '';
  return '${clean.isEmpty ? fallback : clean}.png';
}

/// Draws [report] as one image, as the Report tab shows it (without its
/// buttons), headed by [title], with [extra] cards (the coach) after it,
/// and shares or saves it through [sharer]. Throws when the image cannot
/// be drawn or written ([ReportImageTooLong] when it is too tall).
Future<ReportShareOutcome> shareDayReport(
  BuildContext context, {
  required Map<String, Object?> report,
  required String title,
  required ReportSharer sharer,
  required Rect origin,
  List<Widget> extra = const [],
}) async {
  final l10n = context.l10n;
  final fileName = reportFileName(title, l10n.dayReport);
  final image = await renderWidgetImage(
    View.of(context),
    reportImageFrame(
      context,
      DayReportPage(
        report: report,
        printable: true,
        heading: title,
        extra: extra,
      ),
    ),
    width: reportImageWidth,
  );
  if (sharer.shares) {
    final path = await sharer.workFile(fileName);
    await File(path).writeAsBytes(image, flush: true);
    return await sharer.share(path, origin)
        ? ReportShareOutcome.shared
        : ReportShareOutcome.cancelled;
  }
  final path = await sharer.saveLocation(fileName);
  if (path == null) return ReportShareOutcome.cancelled;
  await File(path).writeAsBytes(image, flush: true);
  return ReportShareOutcome.saved;
}

/// Why sharing the report failed, in the app's language where it is known.
String reportShareError(AppLocalizations l10n, Object error) => switch (error) {
  ReportImageTooLong() => l10n.reportImageTooLong,
  FileSystemException(:final osError?) => osError.message,
  FileSystemException(:final message) => message,
  _ => '$error',
};

/// [child] with what it reads from [context]'s app: theme, language (the
/// app's loaded texts) and text direction, at text scale 1 so the image
/// looks the same anywhere.
Widget reportImageFrame(BuildContext context, Widget child) {
  final theme = Theme.of(context);
  return MediaQuery(
    data: const MediaQueryData(textScaler: TextScaler.noScaling),
    child: Localizations.override(
      context: context,
      child: Directionality(
        textDirection: Directionality.of(context),
        child: Theme(
          data: theme,
          child: Material(color: theme.scaffoldBackgroundColor, child: child),
        ),
      ),
    ),
  );
}

/// [widget] laid out [width] wide and as tall as it needs, drawn off
/// screen for [view] at [pixelRatio] (less for a tall widget, so the image
/// stays at most [maximumReportImagePixels] tall) and encoded as PNG.
/// Throws [ReportImageTooLong] when even that cannot hold it.
Future<Uint8List> renderWidgetImage(
  ui.FlutterView view,
  Widget widget, {
  required double width,
  double pixelRatio = 2,
}) async {
  const maximumHeight = 100000.0;
  final boundary = RenderRepaintBoundary();
  final constraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: maximumHeight,
  );
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: constraints,
      physicalConstraints: constraints,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);
  RenderObjectToWidgetElement<RenderBox>? root;
  try {
    root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: double.infinity,
        fit: OverflowBoxFit.deferToChild,
        child: widget,
      ),
    ).attachToRenderTree(build);
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline.flushLayout();
    final height = boundary.size.height;
    final ratio = math.min(pixelRatio, maximumReportImagePixels / height);
    // Too tall for the image, or for the layout: never a cut-off report.
    if (height >= maximumHeight || ratio < 0.75) {
      throw const ReportImageTooLong();
    }
    pipeline
      ..flushCompositingBits()
      ..flushPaint();
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('The report image could not be encoded.');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // Unmount the tree and let the render objects go.
    if (root != null) {
      RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
          .attachToRenderTree(build, root);
      build.finalizeTree();
    }
    pipeline.rootNode = null;
    renderView.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}
