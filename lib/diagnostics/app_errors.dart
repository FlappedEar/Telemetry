import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n.dart';

/// One error the app did not expect: when, what, and where it happened.
@immutable
final class AppErrorRecord {
  const AppErrorRecord({
    required this.time,
    required this.summary,
    required this.details,
  });

  final DateTime time;

  /// One line: the error's message, prefixed with what the app was doing
  /// when it knows.
  final String summary;

  /// The summary and the stack trace, for a bug report.
  final String details;
}

/// The unexpected errors since the app started, newest last, so a driver
/// can see that something failed and copy the details for a bug report.
/// Kept for the app's lifetime only; nothing is written anywhere.
final class AppErrors extends ChangeNotifier {
  AppErrors({this.capacity = 20, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// The most errors kept; older ones are dropped first.
  final int capacity;
  final DateTime Function() _clock;
  final List<AppErrorRecord> _records = [];

  /// Errors dropped because more than [capacity] arrived.
  int get dropped => _dropped;
  int _dropped = 0;

  List<AppErrorRecord> get records => List.unmodifiable(_records);

  /// Keeps [error]. [context] says what the app was doing ("Saving the
  /// day"), in English, as bug reports are.
  void record(Object error, StackTrace? stack, {String? context}) {
    final message = _firstLine('$error');
    final summary = context == null ? message : '$context: $message';
    final trace = stack == null ? '' : '\n${_trimmed(stack)}';
    _records.add(
      AppErrorRecord(
        time: _clock(),
        summary: summary,
        details: '$summary$trace',
      ),
    );
    if (_records.length > capacity) {
      _records.removeAt(0);
      _dropped++;
    }
    notifyListeners();
  }

  /// Every kept error with its stack trace, newest last, for the clipboard.
  String report() => [
    if (_dropped > 0) '($_dropped earlier errors not kept)',
    for (final record in _records)
      '${record.time.toIso8601String()} ${record.details}',
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
  static String _trimmed(StackTrace stack) {
    final lines = '$stack'.trimRight().split('\n');
    return lines.length <= 40
        ? lines.join('\n')
        : [...lines.take(40), '…'].join('\n');
  }
}

/// The app's errors.
final appErrors = AppErrors();

/// The app's own [ScaffoldMessenger], so an error from anywhere can say so.
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Routes every error nothing else handled to [errors]:
/// - errors while building, laying out or painting a widget
///   ([FlutterError.onError]), which are still printed as before;
/// - errors of asynchronous work nobody awaited
///   ([PlatformDispatcher.onError]).
///
/// In a release build a widget that fails to build shows [FailedPart]
/// instead of an empty grey box. After an error a short message points to
/// Diagnostics, at most once a minute for the same error.
void installErrorHandlers() {
  final reporter = AppErrorReporter(appErrors, appMessengerKey);
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    reporter.flutterError(details);
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = reporter.platformError;
  if (kReleaseMode) {
    ErrorWidget.builder = (details) => FailedPart(details: details);
  }
}

/// Records an error in [errors] and says so through [messenger]: a short
/// message that points to Diagnostics, at most once a minute for the same
/// error.
final class AppErrorReporter {
  AppErrorReporter(this.errors, this.messenger);

  final AppErrors errors;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final Map<String, DateTime> _shown = {};

  /// For [FlutterError.onError].
  void flutterError(FlutterErrorDetails details) {
    errors.record(
      details.exception,
      details.stack,
      context: details.context?.toDescription(),
    );
    _notify(errors.records.last.summary);
  }

  /// For [PlatformDispatcher.onError]: the error is handled.
  bool platformError(Object error, StackTrace stack) {
    errors.record(error, stack);
    _notify(errors.records.last.summary);
    debugPrint('Unhandled error: $error\n$stack');
    return true;
  }

  void _notify(String summary) {
    final now = DateTime.now();
    final last = _shown[summary];
    if (last != null && now.difference(last) < const Duration(minutes: 1)) {
      return;
    }
    _shown[summary] = now;
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

/// What a widget that failed to build shows in a release build: a short
/// note in place of the part, instead of an empty grey box.
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
