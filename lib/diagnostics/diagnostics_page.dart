import 'dart:async';

import 'package:flutter/material.dart';

import 'app_diagnostics.dart';

/// "1.84 s", or "120 ms" below a second.
String diagnosticDuration(Duration duration) {
  final milliseconds = duration.inMicroseconds / 1000.0;
  return milliseconds < 1000
      ? '${milliseconds.round()} ms'
      : '${(milliseconds / 1000).toStringAsFixed(2)} s';
}

/// "123.4 MiB", or "Not available".
String diagnosticMemory(int? bytes) => bytes == null
    ? 'Not available'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';

/// How long the last import took step by step, how much it read, and the
/// memory the platform reports for the app, for measuring on a phone.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({
    super.key,
    this.diagnostics,
    this.memory = readProcessMemory,
  });

  /// The app's figures ([appDiagnostics]) when null.
  final AppDiagnostics? diagnostics;

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
    final diagnostics = widget.diagnostics ?? appDiagnostics;
    final last = diagnostics.lastImport;
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    Widget row(String label, String value, {Key? key}) => ListTile(
      key: key,
      dense: true,
      title: Text(label),
      trailing: Text(value, style: theme.textTheme.bodyLarge),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            key: const ValueKey('refreshDiagnostics'),
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: ListView(
        key: const ValueKey('diagnostics'),
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          heading('Last import'),
          if (last == null)
            const ListTile(
              title: Text('No day imported since the app started.'),
            )
          else ...[
            for (final step in diagnostics.steps)
              row(step.name, diagnosticDuration(step.duration)),
            row('Recordings read', '${last.recordings}'),
            row(
              'Sessions',
              '${last.sessions}',
              key: const ValueKey('diagnosticsSessions'),
            ),
            row(
              'Samples',
              '${last.samples}',
              key: const ValueKey('diagnosticsSamples'),
            ),
            row('Channel values', '${last.channelSamples}'),
          ],
          heading('Memory'),
          row(
            'Current',
            diagnosticMemory(_memory.current),
            key: const ValueKey('diagnosticsCurrentMemory'),
          ),
          row(
            'Peak',
            diagnosticMemory(_memory.peak),
            key: const ValueKey('diagnosticsPeakMemory'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Resident memory of the app as the system reports it; the peak is '
              'since the app started. Times are wall time on this device.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
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
      onTap: () => _openDiagnostics(context),
      child: const Text('Diagnostics'),
    );

/// An overflow menu with the diagnostics entry, for an app bar.
class DiagnosticsMenu extends StatelessWidget {
  const DiagnosticsMenu({super.key});

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
    key: const ValueKey('moreMenu'),
    tooltip: 'More',
    itemBuilder: (_) => [diagnosticsMenuItem(context)],
  );
}
