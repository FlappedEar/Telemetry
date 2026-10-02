#!/usr/bin/env python3
"""Writes the synthetic VBO files of the parity corpus.

Every file is synthetic: no real recording, GPS trace or heart rate. The C++
reference dump (tool/cpp_reference_dump) is run over these files to produce
test/parity/cpp_reference.json, and the Dart tests compare against it.

Run from packages/telemetry_core:  python3 tool/generate_parity_corpus.py
"""
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "test", "parity", "corpus")
LAT0, LON0 = 52.0, 21.0
M_PER_DEG = 6371000.0 * math.pi / 180.0


def to_degrees(east, north):
    lat = LAT0 + north / M_PER_DEG
    lon = LON0 + east / (M_PER_DEG * math.cos(math.radians(LAT0)))
    return lat, lon


def write(name, text, mode="w"):
    path = os.path.join(OUT, name)
    if mode == "wb":
        with open(path, "wb") as f:
            f.write(text)
    else:
        with open(path, "w", newline="") as f:
            f.write(text)


def loop_rows(radius, speeds, rate_hz, clockwise=False, laps_extra=0.5, start_time=0.0):
    """Drives a circle through the gate at the origin, starting before it.

    The circle's centre is (-radius, 0), so the car passes (0, 0) heading north
    (counterclockwise) or south (clockwise). `speeds` gives one speed in m/s
    per lap; the run ends `laps_extra` of a lap after the last listed lap.
    """
    rows = []
    t = start_time
    angle = -0.25  # radians before the gate
    sign = -1.0 if clockwise else 1.0
    total = (len(speeds) + laps_extra) * 2 * math.pi
    travelled = 0.0
    while travelled < total:
        lap = min(int(travelled / (2 * math.pi)), len(speeds) - 1)
        speed = speeds[lap]
        a = angle + sign * travelled
        east = -radius + radius * math.cos(a)
        north = radius * math.sin(a)
        lat, lon = to_degrees(east, north)
        rows.append((t, lat, lon, speed * 3.6))
        travelled += speed / rate_hz / radius
        t += 1.0 / rate_hz
    return rows


def path_points(commands, step=0.1):
    """Traces turtle commands from (0, -150) heading north, one point per `step`.

    Each command is ("straight", metres) or ("arc", radius, degrees), positive
    degrees turning left.
    """
    x, y, heading = 0.0, -150.0, math.pi / 2
    points = [(x, y)]
    for command in commands:
        if command[0] == "straight":
            steps = max(1, round(command[1] / step))
            ds = command[1] / steps
            for _ in range(steps):
                x += ds * math.cos(heading)
                y += ds * math.sin(heading)
                points.append((x, y))
        else:
            radius, degrees = command[1], command[2]
            arc = radius * math.radians(abs(degrees))
            steps = max(1, round(arc / step))
            turn = math.radians(degrees) / steps
            ds = 2.0 * radius * math.sin(abs(turn) / 2)
            for _ in range(steps):
                # The chord of each small arc piece, at its mid heading.
                heading += turn / 2
                x += ds * math.cos(heading)
                y += ds * math.sin(heading)
                heading += turn / 2
                points.append((x, y))
    return points, (x, y, heading)


def closed_track(commands):
    """Closes `commands` (which must end heading west, left of x = -40) back to
    the start with three left 90 degree turns and straights sized to fit."""
    _, (x, y, heading) = path_points(commands)
    assert abs(math.remainder(heading - math.pi, 2 * math.pi)) < 1e-9 and x < -40.0
    south = y + 160.0
    east = -x - 40.0
    tail = [("arc", 40.0, 90.0), ("straight", south), ("arc", 40.0, 90.0),
            ("straight", east), ("arc", 40.0, 90.0), ("straight", 50.0)]
    points, (x, y, _) = path_points(commands + tail)
    assert abs(x) < 1e-6 and abs(y + 150.0) < 1e-6, (x, y)
    return points


def track_rows(points, speeds, rate_hz, mirror=False, laps_extra=0.5):
    """Drives the closed polyline `points` from its first point, one speed in m/s
    per lap; with `mirror`, east is negated (every turn changes side)."""
    cumulative = [0.0]
    for (ax, ay), (bx, by) in zip(points, points[1:]):
        cumulative.append(cumulative[-1] + math.hypot(bx - ax, by - ay))
    length = cumulative[-1]
    rows = []
    t = 0.0
    travelled = 0.0
    index = 0
    total = (len(speeds) + laps_extra) * length
    while travelled < total:
        lap = min(int(travelled / length), len(speeds) - 1)
        s = travelled % length
        if s < cumulative[index]:
            index = 0
        while cumulative[index + 1] < s:
            index += 1
        span = cumulative[index + 1] - cumulative[index]
        ratio = (s - cumulative[index]) / span if span > 0 else 0.0
        (ax, ay), (bx, by) = points[index], points[index + 1]
        east = ax + (bx - ax) * ratio
        north = ay + (by - ay) * ratio
        lat, lon = to_degrees(-east if mirror else east, north)
        rows.append((t, lat, lon, speeds[lap] * 3.6))
        travelled += speeds[lap] / rate_hz
        t += 1.0 / rate_hz
    return rows


def gate_line(name="Start", half=10.0, description="start"):
    lat_a, lon_a = to_degrees(-half, 0.0)
    lat_b, lon_b = to_degrees(half, 0.0)
    return f"{name} {lon_a:.8f} {lat_a:.8f} {lon_b:.8f} {lat_b:.8f} {description}"


def lap_file(name, rows, gates, header="coordinate units = degrees", drop=None, blank=None):
    lines = ["[header]", header, "[laptiming]"] + gates
    lines += ["[column names]", "time latitude longitude velocity", "[data]"]
    for index, (t, lat, lon, speed) in enumerate(rows):
        if drop and drop[0] <= t < drop[1]:
            continue
        if blank and blank[0] <= t < blank[1]:
            lines.append(f"{t:.2f} - {lon:.8f} {speed:.2f}")
            continue
        lines.append(f"{t:.2f} {lat:.8f} {lon:.8f} {speed:.2f}")
    write(name, "\n".join(lines) + "\n")


def main():
    os.makedirs(OUT, exist_ok=True)

    # Laps.
    clean = loop_rows(100.0, [30.0, 28.0, 31.0], 10)
    lap_file("laps_clean.vbo", clean, [gate_line()])
    lap_file("laps_gps_gap.vbo", clean, [gate_line()], drop=(30.0, 32.0))
    lap_file("laps_invalid_coordinate.vbo", clean, [gate_line()], blank=(30.0, 30.3))
    lap_file("laps_clockwise.vbo", loop_rows(100.0, [30.0, 30.0], 10, clockwise=True), [gate_line()])
    lap_file("laps_slow.vbo", loop_rows(20.0, [1.5], 10), [gate_line()])
    ends_at_gate = [r for r in loop_rows(100.0, [30.0, 30.0], 10, laps_extra=0.05)]
    lap_file("laps_end_inside_corridor.vbo", ends_at_gate, [gate_line()])
    lap_file("laps_gate_too_long.vbo", clean, [gate_line(half=150.0)])
    lap_file("laps_two_start_gates.vbo", clean, [gate_line(), gate_line(half=8.0)])
    lap_file("laps_no_start_gate.vbo", clean, [gate_line(name="Split", description="split")])
    lap_file("laps_long_trace.vbo", loop_rows(1000.0, [15.0, 15.5], 10), [gate_line()])

    # Tracks with corners and straights, for segment proposals: a rounded rectangle, and
    # a track with a kink, a short straight, an S-bend, two corners joined by a
    # 10 m straight and a hairpin, also mirrored and with a GPS gap.
    rectangle = closed_track([("straight", 300.0), ("arc", 50.0, 90.0), ("straight", 100.0)])
    lap_file("segments_rectangle.vbo", track_rows(rectangle, [25.0, 24.0, 25.5], 10), [gate_line()])
    mixed = closed_track([
        ("straight", 250.0), ("arc", 200.0, -8.0), ("straight", 15.0), ("arc", 200.0, 8.0),
        ("straight", 60.0), ("arc", 35.0, 90.0), ("straight", 30.0), ("arc", 30.0, -50.0),
        ("arc", 30.0, 50.0), ("straight", 80.0), ("arc", 25.0, 30.0), ("straight", 10.0),
        ("arc", 25.0, -30.0), ("straight", 60.0), ("arc", 15.0, 180.0), ("straight", 70.0),
        ("arc", 15.0, -180.0), ("straight", 60.0),
    ])
    mixed_rows = track_rows(mixed, [22.0, 21.0, 22.5], 10)
    lap_file("segments_mixed.vbo", mixed_rows, [gate_line()])
    lap_file("segments_mixed_mirrored.vbo", track_rows(mixed, [22.0, 21.5], 10, mirror=True), [gate_line()])
    lap_file("segments_mixed_gps_gap.vbo", mixed_rows, [gate_line()], drop=(76.5, 79.5))

    # Arc-minute coordinates declared in the header.
    arc = [(t, lat * 60.0, lon * 60.0, s) for t, lat, lon, s in clean]
    lat_a, lon_a = to_degrees(-10.0, 0.0)
    lat_b, lon_b = to_degrees(10.0, 0.0)
    arc_gate = f"Start {lon_a * 60:.6f} {lat_a * 60:.6f} {lon_b * 60:.6f} {lat_b * 60:.6f}"
    lap_file("laps_arc_minutes.vbo", arc, [arc_gate], header="coordinate units = arc-minutes")

    # RaceChrono Pro 10.2.4: arc-minutes, clock times, centre-direction gates.
    rc_rows = loop_rows(100.0, [30.0, 29.0], 10, start_time=0.0)
    lines = ["File created on 19/08/2026 at 11:20:05", "", "[header]", "satellites", "time",
             "latitude", "longitude", "velocity kmh", "", "[comments]",
             "Generated by RaceChrono Pro v10.2.4", "", "[laptiming]"]
    c_lat, c_lon = to_degrees(0.0, 0.0)
    b_lat, b_lon = to_degrees(0.0, -20.0)  # 20 m backward of northbound travel
    lines.append(f"Start {c_lon * 60:.6f} {c_lat * 60:.6f} {b_lon * 60:.6f} {b_lat * 60:.6f} Start / finish")
    lines += ["", "[column names]", "sats time lat long velocity", "", "[data]"]
    clock0 = 11 * 3600 + 14 * 60 + 28.0
    for t, lat, lon, s in rc_rows:
        c = clock0 + t
        hh, rem = divmod(c, 3600)
        mm, ss = divmod(rem, 60)
        lines.append(f"012 {int(hh):02d}{int(mm):02d}{ss:06.3f} {lat * 60:+.6f} {lon * 60:+.6f} {s:07.3f}")
    write("racechrono_10_2_4.vbo", "\r\n".join(lines) + "\r\n")

    rc_old = [l.replace("v10.2.4", "v9.1.0") for l in lines]
    write("racechrono_unvalidated_version.vbo", "\r\n".join(rc_old) + "\r\n")

    # Header and scanner edge cases.
    write("comma_separated.vbo",
          "[header]\ncoordinate units = degrees\n[column names]\n"
          "time, 'Lat' , \"Longitude\",speed,, speed ,Accelerator Pedal,throttle\n[data]\n"
          "0.0, 52.0, 21.0, 10 ,1,2, 0, 15\n"
          "0.5,52.0001,21.0001,  11,1,2,5,16 \n"
          "1.0 , 52.0002 , 21.0002 , 12 , 1 , 2 , 50 , 17, 99\n"
          "1.5,52.0003\n")
    write("clock_formats.vbo",
          "[column names]\ntime value\n[data]\n"
          "23:59:58.5 1\n23:59:59.0 2\n235959.50 3\n000000.25 4\n00:00:01 5\n000002 6\n12:00:00 7\n")
    write("relative_seconds.vbo",
          "[column names]\ntimestamp a b\n[data]\n"
          "10.0 1 2\n10.5 1 2\n10.5 9 9\n10.2 8 8\nabc 7 7\n11 1\n11.5 1 2 3 4\n1e1 5 5\n12.0 nan inf\n")
    write("no_time_column.vbo", "[column names]\nrpm brake\n[data]\n1000 0\n2000 10\n3000 x\n")
    write("number_spellings.vbo",
          "[column names]\ntime v\n[data]\n" + "".join(
              f"{i} {v}\n" for i, v in enumerate(
                  ["1e5", ".5", "5.", "+1", "-0", "0x10", "inf", "-inf", "nan", "NaN", "Infinity",
                   "1e400", "3.4e38", "3.5e38", "1.17549e-38", "1e-46", "1_0", "\u0661", "0001.5000",
                   "1e+2", "1E2", "1.5e", "e5", "--1", "1d", "1f", " "]))
              )
    write("whitespace.vbo",
          "[column names]\ntime\ta\u00a0b  c\n[data]\n0\t1\u00a02  3\n1\u20032 3\n2 , 4\u00a0, 5 ,6\n3 7\u00a0 \u00a08\n4 \u30009 1\n")
    write("sections_and_metadata.vbo",
          "; comment\n# another\nloose line\n[Header]\nvehicle: Test Car\ndriver = A  B\n"
          "no separator here\n[HEADER]\nvehicle = Second\n[session data]\nkey: value\n"
          "  [ Column Names ]  \ntime x x x (2) \n[DATA]\n0 1 2 3 4\n1 1 2 3 4\n"
          "[header]\ngpsCoordinateUnit = forged\ntimingGateFormat = forged\n")
    write("coordinate_units_invalid.vbo",
          "[header]\ncoordinate units = radians\n[column names]\ntime lat lon v\n[data]\n0 52 21 1\n1 52 21 2\n")
    write("coordinate_units_conflict.vbo",
          "[header]\ncoordinate units = degrees\ncoordinate units = arc-minutes\n"
          "[column names]\ntime latitude longitude\n[data]\n0 52 21\n1 52 21\n")
    write("coordinate_units_missing.vbo",
          "[laptiming]\nStart 21 52 21 52.0002\n[column names]\ntime latitude longitude v\n[data]\n0 52 21 1\n1 52 21 2\n")
    write("coordinate_out_of_range.vbo",
          "[header]\ncoordinate units = degrees\n[column names]\ntime latitude longitude\n[data]\n"
          "0 91 21\n1 -90 180\n2 90 -181\n3 45 45\n")
    write("gate_lines.vbo",
          "[header]\ncoordinate units = degrees\n[laptiming]\n"
          "Start 21 52 21 52.0002 main straight\nSplit 21.001 52 21.001 52.0002\n"
          "Finish 21.002 52 21.002 52.0002\nStart 21 52 21\nStart 21 52 21 52\n"
          "Start 21 52 x 52.0002\nStart 21 95 21 52.0002\nsplit 21 52 21 52.0002   \n"
          "[column names]\ntime latitude longitude\n[data]\n0 52 21\n1 52.0001 21\n")
    write("bom_crlf.vbo", "\ufeff[column names]\r\ntime a\r\n[data]\r\n0 1\r\n1 2\r\n2 3\r\n")
    write("cr_only.vbo", "[column names]\rtime a\r[data]\r0 1\r1 2\r")
    write("bad_utf8.vbo", b"[header]\nname = caf\xc3\xa9 \xff\xfe x\xe2\x82\n[column names]\ntime a\xff\n[data]\n0 1\n1 2\n", "wb")
    write("all_columns_empty.vbo", "[column names]\ntime a b\n[data]\n0 x y\n1 - -\n2 1 -\n")
    write("acceleration_aliases.vbo",
          "[column names]\ntime latacc longacc latacc-calc LongAcc-Calc heart_rate Engine Speed g_x\n[data]\n"
          "0 0 0 0.1 0.2 120 3000 1\n1 0 0 0.2 0.3 121 3100 1\n")
    write("midnight_and_mixed.vbo",
          "[column names]\ntime a\n[data]\n23:30:00 1\n23:59:59.9 2\n00:00:00.1 3\n5 4\n00:30:00 5\n01:00:00 6\n01:00:01 7\n")
    write("error_no_columns.vbo", "[header]\nx = 1\n[data]\n0 1\n")
    write("error_no_data.vbo", "[column names]\ntime a\n[data]\n")
    write("error_two_data_sections.vbo", "[column names]\ntime a\n[data]\n0 1\n[data2]\n1 2\n")
    write("error_two_column_sections.vbo", "[column names]\ntime a\n[columns]\ntime a\n[data]\n0 1\n")
    write("error_no_valid_rows.vbo", "[column names]\ntime a\n[data]\nx 1\ny 2\n")
    write("error_empty_column_names.vbo", "[column names]\n , , \n[data]\n0 1\n")
    write("error_huge_timestamp.vbo", "[column names]\ntime a\n[data]\n0 1\n1e14 2\n")
    write("error_empty.vbo", "")


if __name__ == "__main__":
    main()
