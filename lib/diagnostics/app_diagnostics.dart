import 'dart:io';

/// One measured step: its name and wall time.
typedef DiagnosticStep = ({String name, Duration duration});

/// Step names, as the diagnostics page and the day benchmark
/// (packages/telemetry_core/tool/day_benchmark.dart) name them.
abstract final class DiagnosticSteps {
  static const scan = 'Find recordings';
  static const parse = 'Parse and import';
  static const analysis = 'Day analysis';
  static const fusion = 'Align and combine VBO and RCZ';
  static const importTotal = 'Import, start to results';
  static const theoreticalBest = 'Theoretical best and segments';
  static const channelSummaries = 'Channel summaries';

  /// From the share (or Add recordings) until the session is in the day,
  /// opening today's day and waiting for earlier additions included, its
  /// save not.
  static const addSession = 'Add a session';
  static const coach = 'Coach';

  /// From the same start until the Next session card has the coach's plan.
  static const addToCoach = 'Add a session, to the coach';
}

/// What the last import measured.
final class ImportDiagnostics {
  const ImportDiagnostics({
    required this.steps,
    required this.recordings,
    required this.sessions,
    required this.samples,
    required this.channelSamples,
  });

  /// In the order they ran.
  final List<DiagnosticStep> steps;

  /// Recordings read, alternative sources included.
  final int recordings;

  /// Sessions of the day (one per drive).
  final int sessions;

  /// Samples of the sessions (rows of their recordings).
  final int samples;

  /// Values of every channel of the sessions.
  final int channelSamples;
}

/// The figures the diagnostics page shows, for measuring on a phone. Kept
/// for the app's lifetime; nothing is written anywhere.
final class AppDiagnostics {
  ImportDiagnostics? _lastImport;
  final List<DiagnosticStep> _later = [];

  /// The last import, or null before the first one finished.
  ImportDiagnostics? get lastImport => _lastImport;

  /// The last import's steps, then the steps of its day measured since
  /// (the theoretical best, the channel summaries, an added session and
  /// the coach), latest of each.
  List<DiagnosticStep> get steps => [...?_lastImport?.steps, ..._later];

  /// Starts the figures of a new import.
  void recordImport(ImportDiagnostics diagnostics) {
    _lastImport = diagnostics;
    _later.clear();
  }

  /// Records a step of the day after its import; replaces an earlier
  /// measurement of the same step.
  void recordStep(String name, Duration duration) {
    _later
      ..removeWhere((step) => step.name == name)
      ..add((name: name, duration: duration));
  }
}

/// The app's figures.
final appDiagnostics = AppDiagnostics();

/// The process's resident memory now and at its peak, in bytes, as the
/// platform reports it; null where it does not.
typedef MemoryReading = ({int? current, int? peak});

/// Reads [ProcessInfo.currentRss] and [ProcessInfo.maxRss]. The peak is
/// never below the current figure: some systems update it later.
MemoryReading readProcessMemory() {
  int? read(int Function() value) {
    try {
      final bytes = value();
      return bytes > 0 ? bytes : null;
    } on Object {
      return null;
    }
  }

  final current = read(() => ProcessInfo.currentRss);
  final peak = read(() => ProcessInfo.maxRss);
  return (
    current: current,
    peak: peak == null || current == null || peak >= current ? peak : current,
  );
}
