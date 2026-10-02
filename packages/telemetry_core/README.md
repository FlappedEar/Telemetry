# telemetry_core

The recording model, the VBO parser and lap timing for FlappedEar Telemetry.
Pure Dart: no Flutter, UI, video or platform code, so it runs in `dart test` and in
a background isolate.

## What it does

- `VboParser.parse`, `VboParser.parseBytes` and `parseVboFile` read a RaceChrono VBO
  export into a `TelemetrySession`: float32 channels on one strictly increasing clock
  in seconds, NaN for missing values, semantic aliases (`speed`, `latitude`,
  `throttle`...), timing gates, metadata and warnings.
- `deriveSourceLapSession` finds the passes through the recording's single `Start`
  gate and the laps between them, with reference eligibility, ranking and lap
  traces. `formatLapTime` formats a lap time without ever showing `x:60`.

- `RczParser.parseFile` reads a RaceChrono RCZ shared session (format version 1)
  into the same `TelemetrySession`: each channel keeps its own clock from the
  session origin, missing values are NaN, recording gaps get missing-value
  boundaries so they are never bridged, and the Start trap becomes a timing gate.
  The ZIP reader never extracts files, validates every header before reading
  data, caps inflation at the declared size and checks CRC-32. Resumed sessions,
  several sessions in one archive, ZIP64 and encryption are refused. Device-axis
  accelerometer channels are not presented as vehicle G.
- `scanTelemetryFolder` and `scanTelemetrySources` turn a chosen folder, or any mix
  of dropped or shared files and folders, into the list of VBO and RCZ recordings
  to import, with notes on what was skipped. Links are never followed, dot files
  and macOS `._` sidecars are skipped, and depth, entry and file counts are bounded.
- `contentSha256` gives a recording's identity by content (`recordingSourceId`:
  `sha256:<hex>`), never by file name, and refuses a file that changes while it is
  read.

- `prepareTelemetryImport` turns a list of recordings into the proposed runs of
  one day: each file is size-checked, hashed, parsed, counted against the sample
  budget, given its laps and hashed again, and is Ready, Duplicate or Error; one
  bad file never stops the batch, and cancellation returns nothing. Budgets: 64
  files, 128 MiB per file, 256 MiB per batch (every attempt counts), 16 million
  retained samples. A VBO and an RCZ of the same drive are offered as a pair from
  their GPS traces; `automaticVboPrimaries` groups a unique pair dated within 1 s
  (VBO primary, RCZ alternative, channels never fused).
  `nameRunsInRecordingOrder` names runs "Session N" by recording time, undated
  last, and `ImportGeneration` keeps a stale result from being committed.

Every untrusted size is bounded before allocation (`VboLimits`), and long
operations take a `CancellationCheck`.

## Matching FlappedEar Overlays

Both apps must read a file identically: the `.fetproject` fingerprint depends on
channel names and sample counts. The behaviour follows FlappedEar Overlays'
`VboParser.cpp`, `LapTiming.cpp`, `RczParser.cpp`, `TelemetryImportPlan.cpp`, `TelemetryFolderScan.cpp` and `TelemetrySource.cpp` (VBOOverlay `1a96ae3`), re-implemented in
Dart. The handover section "VBO" in VBOOverlay summarises the rules.

`test/parity/cpp_parity_test.dart` checks this file by file. The reference
`test/parity/cpp_reference.json` is the output of Overlays' own C++ code, built in
`tool/cpp_reference_dump`, over the synthetic corpus in `test/parity/corpus` and
the fixtures in `test/fixtures`. Parsed values match exactly; values derived
through trigonometry are compared to 1e-9 relative, because C libraries may
differ in the last bit. See [tool/README.md](tool/README.md) to regenerate it.

Known, deliberate differences:

- **Metadata lines without a separator** are stored as `<section>.<n>`. Overlays
  numbers them in Qt hash order, which Qt seeds per process, so its keys can
  change from run to run. This package numbers them in file order. Metadata is
  not part of the fingerprint.
- **Decoded-memory budget.** Overlays' `maximumDecodedBytes` argument belongs to
  its desktop session cache. The phone budget is decided separately (KAN-129), so
  it is not ported.
- **`timingGateRevision`** (`gates-v1`) is not here; it belongs with the other
  document ids.

## Development

```bash
cd packages/telemetry_core
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Real recordings are private (`FlappedEar/refdata`) and never committed. Point
`FLAPPEDEAR_REAL_VBO` at one to run `test/real_vbo_test.dart`; report its result
separately from the synthetic tests. `FLAPPEDEAR_REAL_RCZ` does the same for
`test/rcz/rcz_parser_test.dart`; it prints summary figures only.
