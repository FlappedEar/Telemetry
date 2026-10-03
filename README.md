# FlappedEar Telemetry

Track-day analysis for drivers. Import a day of RaceChrono recordings (VBO and
RCZ), see the best lap and where it loses time, and compare laps, on a phone,
tablet or desktop. There is no video; video overlays are a separate app,
FlappedEar Overlays.

The app is free for users.

The user guide for drivers is at <https://flappedear.github.io/Telemetry/>
(sources in [`docs/user-guide`](docs/user-guide/README.md)).

## Status

Early development. The app opens on **Import a day**: choose the day's VBO and
RCZ recordings or a folder (optionally with subfolders), or drop them on the
window on desktop. Recordings are prepared in a background isolate with progress
and Cancel; each primary run is named "Session N" in recording-time order and
shows its laps, and import notes list what was skipped, grouped or failed.
**Show the day's results** then leads with the best lap of the day ("Best day ·
1:49.898 · Session 5 · LAP 2") and its GPS trace coloured by speed, each
session's best lap, and every lap section in recording order with why a lap is
not ranked. A lap opens on its own map, over the best lap in grey, and can be
excluded from the ranking with a reason; under the map, its channels (speed,
lateral and longitudinal G, throttle or brake when recorded, or any other
channel, up to four) are charted on a time axis: drag across a chart to move a
cursor, shown on the map, and zoom around it. **Compare with…** (on a lap, or
**Compare two laps** above the lap list) puts two laps of one group side by
side on a shared track-position axis, as FlappedEar Overlays does: A green, B
orange, the Δ time (A − B, positive when A is behind) and the channels of both
laps, braking drawn upward, and both lines on one map over street or satellite
tiles, with the zoom window highlighted on lap B and a dot per lap at the
cursor, optionally coloured by
speed, the Δ time, G, the pedals or a recorded temperature (never invented
when a lap did not record it). Swap the laps, change either, or set B to the
best of A's session or of the day; a time loss or a focus area opens its two
laps there, zoomed to its segment. Under the charts, the **Corner Analyzer**
lists the approved segments both laps share ("Corner 1 · 108 m") and, for the
chosen one, a one-line summary of who is faster there (with the largest speed
difference in that lap's favour), a chart of both laps' speed through the
segment and a lead-in before it (speed axis with its unit, metres from the
corner entry, the corner shaded between its entry and exit, the apex dashed,
and each lap's braking start ▲, throttle pickup ◆ and lowest speed ● on its own
line, with a legend and the shared cursor's readout), and a table of A, B and
Δ grouped as Time, Braking (where braking starts before the entry, time on the
brakes, peak deceleration), Corner (entry, apex and minimum speed; entry, top
and lowest elsewhere), Exit (exit speed, throttle pickup after the entry) and
Driver (heart rate). Every value carries its unit, or the panel says once that
the recording declares none; Δ is coloured by the faster lap or the lap
carrying more speed and says so in words; each missing value gives its reason
in plain words and inferred values are labelled. Choosing a segment zooms the
charts to it; **Lap A here** and **Lap B here** open a lap
at its start. A time loss, a focus area, a row of the theoretical best's loss
list or a corner's details open it on that segment, measured against the
theoretical best's segments when the two laps' own differ (and saying so);
laps without shared segments can use them too. Below it, **Theoretical best** times every
ranked lap against the day's segments (proposed from the best lap when the
day has none yet, as FlappedEar Overlays does): the best lap, the theoretical
best (the fastest time of each segment) and the time available; a loss map,
the best lap's trace with each segment coloured by the time the chosen lap
loses there to the fastest time, with the segments listed largest loss first;
and a sector table of every lap by segment, the fastest time of each segment
highlighted. Tap a lap in the table to show its losses on the map. Each corner in the loss list also shows the lap's minimum speed and braking point against the best lap; tap it for entry, minimum and exit speed, braking point, braking time, peak deceleration and throttle pickup against the best lap and the best of all laps, measured and inferred values labelled. **Edit segments** shows the best lap's map with the segment boundaries and the segments in lap order: tap one to rename it, change its type, move its start or end in metres, split it, merge it with the next one or remove it, with undo and redo, or **Restore automatic**; every change times the laps again. Corrections are saved with the day as its approved segments and are never replaced by automatic ones. **Time losses** ranks the largest losses of each session's best lap (or of every lap) against the best lap, one segment at a time; tap one for both laps' times through that segment and the segment on the map. **Consistency** gives the typical lap and segment time (median) and the spread (interquartile range) over the day and per session, or says that at least three laps are needed. **Progression** lists the sessions in recording order with their best and typical lap and the best against the session before, and each segment's typical time per session; tap a cell for its laps. **Where to look next** picks at most three areas from the measured losses, sector gaps and corner spreads: each shows what was measured apart from a hypothesis to check, never a cause or an instruction; tap one to compare its two laps (A green, B orange) through the segment. **Car** summarizes each session's recorded temperatures (mean, range, coverage, implausible readings left out, continuously recorded cooling) and how each moved with lap time over the compared laps, saying when there are too few laps or the day's progression could explain it; **Driver** shows each session's recorded heart rate and each lap's mean. **Day report** (in the toolbar) presents the day's results as calculated, each leading to its lap, and says exactly why one is missing. Every map
draws the trace over a real map: OpenStreetMap street tiles, or MapTiler
satellite imagery when the build has a key; the layers button switches
between them, on every map at once. Tiles already seen stay cached for the
track. **Save** writes the day as a
`.fetproject` document FlappedEar Overlays can open (sessions, recordings,
circuit names, excluded laps and the group shown); **Open a saved day** reads
it back, and a session whose recording has moved or changed is listed with
**Find recordings in a folder**, which finds each recording by its content
(even renamed), never uses a different recording that only has its name, and
saves where the recordings are now. When none of a day's recordings can be
read, the open dialog offers the same search. On macOS the sandbox lets the
app read a chosen or dropped file only until it quits, so the app keeps a
security-scoped bookmark of every recording and folder chosen and restores
that access before opening a day; recordings chosen before this existed are
found once with **Find recordings in a folder…**. Days saved by either app open in the
other with their segments, lap exclusions, notes and the group shown. On desktop the system dialogs choose the file;
on phones days are kept in the app. A day with unsaved changes is kept in
the app's own folder as you work, and after a crash or a closed app the import
screen offers to **Restore** or **Discard** it. This recovery is best effort:
changes are written half a second after they settle, and at once when the app
leaves the foreground or is asked to quit, so a crash or a forced stop right
after a change can lose that last change. Saving is the only guarantee. The
recording model, parsers, lap timing and day import plan live in
[`packages/telemetry_core`](packages/telemetry_core/README.md). Milestones are tracked in
the Jira space [FET](https://kozucharkadiusz.atlassian.net/browse/FET).

Under a comparison's charts, for the stretch shown (the whole lap or the
zoomed part), **G-G** plots both laps' lateral against longitudinal G with
their observed peaks and sample counts, **Driving states** shows when each lap
brakes, brakes while cornering, corners, accelerates and coasts, as strips
along the track and as shares of the lap's time, and **Coasting** gives each
lap's coasting time, distance and episodes (select one to move the cursor
there); a lap's page shows its own coasting, by segment once the day's
segments are calculated. Every value says whether it was measured from a
pedal or sensor, calculated by the logger from GPS, or inferred from
longitudinal G, which happens only when the recording has no such pedal
channel.

Speeds carry the unit their recording declares: RCZ declares its unit, and a
RaceChrono VBO names it in its header (`velocity kmh`), which the parser keeps
as header metadata. A declared unit is always shown as declared. **Settings**
(the gear in the toolbar) chooses the **unit for unlabelled speeds** (**None**,
**km/h** or **mph**), used only for recordings that declare none. Values are
never converted, so every calculation and the parity with FlappedEar Overlays
are unchanged. A day whose recordings end up with different units, or with no
unit, shows speeds without one rather than a wrong label.

## Phones and tablets

On a phone or tablet, **Choose recordings…** picks VBO and RCZ files (there is
no folder picker). Recordings can also be sent from another app: in
RaceChrono, export a session and choose **FlappedEar Telemetry** in the share
sheet. The app copies the shared files into its own storage and imports them
on **Import a day**, and the day opens by itself. While a day is open, a
shared recording is added to that day instead, as its next session. When the
system has closed the app between sessions, a shared recording continues
today's day: the unsaved day the app kept, or else the day saved last in the
app, when it was worked on in the last 24 hours and the recording started on
its date. Otherwise it starts a new day.

At the track, a day grows one session at a time: **Add recordings** (the
playlist button on the day page) or a recording shared while the day is open
adds it as the next "Session N". Only the new recording is read; the day is
grouped and ranked again with your circuit names, excluded laps and chosen
group, a recording already in the day is not added twice, and a day that has
been saved is saved again where it was. On the six real recordings of one day
this gives exactly the day imported all at once.

Below 900 logical pixels of width (a phone, or a tablet in portrait) the day
page shows **Results** and **Laps** as two tabs; wider screens show them side
by side. A lap's trace keeps a readable height, with its charts below, and
scrolls on a short screen, such as a phone held sideways; a comparison shows
its map and its charts side by side on a wide screen and one under the other
on a phone. `test/layout/screen_sizes_test.dart` opens
every screen at small phone, Pixel and tablet sizes in both orientations, at
the normal text size and at 1.3 times it, and fails on any overflow.

The screens are made for fingers: nothing depends on hovering, and every
button, row and strip is at least 48 dp square with a label for screen
readers. One finger always scrolls the page; maps zoom and move with two
fingers (a double tap also zooms the tiled map), so a map never traps the
scroll. On a chart, a tap or a sideways drag moves the cursor and an upward or
downward drag scrolls the page. Wide tables, such as sector times and the
times by segment, keep the lap or segment column in place and scroll the rest
sideways. Lap A and B text uses a darker shade of their colours on a light
background so it stays readable; the lines keep the colours. The lap chosen
on a card, a table's mode and the Corner Analyzer's segment and zoom are kept
while the card is scrolled out of view, and back closes a sheet or dialog
before the page. `test/layout/touch_test.dart` checks tap targets and labels
on every screen at both text sizes (the Diagnostics menu entry too), the
two-finger and double-tap gestures on the plain and tiled maps of a lap and a
comparison, chart drags and back.

To install on Android without a store, download the
`flappedear-telemetry-android-<commit>` artifact from a CI run, unzip it and
install `app-release.apk` (allow installs from the browser or file manager).
Use builds from `main`: they share one signing key kept in the Actions cache,
so a newer APK installs over the old one and keeps the app's days. If that
cache expires (seven days without a build), the key changes and Android
refuses the update; days would then have to be saved elsewhere first. The
job prints the key's SHA-256 ("Check the APK's signing key") and warns when it
had to make a new one. APKs built before 2026-10-03 were each signed with a
different key and do not update; uninstall such a build once before
installing a newer one.

### Measuring a day on the phone

**Diagnostics**, in the **More** menu of **Import a day** and of the day page,
shows how long the last import took step by step (finding the recordings,
parse and import, day analysis, start to results, then the theoretical best
and the channel summaries once they have been calculated), how many
recordings, sessions and samples it read, and the app's current and peak
resident memory as the system reports it ("Not available" where it does not).
Nothing is stored or sent. The same steps can be measured on a computer, on
any folder or a synthetic day, with `packages/telemetry_core/tool/day_benchmark.dart`
(see [its notes](packages/telemetry_core/tool/README.md#day_benchmarkdart)).

## Look

`lib/ui/theme.dart` holds the whole look: a dark track-day dashboard of flat
charcoal panels, after the design language of Track Titan, with FlappedEar
amber (the logo's colour) as the accent. `FetColors` names the lap colours:
your lap amber, the reference lap blue, time lost red and time gained green;
charts and maps move to them screen by screen. Text is
Sora with tabular digits, so times line up; lap times in large type use
JetBrains Mono. Both fonts are bundled under `assets/fonts/` with their
licences (SIL Open Font License 1.1), so the app needs no network for them;
the licence texts ship in the app and show on its licence page. Screens use
the theme's colour roles and text styles rather than their own colours.

The app icon is the FlappedEar ears from the Overlays logo over two laps'
speed traces, amber and blue, on charcoal; the launch screen shows the ears
with the FlappedEar Telemetry wordmark. Their sources are in
`assets/branding/` (`icon.svg` is the vector original). After changing them,
regenerate the platform files with `dart run flutter_launcher_icons` and
`dart run flutter_native_splash:create`, then revert the generators'
unrelated edits to `ios/Runner/Info.plist` and `ios/Runner.xcodeproj`.

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 15 |
| Android | 8.0 (API level 26) |
| macOS | 12.0 |
| Windows | 10 (64-bit) |

macOS is the active development platform.

Application identifier: `com.flappedear.telemetry`.

## Maps

Street tiles come from OpenStreetMap under its
[tile usage policy](https://operations.osmfoundation.org/policies/tiles/): the
app identifies itself as `com.flappedear.telemetry`, shows the attribution and
caches tiles. Satellite tiles come from MapTiler and need a key at build time,
which is never committed:

```bash
flutter run --dart-define=MAPTILER_KEY=your-key
```

CI reads it from the repository secret `MAPTILER_KEY`. Without a key the app
offers streets only. There is no trace-only choice: the plain drawing without
tiles is used only by the tests, which have no network. Another provider is another `TileSource` in
`lib/day/track_map.dart`.

## Development

Flutter is pinned to **3.47.6** (stable, Dart 3.13.5) in `pubspec.yaml`
(`environment: flutter`). CI installs exactly that version.

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```

The shared `.fetproject` format lives in the pure Dart package
[`packages/fetproject`](packages/fetproject/README.md); run `dart pub get`,
`dart analyze` and `dart test` there. Run its `dart pub get` before the root
`flutter analyze`, which covers the package too.

CI (GitHub Actions, `.github/workflows/ci.yml`) runs on every pull request and
on `main`:

- analyze, tests and a macOS debug build;
- analyze, tests and a Windows release build on Windows;
- an iOS simulator debug build, then `integration_test/` on a booted iPhone
  simulator;
- an Android debug APK, then `integration_test/` on an Android emulator
  (API 34, x86_64, OpenGL ES on SwiftShader with guest Vulkan turned off),
  through `.github/scripts/android-integration-test.sh`. A run whose app never
  reports a result is stopped after 15 minutes and run once more, with a
  warning in the job summary.

The integration tests run the app on the device with its real storage,
background isolates and saved-days folder: the app starts; a synthetic VBO is
imported, its results shown, the day saved, the app's widgets started again
from scratch and the saved day reopened with the same best lap; and on
Android a real `ACTION_SEND` share, sent by the script through a debug-only
content provider, is imported and opens as the day. They do not drive the system file picker or
restart the app's process, and on iOS no share is sent.

Run the integration tests locally on any connected device or simulator:

```bash
flutter test integration_test -d <device id>
```

## Contributing

Read [AGENTS.md](AGENTS.md) first. It holds the engineering rules, the shared
`.fetproject` format rules and the invariants every change must keep.

## Licence

[Apache License 2.0](LICENSE). Map tiles keep their own terms: OpenStreetMap
data is © OpenStreetMap contributors under the
[ODbL](https://www.openstreetmap.org/copyright), and MapTiler imagery is
© [MapTiler](https://www.maptiler.com/copyright/).
In the app, **Settings** → **Open-source licences** shows the app's licence,
the map credits and the licences of every package it uses.
