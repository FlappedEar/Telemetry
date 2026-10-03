# FlappedEar Telemetry

Track-day analysis for drivers. Import a day of RaceChrono recordings (VBO and
RCZ), see the best lap and where it loses time, and compare laps, on a phone,
tablet or desktop. There is no video; video overlays are a separate app,
FlappedEar Overlays.

The app is free for users.

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
excluded from the ranking with a reason. Below it, **Theoretical best** times every
ranked lap against the day's segments (proposed from the best lap when the
day has none yet, as FlappedEar Overlays does): the best lap, the theoretical
best (the fastest time of each segment) and the time available; a loss map,
the best lap's trace with each segment coloured by the time the chosen lap
loses there to the fastest time, with the segments listed largest loss first;
and a sector table of every lap by segment, the fastest time of each segment
highlighted. Tap a lap in the table to show its losses on the map. Each corner in the loss list also shows the lap's minimum speed and braking point against the best lap; tap it for entry, minimum and exit speed, braking point, braking time, peak deceleration and throttle pickup against the best lap and the best of all laps, measured and inferred values labelled. **Edit segments** shows the best lap's map with the segment boundaries and the segments in lap order: tap one to rename it, change its type, move its start or end in metres, split it, merge it with the next one or remove it, with undo and redo, or **Restore automatic**; every change times the laps again. Corrections are saved with the day as its approved segments and are never replaced by automatic ones. The trace is drawn over
OpenStreetMap street tiles, or MapTiler satellite imagery when the build has a
key; the layers button switches between them and the trace alone, which needs
no network. Tiles already seen stay cached for the track. **Save** writes the day as a
`.fetproject` document FlappedEar Overlays can open (sessions, recordings,
circuit names, excluded laps and the group shown); **Open a saved day** reads
it back, and a session whose recording has moved or changed is listed with
**Find recordings in a folder**. On desktop the system dialogs choose the file;
on phones days are kept in the app. A day with unsaved changes is kept in
the app's own folder as you work, so after a crash or a closed app the import
screen offers to **Restore** or **Discard** it. The
recording model, parsers, lap timing and day import plan live in
[`packages/telemetry_core`](packages/telemetry_core/README.md). Milestones are tracked in
the Jira space [FET](https://kozucharkadiusz.atlassian.net/browse/FET).

## Phones and tablets

On a phone or tablet, **Choose recordings…** picks VBO and RCZ files (there is
no folder picker). Recordings can also be sent from another app: in
RaceChrono, export a session and choose **FlappedEar Telemetry** in the share
sheet. The app copies the shared files into its own storage and imports them
on **Import a day**.

Below 900 logical pixels of width (a phone, or a tablet in portrait) the day
page shows **Results** and **Laps** as two tabs; wider screens show them side
by side. A lap's trace fills the rest of a tall screen and scrolls on a short
one, such as a phone held sideways. `test/layout/screen_sizes_test.dart` opens
every screen at small phone, Pixel and tablet sizes in both orientations and
fails on any overflow.

To install on Android without a store, download the
`flappedear-telemetry-android-<commit>` artifact from a CI run, unzip it and
install `app-release.apk` (allow installs from the browser or file manager).
Use builds from `main`: they share one signing key kept in the Actions cache,
so a newer APK installs over the old one and keeps the app's days. If that
cache expires (seven days without a build), the key changes and Android
refuses the update; days would then have to be saved elsewhere first.

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 15 |
| Android | 8.0 (API level 26) |
| macOS | not decided |
| Windows | not decided |

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
offers streets and the trace only. Another provider is another `TileSource` in
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
- an iOS simulator debug build, then `integration_test/` on a booted iPhone
  simulator;
- an Android debug APK, then `integration_test/` on an Android emulator
  (API 34, x86_64, OpenGL ES on SwiftShader with guest Vulkan turned off),
  through `.github/scripts/android-integration-test.sh`. A run whose app never
  reports a result is stopped after 8 minutes and run once more, with a
  warning in the job summary.

Run the integration tests locally on any connected device or simulator:

```bash
flutter test integration_test -d <device id>
```

## Contributing

Read [AGENTS.md](AGENTS.md) first. It holds the engineering rules, the shared
`.fetproject` format rules and the invariants every change must keep.

## Licence

Not chosen yet.
