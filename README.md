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
shows its laps, and import notes list what was skipped, grouped or failed. The
recording model, parsers, lap timing and day import plan live in
[`packages/telemetry_core`](packages/telemetry_core/README.md). Milestones are tracked in
the Jira space [FET](https://kozucharkadiusz.atlassian.net/browse/FET).

## Platforms

| Platform | Minimum |
| --- | --- |
| iOS | 15 |
| Android | 8.0 (API level 26) |
| macOS | not decided |
| Windows | not decided |

macOS is the active development platform.

Application identifier: `com.flappedear.telemetry`.

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

CI (GitHub Actions, `.github/workflows/ci.yml`) runs analyze, tests and a macOS
debug build on every pull request and on `main`. iOS simulator and Android
emulator jobs come next.

## Contributing

Read [AGENTS.md](AGENTS.md) first. It holds the engineering rules, the shared
`.fetproject` format rules and the invariants every change must keep.

## Licence

Not chosen yet.
