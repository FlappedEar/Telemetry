import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';

/// One error the app did not expect: when, what, and where it happened.
@immutable
final class AppErrorRecord {
  const AppErrorRecord({
    required this.firstTime,
    required this.time,
    required this.summary,
    required this.details,
    this.count = 1,
  });

  /// When it first happened.
  final DateTime firstTime;

  /// When it last happened.
  final DateTime time;

  /// One line: the error's message, prefixed with what the app was doing
  /// when it knows.
  final String summary;

  /// The summary and the stack trace of its first occurrence, for a bug
  /// report.
  final String details;

  /// How often it happened.
  final int count;
}

/// The unexpected errors since the app started, so a driver can see that
/// something failed and copy the details for a bug report. An error that
/// happens again is counted, not added again, so a repeating error never
/// pushes out the first one. Kept for the app's lifetime only; nothing is
/// written anywhere.
final class AppErrors extends ChangeNotifier {
  AppErrors({this.capacity = 20, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The most different errors kept; the least recent ones are dropped
  /// first.
  final int capacity;
  final DateTime Function() _clock;
  final List<AppErrorRecord> _records = [];

  /// Errors dropped because more than [capacity] different ones arrived.
  int get dropped => _dropped;
  int _dropped = 0;

  /// Least recent first.
  List<AppErrorRecord> get records => List.unmodifiable(_records);

  /// Keeps [error] and returns its one-line summary. [context] says what
  /// the app was doing ("Saving the day"), in English, as bug reports are.
  /// [stackText] stands in for [stack] when the trace arrived as text (from
  /// a background isolate).
  String record(
    Object error,
    StackTrace? stack, {
    String? context,
    String? stackText,
  }) {
    final message = _firstLine('$error');
    final summary = context == null ? message : '$context: $message';
    final now = _clock();
    final known = _records.indexWhere((record) => record.summary == summary);
    if (known >= 0) {
      final earlier = _records.removeAt(known);
      _records.add(
        AppErrorRecord(
          firstTime: earlier.firstTime,
          time: now,
          summary: summary,
          details: earlier.details,
          count: earlier.count + 1,
        ),
      );
    } else {
      final trace = stackText ?? (stack == null ? '' : '$stack');
      _records.add(
        AppErrorRecord(
          firstTime: now,
          time: now,
          summary: summary,
          details: trace.trim().isEmpty
              ? summary
              : '$summary\n${_trimmed(trace)}',
        ),
      );
      if (_records.length > capacity) {
        _records.removeAt(0);
        _dropped++;
      }
    }
    notifyListeners();
    return summary;
  }

  /// Every kept error with its stack trace, least recent first, for the
  /// clipboard.
  String report() => [
    if (_dropped > 0)
      _dropped == 1
          ? '(1 earlier error not kept)'
          : '($_dropped earlier errors not kept)',
    for (final record in _records)
      '${record.firstTime.toIso8601String()}'
          '${record.count > 1 ? ' (${record.count} times, last ${record.time.toIso8601String()})' : ''}'
          ' ${record.details}',
  ].join('\n\n');

  void clear() {
    _records.clear();
    _dropped = 0;
    notifyListeners();
  }

  static String _firstLine(String text) {
    final line = text.trim().split('\n').first.trim();
    return line.length <= 300 ? line : '${line.substring(0, 300)}…';
  }

  // The frames that matter for a report; a deep stack is cut.
  static String _trimmed(String stack) {
    final lines = stack.trimRight().split('\n');
    return lines.length <= 40
        ? lines.join('\n')
        : [...lines.take(40), '…'].join('\n');
  }
}

/// The app's errors.
final appErrors = AppErrors();

/// The app's own [ScaffoldMessenger], so an error from anywhere can say so.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Reports the app's errors to [appErrors] and [appMessengerKey].
final appErrorReporter = AppErrorReporter(appErrors, appMessengerKey);

/// Keeps [error] in [appErrors] and tells the user, for an error the app
/// caught but that means something did not work (a recovery write, say).
void reportError(Object error, StackTrace? stack, {String? context}) =>
    appErrorReporter.report(error, stack, context: context);

/// Routes every error nothing else handled to [appErrorReporter]:
/// - errors while building, laying out or painting a widget
///   ([FlutterError.onError]), which are still passed on to the previous
///   handler (in debug builds it prints them);
/// - errors of asynchronous work nobody awaited
///   ([PlatformDispatcher.onError]).
///
/// Outside debug builds a widget that fails to build shows [FailedPart]
/// instead of an empty grey box.
void installErrorHandlers({AppErrorReporter? reporter}) {
  final target = reporter ?? appErrorReporter;
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    target.flutterError(details);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = target.platformError;
  if (!kDebugMode) {
    ErrorWidget.builder = (details) => FailedPart(details: details);
  }
}

/// Records an error in [errors] and says so through [messenger]: a short
/// message that points to Diagnostics. The same error shows it at most
/// once a minute, and no two show within ten seconds, so a burst of
/// errors is one message.
final class AppErrorReporter {
  AppErrorReporter(this.errors, this.messenger, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppErrors errors;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final DateTime Function() _clock;
  final Map<String, DateTime> _shown = {};
  DateTime? _lastShown;

  /// Keeps [error] and tells the user.
  void report(Object error, StackTrace? stack, {String? context}) =>
      _notify(errors.record(error, stack, context: context));

  /// For [FlutterError.onError].
  void flutterError(FlutterErrorDetails details) => report(
    details.exception,
    details.stack,
    context: details.context?.toDescription(),
  );

  /// For [PlatformDispatcher.onError]: the error is handled.
  bool platformError(Object error, StackTrace stack) {
    report(error, stack);
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  }

  /// Keeps the defects `telemetry_core` caught in a background import or
  /// analysis and turned into a file's error or a session's note, with
  /// their stack traces, and tells the user once.
  void coreDefects({
    TelemetryImportPlan? plan,
    Iterable<DayMessage> messages = const [],
    Iterable<String> notes = const [],
  }) {
    String? last;
    // Notes of an addition ("file.vbo: Unexpected error …") carry no trace.
    for (final note in notes) {
      if (note.contains(unexpectedFileError)) {
        last = errors.record(note, null, context: 'Adding recordings');
      }
    }
    for (final file in plan?.files ?? const <TelemetryImportFileResult>[]) {
      if (file.message.startsWith(unexpectedFileError)) {
        last = errors.record(
          file.message.substring(unexpectedFileError.length),
          null,
          context: 'Reading ${file.requestedPath.split(RegExp(r'[/\\]')).last}',
          stackText: file.detail,
        );
      }
    }
    for (final message in messages) {
      if (message.text.startsWith(unexpectedRunError)) {
        last = errors.record(
          message.text.substring(unexpectedRunError.length),
          null,
          context: 'Analysing run ${message.runId}',
          stackText: message.detail,
        );
      }
    }
    if (last != null) _notify(last);
  }

  void _notify(String summary) {
    final now = _clock();
    // Without the app (a unit test, before the first frame) there is no
    // one to tell.
    if (messenger.currentState == null) return;
    _shown.removeWhere(
      (_, time) => now.difference(time) >= const Duration(minutes: 1),
    );
    final lastShown = _lastShown;
    if (_shown.containsKey(summary) ||
        (lastShown != null &&
            now.difference(lastShown) < const Duration(seconds: 10))) {
      return;
    }
    _shown[summary] = now;
    _lastShown = now;
    // A build error must not show a message during that build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = messenger.currentState;
      final context = messenger.currentContext;
      if (state == null || context == null || !context.mounted) return;
      final l10n = Localizations.of<AppLocalizations>(
        context,
        AppLocalizations,
      );
      state.showSnackBar(
        SnackBar(
          content: Text(
            l10n?.appErrorNotice ??
                'Something went wrong. Details are in Diagnostics.',
          ),
        ),
      );
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }
}

/// What a widget that failed to build shows outside debug builds: a short
/// note in place of the part, instead of an empty grey box. Like Flutter's
/// own error box it is a box: a failing sliver still fails as before.
class FailedPart extends StatelessWidget {
  const FailedPart({super.key, this.details});

  final FlutterErrorDetails? details;

  @override
  Widget build(BuildContext context) {
    // Above the app's Directionality (in the app's root) a text cannot
    // show; fall back to the framework's error box.
    if (Directionality.maybeOf(context) == null) {
      return ErrorWidget.withDetails(
        message: '${details?.exception ?? ''}',
        error: details?.exception is FlutterError
            ? details!.exception as FlutterError
            : null,
      );
    }
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    final color = Theme.of(context).colorScheme.error;
    // One text, no Row or Flexible: the part may sit where the width or
    // height is unbounded, and this must not fail in turn.
    return Padding(
      key: const ValueKey('failedPart'),
      padding: const EdgeInsets.all(8),
      child: Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(Icons.error_outline, color: color, size: 18),
            ),
            TextSpan(
              text: ' ${l10n?.appErrorPart ?? 'This part could not be shown.'}',
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: color),
      ),
    );
  }
}
