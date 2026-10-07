# Projection constants

`telemetry_core` places each GPS fix of a lap on a distance axis built from a
reference lap (`buildProgressAxis`, `projectSample`, `projectLapTrace` in
`packages/telemetry_core/lib/src/analysis/track_progress.dart`). Lap comparison,
sector timing, the theoretical best and automatic segments all read their
distances from it. The projection rests on tuned constants, ported from
FlappedEar Overlays' `TrackProgress.cpp` (KAN-32, gate anchoring and
unwrapping from KAN-152; Dart port FET-30 and FET-192). Those constants are
unchanged, so Overlays and Telemetry agree
(`test/parity/progress_parity_test.dart`). Telemetry departs from Overlays
deliberately in three places, and the parity fixtures' results are unchanged
by all three:

- `_segmentStartBackwardMeters` (FET-249, Overlays KAN-237) lets the first
  fix of a segment after a gap fall up to 30 m behind the last progress,
  where Overlays allows only the 3 m backward tolerance.
- A cold start in the middle of a lap is checked more strictly, and a
  segment on another branch cannot move the rest of the lap on by a lap
  (FET-256, Overlays KAN-238; finding 2), with constants Overlays does not
  have: `_maximumPlausibleSpeedMetersPerSecond`, `_ownSpeedMargin` with
  `_ownSpeedFloorMetersPerSecond`, and `_minimumHeadingMovementMeters`.
- While locked, a fix that Overlays' runner-up 10 m along the axis would
  refuse is kept when no part of the whole axis beyond the match's own
  branch is nearly as near and the fix does not lie well inside a bend; a
  fix whose nearest point lies beyond the forward end of the search window
  is refused rather than placed at the window's end (FET-257; findings 1
  and 3). Constants Overlays does not have: `_flatBranchRatio`,
  `_sameBranchCosine` and `_insideBendShare`. No constant Overlays has
  changes.

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
| `lockProximityMeters` | 20 m | Following a fix that has left the track | As above. Since FET-257 (finding 1) the binding limit while locked: synthetic, a lap 19.5 m off an oval's line keeps every fix and one 20.5 m off none. Real: 2 fixes refused by it (3 before FET-257) | Laps off the reference line lose fixes while locked | As above |
| `ambiguityRatio` | 0.7 | Choosing between two equally near branches: a crossing, a hairpin's centre, parallel straights | Overlays KAN-32 (`ambiguousEquidistantCrossingIsRejected`). Synthetic: on parallel straights a cold start is refused once a fix is more than 0.7/1.7 of the separation off its line toward the other straight (6.2 m at 15 m apart, 8.2 m at 20 m, 12.4 m at 30 m); while locked, a fix midway between a hairpin's legs (3, 7.5 and 15 m radius) or between two straights 15 m apart that are both in the window is refused (`locked_off_line_test.dart`). Real: while locked, against the window's runner-up 10 m along or, where that is above 0.7, the runner-up on the whole axis beyond the match's own branch (FET-257), 82 fixes are above 0.7, up to 0.98 (before, against the window's runner-up alone, 2,590: finding 1); on a cold start it reaches 0.75, 22 fixes above 0.7 | A fix nearly equidistant from two branches locks on either | A cold start a few metres off the line toward another branch is refused; while locked, until FET-257, fixes a few metres off the reference line were refused (finding 1) |
| `coldStartSeparationMeters` | 30 m (at least 4 axis points) | The runner-up of a cold start being a neighbouring part of the same branch | Overlays KAN-32. Real: the nearest runner-up more than 30 m along is 14.3 m from a fix | Every fix on a curve looks ambiguous | The other leg of a hairpin tighter than about 10 m radius (half a turn of about 30 m) would be skipped as a runner-up; since FET-256 a part of the axis within the separation that runs the other way is compared too (finding 2) |
| `windowedSeparationMeters` | 10 m (at least 3 axis points) | The same while locked | Overlays KAN-32. Alone it let the runner-up be the same line 10 m on, and with 0.7 refused fixes from about 8 m off a straight (finding 1). Since FET-257 a fix it would refuse is kept when the runner-up anywhere on the whole axis beyond the match's own branch is not within 0.7 either, and the fix does not lie well inside a bend (`_insideBendShare`). The own branch is the run of the axis next to the match, unbroken along it, that runs within 90° of it (`_sameBranchCosine`) and is near enough to make the fix ambiguous; a stretch clearly further from the fix (a hairpin's apex, the loop between the two passes of a crossing) or one running the other way (a hairpin's other leg) ends it. Only fixes it refuses are checked again, so the change refuses nothing that was accepted before | Every fix looks ambiguous | Close branches inside the window are skipped |
| `_flatBranchRatio` | 0.95 | A fix near the centre of a corner, about as near the whole corner, placed anywhere along it (FET-257) | While locked, a part of the match's own branch at least the windowed separation along the axis that is within 0.95 of the match's distance is still compared as a runner-up, so the fix is refused, as before FET-257. Off a straight, 10 m along is never nearer than 0.93 within the 20 m proximity. Synthetic: a fix at the centre of 3, 7.5 and 15 m hairpins and of 10, 15 and 19 m 90° corners is refused (`locked_off_line_test.dart`); without it the 90° corners were accepted. Real: 37 fixes refused while locked as ambiguous, by it or by another part of the track (ratio up to 0.98) | Fixes on the inside of a tight corner are refused | A fix near a corner's centre is placed anywhere along it |
| `_sameBranchCosine` | 0 (within 90°) | The other leg of a hairpin, or the corner beyond a bend, counted as the match's own branch and never compared (FET-257) | The own branch ends where the axis turns more than 90° from the match's direction, so a hairpin's other leg is compared however near. Tighter values (30° and 45° were tried) refuse fixes off the line through ordinary corners: on the real day 784 fixes refused while locked and 79 split lap projections at 30°, and no fewer misplaced fixes in the review's synthetic grid | Fixes off the line through a long corner are refused | A hairpin's other leg is taken as the same branch, and a fix between the legs is placed on either |
| `_insideBendShare` | 0.5 of the bend's radius | A fix kept off the line on the inside of a bend, further in than the bend's centre or than an ess's radius: there the nearest point of the axis no longer says where the car is (the review of FET-257) | Applies only to a fix kept by the whole-axis check. The radius comes from the turn between the axis segments two either side of each point of the match's own branch. Synthetic: with it, 1 Hz laps of 6–8 m hairpins and of a 20° figure-eight with 80 m diagonals, on the line and 3–4 m off it, are never more than 10 m out (`locked_off_line_test.dart`); without it the review's synthetic grid had 96 fixes misplaced by more than 15 m that were not before FET-257, with it 19: 18 within a second of a fix of the same lap that was misplaced before FET-257 too, and a cold start after a fix it refused. An apex cut of 6 m in a 10 m hairpin drops 18 fixes, as before FET-257. Real: 254 fixes refused by it; 38 of the 46 split lap projections are split by it (12 with fixes ambiguous while locked as well) | Fixes a few metres inside a bend are refused | A fix past a hairpin's centre or across an ess is placed on the near side |
| `minimumHeadingCosine` | 0 (within 90°) | Locking on to a parallel section driven the opposite way, or a hairpin's other side | Overlays KAN-32 (`headingRejectsOppositeDirectionParallelSection`); Dart test "never locks on to the same path driven the opposite way". Real: lowest cosine 0.028, 99.9% of fixes at least 0.65 (0.1% quantile 0.658), no fix refused by it. Synthetic: at least 0.94 on the figure-eights, 0.62 in a 7.5 m hairpin with a 3 m apex cut | Opposite-direction sections lock on | Cornering and line changes are refused; GPS error of ±0.5 m uncorrelated from fix to fix already trips it at 10 Hz (5 seeds on an oval: 45 fixes dropped at 10 m/s, 2 at 12 m/s, none at 15 m/s; `projection_findings_test.dart`) |
| `_backwardToleranceMeters` | 3 m | GPS jitter projecting just behind the last fix of a segment (often while stopped); such a fix is held at the last progress | Overlays KAN-152 (`b65acbd`, `3b8b6cd`). Synthetic: a fix without a heading 2.9 m back is held, 3.1 m back is refused; with a heading, any step back on a straight is refused by the heading rule first. Real: no fix steps back (0.00 m) | Jitter splits segments | A wrong match behind the car is accepted |
| `_segmentStartBackwardMeters` | 30 m, at most a quarter of the axis length | The first fix of a segment after a gap, found again from scratch, projecting a little behind the last progress: read as the next lap, it moved the rest of the lap a whole lap forward | FET-249, a deliberate departure from Overlays, which allows the 3 m tolerance here (KAN-237): on a 25 Hz RaceChrono lap each restart after a break was unwrapped one lap on. Synthetic: `track_progress_uneven_test.dart` (a fix found again behind after a gap stays on its lap); a 5 m hairpin re-acquired 3.7 m behind stays on its lap (finding 2) | A segment after a gap starting just behind is unwrapped a whole lap forward | A first fix wrongly matched up to 30 m behind stays on this lap, so progress falls between segments; on a short loop a real jump forward of more than three quarters of a lap would read as a step back, hence the cap |
| `_maximumGapSeconds` | 5 s | Continuing a stale lock; at the lap start, a first fix within 5 s that projects onto the far half is stored just before 0 | Overlays KAN-32 and KAN-152. Synthetic: a fix 4.9 s after the lock is searched in the window, 5.1 s after it is a cold start. Real: the longest interval between fixes in a lap is 0.10 s. `sampledSegments` already ends a segment at three base intervals (0.3 s at 10 Hz), so the 5 s rule binds only below 0.6 Hz | Short dropouts become cold starts; since FET-256 the direction of travel is kept across a raw GPS gap of up to 5 s, so they keep the heading check (finding 2) | A stale lock steers the window; the window cap usually just costs a fix; the movement across a long gap, taken as the heading of the fix after it, can refuse that fix on a curve |
| `_maximumPlausibleSpeedMetersPerSecond` | 100 m/s (360 km/h), plus the 30 m allowed behind | A segment after a gap starting on another branch of the track and shifting the rest of the lap (FET-256, finding 2) | Synthetic: refuses the figure-eight fixes found again on the other diagonal, hundreds of metres ahead under a second after the last fix. Guards: a car at 95 m/s keeps every fix after gaps of 50–1,000 m, one at 40 m/s after gaps of 10–900 m. Real: never binds (the same fixes are projected) | A fast car's segment after a gap is refused | A wrong branch within reach is accepted (then the own-speed rule below can still drop it); after a gap longer than (L − 60 m) / 100 m/s, about 20 s at Jastrząb, the next lap is within reach and laps cannot be told apart |
| `_ownSpeedMargin`, `_ownSpeedFloorMetersPerSecond` | 1.5 × the lap's own speed, at least 40 m/s and at most 100 m/s, plus 30 m | Right fixes after a wrong segment that lies within reach being moved on by a lap once the 100 m/s reach has grown enough (the review of FET-256, finding 2) | The lap's own speed is its fastest progress over a second within a segment. A segment's first fix further ahead of the last projected fix than the own speed allows is read as lying behind the latest segments instead: when it is within the 100 m/s reach of the lock before them, lies more than 30 m behind where they started, and they cover less than a quarter of the axis, they are dropped. A fix out of the latest run's 100 m/s reach that the lock before the run could have reached at the own speed drops the run too (the re-review: a long gap on the 10° figure-eight, 19–63 of 549 trials refusing the rest of the lap before, none after). Synthetic: the 10° figure-eight with 200 m gaps (279 trials) drops 31 one-fix segments, and none of the 2,511 figure-eight trials with 100–400 m gaps is shifted (31 and 33 of 279 at 10°, 10 of 279 at 30° before). Real: never binds | A car faster than its margin during a gap, behind a short run, could have that run dropped and be placed a lap back; only after a gap of nearly a lap | A wrong run is kept and the right fixes after it refused, or moved on by a lap once within the 100 m/s reach |
| `_minimumHeadingMovementMeters`, standing | 0.5 m while the lap stands: less than 1 m/s of projected progress over the 0.5 s before its last projected fix, at most 0.5 s old | A cold start taking the GPS jitter of a standing car as its direction of travel (the review of FET-256) | Synthetic: a car standing for a minute with 0.5 m of GPS error, five seeds: 6,133 of 7,115 fixes projected (6,215 before FET-256, 5,880 with jitter as a heading). The heading rule while locked still refuses jitter, as in Overlays (864 fixes). A car crawling through a 3 m hairpin keeps its heading, so the hairpin tests are unchanged. Real: never binds | More fixes of a standing car refused | A cold start of a car rolling slowly after a stop has no heading |
| Forward window | 1.6 × speed × Δt, clamped to 15–150 m | Searching the whole track for every fix while locked | Overlays KAN-32. It keeps a fix to near where the lap was, but it does not keep other branches out by itself: a branch inside it is refused by the ambiguity ratio, and one beyond it is not seen. A fix near the line is accepted on the window alone; since FET-257 a fix a few metres off it is checked against the whole axis (finding 1). Synthetic: holds the lock at 45 m/s with up to 3.3 s between fixes (148.5 m). Since FET-257 a fix whose nearest point lies beyond the window's forward end is refused, not placed at the end (finding 3). Real: from one fix to the next the nearest point on the axis advances at most 12.2 m, 81% of the 15 m floor; no fix is refused at the window's end | Fast or sparse fixes lose the lock (since FET-257 a fix beyond the window is refused and the next fix is a cold start) | Other branches enter the window |
| Backward window | min(15 m, 0.3 × forward) | Jitter behind the last lock | Overlays KAN-32; with the 3 m tolerance, anything beyond it is refused anyway | Jitter falls outside the window | — |
| `gateCoverageToleranceMeters` | 15 m | A lap's projection starting and ending a few fixes inside the gate | Overlays KAN-152 (FET-192); the oblique-gate tests in `track_progress_test.dart`. Real: the first or last projected fix is at most 8.86 m from the gate | The timed delta and the first and last sectors lose the lap's ends | Coverage over a real gap of up to 15 m next to the gate is assumed |
| Axis spacing | ~2 m (length / 2, 32–15,000 points) | Fine enough for 2 m chords of a corner; window and separations are counted in points | Overlays KAN-32. Real: 2.00 m | — | Separations and windows round coarsely |
| Axis bounds | 50–30,000 m, at least 12 distinct points; fixes closer than 0.5 m dropped | Building an axis from something that is not a lap; zero-length resampling | Overlays KAN-32. Real: 2,031–2,066 m | — | — |
| Fix budget | 4,000 time buckets per lap (`sampledSegments`), each keeping its lowest and highest latitude | Unbounded work on a long lap | Overlays `sampledSegments`. Real: about 1,100–1,500 fixes per lap. A lap of more than 8,000 fixes (800 s at 10 Hz, 400 s at 20 Hz) is thinned before it is projected | — | — |

## Findings

The calibration found three ways the projection fails on shapes it is meant to
handle. The constants Overlays has stay as they are, and a change to them is
for the owner to decide in both apps. All three are fixed in Telemetry
without changing one of them: finding 2 by FET-256, findings 1 and 3 by
FET-257. The calibration tests assert only what holds;
`projection_findings_test.dart` and the real-day test pin the figures below
at their current values, one constant per figure, so a change that moves
them has to update this page with them.

1. **Fixed (FET-257): while locked, a lap more than about 8 m off the
   reference lap's line lost fixes, long before the 20 m proximity.** The
   runner-up of a locked fix only had to be 10 m along the axis, so on a
   straight it was the same line 10 m on: a fix d metres off the line is
   d / √(d² + a²) of the way to it, with a about 8–10 m (the segment five
   points on, its nearest point at its start), and the 0.7 ratio refused it
   from d ≈ 0.98 a. The ratio compared the line with itself.
   Before the fix, synthetic: on an oval a lap 7 m off the line kept every
   fix; 8.5 m off lost about a quarter of them (415 and 407 of 546), in
   alternate fixes, since each refusal is followed by a cold start, which
   accepts it; 10 and 15 m off lost about half. Real day: 1% of fixes are
   more than 12 m off the reference lap's line (5% more than 5.5 m), 1,387
   fixes were refused this way (on the first session's axis about half of
   them 140–185 m after the gate, median 189 m), and 89 of the 150 lap
   projections were split into more than one segment. In all, 2,078 fixes
   (1.07%) went unprojected: 1,387 for ambiguity while locked, 670 beyond
   20 m on a cold start (the excursion), 18 for ambiguity on a cold start
   and 3 beyond 20 m while locked. No fix was misplaced, but a sector that
   needed a missing stretch had no time: on the VBO files 9 of the 23 laps
   of the theoretical best's table missed at least one of its 14 segments.

   The fix: while locked, a fix the window's runner-up 10 m along refuses
   is kept only when every other branch of the track is ruled out. The
   runner-up is then the best match anywhere on the axis beyond the
   match's own branch: the run next to the match, unbroken along the
   axis, that runs within 90° of it (`_sameBranchCosine`) and is near
   enough to make the fix ambiguous (within the 0.7 ratio of its
   distance). Another branch is beyond a stretch clearly further from the
   fix (a hairpin's apex, the loop between a crossing's two passes) or one
   running the other way (a hairpin's other leg), however far along the
   axis it lies. A part of the own branch nearly as near the fix as the
   match (within 0.95 of its distance, `_flatBranchRatio`) is still
   compared: the fix is near the centre of a corner and where it lies
   along it is not known. And the fix must not lie on the inside of a bend
   of its own branch by more than half the bend's radius
   (`_insideBendShare`): further in, the nearest point of the axis no
   longer says where the car is (past a hairpin's centre, across an ess).
   Only fixes the window's runner-up refuses are checked this way, so the
   change refuses nothing that was accepted before. The first version of
   the fix compared only the window: at 1–2 Hz the window can end before
   a hairpin whose other leg the car is already on, and a fix 6–16 m off
   the near leg was placed on it (the review of FET-257).

   After, synthetic (`locked_off_line_test.dart`, 12 of whose 25 tests fail
   before FET-257 or with its first version): laps 8.5, 10 and 15 m off
   the oval's line, either side, five seeds with 0.3 m of GPS error, keep
   every fix in one segment; a lap 8.5 m off through the figure-eights is
   never misplaced (at most 3.9 m out, in the 10° figure-eight's 13 m
   lobes, as before). Still refused while locked: a fix midway between the
   legs of 3, 7.5 and 15 m hairpins, at the centre of those hairpins and
   of 10, 15 and 19 m 90° corners, midway between two straights 15 m apart
   that are both in the window, and a lap 0.5 m beyond separation / 1.7
   off toward the other of two parallel straights where it is nearer the
   other straight than 0.7 of the way (137 of 186, 144 of 193 and 156 of
   205 fixes kept, as before FET-257; the first version kept all). At
   1 Hz, a fix on the other leg of a 5–8 m hairpin, 10 m past it, with the
   window ending before it, is refused (the first version placed it on the
   near leg of the 5, 6 and 8 m ones); laps of 6–8 m hairpins and of a 20° figure-eight with 80 m
   diagonals at 1 and 2 Hz, on the line and 3–4 m either side of it, four
   top speeds, with and without 1 m of GPS error, are never more than 10 m
   out (the first version and the code before FET-257 were). The
   figure-eight, hairpin and cold-start truth tests of FET-256 are
   unchanged. An apex cut of 6 m holds in a 15 m hairpin (2 fixes
   dropped before) and drops 18 fixes in a 10 m one, as before.
   After, real day: 192,782 of 193,764 fixes are projected (191,686
   before, 193,066 with the first version). Of the 982 left, 673 are more
   than 20 m from the axis (671 on a cold start, 2 while locked), 254 are
   refused while locked well inside a bend, 37 while locked as ambiguous,
   and 18 more on the cold starts after those (17 ambiguous, 1 nearer the
   other leg). 46 of the 150 lap projections are split (89 before, 13 with
   the first version): 8 by fixes more than 20 m from the axis (the lap of
   the off-track excursion on all six axes, and one lap that runs more than
   20 m from two of the axes for a few metres), 38 by fixes refused inside
   a bend. Every projected fix still agrees with the nearest point of the
   axis followed along the lap (0.00 m apart). The 25 timed laps, the best
   lap (1:49.898) and the theoretical best (107.905 s over 14 segments)
   are unchanged, every segment's fastest time is the same, and every lap
   of its table is timed through all 14 segments (14 of 23 before). The
   RCZ files, projected the same way (144 lap projections, 430,590 fixes),
   project 428,105 fixes instead of 425,750 and split 77 projections
   instead of 101 (68 with the first version; most of the rest by the
   heading rule on 25 Hz GPS jitter, 145 fixes, or inside a bend, 572);
   their theoretical best (107.812 s over 14 segments, every segment's
   time the same) is unchanged, with 13 of 22 laps timed through every
   segment instead of 9.

   Limits. A fix the window's runner-up does not refuse is not checked
   against the rest of the axis, as before FET-257: at 1 Hz a fix 6–8 m
   off one leg of a 3–4 m hairpin, on the other leg beyond the window, is
   placed on the near leg. A lap driven further inside a bend than half its
   radius loses those fixes. At 1–2 Hz, laps of 3–5 m hairpins and of small
   figure-eights (80–200 m diagonals, 10–30°) still have fixes misplaced by
   more than 10 m, before FET-257 and after it.
2. **Fixed (FET-256): a cold start in the middle of a lap could lock on to
   the wrong branch, and one wrong fix then shifted the rest of the lap by
   whole laps.** Before the fix, after a refusal `projectLapTrace` restarted
   with no previous fix, so the next fix was placed by distance and the ratio
   alone, with no heading check. Its progress then became the reference for
   unwrapping, and every later segment was unwrapped past it, a lap length or
   more out. Synthetic, before the fix:
   - Figure-eight with 300 m diagonals, GPS back after a 30 m gap (lines −1,
     0 and +1 m off the centre line, five seeds, the gap's end every metre
     from 30 m before to 30 m after the crossing: 915 trials per angle): 50
     trials locked on to the other diagonal at a 90° crossing (GPS back 4 to
     1 m before it), 45 at 30° (10 m before to 3 m after) and 118 at 10°
     (18 m before to 14 m after). The error was one lap: 2,015 m, 895 m and
     688 m. 40 m before the crossing it always found the right branch.
   - Parallel straights driven in opposite directions: a lap more than
     separation / 1.7 off its line toward the other straight (8.8 m at 15 m
     apart, 11.8 m at 20 m, 17.6 m at 30 m) is refused while locked
     (finding 1), and was then re-acquired on the other straight: 14, 12 and
     10 of 15 laps (0.55–0.65 of the separation off, five seeds) at 15, 20
     and 30 m apart; a lap 0.5 m beyond separation / 1.7 off was out by
     1.3–1.4 km, about two laps. At 7 m off it stays on its own straight
     (tested).
   - Hairpins cut by 40% with 1 m of GPS error: in a 3 m hairpin a fix
     midway between the legs locked on to the other leg (18.4 m out over
     five seeds, 8 fixes misplaced over 20). The other leg is within 30 m
     along the axis, so the cold-start ratio never compared it. In a 5 m
     hairpin one lap re-acquired 3.7 m behind its last fix and, within the
     30 m allowance of `_segmentStartBackwardMeters`, stayed on its lap.

   The fix (FET-256, with the fixes of its review) only refuses fixes or
   drops a run of them (a gap, never a guess):
   - The direction of travel is kept after a fix the projection refused,
     across a raw GPS gap of up to 5 s (`_maximumGapSeconds`; at 25 Hz three
     missed fixes are one), and from the last fix before the lap, if it is
     at most 5 s old, for the lap's first fix. So the cold start after them
     has the heading check. It is forgotten after a longer gap or a fix with
     no coordinate, and while the lap stands a cold start takes no heading
     from less than 0.5 m of movement (GPS jitter).
   - A cold start also compares the nearest part of the axis within the
     30 m separation that runs the other way from the match (a hairpin's
     other leg) with the same 0.7 ratio, unless the car's movement fits the
     match better than that leg.
   - The first fix of a segment after a gap may lie no further ahead of the
     lap's last projected fix than 100 m/s times the time since, plus the
     30 m allowed behind (`_maximumPlausibleSpeedMetersPerSecond`);
     otherwise it matched another branch and is refused. The lap's first
     fix has no such bound, since a lap may be timed from another line than
     the axis gate.
   - A short run of the latest segments (less than a quarter of the axis)
     is dropped as being on another branch, and the fix continues from the
     lock before it (the gate at the lap's start time before the first
     segment), when a segment's first fix shows it up in either of two ways.
     Behind: the fix lies further ahead than the lap's own speed (1.5 times
     its fastest progress over a second, at least 40 m/s) could have taken
     it since the last projected fix, but from the lock before the run it
     lies more than 30 m behind where the run started and within the
     100 m/s reach. Ahead (the re-review): the fix is out of the run's
     100 m/s reach, but the lock before the run could have reached it at
     the lap's own speed.

   Without the first rule the parallel straights fail, without the second
   the 3 m hairpin, without the third the figure-eight with 30 m gaps, and
   without the fourth the figure-eight with longer gaps. After the fix
   (`test/analysis/cold_start_branch_test.dart`), no lap has a fix on the
   wrong branch or a segment shifted in: the 2,745 figure-eight trials with
   30 m gaps; 2,511 with 100–400 m gaps (before: 12–45 of 279 per angle and
   gap; with the first version of the fix 31 and 33 of 279 at 10° after 200
   and 400 m, 10 at 30° after 400 m, shifted by 683–891 m); 45
   parallel-straight laps; 1,782 laps with a raw gap of 5–40 m on a
   straight (before 506, 462 and 396 of 594 at 15, 20 and 30 m apart; with
   the first version 92, 80 and 74, whose wrong segments covered progress
   the car had not reached, so a sector time read from them came out about
   3 s early in the review's measurement); 351 laps with a gap at the lap's
   start (before 89, 85 and 78 of 117 moved on by whole laps; with the
   first version 18 of 117 with fixes up to 140 m out); 2,196 trials with
   one gap of 300–400 m on the 10° figure-eight and 600 m on the 30° one
   ending within 30 m of the lap's second pass of the crossing (19, 50 and
   63 of 549, and 15, with every fix after the gap refused and the lap
   ending about 400 m short before the "ahead" drop); and 40 hairpin laps
   (3 and 5 m radius, 20 seeds each; the 5 m one passed before the fix too
   and is a guard). A car at 95 m/s with gaps of 50–1,000 m and one at 40
   m/s with gaps of 10–900 m keep every fix, and so does a lap timed from a
   line 20–100 m either side of the axis gate (at 40–100 m it lost its
   first 2–18 fixes to a bound on the lap's first fix, since removed). A
   car standing for a minute keeps 6,133 of 7,115 fixes (five seeds; 6,215
   before the fix, 5,880 with its first version).
   What is left (`projection_findings_test.dart`): the figure-eight trials
   with 30 m gaps leave 60, 82 and 357 fixes unprojected in all at 90, 30
   and 10 degrees, the worst projected fix 1.3 m out; the parallel-straight
   lap 0.5 m beyond separation / 1.7 off keeps 137 of 186, 144 of 193 and
   156 of 205 fixes, within 0.8 m: the fixes nearer the other straight
   than 0.7 of the way are refused while locked (finding 1). With GPS error as large as the
   hairpin, the worst fix over five seeds is 5.7 m out in a 3 m hairpin and
   6.2 m in a 5 m one, never more than 2 m beyond the fix's own distance
   from the car, and a segment re-acquires at most 1.0 m behind the last.
   The same test pins, rule by rule, the fixes refused on the shapes of the
   review and the re-review, and checks that its replay keeps exactly the
   fixes `projectLapTrace` keeps.

   Limits. A lap can still lock on to another branch, and move on by a lap,
   when: the direction of travel is forgotten (a raw gap longer than 5 s, a
   fix with no coordinate, a lap with no fix in the 5 s before it) or the
   car stands, and a parallel section driven the other way is the nearer
   branch; a wrong run covers a quarter of the axis or more, so it is kept;
   or a gap is longer than (L − 60 m) / 100 m/s and no drop applies. A
   wrong run is dropped only when the first fix of a later segment shows it
   up as above, so a wrong run that ends the lap, or one that lies less than
   30 m from where the car is (a hairpin's other leg just ahead), keeps its
   misplaced fixes; the fixes after it are not moved on by a lap. For the
   lap's first segment the lock before it is the gate at the lap's start
   time, which is off by the timing line's distance from the axis gate when
   the lap is timed from another line. A real car that drove nearly a whole lap during one gap,
   faster than its own margin, right after a short run could have that run
   dropped and be placed a lap back.
   The real day has no crossing or parallel section within 20 m, and none of
   its fixes was misplaced before the fix. It is unchanged: the same 191,686
   of 193,764 fixes are projected, at the same progress, and laps, best laps
   and the theoretical best are identical. Its RaceChrono RCZ files (25 Hz),
   projected the same way, lose 45 fixes and gain 31 in 10 of the 150 lap
   projections (444,742 projected instead of 444,756; no fix moves), all
   with the first version of the fix and none more since; their
   theoretical best (107.812 s over 14 segments) is unchanged.
3. **Fixed (FET-257): a fix up to 20 m beyond the 150 m forward window was
   placed at the window's end.** Synthetic, before the fix: at 45 m/s with
   3.4 s between fixes (153 m) the lap stayed one segment with errors of
   15 m. Now a fix whose nearest point lies beyond the forward end of the
   window (the match is the window's last segment, at its end) is refused,
   and the next fix is a cold start on the whole axis: the same lap keeps 9
   of its 17 fixes in 9 segments, at most 0.18 m out, and laps with 3.4–3.8 s
   between fixes are never misplaced (`locked_off_line_test.dart`). It
   needs more than 150 m between two fixes of one sampled segment, which
   `sampledSegments` allows only below about 0.3 Hz; at 10 Hz fixes are
   4.5 m apart at 45 m/s, and on the real day no fix is refused this way.

Smaller limits at 10 Hz, which drop fixes and misplace none in these tests (at
1–2 Hz, see the limits of finding 1): in hairpins of 3 and 5 m radius cut by
40%, 4 of 855 and 3 of 890 fixes are dropped; an apex cut of 6 m drops 18 of
193 fixes in a 10 m hairpin and holds in a 15 m one (4.5 m holds in both).
Parallel straights down to 2 m apart keep every fix while locked.

## Progress, axis length and point spacing (FET-251)

`ProgressAxis.lengthMeters` is the raw reference path's length, as in Overlays;
`cumulative` adds up the straight lines between the resampled points and is
shorter (VBO axes of the real day 3.6 m, RCZ axes 19.4 m, a 150 m synthetic zigzag
circle 26 m). Making `lengthMeters` the chord length (with or without
`spacingMeters`) fails 191 of 497 tests in `test/parity`, so it stays a departure
to agree with the owner. Converting progress to a point uses the cumulative
distances (`nearestAxisIndex`) in the driver profile's corner positions: before,
`progress / spacingMeters` was up to 2 m off on the VBO axes and up to 13.9 m
(7 points) off on the RCZ axes of the real day. `corner_phases.dart` still takes
a curvature region's width as point count times mean spacing: using the samples'
own progress moves the apex progress and tolerance in `corner_analyzer_parity`
and `corner_metrics_parity` by up to 0.27 m, so it is a departure too
(`axis_progress_conversion_test.dart`, skipped test).

Profiles already stored keep the corner positions the old conversion gave them;
they are not migrated. Matching a re-analysed day to a track's corners is by
overlap (at least half of the shorter span), not by a distance, so a corner
moved by up to 13.9 m (0.7% of a 2 km lap) still merges instead of becoming a
duplicate (`profile_aggregates_test.dart`, "measured at its old position"). Only
a corner shorter than about twice the shift (under ~28 m) could fail to merge.

`corner_classes.dart` (`along()`, FET-220) turns progress into a sample index the
same way, by dividing by `spacingMeters`, and is left alone for the same reason
(KAN-244). Changing it leaves `test/parity` green, but no parity fixture
exercises corner classes, so that is no evidence that it is safe.
