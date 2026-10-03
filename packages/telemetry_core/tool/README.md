# Tools

## generate_parity_corpus.py

Writes the synthetic VBO files in `test/parity/corpus`: laps on generated circles,
RaceChrono-style exports, and header, scanner, number, encoding and error edge
cases. No real recording, GPS trace or heart rate.

```bash
python3 tool/generate_parity_corpus.py
```

## day_benchmark.dart

Measures one day of recordings step by step, as the app runs them (FET-41):
parse and import, day analysis, theoretical best and segments, one A/B
comparison (the group's best lap against the next fastest, as the comparison
page first draws it), the Corner Analyzer on the theoretical best's segments,
the channel summaries and the day report. For each step it prints the wall
time, the peak and final resident set (RSS) of the process and, when the VM
service can run, the peak and final heap. Import, analysis, the theoretical
best and the channel summaries run in background isolates as in the app, so
copies into and out of isolates are part of their figures; `--one-isolate`
runs everything on one isolate, for profiling the analysis code alone.

It prints figures only (times, MiB and counts) and a SHA-256 "result digest"
of the results: laps, ranking, comparison series, Corner Analyzer metrics,
channel summaries and the day report. Two runs with the same digest gave
identical results, so a performance change can be checked on real recordings
without printing anything from them.

```bash
# A synthetic day (no recordings needed); this is what CI runs.
dart run tool/day_benchmark.dart --synthetic=6 --laps=12

# Any folder or files, for example a real day. Compile it ahead of time for
# figures close to the phone's (an AOT executable has no VM service, so the
# heap is not sampled; RSS is).
dart compile exe tool/day_benchmark.dart -o /tmp/day_benchmark
/tmp/day_benchmark --runs=2 --json=/tmp/day.json <folder>
```

`test/tool/day_benchmark_test.dart` only checks that it runs on a synthetic
day and that one isolate gives the same digest; it checks no timing.

## cpp_reference_dump

A small C++ program that runs FlappedEar Overlays' own `VboParser` and
`deriveSourceLapSession` over VBO files and writes the results as JSON. It compiles
five files from a read-only VBOOverlay checkout against Qt 6.8 Core. It is not
part of the app or of CI, and nothing here is copied from VBOOverlay.

```bash
# Qt 6.8.3 Core, as in VBOOverlay CI (Linux shown; about 15 s):
python3 -m pip install aqtinstall
python3 -m aqt install-qt linux desktop 6.8.3 linux_gcc_64 -O /opt/Qt --archives qtbase icu
git clone --depth 1 https://github.com/FlappedEar/Overlay /tmp/vbooverlay

cmake -S tool/cpp_reference_dump -B /tmp/dumpbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/dumpbuild
/tmp/dumpbuild/cpp_reference_dump test/parity/cpp_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
```

The committed reference was generated from FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and
g++ 13.3 on Ubuntu 24.04. When Overlays changes its parser or lap timing,
regenerate it and fix the Dart side until `dart test test/parity` passes; never
edit the JSON by hand.

## cpp_progress_dump

Runs FlappedEar Overlays' own `TrackProgress` (`buildProgressAxis`,
`computeTrackFeatures`, `projectLapTrace`, `timeAtProgress`, `progressAtTime`,
`computeDeltaSeries`) and `TelemetrySession::sampledSegments` over VBO files and
writes a summary as JSON. For each file with lap traces it builds the axis from
the first reference-eligible lap trace around the start gate's midpoint (the
origin `LapTiming` uses for lap traces), and writes the axis length, spacing and
every 50th point, track features with 15 m smoothing (every 50th), every timed
lap's projection (segment sizes, first and last sample, every 25th sample, time
at 0, 100 and 500 m, progress at four times), the delta series of the first lap
against the fastest at 5 m steps (counts, ends, every 50th point), and three
`sampledSegments` calls (every 10th point). It compiles six files from a
read-only Overlay checkout against Qt 6.8 Core, like `cpp_reference_dump`.

```bash
cmake -S tool/cpp_progress_dump -B /tmp/progressbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/progressbuild
/tmp/progressbuild/cpp_progress_dump test/parity/progress_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/progress_parity_test.dart
```

The committed `test/parity/progress_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04. Files
without lap traces are left out. Regenerate it when Overlays changes this code;
never edit the JSON by hand.

## cpp_segments_dump

Runs FlappedEar Overlays' own `TrackSegments`, `TrackSegmentProposals` and
`TrackSegmentReview` over VBO files and fixed cases and writes the results as
JSON. For every timed lap of each file with lap traces it follows
`AnalysisController::computeSegmentReview` (axis from the lap's own trace
around the start gate's midpoint, features with 6 m smoothing, the lap
projected, `coverageGaps`, `proposeTrackSegments`) and then the automatic
approval loop (KAN-136) twice, the second time over the first result; segment
ids are random and left out. On the first reference-eligible lap's axis it
also writes the proposals with each lap's coverage gaps and with eight option
and gap variants. The cases section holds `validTrackSegments`,
`progressRangesOverlap`, `withApprovedSegment` and `approvedSegmentation` with
their inputs. `coverageGaps` and the approval loop are in Overlays' app
sources, which need Qt Quick: CMake copies their text out of the checkout into
the build directory at configure time, so the tool still runs Overlays' code
and nothing of it is committed here.

```bash
cmake -S tool/cpp_segments_dump -B /tmp/segmentsbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/segmentsbuild
/tmp/segmentsbuild/cpp_segments_dump test/parity/segments_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/segments_parity_test.dart
```

The committed `test/parity/segments_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04. The
corpus's `segments_*.vbo` tracks (a rounded rectangle, and a track with a kink,
a short straight, an S-bend, two corners 10 m apart and two hairpins, also
mirrored and with a GPS gap) were added for it; `cpp_reference.json` and
`progress_reference.json` were regenerated with them and are unchanged for
the other files. To check other recordings locally, write a reference for them
and run the test with `FET_SEGMENTS_REFERENCE=<json>` and
`FET_SEGMENTS_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the largest
difference. Never edit the JSON by hand.

## cpp_segment_editing_dump

Runs FlappedEar Overlays' own `TrackSegmentEditing` and the rest of
`TrackSegmentReview` over VBO files and fixed cases and writes the results
as JSON. For each file with lap traces it takes the first reference-eligible
lap, follows `computeSegmentReview` and the automatic approval loop (as
`cpp_segments_dump`), renames the approved ids `s0`, `s1`, ... and edits that
set: every segment renamed and retyped, its start moved back and its end on
with the neighbour, its end on without it, shrunk, split in the middle,
merged with the next one and removed, and a chain of seven edits each on the
last result. It writes the review states of the proposals against the
automatic and the edited set and the stored rejections. A split mints a
random id; ids not in the input are renamed `n0`, `n1`, ... on both sides.
The cases section holds the editing functions on hand-made sets (overlap,
empty, gate crossings, other configurations, the 64-segment bound),
`validProposalEdit`, `withoutOtherConfigurations`, `validTrackSegmentReview`,
result stamps, `SegmentEditHistory`, `pickProgressAt` and
`reviewSegmentProposals` with their inputs.

```bash
cmake -S tool/cpp_segment_editing_dump -B /tmp/editbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/editbuild
/tmp/editbuild/cpp_segment_editing_dump test/parity/segment_editing_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/segment_editing_parity_test.dart
```

The committed `test/parity/segment_editing_reference.json` was generated
from FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04;
the other references are unchanged. To check other recordings locally, run
the test with `FET_EDITING_REFERENCE=<json>` and
`FET_EDITING_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the largest
difference. Never edit the JSON by hand.

## cpp_project_check

Opens `.fetproject` documents with FlappedEar Overlays' own C++ code and prints
what Overlays sees: whether the document is valid, each run's approved
segments (valid, count and revision), its segment review's rejections (valid,
count), each run's recording
(resolved path, `telemetry-v1` fingerprint match, content SHA-256), lap
derivation key and track configuration, its source-fusion decision as Run
details judges it, the laps its exclusions apply to with
Overlays' own lap timing, and whether an Overlays re-save keeps the event
unchanged. It compiles Overlays' `project/` and `telemetry/` sources from a
read-only checkout against Qt 6.8 Core, like `cpp_reference_dump` above. Not
part of the app or of CI.

```bash
cmake -S tool/cpp_project_check -B /tmp/checkbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/checkbuild
FLAPPEDEAR_OVERLAYS_CHECK=/tmp/checkbuild/cpp_project_check \
  dart test test/day/overlays_check_test.dart
```

The test saves a synthetic day with a circuit name and an excluded lap and
checks that Overlays reads all of it. It is skipped when the variable is not set.
The test also checks that the chosen group's best lap got automatic segments,
which Overlays accepts, and saves a day whose segments were split, merged,
moved, renamed and removed (`DaySegmentEdits`), with the removed segment's
proposal rejected in the segment review (FET-56): Overlays reads the same
segment revision and a valid `trackSegmentReview`, and keeps them on re-save.
A third test saves a synthetic VBO/RCZ pair fused automatically with a channel rule (FET-51): Overlays
validates the run's `fusion` decision, applies it ("applied": both recordings'
content revisions match), keeps it on re-save, and reports a decision bound to
other content as "needsRevalidation". Last run against FlappedEar/Overlay
`d4d1039`: passed.

## cpp_project_roundtrip

Drives FlappedEar Overlays' own document and analysis controllers headless,
as Overlays' `TelemetryAppTests` do: `TelemetryController` with its
`DocumentController` and `AnalysisController`, automatic segments on as in
the Overlays app. It compiles every file of Overlays' `project/` and
`telemetry/` sources and the controllers of `app/` (Overlays'
`flappedear_telemetry_core` and `flappedear_telemetry_app`) from a read-only
checkout against Qt 6.8 Core and Concurrent and the system zlib. Not part of
the app or of CI.

```bash
cmake -S tool/cpp_project_roundtrip -B /tmp/rtbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/rtbuild -j4
FLAPPEDEAR_OVERLAYS_ROUNDTRIP=/tmp/rtbuild/cpp_project_roundtrip \
  dart test test/day/overlays_roundtrip_test.dart
```

Commands (each prints JSON):

- `fingerprint <recording>...`: Overlays' `telemetry-v1` fingerprint of
  each VBO or RCZ recording (`TelemetrySource::load`,
  `ProjectSourceReferenceCodec::telemetryFingerprint`), or Overlays' error.
- `create <project> <name> <recording>...`: Overlays imports the
  recordings as a day ("Session N"), approves the best lap's segments
  automatically, renames one segment and merges two in the segment review,
  excludes a lap ("Traffic"), writes notes, conditions and setup changes on
  the first session, saves the group shown, the comparison pair, range and
  channels, and saves the day. The overlay editor's state (a session's sync
  and video, the chart channels, the widget scene) is then added as
  Overlays' `TelemetryAppTests` add it, and Overlays opens and saves the day
  once more. Prints `inspect` of the result.
- `resave <project> [<target>]`: Overlays opens the day and saves it (Save
  As to `<target>`). Prints `inspect` of the day as opened and as saved.
- `metadata <project> <target> <run> <name> <notes> <conditions> <setupChanges>`:
  Overlays opens the day, edits the run at index `<run>` with its own
  `AnalysisController::updateRunMetadata` (as its session details editor
  does) and saves the day at `<target>`. Prints `inspect` of the result.
- `inspect <project>...`: what Overlays sees: validity, `documentState`,
  each run's name, notes, conditions, setup changes and approved segments
  (count, names, revision), every lap section ("Session 2 · LAP 3", times,
  group, exclusion and reason), the group shown and the day report's best
  lap, theoretical best and number of eligible laps, and the comparison
  Overlays restores (FET-53): each slot's lap and state, whether the pair
  is ready, and the saved range and charts. Each run also lists its
  recordings (source id, format, primary, available) and, with a `fusion`
  decision, what Overlays does with it (FET-55): `state` as Run details
  shows it ("applied" or "needsRevalidation"), the `decision`, whether the
  analysis applies it, the fused session as Overlays' analysis loads it
  (`loadOutingLapDetail`: every channel's name, unit, sample count and
  FNV-1a digest, as `cpp_fusion_dump` writes them) and the `origins`, the
  channels taken from the alternative with their rule (`fuseChannels` with
  the decision's clock and rules).
- `import <project> <name> <recording>...`: Overlays imports the recordings
  as a day and saves it, nothing else. Prints `inspect`.
- `attach <project> <run> <recording>`: Overlays adds the recording to the
  run (its id or 1-based position) as an alternative, as Run details does
  (KAN-90: `attachRunRecording`, the match evidence, `confirmRunRecording`),
  and saves the day. Prints the evidence and `inspect`.
- `compare <project> <lap A> <lap B> <start> <end> [<channel>...]`:
  Overlays compares the two laps ("Session 1 · LAP 3", `selectComparisonLap`),
  then saves the range in meters and the charts as its comparison view does
  (`persistComparisonRange`, `persistComparisonChannels`), and saves the
  day. Prints `inspect`.
- `fuse <project> <run> [<channel key>=<rule>...]`: Overlays reviews fusing
  the run's alternative recording (KAN-103: `reviewRunFusion`) and approves
  it with the rules (`approveRunFusion`; `primaryOnly`, `fillGaps` or
  `preferAlternative`; `*=<rule>` for every other conflicting channel, as
  Overlays needs a rule for each), and saves the day. Prints the alignment,
  the review's channels and conflicts, and `inspect`.
- `primary <project> <run>`: Overlays makes the run's other recording its
  primary, as Run details' "Make primary" does (KAN-90:
  `setRunPrimarySource`), and saves the day. Prints the new primary source
  id and `inspect`.
- `unfuse <project> <run>`: Overlays removes the run's fusion, as Run
  details' "Remove fusion" does (KAN-103: `removeRunFusion`), and saves the
  day. Prints `inspect`.
- `clock <project> <run>`: Overlays compares the clocks of the run's other
  recording and its primary, as Run details' "Check clock" does (KAN-101:
  `checkRunRecordingAlignment`), and prints the alignment (status, reason,
  offset, uncertainty, drift, correlation, windows, declared offset).
  Nothing is saved.

`test/day/overlays_roundtrip_test.dart` (skipped unless
`FLAPPEDEAR_OVERLAYS_ROUNDTRIP` is set) runs both directions on the shared
fixtures' recordings:

- **Telemetry → Overlays → Telemetry.** Telemetry saves a day with edited
  segments (renamed, split, merged), an exclusion and the group shown, then
  with notes, conditions and unknown keys in open objects (top level,
  `documentState`, event, `analysisDecisions`, run, source, reference) that
  were already in the document. Overlays opens it and reports the same
  sessions, laps, exclusions, group, segments and results; its save differs
  from Telemetry's only by its own `mapSettings` and `exportSettings`
  defaults (so no closed object gains a key) and keeps `documentState`.
  Telemetry opens it again with the same day and results, and its next save
  keeps everything Overlays wrote, with `savedRevision` one higher.
- **Session details** (FET-52). The same edits of a session's name, notes,
  conditions and setup changes (spaces around a name, texts with spaces, a
  blank text on a record without it, a cleared text, Polish text and symbols)
  made in Telemetry and by Overlays' `updateRunMetadata` on the same day give
  the same document, and each app sees the other's edit, laps named after
  it. A day Telemetry renamed opens in Overlays with its name, and Overlays'
  save keeps it.
- **Overlays → Telemetry → Overlays.** `create` builds a day; Telemetry
  opens it with the same sessions, laps, exclusions, group, segments and
  results, and its save equals Overlays' document but for `savedRevision`
  (one higher, the same `id`) and the order of `lapExclusions`. Overlays
  inspects it and sees the same day.

`test/day/overlays_comparison_roundtrip_test.dart` (also skipped unless
`FLAPPEDEAR_OVERLAYS_ROUNDTRIP` is set) checks the comparison decisions
(FET-53) on the shared recordings: a day Overlays imported without choosing
a group has no `analysisDecisions` and stays "automatic" after Telemetry
saves it; the pair, range and charts Telemetry saves are the comparison
Overlays restores (both slots ready) and keeps on its save; and the
comparison Overlays sets up (`compare`) opens in Telemetry with the same
laps, range and charts, survives Telemetry's save unchanged, and Overlays
restores it again.

`FET_ROUNDTRIP_RECORDINGS=<folder>` runs both on other recordings (VBO, or
RCZ with `FET_ROUNDTRIP_EXTENSION=.rcz`), for example a real day; never commit
their output. `FET_PARITY_REPORT=1` prints counts.

`test/day/overlays_fusion_roundtrip_test.dart` (also skipped unless
`FLAPPEDEAR_OVERLAYS_ROUNDTRIP` is set) checks a fusion Overlays decided
(FET-55): Overlays imports the synthetic VBO of `writeFusionPair`
(`test/support/fusion_pair.dart`), attaches its RCZ and approves the fusion
with `sats=preferAlternative`. Telemetry opens the day with the same
sessions and laps and applies the decision without aligning again: the same
clock and rules, the same origins (`rpm-obd` added, `sats`
preferAlternative) and bit-identical fused channels. Telemetry's re-save is
Overlays' document with `savedRevision` one higher (and the group still
"automatic" in Overlays). Overlays inspects Telemetry's save with the same decision
applied. `FET_FUSION_ROUNDTRIP_DAY=<folder>` does the same for every VBO/RCZ
pair of a folder (each conflicting channel `primaryOnly`), for example a
real day; it prints counts only.

`test/day/overlays_primary_roundtrip_test.dart` (also skipped unless
`FLAPPEDEAR_OVERLAYS_ROUNDTRIP` is set) checks a run's recordings (FET-57)
on the same synthetic pair, fused by Overlays: a primary Overlays made
(`primary`) opens in Telemetry with the RCZ as the run and the VBO kept
beside it, and Telemetry's re-save is Overlays' document; Telemetry making
the RCZ primary on a copy of the day writes the document Overlays' `primary`
writes, and Overlays sees the same day in it; Telemetry refusing the
alignment writes the document Overlays' `unfuse` writes; and Telemetry's
clock check measures what Overlays' `clock` measures, and accepting it saves
the decision Overlays approved.

The committed day in `../fetproject/test/fixtures/roundtrip` was built by
`create` from FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on
Ubuntu 24.04, in `/tmp/flappedear-roundtrip` (its absolute paths), from the
recordings `tool/generate_roundtrip_fixtures.py` writes:

```bash
python3 tool/generate_roundtrip_fixtures.py
mkdir -p /tmp/flappedear-roundtrip/recordings
cp ../fetproject/test/fixtures/roundtrip/recordings/*.vbo /tmp/flappedear-roundtrip/recordings/
cd /tmp/flappedear-roundtrip && /tmp/rtbuild/cpp_project_roundtrip create \
  overlays-day.fetproject "Synthetic day" recordings/morning.vbo \
  recordings/midday.vbo recordings/afternoon.vbo > overlays-day.inspected.json
```

then copy `overlays-day.fetproject` and `overlays-day.inspected.json` there.
`test/day/overlays_fixture_test.dart` (pure Dart, in CI) opens it and checks
Telemetry sees what Overlays reported, and that Telemetry's re-save keeps
every field. Never edit either file by hand.

`test/parity/fingerprint_reference.json` is `fingerprint` over every
recording of `test/parity/corpus`, `test/parity/driving`,
`test/parity/rcz_corpus` (synthetic RCZ archives written by
`dart run test/parity/write_rcz_corpus.dart`), `test/fixtures` and the shared
round-trip recordings, run from this package:

```bash
/tmp/rtbuild/cpp_project_roundtrip fingerprint test/parity/corpus/*.vbo \
  test/parity/driving/*.vbo test/fixtures/*.vbo test/parity/rcz_corpus/*.rcz \
  ../fetproject/test/fixtures/roundtrip/recordings/*.vbo \
  > test/parity/fingerprint_reference.json
dart test test/parity/fingerprint_parity_test.dart
```

`FET_FINGERPRINT_REFERENCE=<json>` checks another reference, for example one
made locally for private recordings (never committed).

Last run against FlappedEar/Overlay `d4d1039`: all passed (see the FET-40
pull request for the counts on the real day).

## cpp_theoretical_best_dump

Runs FlappedEar Overlays' own `SectorTiming`, `TheoreticalBest`, `TimeLoss`,
`Consistency` and `OutingTheoreticalBestResults` (`publishTheoreticalBest`,
`publishTimeLossRanking`) over VBO files and fixed cases and writes the
results as JSON. Each file becomes a day of two runs (its odd and its even
reference-eligible laps). The fastest lap's segment proposals are approved
into its run with ids `s0`, `s1`, ..., and also shifted 37 m (the last one
crossing the gate) and thinned to every other segment. For each set it picks
the canonical run as `requestOutingTheoreticalBest` does and follows the loop
of `calculateOutingTheoreticalBest` with the sessions in memory (one axis
from the canonical run's fastest lap, every lap projected and timed; the
corner metrics are left out), and writes every lap's sector times, the
theoretical best, the published theoretical best (map thinned to part sizes,
end points and every 50th outline point), both time-loss rankings, one lap's
loss windows and sector comparisons. The cases section times hand-made
projections (wrapping segments, gaps, gate tolerance, other revisions).

```bash
cmake -S tool/cpp_theoretical_best_dump -B /tmp/tbbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/tbbuild
/tmp/tbbuild/cpp_theoretical_best_dump test/parity/theoretical_best_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/theoretical_best_parity_test.dart
```

`--day <day.json> <output.json>` runs the same calculation for a real day
described in a file: `runs` (`runId`, VBO `file`), the eligible laps
(`population`: `runId`, `lapNumber`, `start`, `end`), each run's stored
`segments` (with the tool's configuration reference) and the `actualBest`
(`runId`, `lapNumber`). Use it locally to compare a day's theoretical best
with the app's; never commit its input or output.

The committed `test/parity/theoretical_best_reference.json` was generated
from FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04.
To check other recordings locally, run the test with
`FET_TB_REFERENCE=<json>` and `FET_TB_DIRS=<dir>[:<dir>]`;
`FET_PARITY_REPORT=1` prints the largest difference. Never edit the JSON by
hand.

## cpp_corner_metrics_dump

Runs FlappedEar Overlays' own Corner Analyzer (`CornerPhases`,
`CornerSpeeds`, `BrakingOnset`, `BrakingMetrics`, `ExitMetrics`,
`DrivingVariability` and the variability of `publishTheoreticalBest`) over
VBO files and fixed cases and writes the results as JSON. Each file becomes
the same day of two runs with the same three segment sets as in
`cpp_theoretical_best_dump`. For each set it follows the loop of
`calculateOutingTheoreticalBest` and writes the geometric phases of every
segment, every lap's `computeCornerSpeeds`, `computeBrakingMetrics` and
`computeExitMetrics` of every corner in full, the KAN-63 observations (in
segment order), the published variability and each lap compared with the
best lap; the shared axis is written in full so the Dart side can measure on
exactly the same axis. The cases section runs the onset detector and the
braking and exit metrics on hand-made sessions and projections (channels
measured, inferred, missing, with a gap, NaN and unit mismatches), and
`lateralOffsetMeters` and `summarizeCornerVariability` on fixed inputs.

```bash
cmake -S tool/cpp_corner_metrics_dump -B /tmp/cornerbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/cornerbuild
/tmp/cornerbuild/cpp_corner_metrics_dump test/parity/corner_metrics_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/corner_metrics_parity_test.dart
```

`--day <day.json> <output.json>` does the same for a real day described as
for `cpp_theoretical_best_dump`; never commit its input or output.

The committed `test/parity/corner_metrics_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04. The
corpus's `corners_*.vbo` laps (the mixed track driven with braking before
and acceleration after each corner: throttle, brake, longitudinal G and GPS
accuracy with a brake spike; longitudinal G only; and with a GPS gap and
missing brake data) were added for it;
`cpp_reference.json`, `progress_reference.json`, `segments_reference.json`
and `theoretical_best_reference.json` were regenerated with them and are
unchanged for the other files. To check other recordings locally, run the
test with `FET_CORNER_REFERENCE=<json>` and `FET_CORNER_DIRS=<dir>[:<dir>]`;
`FET_PARITY_REPORT=1` prints the largest difference. Never edit the JSON by
hand.

## cpp_progression_dump

Runs FlappedEar Overlays' own `rankOutingLaps`, `summarizeOutingProgression`,
`eligibleOutingLaps`, `Consistency`, `publishTimeLossRanking` and
`publishSectorProgression` over VBO files and fixed cases and writes the
results as JSON. Each file with laps becomes the day of two runs of
`cpp_theoretical_best_dump`, timed against the fastest lap's proposals and
the same shifted 37 m, and gets its section progression (runs listed in a
fixed order with a run without laps) and both time-loss rankings with corner
names. All inputs together form one day of runs (`outingLapRows`, sorted by
`sortOutingLaps`) on two track configurations and an unresolved one, with a
user exclusion, a stale run and run notes, conditions and setup changes; for
each group it writes the ranking, the progression and the lap consistency of
`AnalysisController::outingLapConsistency` (an app member function, so the
tool repeats its few lines over Overlays' `summarizeConsistency`). The cases
section holds `summarizeConsistency` on fixed values and the section
progression and time losses of hand-made laps (runs of up to five laps, so
the statistics are available).

```bash
cmake -S tool/cpp_progression_dump -B /tmp/progressionbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/progressionbuild
/tmp/progressionbuild/cpp_progression_dump test/parity/progression_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/progression_parity_test.dart
```

`--day <day.json> <output.json>` does the same for a real day described as
for `cpp_theoretical_best_dump` (each run also with its `name`; every run
gets the same configuration); never commit its input or output.

The committed `test/parity/progression_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. To check other recordings locally, run the
test with `FET_PROGRESSION_REFERENCE=<json>` and
`FET_PROGRESSION_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the
largest difference. Never edit the JSON by hand.

## cpp_dayreport_dump

Runs FlappedEar Overlays' own `ChannelSummary`, `TemperatureAssociation`,
`summarizeOutingChannels`, `FocusAreas`, `DayReport` and
`buildOutingDayReport` over VBO files and fixed cases and writes the results
as JSON. Each file with laps becomes the day of two runs of
`cpp_theoretical_best_dump` (on one track configuration, half of the laps
excluded by the user), timed against the fastest lap's proposals, the same
shifted 37 m and every other one, as `AnalysisController::computeOutingDayReport`
does: ranking, progression, lap consistency, theoretical best with corner
observations, time losses, section progression, channel summaries and the
focus inputs, assembled into the day report; it also writes the selected
focus areas, the channel summaries and the temperature associations of
`AnalysisController::outingTemperatureAssociations` (an app member function,
so the tool repeats its lines). The first file also gets reports in every
other state (loading, not calculated, failed, unavailable, stale, without
focus inputs, without a group, every lap's losses). Overlays'
`loadOutingLapDetail` reads recordings from a project; the tool defines it
over the sessions it holds in memory. The cases section holds channel
summaries, combinations, placeholders and cooling of a hand-made session,
rank correlations, associations and strong acceleration, focus areas of
hand-made and generated inputs, built and validated report documents, and a
hand-made day of four runs with temperatures (placeholder zeros, a glitch, a
gap), heart rate and longitudinal acceleration, one run without a recording
and one without those channels.

```bash
cmake -S tool/cpp_dayreport_dump -B /tmp/dayreportbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/dayreportbuild
/tmp/dayreportbuild/cpp_dayreport_dump test/parity/dayreport_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/dayreport_parity_test.dart
```

`--day <day.json> <output.json>` does the same for a real day described as
for `cpp_progression_dump`, optionally with each run's `sourceRevision`, the
group's `trackConfiguration` and `groupLabel`, and the segments'
`configuration` reference; never commit its input or output.

The committed `test/parity/dayreport_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. To check other recordings locally, run the
test with `FET_DAYREPORT_REFERENCE=<json>` and
`FET_DAYREPORT_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the
largest difference. Never edit the JSON by hand.

## cpp_comparison_dump

Runs FlappedEar Overlays' own `TrackProgress`, `TrackGeometry`, `MapLayers`
and `ChannelSummary` with the comparison, map-layer and lap-chart functions
of its app (`AnalysisControllerComparison.cpp`,
`AnalysisControllerMapLayers.cpp`, `comparisonPreferredChannels` and
`sessionSeries`; app member functions, so the tool repeats their lines) over
VBO files and fixed cases and writes the results as JSON. Each file with lap
traces, a start gate and an eligible lap gets pairs of its own laps (the
first eligible lap against the fastest, the swap, and the last eligible lap
against the second; a single eligible lap against itself), and a few
corpus files of one track are compared across files. For each pair it
follows the comparison of `AnalysisController`: the shared axis from lap A's
trace and start gate, both projections, the shared map geometry and both
overlay tracks, the available and preferred channels, the Δ time by
progress over seven ranges, channel series by progress on both laps
(including a missing channel, the gear and invalid ranges), both laps'
positions and times at 42 progress values, the map-layer options and every
layer on both laps (and an unknown layer and slot), and lap A's lap-detail
charts on a time axis, values at the cursor and its own map. Series points
are written every 4th and map points every 16th (`strides`), with each run's
last point. The cases section runs `channelAlongProgress`, `placeOnMap`,
`plausibleChannelValue`, `currentTrackPoint`, `buildTrackSegments` and
`buildSharedTrackGeometry` on the hand-made straight runs of
`MapLayersTests.cpp` (one with a GPS gap, one west-positive).

```bash
cmake -S tool/cpp_comparison_dump -B /tmp/comparisonbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/comparisonbuild
/tmp/comparisonbuild/cpp_comparison_dump test/parity/comparison_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/comparison_parity_test.dart
```

`--day <day.json> <output.json>` compares chosen laps of a real day, writing
every point: `runs` (`runId`, VBO `file`) and `pairs` (`a` and `b`, each a
`runId` and `lapNumber`). Use it locally only; never commit its input or
output. Run the test against it with `FET_COMPARISON_REFERENCE=<json>` and
`FET_COMPARISON_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the number
of values compared, the mismatches and the largest difference.

The committed `test/parity/comparison_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. Never edit the JSON by hand.

## cpp_corner_analyzer_dump

Runs FlappedEar Overlays' own Corner Analyzer of two compared laps
(`comparisonSharedSegmentation`, `comparisonApprovedSegments`,
`comparisonSegmentMetrics`, `comparisonTimeLossObservations` and
`comparisonHeartRate` of `AnalysisControllerCornerAnalyzer.cpp` and
`AnalysisControllerChannelSummaries.cpp`; app member functions, so the tool
repeats their lines over Overlays' `TrackProgress`, `SectorTiming`,
`TimeLoss`, `CornerPhases`, `CornerSpeeds`, `BrakingMetrics`, `ExitMetrics`
and `ChannelSummary`) over VBO files and fixed cases and writes the results as
JSON. Pairs are chosen as in `cpp_comparison_dump`, with a few more across
corpus files of one track. Each pair is analysed with three segment sets
approved on both laps: the automatic proposals of the file's fastest lap
(ids `s0`, `s1`, ...), the same shifted 37 m and every other one. For every
segment it writes the row, the A/B/Δ metrics, the heart rate over the
segment and the per-lap figures behind them (segment speeds, the corner's
geometric phases, corner speeds, braking and exit metrics in full), then an
unknown segment's metrics and the time-loss observations; the shared axis is
written in full so the Dart side measures on exactly the same axis. The cases
section holds `comparisonSharedSegmentation` on fixed stored segments (same,
different, canonical, other configuration, empty, malformed and missing, with
and without the theoretical best's group) and hand-made pairs on a 2 km
circle: sessions with measured, inferred, undeclared, mismatched and missing
channels, heart rate with zeros, a glitch and NaN, projections with a gap and
a late end, a partition and a set across the gate, and heart rate over six
ranges (one across start/finish, one outside the axis, one empty).

```bash
cmake -S tool/cpp_corner_analyzer_dump -B /tmp/analyzerbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/analyzerbuild
/tmp/analyzerbuild/cpp_corner_analyzer_dump test/parity/corner_analyzer_reference.json \
  test/parity/corpus/*.vbo test/fixtures/*.vbo
dart test test/parity/corner_analyzer_parity_test.dart
```

`--day <day.json> <output.json>` analyses chosen laps of a real day: `runs`
(`runId`, VBO `file`), `pairs` (`a` and `b`, each a `runId` and `lapNumber`)
and `segmentsFrom` (the `runId` and `lapNumber` whose automatic proposals
give the segment sets). Use it locally only; never commit its input or
output. Run the test against it with `FET_ANALYZER_REFERENCE=<json>` and
`FET_ANALYZER_DIRS=<dir>[:<dir>]`; `FET_PARITY_REPORT=1` prints the number of
values compared, the mismatches and the largest difference.

The committed `test/parity/corner_analyzer_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. Never edit the JSON by hand.

## cpp_driving_dump

Runs FlappedEar Overlays' own `GgPairs`, `DrivingStates` and
`CoastingAnalysis` with the G-G and trail-braking functions of its app
(`comparisonGgScatter` and `comparisonTrailBraking` of
`AnalysisControllerCornerAnalyzer.cpp`; app member functions, so the tool
repeats their lines) over VBO files and fixed cases and writes the results
as JSON. For every timed lap and the whole recording of each file it writes
the G-G pairs, peaks and thinned points, the driving states (also with
inference disabled), braking while cornering with its distance, and coasting
without and with a lap trace and four fixed approved segments (the last
across start/finish). Pairs of laps are chosen as in `cpp_comparison_dump`;
for each, the G-G scatter over six ranges, trail braking over five (one
across start/finish) and both laps' driving states and coasting over two, as
`comparisonDrivingStates` computes them. The cases section runs the
hand-made sessions of `GgPairsTests.cpp` and `DrivingStatesTests.cpp` (and a
few more) with several options. G-G points are written every 4th
(`strides`), with the last.

The synthetic recordings of `test/parity/driving` are written by
`tool/generate_driving_corpus.py` (the corner track of the main corpus with
lateral G); they are kept out of `test/parity/corpus` so the other
references stay unchanged.

```bash
python3 tool/generate_driving_corpus.py
cmake -S tool/cpp_driving_dump -B /tmp/drivingbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/drivingbuild
/tmp/drivingbuild/cpp_driving_dump test/parity/driving_reference.json \
  test/parity/driving/*.vbo test/parity/corpus/corners_*.vbo \
  test/parity/corpus/acceleration_aliases.vbo test/parity/corpus/laps_clean.vbo \
  test/fixtures/*.vbo
dart test test/parity/driving_parity_test.dart
```

`--day <day.json> <output.json>` checks a real day, writing every point:
`runs` (`runId`, VBO `file`) and optionally `pairs` (`a` and `b`, each a
`runId` and `lapNumber`); without `pairs`, each run's own pairs and its first
eligible lap against the next run's are compared. Use it locally only;
never commit its input or output. Run the test against it with
`FET_DRIVING_REFERENCE=<json>` and `FET_DRIVING_DIRS=<dir>[:<dir>]`;
`FET_PARITY_REPORT=1` prints the number of values compared, the mismatches
and the largest difference.

The committed `test/parity/driving_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. Never edit the JSON by hand.

## cpp_fusion_dump

Runs FlappedEar Overlays' own `TelemetrySyncEngine`, `RecordingAlignment`
(`recording-alignment-v1`) and `ChannelFusion` (`channel-fusion-v1`) over
fixed synthetic cases and writes the results as JSON: `synchronize` on four
pairs and the confidence levels; `alignRecordings` on a clean offset (with
and without a declared clock, and negative), a lap-away match measured only
and resolved by the declared clock, an agreeing and a conflicting declared
clock, drift (positive, negative, implausible, three windows), a clock step,
periodic, flat and unrelated traces, no speed, insufficient overlap and too
few samples; `fuseChannels` and `fusedSession` on the sessions of
`ChannelFusionTests.cpp` under no rule, `primaryOnly`, `fillGaps` and
`preferAlternative` (with drift and a fractional offset), unresolved
conflicts, refused sources, unit mismatches and case, two alternatives,
alias and name clashes, temperatures and missing values; and
`fusionConflictTolerance` for fixed units. `inputs` holds a digest of every
input session. The synthetic traces use a sine made of `+ - * /` and
`floor` only, so the Dart test builds bit-identical inputs on any platform.
A channel's samples are written as a digest (FNV-1a over the bytes of every
timestamp and value) and every 25th sample.

Overlays ranks the coarse offsets by `std::atanh`. On x86-64 CPUs with FMA,
glibc 2.39 switches `log1p` (which `atanh` calls) to an FMA build that differs
from the generic one in the last bit for about one argument in 10 000; the
Dart port (`lib/src/fusion/atanh.dart`) reproduces the generic build. Generate
the reference with the generic build, as below; the committed reference is
byte-identical with and without the FMA build.

```bash
cmake -S tool/cpp_fusion_dump -B /tmp/fusionbuild -DCMAKE_BUILD_TYPE=Release \
  -DVBOOVERLAY_DIR=/tmp/vbooverlay -DCMAKE_PREFIX_PATH=/opt/Qt/6.8.3/gcc_64
cmake --build /tmp/fusionbuild
GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA \
  /tmp/fusionbuild/cpp_fusion_dump test/parity/fusion_reference.json
dart test test/parity/fusion_parity_test.dart
```

`--pairs <pairs.json> <output.json>` checks real recordings:
`{"pairs": [{"primary": <VBO path>, "alternative": <RCZ path>}]}`, each
parsed with Overlays' `VboParser` and `RczParser`, aligned, and fused (when
there is a measured offset) with no rules and with `fillGaps` for every
channel both recorded. `test/fusion/real_fusion_test.dart` finds the pairs
of a folder with the import plan (`automaticVboPrimaries`), writes them for
the tool and compares the tool's output; it prints summary figures only.
Use it locally only; never commit its input or output.

```bash
FET_FUSION_DAY=<folder> FET_FUSION_PAIRS_OUT=/tmp/pairs.json \
  dart test test/fusion/real_fusion_test.dart -r expanded
GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX2,-FMA \
  /tmp/fusionbuild/cpp_fusion_dump --pairs /tmp/pairs.json /tmp/fusion_day.json
FET_FUSION_DAY=<folder> FET_FUSION_REFERENCE=/tmp/fusion_day.json \
  dart test test/fusion/real_fusion_test.dart -r expanded
```

The committed `test/parity/fusion_reference.json` was generated from
FlappedEar/Overlay `d4d1039` with Qt 6.8.3 and g++ 13.3 on Ubuntu 24.04; the
other references are unchanged. Never edit the JSON by hand.
