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
  `startMilliseconds`) are rebuilt from the day's analysis whenever the day is
  added again (`addDayToProfile`).

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
      }
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
      "sessions": [
        { "runId": "...", "name": "Session 1", "startMilliseconds": 1788076800000,
          "lapCount": 4, "bestLapSeconds": 124.053 }
      ]
    }
  ],
  "lastCarId": "<car id>"
}
```

Limits: 64 cars, 1024 tracks, 10 000 days, 64 sessions a day, 4096 code units a
text. A day names a car and (unless `null`) a track of the profile; ids are
unique. `file` is a relative path inside the profile folder (no `..`).
Times are within the range a date can hold; route points are within 50 km of
the origin; values kept from a newer version nest at most 64 deep. Adding a day
refuses what reading would refuse, so the app never writes a profile it cannot
read back. A profile written by a newer version is refused, never rewritten.

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
