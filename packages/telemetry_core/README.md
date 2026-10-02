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

- `dayLapRows` lists one run's OUT, LAP n and IN sections (UNKNOWN when the
  recording has no accepted gate pass), with the clock from the recording;
  `sortDayLaps` orders a day's rows by that clock, undated runs last in import
  order. A lap is identified by `DayLapReference`: its exact bounds in one
  recording's content (SHA-256), never its number.
- `rankDayLaps` ranks the timed laps of one compatibility group
  (`TrackConfiguration.compatibilityGroupId`, the `compatibility-v1` id from
  `packages/fetproject`): best of the day, each run's best with linearly
  interpolated quartiles, ties, and every lap left out with its `LapIssue`s
  (unresolved layout, direction or gates, incomplete or invalid GPS, user
  exclusion, off the recorded route, changed source). Ties order by duration,
  clock, run, start and end. `eligibleDayLaps` is the same eligibility rule for
  later consumers.

- `inferTrack` finds the route a recording's complete laps follow (closed
  within 25 m, 100–30,000 m, resampled to 256 points; clockwise when the signed
  area is negative) and the laps on it; a lap more than 12 m off the other
  laps' line is off the route. `groupInferredTracks` groups runs whose routes
  match (same direction, length within 5 %, cross-track at most 25 m and 10 m
  RMS), complete-link, under a `gps-route-v1:` layout. A manual layout always
  wins.
- `analyzeDay` derives a whole day from its runs: rows, configurations (with
  the `gates-v1` revision of each recording's gates), groups labelled
  "Group 1 · Detected route · Clockwise", the ranking of every group, the
  group shown first (the one with the most eligible laps unless one is
  preferred), and messages. One failing run never stops the others.
- `lapPath` gives a lap section's GPS fixes in metres, with speed, split at
  every gap, for the track map (trace only, no tiles).

- `dayDocument` writes a day as a version 3 `.fetproject` document: each
  run's recording (relative path when close, content SHA-256, `telemetry-v1`
  fingerprint from `telemetryFingerprint`), its manual layout and direction
  or the unknown configuration with its gate revision, the detected route's
  provenance, lap exclusions as full lap references, and the group shown as
  `analysisDecisions.comparisonGroupId`. A document opened earlier keeps
  everything this app does not manage, including runs whose recordings were
  missing. `openDay` reads it back: it finds each recording (relative path
  first, then absolute, or a relinked path), refuses a different recording by
  content or fingerprint, applies exclusions whose recording and derivation key
  still match, and analyses the day. `openDayDocument` does the same for a
  document already in memory.
- `writeDayRecovery` and `readDayRecovery` keep an unsaved day for recovery
  (after Overlays' `ProjectRecoveryStore`): this app's own file, wrapping the
  version 3 document with where the day was last saved, the path its
  relative recording paths are relative to, and the time. `openRecoveredDay`
  opens it. Overlays' discard tombstones are not ported: one app instance
  owns the file.

Every untrusted size is bounded before allocation (`VboLimits`), and long
operations take a `CancellationCheck`.

## Matching FlappedEar Overlays

Both apps must read a file identically: the `.fetproject` fingerprint depends on
channel names and sample counts. The behaviour follows FlappedEar Overlays'
`VboParser.cpp`, `LapTiming.cpp`, `RczParser.cpp`, `TelemetryImportPlan.cpp`, `TelemetryFolderScan.cpp`, `TelemetrySource.cpp`, `OutingLaps.cpp`, `TrackInference.cpp` and `OutingLapDerivation.cpp` (VBOOverlay `1a96ae3`), re-implemented in
Dart. The handover section "VBO" in VBOOverlay summarises the rules.

`test/parity/cpp_parity_test.dart` checks this file by file. The reference
`test/parity/cpp_reference.json` is the output of Overlays' own C++ code, built in
`tool/cpp_reference_dump`, over the synthetic corpus in `test/parity/corpus` and
the fixtures in `test/fixtures`. Parsed values match exactly; values derived
through trigonometry are compared to 1e-9 relative, because C libraries may
differ in the last bit. See [tool/README.md](tool/README.md) to regenerate it.

Known, deliberate differences:

- **Decoded-memory budget.** Overlays' `maximumDecodedBytes` argument belongs to
  its desktop session cache. The phone budget is decided separately (KAN-129), so
  it is not ported.
- **Day lap references** (`OutingLaps.cpp`, VBOOverlay `ca2bde5`) carry the run,
  the content SHA-256, the type and the exact bounds; `dayDocument` adds
  `eventId`, `sourceId` and `derivationKey` when it writes them, and `openDay`
  applies only references whose content and derivation key still match. Progression across runs is not ported yet (FET-5).
- **Detected layout ids** are computed again on opening rather than read from
  the saved `trackInference` provenance. The id is derived from the cluster's
  first run and its content, so it is the same as long as the routes group the
  same way.
- **The group shown first** is the one with the most eligible laps. Overlays
  takes the first resolved group in id order, which is arbitrary; on a day with
  one group both choose the same.
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
