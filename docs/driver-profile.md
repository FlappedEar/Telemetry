# The driver profile (`.feprofile`)

The driver profile keeps the driver, their cars, the tracks they drove and
every day kept on the device, so analysis can look across days. It is read and
written by `telemetry_core` (`lib/src/profile/`). Days stay `.fetproject`
documents; the profile never changes their format.

## What is authoritative where

- The profile: the driver, the cars, track names and routes, and which car each
  day was driven in.
- The day document: its sessions, laps, notes, conditions and setup changes.
  A day's `summary` fields in the profile (`sessions`, `bestLapSeconds`,
  `theoreticalBestSeconds`, `startMilliseconds`, each session's `stats`) are
  rebuilt from the day's analysis whenever the day is added again
  (`addDayToProfile`).
- The profile also keeps what each session measured (`stats`), so analysis
  across days never re-opens old days. It stores measurements only, in SI
  units, each with the laps behind it; levels, trends and repeated losses are
  worked out when read (see "Across days").

## Format, version 1

UTF-8 JSON, at most 32 Mi UTF-16 code units. Every object keeps keys this
version does not know, so a newer app's additions survive a re-save.

```json
{
  "format": "flappedear-driver-profile",
  "version": 1,
  "driver": { "id": "<32 hex>", "name": "" },
  "cars": [ { "id": "<32 hex>", "name": "My car", "notes": "" } ],
  "tracks": [
    {
      "id": "<32 hex>",
      "name": "Jastrząb",
      "route": {
        "origin": [52.0, 21.0],
        "lengthMeters": 2061.4,
        "direction": "clockwise",
        "points": [[0.0, 0.0], "... 256 [east, north] metres from origin"]
      },
      "corners": [
        { "id": "<32 hex>", "name": "Corner 1", "start": 0.0621, "end": 0.1143 }
      ]
    }
  ],
  "days": [
    {
      "eventId": "<the day document's event.id>",
      "file": "Days/<eventId>.fetproject",
      "name": "Day 2026-08-29",
      "carId": "<car id>",
      "trackId": "<track id, or null>",
      "startMilliseconds": 1788076800000,
      "bestLapSeconds": 109.898,
      "theoreticalBestSeconds": 108.2,
      "sessions": [
        { "runId": "...", "name": "Session 1", "startMilliseconds": 1788076800000,
          "lapCount": 4, "bestLapSeconds": 124.053,
          "stats": {
            "distanceMeters": 11890.0, "drivingSeconds": 760.4,
            "rankedLaps": 3, "medianLapSeconds": 125.1, "lapSpreadSeconds": 1.2,
            "theoreticalBestSeconds": 122.9,
            "corners": [
              { "cornerId": "<track corner id>", "laps": 3,
                "minimumSpeed": 18.5, "bestMinimumSpeed": 19.4,
                "exitSpeed": 23.1, "bestExitSpeed": 23.6,
                "brakingSpreadMeters": 6.2, "lossSeconds": 0.31 }
            ]
          } }
      ]
    }
  ],
  "lastCarId": "<car id>"
}
```

Limits: 64 cars, 1024 tracks, 10 000 days, 64 sessions a day, 128 corners a
track or session, 4096 code units a text. Speeds are at most 200 m/s; corner
`start`/`end` are fractions from 0 (inclusive) to 1 (exclusive). A day names a car and (unless `null`) a track of the profile; ids are
unique, and so are a day's session run ids. `file` is a relative path inside
the profile folder: no drive, `:`, empty, dot-only or trailing-dot or -space
segment. Times are within the range a date can hold less two days; route points are within 50 km of
the origin; values kept from a newer version nest at most 64 deep and hold no number too
large for a double. Adding a day
and writing a profile refuse what reading would refuse, so the app never writes
a profile it cannot read back. A profile written by a newer version is refused, never rewritten.

## Tracks across days

A day document's `layoutId` is new on every day, so it cannot recognise a
circuit on another day. The profile keeps the route of the day that first added
the track: the 256-point lap shape from track inference, in metres east and
north of the start line, rounded to 0.1 m. A new day's route belongs to the
first track it matches with `routesMatch` (same direction, length within 5 %,
every point within 25 m of the other path, RMS at most 10 m); a route no track
matches adds a track. A day added again without a route (recordings missing,
every lap left out) keeps its track. The first match wins; choosing the closest
of several matching tracks, and merging tracks, are left for later.

## Cars

Adding a day never asks. A new day takes the car of the last new day or the
last day moved to another car (`lastCarId`), else the first car, else a new car
with the name the app passes (`defaultCarName`). A day added again keeps its car
and does not change `lastCarId`.

## The library tree

`profileTree` groups days as Car > Year > Track > Date > Days (sessions are in
each day). Years and dates are the device's local date of the first session;
undated days and days without a recognised track come last.

## What a session measured (`stats`)

All optional; added in the same version 1, so an older app keeps them as
unknown keys. Absent values are left out, and values are rounded to a
thousandth. A measurement out of range (a GPS spike, a speed in another unit
than declared) is left out rather than refusing the day. A session without `stats` was added before them, or not measured
yet; it still counts in days, sessions and laps.

| Key | Meaning |
|---|---|
| `distanceMeters`, `drivingSeconds` | Speed integrated over time (a speed in a declared or assumed unit), else the GPS path; gaps over 1 s are skipped. Driving is above 2 m/s. Out and in laps included. |
| `rankedLaps`, `medianLapSeconds`, `lapSpreadSeconds` | Ranked laps of the session's group; median; interquartile range (3 laps or more). |
| `theoreticalBestSeconds` | The session's own fastest segments added up, when every segment was timed on one of its ranked laps. |
| `otherLayout` | `true` when the session was on another layout than the day's track: it counts in totals only. |
| `corners[]` | Per track corner, over the session's ranked laps: `laps`, median and highest `minimumSpeed` and `exitSpeed` (m/s; absent without a speed unit), `brakingSpreadMeters` (interquartile range of the braking point, 3 laps or more), `lossSeconds` (median time lost there against the group's fastest). From FET-165 also: `liftSeconds` (median time from the last lift off the throttle to a measured braking point, 0 when the pedals overlap; needs throttle and brake), `releaseSpreadMeters` (interquartile range of where a measured braking ends), median and highest `decelerationG` / `bestDecelerationG` (mean deceleration while braking, g; needs longitudinal G in g, also unlabelled, or m/s²), `entrySpeedSpread` (interquartile range of the corner entry speed, m/s), `lineSpreadMeters` (interquartile range of the line across the track at the apex; only when the recording states a median GPS accuracy of 1 m or better for at least half the laps), `pickupSpreadMeters` (interquartile range of the measured throttle pickup at or after the slow point), `releasedPickupShare` (0–1, of 3 or more laps whose throttle is known from the end of braking to the slow point, those with a pickup released again in between) and `sequenceLossSeconds` (the best lap's time through the corner and the segment after it, less the best of each added: what a faster corner gave away after it, or the reverse). Pedal readings are the coach's (`coachCornerPassages` in `day_coach.dart`); spreads need 3 laps. |

A day's `theoreticalBestSeconds` is its track's theoretical best (the chosen
group's). Days re-added before their theoretical best is worked out, or when it
failed, keep the corners and theoretical bests measured before.

A whole profile keeps at most 30 000 session corners
(`maximumProfileCornerStats`, halved from 60 000 when FET-165 added nine
figures per corner); past it, a day is added without its corners.
10 000 days of 5 sessions with that many corners stay under the 32 Mi characters
on a few tracks; each track adds about 4.5 Ki (16 Ki with 128 corners), so
hundreds of tracks on top of that would exceed the limit (not budgeted yet).

## Corners across days

A track's `corners` are the same places on every visit, as fractions of the
track's stored route (`start` > `end` crosses the start line). A day's corner
is placed by the route point nearest its start and end (within 50 m), and
takes the id of the known corner it overlaps by at least half (of either) and
that no other corner of that day took; otherwise it is added, with the day's
name for it. A span over half a lap is not a corner. A recording
whose longitudes count west as positive is turned around first.

## Across days (`profile_aggregates.dart`)

Worked out when read; lap times compare only on the same track (one direction)
and, when a car is given, the same car; sessions on another layout and, for
records, sessions measured before `stats` existed count only through the day's
best lap. Totals mix everything. Days run in date order; undated days come
last.

- `driverTotals`, `carTotals`, `trackTotals`: days, sessions, laps, ranked
  laps, distance and driving time (of measured sessions), tracks, cars, first
  and last day.
- `trackRecords`: per track, visits, the best lap, the best day theoretical
  best and the best session median, each with its day.
- `trackProgress`, `lastTimeHere`: per visit, best, theoretical best, typical
  lap and spread (sessions averaged by ranked laps) and the gain against the
  visit before; the last visit prefers the same car.
- `cornerHistory`: a corner's figures on every visit.
- `repeatedLosses`: corners among a visit's three costliest (0.1 s or more) on
  two visits or more; active, fading (two visits since, fewer than two of them measuring it) or
  fixed (measured without a loss on the two visits since).
- `skillLevels`: the 12 skills of `skillCatalogue`, each level 1–5 = 5 − bands
  exceeded, over the last 3 days that measured it; confidence from its ranked
  laps (low below 5, medium below 15, high from 15); trend against the 3 days before.
  Each is the median over a session's corners (sessions weighed by ranked
  laps), lower is better:

  | Skill | Measure | Bands |
  |---|---|---|
  | liftTiming | `liftSeconds` | 0.2, 0.4, 0.7, 1 s |
  | brakePointConsistency | `brakingSpreadMeters` | 4, 6, 9, 14 m |
  | brakeReleaseTiming | `releaseSpreadMeters` | 6, 9, 14, 21 m |
  | brakingEffectiveness | day's best `bestDecelerationG` at the corner − `decelerationG` | 0.03, 0.06, 0.1, 0.15 g |
  | turnInConsistency | `entrySpeedSpread` | 2, 4, 6, 9 km/h |
  | minimumSpeedControl | day's best − `minimumSpeed` | 2, 4, 6, 9 km/h |
  | lineConsistency | `lineSpreadMeters` | 0.5, 1, 1.5, 2.5 m |
  | throttleReapplication | `pickupSpreadMeters` | 4, 6, 9, 14 m |
  | throttleCommitment | mean `releasedPickupShare` over corners, % of passes | 5, 15, 30, 50 % |
  | exitSpeedExecution | day's best − `exitSpeed` | 1, 3, 6, 9 km/h |
  | cornerSequenceManagement | `sequenceLossSeconds` | 0.02, 0.05, 0.1, 0.2 s |
  | paceConsistency | `lapSpreadSeconds` | 1, 2.5, 5, 8 s |

  A skill none of the window's sessions measured (no pedals, no G, no stated
  GPS accuracy, or days added before FET-165) says "needs more evidence". The
  bands are a first setting from one real day (Jastrząb, 2026-08-29: every
  skill between level 2 and 5) and are tuned in `skillCatalogue`; stored data
  never changes.
