import 'package:flutter/material.dart';

import 'units.dart';

/// The settings button for an app bar.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Settings',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const SettingsDialog(),
    ),
  );
}

/// The app's settings: the unit assumed for unlabelled speeds.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final declared = {
      for (final unit in declaredSpeedUnits)
        if (unit.isNotEmpty) unit,
    };
    final unlabelled = declaredSpeedUnits.where((unit) => unit.isEmpty).length;
    return AlertDialog(
      title: const Text('Settings'),
      content: ValueListenableBuilder(
        valueListenable: speedUnitSetting,
        builder: (context, setting, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Unit for unlabelled speeds',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Used only for recordings that do not say their speed unit. A '
              'unit a recording declares is always shown as declared. '
              'Values are never converted.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<SpeedUnitSetting>(
              key: const ValueKey('speedUnitSetting'),
              showSelectedIcon: false,
              segments: [
                for (final value in SpeedUnitSetting.values)
                  ButtonSegment(value: value, label: Text(value.label)),
              ],
              selected: {setting},
              onSelectionChanged: (choice) =>
                  speedUnitSetting.value = choice.first,
            ),
            const SizedBox(height: 8),
            Text(
              key: const ValueKey('speedUnitDetected'),
              declaredSpeedUnits.isEmpty
                  ? 'No day open yet.'
                  : [
                      if (declared.isNotEmpty)
                        'The open day\'s recordings declare '
                            '${declared.join(' and ')}.',
                      if (unlabelled > 0)
                        unlabelled == declaredSpeedUnits.length
                            ? 'Its recordings do not say their speed unit.'
                            : '$unlabelled of its recordings do not say '
                                  'their speed unit.',
                    ].join(' '),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
