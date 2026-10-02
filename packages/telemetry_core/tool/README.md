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

## cpp_project_check

Opens `.fetproject` documents with FlappedEar Overlays' own C++ code and prints
what Overlays sees: whether the document is valid, each run's recording
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
Last run against FlappedEar/Overlay `d4d1039`: passed.
