#!/usr/bin/env python3
"""Writes the synthetic VBO files of the driving-states parity corpus.

Every file is synthetic: no real recording, GPS trace or heart rate. They
drive the corner track of generate_parity_corpus.py with lateral G as well
as longitudinal G and pedals, so the G-G, driving-state and coasting ports
see every channel combination: measured pedals with a sensor lateral G,
RaceChrono-style "-calc" accelerations, deceleration only (inferred pedals)
and a brake recorded as pressure. tool/cpp_driving_dump is run over these
files (and a few of the main corpus) to produce
test/parity/driving_reference.json.

They live in test/parity/driving, not in the main corpus, so the other
references, which cover every corpus file, stay unchanged.

Run from packages/telemetry_core:  python3 tool/generate_driving_corpus.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import generate_parity_corpus as corpus  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "test", "parity", "driving")


def to_metres(lat, lon):
    north = (lat - corpus.LAT0) * corpus.M_PER_DEG
    east = (lon - corpus.LON0) * corpus.M_PER_DEG * math.cos(math.radians(corpus.LAT0))
    return east, north


def with_lateral(rows):
    """Adds lateral G (+ to the left) from the heading change between the
    neighbouring positions: speed times yaw rate, with a little noise."""
    points = [to_metres(row[1], row[2]) for row in rows]
    headings = []
    for i in range(len(points)):
        (ax, ay), (bx, by) = points[max(0, i - 1)], points[min(len(points) - 1, i + 1)]
        headings.append(math.atan2(by - ay, bx - ax))
    result = []
    for i, row in enumerate(rows):
        before, after = max(0, i - 1), min(len(rows) - 1, i + 1)
        turn = headings[after] - headings[before]
        turn = (turn + math.pi) % (2 * math.pi) - math.pi
        span = rows[after][0] - rows[before][0]
        yaw = turn / span if span > 0 else 0.0
        lateral = row[3] / 3.6 * yaw / 9.81 + 0.006 * math.sin(row[0] * 5.0)
        result.append(tuple(row) + (lateral,))
    return result


def coasting(rows):
    """Lifts off through the corners: the 15 % part throttle of corner_rows
    becomes 3 %, so the measured files coast as well."""
    return [row[:4] + ((3.0 if row[4] == 15.0 else row[4]),) + row[5:] for row in rows]


NAMES = ["time", "latitude", "longitude", "velocity", "throttle", "brake", "longacc", "accuracy", "latacc"]
FORMATS = ["{:.3f}", "{:.8f}", "{:.8f}", "{:.2f}", "{:.1f}", "{:.1f}", "{:.3f}", "{:.2f}", "{:.3f}"]


def driving_file(name, rows, columns, headers=None, drop=None, blanks=(), overrides=()):
    """Writes `rows` with the chosen columns. `headers` renames columns in
    the file; `drop` (start, end) removes whole rows; `blanks` are (start,
    end, column) where that column reads "-"; `overrides` are (time, column,
    value) single-sample values (spikes and outliers)."""
    keep = [NAMES.index(column) for column in columns]
    header = [(headers or {}).get(column, column) for column in columns]
    lines = ["[header]", "coordinate units = degrees", "[laptiming]", corpus.gate_line(),
             "[column names]", " ".join(header), "[data]"]
    for row in rows:
        t = row[0]
        if drop and drop[0] <= t < drop[1]:
            continue
        values = list(row)
        for at, column, value in overrides:
            if abs(t - at) < 1e-6:
                values[NAMES.index(column)] = value
        cells = []
        for k in keep:
            if any(blank[2] == NAMES[k] and blank[0] <= t < blank[1] for blank in blanks):
                cells.append("-")
            else:
                cells.append(FORMATS[k].format(values[k]))
        lines.append(" ".join(cells))
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, name), "w", newline="") as f:
        f.write("\n".join(lines) + "\n")


def main():
    commands = corpus.closed_commands([
        ("straight", 250.0), ("arc", 200.0, -8.0), ("straight", 15.0), ("arc", 200.0, 8.0),
        ("straight", 60.0), ("arc", 35.0, 90.0), ("straight", 30.0), ("arc", 30.0, -50.0),
        ("arc", 30.0, 50.0), ("straight", 80.0), ("arc", 25.0, 30.0), ("straight", 10.0),
        ("arc", 25.0, -30.0), ("straight", 60.0), ("arc", 15.0, 180.0), ("straight", 70.0),
        ("arc", 15.0, -180.0), ("straight", 60.0),
    ])
    points, _ = corpus.path_points(commands)
    radii = corpus.radii(commands)
    laps = [(38.0, 9.0, 8.0, 3.0), (37.0, 8.5, 7.0, 2.8), (38.5, 9.2, 8.5, 3.1)]
    fast = coasting(with_lateral(corpus.corner_rows(points, radii, laps, 20)))
    slow = coasting(with_lateral(corpus.corner_rows(points, radii, laps[:2], 10)))

    # Measured pedals and a sensor lateral G at 20 Hz: a one-sample brake
    # spike, an implausible longitudinal sample and lateral G missing for a
    # second.
    every = ["time", "latitude", "longitude", "velocity", "throttle", "brake", "longacc", "latacc"]
    driving_file("driving_measured.vbo", fast, every,
                 blanks=[(70.0, 71.0, "latacc")],
                 overrides=[(40.0, "brake", 30.0), (60.0, "longacc", 6.5)])
    # RaceChrono-style calculated accelerations at 10 Hz, a brake gap and a
    # GPS gap.
    driving_file("driving_calc.vbo", slow, every,
                 headers={"longacc": "longacc-calc", "latacc": "latacc-calc"},
                 drop=(150.0, 152.0), blanks=[(95.0, 99.0, "brake")])
    # No pedals: braking and accelerating are inferred from longitudinal G.
    driving_file("driving_inferred.vbo", slow,
                 ["time", "latitude", "longitude", "velocity", "longacc", "latacc"])
    # Throttle and a brake pressure but no lateral G.
    driving_file("driving_pressure.vbo", slow,
                 ["time", "latitude", "longitude", "velocity", "throttle", "brake", "longacc"],
                 headers={"brake": "brake_pressure"})


if __name__ == "__main__":
    main()
