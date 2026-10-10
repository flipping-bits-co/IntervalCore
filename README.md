# IntervalCore

Pure Swift interval-training domain for Ember Reps (iPhone + Apple Watch): models, timeline
compiler, engine, presets, and formatting. Foundation only. No SwiftUI, SwiftData, HealthKit,
or WatchConnectivity, so it runs under `swift test` on the Mac and both app targets link it.
Swift 6 language mode. Every public type is `Sendable`, and value types are `Codable, Hashable`.

```sh
swift test                          # all tests
swift test --enable-code-coverage   # + coverage (see "Coverage" below)
```

## How it fits together

```
[IntervalBlock] ──TimelineCompiler──▶ Timeline ──▶ IntervalEngine ──▶ [EngineEvent]
 (what the user    (flat [TimelineStep],           (feed it time,       (apps map to haptics,
  built/saved)      loop range, workout end)        HR, metrics, taps)    audio cues, UI)
```

1. **Model.** A program is `[IntervalBlock]` plus a `WorkoutEnd`. A block is `steps × repeats`.
   A step is a `StepKind` + optional name + an `EndCondition`. `ProgramSnapshot` is the Codable
   program used for the Watch cache and WatchConnectivity. On the phone, SwiftData stores the blocks as JSON.
2. **Compile.** `TimelineCompiler.compile(blocks, workoutEnd:)` flattens everything into a
   `Timeline`: one `TimelineStep` per step occurrence, carrying `blockIndex`, `round`/`totalRounds`,
   `stepIndex`, `kind`, `end`. The timeline strip, "next up", the progress ring, and the Watch all
   read this one structure.
3. **Run.** `IntervalEngine` walks the timeline. It's a struct with no clock, timers, or
   callbacks. The caller pushes inputs in and gets ordered events back:

```swift
var engine = IntervalEngine(program: Presets.tabata())
engine.start(at: .now)
// every timer fire:
for event in engine.tick(at: .now) {
    switch event {
    case .stepStarted(let index, _): haptics.play(for: engine.timeline.steps[index].kind)
    case .countdown(_, let n): audio.beep(n)
    case .completed: save()
    default: break
    }
}
engine.updateHeartRate(bpm)                        // from HKLiveWorkoutBuilder
engine.updateMetrics(distance: total, calories: kcal)   // cumulative totals
engine.next() / skip() / previous() / pause(at:) / resume(at:) / finish(at:)
```

The apps hold the engine as a `var` inside their `@Observable` view model or manager, so every
mutation publishes. Tests drive it with `advance(by:)` and fixed dates, which makes it deterministic.

## Types

| Type | What |
|---|---|
| `StepKind` | `prepare, warmup, work, rest, cooldown`. `label`, `iconName` (SF Symbol string). |
| `EndCondition` | `.time`, `.distance(meters:)`, `.calories`, `.reps` (tap Done), `.open` (tap Next), `.heartRateBelow/Above(bpm:maxWait:)`. `maxWait <= 0` means no fallback. |
| `IntervalStep`, `IntervalBlock` | Builder data. `skipLastRest` (default on) drops trailing rests in the final round. `loopsUntilTarget` marks the loop range. |
| `Activity` | Saved activity, mapped to `HKWorkoutActivityType` in the apps. `supportsDistance`. |
| `WorkoutEnd`, `WorkoutTarget` | `.allBlocks` or `.target(.time / .distance / .calories)`. |
| `ProgramSnapshot` | Codable program: `displayName`, `structureHash`, `compile()`, `estimatedDuration()`. |
| `Timeline`, `TimelineStep` | Compiled output. `loopRange`, `postLoopStart`. |
| `IntervalEngine` | The runner. State: `status`, `currentStep`, `nextStep`, `stepRemaining`, `stepProgress`, `totalElapsed`, `loopIteration`, `records`… |
| `EngineEvent` | `stepStarted`, `countdown` (3-2-1), `halfway` (≥ 60 s steps), `loopStarted`, `targetReached`, `roundLogged`, `paused`, `resumed`, `completed`. |
| `StepRecord` | Per-step actuals (duration, end reason, distance, calories) for summaries and splits. |
| `Preset`, `Presets` | Work/Rest, Tabata, EMOM, AMRAP, For Time. Each returns a `ProgramSnapshot`. |
| `LadderGenerator` | start/step/peak (± descending) → one concrete block, with optional rest. |
| `DurationFormatter` | `clock` "1:05", `countdown` (rounds up), `short` "18 min", `estimate` "~18 min", `distance`. |
| `DurationEstimator`, `EstimateAssumptions` | Totals with an `isEstimate` flag for non-time steps (F8). |
| `ProgramNamer` | Auto names: "Warm-up + 8×1:00/1:00 + Cool-down". |
| `StructureHash` | Stable 16-hex fingerprint for Recents dedupe. |
| `CueMapper`, `Cue`, `CuePreferences`, `HapticStrength`, `WatchSettings` | Shared audio cue rules and the phone → Watch cue/haptic settings. |
| `HapticPreset`, `WatchHaptics`, `HapticFeel`, `HapticCueEvent` | Watch haptic presets (subtle / standard / strong / max) + per-event feel overrides (3-2-1 and halfway toggles are views of them), inside `WatchSettings.haptics`. |
| `TrackDefinition`, `TrackLevel`, `TrackSession`, `TrackAssessment`, `TrackCadence`, `TrackRef` | Training tracks (Phase 7). See "Training tracks". |
| `TrackChainer`, `TrackOutcome`, `TrackProgress` | Chain sessions into one program; map a result back to advance / repeat / unchanged; next session, % and due hint. |
| `RepsSetBuilder`, `BundledTracks`, `TemplateCatalog`, `StableUUID` | Sets-with-rest blocks; the launch tracks and extra templates; name-derived stable ids. |
| `LibraryQuery`, `LibraryRankable`, `LibraryItem` | Library ranking (F10): `sections` → pinned / recents / templates / others. Score = 0.5^(age/14 d) × (1 + ln(1 + uses)). Recents skip pinned and dedupe by `structureHash`. |

## Engine rules

- **Time.** One `advance`/`tick` can cross any number of step boundaries. Pauses don't count.
  `totalElapsed` is active time.
- **Untimed steps** (`reps`, `open`, `distance`, `calories`, HR without `maxWait`) count up and
  never end on time. `stepRemaining` is `nil` for them.
- **HR steps** end when the latest HR meets the threshold (≤ for below, ≥ for above) after the
  step has started (`stepElapsed > 0`, same as RowUp2), or at `maxWait` (`.heartRateTimeout`).
  No 3-2-1 for HR steps.
- **Metric steps** measure from the totals snapshotted at step start. Feed cumulative workout totals.
- **Loop until target.** Only when `workoutEnd` is a target. The loop range runs from the first to
  the last `loopsUntilTarget` block. Loop blocks keep their final rest, since it sits between iterations.
- **Target reached.** Jumps to the first step after the loop range (e.g. cool-down), or completes
  right away if nothing follows. With no loop blocks, a time target is therefore a cap (For Time).
- **`previous()`** goes to the start of the previous step, back across a loop boundary if needed.
  On the first step it restarts that step. `restartStep()` restarts the current one.

## Phone ↔ Watch messages

Both apps send everything through `WCMessage`, so neither side hand-builds dictionaries:

```swift
// small messages: sendMessage / transferUserInfo / updateApplicationContext
WCSession.default.sendMessage(try WCMessage.liveSample(sample).toDictionary(), replyHandler: nil)
let message = try WCMessage(dictionary: received)   // throws on unknown type / newer version

// SessionResult: always transferFile (no size cap, full 5 s HR)
let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
let url = FileManager.default.temporaryDirectory.appending(path: "\(result.sessionID).json")
try data.write(to: url)
WCSession.default.transferFile(url, metadata: metadata)

// receiving side, inside session(_:didReceive:) (the file URL is only valid during the call)
let message = try WCMessage(fileURL: file.fileURL, metadata: file.metadata)
WCMessage.sessionID(fromMetadata: file.metadata)    // dedupe before decoding
```

| Message | Direction / transport | What |
|---|---|---|
| `SessionCommand.start(SessionStart)` | phone → Watch, `sendMessage` (fall back to `transferUserInfo`) | Start or mirror a session. |
| `SessionCommand.control(_:sessionID:)` | either way, `sendMessage` | pause / resume / next / skip / previous / restartStep / logRound / end. |
| `SessionCommand.syncPrograms([ProgramSnapshot])` | phone → Watch, `updateApplicationContext` | Replaces the Watch's pinned + recents cache. |
| `SessionCommand.heartRateStream(enabled:)` | phone → Watch, `sendMessage` | Start/stop Watch HR for a phone-only session. |
| `WCMessage.heartRate(HeartRateReading)` | Watch → phone, `sendMessage` (~1 Hz) | One live HR reading (bpm, timestamp) for phone-only sessions. |
| `LiveSample` | runner → other device, `sendMessage` (~1 Hz) | Mirror state: step, remaining, HR, totals. `LiveSample(sessionID:engine:timestamp:)`. |
| `SessionResult` | Watch → phone, **`transferFile`** | Program, dates, completion, `StepRecord`s, and the 5 s HR series. |

Envelope: `["type", "v": 1, "payload": JSON Data]`. File transfer: the file is the JSON payload, and
the metadata is `["type", "v", "sessionID"]`. Both decode with the same typed errors. The receiver accepts
`v` ≤ its own schema version, and checks `v` before `type`. `HeartRateDownsampler` turns raw HR into
~5 s buckets (closing a bucket on step change). Each `HeartRateSample` has an active-time offset, bpm, and
step index, so it joins `StepRecord`s for per-step-kind zones. `StepRecord` and `HeartRateSample` use short
JSON keys, and `StepRecord` omits default values. The worst case tested, 4 h of 20/10 (959 steps, ~2880 HR
samples), is about 128 KB.

## Cues and Watch settings

`CueMapper.cues(for: events, timeline:, preferences:)` turns engine events into `Cue`s: `.phase(name)`
(the step name, or the kind label), `.countdown(3/2/1)`, `.halfway`, and `.completed`. Phone and Watch share
this one rule set. After a multi-boundary tick only the latest step is announced, and stopping early is silent.
`CuePreferences` (enabled, voice, countdownBeeps, halfway, `watchVoiceCues` = false) filters the cues;
`watchVoiceCues` only decides whether the Watch plays cues at all. `HapticStrength` is light / normal /
strong (default strong), used for iPhone haptics. The Watch uses `WatchHaptics { preset, countdownTaps,
halfwayTap }`: a `HapticPreset` (subtle / standard / strong / max, default strong) whose patterns live in the
Watch app, since `WKHapticType` is watchOS-only. `WatchSettings.hapticStrength` is kept as a computed view of the
preset; encoding writes both, and an older payload with only `hapticStrength` maps light → subtle, normal → standard,
strong → strong. `SessionCommand.testHaptic(preset)` (phone → Watch) plays a preset's work-start pattern;
`SessionCommand.watchHapticsChanged(haptics, changedAt:)` (Watch → phone) reports a change made on the Watch.
`WatchHaptics` keeps a remembered `HapticFeel` per `HapticCueEvent` and a separate `disabled` set; `override(for:)` gives
the resolver's answer (disabled → off, else feel, else `nil` = preset). Customize lists use `HapticSelection` with
`selection(for:)` / `select(_:for:)`;
`SessionCommand.testHapticCue(event, feel:, preset:)` plays one event's feel, or the preset's pattern when `feel` is nil.

The phone syncs `WatchSettings { cues, haptics }` in the same application context as its programs:

```swift
// phone
try session.updateApplicationContext(WCMessage.applicationContext(programs: snapshots, settings: settings))
// Watch: programs exactly as before, settings next to them (defaults when an older phone sent none)
let message = try WCMessage(dictionary: context)          // .command(.syncPrograms(...))
let settings = WatchSettings(applicationContext: context)
```

`engine.remainingEstimate(assumptions:)` gives the time left for the live "elapsed · ~remaining" line,
using the same rules as `DurationEstimator`. Format it with `DurationFormatter.estimate`.

## Training tracks

A track is a per-exercise progression: `TrackDefinition` → `levels` (A/B/C, or one) → `sessions`, each one
ordinary `ProgramSnapshot`. Progress lives in the app (the phone's `TrackEnrollment`), never in the definition.

```
Up next ──TrackChainer.chain(links)──▶ Chain { program (tagged), refs, gaps } ──▶ run as any program
                                                                                     │ SessionResult
TrackEnrollment ◀── advance / repeat / unchanged ◀── TrackOutcome.evaluate(result, autoRepeat:) ◀┘
```

- **Chain.** `TrackChainer.chain([Link], lastUsedGap:)` puts a Get Ready block, each session's blocks, and a real
  rest block per gap (user value > next track's lead-in > `lastUsedGap` > 2:00) into one program, and tags it with a
  `TrackRef` per track (enrolment, session id, block ids, "Push-ups · W2 D1"). One link works too (Run / Walk). Only
  chain `isChainable` tracks together: Run / Walk stays its own workout.
- **Tags travel.** `ProgramSnapshot.trackRefs` rides inside the program on `syncPrograms`, `SessionStart` and
  `SessionResult` (`start.trackRefs`, `result.trackRefs`). Older builds ignore the key. Keep block ids and `trackRefs`
  when copying programs.
- **Reps.** `engine.next(repsLogged:)` ends a step and stores `StepRecord.repsLogged`; a plain `next()` on a
  `.reps(n)` step logs `n`.
- **Outcome.** `TrackOutcome.evaluate` is pure. Missed = a work step skipped, never finished, or below its reps
  target. Missed + auto-repeat → `.repeat`; otherwise `.advance`; blocks never reached → `.unchanged`. Re-tests always
  advance and give `maxRepsLogged` for `TrackAssessment.levelID(forMaxReps:)`. `Result.decision(repeatOverride:)`
  applies the summary toggle.
- **Progress.** `TrackProgress(definition:levelID:nextSessionIndex:completions:cadence:now:calendar:)` gives the
  next session, `fractionComplete`, and `due` (`.due`, `.resting(until:)`, `.weeklyGoalMet`, `.notScheduledToday`,
  `.finished`). It's a hint for pre-ticks and reminders; nothing blocks a start.
- **Watch Up next.** `WatchUpNext { chained, items, generatedAt }` goes in the phone's application context via
  `WCMessage.applicationContext(programs:settings:upNext:)`; the Watch reads it with
  `WatchUpNext(applicationContext:)` (empty when missing) and starts the tagged programs as they are.
- **Content.** `BundledTracks`: Run / Walk (C25K, 9 × 3), Push-ups, Pull-ups (level A = assisted + negatives),
  Sit-ups (3 levels, 6 × 3, re-tests W3 D3 and W6 D3), Plank (4 × 3 timed holds). `TemplateCatalog`: 30/30,
  4×4 Norwegian, 10-20-30, Pyramid. Every id is a `StableUUID` derived from a fixed name.

## Session stats

`SessionStats(steps:heartRate:)` (or `SessionStats(result:)`) breaks a finished session down for the
summary and History. It's pure: feed it `engine.records` + `HeartRateDownsampler.finish()` live, or a
`SessionResult` later.

| Property / method | Returns |
|---|---|
| `total`, `perStep`, `byKind` | `SegmentStats` (duration, distance, calories, avg/max HR, step count) at each level. |
| `rounds` | `[RoundStats]`: per-round splits (`work`, `rest`, `total`) in run order. `sequence` numbers rounds across loop passes; `previous()` repeats merge into their round. |
| `blocks` | `[BlockStats]`: per-block totals plus that block's rounds. |
| `zoneBreakdown(HeartRateZones)` | `[ZoneTime]`: seconds in each zone per step kind. |
| `totalZoneTime(HeartRateZones)` | Seconds per zone, all kinds combined. |

`HeartRateZones(maxHeartRate:lowerBounds:)` (or `init(age:)` = 220 − age) maps bpm to a zone index.
Defaults match RowUp2's `HRZone`: Z0 < 50 %, then 10 % bands up to Z5 ≥ 90 %. The apps own zone names
and colours. Each HR sample belongs to exactly one step record (same timeline index, inside its time window;
the later record wins on a shared edge). Zone time is integrated per step: the latest reading at or before the step's start carries in until
the step's first reading, and each reading then runs to the next one or the step end. A reading never
covers more than `maxSampleSpan` (15 s) past its own offset, so sensor dropouts aren't credited to any zone.

## Coverage

```sh
swift test --enable-code-coverage
xcrun llvm-cov report .build/debug/IntervalCorePackageTests.xctest/Contents/MacOS/IntervalCorePackageTests \
  -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='(Tests|\.build)/'
```

## Parity with RowUp2

`Tests/IntervalCoreTests/Fixtures/RowUp2Reference.swift` is a copy of RowUp2's `IntervalManager`
and `WorkoutSegment`, used only as a test oracle. `ParityTests` runs RowUp2 segment fixtures
(time, distance-triggered, HR-triggered, loop-on-target) through both engines second by second
and requires the same step sequence and durations. The copy is a frozen reference, so don't edit it.
