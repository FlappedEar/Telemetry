import 'package:flutter/material.dart';

import 'channel_names.dart';
import 'circuits/circuit_directory.dart';
import 'l10n.dart';
import 'ui/theme.dart';
import 'day/day_context.dart';
import 'units.dart';
import 'update/update_dialog.dart';

/// The Updates section of settings: the app's version, "Check for updates"
/// and the switch for the check on launch.
class UpdateSettings extends StatefulWidget {
  const UpdateSettings({super.key});

  @override
  State<UpdateSettings> createState() => _UpdateSettingsState();
}

class _UpdateSettingsState extends State<UpdateSettings> {
  @override
  void initState() {
    super.initState();
    // Once per opening of settings, not on every rebuild.
    if (appUpdater.installedLabel == null) appUpdater.readInstalledLabel();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final updater = appUpdater;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.settingsUpdatesHeading, style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: updater,
          builder: (context, _) => Text(
            l10n.updateInstalledVersion(
              updater.installedLabel ?? l10n.updateVersionUnknown,
            ),
            key: const ValueKey('settingsAppVersion'),
            style: theme.textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('checkForUpdates'),
          icon: const Icon(Icons.system_update_outlined),
          onPressed: () => showUpdateDialog(context),
          label: Text(l10n.settingsUpdateCheckNow),
        ),
        ValueListenableBuilder(
          valueListenable: updateCheckSetting,
          builder: (context, on, _) => SwitchListTile(
            key: const ValueKey('updateCheckSetting'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsUpdateSwitch),
            value: on,
            onChanged: (value) => updateCheckSetting.value = value,
          ),
        ),
        Text(l10n.settingsUpdateHelp, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

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

/// The app's settings: the app's version and updates (first, FET-195), the
/// unit assumed for unlabelled speeds, the look
/// (dark or sunlight) and whether the screen stays on at the coach, whether
/// sessions' weather is looked up, the names shown for recorded channels,
/// the circuit list and the driver's circuit names, and the licences of the app and the
/// software it uses.
class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final declaredSpeedUnits = openDayContext.speedUnits;
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
          // A scrollbar that is always shown, so a phone shows that the
          // settings go on below (FET-195).
          builder: (context, setting, _) => Scrollbar(
            key: const ValueKey('settingsScrollbar'),
            controller: _scroll,
            thumbVisibility: true,
            // Desktops add a scrollbar of their own; one is enough.
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(context)
                  .copyWith(scrollbars: false),
              child: SingleChildScrollView(
                controller: _scroll,
                // Room for the scrollbar beside the switches.
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // First, so it is found without scrolling (FET-195).
                    const UpdateSettings(),
                    const SizedBox(height: 16),
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
                      l10n.settingsLookHeading,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ValueListenableBuilder(
                      valueListenable: appLookSetting,
                      builder: (context, look, _) => SegmentedButton<AppLook>(
                        key: const ValueKey('appLookSetting'),
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(
                            value: AppLook.dark,
                            icon: const Icon(Icons.dark_mode_outlined),
                            label: Text(l10n.lookDark),
                          ),
                          ButtonSegment(
                            value: AppLook.sunlight,
                            icon: const Icon(Icons.wb_sunny_outlined),
                            label: Text(l10n.lookSunlight),
                          ),
                        ],
                        selected: {look},
                        onSelectionChanged: (choice) =>
                            appLookSetting.value = choice.first,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.settingsLookHelp,
                      style: theme.textTheme.bodySmall,
                    ),
                    ValueListenableBuilder(
                      valueListenable: keepScreenOnSetting,
                      builder: (context, on, _) => SwitchListTile(
                        key: const ValueKey('keepScreenOnSetting'),
                        contentPadding: EdgeInsets.zero,
                        title: Text(l10n.settingsKeepScreenOnSwitch),
                        value: on,
                        onChanged: (value) => keepScreenOnSetting.value = value,
                      ),
                    ),
                    Text(
                      l10n.settingsKeepScreenOnHelp,
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
                        onChanged: (value) =>
                            weatherLookupSetting.value = value,
                      ),
                    ),
                    Text(
                      l10n.settingsWeatherHelp,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.channelNamesTitle,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.settingsChannelNamesHelp,
                      style: theme.textTheme.bodySmall,
                    ),
                    TextButton(
                      key: const ValueKey('openChannelNames'),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChannelNamesPage(),
                        ),
                      ),
                      child: Text(l10n.settingsChannelNamesOpen),
                    ),
                    const SizedBox(height: 16),
                    const CircuitSettings(),
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

/// The circuit list's size, a button that updates it now, and the circuits
/// the driver named, each of which can be forgotten.
class CircuitSettings extends StatelessWidget {
  const CircuitSettings({super.key});

  Future<void> _update(BuildContext context) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final outcome = await circuitDirectory.refresh();
    if (outcome == CircuitRefresh.updated ||
        outcome == CircuitRefresh.upToDate) {
      lastCircuitCheck.value = DateTime.now();
    }
    messenger?.showSnackBar(
      SnackBar(
        content: Text(switch (outcome) {
          CircuitRefresh.updated => l10n.settingsCircuitsUpdated,
          CircuitRefresh.upToDate => l10n.settingsCircuitsUpToDate,
          CircuitRefresh.failed => l10n.settingsCircuitsFailed,
          CircuitRefresh.notSaved => l10n.settingsCircuitsNotSaved,
        }),
      ),
    );
  }

  Future<void> _forget(BuildContext context, String id) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (await circuitDirectory.remove(id) == CircuitSave.notSaved) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.settingsCircuitsForgetNotSaved)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final circuits = circuitDirectory;
    return ListenableBuilder(
      listenable: circuits,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingsCircuitsHeading, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            l10n.settingsCircuitsCount(circuits.list.circuits.length),
            key: const ValueKey('circuitCount'),
          ),
          Text(l10n.settingsCircuitsHelp, style: theme.textTheme.bodySmall),
          TextButton(
            key: const ValueKey('updateCircuits'),
            onPressed: circuits.refreshing ? null : () => _update(context),
            child: Text(l10n.settingsCircuitsUpdate),
          ),
          if (circuits.mine.isNotEmpty) ...[
            Text(l10n.settingsCircuitsMine, style: theme.textTheme.bodyMedium),
            for (final circuit in circuits.mine)
              ListTile(
                key: ValueKey('ownCircuit-${circuit.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(circuit.name),
                subtitle: Text(switch (circuits.listed(circuit.id)) {
                  final listed? => l10n.settingsCircuitsRenamed(listed.name),
                  null => l10n.settingsCircuitsAdded,
                }),
                trailing: IconButton(
                  tooltip: l10n.settingsCircuitsForget,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _forget(context, circuit.id),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
