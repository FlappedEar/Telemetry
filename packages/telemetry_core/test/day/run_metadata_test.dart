import 'dart:convert';
import 'dart:io';

import 'package:fetproject/fetproject.dart' as fet;
import 'package:path/path.dart' as p;
import 'package:telemetry_core/telemetry_core.dart';
import 'package:test/test.dart';

import '../support/circuit_vbo.dart';

void main() {
  group('runMetadataProblem', () {
    test('accepts a name and bounded texts', () {
      expect(runMetadataProblem(const RunMetadata(name: 'Session 1')), isNull);
      expect(
        runMetadataProblem(
          RunMetadata(name: 'x' * 160, notes: 'n' * 4096, conditions: '', setupChanges: 's'),
        ),
        isNull,
      );
    });

    test('refuses a blank, long or NUL name and long or NUL texts', () {
      expect(runMetadataProblem(const RunMetadata(name: '  ')), isNotNull);
      // Overlays counts the name as typed, before trimming.
      expect(runMetadataProblem(RunMetadata(name: ' ${'x' * 160}')), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a\u0000b')), isNotNull);
      expect(runMetadataProblem(RunMetadata(name: 'a', notes: 'n' * 4097)), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a', conditions: '\u0000')), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a', setupChanges: 'x\u0000')), isNotNull);
    });

    test('counts UTF-16 code units, as Qt does', () {
      // 80 emoji are 160 code units.
      expect(runMetadataProblem(RunMetadata(name: '🏁' * 80)), isNull);
      expect(runMetadataProblem(RunMetadata(name: '🏁' * 81)), isNotNull);
    });
  });

  group('applyRunMetadata', () {
    test('trims the name and keeps texts as written', () {
      final run = <String, Object?>{'id': 'r', 'name': 'Session 1'};
      expect(
        applyRunMetadata(
          run,
          const RunMetadata(name: '  Warm-up  ', notes: ' Dry line ', conditions: 'Wet'),
        ),
        isTrue,
      );
      expect(run, {'id': 'r', 'name': 'Warm-up', 'notes': ' Dry line ', 'conditions': 'Wet'});
    });

    test('an unchanged legacy record gains no keys', () {
      final run = <String, Object?>{'id': 'r', 'name': 'Session 1'};
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isFalse);
      expect(run, {'id': 'r', 'name': 'Session 1'});
    });

    test('a cleared or blank text is stored as null, as Overlays stores it', () {
      final run = <String, Object?>{
        'id': 'r',
        'name': 'Session 1',
        'notes': 'Old',
        'conditions': null,
      };
      expect(
        applyRunMetadata(run, const RunMetadata(name: 'Session 1', notes: '', setupChanges: '  ')),
        isTrue,
      );
      expect(run, {
        'id': 'r',
        'name': 'Session 1',
        'notes': null,
        'conditions': null,
        'setupChanges': null,
      });
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isFalse);
    });

    test('reads a stored document run', () {
      final metadata = RunMetadata.fromRun(const {
        'name': 'Session 2',
        'notes': 'N',
        'conditions': null,
      });
      expect(metadata, const RunMetadata(name: 'Session 2', notes: 'N'));
    });
  });

  test('applyRunMetadataEdits copies edited runs and adds runs not saved yet', () {
    final stored = <String, Object?>{'id': 'a', 'name': 'Session 1', 'notes': 'x'};
    final runs = applyRunMetadataEdits(
      [stored, 7],
      {
        'a': const RunMetadata(name: 'Session 1', notes: 'y'),
        'b': const RunMetadata(name: 'Session 2', conditions: 'Dry'),
      },
    );
    expect(stored['notes'], 'x');
    expect(runs, [
      {'id': 'a', 'name': 'Session 1', 'notes': 'y'},
      7,
      {'id': 'b', 'name': 'Session 2', 'conditions': 'Dry'},
    ]);
  });

  group('run setup', () {
    const bar = RunSetup(
      pressureUnit: PressureUnit.bar,
      cold: WheelPressures(fl: 2.1, fr: 2.1, rl: 2.0, rr: 2.0),
      hot: WheelPressures(fl: 2.45, rr: 2.5),
      tyre: 'Pirelli Diablo Supercorsa SC2',
      fuelStartLitres: 8.5,
    );

    test('parses what the driver types, with a decimal point only', () {
      expect(parseSetupNumber('2.1'), 2.1);
      expect(parseSetupNumber(' 32 '), 32);
      expect(parseSetupNumber('2.'), 2);
      expect(parseSetupNumber('.5'), 0.5);
      expect(parseSetupNumber('150.25'), 150.25);
      expect(parseSetupNumber('2,1'), isNull);
      expect(parseSetupNumber('2, 1'), isNull);
      expect(parseSetupNumber(' 2.1'), 2.1);
      expect(parseSetupNumber('2. 1 '), 2.1);
      expect(parseSetupNumber('2.125'), isNull);
      expect(parseSetupNumber('-1'), isNull);
      expect(parseSetupNumber('1e1'), isNull);
      expect(parseSetupNumber(''), isNull);
      expect(parseSetupNumber('.'), isNull);
      expect(parseSetupNumber('1234'), isNull);
    });

    test('validates ranges per unit, decimals, fuel and the tyre', () {
      expect(runSetupProblem(bar), isNull);
      expect(runSetupProblem(const RunSetup()), isNull);
      expect(runSetupProblem(const RunSetup(pressureUnit: PressureUnit.psi)), isNull);
      RunSetup cold(PressureUnit? unit, double value) => RunSetup(
        pressureUnit: unit,
        cold: WheelPressures(rl: value),
      );
      expect(runSetupProblem(cold(PressureUnit.bar, 0.5)), isNull);
      expect(runSetupProblem(cold(PressureUnit.bar, 6)), isNull);
      expect(runSetupProblem(cold(PressureUnit.bar, 0.49)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.bar, 6.01)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.bar, 2.105)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.bar, 30)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.psi, 7)), isNull);
      expect(runSetupProblem(cold(PressureUnit.psi, 90)), isNull);
      expect(runSetupProblem(cold(PressureUnit.psi, 6.99)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.psi, 90.01)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.psi, 2.1)), isNotNull);
      expect(runSetupProblem(cold(PressureUnit.psi, double.nan)), isNotNull);
      // A pressure needs a unit.
      expect(runSetupProblem(cold(null, 2.1)), isNotNull);
      expect(runSetupProblem(const RunSetup(hot: WheelPressures(fr: 30))), isNotNull);
      expect(runSetupProblem(const RunSetup(fuelStartLitres: 0)), isNull);
      expect(runSetupProblem(const RunSetup(fuelStartLitres: 200)), isNull);
      expect(runSetupProblem(const RunSetup(fuelStartLitres: 200.01)), isNotNull);
      expect(runSetupProblem(const RunSetup(fuelStartLitres: -1)), isNotNull);
      expect(runSetupProblem(const RunSetup(fuelStartLitres: 8.555)), isNotNull);
      expect(runSetupProblem(RunSetup(tyre: 'x' * 160)), isNull);
      expect(runSetupProblem(RunSetup(tyre: 'x' * 161)), isNotNull);
      expect(runSetupProblem(const RunSetup(tyre: 'a\u0000')), isNotNull);
      // The session's other details are checked with it.
      expect(runMetadataProblem(RunMetadata(name: 'a', setup: cold(null, 2))), isNotNull);
      expect(runMetadataProblem(const RunMetadata(name: 'a', setup: bar)), isNull);
    });

    test('is stored in the unit entered and read back the same', () {
      final run = <String, Object?>{'name': 'Session 1'};
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1', setup: bar)), isTrue);
      expect(run['setup'], {
        'version': 'session-setup-v1',
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1, 'fr': 2.1, 'rl': 2.0, 'rr': 2.0},
        'hotPressure': {'fl': 2.45, 'rr': 2.5},
        'tyre': 'Pirelli Diablo Supercorsa SC2',
        'fuelStartLitres': 8.5,
      });
      expect(RunMetadata.fromRun(run).setup, bar);
      expect(bar.toJson(), run['setup']);
      final psi = <String, Object?>{'name': 'Session 1'};
      const inPsi = RunSetup(
        pressureUnit: PressureUnit.psi,
        cold: WheelPressures(fl: 30, fr: 30.5, rl: 28, rr: 28),
      );
      applyRunMetadata(psi, const RunMetadata(name: 'Session 1', setup: inPsi));
      expect((psi['setup']! as Map)['coldPressure'], {'fl': 30, 'fr': 30.5, 'rl': 28, 'rr': 28});
      expect(RunMetadata.fromRun(psi).setup, inPsi);
    });

    test('reads leniently: invalid values are not entered', () {
      expect(RunSetup.fromJson(null), const RunSetup());
      expect(RunSetup.fromJson('bar'), const RunSetup());
      expect(RunSetup.fromJson(const {'coldPressure': 7}), const RunSetup());
      final read = RunSetup.fromJson({
        'version': 'session-setup-v1',
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1, 'fr': '2.1', 'rl': 30, 'rr': 2.123},
        'hotPressure': [2.4],
        'tyre': 'x' * 161,
        'fuelStartLitres': 500,
      });
      expect(read, const RunSetup(pressureUnit: PressureUnit.bar, cold: WheelPressures(fl: 2.1)));
      // Pressures without a unit, or in an unknown one, are not entered.
      expect(
        RunSetup.fromJson(const {
          'pressureUnit': 'kPa',
          'coldPressure': {'fl': 210},
          'tyre': 'Slick',
        }),
        const RunSetup(tyre: 'Slick'),
      );
      expect(
        RunMetadata.fromRun(const {'id': 'a', 'name': 'Session 1', 'setup': 'garbage'}).setup,
        const RunSetup(),
      );
    });

    test('keeps unknown keys and changes only what was edited', () {
      final run = <String, Object?>{
        'name': 'Session 1',
        'setup': {
          'version': 'session-setup-v1',
          'pressureUnit': 'bar',
          'coldPressure': {'fl': 2.1, 'fr': 2.1, 'rl': 9.0, 'futureWheel': 'kept'},
          'tyre': 'Old',
          'futureSetup': {'kept': true},
        },
      };
      final stored = RunMetadata.fromRun(run);
      final edited = RunMetadata(
        name: 'Session 1',
        setup: RunSetup(
          pressureUnit: PressureUnit.bar,
          cold: const WheelPressures(fl: 2.2, fr: 2.1),
          hot: const WheelPressures(rr: 2.4),
          tyre: stored.setup.tyre,
        ),
      );
      expect(applyRunMetadata(run, edited), isTrue);
      expect(run['setup'], {
        'version': 'session-setup-v1',
        'pressureUnit': 'bar',
        // 9.0 bar reads as not entered and was not edited: it stays.
        'coldPressure': {'fl': 2.2, 'fr': 2.1, 'rl': 9.0, 'futureWheel': 'kept'},
        'tyre': 'Old',
        'futureSetup': {'kept': true},
        'hotPressure': {'rr': 2.4},
      });
      // Cleared, the setup keeps only what this app does not know.
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isTrue);
      expect(run['setup'], {
        'version': 'session-setup-v1',
        // The unit went with the last pressure: the value read as not
        // entered went with it.
        'coldPressure': {'futureWheel': 'kept'},
        'futureSetup': {'kept': true},
      });
      final plain = <String, Object?>{
        'name': 'Session 1',
        'setup': {'version': 'session-setup-v1', 'tyre': 'Wet'},
      };
      expect(applyRunMetadata(plain, const RunMetadata(name: 'Session 1')), isTrue);
      expect(plain.containsKey('setup'), isFalse);
    });

    test('a new unit drops pressures read as not entered in the old one', () {
      final run = <String, Object?>{
        'name': 'Session 1',
        'setup': {
          'version': 'session-setup-v1',
          'pressureUnit': 'bar',
          // 30 is no pressure in bar, but would be one in psi.
          'coldPressure': {'fl': 2.1, 'rl': 30, 'futureWheel': 'kept'},
          'hotPressure': {'rr': 31},
        },
      };
      const psi = RunSetup(pressureUnit: PressureUnit.psi, cold: WheelPressures(fl: 30.5));
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1', setup: psi)), isTrue);
      expect(run['setup'], {
        'version': 'session-setup-v1',
        'pressureUnit': 'psi',
        'coldPressure': {'fl': 30.5, 'futureWheel': 'kept'},
      });
      expect(RunMetadata.fromRun(run).setup, psi);
      // Pressures stored without a unit do not come back with one either.
      final unitless = <String, Object?>{
        'name': 'Session 1',
        'setup': {
          'coldPressure': {'fl': 2.1, 'fr': 2.2},
        },
      };
      const bar = RunSetup(pressureUnit: PressureUnit.bar, cold: WheelPressures(fl: 2.0));
      applyRunMetadata(unitless, const RunMetadata(name: 'Session 1', setup: bar));
      expect((unitless['setup']! as Map)['coldPressure'], {'fl': 2.0});
    });

    test('a setup cleared of everything leaves no stub', () {
      final run = <String, Object?>{
        'name': 'Session 1',
        'setup': {
          'version': 'session-setup-v1',
          'pressureUnit': 'psi',
          'coldPressure': {'fl': 30},
          'tyre': 'Slick',
          'fuelStartLitres': 10,
        },
      };
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isTrue);
      expect(run.containsKey('setup'), isFalse);
      // A unit with no pressure stays while the setup is not edited, and
      // goes once it is.
      final unitOnly = <String, Object?>{
        'name': 'Session 1',
        'setup': {'version': 'session-setup-v1', 'pressureUnit': 'bar', 'tyre': 'Rain'},
      };
      expect(
        applyRunMetadata(
          unitOnly,
          const RunMetadata(
            name: 'Session 1',
            setup: RunSetup(pressureUnit: PressureUnit.bar, tyre: 'Rain'),
          ),
        ),
        isFalse,
      );
      expect(
        applyRunMetadata(
          unitOnly,
          const RunMetadata(
            name: 'Session 1',
            setup: RunSetup(pressureUnit: PressureUnit.bar, tyre: 'Wet'),
          ),
        ),
        isTrue,
      );
      expect(unitOnly['setup'], {'version': 'session-setup-v1', 'tyre': 'Wet'});
      final fresh = <String, Object?>{'name': 'Session 1'};
      expect(
        applyRunMetadata(
          fresh,
          const RunMetadata(
            name: 'Session 1',
            setup: RunSetup(pressureUnit: PressureUnit.psi),
          ),
        ),
        isFalse,
      );
      expect(fresh.containsKey('setup'), isFalse);
    });

    test('editing only the notes leaves the setup as stored', () {
      final setup = {
        'version': 'session-setup-v1',
        'pressureUnit': 'bar',
        // Not readable in bar: read as not entered, and kept.
        'coldPressure': {'fl': 9},
      };
      final run = <String, Object?>{'name': 'Session 1', 'setup': setup};
      final before = jsonEncode(run);
      final read = RunMetadata.fromRun(run);
      expect(read.setup, const RunSetup(pressureUnit: PressureUnit.bar));
      expect(
        applyRunMetadata(run, RunMetadata(name: 'Session 1', notes: 'Wet', setup: read.setup)),
        isTrue,
      );
      expect(identical(run['setup'], setup), isTrue);
      expect(jsonEncode(run['setup']), jsonEncode(jsonDecode(before)['setup']));
      expect(run['notes'], 'Wet');
    });

    test('an unchanged setup is left byte for byte', () {
      final setup = {
        'fuelStartLitres': 8.50,
        'tyre': 'Slick',
        'pressureUnit': 'psi',
        'coldPressure': {'rr': 28, 'fl': 30},
        'version': 'session-setup-v1',
      };
      final run = <String, Object?>{'name': 'Session 1', 'setup': setup};
      final before = jsonEncode(run);
      expect(applyRunMetadata(run, RunMetadata.fromRun(run)), isFalse);
      expect(jsonEncode(run), before);
      expect(identical(run['setup'], setup), isTrue);
      // A tyre typed with spaces around it is the same tyre.
      final spaced = RunMetadata(
        name: 'Session 1',
        setup: RunSetup(
          pressureUnit: PressureUnit.psi,
          cold: const WheelPressures(fl: 30, rr: 28),
          tyre: ' Slick ',
          fuelStartLitres: 8.5,
        ),
      );
      expect(applyRunMetadata(run, spaced), isFalse);
    });

    test('an unchanged record gains no setup key', () {
      final run = <String, Object?>{'name': 'Session 1', 'notes': 'n'};
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1', notes: 'n')), isFalse);
      expect(run, {'name': 'Session 1', 'notes': 'n'});
      expect(
        applyRunMetadata(
          run,
          const RunMetadata(
            name: 'Session 1',
            notes: 'n',
            setup: RunSetup(tyre: '  '),
          ),
        ),
        isFalse,
      );
      expect(run.containsKey('setup'), isFalse);
    });

    test('a setup of an unknown version is read but never rewritten', () {
      final setup = {
        'version': 'session-setup-v2',
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1},
        'futureField': 1,
      };
      final run = <String, Object?>{'name': 'Session 1', 'setup': setup};
      final read = RunMetadata.fromRun(run).setup;
      expect(read.readOnly, isTrue);
      expect(read.unknownVersion, 'session-setup-v2');
      expect(read.cold.fl, 2.1);
      expect(runSetupProblem(read), isNull);
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1', setup: bar)), isFalse);
      expect(applyRunMetadata(run, const RunMetadata(name: 'Session 1')), isFalse);
      expect(identical(run['setup'], setup), isTrue);
      expect(run['setup'], {
        'version': 'session-setup-v2',
        'pressureUnit': 'bar',
        'coldPressure': {'fl': 2.1},
        'futureField': 1,
      });
      expect(RunSetup.fromJson(read.toJson()), read);
    });

    test('travels with the other edits of a day not saved yet', () {
      final runs = applyRunMetadataEdits(
        [
          {
            'id': 'a',
            'name': 'Session 1',
            'setup': {'futureSetup': 1},
          },
        ],
        {
          'a': const RunMetadata(
            name: 'Session 1',
            setup: RunSetup(tyre: 'Rain'),
          ),
          'b': const RunMetadata(name: 'Session 2', setup: RunSetup(fuelStartLitres: 20)),
        },
      );
      expect(runs, [
        {
          'id': 'a',
          'name': 'Session 1',
          'setup': {'futureSetup': 1, 'version': 'session-setup-v1', 'tyre': 'Rain'},
        },
        {
          'id': 'b',
          'name': 'Session 2',
          'setup': {'version': 'session-setup-v1', 'fuelStartLitres': 20.0},
        },
      ]);
    });
  });

  test('dayNameProblem follows the event name rules', () {
    expect(dayNameProblem('Day 2026-08-29'), isNull);
    expect(dayNameProblem(' ${'x' * 160} '), isNull);
    expect(dayNameProblem('x' * 161), isNotNull);
    expect(dayNameProblem(' '), isNotNull);
    expect(dayNameProblem('a\u0000'), isNotNull);
  });

  group('a day', () {
    late Directory directory;
    setUp(() => directory = Directory.systemTemp.createTempSync('run_metadata'));
    tearDown(() => directory.deleteSync(recursive: true));

    test('saves edited metadata and a renamed day, and opens them again', () async {
      final root = directory.resolveSymbolicLinksSync();
      final a = p.join(root, 'a.vbo');
      final b = p.join(root, 'b.vbo');
      File(a).writeAsStringSync(circuitVbo([30, 28, 31]));
      File(b).writeAsStringSync(circuitVbo([29, 32]));
      final runs = nameRunsInRecordingOrder(prepareTelemetryImport([a, b]).runs);
      var analysis = analyzeDay([
        for (final named in runs)
          DayRunInput(
            runId: named.run.id,
            name: named.name,
            contentSha256: named.run.contentSha256,
            session: named.run.telemetry,
            laps: named.run.laps,
          ),
      ]);
      final first = runs.first.run.id;
      analysis = renameDayRun(analysis, first, 'Warm-up');
      expect(
        {
          for (final row in analysis.rows)
            if (row.runId == first) row.runName,
        },
        {'Warm-up'},
      );
      expect([for (final run in analysis.ranking!.runs) run.runName], contains('Warm-up'));
      final named = [
        for (final run in runs) run.run.id == first ? (run: run.run, name: 'Warm-up') : run,
      ];
      final path = p.join(root, 'day.fetproject');
      final document = dayDocument(
        eventId: newEventId(),
        name: 'Łódź, morning',
        runs: named,
        analysis: analysis,
        projectPath: path,
        runMetadata: {
          first: const RunMetadata(
            name: 'Warm-up',
            notes: 'Brake earlier into T1',
            conditions: 'Dry, 18 °C',
            setupChanges: 'Tyres +0.1 bar',
            setup: RunSetup(
              pressureUnit: PressureUnit.psi,
              cold: WheelPressures(fl: 30, fr: 30, rl: 28.5, rr: 28.5),
              tyre: 'Pirelli SC2',
            ),
          ),
        },
      );
      expect(fet.validateFetproject(document), isNull);
      await saveDayDocument(path, document);
      final opened = openDay(path);
      expect(opened.name, 'Łódź, morning');
      final run = ((opened.document['event']! as Map)['runs']! as List).firstWhere(
        (run) => (run as Map)['id'] == first,
      ) as Map<String, Object?>;
      expect(
        RunMetadata.fromRun(run),
        const RunMetadata(
          name: 'Warm-up',
          notes: 'Brake earlier into T1',
          conditions: 'Dry, 18 °C',
          setupChanges: 'Tyres +0.1 bar',
          setup: RunSetup(
            pressureUnit: PressureUnit.psi,
            cold: WheelPressures(fl: 30, fr: 30, rl: 28.5, rr: 28.5),
            tyre: 'Pirelli SC2',
          ),
        ),
      );
      final other = ((opened.document['event']! as Map)['runs']! as List).firstWhere(
        (run) => (run as Map)['id'] != first,
      ) as Map<String, Object?>;
      for (final key in [...runMetadataTextKeys, runSetupKey]) {
        expect(other.containsKey(key), isFalse);
      }
      expect([for (final run in opened.runs) run.name], contains('Warm-up'));
    });
  });
}
