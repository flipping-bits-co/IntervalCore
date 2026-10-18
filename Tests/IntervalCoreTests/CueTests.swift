import Foundation
import Testing
@testable import IntervalCore

/// Ported from the iPhone's `AudioCueMapperTests`.
struct CueMapperTests {
    let timeline = Presets.tabata().compile()
    let all = CuePreferences()

    @Test func transitionsSpeakTheKindOrName() {
        #expect(CueMapper.cues(for: [.stepStarted(index: 0, reason: .start)], timeline: timeline, preferences: all) == [.phase("Get Ready")])
        #expect(CueMapper.cues(for: [.stepStarted(index: 1, reason: .timeElapsed)], timeline: timeline, preferences: all) == [.phase("Work")])

        let named = ProgramSnapshot(blocks: [IntervalBlock(steps: [IntervalStep(kind: .work, name: " Squats ", end: .time(40))])]).compile()
        #expect(CueMapper.cues(for: [.stepStarted(index: 0, reason: .start)], timeline: named, preferences: all) == [.phase("Squats")])
    }

    @Test func countdownHalfwayAndCompletion() {
        let events: [EngineEvent] = [.countdown(index: 1, secondsRemaining: 3), .halfway(index: 1), .completed(reason: .finished)]
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: all) == [.countdown(3), .halfway, .completed])
    }

    @Test func targetCompletionIsAnnounced() {
        #expect(CueMapper.cues(for: [.completed(reason: .targetReached)], timeline: timeline, preferences: all) == [.completed])
    }

    @Test func onlyTheLatestStepIsAnnouncedAfterAMultiBoundaryTick() {
        let events: [EngineEvent] = [.stepStarted(index: 1, reason: .timeElapsed), .stepStarted(index: 2, reason: .timeElapsed)]
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: all) == [.phase("Rest")])
    }

    @Test func countdownBeforeTheLatestStepStillBeeps() {
        let events: [EngineEvent] = [
            .countdown(index: 1, secondsRemaining: 1),
            .stepStarted(index: 2, reason: .timeElapsed),
            .stepStarted(index: 3, reason: .timeElapsed),
        ]
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: all) == [.countdown(1), .phase("Work")])
    }

    @Test func stoppingEarlyIsSilent() {
        #expect(CueMapper.cues(for: [.completed(reason: .stopped)], timeline: timeline, preferences: all).isEmpty)
    }

    @Test func outOfRangeStepIsSilent() {
        #expect(CueMapper.cues(for: [.stepStarted(index: 99, reason: .start)], timeline: timeline, preferences: all).isEmpty)
    }

    @Test func nonCueEventsAreIgnored() {
        let events: [EngineEvent] = [.paused, .resumed, .targetReached, .loopStarted(iteration: 2), .roundLogged(count: 1)]
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: all).isEmpty)
    }

    @Test func preferencesFilterCues() {
        let events: [EngineEvent] = [.stepStarted(index: 1, reason: .timeElapsed), .countdown(index: 1, secondsRemaining: 2), .halfway(index: 1)]
        var noVoice = all
        noVoice.voice = false
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: noVoice) == [.countdown(2)])
        #expect(CueMapper.cues(for: [.completed(reason: .finished)], timeline: timeline, preferences: noVoice).isEmpty)

        var noBeeps = all
        noBeeps.countdownBeeps = false
        noBeeps.halfway = false
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: noBeeps) == [.phase("Work")])

        var off = all
        off.enabled = false
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: off).isEmpty)
    }

    /// The Watch toggle gates whether the Watch plays cues at all; it never changes the mapping.
    @Test func watchVoiceCuesDoesNotAffectMapping() {
        var watchOn = all
        watchOn.watchVoiceCues = true
        let events: [EngineEvent] = [.stepStarted(index: 1, reason: .timeElapsed), .halfway(index: 1)]
        #expect(CueMapper.cues(for: events, timeline: timeline, preferences: watchOn)
                == CueMapper.cues(for: events, timeline: timeline, preferences: all))
    }

    /// A real run through the engine produces the cue sequence the user hears.
    @Test func engineDrivenTabata() {
        var engine = IntervalEngine(program: Presets.tabata())
        var cues = CueMapper.cues(for: engine.start(at: .testEpoch), timeline: engine.timeline, preferences: all)
        for second in 1...300 {
            cues += CueMapper.cues(for: engine.tick(at: Date.testEpoch.addingTimeInterval(Double(second))),
                                   timeline: engine.timeline, preferences: all)
        }
        #expect(cues.first == .phase("Get Ready"))
        #expect(cues.last == .completed)
        #expect(cues.filter { $0 == .phase("Work") }.count == 8)
        #expect(cues.filter { $0 == .phase("Rest") }.count == 7)
        #expect(cues.filter { $0 == .countdown(3) }.count == 16)
        #expect(!cues.contains(.halfway))
    }

    @Test func spokenText() {
        #expect(Cue.phase("Work").spokenText == "Work")
        #expect(Cue.halfway.spokenText == "Halfway")
        #expect(Cue.completed.spokenText == "Workout complete")
        #expect(Cue.countdown(2).spokenText == nil)
        #expect(Cue.phase("Rest").isSpoken)
        #expect(!Cue.countdown(1).isSpoken)
    }
}

struct CuePreferencesTests {

    @Test func defaults() {
        let prefs = CuePreferences()
        #expect(prefs.enabled && prefs.voice && prefs.countdownBeeps && prefs.halfway)
        #expect(!prefs.watchVoiceCues)
        #expect(HapticStrength.default == .strong)
        #expect(WatchSettings() == WatchSettings(cues: CuePreferences(), hapticStrength: .strong))
    }

    @Test func roundTrip() throws {
        let settings = WatchSettings(
            cues: CuePreferences(enabled: true, voice: false, countdownBeeps: true, halfway: false, watchVoiceCues: true),
            hapticStrength: .light
        )
        #expect(try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(settings)) == settings)
        #expect(try JSONDecoder().decode(Cue.self, from: JSONEncoder().encode(Cue.phase("Squats"))) == .phase("Squats"))
    }

    @Test func missingKeysTakeDefaults() throws {
        let prefs = try JSONDecoder().decode(CuePreferences.self, from: Data(#"{"voice":false}"#.utf8))
        #expect(prefs == CuePreferences(voice: false))
        #expect(!prefs.watchVoiceCues)

        let settings = try JSONDecoder().decode(WatchSettings.self, from: Data("{}".utf8))
        #expect(settings == WatchSettings())
    }

    @Test func unknownHapticStrengthFallsBackToDefault() throws {
        let decoded = try JSONDecoder().decode(WatchSettings.self, from: Data(#"{"hapticStrength":"thunder"}"#.utf8))
        #expect(decoded.hapticStrength == .strong)
        #expect(HapticStrength.allCases.map(\.label) == ["Light", "Normal", "Strong"])
        #expect(HapticStrength.normal.id == "normal")
    }

    // MARK: - Start countdown

    @Test func startCountdownDefaultsToThree() {
        #expect(CuePreferences().startCountdownSeconds == 3)
    }

    @Test func oldPayloadWithoutStartCountdownDecodesToDefault() throws {
        let prefs = try JSONDecoder().decode(CuePreferences.self, from: Data(#"{"voice":false}"#.utf8))
        #expect(prefs.startCountdownSeconds == 3)

        // A full pre-field payload, as an older phone would have sent it.
        let legacy = #"{"enabled":true,"voice":true,"countdownBeeps":true,"halfway":true,"watchVoiceCues":false}"#
        let fromLegacyPhone = try JSONDecoder().decode(CuePreferences.self, from: Data(legacy.utf8))
        #expect(fromLegacyPhone.startCountdownSeconds == 3)
        #expect(fromLegacyPhone == CuePreferences())
    }

    @Test func startCountdownRoundTrips() throws {
        let prefs = CuePreferences(startCountdownSeconds: 10)
        let decoded = try JSONDecoder().decode(CuePreferences.self, from: JSONEncoder().encode(prefs))
        #expect(decoded == prefs)
        #expect(decoded.startCountdownSeconds == 10)

        let settings = WatchSettings(cues: prefs, hapticStrength: .light)
        let decodedSettings = try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(settings))
        #expect(decodedSettings.cues.startCountdownSeconds == 10)
    }

    @Test func startCountdownClampsToZeroToFifteen() throws {
        #expect(CuePreferences(startCountdownSeconds: -5).startCountdownSeconds == 0)
        #expect(CuePreferences(startCountdownSeconds: 0).startCountdownSeconds == 0)
        #expect(CuePreferences(startCountdownSeconds: 15).startCountdownSeconds == 15)
        #expect(CuePreferences(startCountdownSeconds: 100).startCountdownSeconds == 15)
        #expect(CuePreferences.clampedStartCountdown(42) == 15)
        #expect(CuePreferences.clampedStartCountdown(-1) == 0)

        // An out-of-range synced value (e.g. a corrupt payload) still clamps on decode.
        let decoded = try JSONDecoder().decode(CuePreferences.self, from: Data(#"{"startCountdownSeconds":999}"#.utf8))
        #expect(decoded.startCountdownSeconds == 15)
        let negative = try JSONDecoder().decode(CuePreferences.self, from: Data(#"{"startCountdownSeconds":-3}"#.utf8))
        #expect(negative.startCountdownSeconds == 0)
    }

    @Test func beepSecondsIsAtMostThreeAndNeverExceedsTheCountdown() {
        #expect(CuePreferences.beepSeconds(forCountdown: 3) == 3)
        #expect(CuePreferences.beepSeconds(forCountdown: 10) == 3)
        #expect(CuePreferences.beepSeconds(forCountdown: 15) == 3)
        #expect(CuePreferences.beepSeconds(forCountdown: 2) == 2)
        #expect(CuePreferences.beepSeconds(forCountdown: 1) == 1)
        #expect(CuePreferences.beepSeconds(forCountdown: 0) == 0)
        // Clamped before counting, so out-of-range inputs still behave sanely.
        #expect(CuePreferences.beepSeconds(forCountdown: -4) == 0)
        #expect(CuePreferences.beepSeconds(forCountdown: 999) == 3)
    }
}

struct WatchSettingsSyncTests {
    let programs = [Presets.tabata(), Presets.emom()]

    @Test func contextCarriesProgramsAndSettings() throws {
        let settings = WatchSettings(cues: CuePreferences(watchVoiceCues: true), hapticStrength: .normal)
        let context = try WCMessage.applicationContext(programs: programs, settings: settings)
        _ = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)

        // The Watch's existing decode path still sees a plain syncPrograms command.
        #expect(try WCMessage(dictionary: context) == .command(.syncPrograms(programs)))
        #expect(WatchSettings(applicationContext: context) == settings)
    }

    /// Older phone builds send only the syncPrograms envelope.
    @Test func contextWithoutSettingsGivesDefaults() throws {
        let legacy = try WCMessage.command(.syncPrograms(programs)).toDictionary()
        let settings = WatchSettings(applicationContext: legacy)
        #expect(settings == WatchSettings())
        #expect(!settings.cues.watchVoiceCues)
        #expect(settings.hapticStrength == .strong)
    }

    @Test func unreadableSettingsGiveDefaults() throws {
        var context = try WCMessage.applicationContext(programs: programs, settings: WatchSettings(hapticStrength: .light))
        context[WatchSettings.contextKey] = Data("garbage".utf8)
        #expect(WatchSettings(applicationContext: context) == WatchSettings())
        context[WatchSettings.contextKey] = "not data"
        #expect(WatchSettings(applicationContext: context) == WatchSettings())
    }

    /// A newer phone may add preference fields; this build keeps what it knows.
    @Test func newerSettingsDecodeWhatTheyCan() throws {
        let json = #"{"cues":{"watchVoiceCues":true,"spokenRepCount":true},"hapticStrength":"normal","ledFlash":true}"#
        var context = try WCMessage.command(.syncPrograms(programs)).toDictionary()
        context[WatchSettings.contextKey] = Data(json.utf8)
        let settings = WatchSettings(applicationContext: context)
        #expect(settings.cues.watchVoiceCues)
        #expect(settings.cues.voice)
        #expect(settings.hapticStrength == .normal)
    }
}

struct RemainingEstimateTests {

    private func engine(_ program: ProgramSnapshot) -> IntervalEngine {
        var engine = IntervalEngine(program: program)
        engine.start(at: .testEpoch)
        return engine
    }

    @Test func timedWorkoutCountsDownExactly() {
        var e = engine(Presets.tabata())
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 240, isEstimate: false))
        e.advance(by: 47.5)
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 192.5, isEstimate: false))
        e.advance(by: 1000)
        #expect(e.remainingEstimate() == .zero)
    }

    @Test func totalsAgreeWithTheTimelineEstimateAtStart() {
        let program = ProgramSnapshot(activity: .running, blocks: [
            IntervalBlock(steps: [IntervalStep(kind: .warmup, end: .time(300))]),
            IntervalBlock(steps: [IntervalStep(kind: .work, end: .distance(meters: 400)), IntervalStep(kind: .rest, end: .time(60))], repeats: 4),
        ])
        let assumptions = EstimateAssumptions(activity: .running)
        #expect(engine(program).remainingEstimate(assumptions: assumptions) == program.estimatedDuration(assumptions: assumptions))
    }

    @Test func untimedCurrentStepIsAnEstimateThatShrinks() {
        var e = engine(ProgramSnapshot(blocks: [IntervalBlock(steps: [IntervalStep(kind: .work, end: .open)])]))
        e.advance(by: 20)
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 40, isEstimate: true))
        e.advance(by: 100)
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 0, isEstimate: true))
    }

    @Test func timeTargetLoopIsExact() {
        let program = ProgramSnapshot(blocks: [
            IntervalBlock(steps: [IntervalStep(kind: .work, end: .time(60)), IntervalStep(kind: .rest, end: .time(30))], loopsUntilTarget: true),
            IntervalBlock(steps: [IntervalStep(kind: .cooldown, end: .time(120))]),
        ], workoutEnd: .target(.time(600)))
        var e = engine(program)
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 720, isEstimate: false))
        e.advance(by: 250)
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 470, isEstimate: false))
        e.advance(by: 400)  // target reached at 600, 50 s into cool-down
        #expect(e.remainingEstimate() == DurationEstimate(seconds: 70, isEstimate: false))
    }

    @Test func distanceTargetLoopIsEstimated() {
        let program = ProgramSnapshot(activity: .rowing, blocks: [
            IntervalBlock(steps: [IntervalStep(kind: .work, end: .time(60)), IntervalStep(kind: .rest, end: .time(30))], loopsUntilTarget: true),
        ], workoutEnd: .target(.distance(meters: 2000)))
        var e = engine(program)
        e.updateMetrics(distance: 1000)
        #expect(e.remainingEstimate(assumptions: EstimateAssumptions(activity: .rowing)) == DurationEstimate(seconds: 250, isEstimate: true))

        let calories = ProgramSnapshot(blocks: program.blocks, workoutEnd: .target(.calories(100)))
        var c = engine(calories)
        c.updateMetrics(calories: 40)
        #expect(c.remainingEstimate() == DurationEstimate(seconds: 360, isEstimate: true))
    }

    @Test func capWithoutLoop() {
        var capped = engine(Presets.forTime(cap: 600, prepare: 0))
        capped.advance(by: 30)
        // Open step guess (60 − 30 = 30 s) is shorter than the cap: an estimate.
        #expect(capped.remainingEstimate() == DurationEstimate(seconds: 30, isEstimate: true))
        capped.advance(by: 540)
        // Past the guess, the cap is the honest bound.
        #expect(capped.remainingEstimate() == DurationEstimate(seconds: 0, isEstimate: true))

        var amrapCap = engine(ProgramSnapshot(blocks: [IntervalBlock(steps: [IntervalStep(kind: .work, end: .time(1200))])],
                                              workoutEnd: .target(.time(300))))
        amrapCap.advance(by: 100)
        #expect(amrapCap.remainingEstimate() == DurationEstimate(seconds: 200, isEstimate: false))

        // Timed pass shorter than the distance cap: ends on time unless the distance comes first.
        let distanceCap = engine(ProgramSnapshot(blocks: [IntervalBlock(steps: [IntervalStep(kind: .work, end: .time(300))])],
                                                 workoutEnd: .target(.distance(meters: 5000))))
        #expect(distanceCap.remainingEstimate() == DurationEstimate(seconds: 300, isEstimate: true))
    }
}
