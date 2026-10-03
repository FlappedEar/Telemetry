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

/// The app's settings: the speed unit label.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detected = detectedSpeedUnit;
    return AlertDialog(
      title: const Text('Settings'),
      content: ValueListenableBuilder(
        valueListenable: speedUnitSetting,
        builder: (context, setting, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Speed unit', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Only the label next to speeds changes. Values are always '
              'shown as recorded, never converted.',
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
              detected.isEmpty
                  ? 'Automatic: the unit the recordings declare (km/h in '
                        'RaceChrono files). No day open yet, or its '
                        'recordings do not say.'
                  : 'Automatic: $detected, from the open day\'s recordings.',
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
