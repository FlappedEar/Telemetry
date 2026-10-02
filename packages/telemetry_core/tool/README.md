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
