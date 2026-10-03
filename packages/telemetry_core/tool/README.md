# Tools

## generate_parity_corpus.py

Writes the synthetic VBO files in `test/parity/corpus`: laps on generated circles,
RaceChrono-style exports, and header, scanner, number, encoding and error edge
cases. No real recording, GPS trace or heart rate.

```bash
python3 tool/generate_parity_corpus.py
```

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
segments (valid, count and revision), each run's recording
(resolved path, `telemetry-v1` fingerprint match, content SHA-256), lap
derivation key and track configuration, the laps its exclusions apply to with
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
moved, renamed and removed (`DaySegmentEdits`): Overlays reads the same
segment revision and keeps them on re-save. Last run against
FlappedEar/Overlay `d4d1039`: passed.

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
