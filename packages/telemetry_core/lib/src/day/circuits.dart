// The circuit list: named places, each a centre and a radius, that put a
// name on a route found from GPS. The list ships with the app, a newer one
// can be fetched, and the driver's own circuits (new ones, or a new name
// for a listed one) are kept beside it.
import 'dart:convert';
import 'dart:math' as math;

import '../geometry.dart';
import 'day_analysis.dart';

/// The `format` of a circuit list.
const circuitListFormat = 'flappedear-circuits';

/// The `format` of the driver's own circuits.
const userCircuitsFormat = 'flappedear-my-circuits';

/// The version of both formats this code writes and the newest it reads.
const circuitListVersion = 1;

/// The most circuits a list holds.
const maximumCircuits = 20000;

/// The longest circuit name, in UTF-16 code units.
const maximumCircuitNameCharacters = 128;

/// The radius of a circuit that gives none, in metres.
const defaultCircuitRadiusMeters = 2000.0;

/// The largest radius a circuit can have, in metres.
const maximumCircuitRadiusMeters = 20000.0;

/// A named circuit: a route whose start lies within [radiusMeters] of
/// [centre] is on it.
final class Circuit {
  const Circuit({
    required this.id,
    required this.name,
    required this.centre,
    this.country = '',
    this.radiusMeters = defaultCircuitRadiusMeters,
  });

  /// Stable across list revisions; a driver's circuit with the same id
  /// renames the listed one.
  final String id;
  final String name;
  final GeoCoordinate centre;

  /// ISO 3166-1 alpha-2 code; empty when unknown.
  final String country;
  final double radiusMeters;

  Circuit copyWith({String? name}) => Circuit(
    id: id,
    name: name ?? this.name,
    centre: centre,
    country: country,
    radiusMeters: radiusMeters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (country.isNotEmpty) 'country': country,
    'lat': centre.latitudeDegrees,
    'lon': centre.longitudeDegrees,
    'radius': radiusMeters,
  };
}

/// A list of circuits and its [revision]: a list with a higher revision
/// replaces one with a lower.
final class CircuitList {
  CircuitList({required this.revision, List<Circuit> circuits = const [], this.source = ''})
    : circuits = List.unmodifiable(circuits);

  /// An empty list, older than any published one.
  static final empty = CircuitList(revision: 0);

  final int revision;
  final List<Circuit> circuits;

  /// Where the circuits come from and under which licence.
  final String source;
}

/// The circuit list in [text]. Entries that are not a circuit (no name, a
/// position off the globe) are left out. Throws [FormatException] when the
/// text is not a circuit list this version reads.
CircuitList decodeCircuitList(String text) {
  final json = _object(text, circuitListFormat);
  final revision = json['revision'];
  if (revision is! int || revision < 0) {
    throw const FormatException('A circuit list needs a revision.');
  }
  final source = json['source'];
  return CircuitList(
    revision: revision,
    circuits: _circuits(json['circuits']),
    source: source is String ? source : '',
  );
}

/// The driver's own circuits in [text]; see [decodeCircuitList].
List<Circuit> decodeUserCircuits(String text) =>
    _circuits(_object(text, userCircuitsFormat)['circuits']);

/// [circuits] as the driver's own circuits file.
String encodeUserCircuits(List<Circuit> circuits) => const JsonEncoder.withIndent('  ').convert({
  'format': userCircuitsFormat,
  'version': circuitListVersion,
  'circuits': [for (final circuit in circuits) circuit.toJson()],
});

Map<String, Object?> _object(String text, String format) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('Not JSON.');
  }
  if (json is! Map<String, Object?> || json['format'] != format) {
    throw FormatException('Not a $format file.');
  }
  final version = json['version'];
  if (version is! int || version < 1 || version > circuitListVersion) {
    throw FormatException('Unsupported $format version: $version.');
  }
  return json;
}

List<Circuit> _circuits(Object? value) {
  if (value is! List) throw const FormatException('No circuits.');
  if (value.length > maximumCircuits) throw const FormatException('Too many circuits.');
  final circuits = <Circuit>[];
  final ids = <String>{};
  for (final entry in value) {
    final circuit = _circuit(entry);
    if (circuit != null && ids.add(circuit.id)) circuits.add(circuit);
  }
  return circuits;
}

Circuit? _circuit(Object? entry) {
  if (entry is! Map) return null;
  final id = entry['id'], name = entry['name'], lat = entry['lat'], lon = entry['lon'];
  final radius = entry['radius'] ?? defaultCircuitRadiusMeters;
  final country = entry['country'] ?? '';
  if (id is! String || id.isEmpty || id.length > 64) return null;
  if (name is! String || lat is! num || lon is! num || radius is! num || country is! String) {
    return null;
  }
  final trimmed = name.trim();
  if (trimmed.isEmpty ||
      trimmed.length > maximumCircuitNameCharacters ||
      trimmed.contains('\u0000')) {
    return null;
  }
  final centre = GeoCoordinate(lat.toDouble(), lon.toDouble());
  if (!isValidCoordinate(centre)) return null;
  final metres = radius.toDouble();
  if (!metres.isFinite || metres <= 0 || metres > maximumCircuitRadiusMeters) return null;
  return Circuit(
    id: id,
    name: trimmed,
    centre: centre,
    country: country.length == 2 ? country.toUpperCase() : '',
    radiusMeters: metres,
  );
}

/// The great-circle distance between [a] and [b], in metres.
double distanceMeters(GeoCoordinate a, GeoCoordinate b) {
  final lat1 = a.latitudeDegrees * radiansPerDegree;
  final lat2 = b.latitudeDegrees * radiansPerDegree;
  final dLat = lat2 - lat1;
  final dLon = (b.longitudeDegrees - a.longitudeDegrees) * radiansPerDegree;
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(dLon / 2), 2);
  return 2 * earthRadiusMeters * math.asin(math.min(1.0, math.sqrt(h)));
}

/// The circuit [at] lies on: of the circuits whose radius reaches it, the
/// one with the nearest centre. The driver's own circuits ([mine]) come
/// first; one of them with a listed circuit's id only renames that circuit,
/// which keeps the list's position. Null when none reaches it.
Circuit? findCircuit(GeoCoordinate at, List<Circuit> listed, {List<Circuit> mine = const []}) {
  if (!isValidCoordinate(at)) return null;
  final names = {for (final circuit in mine) circuit.id: circuit.name};
  final ids = {for (final circuit in listed) circuit.id};
  final own = _nearest(at, [
    for (final circuit in mine)
      if (!ids.contains(circuit.id)) circuit,
  ]);
  if (own != null) return own;
  final match = _nearest(at, listed);
  if (match == null) return null;
  final name = names[match.id];
  return name == null ? match : match.copyWith(name: name);
}

Circuit? _nearest(GeoCoordinate at, List<Circuit> circuits) {
  Circuit? best;
  var bestDistance = double.infinity;
  for (final circuit in circuits) {
    final distance = distanceMeters(at, circuit.centre);
    if (distance <= circuit.radiusMeters && distance < bestDistance) {
      best = circuit;
      bestDistance = distance;
    }
  }
  return best;
}

/// Where the route of [runIds] starts in [analysis]: the start line of the
/// first of them with a detected route. Null when none has one.
GeoCoordinate? routeStart(DayAnalysis analysis, Iterable<String> runIds) {
  for (final runId in runIds) {
    final route = analysis.inferences[runId]?.route;
    if (route != null) return route.origin;
  }
  return null;
}
