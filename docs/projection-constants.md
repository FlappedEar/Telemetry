# Projection constants

`telemetry_core` places each GPS fix of a lap on a distance axis built from a
reference lap (`buildProgressAxis`, `projectSample`, `projectLapTrace` in
`packages/telemetry_core/lib/src/analysis/track_progress.dart`). Lap comparison,
sector timing, the theoretical best and automatic segments all read their
distances from it. The projection rests on tuned constants, ported from
FlappedEar Overlays' `TrackProgress.cpp` (KAN-32, gate anchoring and
unwrapping from KAN-152; Dart port FET-30 and FET-192). All but one are
unchanged, so Overlays and Telemetry agree
(`test/parity/progress_parity_test.dart`). The exception is deliberate:
`_segmentStartBackwardMeters` (FET-249, Overlays KAN-237) lets the first fix
of a segment after a gap fall up to 30 m behind the last progress, where
Overlays allows only the 3 m backward tolerance.

This page lists them with the evidence behind each and how far each is from
failing (FET-215). The evidence comes from:

- **Synthetic shapes**: `test/analysis/projection_calibration_test.dart` drives
  laps with a known distance at every fix around a figure-eight (90°, 30° and
  10° crossings), parallel straights driven in opposite directions (2–40 m
  apart) and hairpins (3–15 m radius), at 10 Hz with 0.3 m of GPS error
  correlated over a second, and compares the projection with the truth. It
  runs in CI. `test/analysis/projection_findings_test.dart` drives the same
  shapes into the failures of findings 2 and 3 and pins every figure quoted
  for them at its current value.
- **The real day**: `test/analysis/real_day_projection_test.dart` measures, on
  the owner's Jastrząb day of 29 August 2026 (six sessions, 25 timed laps,
  10 Hz), the quantity each constant bounds. Each session's fastest lap builds
  an axis and every timed lap of the day is projected on all six: 150 lap
  projections, 193,764 fixes, axes 2,031–2,066 m at 2.00 m spacing. It runs
  only when `FLAPPEDEAR_REAL_DAY` points at a folder of the day's VBO files,
  and in `tool/real_day_parity.dart`. Only the aggregate figures below come
  from it. It prints every real-day figure on this page, names the rule
  behind each refused fix (checked against `projectSample` fix by fix), and
  holds the split and unprojected counts of finding 1 within a narrow band.

Real-day and synthetic results are reported separately, as AGENTS.md asks.

## The constants

| Constant | Value | Guards against | Evidence | Too small | Too large |
| --- | --- | --- | --- | --- | --- |
| `coldStartProximityMeters` | 20 m | Locking on from a fix that is not on the track (paddock, pit lane, a run-off) | Overlays KAN-32; handover "match ≤ 20 m". Synthetic: a cold start accepts a fix 19.9 m off a straight and refuses one 20.1 m off. Real: 673 fixes (0.35%) are more than 20 m from the axis, all in one off-track excursion; the nearest other part of the track is 22.4 m away (more than 100 m along it), 21.3 m for anything more than 30 m along it | Laps off the reference line cannot re-acquire after a gap | Fixes on a nearby other part of the track, or the pit lane, lock on (2.4 m of margin at Jastrząb) |
| `lockProximityMeters` | 20 m | Following a fix that has left the track | As above; never the binding limit while locked (see finding 1). Real: 3 fixes refused by it | — (finding 1 binds first) | As above |
| `ambiguityRatio` | 0.7 | Choosing between two equally near branches: a crossing, a hairpin's centre, parallel straights | Overlays KAN-32 (`ambiguousEquidistantCrossingIsRejected`). Synthetic: on parallel straights a cold start is refused once a fix is more than 0.7/1.7 of the separation off its line toward the other straight (6.2 m at 15 m apart, 8.2 m at 20 m, 12.4 m at 30 m). Real: while locked the ratio reaches 0.98, with 2,590 fixes above 0.7 (finding 1); on a cold start it reaches 0.75, 22 fixes above 0.7 | A fix nearly equidistant from two branches locks on either | Fixes a few metres off the reference line are refused (finding 1) |
| `coldStartSeparationMeters` | 30 m (at least 4 axis points) | The runner-up of a cold start being a neighbouring part of the same branch | Overlays KAN-32. Real: the nearest runner-up more than 30 m along is 14.3 m from a fix | Every fix on a curve looks ambiguous | The other leg of a hairpin tighter than about 10 m radius (half a turn of about 30 m) is skipped as a runner-up (finding 2) |
| `windowedSeparationMeters` | 10 m (at least 3 axis points) | The same while locked | Overlays KAN-32. Synthetic: with 0.7 it refuses fixes from about 8 m off a straight (finding 1) | Every fix looks ambiguous | Close branches inside the window are skipped |
| `minimumHeadingCosine` | 0 (within 90°) | Locking on to a parallel section driven the opposite way, or a hairpin's other side | Overlays KAN-32 (`headingRejectsOppositeDirectionParallelSection`); Dart test "never locks on to the same path driven the opposite way". Real: lowest cosine 0.028, 99.9% of fixes at least 0.65 (0.1% quantile 0.658), no fix refused by it. Synthetic: at least 0.94 on the figure-eights, 0.62 in a 7.5 m hairpin with a 3 m apex cut | Opposite-direction sections lock on | Cornering and line changes are refused; GPS error of ±0.5 m uncorrelated from fix to fix already trips it at 10 Hz (5 seeds on an oval: 45 fixes dropped at 10 m/s, 2 at 12 m/s, none at 15 m/s; `projection_findings_test.dart`) |
| `_backwardToleranceMeters` | 3 m | GPS jitter projecting just behind the last fix of a segment (often while stopped); such a fix is held at the last progress | Overlays KAN-152 (`b65acbd`, `3b8b6cd`). Synthetic: a fix without a heading 2.9 m back is held, 3.1 m back is refused; with a heading, any step back on a straight is refused by the heading rule first. Real: no fix steps back (0.00 m) | Jitter splits segments | A wrong match behind the car is accepted |
| `_segmentStartBackwardMeters` | 30 m, at most a quarter of the axis length | The first fix of a segment after a gap, found again from scratch, projecting a little behind the last progress: read as the next lap, it moved the rest of the lap a whole lap forward | FET-249, a deliberate departure from Overlays, which allows the 3 m tolerance here (KAN-237): on a 25 Hz RaceChrono lap each restart after a break was unwrapped one lap on. Synthetic: `track_progress_uneven_test.dart` (a fix found again behind after a gap stays on its lap); a 5 m hairpin re-acquired 3.7 m behind stays on its lap (finding 2) | A segment after a gap starting just behind is unwrapped a whole lap forward | A first fix wrongly matched up to 30 m behind stays on this lap, so progress falls between segments; on a short loop a real jump forward of more than three quarters of a lap would read as a step back, hence the cap |
| `_maximumGapSeconds` | 5 s | Continuing a stale lock; at the lap start, a first fix within 5 s that projects onto the far half is stored just before 0 | Overlays KAN-32 and KAN-152. Synthetic: a fix 4.9 s after the lock is searched in the window, 5.1 s after it is a cold start. Real: the longest interval between fixes in a lap is 0.10 s. `sampledSegments` already ends a segment at three base intervals (0.3 s at 10 Hz), so the 5 s rule binds only below 0.6 Hz | Short dropouts become cold starts, which have no heading check (finding 2) | A stale lock steers the window; the window cap usually just costs a fix |
| Forward window | 1.6 × speed × Δt, clamped to 15–150 m | Searching the whole track while locked (the window keeps crossings and parallel straights out) | Overlays KAN-32. Synthetic: holds the lock at 45 m/s with up to 3.3 s between fixes (148.5 m). Real: from one fix to the next the nearest point on the axis advances at most 12.2 m, 81% of the 15 m floor | Fast or sparse fixes lose the lock | Other branches enter the window |
| Backward window | min(15 m, 0.3 × forward) | Jitter behind the last lock | Overlays KAN-32; with the 3 m tolerance, anything beyond it is refused anyway | Jitter falls outside the window | — |
| `gateCoverageToleranceMeters` | 15 m | A lap's projection starting and ending a few fixes inside the gate | Overlays KAN-152 (FET-192); the oblique-gate tests in `track_progress_test.dart`. Real: the first or last projected fix is at most 8.86 m from the gate | The timed delta and the first and last sectors lose the lap's ends | Coverage over a real gap of up to 15 m next to the gate is assumed |
| Axis spacing | ~2 m (length / 2, 32–15,000 points) | Fine enough for 2 m chords of a corner; window and separations are counted in points | Overlays KAN-32. Real: 2.00 m | — | Separations and windows round coarsely |
| Axis bounds | 50–30,000 m, at least 12 distinct points; fixes closer than 0.5 m dropped | Building an axis from something that is not a lap; zero-length resampling | Overlays KAN-32. Real: 2,031–2,066 m | — | — |
| Fix budget | 4,000 time buckets per lap (`sampledSegments`), each keeping its lowest and highest latitude | Unbounded work on a long lap | Overlays `sampledSegments`. Real: about 1,100–1,500 fixes per lap. A lap of more than 8,000 fixes (800 s at 10 Hz, 400 s at 20 Hz) is thinned before it is projected | — | — |

## Findings

The calibration found three ways the projection fails on shapes it is meant to
handle. None is fixed here: the constants stay as they are, and a change is
for the owner to decide in both apps. The calibration tests assert only what
holds; `projection_findings_test.dart` and the real-day test pin the failures
below at their current values, one constant per figure, so a change that
moves them (FET-256 is expected to) has to update this page with them.

1. **While locked, a lap more than about 8 m off the reference lap's line loses
   fixes, long before the 20 m proximity.** The runner-up of a locked fix only
   has to be 10 m along the axis, and on a straight a fix d metres off the line
   is d / √(d² + a²) of the way to it, with a about 8–10 m: the 0.7 ratio
   refuses it from d ≈ 0.98 a. Synthetic: on an oval a lap 7 m off the line
   keeps every fix; 8.5 m off loses about a quarter of them, in alternate
   fixes, since each refusal is followed by a cold start, which accepts it.
   Real day: 1% of fixes are more than 12 m off the reference lap's line (5%
   more than 5.5 m), 1,387 fixes are refused this way (on the first session's
   axis about half of them 140–185 m after the gate, median 189 m), and 89 of
   the 150 lap projections are split into more than one segment. In all,
   2,078 fixes (1.07%) go unprojected: 1,387 for ambiguity while locked, 670 beyond 20 m on a cold start (the excursion), 18 for
   ambiguity on a cold start and 3 beyond 20 m while locked. Every projected
   fix agrees with the nearest point of the axis followed along the lap
   (0.00 m apart). The gaps never invent data, but a sector or delta that
   needs the missing stretch has no value there.
2. **A cold start right after a refused fix has no heading, and can lock on to
   the wrong branch; one wrong fix then shifts the rest of the lap by whole
   laps.** After a refusal `projectLapTrace` restarts with no previous fix, so
   the next fix is placed by distance and the ratio alone. Its progress then
   becomes the reference for unwrapping. When the wrong fix is more than 30 m
   (or a quarter of the axis) ahead of where the lap really is, the
   allowance of `_segmentStartBackwardMeters` no longer covers it and every
   later segment is unwrapped past it, a lap length or more out; a wrong fix
   less far ahead costs only its own error. Synthetic:
   - Figure-eight with 300 m diagonals, GPS back after a 30 m gap (lines −1,
     0 and +1 m off the centre line, five seeds, the gap's end every metre
     from 30 m before to 30 m after the crossing: 915 trials per angle): 50
     trials lock on to the other diagonal at a 90° crossing (GPS back 4 to 1 m
     before it), 45 at 30° (10 m before to 3 m after) and 118 at 10° (18 m
     before to 14 m after). The error is one lap: 2,015 m, 895 m and 688 m.
     40 m before the crossing it always finds the right branch (tested).
   - Parallel straights driven in opposite directions: a lap more than
     separation / 1.7 off its line toward the other straight (8.8 m at 15 m
     apart, 11.8 m at 20 m, 17.6 m at 30 m) is refused while locked
     (finding 1), then re-acquired on the other straight; errors reach
     1.3–1.4 km, about two laps. At 7 m off it stays on its own straight (tested).
   - Hairpins cut by 40% with 1 m of GPS error, five seeds: in a 5 m hairpin
     (legs 10 m apart) one lap re-acquires 3.7 m behind its last fix and,
     within the 30 m allowance, stays on its lap; its worst fix is 6.2 m out.
     In a 3 m hairpin one fix is 18.4 m out. The other leg
     is within 30 m along the axis, so the cold-start ratio never sees it.
   The real day has no crossing or parallel section within 20 m, and none of
   its fixes is misplaced.
3. **A fix up to 20 m beyond the 150 m forward window is placed at the window's
   end.** Synthetic: at 45 m/s with 3.4 s between fixes (153 m) the lap stays
   one segment with errors of 15 m. It needs more than 150 m between two fixes
   of one sampled segment, which `sampledSegments` allows only below about
   0.3 Hz; at 10 Hz fixes are 4.5 m apart at 45 m/s.

Smaller limits, which drop fixes but never misplace them: in hairpins of 3 and
5 m radius cut by 40%, 4 of 855 and 3 of 890 fixes are dropped; an apex cut of
6 m drops fixes in 10 m and 15 m hairpins (4.5 m holds). Parallel straights
down to 2 m apart keep every fix while locked.
