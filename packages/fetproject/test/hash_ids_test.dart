import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fetproject/fetproject.dart';
import 'package:test/test.dart';

final Map<String, Object?> vectors = (jsonDecode(
  File('test/fixtures/qt_hash_vectors.json').readAsStringSync(),
) as Map).cast<String, Object?>();

List<Map<String, Object?>> cases(String name) => [
  for (final item in vectors[name] as List)
    (item as Map).cast<String, Object?>(),
];

double fromBits(String hex) {
  final bytes = ByteData(8)
    ..setUint32(0, int.parse(hex.substring(0, 8), radix: 16))
    ..setUint32(4, int.parse(hex.substring(8), radix: 16));
  return bytes.getFloat64(0);
}

Map<String, Object?> object(String text) =>
    (qtJsonDecode(text) as Map).cast<String, Object?>();

void main() {
  group('gates-v1', () {
    for (final vector in cases('gatesV1')) {
      test(vector['name'], () {
        final gates = [
          for (final item in vector['gates'] as List)
            (
              type: TimingGateType.values.byName(
                (item as Map)['type'] as String,
              ),
              aLatitude: fromBits(item['aLatitudeBits'] as String),
              aLongitude: fromBits(item['aLongitudeBits'] as String),
              bLatitude: fromBits(item['bLatitudeBits'] as String),
              bLongitude: fromBits(item['bLongitudeBits'] as String),
            ),
        ];
        expect(
          gatesV1Revision(gates, westPositive: vector['westPositive'] as bool),
          vector['revision'],
        );
      });
    }

    test('more than 128 gates is unresolved', () {
      final gates = [
        for (var i = 0; i < 129; i++)
          (
            type: i == 0 ? TimingGateType.start : TimingGateType.split,
            aLatitude: 50.0,
            aLongitude: 19.0,
            bLatitude: 50.001,
            bLongitude: 19.001,
          ),
      ];
      expect(gatesV1Revision(gates, westPositive: false), isNull);
      expect(
        gatesV1Revision(gates.sublist(0, 128), westPositive: false),
        isNotNull,
      );
    });

    test('a non-finite coordinate is unresolved', () {
      final gate = (
        type: TimingGateType.start,
        aLatitude: double.nan,
        aLongitude: 19.0,
        bLatitude: 50.001,
        bLongitude: 19.001,
      );
      expect(gatesV1Revision([gate], westPositive: false), isNull);
    });
  });

  group('compatibility-v1', () {
    for (final vector in cases('compatibilityV1')) {
      test(vector['name'], () {
        expect(
          compatibilityV1Id(object(vector['trackConfiguration'] as String)),
          vector['id'],
        );
      });
    }
  });

  group('track-segments-v1', () {
    for (final vector in cases('trackSegmentsV1')) {
      test(vector['name'], () {
        final segments =
            qtJsonDecode(vector['trackSegments'] as String) as List;
        expect(trackSegmentsV1Revision(segments), vector['revision']);
      });
    }
  });

  group('lap-derivation-v1', () {
    for (final vector in cases('lapDerivationV1')) {
      test(vector['name'], () {
        expect(
          lapDerivationV1Key(object(vector['run'] as String)),
          vector['key'],
        );
      });
    }
  });

  group('lap reference keys', () {
    for (final vector in cases('lapReferenceKeys')) {
      test(vector['key'], () {
        expect(
          lapReferenceKey(object(vector['reference'] as String)),
          vector['key'],
        );
      });
    }
  });

  test('Qt whitespace matches QChar::isSpace', () {
    final expected = (vectors['qtSpaceCodeUnits'] as List).cast<int>().toSet();
    for (var unit = 0; unit <= 0xffff; unit++) {
      final layout = String.fromCharCode(unit);
      final configuration = {
        'layoutId': layout,
        'direction': 'clockwise',
        'gateRevision': 'gates-v1:${'a' * 64}',
      };
      final resolved = compatibilityV1Id(configuration) != null;
      final isSpace = expected.contains(unit);
      if (unit == 0) {
        expect(resolved, isFalse);
      } else {
        expect(resolved, !isSpace, reason: 'U+${unit.toRadixString(16)}');
      }
    }
  });
}
