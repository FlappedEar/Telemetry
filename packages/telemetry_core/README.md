# telemetry_core

The recording model, the VBO parser and lap timing for FlappedEar Telemetry.
Pure Dart: no Flutter, UI, video or platform code, so it runs in `dart test` and in
a background isolate.

## What it does

- `VboParser.parse`, `VboParser.parseBytes` and `parseVboFile` read a RaceChrono VBO
  export into a `TelemetrySession`: float32 channels on one strictly increasing clock
  in seconds, NaN for missing values, semantic aliases (`speed`, `latitude`,
  `throttle`...), timing gates, metadata and warnings.
- `deriveSourceLapSession` finds the passes through the recording's single `Start`
  gate and the laps between them, with reference eligibility, ranking and lap
  traces. `formatLapTime` formats a lap time without ever showing `x:60`.

- `RczParser.parseFile` reads a RaceChrono RCZ shared session (format version 1)
  into the same `TelemetrySession`: each channel keeps its own clock from the
  session origin, missing values are NaN, recording gaps get missing-value
  boundaries so they are never bridged, and the Start trap becomes a timing gate.
  The ZIP reader never extracts files, validates every header before reading
  data, caps inflation at the declared size and checks CRC-32. Resumed sessions,
  several sessions in one archive, ZIP64 and encryption are refused. Device-axis
  accelerometer channels are not presented as vehicle G.
- `scanTelemetryFolder` and `scanTelemetrySources` turn a chosen folder, or any mix
  of dropped or shared files and folders, into the list of VBO and RCZ recordings
  to import, with notes on what was skipped. Links are never followed, dot files
  and macOS `._` sidecars are skipped, and depth, entry and file counts are bounded.
- `contentSha256` gives a recording's identity by content (`recordingSourceId`:
  `sha256:<hex>`), never by file name, and refuses a file that changes while it is
  read.

- `prepareTelemetryImport` turns a list of recordings into the proposed runs of
  one day: each file is size-checked, hashed, parsed, counted against the sample
  budget, given its laps and hashed again, and is Ready, Duplicate or Error; one
  bad file never stops the batch, and cancellation returns nothing. Budgets: 64
  files, 128 MiB per file, 256 MiB per batch (every attempt counts), 16 million
  retained samples. A VBO and an RCZ of the same drive are offered as a pair from
  their GPS traces; `automaticVboPrimaries` groups a unique pair dated within 1 s
  (VBO primary, RCZ alternative, channels never fused).
  `nameRunsInRecordingOrder` names runs "Session N" by recording time, undated
  last, and `ImportGeneration` keeps a stale result from being committed.

- `dayLapRows` lists one run's OUT, LAP n and IN sections (UNKNOWN when the
  recording has no accepted gate pass), with the clock from the recording;
  `sortDayLaps` orders a day's rows by that clock, undated runs last in import
  order. A lap is identified by `DayLapReference`: its exact bounds in one
  recording's content (SHA-256), never its number.
- `rankDayLaps` ranks the timed laps of one compatibility group
  (`TrackConfiguration.compatibilityGroupId`, the `compatibility-v1` id from
  `packages/fetproject`): best of the day, each run's best with linearly
  interpolated quartiles, ties, and every lap left out with its `LapIssue`s
  (unresolved layout, direction or gates, incomplete or invalid GPS, user
  exclusion, off the recorded route, changed source). Ties order by duration,
  clock, run, start and end. `eligibleDayLaps` is the same eligibility rule for
  later consumers.

- `inferTrack` finds the route a recording's complete laps follow (closed
  within 25 m, 100–30,000 m, resampled to 256 points; clockwise when the signed
  area is negative) and the laps on it; a lap more than 12 m off the other
  laps' line is off the route. `groupInferredTracks` groups runs whose routes
  match (same direction, length within 5 %, cross-track at most 25 m and 10 m
  RMS), complete-link, under a `gps-route-v1:` layout. A manual layout always
  wins.
- `analyzeDay` derives a whole day from its runs: rows, configurations (with
  the `gates-v1` revision of each recording's gates), groups labelled
  "Group 1 · Detected route · Clockwise", the ranking of every group, the
  group shown first (the one with the most eligible laps unless one is
  preferred), and messages. One failing run never stops the others.
- `lapPath` gives a lap section's GPS fixes in metres, with speed, split at
  every gap, for the track map (trace only, no tiles).

- `dayDocument` writes a day as a version 3 `.fetproject` document: each
  run's recording (relative path when close, content SHA-256, `telemetry-v1`
  fingerprint from `telemetryFingerprint`), its manual layout and direction
  or the unknown configuration with its gate revision, the detected route's
  provenance, lap exclusions as full lap references and the comparison
  decisions as Overlays writes them (FET-53): the group as
  `analysisDecisions.comparisonGroupId` only when the user chose it
  (`groupChosen`; otherwise the saved group, or none, is kept, so a day
  never chosen stays "automatic" in Overlays), and the comparison set up
  (`ComparisonDecisions`: `comparisonSlots` as lap references,
  `comparisonRange` in meters and `comparisonChannels`, each written only
  when set and valid). A document opened earlier keeps
  everything this app does not manage, including runs whose recordings were
  missing. `openDay` reads it back: it finds each recording (relative path
  first, then absolute, or a relinked path), refuses a different recording
  as Overlays does (a content SHA-256 or a fingerprint that differs, never
  accepted by its name), applies exclusions whose recording and derivation key
  still match, and analyses the day with the saved group shown when it is
  still one of the day's (a saved group the day cannot show stays saved until
  the user chooses another); `OpenedDay.comparison` (`documentComparison`)
  is the saved comparison, a lap whose recording or derivation changed read
  as none and kept in the document as it was. `findMovedRecordings` looks for missing
  recordings in a folder by the identity the document stores: the content
  SHA-256, else the fingerprint's size and sampled SHA-256, and only for a
  recording with neither, its file name; a file named like one but holding
  another recording is reported and not used. A day opened with recordings
  found elsewhere lists them in `OpenedDay.relinked`; saving writes their new
  paths. `openDayDocument` does the same for a
  document already in memory. Each save keeps Overlays' `documentState.id`
  and raises `documentState.savedRevision` by one (`nextDocumentState`).
  Each save also writes a new `documentState.saveId` (KAN-183). Overlays
  treats a recovery snapshot as stale only after a save of its own, so when a
  save here reaches or passes the snapshot's revision, Overlays sees a
  `saveId` that is not its own and offers the snapshot instead of dropping it.
  `test/day/overlays_check_test.dart` opens a saved day with Overlays' C++
  code, and `test/day/overlays_roundtrip_test.dart` takes days through both
  apps in both directions (see [tool/README.md](tool/README.md));
  `test/day/overlays_fixture_test.dart` checks a committed day Overlays built
  and saved, in CI.
- `writeDayRecovery` and `readDayRecovery` keep an unsaved day for recovery
  (after Overlays' `ProjectRecoveryStore`): this app's own file, wrapping the
  version 3 document with where the day was last saved, the path its
  relative recording paths are relative to, and the time. `openRecoveredDay`
  opens it. Overlays' discard tombstones are not ported: one app instance
  owns the file.

- `buildProgressAxis` turns one reference-eligible lap trace into a ~2 m,
  gate-anchored distance axis for its track (progress 0 at the start gate);
  `computeTrackFeatures` gives smoothed heading and signed curvature along it.
  `projectLapTrace` places a lap's GPS fixes on the axis with a bounded,
  heading-checked local search, ending a segment at every gap or lost lock
  instead of guessing; `timeAtProgress`, `progressAtTime` and
  `computeDeltaSeries` read time and the delta between two laps by distance,
  only where both laps are covered. `TelemetrySession.sampledSegments` gives a
  channel's actual samples, split at gaps and reduced to bucket extremes.
- `proposeTrackSegments` splits a progress axis into alternating corner and
  straight proposals from its smoothed curvature (kinks fold into the straight,
  corners with no 20 m straight between them form one chain, short straights
  and GPS gaps mark boundaries uncertain). `computeSegmentReview` runs it for
  one timed lap as Overlays does (axis from the lap's own trace, 6 m smoothing,
  the lap's `coverageGaps`). `approvedSegmentation`, `progressRangesOverlap`,
  `withApprovedSegment` and `withoutApprovedSegment` handle the approved
  segments a run stores in `trackSegments`; the segment model itself
  (`makeTrackSegment`, `validTrackSegment(s)`) is in `packages/fetproject`.
- Segments are automatic, with no manual approval (Overlays KAN-136):
  `dayDocument` approves every proposal of the chosen group's best lap into
  that lap's run when no run of the document has segments for the group
  (`automaticTrackSegments`; `automaticSegments: false` turns it off). They are
  then kept on every later save. A run that still stores segments of another
  configuration gets none, as in Overlays.
- Editing approved segments (Overlays `TrackSegmentEditing`, KAN-49):
  `withEditedSegment` (rename, retype, move, optionally with the neighbour
  sharing the boundary), `withSplitSegment`, `withMergedSegments` and
  `withoutApprovedSegment` return a whole new `trackSegments` or a reason;
  ids are stable. `SegmentEditHistory` is the bounded undo and redo,
  `pickProgressAt` maps a map point to progress and refuses crossings. The
  rest of `TrackSegmentReview` is ported too: review states
  (`reviewSegmentProposals`), `proposalEditError`, stored rejections
  (`makeTrackSegmentReview`, `rejectedProposalIndexes`) and result stamps as
  JSON. `DaySegmentEdits` keeps a day's unsaved edits by run (on the run whose
  segments the theoretical best uses), applies them to the document's runs
  and restores the automatic segments by removing the group's approved ones;
  `dayDocument(trackSegments: ...)` saves them. The last segment cannot be
  removed (restore instead), so a saved edit is never followed by automatic
  approval.
- `computeLapSectorTimes` times every approved segment of one lap from its
  projection on the shared axis (gate boundaries use the lap's own start and
  end, a segment across the gate is timed within the lap, a gap inside a
  segment leaves it untimed), and says whether the segments tile the lap.
  `computeTheoreticalBest` takes each segment's fastest time and the lap that
  set it; `computeTimeLossObservations` and `rankTimeLosses` give each lap's
  loss windows against a reference (a straight after a corner is the corner's
  continuation); `summarizeConsistency` and `computeSectorConsistency` give
  the median and interquartile range. `calculateOutingTheoreticalBest` times
  a population on one axis from the canonical run's fastest lap
  (`canonicalSegmentation`: the first run by id with segments for the group),
  and `publishTheoreticalBest` gives what Overlays' theoretical-best dialog
  shows (best lap, theoretical best, time available, segments by loss, the
  map), with each corner's repeatability (`summarizeCornerVariability`).
- The Corner Analyzer (Overlays `d4d1039`): `proposeCornerGeometryPhases`
  (entry, apex and exit from curvature), `computeCornerSpeeds` (entry, apex,
  minimum and exit speed), `detectBrakingOnsets` and `computeBrakingMetrics`
  (braking point from the brake channel, or inferred from longitudinal G only
  without one; braking time, distance and deceleration),
  `computeExitMetrics` (throttle pickup from the throttle channel, or inferred
  from acceleration, and exit speed downstream) and their `compare*`
  functions, which never compare values measured differently.
  `calculateOutingTheoreticalBest` measures them for every lap and corner
  (`cornerMetrics`).
- The Corner Analyzer of two compared laps (Overlays
  `AnalysisControllerCornerAnalyzer.cpp`, `d4d1039`): `CornerAnalyzer` on a
  comparison's shared axis lists the segments both laps share
  (`comparisonSharedSegmentation`: the same approved revision, or the
  theoretical best's segments, `borrowed`, when opened from it) and gives per
  segment A, B and Δ (A − B) of the sector time, segment speeds, corner
  speeds, braking point, braking time and peak deceleration, throttle pickup
  and exit speed, each with its provenance or the reason it is missing, plus
  the corner's geometric phases and the per-lap figures behind them;
  `heartRate` summarizes both laps over a range (also across start/finish)
  and `timeLosses` gives the observations through every segment.
  `dayComparisonSegmentation` and `dayTheoreticalBestSectorPair` choose the
  segments and the pair for a day. Trail braking, G-G and driving states are
  not part of it yet.
- `dayTheoreticalBest` does it for one group of a day: its eligible laps in
  recording order with their sector times and their loss to the fastest time
  of every segment (`DayLapSectors.lossSeconds`), the theoretical best and
  the time available, the largest time losses, and the segment at any time of
  a lap (`segmentAtTime`). It uses the document's segments, or proposes them
  from the best lap as saving the day would; `segmentRunId`, `runSegments`
  and `proposalReview` (the best lap's proposals against the approved
  segments, `segmentsAutomatic`) are what the segment editor works on.
  `corners` holds each corner
  segment with every lap's figures; `DayCorner.compare` sets one lap against
  the best lap and the best value of the group's laps.
- Progression and consistency (Overlays `summarizeOutingProgression`,
  `outingLapConsistency`, `publishTimeLossRanking` and
  `publishSectorProgression`, `d4d1039`): `summarizeDayProgression` lists a
  group's runs by recording clock (undated runs after them, in the day's
  order) with each run's best lap, quartiles, left-out laps and its best
  against the run listed before it, never across a run without an eligible
  lap; `summarizeLapConsistency` gives the median and interquartile range of
  the eligible lap times over the day and per run (none below three laps).
  `publishTimeLossRanking` gives the largest losses (each run's best lap, or
  every lap) with corner names, `compareTimeLoss` the two laps' times through
  a loss's segment, and `publishSectorProgression` each segment's median and
  spread per run with the laps behind it. `dayProgression`,
  `dayLapConsistency`, `DayTheoreticalBest.publishedTimeLosses`,
  `compareLoss` and `sectionProgression` do it for a group of a day;
  `progressionRunInfo` reads the notes, conditions and setup changes a
  document records for a run.
- Channel summaries, temperature associations, focus areas and the day
  report (Overlays `ChannelSummary`, `TemperatureAssociation`,
  `OutingChannelSummaries`, `FocusAreas`, `DayReport`, `OutingDayReport` and
  the day-report and association steps of its app, `d4d1039`):
  `summarizeChannel` gives a channel's time-weighted mean, extrema and
  coverage over an interval, never bridging a recording gap and leaving out
  implausible readings and placeholder zeros (counted);
  `findCoolingIntervals` finds continuously recorded cooling;
  `spearmanCorrelation` and `associateTemperature` describe how a
  temperature moved with a lap metric and with the order of laps, and
  `lapStrongAcceleration` gives a lap's strong acceleration.
  `selectFocusAreas` picks at most three areas to inspect next, each an
  observation with its numbers apart from a hypothesis that claims no cause.
  `buildDayReport` and `validateDayReport` write and check the
  `flappedear.day-report` document. For a day, `summarizeDayChannels`
  summarizes every run and section, `dayTemperatureAssociations` the
  group's eligible laps, `dayFocusAreas` the theoretical best, and
  `dayReport` assembles the report from what was computed, with
  `dayDecisionsKey` marking results computed under other decisions stale.
- Lap detail and A/B comparison (Overlays `MapLayers`, `TrackGeometry` and
  the comparison, map-layer and lap-chart functions of its app, `d4d1039`):
  `timeSeries` gives a channel's samples over a lap on a time axis for a chart
  (`ChartSeries`: runs never joined across a gap, the range, the unit, whether
  braking is drawn upward, and why there is nothing when something is wrong),
  and `lapChartChannels` the channels a lap's charts show first.
  `LapComparison` compares two laps of one group on a track-position axis
  built from lap A's own trace: the channels both recorded, `deltaSeries`
  (Δ time, A − B, positive when A is behind) and `channelSeries` by position,
  each lap's time and map position at a position, both traces on one map
  normalization (`sharedMapGeometry`, `mapTrace`, `mapPointAt`; its inverse
  `mapPointCoordinate` places a normalized position back in east-positive
  degrees, so the app draws it over map tiles), and
  `mapLayer`, one lap's line coloured by speed, the Δ time, lateral or
  longitudinal G, throttle, the measured brake or a recorded temperature
  (`channelAlongProgress` and `placeOnMap`, never bridging a gap, an
  implausible reading or a placeholder zero, and never inventing a channel).
  `dayComparisonCandidates`, `dayLapsComparable`, `dayBestComparisonLap` and
  `dayComparisonLap` choose the laps on a day. Video is not ported.
- G-G, driving states and coasting (Overlays `GgPairs`, `DrivingStates`,
  `CoastingAnalysis` and the `comparisonGgScatter`, `comparisonTrailBraking`
  and `outingLapCoasting` functions of its app, `d4d1039`): `buildGgPairs`
  pairs longitudinal and lateral G on the longitudinal clock (lateral
  interpolated only within its gap threshold, m/s² converted, other units
  refused, beyond ±4 g excluded and counted), `computeGgPeaks` gives the
  observed lateral, braking, acceleration and combined peaks from every pair
  and `decimateGgPoints` thins the points to draw, keeping the peaks.
  `classifyDrivingStates` finds braking, accelerating, cornering and coasting
  intervals with their provenance: measured from the pedals, calculated from
  a "-calc" channel, or inferred from longitudinal G only when the recording
  has no such pedal channel; a gap is unknown, never bridged.
  `summarizeCoasting` gives a lap's coasting by episode, by approved segment
  and in total. `comparisonGgScatter`, `comparisonTrailBraking` and
  `comparisonDrivingStates` compute them for both laps of a `LapComparison`
  over a range of its axis.
- Recording alignment and channel fusion (Overlays `TelemetrySyncEngine`,
  `RecordingAlignment` and `ChannelFusion`, `d4d1039`):
  `synchronizeTelemetry` finds the offset between two speed traces (a 1 Hz
  search ranked by significance, refined at 10 Hz). `alignRecordings`
  (`recording-alignment-v1`) describes how an alternative recording lines up
  with a run's primary: the declared offset from the loggers' start
  timestamps, the measured offset and drift from windows along the overlap,
  their uncertainty, and a status (aligned, ambiguous, conflicting,
  insufficient) with its reason; a match that repeats a lap away is decided
  only by an agreeing declared clock. Nothing is applied to either recording.
  `fuseChannels` (`channel-fusion-v1`) brings an aligned alternative's
  channels onto the primary clock: a channel only the alternative has is
  added, one both have keeps the primary unless a `FusionPolicy` rule
  (`primaryOnly`, `fillGaps`, `preferAlternative`) says otherwise, a
  disagreement without a rule is reported as unresolved
  (`fusionConflictTolerance`), units must match exactly and samples are
  never resampled; every output segment keeps its source and clock.
  `fusedSession` gives the primary session with the fusion applied.
- A day's source fusion without a review (`day_fusion.dart`, FET-51):
  `importedAlternatives` names the RCZ grouped under each VBO run;
  `fuseRunRecordings` aligns it and, when the alignment is "aligned", fuses
  it at once (`fuseImportedRuns` does both): added channels join, every
  shared channel keeps the VBO, and a conflicting one gets a `primaryOnly`
  rule. `withFusionRule` changes one channel's rule. `RunFusion.decision` is
  the run's `fusion` object of the `.fetproject` format (Overlays KAN-103),
  bound to both recordings' content SHA-256; `dayDocument` writes it with the
  RCZ as the run's alternative source (updating that entry, never adding a
  second one). `openDay` does not read the RCZ: `OpenedDay.alternatives`
  names each run's, and `resolveDocumentAlternative` (meant for a background
  isolate; `fuseOpenedDay` does all) reads it, applies the decision without
  aligning again while both recordings still match (`fusionDecisionApplies`)
  and aligns afresh otherwise. A file that is not the content the document
  asserts is used only when it is the same drive as the VBO
  (`sameDriveInOtherFormat`), with `RunFusion.documentChanged` set so its
  entry is rewritten; otherwise it is a different recording.
  `findMovedRecordings` also looks for missing alternatives
  (`missingAlternatives`), by content or else by name, and `openDay` takes
  them as `relinkedAlternatives`. Laps and lap timing never come from the
  fused session.

Every untrusted size is bounded before allocation (`VboLimits`), and long
operations take a `CancellationCheck`.

## Matching FlappedEar Overlays

Both apps must read a file identically: the `.fetproject` fingerprint depends on
channel names and sample counts. The behaviour follows FlappedEar Overlays'
`VboParser.cpp`, `LapTiming.cpp`, `RczParser.cpp`, `TelemetryImportPlan.cpp`, `TelemetryFolderScan.cpp`, `TelemetrySource.cpp`, `OutingLaps.cpp`, `TrackInference.cpp` and `OutingLapDerivation.cpp` (VBOOverlay `1a96ae3`), re-implemented in
Dart. The handover section "VBO" in VBOOverlay summarises the rules.

`test/parity/cpp_parity_test.dart` checks this file by file. The reference
`test/parity/cpp_reference.json` is the output of Overlays' own C++ code, built in
`tool/cpp_reference_dump`, over the synthetic corpus in `test/parity/corpus` and
the fixtures in `test/fixtures`. Parsed values match exactly; values derived
through trigonometry are compared to 1e-9 relative, because C libraries may
differ in the last bit. See [tool/README.md](tool/README.md) to regenerate it.
`test/parity/progress_parity_test.dart` does the same for the track-progress
port (`TrackProgress.cpp` and `TelemetrySession::sampledSegments`, Overlays
`d4d1039`) against `test/parity/progress_reference.json` from
`tool/cpp_progress_dump`.
`test/parity/segments_parity_test.dart` does the same for the segment port
(`TrackSegments.cpp`, `TrackSegmentProposals.cpp`, `TrackSegmentReview.cpp`
and the review and automatic-approval steps of Overlays' app, `d4d1039`)
against `test/parity/segments_reference.json` from `tool/cpp_segments_dump`.
`test/parity/segment_editing_parity_test.dart` does the same for segment
editing (`TrackSegmentEditing.cpp` and the rest of `TrackSegmentReview.cpp`,
`d4d1039`) against `test/parity/segment_editing_reference.json` from
`tool/cpp_segment_editing_dump`.
`test/parity/corner_metrics_parity_test.dart` does the same for the Corner
Analyzer port (`CornerPhases`, `CornerSpeeds`, `BrakingOnset`,
`BrakingMetrics`, `ExitMetrics`, `DrivingVariability`, `d4d1039`) against
`test/parity/corner_metrics_reference.json` from `tool/cpp_corner_metrics_dump`.
`test/parity/progression_parity_test.dart` does the same for the ranking,
progression, lap consistency and time-loss and section presentation
(`OutingLaps.cpp`, `Consistency.cpp`, `OutingTheoreticalBestResults.cpp` and
the lap consistency of Overlays' app, `d4d1039`) against
`test/parity/progression_reference.json` from `tool/cpp_progression_dump`.
`test/parity/dayreport_parity_test.dart` does the same for channel
summaries, temperature associations, focus areas and the day report
(`ChannelSummary.cpp`, `TemperatureAssociation.cpp`,
`OutingChannelSummaries.cpp`, `FocusAreas.cpp`, `DayReport.cpp`,
`OutingDayReport.cpp` and the day-report and association steps of Overlays'
app, `d4d1039`) against `test/parity/dayreport_reference.json` from
`tool/cpp_dayreport_dump`, comparing whole documents.
`test/parity/comparison_parity_test.dart` does the same for the lap detail
and A/B comparison (`MapLayers.cpp`, `TrackGeometry.cpp` and the comparison,
map-layer and lap-chart functions of Overlays' app, `d4d1039`) against
`test/parity/comparison_reference.json` from `tool/cpp_comparison_dump`.
`test/parity/corner_analyzer_parity_test.dart` does the same for the Corner
Analyzer of two compared laps (`comparisonSegmentMetrics`,
`comparisonSharedSegmentation`, `comparisonHeartRate` and the time-loss
observations of Overlays' app, `d4d1039`) against
`test/parity/corner_analyzer_reference.json` from
`tool/cpp_corner_analyzer_dump`.
`test/parity/driving_parity_test.dart` does the same for G-G, driving
states and coasting (`GgPairs.cpp`, `DrivingStates.cpp`,
`CoastingAnalysis.cpp` and the matching functions of Overlays' app,
`d4d1039`) against `test/parity/driving_reference.json` from
`tool/cpp_driving_dump`, over the synthetic recordings of
`test/parity/driving` (`tool/generate_driving_corpus.py`).
`test/parity/fusion_parity_test.dart` does the same for recording alignment
and channel fusion (`TelemetrySyncEngine.cpp`, `RecordingAlignment.cpp` and
`ChannelFusion.cpp`, `d4d1039`) against `test/parity/fusion_reference.json`
from `tool/cpp_fusion_dump`, over synthetic sessions built identically on
both sides; every value is equal, with no tolerance.

Known, deliberate differences:

- **Decoded-memory budget.** Overlays' `maximumDecodedBytes` argument belongs to
  its desktop session cache. The phone budget is decided separately (KAN-129), so
  it is not ported.
- **Day lap references** (`OutingLaps.cpp`, VBOOverlay `ca2bde5`) carry the run,
  the content SHA-256, the type and the exact bounds; `dayDocument` adds
  `eventId`, `sourceId` and `derivationKey` when it writes them, and `openDay`
  applies only references whose content and derivation key still match.
- **Detected layout ids** are computed again on opening rather than read from
  the saved `trackInference` provenance. The id is derived from the cluster's
  first run and its content, so it is the same as long as the routes group the
  same way.
- **The group shown first** is the one with the most eligible laps. Overlays
  takes the first resolved group in id order, which is arbitrary; on a day with
  one group both choose the same.
- **Progression** has no group label or formatted clock: the app writes
  its own, and an undated run says so instead of "Time unavailable · import
  order". A time-loss list that is unavailable keeps Overlays' reason code
  (`noReferenceLap`) for the app to word.
- **Section progression laps** with exactly equal times keep their
  population order; Overlays' `std::sort` leaves it unspecified.
- **Day-report decisions key.** `dayDecisionsKey` hashes the group, the
  approved segments, the eligible and excluded laps and the best lap
  (SHA-256 of their JSON); Overlays hashes its own project state. Both are
  opaque and only compared for equality.
- **Channel summaries** read the recordings the day already holds; Overlays
  loads and verifies each one from the project (`loadOutingLapDetail`). A
  run without a recording says "Recording unavailable.".
- **Focus areas and time losses** with exactly equal values keep their input
  order; Overlays' `std::sort` leaves it unspecified.
- **While the day's laps are derived again**, the report names no group, as
  Overlays' ranking does while it loads.
- **`timingGateRevision`** (`gates-v1`) is not here; it belongs with the other
  document ids.
- **Lap chart channels.** Without a remembered choice, `lapChartChannels`
  adds the throttle (or else the brake) as a fourth chart when recorded;
  Overlays shows speed, lateral and longitudinal G and the pedals only when
  added (`includePedals: false` is its rule).
- **A comparison** is built from the two laps' recordings the day already
  holds; Overlays loads and verifies each lap from the project
  (`loadOutingLapDetail`) and keeps its pair in the document.
- **Driving states of a comparison.** `comparisonDrivingStates` (every
  state's time, braking while cornering and coasting of both laps over the
  shown range) is Telemetry's own; Overlays shows trail braking per segment
  and coasting for one lap only. It uses the same ported functions.
- **Sync ranking key.** The coarse sync search ranks offsets by
  `atanh(r) * sqrt(n - 3)`. The port reproduces glibc's generic `atanh`;
  on x86-64 CPUs with FMA, glibc uses an FMA build of `log1p` that can differ
  in the last bit, so Overlays itself can rank two offsets within one ULP of
  each other differently by CPU. The parity cases and the real day give the
  same results with both builds.
- **Fusion unit comparison.** Units are compared trimmed and case-folded
  per character; Qt's `QString::trimmed` and case-insensitive comparison can
  differ from Dart's `trim` and this folding for rare characters (for
  example U+FEFF, which Dart trims and Qt keeps).
- **Start/finish seam.** A lap's last projected sample can sit exactly where
  the axis wraps; Overlays and this port may then place it at the axis
  length or at 0 (a last-digit difference in the projection's distance
  arithmetic). Positions derived from that one sample can differ; times and
  every value of the states themselves do not.

## Development

```bash
cd packages/telemetry_core
dart pub get
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
dart test
```

Real recordings are private (`FlappedEar/refdata`) and never committed. Point
`FLAPPEDEAR_REAL_VBO` at one to run `test/real_vbo_test.dart`; report its result
separately from the synthetic tests. `FLAPPEDEAR_REAL_RCZ` does the same for
`test/rcz/rcz_parser_test.dart`; it prints summary figures only.
`FET_FUSION_DAY` names a folder of a real day for
`test/fusion/real_fusion_test.dart`, which aligns and fuses each VBO and RCZ
pair of the import plan and prints summary figures only (see
[tool/README.md](tool/README.md) to compare it with Overlays' C++).
