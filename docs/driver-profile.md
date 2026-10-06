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
  `theoreticalBestSeconds`, `startMilliseconds`, each session's `stats` and
  `weather`) are rebuilt from the day's analysis whenever the day is added
  again (`addDayToProfile`).
- The profile also keeps what each session measured (`stats`), so analysis
  across days never re-opens old days. It stores measurements only, in SI
  units, each with the laps behind it; levels, trends and repeated losses are
  worked out when read (see "Across days").
- It also keeps a copy of each session's weather (`weather`), so the day page
  can compare a visit's weather with today's without opening the old day.
  The day document's `event.runs[].weather` stays the source.
- And a copy of each session's setup as the day was saved (`setup`): tyre
  pressures, tyre and fuel the driver entered. The day document's
  `event.runs[].setup` stays the source.

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
              { "cornerId": "<track corner id>", "segmentId": "<day segment id>", "laps": 3,
                "minimumSpeed": 18.5, "bestMinimumSpeed": 19.4,
                "exitSpeed": 23.1, "bestExitSpeed": 23.6,
                "brakingSpreadMeters": 6.2, "lossSeconds": 0.31 }
            ]
          },
          "weather": {
            "sourceRevision": "<recording SHA-256>",
            "temperatureC": 21.4, "temperatureMinC": 19.2, "temperatureMaxC": 22.6,
            "condition": "overcast", "precipitationMm": 0.0,
            "windSpeedKmh": 12.3, "windDirectionDegrees": 225.0
          },
          "setup": {
            "version": "session-setup-v1", "pressureUnit": "bar",
            "coldPressure": { "fl": 2.1, "fr": 2.1, "rl": 2.0, "rr": 2.0 },
            "hotPressure": { "fl": 2.45, "rr": 2.3 },
            "tyre": "Pirelli SC2", "fuelStartLitres": 8.5
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
| `corners[]` | Per track corner, over the session's ranked laps: `segmentId` (from FET-184: the day's theoretical-best segment placed on this corner when the day was added; absent in profiles written before), `laps`, median and highest `minimumSpeed` and `exitSpeed` (m/s; absent without a speed unit), `brakingSpreadMeters` (interquartile range of the braking point, 3 laps or more), `lossSeconds` (median time lost there against the group's fastest). From FET-165 also: `liftSeconds` (median time from the last lift off the throttle to a measured braking point, 0 when the pedals overlap; the lift is looked for from 150 m before the corner, or the lap's start, and coasting with both pedals off through all of that counts as that long, unless the throttle is never pressed in the session (an unplugged pedal logging zeros); needs throttle and brake), `releaseSpreadMeters` (interquartile range of where a measured braking ends), median and highest `decelerationG` / `bestDecelerationG` (mean deceleration through a measured braking, never one inferred from G alone, g; needs longitudinal G in g, also unlabelled as the G-G diagram reads it, or m/s²), `entrySpeedSpread` (interquartile range of the speed at the corner's start, m/s), `lineSpreadMeters` (interquartile range of the line across the track at the apex; only when the recording states a median GPS accuracy of 0.25 m or better for at least half the laps, half the closest band), `pickupSpreadMeters` (interquartile range of the measured throttle pickup at or after the slow point), `throttleKnownLaps` and `releasedPickups` (laps whose throttle is known from the end of a measured braking to the slow point, and of them those with a pickup released again in between) and `sequenceLossSeconds` (the median time the faster half of the laps through the corner lost in the segment right after it, less the slower half's, at least 0; 4 laps or more). Pedal readings are the coach's (`coachCornerPassages` in `day_coach.dart`); spreads need 3 laps. The app measures a day off the UI thread (`ProfileLibrary.recordDay`). |

A day's `theoreticalBestSeconds` is its track's theoretical best (the chosen
group's). Days re-added before their theoretical best is worked out, or when it
failed, keep the corners and theoretical bests measured before.

A whole profile keeps at most 30 000 session corners
(`maximumProfileCornerStats`, halved from 60 000 when FET-165 added nine
figures per corner); past it, a new day is added without its corners and a
day already in the profile keeps the corners it had, so a profile written
under the larger budget loses none.
10 000 days of 5 sessions with that many corners stay under the 32 Mi characters
on a few tracks; each track adds about 4.5 Ki (16 Ki with 128 corners), so
hundreds of tracks on top of that would exceed the limit (not budgeted yet).

## A session's weather (`weather`)

All optional; added in the same version 1 (FET-132), so an older app keeps
it as an unknown key and a profile without it reads as before. It copies a few
values of the session's `WeatherSummary` (`session_weather.dart`), the weather
model's values for the area around the track at the session's time, not a
measurement at the track. Values stay in the units the day stores them in; they
are never converted. Absent values are left out, and a session with none of
them has no `weather`.

| Key | Meaning |
|---|---|
| `sourceRevision` | The SHA-256 of the recording the weather is for (the day weather's `sourceRevision`). |
| `temperatureC` | Air temperature at the session's middle, °C. |
| `temperatureMinC`, `temperatureMaxC` | Lowest and highest air temperature from the session's start to its end, °C. |
| `condition` | The worst weather of the hours nearest the session: a `WeatherCondition` name (`clear`, `partlyCloudy`, `overcast`, `fog`, `drizzle`, `rain`, `snow`, `showers`, `thunderstorm`). |
| `precipitationMm` | Rain (and melted snow) over the hours the session ran in, mm. |
| `windSpeedKmh` | Wind speed at the session's middle, km/h. |
| `windDirectionDegrees` | Where the wind comes from, degrees clockwise from north. |

Reading checks each value against the ranges a day's stored weather uses
(`weatherValueRanges`: −90 to 60 °C, 0 to 500 mm, 0 to 500 km/h, 0 to 360°);
a value out of range or not a number is left out rather than refusing the
profile, and so is a `sourceRevision` that is not a string of 1 to 128 code
units. A `condition` this version does not know (a newer version's) is kept
as written and written back unchanged; the app shows it as conditions it does
not know. `weather` that is not an object is refused, like `stats`.

The app records the weather the day page shows for each session: weather kept
in the day document, or fetched while the day is open. Nothing is looked up
for the profile, so with weather lookup off only weather the day already kept
is recorded. Each save that records the day (`ProfileLibrary.recordDay`)
passes it. Weather usually arrives after that save; it then goes to the
profile on its own (`ProfileLibrary.recordWeather`, `setProfileSessionWeather`),
which swaps only the sessions' `weather` and measures nothing again. The page
gives it only while the day has no unsaved changes, so it goes only to the
sessions of the saved day the profile lists; on a day with unsaved changes it
waits for the save (a library day saves itself after 2 s). Sessions the
profile does not list are left out. The library also holds the latest
weather given for each day and applies it over the weather of a
`recordDay` that finishes later (`ProfileDayInput.withWeather`, only for
the same recording), so weather given while the day is measured, before it
is in the profile, or when a measure fails is not lost.

A day added again without a session's weather keeps the weather that session
had while it is the weather of the same recording: when the session's
recording revision (from its lap rows) differs from the kept
`sourceRevision`, the kept weather is dropped. Weather without a
`sourceRevision`, or a session without lap rows, keeps it. New weather
replaces the old whole. Days added before FET-132 get their weather when they
are next opened, if their document holds it.

"Last time here" on the day page shows each visit by the session that set the
day's best lap (`bestLapSeconds` equal to the day's), labelled "best lap";
when that session has no weather, by its first session with weather, labelled
as such. Today without weather in the profile says why from the page's
weather state (being looked up, lookup off, service not reached, no time or
position, not saved yet, or stored by a newer version).

## A session's setup (`setup`)

Optional; added in the same version 1 (FET-188), so an older app keeps it as
an unknown key and a profile without it reads as before. It is the run's
`setup` object of the day document (`session-setup-v1`, `run_setup.dart`)
as the day was saved, copied as it is (`ProfileSetup`): `version`,
`pressureUnit` (`bar` or `psi`), `coldPressure` and `hotPressure` (`fl`,
`fr`, `rl`, `rr`), `tyre` and `fuelStartLitres`. Pressures stay in the unit
the driver entered them in and are never converted.

It is read as the day reads it (`RunSetup.fromJson`): a value that is
missing, of the wrong type or out of range (bar 0.5–6.0, psi 7–90, fuel
0–200 l, at most two decimals, tyre at most 160 code units) reads as not
entered, pressures without a unit are not entered, and a setup of another
`version` is read as far as it can be. None of this refuses the profile.
Keys this version does not know, in the object and in its pressure objects,
and values read as not entered are kept as stored and written back
unchanged. A `setup` that is not an object reads as no setup and is kept as
it is; one holding nothing but its `version` is no setup.

Unlike `weather`, it has no `sourceRevision`: the setup is the driver's own
statement about the run, not something measured from the recording, so a
replaced recording keeps it. It reaches the profile only when the day is
saved: each save that records the day (`ProfileLibrary.recordDay`) passes
every run's setup as saved (`DayResultsController.savedRunSetup`), never an
unsaved edit. Given that way, a session's setup replaces what the profile
had, and a run without one clears it. A day added without setups, such as a
day found in the days folder (`ProfileDayInput` without
`ProfileDayInput.fromAnalysis`'s `setups`), keeps the profile's. New weather
(`setProfileSessionWeather`) and moving the profile to another device
(`mergeDriverProfile`, the bundle) carry it along.

"Last time here" shows each visit's setup as entered, chosen as its weather
is: the session that set the day's best lap, else its first session with a
setup, labelled as such. When both visits entered pressures in the same unit,
it adds today minus then for each wheel entered on both (no colour: higher
is not better); in different units it shows both and says they are not
compared. Today without a setup in the profile says, for the session that
set the best lap (else the first), that none was entered, and that it comes
with the save when that session's setup was entered on the page and the day
is not saved yet (`DayResultsController.runSetupWaitsForSave`).

## Corners across days

A track's `corners` are the same places on every visit, as fractions of the
track's stored route (`start` > `end` crosses the start line). A day's corner
is placed by the route point nearest its start and end (within 50 m), and
takes the id of the known corner it overlaps by at least half (of either) and
that no other corner of that day took; otherwise it is added, with the day's
name for it. A span over half a lap is not a corner. A recording
whose longitudes count west as positive is turned around first.
`matchTrackCorners` finds the same ids for a day's spans without adding any.

Each session corner keeps the segment it was placed from (`segmentId`), and
`dayCornerIds` reads a day's segment-to-corner ids back from them, so the day
page names the corner its figures are kept on (FET-184). A later day can add a
corner that fits a span better, and matching again would then name that corner
instead, so the kept id always wins; `matchTrackCorners` only fills the
segments without one (days added before FET-184, a corner without ranked laps
in any session, corners kept past the budget). A day added again keeps the
segments of the corners it keeps; a merged day keeps its segments, its corner
ids moved to this track's. An older app drops the key when it measures the
day's corners afresh, and keeps it with its corner when it adds the day again
without measuring, so the pair stays consistent either way. If a day's
segments are edited and adding it again cannot measure its corners, a kept id
names the old placement until the next measured add.

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
- `cornerBefore`: by the same rule, one corner on the visits before a day in
  its car: visits, how many measured it and lost time there, the last loss and
  whether it is fixed.
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
  | throttleCommitment | all corners' `releasedPickups` / `throttleKnownLaps` (3 or more passes, 3 or more ranked laps), % of passes | 5, 15, 30, 50 % |
  | exitSpeedExecution | day's best − `exitSpeed` | 1, 3, 6, 9 km/h |
  | cornerSequenceManagement | `sequenceLossSeconds` | 0.02, 0.05, 0.1, 0.2 s |

  Minimum speed, exit speed and braking effectiveness compare against the
  day's best at the corner, so a day with more laps sets a higher best.
  | paceConsistency | `lapSpreadSeconds` | 1, 2.5, 5, 8 s |

  A skill none of the window's sessions measured (no pedals, no G, no stated
  GPS accuracy, or days added before FET-165) says "needs more evidence". The
  bands are a first setting from one real day (Jastrząb, 2026-08-29: every
  skill between level 2 and 5) and are tuned in `skillCatalogue`; stored data
  never changes.

## Moving a profile to another device (`profile_bundle.dart`, FET-133)

`writeProfileBundle` writes the profile, its days and their recordings to one
zip file, also with the `.feprofile` extension (the index alone is
`driver.feprofile`; a bundle is any other name):

- `bundle.json`: `{"format": "flappedear-profile-bundle", "version": 1}`.
- `driver.feprofile`: the profile as it is.
- `Days/<eventId>.fetproject`: each day's document, its telemetry references
  rewritten to `../Recordings/<name>` (the absolute path is dropped, unknown
  keys kept).
- `Recordings/<name>`: each recording once, however many days use it; a
  recording not found is left out and counted (`recordingsMissing`), and its
  day still comes along and reports it missing when opened.

Recordings are deflated as they are added; the encoder keeps one recording's
compressed bytes in memory at a time (about twice that at most), which is fine
for VBO files of tens of megabytes. The bundle is written to `<target>.partial` and renamed. The app writes it in
its temporary folder and then copies it where the user chose (a sandboxed Mac
app may only write the chosen file) or shares it (phones).

`readProfileBundle` accepts only those names (no `..`, no nested folders, no
drive letters, Windows device names or trailing dots, no other files) and the
known format with an integer version from 1 to the current one. Every entry is
unpacked in pieces, never past the size it declares (only stored or deflated,
unencrypted entries), and must match its CRC-32; each
day's document must be that day (`event.id`), and each recording the SHA-256
its day names. Anything else throws `ProfileBundleError`.

It never replaces: a day the profile has, or whose document already exists in
`Days/`, is left as it is (`alreadyHere`). The other days are merged by
`mergeDriverProfile`: a car joins this profile's car with the same id or name
(ignoring case and leading or trailing spaces), a track the one with the same
id or circuit (`routesMatch`), its corners placed on this track's as a day's
are; anything else is added within the profile's limits (`notAdded`
otherwise, leaving no car or track of its own).

All of it is read and checked first: the documents in memory, the recordings
unpacked into a `.bundle-import-*` folder beside the index. Only then are the
recordings moved into `Recordings/` and the documents written; a failure there
removes what this import wrote, and a staging folder left by a crash is removed
by the next import. A recording already in `Recordings/` is reused only when
its SHA-256 is the one the day names; another file of that name makes the new
one `name (2)`. The caller writes the merged profile: the app merges it into
the profile as it is by then, so a day recorded during the import is kept, and
says so when the profile cannot be written (the days then come back through
the unlisted-days scan at the next start, under the last car).
