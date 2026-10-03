#!/usr/bin/env python3
"""Writes the synthetic recordings of the shared round-trip fixtures (FET-40).

Three sessions on the parity corpus's "mixed" track (a kink, an S-bend, two
corners joined by a short straight and two hairpins), driven at different
speeds. Every file is synthetic: no real recording, GPS trace or heart rate.
FlappedEar Overlays' own code builds the committed day from them (see
tool/README.md, cpp_project_roundtrip).

Run from packages/telemetry_core:  python3 tool/generate_roundtrip_fixtures.py
"""
import os

import generate_parity_corpus as corpus

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "fetproject", "test", "fixtures",
                   "roundtrip", "recordings")

MIXED = [
    ("straight", 250.0), ("arc", 200.0, -8.0), ("straight", 15.0), ("arc", 200.0, 8.0),
    ("straight", 60.0), ("arc", 35.0, 90.0), ("straight", 30.0), ("arc", 30.0, -50.0),
    ("arc", 30.0, 50.0), ("straight", 80.0), ("arc", 25.0, 30.0), ("straight", 10.0),
    ("arc", 25.0, -30.0), ("straight", 60.0), ("arc", 15.0, 180.0), ("straight", 70.0),
    ("arc", 15.0, -180.0), ("straight", 60.0),
]

SESSIONS = {
    "morning.vbo": [21.0, 22.0, 21.5],
    "midday.vbo": [21.8, 22.6, 22.1],
    "afternoon.vbo": [22.3, 21.6],
}


def main():
    os.makedirs(OUT, exist_ok=True)
    corpus.OUT = OUT
    track = corpus.closed_track(MIXED)
    for name, speeds in SESSIONS.items():
        corpus.lap_file(name, corpus.track_rows(track, speeds, 10), [corpus.gate_line()])


if __name__ == "__main__":
    main()
