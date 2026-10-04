import 'package:flutter/material.dart';

import 'l10n.dart';
import 'units.dart';

/// The settings button for an app bar.
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.l10n.settings,
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (_) => const SettingsDialog(),
    ),
  );
}

/// The app's settings: the unit assumed for unlabelled speeds, whether
/// sessions' weather is looked up, and the licences of the app and the
/// software it uses.
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final declared = {
      for (final unit in declaredSpeedUnits)
        if (unit.isNotEmpty) unit,
    };
    final unlabelled = declaredSpeedUnits.where((unit) => unit.isEmpty).length;
    return AlertDialog(
      title: Text(l10n.settings),
      // A readable line length on a desktop.
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ValueListenableBuilder(
          valueListenable: speedUnitSetting,
          builder: (context, setting, _) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.settingsSpeedUnitHeading,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.settingsSpeedUnitHelp,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<SpeedUnitSetting>(
                  key: const ValueKey('speedUnitSetting'),
                  showSelectedIcon: false,
                  segments: [
                    for (final value in SpeedUnitSetting.values)
                      ButtonSegment(
                        value: value,
                        label: Text(
                          value == SpeedUnitSetting.automatic
                              ? l10n.speedUnitNone
                              : value.label,
                        ),
                      ),
                  ],
                  selected: {setting},
                  onSelectionChanged: (choice) =>
                      speedUnitSetting.value = choice.first,
                ),
                const SizedBox(height: 8),
                Text(
                  key: const ValueKey('speedUnitDetected'),
                  declaredSpeedUnits.isEmpty
                      ? l10n.settingsNoDayOpen
                      : [
                          if (declared.isNotEmpty)
                            l10n.settingsDeclaredUnits(
                              declared.join(l10n.unitsAnd),
                            ),
                          if (unlabelled > 0)
                            unlabelled == declaredSpeedUnits.length
                                ? l10n.settingsAllUnlabelled
                                : l10n.settingsSomeUnlabelled(unlabelled),
                        ].join(' '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.settingsWeatherHeading,
                  style: theme.textTheme.titleSmall,
                ),
                ValueListenableBuilder(
                  valueListenable: weatherLookupSetting,
                  builder: (context, on, _) => SwitchListTile(
                    key: const ValueKey('weatherLookupSetting'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.settingsWeatherSwitch),
                    value: on,
                    onChanged: (value) => weatherLookupSetting.value = value,
                  ),
                ),
                Text(
                  l10n.settingsWeatherHelp,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Text(
                  context.l10n.settingsAbout,
                  style: theme.textTheme.titleSmall,
                ),
                TextButton(
                  key: const ValueKey('openLicences'),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: context.l10n.appTitle,
                    applicationLegalese: context.l10n.licencesLegalese,
                  ),
                  child: Text(context.l10n.settingsLicences),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
