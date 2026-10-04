import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import 'day_results_controller.dart';
import 'weather_text.dart';

/// Edits one session's name, conditions, setup changes and notes, as
/// FlappedEar Overlays stores them in the day's document (FET-52). The day
/// then has unsaved changes.
class SessionDetailsDialog extends StatefulWidget {
  const SessionDetailsDialog({
    super.key,
    required this.controller,
    required this.runId,
  });

  final DayResultsController controller;
  final String runId;

  @override
  State<SessionDetailsDialog> createState() => _SessionDetailsDialogState();
}

class _SessionDetailsDialogState extends State<SessionDetailsDialog> {
  late final RunMetadata _stored = widget.controller.runMetadata(widget.runId);
  TextEditingController? _name;
  late final _conditions = TextEditingController(text: _stored.conditions);
  late final _setup = TextEditingController(text: _stored.setupChanges);
  late final _notes = TextEditingController(text: _stored.notes);
  bool _invalid = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // "Session 2" reads "Sesja 2" in Polish; left as shown, it stays
    // "Session 2" in the file.
    _name ??= TextEditingController(text: context.l10n.session(_stored.name));
  }

  @override
  void dispose() {
    for (final controller in [_name, _conditions, _setup, _notes]) {
      controller?.dispose();
    }
    super.dispose();
  }

  void _save() {
    final typed = _name!.text;
    final name = typed == context.l10n.session(_stored.name)
        ? _stored.name
        : typed;
    final problem = widget.controller.updateRunMetadata(
      widget.runId,
      RunMetadata(
        name: name,
        notes: _notes.text,
        conditions: _conditions.text,
        setupChanges: _setup.text,
      ),
    );
    if (problem != null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 3,
  }) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: maxLines,
    keyboardType: TextInputType.multiline,
    textCapitalization: TextCapitalization.sentences,
    inputFormatters: [
      LengthLimitingTextInputFormatter(maximumDetailsTextCharacters),
    ],
    decoration: InputDecoration(labelText: label, hintText: hint),
    onChanged: (_) {
      if (_invalid) setState(() => _invalid = false);
    },
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final blank = _name!.text.trim().isEmpty;
    return AlertDialog(
      title: Text(l10n.sessionDetailsTitle(l10n.session(_stored.name))),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const ValueKey('sessionDetailsName'),
                controller: _name,
                maxLength: maximumDetailsNameCharacters,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.sessionDetailsName,
                  errorText: blank ? l10n.sessionDetailsNameRequired : null,
                ),
                onChanged: (_) => setState(() => _invalid = false),
              ),
              const SizedBox(height: 8),
              _field(
                _conditions,
                l10n.sessionDetailsConditions,
                hint: l10n.sessionDetailsConditionsHint,
              ),
              const SizedBox(height: 12),
              _field(
                _setup,
                l10n.sessionDetailsSetup,
                hint: l10n.sessionDetailsSetupHint,
                maxLines: 4,
              ),
              const SizedBox(height: 12),
              _field(_notes, l10n.sessionDetailsNotes, maxLines: 6),
              const SizedBox(height: 16),
              SessionWeatherSection(
                weather: widget.controller.weather,
                runId: widget.runId,
              ),
              const SizedBox(height: 12),
              // Any field can be refused (too long once counted as the file
              // stores it), so the message sits under all of them.
              if (_invalid) ...[
                Text(
                  l10n.detailsInvalid,
                  key: const ValueKey('sessionDetailsInvalid'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Text(l10n.sessionDetailsSaved, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('sessionDetailsSave'),
          onPressed: blank ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Renames the day: the name of its document, which Overlays shows too.
class RenameDayDialog extends StatefulWidget {
  const RenameDayDialog({super.key, required this.controller});

  final DayResultsController controller;

  @override
  State<RenameDayDialog> createState() => _RenameDayDialogState();
}

class _RenameDayDialogState extends State<RenameDayDialog> {
  late final _name = TextEditingController(text: widget.controller.name);
  bool _invalid = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    if (widget.controller.renameDay(_name.text) != null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blank = _name.text.trim().isEmpty;
    return AlertDialog(
      title: Text(l10n.renameDayTitle),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey('renameDayName'),
          controller: _name,
          autofocus: true,
          maxLength: maximumDetailsNameCharacters,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.renameDayName,
            errorText: blank
                ? l10n.renameDayRequired
                : _invalid
                ? l10n.detailsInvalid
                : null,
          ),
          onChanged: (_) => setState(() => _invalid = false),
          onSubmitted: blank ? null : (_) => _save(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('renameDaySave'),
          onPressed: blank ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
