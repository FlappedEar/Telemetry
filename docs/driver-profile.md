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
      ],
      "notebook": {
        "notes": "Bumpy braking into Corner 1",
        "corners": [ { "cornerId": "<track corner id>", "note": "Brake at the 100 board" } ],
        "toTry": [ { "id": "<32 hex>", "text": "Third gear in Corner 2", "done": false } ]
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

## Track notebook (`notebook`, FET-231)

What the driver writes down about a track for the next visit: general `notes`,
a note per corner and things to try. It is kept on the track, not on a day, so
every day at the track shares it. Written only when it holds something. Each
text is at most 4096 code units; at most 256 things to try, with unique ids, and
at most 128 corner entries (`maximumProfileCorners`), each naming one of the
track's corners. Blank notes and blank things to try are dropped unless they
carry keys a newer version wrote; a corner entry whose note is cleared is kept
with an empty `note` for the same reason. A change past these limits is refused
and the notebook page says it was not saved. The page limits each field to 4096
characters as the user sees them; text with emoji can be longer in code units,
and the part past 4096 code units is cut when it is kept.

Merging two profiles (`mergeDriverProfile`) joins the notebooks of every track
both have, whether or not a day is added, and changes nothing of this profile's:
the other's notes follow these when they are not already held; a note on a
corner both have follows this one's the same way; a note on a corner of the
other's that is not one of this track's joins the general notes as
`<corner name>: <note>`; the other's things to try not already present by id or
text follow these. A corner entry of the other's that names no corner of
this track and holds no note (only keys a newer version wrote) is not kept. Text or things to try that would go past the limits are left
out whole, and the merge reports it (`ProfileMerge.notebookCut`); the tracks
whose notebook took something are `ProfileMerge.notebooks`. A bundle import that
finds the profile changed while the bundle was read merges the bundle's own
profile (`ProfileBundleImport.source`) into the changed one again, so edits made
meanwhile stay.

## A day's reference lap (`reference`, FET-276)

The reference lap of a day (FET-175: a friend's or an instructor's recording,
or a lap of another day) is kept in the profile, not in the day file: the owner
chose that on 2026-10-07. It is a new optional key `reference` on the day's
entry in `days[]` (an open object, like the notebook on a track). It is written
only when the day has a reference; no closed object got a key and the
`.fetproject` day format is unchanged.

```json
"reference": {
  "kind": "file",
  "name": "friend.vbo",
  "recordingId": "friend.vbo",
  "lapNumber": 3,
  "sha256": "<64 lower-case hex>",
  "extension": ".vbo",
  "bytes": 8123456
}
```

or, for a lap of another day of the profile:

```json
"reference": {
  "kind": "day", "name": "Day 2026-08-29",
  "recordingId": "<run id of that day's session>", "lapNumber": 2,
  "eventId": "<the other day's event id>"
}
```

| Key | Meaning |
|---|---|
| `kind` | `file` or `day`. |
| `recordingId` | The session's run id (`day`) or the file's name (`file`); with `lapNumber` it names the lap on today's line, never the recording's position in its source. 1 to 4096 code units. |
| `lapNumber` | 1 to 100 000. If that lap is no longer there (today's line changed), the source's fastest lap is shown and the stored choice is left as it was: it is only rewritten when the driver chooses a lap on purpose (or picks another source), and a later reload of the same source asks for the stored lap again. |
| `name` | Optional. The file's name (cut at 255 code units) or the other day's name when it was chosen: only used to say what is not found. Never used as a path. |
| `sha256`, `extension`, `bytes` (`file`) | The copy in `Recordings/<sha256><extension>` of the profile folder: 64 lower-case hex digits, `.vbo` or `.rcz`, 1 byte to 128 MiB. The path is built only from these two checked values, so a profile cannot point outside `Recordings`; the user's own path is never stored. |
| `eventId` (`day`) | The other day. It works while that day is in the profile; when it is not (deleted), the reference stays and says so, and works again if the day comes back (same event id, such as from a bundle). A day is never its own reference. |

Unknown keys of the object are kept. A `reference` this version cannot read (an
unknown `kind`, a bad hash or extension, a number out of range, not an object)
never refuses the profile: it is kept as written in the day's unknown keys,
shows as no reference, and is replaced when a reference is set or cleared.
Absent means no reference, also after the driver cleared one: clearing removes the key
and the copy.

Limits: a recording is kept as one copy, however many days use it, at most
**32 distinct copies**, **128 MiB each** (the size the importers read at most,
so a larger file could never be read again) and **512 MiB together**. One
reference per day, so at most one per day entry (10 000 days). At a limit a
change is refused (`ProfileReferenceError`: too many files, too much, too
large, empty, not a VBO or RCZ file, unreadable, not written) and nothing is
changed: the copy made for it is removed unless something else uses it, and the
day page says the reference is not remembered and why, with a retry; the
reference still works while the day is open. A profile read with more than the
limits (a newer or hand-made one) is not refused: only new copies are.
`bytes` of a restored reference is checked against the copy's size when read
(the day says the recording changed if it differs); the copy is not hashed again.

Where it lives and what happens:

- **Saving.** The page asks the store (`ProfileReferenceStore`, `ProfileLibrary.setFileReference`
  / `setDayReference` / `clearReference`). The file is hashed and copied in
  64 KiB pieces off the UI thread to a `.reference-*.partial` file beside, then
  moved to `Recordings/<sha256><extension>`; an existing copy is reused after
  its content matches the name (a damaged one is replaced). The profile is written
  and the change is only reported kept once that very write succeeded (each write
  has its own outcome: another write failing meanwhile neither fails nor undoes
  this one); if it fails, or the change is refused, the reference is taken back
  from the profile as it is by then (a day recorded meanwhile stays), written
  again with the rest, and the user is told. A copy nothing uses any
  more (replaced or cleared reference) is deleted unless another day's reference or
  any day's recording names the same file (`deleteUnusedReferenceFile`). A day
  not yet listed in the profile (a new day, listed once it is measured) holds
  the choice and gets it when it is added; such choices count against the limits
  too (their copies are on disk already), and one the profile has no room for
  by then (an import added copies meanwhile) is dropped and the day page says
  so (`ProfileLibrary.referenceDropped`), with a retry. Changes, restores and
  deletions of references go through one queue in the order asked, so a day
  closed and opened again before a copy finished, or cleared and opened at
  once, reads what was asked last.
- **Restoring.** Once per opening of the day, as soon as today's line is known.
  A missing copy, a copy of another size, a day no longer in the profile or a
  recording that cannot be read shows as not found with its reason; it never
  blocks the day and never forgets the stored choice. Only an explicit clear does.
- **A day added again** (`addDayToProfile`, weather, setups, car) keeps its reference.
- **Deleting a day** (FET-241, `deleteDayFiles`) forgets its reference with the
  day's entry and deletes its copy unless another day's reference (`otherReferenceFiles`,
  also a reference still waiting for its day) or recording uses it. A day whose
  document is outside the profile's `Days` folder is not deleted, but its
  reference and copy are forgotten as above. Other days' references to the deleted day stay and say
  the day is gone.
- **Merging** (`mergeDriverProfile`): an added day brings its reference. A copy this
  profile keeps already (same hash) is shared; a new one counts against the limits and, past
  them, the day comes without its reference (`ProfileMerge.referencesNotKept`).
  A day already here keeps its own.
- **Bundle** (below): the copy is in the bundle once; reading it checks hash and size.

**Orphans.** A crash between the copy and the profile write, or a reference
dropped after an import, can leave a copy nothing uses in `Recordings/`. Once
at start-up, after the profile is read, behind any import and change of a
reference and never while a choice waits for its day, the app deletes the files
there that are named like a reference copy (64 hex digits and `.vbo` or `.rcz`)
and are neither a reference (also one this version cannot read: every 64-hex
`sha256` inside it counts as used, with either extension) nor a recording of any
day in `Days/`, and the
half-written `.reference-*.partial` files (`sweepReferenceFiles`). Nothing else
in that folder is touched, and the sweep stops altogether when a day cannot be
read or a day's `reference` has a shape that cannot be searched (not an
object), so a newer version's copies are never lost to this one.

A per-track "last reference used" (a fallback when a day has none) is not
kept: it would need an explicit "cleared" marker so a cleared reference stays
cleared, and nothing asked for it yet.

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
it is; one holding nothing this version reads (only its `version`, say) is
kept as written too.

Unlike `weather`, it has no `sourceRevision`: the setup is the driver's own
statement about the run, not something measured from the recording, so a
replaced recording keeps it. It reaches the profile only when the day is
saved: each save that records the day (`ProfileLibrary.recordDay`) passes
every run's setup as saved (`DayResultsController.savedRunSetup`), never an
unsaved edit. Given that way, a session's setup replaces what the profile
had, and a run without one clears it. A day restored from its recovery
snapshot and not saved since gives none (`setupsSaved` is false: the
snapshot holds unsaved changes). A day added without setups, such as a day
found in the days folder or a restored day, keeps the profile's. The setups
go to a day the profile already lists at once (`setProfileSessionSetups`),
before the day is measured, and the library holds the last ones given for
each day (`ProfileLibrary.givenSetups`), applying them to a later record
without setups, so a measure that fails does not lose them. New weather
(`setProfileSessionWeather`) and moving the profile to another device
(`mergeDriverProfile`, the bundle) carry it along.

"Last time here" shows each visit's setup as entered, chosen as its weather
is: the session that set the day's best lap, else its first session with a
setup, labelled as such. When both visits entered pressures in the same unit,
it adds today minus then for each wheel entered on both (no colour: higher
is not better); in different units it shows both and says they are not
compared. A setup this version cannot show says so: stored by a newer
version, or holding only values it cannot read. The previous visit without
any setup says none was entered that day or the day was added before the
library kept setups. Today without a setup in the profile says, for the
session that set the best lap (else the first), that it was entered on the
page and not saved yet (`DayResultsController.runSetupWaitsForSave`, also
for a restored day not saved since), that it was saved and is not in the
library yet (`givenSetups`), or that none was entered.

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
- `profileTrends` (FET-235): per track and car (values depend on both, so
  days compare only within one), every visit oldest first with its
  `TrackVisit` lap times, whether its best lap beat every earlier day's there
  (`personalBest`; the first day never is, nor an undated one), four measures as their skills
  measure them (`trendMeasures`: braking-point spread, minimum speed below
  the best ever at the corner in that car over every day kept, off the
  throttle to braking, lap time spread; sessions weighed by ranked laps, a
  measure not measured is absent) and the weather kept for its sessions (the
  model's conditions, each once, the most rain of one session, and how many
  of the day's sessions have weather). Each measure is the median over the
  corners a session measured, so days may differ in the corners behind it.
  Undated days are listed last and are never a new best nor part of a trend.
  From `trendMinimumDays` (3) dated days that measured it, `changes` gives
  each figure (`trendFigures`: best lap, typical lap and the measures) on its
  first and last such day, with both days; `measuredDays` counts the dated
  days behind each figure, so the page can say why one has no change. A tie
  with the best so far is not a new best. Wet or dry is not
  inferred: the stored weather is the weather model's for the area, not the
  track surface, and nothing new is stored. Stored stats have no coasting
  share of the lap; `liftSeconds` (lift and coast before braking) stands in.
- `skillLevels`: the 12 skills of `skillCatalogue`, each level 1–5 = 5 − bands
  exceeded, over the last 3 days that measured it; confidence from its ranked
  laps (low below 5, medium below 15, high from 15); trend against the 3 days before.
  A level is capped by its ranked laps (FET-191): 5 needs high confidence, 4
  medium, otherwise at most 3. The bands are absolute (FET-191): level 5 is what
  a fast, experienced driver repeats lap after lap, so 5 means at the limit, not
  consistent with oneself.
  Each is the median over a session's corners (sessions weighed by ranked
  laps), lower is better:

  | Skill | Measure | Bands |
  |---|---|---|
  | liftTiming | `liftSeconds` | 0.1, 0.25, 0.5, 0.8 s |
  | brakePointConsistency | `brakingSpreadMeters` | 2, 4, 7, 12 m |
  | brakeReleaseTiming | `releaseSpreadMeters` | 3, 6, 10, 16 m |
  | brakingEffectiveness | best ever `bestDecelerationG` at the corner in the car − `decelerationG` | 0.02, 0.04, 0.07, 0.12 g |
  | turnInConsistency | `entrySpeedSpread` | 1, 2, 4, 7 km/h |
  | minimumSpeedControl | best ever − `minimumSpeed` | 1, 2, 4, 7 km/h |
  | lineConsistency | `lineSpreadMeters` | 0.4, 0.7, 1.1, 1.8 m |
  | throttleReapplication | `pickupSpreadMeters` | 2, 4, 7, 12 m |
  | throttleCommitment | all corners' `releasedPickups` / `throttleKnownLaps` (3 or more passes, 3 or more ranked laps), % of passes | 2, 10, 20, 35 % |
  | exitSpeedExecution | best ever − `exitSpeed` | 1, 2, 4, 7 km/h |
  | cornerSequenceManagement | mean `sequenceLossSeconds` (a median is 0 on most corners) | 0.01, 0.03, 0.06, 0.1 s |
  | paceConsistency | `lapSpreadSeconds` | 0.5, 1, 2, 4 s |

  Minimum speed, exit speed and braking effectiveness compare against the
  best ever at the corner in that car over the days read (FET-191), so a slow
  day is not its own reference. That best is one lap's figure, so a GPS or G
  spike lowers the corner's level on every later day too; a sturdier
  reference (a high quantile of the day bests) is the fix if it shows up.
  cornerSequenceManagement is a mean over corners on purpose, not the median:
  most corners give nothing back, so the median is 0. Trends compare the band
  level without the laps cap, so more laps alone is no change.

  A skill none of the window's sessions measured (no pedals, no G, no stated
  GPS accuracy, or days added before FET-165) says "needs more evidence". The
  bands are tuned in `skillCatalogue`; stored data never changes. The real
  Jastrząb day (2026-08-29) scored 2 to 5 with the first draft's bands and 1
  to 4 with these.

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
  day still comes along and reports it missing when opened. The copy of a
  day's reference lap (FET-276) is one of these, as `<sha256><extension>`; a
  recording that is both a day's recording and a reference is one file. A copy
  not found is counted (`referencesMissing`) and its reference says so there.

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
unpacked into a `.bundle-import-*` folder beside the index. A reference copy
(of an added day) must be the size its reference says (and at most 128 MiB) and
hash to the name that is its `sha256`: one that is not, or is damaged in the
archive, costs the days using it their reference
(`ProfileBundleImport.referencesNotKept`), never the bundle; the rest is still
read all or nothing. On export a copy whose size is not the one the profile says
counts as missing (`ProfileBundleExport.referencesMissing`) and is not written.
One already in `Recordings/` is reused when its content
is that hash, and a different file of that name is never replaced: the days
using it are added without their reference (`ProfileBundleImport.referencesNotKept`,
also those past the limits of reference recordings). Only then are the
recordings moved into `Recordings/` and the documents written; a failure there
removes what this import wrote, and a staging folder left by a crash is removed
by the next import. A recording already in `Recordings/` is reused only when
its SHA-256 is the one the day names; another file of that name makes the new
one `name (2)`. The caller writes the merged profile: the app merges it into
the profile as it is by then, so a day recorded during the import is kept, and
says so when the profile cannot be written (the days then come back through
the unlisted-days scan at the next start, under the last car).
