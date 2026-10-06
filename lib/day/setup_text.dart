import 'package:telemetry_core/telemetry_core.dart';

import '../format.dart';
import '../l10n.dart';

/// A setup number as entered: at most two decimals, trailing zeros trimmed
/// ("2.1", "30", "2.45"), with a decimal point in every language.
String setupNumberText(double value) {
  final text = fixed(value, setupDecimals);
  return text.contains('.') ? text.replaceFirst(RegExp(r'\.?0+$'), '') : text;
}

/// [unit] as the app writes it after a number.
String pressureUnitText(AppLocalizations l10n, PressureUnit unit) =>
    switch (unit) {
      PressureUnit.bar => l10n.pressureUnitBar,
      PressureUnit.psi => l10n.pressureUnitPsi,
    };

/// The short headings of [setupWheels]: "FL", "FR", "RL", "RR".
List<String> setupWheelHeadings(AppLocalizations l10n) => [
  l10n.setupWheelFl,
  l10n.setupWheelFr,
  l10n.setupWheelRl,
  l10n.setupWheelRr,
];

/// The spoken names of [setupWheels]: "front left" and so on.
List<String> setupWheelNames(AppLocalizations l10n) => [
  l10n.setupWheelFlName,
  l10n.setupWheelFrName,
  l10n.setupWheelRlName,
  l10n.setupWheelRrName,
];

/// [setup] on one line, in the unit it was entered in: "Cold 2.1 / 2.1 / 2 /
/// 2 bar · Hot 2.4 / — / 2.3 / 2.3 bar · Tyres Pirelli SC2 · Fuel 8.5 l". A
/// wheel without a pressure reads "—". Null when nothing is entered.
String? setupText(AppLocalizations l10n, RunSetup setup) {
  final unit = setup.pressureUnit;
  String pressures(WheelPressures wheels) => [
    for (final value in wheels.values)
      value == null ? '—' : setupNumberText(value),
  ].join(' / ');
  final tyre = setup.tyre.trim();
  final parts = [
    if (unit != null) ...[
      if (!setup.cold.isEmpty)
        l10n.setupCold(pressures(setup.cold), pressureUnitText(l10n, unit)),
      if (!setup.hot.isEmpty)
        l10n.setupHot(pressures(setup.hot), pressureUnitText(l10n, unit)),
    ],
    if (tyre.isNotEmpty) l10n.setupTyres(tyre),
    if (setup.fuelStartLitres case final fuel?)
      l10n.setupFuel(setupNumberText(fuel)),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// "Setup: …" for [setup], or null when nothing is entered.
String? setupLine(AppLocalizations l10n, RunSetup? setup) => switch (setup) {
  null => null,
  final setup => switch (setupText(l10n, setup)) {
    null => null,
    final text => l10n.sessionSetupLine(text),
  },
};
