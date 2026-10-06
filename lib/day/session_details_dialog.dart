import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../l10n.dart';
import 'day_results_controller.dart';
import 'setup_text.dart';
import 'weather_text.dart';

/// Edits one session's name, conditions, setup changes and notes, as
/// FlappedEar Overlays stores them in the day's document (FET-52), and its
/// structured setup, which only Telemetry shows (FET-188). The day then has
/// unsaved changes.
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
  late final _setupFields = _SetupFields(
    _stored.setup,
    defaultUnit: _previous?.setup.pressureUnit,
  );
  bool _invalid = false;

  // The details of the session recorded before this one, or null.
  late final RunMetadata? _previous = switch (previousRunInRecordingOrder(
    widget.controller.runs,
    widget.runId,
  )) {
    final id? => widget.controller.runMetadata(id),
    null => null,
  };

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
    _setupFields.dispose();
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
        // A setup of a newer version is passed back as it is: never
        // rewritten.
        setup: _stored.setup.readOnly ? _stored.setup : _setupFields.setup!,
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
    final setupValid = _stored.setup.readOnly || _setupFields.setup != null;
    final previousSetup = _previous?.setup;
    return AlertDialog(
      // On a phone the setup table gets the width.
      insetPadding: MediaQuery.sizeOf(context).width < 400
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      // The title scrolls with the fields, so with large text on a small
      // phone every field can still be reached above the buttons.
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  l10n.sessionDetailsTitle(l10n.session(_stored.name)),
                  style:
                      theme.dialogTheme.titleTextStyle ??
                      theme.textTheme.headlineSmall,
                ),
              ),
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
              const SizedBox(height: 16),
              _SessionSetupSection(
                fields: _setupFields,
                stored: _stored.setup,
                sameAs:
                    previousSetup == null ||
                        previousSetup.isEmpty ||
                        previousSetup.readOnly ||
                        _stored.setup.readOnly
                    ? null
                    : (
                        name: l10n.session(_previous!.name),
                        setup: previousSetup,
                      ),
                onChanged: () => setState(() => _invalid = false),
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
          onPressed: blank || !setupValid ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// The session recorded just before [runId] in [runs]: by recording time,
/// sessions without one after the dated ones in the order added, as
/// sessions are numbered. Null for the first, or when [runId] is not there.
String? previousRunInRecordingOrder(List<NamedRun> runs, String runId) {
  final order = List.generate(runs.length, (index) => index);
  final starts = [
    for (final named in runs) recordingTimestamp(named.run.telemetry),
  ];
  order.sort((left, right) {
    final a = starts[left], b = starts[right];
    if ((a == null) != (b == null)) return a == null ? 1 : -1;
    if (a != null && b != null && a != b) return a.compareTo(b);
    return left.compareTo(right);
  });
  final at = order.indexWhere((index) => runs[index].run.id == runId);
  return at <= 0 ? null : runs[order[at - 1]].run.id;
}

/// Turns a comma into a decimal point as it is typed, so every language
/// enters "2.1" (the owner's rule), drops spaces, and refuses anything but digits with at
/// most [setupDecimals] decimals, and [integerDigits] before the point.
class SetupNumberFormatter extends TextInputFormatter {
  SetupNumberFormatter({int integerDigits = 2})
    : _allowed = RegExp('^\\d{0,$integerDigits}(\\.\\d{0,$setupDecimals})?\$');

  final RegExp _allowed;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // A paste such as " 2, 1 " is 2.1: spaces go before the check.
    final text = newValue.text
        .replaceAll(',', '.')
        .replaceAll(RegExp(r'\s'), '');
    if (!_allowed.hasMatch(text)) return oldValue;
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// The text fields of a session's setup and the unit chosen.
class _SetupFields {
  _SetupFields(RunSetup stored, {PressureUnit? defaultUnit})
    : unit = stored.pressureUnit ?? defaultUnit ?? PressureUnit.bar,
      _storedUnit = stored.pressureUnit {
    fill(stored, keepUnit: stored.pressureUnit == null);
  }

  PressureUnit unit;

  // The unit as read: passed back while no pressure is entered, so a setup
  // whose details were not touched is left as it is stored.
  final PressureUnit? _storedUnit;
  final cold = [for (final _ in setupWheels) TextEditingController()];
  final hot = [for (final _ in setupWheels) TextEditingController()];
  final tyre = TextEditingController();
  final fuel = TextEditingController();

  List<TextEditingController> get _all => [...cold, ...hot, tyre, fuel];

  /// Whether any field holds something.
  bool get hasValues =>
      _all.any((controller) => controller.text.trim().isNotEmpty);

  /// Shows [setup] in the fields; its unit too, unless [keepUnit].
  void fill(RunSetup setup, {bool keepUnit = false}) {
    if (!keepUnit && setup.pressureUnit != null) unit = setup.pressureUnit!;
    String number(double? value) => value == null ? '' : setupNumberText(value);
    for (final (index, wheel) in setupWheels.indexed) {
      cold[index].text = number(setup.cold[wheel]);
      hot[index].text = number(setup.hot[wheel]);
    }
    tyre.text = setup.tyre;
    fuel.text = number(setup.fuelStartLitres);
  }

  /// Whether [controller]'s pressure cannot be stored in [unit].
  bool pressureInvalid(TextEditingController controller) {
    if (controller.text.trim().isEmpty) return false;
    final value = parseSetupNumber(controller.text);
    return value == null || !validSetupPressure(unit, value);
  }

  bool get fuelInvalid {
    if (fuel.text.trim().isEmpty) return false;
    final value = parseSetupNumber(fuel.text);
    return value == null || !validFuelLitres(value);
  }

  bool get pressuresInvalid => [...cold, ...hot].any(pressureInvalid);

  /// The setup the fields hold, or null while one of them cannot be
  /// stored. Without a pressure the unit is the one read, so an untouched
  /// setup is left as stored; an edited one then loses it
  /// ([applyRunSetup]).
  RunSetup? get setup {
    if (pressuresInvalid || fuelInvalid || !validTyre(tyre.text.trim())) {
      return null;
    }
    double? number(TextEditingController controller) =>
        controller.text.trim().isEmpty
        ? null
        : parseSetupNumber(controller.text);
    final coldValues = WheelPressures.of([for (final c in cold) number(c)]);
    final hotValues = WheelPressures.of([for (final c in hot) number(c)]);
    final pressures = !coldValues.isEmpty || !hotValues.isEmpty;
    return RunSetup(
      pressureUnit: pressures ? unit : _storedUnit,
      cold: coldValues,
      hot: hotValues,
      tyre: tyre.text.trim(),
      fuelStartLitres: number(fuel),
    );
  }

  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
  }
}

/// The setup part of the session details: the unit, a table of cold and
/// hot pressures per wheel, the tyre and the fuel at the start. A setup
/// stored by a newer version is shown, not edited.
class _SessionSetupSection extends StatefulWidget {
  const _SessionSetupSection({
    required this.fields,
    required this.stored,
    this.sameAs,
    required this.onChanged,
  });

  final _SetupFields fields;
  final RunSetup stored;

  /// The previous session's name and setup, offered to copy.
  final ({String name, RunSetup setup})? sameAs;
  final VoidCallback onChanged;

  @override
  State<_SessionSetupSection> createState() => __SessionSetupSectionState();
}

class __SessionSetupSectionState extends State<_SessionSetupSection> {
  _SetupFields get _fields => widget.fields;

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Widget _pressure(
    BuildContext context,
    TextEditingController controller,
    String key, {
    String? label,
  }) {
    final invalid = _fields.pressureInvalid(controller);
    final errorBorder = OutlineInputBorder(
      borderSide: BorderSide(
        color: Theme.of(context).colorScheme.error,
        width: 2,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: TextField(
        key: ValueKey(key),
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [SetupNumberFormatter()],
        style: _pressureStyle(context),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 2,
            vertical: 10,
          ),
          // The range is said once under the table; the field is marked
          // with the error colour, without an error line under it.
          border: const OutlineInputBorder(),
          enabledBorder: invalid ? errorBorder : null,
          focusedBorder: invalid ? errorBorder : null,
          hintText: '—',
          // Two fields a line: each says its wheel.
          labelText: label,
          floatingLabelBehavior: label == null
              ? null
              : FloatingLabelBehavior.always,
        ),
        onChanged: (_) => _changed(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final heading = Text(
      l10n.sessionSetupHeading,
      style: theme.textTheme.titleSmall,
    );
    if (widget.stored.readOnly) {
      return Column(
        key: const ValueKey('sessionSetupReadOnly'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 4),
          if (setupText(l10n, widget.stored) case final text?)
            Text(text, style: theme.textTheme.bodyMedium),
          Text(l10n.sessionSetupReadOnly, style: small),
        ],
      );
    }
    final unit = _fields.unit;
    final headings = setupWheelHeadings(l10n);
    final names = setupWheelNames(l10n);
    final rows = [
      ('cold', l10n.sessionSetupCold, _fields.cold),
      ('hot', l10n.sessionSetupHot, _fields.hot),
    ];
    Widget field(
      String key,
      String row,
      List<TextEditingController> controllers,
      int index, {
      bool labelled = false,
    }) => Semantics(
      label: l10n.sessionSetupPressureField(row, names[index]),
      child: _pressure(
        context,
        controllers[index],
        'sessionSetup $key ${setupWheels[index]}',
        label: labelled ? headings[index] : null,
      ),
    );
    Widget headingText(String text) => ExcludeSemantics(
      child: Text(text, style: small, textAlign: TextAlign.center),
    );
    final tyre = TextField(
      key: const ValueKey('sessionSetupTyre'),
      controller: _fields.tyre,
      textCapitalization: TextCapitalization.sentences,
      inputFormatters: [
        LengthLimitingTextInputFormatter(maximumTyreCharacters),
      ],
      decoration: InputDecoration(
        labelText: l10n.sessionSetupTyre,
        hintText: l10n.sessionSetupTyreHint,
      ),
      onChanged: (_) => _changed(),
    );
    final fuel = TextField(
      key: const ValueKey('sessionSetupFuel'),
      controller: _fields.fuel,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [SetupNumberFormatter(integerDigits: 3)],
      decoration: InputDecoration(
        labelText: l10n.sessionSetupFuel,
        errorText: _fields.fuelInvalid ? l10n.sessionSetupFuelRange : null,
        errorMaxLines: 3,
      ),
      onChanged: (_) => _changed(),
    );
    // How wide a pressure field must be to show "28.25" in the font and
    // text size in use, with its padding and outline.
    final digits = TextPainter(
      text: TextSpan(text: '28.25', style: _pressureStyle(context)),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final fieldWidth = digits.width + 16;
    // And how wide the row labels beside the table are.
    var labelWidth = 0.0;
    for (final label in [l10n.sessionSetupCold, l10n.sessionSetupHot]) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: small),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      labelWidth = math.max(labelWidth, painter.width + 8);
      painter.dispose();
    }
    digits.dispose();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // A table with the row labels beside it where everything fits; the
        // labels above four fields a row on a phone; on a narrow phone or
        // with large text two fields a line, or one, each with its wheel.
        final layout = width >= labelWidth + 4 * fieldWidth
            ? _PressureLayout.table
            : width >= 4 * fieldWidth
            ? _PressureLayout.rows
            : width >= 2 * fieldWidth
            ? _PressureLayout.grid
            : _PressureLayout.list;
        final narrow = layout != _PressureLayout.table;
        return Column(
          key: const ValueKey('sessionSetup'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            heading,
            if (widget.sameAs case final sameAs?)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('sessionSetupSameAs'),
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: Text(l10n.sessionSetupSameAs(sameAs.name)),
                  onPressed: () => _copy(sameAs),
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  l10n.sessionSetupPressures,
                  style: theme.textTheme.bodyMedium,
                ),
                SegmentedButton<PressureUnit>(
                  key: const ValueKey('sessionSetupUnit'),
                  showSelectedIcon: false,
                  segments: [
                    for (final value in PressureUnit.values)
                      ButtonSegment(
                        value: value,
                        label: Text(pressureUnitText(l10n, value)),
                      ),
                  ],
                  selected: {unit},
                  // Never converted: the numbers stay and are checked again.
                  onSelectionChanged: (selection) {
                    _fields.unit = selection.single;
                    _changed();
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            switch (layout) {
              _PressureLayout.table => Table(
                columnWidths: const {0: IntrinsicColumnWidth()},
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  TableRow(
                    children: [
                      const SizedBox(),
                      for (final text in headings) headingText(text),
                    ],
                  ),
                  for (final (key, label, controllers) in rows)
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 8),
                          child: ExcludeSemantics(
                            child: Text(label, style: small),
                          ),
                        ),
                        for (final index in [0, 1, 2, 3])
                          field(key, label, controllers, index),
                      ],
                    ),
                ],
              ),
              _PressureLayout.rows => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      for (final text in headings)
                        Expanded(child: headingText(text)),
                    ],
                  ),
                  for (final (key, label, controllers) in rows) ...[
                    ExcludeSemantics(child: Text(label, style: small)),
                    Row(
                      children: [
                        for (final index in [0, 1, 2, 3])
                          Expanded(
                            child: field(key, label, controllers, index),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
              _PressureLayout.list => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (key, label, controllers) in rows) ...[
                    ExcludeSemantics(child: Text(label, style: small)),
                    for (final index in [0, 1, 2, 3])
                      field(key, label, controllers, index, labelled: true),
                  ],
                ],
              ),
              _PressureLayout.grid => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (key, label, controllers) in rows) ...[
                    ExcludeSemantics(child: Text(label, style: small)),
                    for (final pair in [
                      [0, 1],
                      [2, 3],
                    ])
                      Row(
                        children: [
                          for (final index in pair)
                            Expanded(
                              child: field(
                                key,
                                label,
                                controllers,
                                index,
                                labelled: true,
                              ),
                            ),
                        ],
                      ),
                  ],
                ],
              ),
            },
            if (_fields.pressuresInvalid)
              Text(
                l10n.sessionSetupPressureRange(
                  pressureUnitText(l10n, unit),
                  setupNumberText(unit.minimum),
                  setupNumberText(unit.maximum),
                ),
                key: const ValueKey('sessionSetupPressureError'),
                style: small?.copyWith(color: theme.colorScheme.error),
              ),
            Text(l10n.sessionSetupKeptAsEntered, style: small),
            const SizedBox(height: 4),
            if (narrow) ...[
              tyre,
              fuel,
            ] else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: tyre),
                  const SizedBox(width: 12),
                  SizedBox(width: 190, child: fuel),
                ],
              ),
          ],
        );
      },
    );
  }

  /// Fills the fields from the previous session; when some already hold a
  /// value, only after the driver agrees. Nothing is saved until Save.
  Future<void> _copy(({String name, RunSetup setup}) sameAs) async {
    if (_fields.hasValues) {
      final l10n = context.l10n;
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(l10n.sessionSetupReplaceTitle),
          content: Text(l10n.sessionSetupReplaceBody(sameAs.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              key: const ValueKey('sessionSetupReplace'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.sessionSetupReplace),
            ),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    _fields.fill(sameAs.setup);
    _changed();
  }
}

/// How the pressure fields are laid out for the width and text size.
enum _PressureLayout { table, rows, grid, list }

TextStyle? _pressureStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14);

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
