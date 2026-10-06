// Rebuilds assets/circuits/circuits.json, the circuit list the app ships and
// fetches from GitHub, from Wikidata (CC0 1.0):
//
//   dart run tool/circuits/update_circuits.dart
//
// Every item that is a motorsport racing track, a kart circuit or a
// rallycross circuit, has a position and is not closed; street circuits and
// dragstrips are left out (temporary, or not lapped). Items sharing one
// position (within 100 m) keep the oldest (lowest Q number): a copied
// position is wrong for all but one of them, and one venue needs one name.
// The revision is the hour of the run (UTC).
import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _query = '''
SELECT ?item ?itemLabel ?coord ?iso WHERE {
  VALUES ?type { wd:Q2338524 wd:Q1232319 wd:Q94196270 }
  ?item wdt:P31 ?type ;
        wdt:P625 ?coord .
  OPTIONAL { ?item wdt:P17 ?country . ?country wdt:P297 ?iso . }
  FILTER NOT EXISTS { ?item wdt:P31 wd:Q926439 }
  FILTER NOT EXISTS { ?item wdt:P31 wd:Q357121 }
  FILTER NOT EXISTS { ?item wdt:P576 [] }
  FILTER NOT EXISTS { ?item wdt:P3999 [] }
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en,mul,pl,de,fr,it,es,nl,cs,pt". }
}''';

final _point = RegExp(
  r'^Point\((-?[0-9.]+(?:[eE]-?\d+)?) (-?[0-9.]+(?:[eE]-?\d+)?)\)$',
);
final _qid = RegExp(r'/entity/(Q(\d+))$');

Future<void> main(List<String> args) async {
  final output = File(
    args.isEmpty ? 'assets/circuits/circuits.json' : args.first,
  );
  final client = HttpClient()
    ..userAgent =
        'FlappedEarTelemetry-circuits/1.0 (https://github.com/FlappedEar/Telemetry)';
  final request = await client.getUrl(
    Uri.https('query.wikidata.org', '/sparql', {
      'query': _query,
      'format': 'json',
    }),
  );
  request.headers.set('Accept', 'application/sparql-results+json');
  final response = await request.close();
  if (response.statusCode != 200) {
    stderr.writeln('Wikidata answered ${response.statusCode}.');
    exit(1);
  }
  final json = jsonDecode(
    await response.transform(utf8.decoder).join(),
  ) as Map<String, Object?>;
  client.close();

  final byId = <String, Map<String, Object?>>{};
  final numbers = <String, int>{};
  for (final row
      in ((json['results'] as Map)['bindings'] as List).cast<Map>()) {
    final item = _qid.firstMatch((row['item'] as Map)['value'] as String);
    final point = _point.firstMatch((row['coord'] as Map)['value'] as String);
    final name = ((row['itemLabel'] as Map?)?['value'] as String? ?? '').trim();
    if (item == null || point == null) continue;
    // An item without a label in any of the languages is shown by its id.
    if (name.isEmpty || RegExp(r'^Q\d+$').hasMatch(name)) continue;
    final lon = double.parse(point[1]!), lat = double.parse(point[2]!);
    if (lat.abs() > 90 || lon.abs() > 180) continue;
    final id = 'wd:${item[1]}';
    // Several countries or positions: the first is kept.
    if (byId.containsKey(id)) continue;
    numbers[id] = int.parse(item[2]!);
    byId[id] = {
      'id': id,
      'name': name.length > 128 ? name.substring(0, 128) : name,
      if ((row['iso'] as Map?)?['value'] case final String iso
          when iso.length == 2)
        'country': iso,
      'lat': double.parse(lat.toStringAsFixed(5)),
      'lon': double.parse(lon.toStringAsFixed(5)),
    };
  }

  // Oldest first; an item within 100 m of one kept already is left out.
  final ordered = byId.values.toList()
    ..sort((a, b) => numbers[a['id']]!.compareTo(numbers[b['id']]!));
  final circuits = <Map<String, Object?>>[];
  for (final entry in ordered) {
    if (!circuits.any((kept) => _metres(kept, entry) < 100)) {
      circuits.add(entry);
    }
  }
  final now = DateTime.now().toUtc();
  final revision = int.parse(
    '${now.year}${_two(now.month)}${_two(now.day)}${_two(now.hour)}',
  );
  await output.parent.create(recursive: true);
  // One circuit a line, so a revision's diff shows what changed.
  final text = StringBuffer()
    ..writeln('{')
    ..writeln(' "format": "flappedear-circuits",')
    ..writeln(' "version": 1,')
    ..writeln(' "revision": $revision,')
    ..writeln(
      ' "source": ${jsonEncode('Wikidata (https://www.wikidata.org), CC0 1.0; built by tool/circuits/update_circuits.dart')},',
    )
    ..writeln(' "circuits": [')
    ..writeAll([
      for (final circuit in circuits) '  ${jsonEncode(circuit)}',
    ], ',\n')
    ..writeln()
    ..writeln(' ]')
    ..writeln('}');
  await output.writeAsString(text.toString());
  stdout.writeln(
    'Wrote ${circuits.length} circuits (${byId.length - circuits.length} '
    'within 100 m of another left out), revision $revision, to ${output.path}.',
  );
}

double _metres(Map<String, Object?> a, Map<String, Object?> b) {
  const radians = pi / 180;
  final lat1 = (a['lat'] as double) * radians,
      lat2 = (b['lat'] as double) * radians;
  final dLat = lat2 - lat1;
  final dLon = ((b['lon'] as double) - (a['lon'] as double)) * radians;
  final h =
      pow(sin(dLat / 2), 2) + cos(lat1) * cos(lat2) * pow(sin(dLon / 2), 2);
  return 2 * 6371000.0 * asin(min(1.0, sqrt(h)));
}

String _two(int value) => value.toString().padLeft(2, '0');
