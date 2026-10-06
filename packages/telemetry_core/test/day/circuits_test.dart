import 'dart:convert';
import 'dart:io';

import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/fusion_pair.dart';

// Synthetic circuits; no real recording.
String _list(List<Object?> circuits, {int revision = 1}) => jsonEncode({
  'format': circuitListFormat,
  'version': 1,
  'revision': revision,
  'source': 'test',
  'circuits': circuits,
});

GeoCoordinate _north(GeoCoordinate from, double metres) => unprojectCoordinate(0, metres, from);

void main() {
  const a = GeoCoordinate(50.0, 20.0);
  const b = GeoCoordinate(50.03, 20.0); // about 3.3 km north of a

  test('reads a list and leaves out what is not a circuit', () {
    final list = decodeCircuitList(
      _list([
        {'id': 'a', 'name': ' Alpha ', 'country': 'pl', 'lat': 50.0, 'lon': 20.0},
        {'id': 'b', 'name': 'Bravo', 'lat': 50.03, 'lon': 20.0, 'radius': 500},
        {'id': 'a', 'name': 'Duplicate id', 'lat': 1, 'lon': 1},
        {'id': 'c', 'name': '', 'lat': 1, 'lon': 1},
        {'id': 'd', 'name': 'Off the globe', 'lat': 91, 'lon': 1},
        {'id': 'e', 'name': 'No radius', 'lat': 1, 'lon': 1, 'radius': 0},
        {'id': 'f', 'name': 'Huge radius', 'lat': 1, 'lon': 1, 'radius': 1e9},
        {'id': 'g', 'name': 'Text position', 'lat': '1', 'lon': 1},
        'not an object',
      ], revision: 7),
    );
    expect(list.revision, 7);
    expect(list.circuits.map((c) => c.name), ['Alpha', 'Bravo']);
    expect(list.circuits.first.country, 'PL');
    expect(list.circuits.first.radiusMeters, defaultCircuitRadiusMeters);
    expect(list.circuits.last.radiusMeters, 500);
  });

  test('refuses what is not a circuit list this version reads', () {
    expect(() => decodeCircuitList('nope'), throwsFormatException);
    expect(() => decodeCircuitList('{"format":"other","version":1}'), throwsFormatException);
    expect(
      () => decodeCircuitList(
        jsonEncode({'format': circuitListFormat, 'version': 2, 'revision': 1, 'circuits': <Object?>[]}),
      ),
      throwsFormatException,
    );
    expect(
      () => decodeCircuitList(
        jsonEncode({'format': circuitListFormat, 'version': 1, 'circuits': <Object?>[]}),
      ),
      throwsFormatException,
    );
  });

  test('measures great-circle distances', () {
    expect(distanceMeters(a, a), 0);
    // One degree of latitude is 111.19 km on a 6371 km sphere.
    expect(distanceMeters(a, const GeoCoordinate(51.0, 20.0)), closeTo(111195, 1));
    expect(distanceMeters(a, _north(a, 1234)), closeTo(1234, 0.5));
  });

  test('finds the nearest circuit whose radius reaches the start', () {
    final listed = [
      Circuit(id: 'a', name: 'Alpha', centre: a),
      Circuit(id: 'b', name: 'Bravo', centre: b, radiusMeters: 3000),
    ];
    // Both reach these; the nearer centre wins (midway is 1668 m).
    expect(findCircuit(_north(a, 1600), listed)?.name, 'Alpha');
    expect(findCircuit(_north(a, 1800), listed)?.name, 'Bravo');
    expect(findCircuit(_north(b, -1500), listed)?.name, 'Bravo');
    // Out of every radius.
    expect(findCircuit(_north(a, -2100), listed), isNull);
    expect(findCircuit(const GeoCoordinate(double.nan, 0), listed), isNull);
  });

  test('the driver\'s circuits win, and rename a listed one by id', () {
    final listed = [Circuit(id: 'a', name: 'Alpha', centre: a)];
    final renamed = [Circuit(id: 'a', name: 'Home track', centre: a)];
    expect(findCircuit(_north(a, 100), listed, mine: renamed)?.name, 'Home track');
    // A newer list moves the circuit: the new name follows it.
    final moved = [Circuit(id: 'a', name: 'Alpha', centre: b)];
    expect(findCircuit(_north(b, 100), moved, mine: renamed)?.name, 'Home track');
    expect(findCircuit(_north(a, 100), moved, mine: renamed), isNull);
    final added = [
      Circuit(id: 'my:1', name: 'Kart track', centre: _north(a, 600), radiusMeters: 300),
    ];
    expect(findCircuit(_north(a, 650), listed, mine: added)?.name, 'Kart track');
    expect(findCircuit(_north(a, 100), listed, mine: added)?.name, 'Alpha');
  });

  test('keeps the driver\'s circuits through a file', () {
    final mine = [
      Circuit(id: 'a', name: 'Home track', centre: a, country: 'PL'),
      Circuit(id: 'my:1', name: 'Kart', centre: b, radiusMeters: 1500),
    ];
    final read = decodeUserCircuits(encodeUserCircuits(mine));
    expect(read.map((c) => (c.id, c.name, c.centre, c.country, c.radiusMeters)), [
      ('a', 'Home track', a, 'PL', defaultCircuitRadiusMeters),
      ('my:1', 'Kart', b, '', 1500.0),
    ]);
    expect(() => decodeUserCircuits(_list(const [])), throwsFormatException);
  });

  test('names the route of a west-positive RaceChrono VBO at its real place', () {
    // A synthetic RaceChrono VBO at 52° N, 21° E, its longitude written
    // west-positive (as RaceChrono writes it): the start must not land at
    // 21° W.
    final folder = Directory.systemTemp.createTempSync('circuits');
    addTearDown(() => folder.deleteSync(recursive: true));
    final (vbo, _) = writeFusionPair(folder.path);
    final session = parseVboFile(vbo);
    expect(session.metadata['gpsLongitudeConvention'], 'west-positive');
    final inference = inferTrack(deriveSourceLapSession(session), longitudeIsWestPositive: true);
    final start = inference.route!.origin;
    expect(start.longitudeDegrees, closeTo(21.0, 0.01));
    final listed = [
      Circuit(id: 'east', name: 'East', centre: const GeoCoordinate(52.0, 21.0)),
      Circuit(id: 'west', name: 'West', centre: const GeoCoordinate(52.0, -21.0)),
    ];
    expect(findCircuit(start, listed)?.name, 'East');
  });

  test('the shipped list is a list this version reads', () {
    final file = File('../../assets/circuits/circuits.json');
    final list = decodeCircuitList(file.readAsStringSync());
    expect(list.revision, greaterThan(0));
    expect(list.circuits.length, greaterThan(500));
    expect(list.source, contains('CC0'));
    // Every entry was read: none was left out as malformed.
    final raw = (jsonDecode(file.readAsStringSync()) as Map)['circuits'] as List;
    expect(list.circuits.length, raw.length);
  });
}
