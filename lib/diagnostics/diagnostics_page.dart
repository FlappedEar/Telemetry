import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../format.dart';
import '../ui/label_value_row.dart';
import '../update/update_dialog.dart';
import 'app_diagnostics.dart';
import 'app_errors.dart';

/// "1.84 s", or "120 ms" below a second.
String diagnosticDuration(Duration duration) {
  final milliseconds = duration.inMicroseconds / 1000.0;
  return milliseconds < 1000
      ? '${milliseconds.round()}\u00a0ms'
      : '${(milliseconds / 1000).toStringAsFixed(2)}\u00a0s';
}

/// "123.4 MiB", or "Not available" in the app's language.
String diagnosticMemory(AppLocalizations l10n, int? bytes) => bytes == null
    ? l10n.diagnosticsNotAvailable
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)}\u00a0MiB';

/// A step's name ([DiagnosticSteps]) in the app's language; a step the app
/// does not know is shown as written. The names themselves stay English:
/// the day benchmark prints them too.
String _stepName(AppLocalizations l10n, String name) => switch (name) {
  DiagnosticSteps.scan => l10n.diagnosticsStepScan,
  DiagnosticSteps.parse => l10n.diagnosticsStepParse,
  DiagnosticSteps.analysis => l10n.diagnosticsStepAnalysis,
  DiagnosticSteps.importTotal => l10n.diagnosticsStepImportTotal,
  DiagnosticSteps.theoreticalBest => l10n.diagnosticsStepTheoreticalBest,
  DiagnosticSteps.channelSummaries => l10n.diagnosticsStepChannelSummaries,
  DiagnosticSteps.fusion => l10n.diagnosticsStepFusion,
  DiagnosticSteps.addSession => l10n.diagnosticsStepAddSession,
  DiagnosticSteps.coach => l10n.diagnosticsStepCoach,
  DiagnosticSteps.addToCoach => l10n.diagnosticsStepAddToCoach,
  _ => name,
};

/// How long the last import took step by step, how much it read, and the
/// memory the platform reports for the app, for measuring on a phone.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    this.diagnostics,
    this.errors,
    this.memory = readProcessMemory,
  });

  /// The app's figures ([appDiagnostics]) when null.
  final AppDiagnostics? diagnostics;

  /// The app's errors ([appErrors]) when null.
  final AppErrors? errors;

  /// Replaced in widget tests.
  final MemoryReading Function() memory;

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  late MemoryReading _memory = widget.memory();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Memory and steps finishing in the background, while the page is open.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _refresh() => setState(() => _memory = widget.memory());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final diagnostics = widget.diagnostics ?? appDiagnostics;
    final last = diagnostics.lastImport;
    final errors = widget.errors ?? appErrors;
    final records = errors.records;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    // The label and the value share the row; with large text the value
    // wraps under its own half instead of crushing the label.
    Widget row(String label, String value, {Key? key}) => MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: LabelValueRow(
            label: Text(label),
            value: Text(
              value,
              key: key,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.diagnosticsTitle),
        actions: [
          IconButton(
            key: const ValueKey('refreshDiagnostics'),
            tooltip: l10n.diagnosticsRefresh,
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      // At most 720 wide, centred, so a value stays near its label.
      body: LayoutBuilder(
        builder: (context, constraints) => ListView(
          key: const ValueKey('diagnostics'),
          padding: EdgeInsets.only(
            left: math.max(0, (constraints.maxWidth - 720) / 2),
            right: math.max(0, (constraints.maxWidth - 720) / 2),
            bottom: 16,
          ),
          children: [
            heading(l10n.diagnosticsLastImport),
            if (last == null)
              ListTile(title: Text(l10n.diagnosticsNoImport))
            else ...[
              for (final step in diagnostics.steps)
                row(
                  _stepName(l10n, step.name),
                  diagnosticDuration(step.duration),
                ),
              row(l10n.diagnosticsRecordingsRead, '${last.recordings}'),
              row(
                l10n.diagnosticsSessions,
                '${last.sessions}',
                key: const ValueKey('diagnosticsSessions'),
              ),
              row(
                l10n.diagnosticsSamples,
                '${last.samples}',
                key: const ValueKey('diagnosticsSamples'),
              ),
              row(l10n.diagnosticsChannelValues, '${last.channelSamples}'),
            ],
            heading(l10n.diagnosticsMemory),
            row(
              l10n.diagnosticsCurrentMemory,
              diagnosticMemory(l10n, _memory.current),
              key: const ValueKey('diagnosticsCurrentMemory'),
            ),
            row(
              l10n.diagnosticsPeakMemory,
              diagnosticMemory(l10n, _memory.peak),
              key: const ValueKey('diagnosticsPeakMemory'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.diagnosticsMemoryNote,
                style: theme.textTheme.bodySmall,
              ),
            ),
            heading(l10n.diagnosticsErrors),
            if (records.isEmpty)
              ListTile(
                key: const ValueKey('diagnosticsNoErrors'),
                title: Text(l10n.diagnosticsNoErrors),
              )
            else ...[
              for (final record in records.reversed)
                ListTile(
                  dense: true,
                  title: Text(
                    record.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    record.count > 1
                        ? '${displayDateTime(record.time)} · '
                              '${l10n.diagnosticsErrorCount(record.count)}'
                        : displayDateTime(record.time),
                  ),
                ),
              if (errors.dropped > 0)
                ListTile(
                  dense: true,
                  title: Text(l10n.diagnosticsErrorsDropped(errors.dropped)),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton(
                    key: const ValueKey('copyErrors'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                        ClipboardData(text: errors.report()),
                      );
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.diagnosticsErrorsCopied)),
                      );
                    },
                    child: Text(l10n.diagnosticsCopyErrors),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens the diagnostics page once the menu has closed.
void _openDiagnostics(BuildContext context) {
  final navigator = Navigator.of(context);
  // The menu pops its own route after the item's tap.
  scheduleMicrotask(
    () => navigator.push(
      MaterialPageRoute<void>(builder: (_) => const DiagnosticsPage()),
    ),
  );
}

/// The overflow-menu entry that opens the diagnostics page.
PopupMenuItem<T> diagnosticsMenuItem<T>(BuildContext context) =>
    PopupMenuItem<T>(
      key: const ValueKey('openDiagnostics'),
      // A full 48 dp touch target, whatever the theme's menu density.
      height: kMinInteractiveDimension,
      onTap: () => _openDiagnostics(context),
      child: Text(context.l10n.diagnosticsTitle),
    );

/// An overflow menu with "Check for updates" and the diagnostics entry, for
/// an app bar.
class DiagnosticsMenu extends StatelessWidget {
  const DiagnosticsMenu({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    key: const ValueKey('moreMenu'),
    tooltip: context.l10n.moreActions,
    itemBuilder: (_) => [
      PopupMenuItem<void>(
        key: const ValueKey('checkForUpdatesMenuItem'),
        height: kMinInteractiveDimension,
        onTap: () => showUpdateDialog(context),
        child: Text(context.l10n.settingsUpdateCheckNow),
      ),
      diagnosticsMenuItem(context),
    ],
  );
}
