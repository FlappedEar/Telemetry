import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:telemetry_core/telemetry_core.dart';

import '../units.dart';
import '../update/app_update.dart';

/// The circuit list the app ships with.
const bundledCircuitList = 'assets/circuits/circuits.json';

/// Where a newer circuit list is published: the same file on `main`.
final circuitListUrl = Uri.https(
  'raw.githubusercontent.com',
  '/$updateRepository/main/$bundledCircuitList',
);

/// The most characters read from a fetched circuit list.
const maximumCircuitListCharacters = 4 * 1024 * 1024;

/// The radius of a circuit the driver adds, in metres.
const ownCircuitRadiusMeters = 1500.0;

/// The outcome of [CircuitDirectory.refresh]. [notSaved]: a newer list was
/// fetched and is in use now, but could not be kept on this device.
enum CircuitRefresh { updated, upToDate, failed, notSaved }

/// The outcome of naming or forgetting a circuit. [invalid]: the name cannot
/// be a circuit's name, nothing changed. [notSaved]: the change is in use
/// until the app closes, but could not be kept on this device.
enum CircuitSave { saved, invalid, notSaved }

/// The circuits the app knows: the newest of the shipped and the fetched
/// list, and the driver's own circuits, kept in the app's support folder.
/// Puts a name on a route from where it starts ([find]).
class CircuitDirectory extends ChangeNotifier {
  CircuitDirectory({
    Future<String> Function()? bundled,
    Future<Directory?> Function()? folder,
    Future<String> Function(Uri uri, int maximumCharacters)? fetch,
  }) : _bundled = bundled ?? (() => rootBundle.loadString(bundledCircuitList)),
       _folder = folder ?? _supportFolder,
       _fetch = fetch ?? fetchUpdateText;

  final Future<String> Function() _bundled;
  final Future<Directory?> Function() _folder;
  final Future<String> Function(Uri uri, int maximumCharacters) _fetch;

  CircuitList _list = CircuitList.empty;
  List<Circuit> _mine = const [];
  Future<void>? _loading;
  Future<CircuitRefresh>? _refreshing;

  /// The list in use: the shipped one, or a newer fetched one.
  CircuitList get list => _list;

  /// The driver's own circuits, including new names for listed ones.
  List<Circuit> get mine => _mine;

  /// Whether a [refresh] is running.
  bool get refreshing => _refreshing != null;

  // Null: nothing is kept on disk here (web, widget tests). A folder that
  // cannot be found throws, so that a save reports it.
  static Future<Directory?> _supportFolder() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
    return Directory(
      p.join((await getApplicationSupportDirectory()).path, 'circuits'),
    );
  }

  // Reading never fails the caller: without a folder there is nothing to read.
  Future<Directory?> _readableFolder() async {
    try {
      return await _folder();
    } on Object catch (error) {
      debugPrint('Circuits folder not found: $error');
      return null;
    }
  }

  /// The circuit a route starting [at] is on; null when none is near or
  /// [at] is null.
  Circuit? find(GeoCoordinate? at) =>
      at == null ? null : findCircuit(at, _list.circuits, mine: _mine);

  /// Reads the shipped list, a fetched one and the driver's circuits; once.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    var list = CircuitList.empty;
    try {
      list = decodeCircuitList(await _bundled());
    } on Object catch (error) {
      debugPrint('Shipped circuit list not read: $error');
    }
    final folder = await _readableFolder();
    if (folder != null) {
      final fetched = await _read(File(p.join(folder.path, 'list.json')));
      if (fetched != null) {
        try {
          final newer = decodeCircuitList(fetched);
          if (newer.revision > list.revision) list = newer;
        } on FormatException catch (error) {
          debugPrint('Fetched circuit list not read: $error');
        }
      }
      final ownFile = File(p.join(folder.path, 'mine.json'));
      final own = await _read(ownFile);
      if (own != null) {
        try {
          _mine = List.unmodifiable(decodeUserCircuits(own));
        } on FormatException catch (error) {
          // Kept aside, never overwritten: a damaged file, or one from a
          // newer version of the app, still holds the driver's names.
          debugPrint('Own circuits not read: $error');
          try {
            await ownFile.rename(
              p.join(
                folder.path,
                'mine.unreadable-${DateTime.now().millisecondsSinceEpoch}.json',
              ),
            );
          } on Object catch (error) {
            debugPrint('Own circuits not kept aside: $error');
          }
        }
      }
    }
    _list = list;
    notifyListeners();
  }

  static Future<String?> _read(File file) async {
    try {
      if (!await file.exists() ||
          await file.length() > maximumCircuitListCharacters * 4) {
        return null;
      }
      return await file.readAsString();
    } on Object {
      return null;
    }
  }

  /// Fetches the published list and keeps it when its revision is newer.
  Future<CircuitRefresh> refresh() {
    final running = _refreshing;
    if (running != null) return running;
    final started = _refreshing = _refresh().whenComplete(() {
      _refreshing = null;
      notifyListeners();
    });
    notifyListeners();
    return started;
  }

  Future<CircuitRefresh> _refresh() async {
    await load();
    final String text;
    final CircuitList fetched;
    try {
      text = await _fetch(circuitListUrl, maximumCircuitListCharacters);
      fetched = decodeCircuitList(text);
    } on Object catch (error) {
      debugPrint('Circuit list not fetched: $error');
      return CircuitRefresh.failed;
    }
    if (fetched.revision <= _list.revision) return CircuitRefresh.upToDate;
    _list = fetched;
    try {
      final folder = await _folder();
      if (folder != null &&
          !await _write(File(p.join(folder.path, 'list.json')), text)) {
        return CircuitRefresh.notSaved;
      }
    } on Object catch (error) {
      debugPrint('Circuit list not saved: $error');
      return CircuitRefresh.notSaved;
    }
    return CircuitRefresh.updated;
  }

  /// Names the circuit a route starting [at] is on [name]: a new name for
  /// the circuit found there, or a new circuit of the driver's. Invalid when
  /// [name] cannot be a circuit's name; [CircuitSave.notSaved] when the name
  /// is in use but could not be kept on this device.
  Future<CircuitSave> nameAt(
    GeoCoordinate at,
    String name, {
    Random? random,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maximumCircuitNameCharacters ||
        trimmed.contains('\u0000') ||
        !isValidCoordinate(at)) {
      return CircuitSave.invalid;
    }
    await load();
    final found = find(at);
    final circuit = found == null
        ? Circuit(
            id: 'my:${newEventId(random)}',
            name: trimmed,
            centre: at,
            radiusMeters: ownCircuitRadiusMeters,
          )
        : found.copyWith(name: trimmed);
    _mine = List.unmodifiable([
      for (final own in _mine)
        if (own.id != circuit.id) own,
      circuit,
    ]);
    notifyListeners();
    return await _saveMine() ? CircuitSave.saved : CircuitSave.notSaved;
  }

  /// Forgets the driver's circuit [id]: a listed circuit gets its listed
  /// name back. [CircuitSave.notSaved] when the change could not be kept on
  /// this device.
  Future<CircuitSave> remove(String id) async {
    if (!_mine.any((circuit) => circuit.id == id)) return CircuitSave.saved;
    _mine = List.unmodifiable([
      for (final own in _mine)
        if (own.id != id) own,
    ]);
    notifyListeners();
    return await _saveMine() ? CircuitSave.saved : CircuitSave.notSaved;
  }

  /// The listed circuit [id] names, or null.
  Circuit? listed(String id) {
    for (final circuit in _list.circuits) {
      if (circuit.id == id) return circuit;
    }
    return null;
  }

  // One write at a time, each of the circuits as they are when it runs.
  // Null while none runs. Each completes with whether its file was written.
  Future<bool>? _saving;

  Future<bool> _saveMine() {
    final previous = _saving;
    final next = previous == null
        ? _writeMine()
        : previous.then((_) => _writeMine());
    _saving = next;
    next.whenComplete(() {
      if (identical(_saving, next)) _saving = null;
    });
    return next;
  }

  Future<bool> _writeMine() async {
    try {
      final folder = await _folder();
      if (folder == null) return true;
      return await _write(
        File(p.join(folder.path, 'mine.json')),
        encodeUserCircuits(_mine),
      );
    } on Object catch (error) {
      debugPrint('Circuits not saved: $error');
      return false;
    }
  }

  // Into a temporary file moved over [file]: a write cut short never leaves
  // half a file. False when it could not be written.
  static Future<bool> _write(File file, String text) async {
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(text, flush: true);
      await temporary.rename(file.path);
      return true;
    } on Object catch (error) {
      debugPrint('Circuits not saved: $error');
      return false;
    }
  }
}

/// The app's circuits, shared by every page.
CircuitDirectory circuitDirectory = CircuitDirectory();

/// Reads the circuits, then fetches the published list at most once a day
/// while [updateCheckSetting] is on. Failures stay quiet: the list in use
/// stays.
Future<void> refreshCircuitsOnLaunch({DateTime? now}) async {
  final directory = circuitDirectory;
  await directory.load();
  final time = now ?? DateTime.now();
  if (!updateCheckSetting.value ||
      !updateCheckDue(lastCircuitCheck.value, time)) {
    return;
  }
  // A list that could not be kept is fetched again at the next launch.
  final outcome = await directory.refresh();
  if (outcome == CircuitRefresh.updated || outcome == CircuitRefresh.upToDate) {
    lastCircuitCheck.value = time;
  }
}
