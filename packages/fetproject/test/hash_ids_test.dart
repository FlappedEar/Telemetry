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

typedef _Gate = TimingGateEndpoints;

_Gate _gate(
  double aLatitude,
  double aLongitude,
  double bLatitude,
  double bLongitude, {
  TimingGateType type = TimingGateType.start,
}) => (
  type: type,
  aLatitude: aLatitude,
  aLongitude: aLongitude,
  bLatitude: bLatitude,
  bLongitude: bLongitude,
);

void main() {
  group('gates-v2 (FET-250)', () {
    // The start line of the owner's Jastrząb day as the RCZ and the VBO of
    // the same session give it: the same line, the endpoints in opposite
    // order and some 1e-9° apart; the VBO is west-positive.
    final rcz = _gate(
      51.263424599976624,
      20.934579632124898,
      51.26333740002338,
      20.93483103454177,
    );
    final vbo = _gate(
      51.2633374014736,
      -20.93483103756758,
      51.26342459852639,
      -20.934579629099087,
    );

    test('one line gives one revision whichever format declared it', () {
      final fromRcz = gatesV2Revision([rcz], westPositive: false);
      expect(fromRcz, matches(RegExp(r'^gates-v2:[0-9a-f]{64}$')));
      expect(gatesV2Revision([vbo], westPositive: true), fromRcz);
      expect(
        gatesV1Revision([vbo], westPositive: true),
        isNot(gatesV1Revision([rcz], westPositive: false)),
      );
    });

    test('a start line moved or turned is another revision', () {
      final base = gatesV2Revision([rcz], westPositive: false);
      expect(
        gatesV2Revision([
          _gate(
            51.263424599976624 + 5e-5,
            20.934579632124898,
            51.26333740002338 + 5e-5,
            20.93483103454177,
          ),
        ], westPositive: false),
        isNot(base),
        reason: 'about 5.5 m north',
      );
      expect(
        gatesV2Revision([
          _gate(
            51.263424599976624,
            20.934579632124898 + 1e-4,
            51.26333740002338,
            20.93483103454177 + 1e-4,
          ),
        ], westPositive: false),
        isNot(base),
        reason: 'about 7 m east',
      );
      // Turned about its centre (51.263381, 20.9347053) from bearing 119° to 129°.
      expect(
        gatesV2Revision([
          _gate(51.2634376, 20.9345935, 51.2633244, 20.9348171),
        ], westPositive: false),
        isNot(base),
      );
    });

    test('the order of the gates counts, the order of one gate\'s endpoints does not', () {
      final split = _gate(
        51.2640,
        20.9350,
        51.2641,
        20.9351,
        type: TimingGateType.split,
      );
      final swapped = _gate(
        51.2641,
        20.9351,
        51.2640,
        20.9350,
        type: TimingGateType.split,
      );
      expect(
        gatesV2Revision([rcz, split], westPositive: false),
        gatesV2Revision([rcz, swapped], westPositive: false),
      );
      expect(
        gatesV2Revision([rcz, split], westPositive: false),
        isNot(gatesV2Revision([split, rcz], westPositive: false)),
      );
    });

    test('is unresolved as gates-v1 is', () {
      expect(gatesV2Revision(const [], westPositive: false), isNull);
      expect(
        gatesV2Revision([rcz, rcz], westPositive: false),
        isNull,
        reason: 'two starts',
      );
      expect(
        gatesV2Revision([_gate(91, 0, 50, 0)], westPositive: false),
        isNull,
      );
      expect(
        gatesV2Revision([_gate(50, 19, 50, 19)], westPositive: false),
        isNull,
        reason: 'a point',
      );
      expect(
        gatesV2Revision([
          _gate(50, 19, 50.001, 19, type: TimingGateType.unknown),
        ], westPositive: false),
        isNull,
      );
    });

    test('a line over the antimeridian keeps its centre on the short side', () {
      final east = _gate(10.0, 179.99995, 10.0001, -179.99995);
      final west = _gate(10.0001, -179.99995, 10.0, 179.99995);
      expect(gatesV2Revision([east], westPositive: false), isNotNull);
      expect(
        gatesV2Revision([east], westPositive: false),
        gatesV2Revision([west], westPositive: false),
      );
    });
  });

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
