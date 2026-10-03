# AGENTS.md

Rules for anyone, human or agent, who changes this repository.

FlappedEar Telemetry is the track-day analysis app for macOS, Windows, iOS and
Android, written in Flutter. The brand is written **FlappedEar**, without a space.

## Where things come from

- **Blank page.** This repository shares no code with
  [`arekkozuch/VBOOverlay`](https://github.com/arekkozuch/VBOOverlay) (FlappedEar
  Overlays). That repository is cross-reference material for behaviour, data and
  decisions only. Do not copy its code and do not add a code dependency between
  the two repositories.
- **Handover.** The architect handover is
  [`docs/telemetry-handover.md`](https://github.com/arekkozuch/VBOOverlay/blob/main/docs/telemetry-handover.md)
  in VBOOverlay (reference revision `0ec7416`). When a rule here and the handover
  disagree, ask the owner.
- **Tracking.** Work is tracked in the Jira space
  [FET](https://kozucharkadiusz.atlassian.net/browse/FET).

## Process

- One active Jira task at a time, a focused commit, and recorded build and test
  evidence before the task is marked done. Jira content is in English.
- Every change goes through a pull request. CI must be green on the PR head and on
  the resulting `main` revision; earlier CI results are not evidence for new code.
- Documentation is part of every iteration.
- Never claim that something works without running it. If a check could not be
  run, say so and say why.
- Report results from real recordings separately from synthetic tests.
- No secrets, API keys, user paths, generated media or build output in Git.
- Check the current version, maintenance and licence of every new dependency
  before adding it, and record the check in the PR. Add no unrelated dependencies.
- Do not implement roadmap features that were not requested.
- No licence file until the owner chooses one.

## The user guide

The user guide in [`docs/user-guide`](docs/user-guide/README.md) is published to
GitHub Pages from `main`. It is written for drivers, not developers, and it must
match what the app on `main` shows.

- A change to anything a user sees or does (a screen, a label, a button, a
  default, a message, a supported format, a workflow) updates the guide pages in
  the same pull request.
- When a screen in a screenshot changes visibly, refresh the screenshots with
  `GUIDE_RECORDINGS=../refdata flutter test tool/user_guide/capture_screens_test.dart --update-goldens` and
  look at them before committing. New screens get a capture step there.
- Screenshots show the owner's Jastrząb day of 29 August 2026 from
  `FlappedEar/refdata` (`GUIDE_RECORDINGS=../refdata`); the owner approved
  screenshots of that day, heart rate included, for the public guide on
  2026-10-03. The recordings themselves still never leave `refdata`.
- Describe only what the app does at that revision; do not announce features.
- The pull request template asks for this; answer it, including "no visible
  change".

## Product rules

- **No video.** Telemetry never has video, video sync or overlays. Those belong to
  FlappedEar Overlays.
- **No data loss.** This holds for every migration and for all project data.
- **Identity.** The bundle and application identifier is
  `com.flappedear.telemetry`. The old desktop editor used the same identifier and
  the storage name "FlappedEar Telemetry". The app must never read, write or delete
  the old editor's data locations (listed in VBOOverlay
  `docs/application-identity.md`). Verify each platform's default directories
  before the first release.
- **Names.** Users see "FlappedEar Telemetry" on every platform. The Windows
  version resource keeps `CompanyName` `com.flappedear` and `ProductName`
  `telemetry` on purpose: Flutter's default Windows storage directories are built
  from those two values, and "FlappedEar" / "FlappedEar Telemetry" would resolve
  to the old editor's `%LOCALAPPDATA%\FlappedEar\FlappedEar Telemetry`. Do not
  change them without choosing an explicit storage directory first.
- **Private recordings.** The real-day recordings live in the private repository
  `FlappedEar/refdata`. Never copy them into this repository or any public place:
  they contain GPS traces and heart rate. Synthetic fixtures may be copied.

## The shared `.fetproject` format

Both apps read and write one `.fetproject` format, and it stays compatible in both
directions (KAN-170). A document written by either app must open in the other and
survive a re-save without losing anything.

- Keep every field Overlays owns unchanged: `scene.widgets`, `analysis.channels`,
  and each run's `sync` and `sources.video`.
- Open objects keep unknown keys. Never add keys to closed objects.
- Keep `documentState.id`, and continue `savedRevision` from the loaded value.
- Schema changes are agreed with the owner first.

The handover section "The shared contract: `.fetproject`" is the detailed reference.

## Invariants

These are carried over from the handover, section "Invariants to carry over". They
apply whatever the app's architecture.

**Parsing and data**

- Bound untrusted input (recordings, JSON documents, metadata) before large
  allocations or recursion.
- Test every parser change, including malformed input.
- Parser output timestamps are strictly monotonic.
- Public boundaries never expose `NaN` or infinity. Values outside the range and
  missing values are "no data"; gaps are never bridged.
- Heart rate comes from the imported VBO/RCZ recording; there is no separate
  heart-rate source.
- Never invent brake telemetry, and never substitute another channel silently.
- Analysis never depends on video or frame rate; all timing is time based.

**Documents**

- Saves are atomic. New, open and quit respect unsaved changes. Opening validates
  and commits a document as one transaction.
- A document and its recordings are separate. A missing or moved recording never
  prevents a valid document from opening. Relative references are preferred, and a
  recording is never accepted only because its pathname matches.
- The saved document is the authoritative clean state. Recovery data is separate,
  represents unsaved changes, and is never silently marked clean. Discard removes
  it. Recovery is offered only when it is newer than the saved document.

**Background work**

- Results of background parsing and analysis are guarded by a generation number
  and the source identity; a stale result never changes committed state.
- Long operations are cooperatively cancellable. Generation checks and
  cancellation are both required.

**Display**

- Static geometry, such as the track map, is not rebuilt on cursor or time
  updates. Moving markers update separately.
- A chart distinguishes "no data in this range" from a failure. Series keep their
  segments, so telemetry gaps stay visibly disconnected.

## How results are presented

From the handover, section "How results are presented".

- Lead with the result: the best lap and where the time is, on the track map.
- Names, not files: "Session 3 · LAP 2". Runs are named "Session N" in
  recording-time order.
- Mobile is touch-first: no hover, no tooltips, large targets.
- Times from one minute read `m:ss.mmm` ("1:49.898"); below a minute "28.662 s";
  a non-finite value is "—". Every language, Polish included, uses a decimal
  point (owner's choice, 2026-10-03). Round before splitting minutes, so a time
  never reads "x:60".
- A missing result says why and is never shown as zero.
- Typical means the median, spread means the interquartile range, and at least
  three laps are needed. No percentage scores.
- Results are observations, not causes or driving instructions.
- Measured and inferred values are labelled.
- Δ is A − B; a positive value means A is behind. A is green `#55e6a5`, B is
  orange `#d95926`.
- Longitudinal G: braking points upward in charts; acceleration points upward in
  G-G and on the map.

## Languages

The app speaks English and Polish and follows the device language, falling back
to English (`lib/l10n.dart`).

- New and translated text comes from `lib/l10n/app_en.arb`, with a
  description, and has its Polish in `app_pl.arb`; screens move over one at a
  time until every visible text does. `flutter pub get` generates
  `lib/l10n/app_localizations*.dart`; commit them. `test/l10n_test.dart` checks
  that both files have the same keys and placeholders.
- Read text with `context.l10n`. Format numbers with `fixed`, times with
  `displayTime`/`displayDelta` and dates with `displayDateTime` from
  `format.dart`, so formatting changes stay in one place.
- Labels and reasons from `telemetry_core` are English; map them to ARB texts in
  the app instead of showing them (see `TrackDirectionText`).
- The owner reviews Polish driving and telemetry terms.
- The user guide stays in English.
