// A session's structured setup (FET-188): tyre pressures cold and hot for
// each wheel in the unit the driver entered, the tyre and the fuel at the
// start. Telemetry stores it as an open object `setup` on the run
// (`event.runs[]`), which FlappedEar Overlays keeps as it is without showing
// it. Numbers are kept as entered and never converted between units.
import 'package:fetproject/fetproject.dart' as fet;

/// The version of a session's stored setup.
const runSetupVersion = 'session-setup-v1';

/// The run key the setup is stored under.
const runSetupKey = 'setup';

/// The wheels' keys in a stored pressure object, in display order: front
/// left, front right, rear left, rear right.
const setupWheels = ['fl', 'fr', 'rl', 'rr'];

/// The longest tyre name, in UTF-16 code units.
const maximumTyreCharacters = fet.maximumNameCharacters;

/// The most fuel at the start, in litres.
const maximumFuelLitres = 200.0;

/// The most decimals a setup number keeps.
const setupDecimals = 2;

/// The unit tyre pressures were entered in.
enum PressureUnit {
  bar(0.5, 6.0),
  psi(7, 90);

  const PressureUnit(this.minimum, this.maximum);

  /// The lowest and highest pressure accepted in this unit.
  final double minimum, maximum;

  /// The unit stored as [name] (`bar` or `psi`), or null.
  static PressureUnit? parse(Object? value) => switch (value) {
    'bar' => bar,
    'psi' => psi,
    _ => null,
  };
}

final _setupNumber = RegExp(r'^\d{0,3}(\.\d{0,2})?$');

/// [text] as a setup number, or null when it is not one: digits with at most
/// [setupDecimals] decimals after a decimal point. A comma is not a decimal
/// point here; the app turns it into one as it is typed.
double? parseSetupNumber(String text) {
  final trimmed = text.trim();
  if (!_setupNumber.hasMatch(trimmed) || !trimmed.contains(RegExp(r'\d'))) return null;
  return double.parse(trimmed.startsWith('.') ? '0$trimmed' : trimmed);
}

bool _hasSetupDecimals(double value) {
  final scaled = value * 100;
  return (scaled - scaled.roundToDouble()).abs() < 1e-6;
}

/// Whether [value] is a pressure [unit] accepts: within its range, with at
/// most [setupDecimals] decimals.
bool validSetupPressure(PressureUnit unit, double value) =>
    value.isFinite && value >= unit.minimum && value <= unit.maximum && _hasSetupDecimals(value);

/// Whether [litres] is a fuel amount at the start that can be stored: 0 to
/// [maximumFuelLitres], with at most [setupDecimals] decimals.
bool validFuelLitres(double litres) =>
    litres.isFinite && litres >= 0 && litres <= maximumFuelLitres && _hasSetupDecimals(litres);

/// Whether [tyre] can be stored: at most [maximumTyreCharacters] and no NUL.
bool validTyre(String tyre) => tyre.length <= maximumTyreCharacters && !tyre.contains('\u0000');

/// One pressure per wheel; null is not entered.
final class WheelPressures {
  const WheelPressures({this.fl, this.fr, this.rl, this.rr});

  /// [values] in [setupWheels] order.
  factory WheelPressures.of(List<double?> values) =>
      WheelPressures(fl: values[0], fr: values[1], rl: values[2], rr: values[3]);

  final double? fl, fr, rl, rr;

  /// The pressures in [setupWheels] order.
  List<double?> get values => [fl, fr, rl, rr];

  bool get isEmpty => values.every((value) => value == null);

  double? operator [](String wheel) => values[setupWheels.indexOf(wheel)];

  @override
  bool operator ==(Object other) =>
      other is WheelPressures &&
      other.fl == fl &&
      other.fr == fr &&
      other.rl == rl &&
      other.rr == rr;

  @override
  int get hashCode => Object.hash(fl, fr, rl, rr);
}

/// A session's setup as the driver entered it. Every field is optional.
final class RunSetup {
  const RunSetup({
    this.pressureUnit,
    this.cold = const WheelPressures(),
    this.hot = const WheelPressures(),
    this.tyre = '',
    this.fuelStartLitres,
    this.unknownVersion,
  });

  /// The setup a run stores ([runSetupKey]), read leniently: a value that
  /// is missing, of the wrong type or out of range reads as not entered, and
  /// pressures without a unit are not entered either. A setup stored under
  /// another version than [runSetupVersion] reads what it can and is
  /// [readOnly].
  factory RunSetup.fromJson(Object? value) {
    if (value is! Map<String, Object?>) return const RunSetup();
    final version = value['version'];
    final unit = PressureUnit.parse(value['pressureUnit']);
    WheelPressures pressures(Object? stored) {
      if (unit == null || stored is! Map<String, Object?>) return const WheelPressures();
      return WheelPressures.of([
        for (final wheel in setupWheels)
          if (stored[wheel] case final num pressure
              when validSetupPressure(unit, pressure.toDouble()))
            pressure.toDouble()
          else
            null,
      ]);
    }

    final tyre = value['tyre'];
    final fuel = value['fuelStartLitres'];
    return RunSetup(
      pressureUnit: unit,
      cold: pressures(value['coldPressure']),
      hot: pressures(value['hotPressure']),
      tyre: tyre is String && validTyre(tyre) ? tyre : '',
      fuelStartLitres: fuel is num && validFuelLitres(fuel.toDouble()) ? fuel.toDouble() : null,
      unknownVersion: version == null || version == runSetupVersion ? null : '$version',
    );
  }

  final PressureUnit? pressureUnit;
  final WheelPressures cold, hot;

  /// The tyre's name or compound; empty is not entered.
  final String tyre;

  final double? fuelStartLitres;

  /// The stored version when it is not [runSetupVersion], or null.
  final String? unknownVersion;

  /// Stored under a version this app does not read: shown, never rewritten.
  bool get readOnly => unknownVersion != null;

  /// Whether any pressure is entered.
  bool get hasPressures => !cold.isEmpty || !hot.isEmpty;

  /// Whether nothing is entered.
  bool get isEmpty =>
      pressureUnit == null && !hasPressures && tyre.trim().isEmpty && fuelStartLitres == null;

  /// This setup as it is stored when nothing was stored before.
  Map<String, Object?> toJson() {
    final run = <String, Object?>{};
    if (readOnly) {
      run[runSetupKey] = {'version': unknownVersion};
      _write(run, this, const RunSetup());
      return run[runSetupKey]! as Map<String, Object?>;
    }
    applyRunSetup(run, this);
    return (run[runSetupKey] as Map<String, Object?>?) ?? {'version': runSetupVersion};
  }

  RunSetup _trimmed() => tyre == tyre.trim()
      ? this
      : RunSetup(
          pressureUnit: pressureUnit,
          cold: cold,
          hot: hot,
          tyre: tyre.trim(),
          fuelStartLitres: fuelStartLitres,
          unknownVersion: unknownVersion,
        );

  @override
  bool operator ==(Object other) =>
      other is RunSetup &&
      other.pressureUnit == pressureUnit &&
      other.cold == cold &&
      other.hot == hot &&
      other.tyre == tyre &&
      other.fuelStartLitres == fuelStartLitres &&
      other.unknownVersion == unknownVersion;

  @override
  int get hashCode => Object.hash(pressureUnit, cold, hot, tyre, fuelStartLitres, unknownVersion);
}

/// Why [setup] cannot be saved, or null when it can: a pressure needs a
/// unit and is within its range (bar 0.5–6.0, psi 7–90), the fuel is 0–200
/// litres, both with at most two decimals; the tyre is at most 160
/// characters without NUL. A [RunSetup.readOnly] setup is never written, so
/// it has no problem.
String? runSetupProblem(RunSetup setup) {
  if (setup.readOnly) return null;
  final unit = setup.pressureUnit;
  if (setup.hasPressures) {
    if (unit == null) return 'Tyre pressures need a unit.';
    for (final pressure in [...setup.cold.values, ...setup.hot.values]) {
      if (pressure != null && !validSetupPressure(unit, pressure)) {
        return 'A tyre pressure is outside ${_number(unit.minimum)}–${_number(unit.maximum)} '
            '${unit.name} or has more than $setupDecimals decimals.';
      }
    }
  }
  if (setup.fuelStartLitres case final fuel? when !validFuelLitres(fuel)) {
    return 'The fuel at the start is outside 0–${_number(maximumFuelLitres)} litres '
        'or has more than $setupDecimals decimals.';
  }
  if (setup.tyre.trim().length > maximumTyreCharacters) {
    return 'The tyre is longer than $maximumTyreCharacters characters.';
  }
  if (setup.tyre.contains('\u0000')) return 'The tyre contains a NUL character.';
  return null;
}

String _number(double value) => value == value.roundToDouble() ? '${value.round()}' : '$value';

/// Writes [setup] into [run] (a document run) as its [runSetupKey]: only
/// what changed against what is stored is written, so keys this app does
/// not know (in the setup and in its pressure objects) and stored values it
/// reads as not entered stay as they are, and a setup equal to the stored
/// one leaves [run] as it was. A setup stored under another version is
/// never rewritten. A setup left with nothing in it is removed. Returns
/// whether [run] changed. [setup] must have no [runSetupProblem].
bool applyRunSetup(Map<String, Object?> run, RunSetup setup) {
  final storedSetup = RunSetup.fromJson(run[runSetupKey]);
  final next = setup._trimmed();
  if (storedSetup.readOnly || next.readOnly || storedSetup == next) return false;
  _write(run, next, storedSetup);
  final object = run[runSetupKey]! as Map<String, Object?>;
  if (object.keys.every((key) => key == 'version')) run.remove(runSetupKey);
  return true;
}

void _write(Map<String, Object?> run, RunSetup next, RunSetup stored) {
  final current = run[runSetupKey];
  final object = <String, Object?>{
    if (current is Map<String, Object?>) ...current,
    if (!next.readOnly) 'version': runSetupVersion,
  };
  void set(String key, Object? value, Object? before) {
    if (value == before) return;
    if (value == null) {
      object.remove(key);
    } else {
      object[key] = value;
    }
  }

  set('pressureUnit', next.pressureUnit?.name, stored.pressureUnit?.name);
  for (final (key, pressures, storedPressures) in [
    ('coldPressure', next.cold, stored.cold),
    ('hotPressure', next.hot, stored.hot),
  ]) {
    if (pressures == storedPressures) continue;
    final wheels = <String, Object?>{if (object[key] case final Map<String, Object?> kept) ...kept};
    for (final wheel in setupWheels) {
      final value = pressures[wheel];
      if (value == storedPressures[wheel]) continue;
      if (value == null) {
        wheels.remove(wheel);
      } else {
        wheels[wheel] = value;
      }
    }
    if (wheels.isEmpty) {
      object.remove(key);
    } else {
      object[key] = wheels;
    }
  }
  set('tyre', next.tyre.isEmpty ? null : next.tyre, stored.tyre.isEmpty ? null : stored.tyre);
  set('fuelStartLitres', next.fuelStartLitres, stored.fuelStartLitres);
  run[runSetupKey] = object;
}
