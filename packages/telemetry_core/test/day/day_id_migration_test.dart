// The ids a day saved before FET-250 holds move to the ids of today when it
// opens, and nothing the driver kept is lost.
import 'package:fetproject/fetproject.dart' as fet;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuits.dart';

const _old = 'compatibility-v1:1111111111111111111111111111111111111111111111111111111111111111';
const _new = 'compatibility-v1:2222222222222222222222222222222222222222222222222222222222222222';
const _other = 'compatibility-v1:3333333333333333333333333333333333333333333333333333333333333333';

Map<String, Object?> _document() => {
  'event': {
    'analysisDecisions': {'comparisonGroupId': _old},
    'runs': [
      {
        'id': 'a',
        'trackSegments': [
          {'id': 's1', 'trackConfigurationReference': _old},
          {'id': 's2', 'trackConfigurationReference': _other},
        ],
        'trackSegmentReview': {'version': 'v', 'trackConfigurationReference': _old},
        'nextGoals': {'version': 1, 'groupId': _old, 'goals': <Object?>[]},
      },
      {'id': 'b'},
    ],
  },
};

void main() {
  test('every place a group id is kept follows the map, and only the ids in it', () {
    final document = _document();
    remapDocumentGroupIds(document, {_old: _new});
    final event = document['event']! as Map<String, Object?>;
    expect((event['analysisDecisions']! as Map)['comparisonGroupId'], _new);
    final run = (event['runs']! as List).first as Map<String, Object?>;
    expect(
      [for (final s in run['trackSegments']! as List) (s as Map)['trackConfigurationReference']],
      [_new, _other],
    );
    expect((run['trackSegmentReview']! as Map)['trackConfigurationReference'], _new);
    expect((run['nextGoals']! as Map)['groupId'], _new);
  });

  test('an empty map leaves the document as it was, and odd shapes are left alone', () {
    final document = _document();
    remapDocumentGroupIds(document, const {});
    expect(document, _document());
    final odd = <String, Object?>{
      'event': {
        'runs': [
          'x',
          {'trackSegments': 'no', 'trackSegmentReview': 3, 'nextGoals': <Object?>[]},
        ],
      },
    };
    remapDocumentGroupIds(odd, {_old: _new});
    remapDocumentGroupIds({'event': 3}, {_old: _new});
    remapDocumentGroupIds({}, {_old: _new});
  });

  group('a run saved with the old gate revision', () {
    final session = circuitSession();
    Map<String, Object?> run(String? gate) => {
      'id': 'a',
      'primaryTelemetrySourceId': 's',
      'sources': <String, Object?>{},
      'trackConfiguration': {
        'layoutId': null,
        'direction': 'unknown',
        'gateRevision': gate,
        'sourceId': 's',
        'sourceFingerprint': <String, Object?>{},
      },
      'trackInference': {'gateRevision': gate},
    };

    test('moves to the new revision and its lap references to the new key', () {
      final legacy = legacySessionGateRevision(session)!;
      final stored = run(legacy);
      final oldKey = fet.lapDerivationV1Key(stored);
      final keys = <String, String>{};
      migrateRunGates(stored, session, keys);
      final current = sessionGateRevision(session);
      expect((stored['trackConfiguration']! as Map)['gateRevision'], current);
      expect((stored['trackInference']! as Map)['gateRevision'], current);
      expect(keys, {'a|$oldKey': fet.lapDerivationV1Key(stored)});
      expect(fet.lapDerivationV1Key(stored), isNot(oldKey));
      final event = <String, Object?>{
        'lapExclusions': [
          {
            'reference': {'runId': 'a', 'derivationKey': oldKey},
          },
          {
            'reference': {'runId': 'b', 'derivationKey': oldKey},
          },
        ],
        'analysisDecisions': {
          'comparisonSlots': [
            {'runId': 'a', 'derivationKey': oldKey},
            null,
          ],
        },
        'extension': {'runId': 'a', 'derivationKey': oldKey},
      };
      rekeyLapReferences(event, keys);
      final moved = fet.lapDerivationV1Key(stored);
      expect(valuesOf(event, 'derivationKey'), [moved, oldKey, moved, oldKey]);
    });

    test('is left as saved for gates that are not the session\'s', () {
      final other = 'gates-v1:${'b' * 64}';
      final stored = run(other);
      final keys = <String, String>{};
      migrateRunGates(stored, session, keys);
      expect((stored['trackConfiguration']! as Map)['gateRevision'], other);
      expect(keys, isEmpty);
      final current = run(sessionGateRevision(session));
      migrateRunGates(current, session, keys);
      expect(keys, isEmpty);
      migrateRunGates(run(null), session, keys);
      expect(keys, isEmpty);
    });
  });
}

Iterable<Object?> valuesOf(Object? value, String key) sync* {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == key) yield entry.value;
      yield* valuesOf(entry.value, key);
    }
  } else if (value is List) {
    for (final item in value) {
      yield* valuesOf(item, key);
    }
  }
}
