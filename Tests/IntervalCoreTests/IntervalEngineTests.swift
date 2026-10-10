import Foundation
import Testing
@testable import IntervalCore

/// Ported from RowUp2 `IntervalManagerTests` (row → work), plus new engine behaviour.
struct IntervalEngineTests {

    // MARK: - Ported: time advance

    @Test func initialState() {
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(120), rest(60), repeats: 3)]))
        #expect(engine.status == .ready)
        #expect(engine.currentStep?.kind == .work)

        let events = engine.start(at: .testEpoch)
        #expect(events == [.stepStarted(index: 0, reason: .start)])
        #expect(engine.status == .running)
        #expect(engine.round == 1)
        #expect(engine.stepElapsed == 0)
        #expect(engine.stepRemaining == 120)
        #expect(engine.isComplete == false)
    }

    @Test func tickAdvancesElapsed() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 3)
        engine.tickSeconds(10)
        #expect(engine.stepElapsed == 10)
        #expect(engine.stepRemaining == 110)
        #expect(engine.totalElapsed == 10)
        #expect(engine.kind == .work)
    }

    @Test func workToRestTransition() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 3)
        let events = engine.tickSeconds(120)
        #expect(engine.kind == .rest)
        #expect(engine.round == 1)
        #expect(engine.stepElapsed == 0)
        #expect(engine.stepRemaining == 60)
        #expect(events.startedIndices == [1])
        #expect(events.startReasons == [.timeElapsed])
    }

    @Test func restToNextWorkTransition() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 3)
        let events = engine.tickSeconds(180)
        #expect(engine.kind == .work)
        #expect(engine.round == 2)
        #expect(engine.stepRemaining == 120)
        #expect(events.startedIndices == [1, 2])
    }

    @Test func fullCompletionThreeRounds() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 3)
        let events = engine.tickSeconds(45)
        #expect(engine.isComplete)
        #expect(engine.completionReason == .finished)
        // Same six transitions as RowUp2: five step starts + completion.
        #expect(events.startedIndices.count == 5)
        #expect(events.completed == .finished)
        #expect(engine.totalElapsed == 45)
    }

    @Test func singleRoundCompletion() {
        var engine = makeIntervalEngine(work: 60, rest: 30, repeats: 1)
        engine.tickSeconds(90)
        #expect(engine.isComplete)
        #expect(engine.currentStep == nil)
    }

    /// The design plan's "time advance across multiple boundaries in one tick".
    @Test func largeDeltaCrossesOneBoundary() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 2)
        engine.advance(by: 130)
        #expect(engine.kind == .rest)
        #expect(engine.stepElapsed == 10)
        #expect(engine.stepRemaining == 50)
    }

    @Test func largeDeltaCrossesManyBoundaries() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 4)
        let events = engine.advance(by: 37)
        // 0-10 w1, 10-15 r1, 15-25 w2, 25-30 r2, 30-40 w3 → 7 s into round 3 work.
        #expect(events.startedIndices == [1, 2, 3, 4])
        #expect(engine.kind == .work)
        #expect(engine.round == 3)
        #expect(engine.stepElapsed == 7)
        #expect(engine.totalElapsed == 37)
    }

    @Test func largeDeltaPastEndCompletesWithoutOvercounting() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 2)
        let events = engine.advance(by: 1000)
        #expect(events.completed == .finished)
        #expect(engine.totalElapsed == 30)
    }

    @Test func fractionalTicksLandOnBoundaries() {
        var engine = makeIntervalEngine(work: 1, rest: 1, repeats: 3)
        for _ in 0..<60 { engine.advance(by: 0.1) }
        #expect(engine.isComplete)
        #expect(abs(engine.totalElapsed - 6) < 1e-6)
        #expect(engine.records.count == 6)
    }

    @Test func tickAfterCompleteIsNoOp() {
        var engine = makeIntervalEngine(work: 5, rest: 5, repeats: 1)
        engine.tickSeconds(10)
        #expect(engine.isComplete)
        let before = engine
        #expect(engine.advance(by: 100).isEmpty)
        #expect(engine == before)
    }

    @Test func advanceBeforeStartIsNoOp() {
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(10))]))
        #expect(engine.advance(by: 5).isEmpty)
        #expect(engine.totalElapsed == 0)
        #expect(engine.start(at: .testEpoch).isEmpty == false)
        #expect(engine.start(at: .testEpoch).isEmpty)
    }

    @Test func zeroOrNegativeDeltaIsNoOp() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 1)
        #expect(engine.advance(by: 0).isEmpty)
        #expect(engine.advance(by: -3).isEmpty)
        #expect(engine.totalElapsed == 0)
    }

    // MARK: - Ported: multi-block

    @Test func warmupOnlyCompletes() {
        var engine = makeEngine([block(step(.warmup, .time(10)))])
        engine.tickSeconds(10)
        #expect(engine.isComplete)
    }

    @Test func multiBlockWarmupIntervalCooldown() {
        var engine = makeEngine([
            block(step(.warmup, .time(5))),
            block(work(10), rest(5), repeats: 2, skipLastRest: false),
            block(step(.cooldown, .time(3))),
        ])

        engine.tickSeconds(5)
        #expect(engine.currentStep?.blockIndex == 1)
        #expect(engine.kind == .work)

        engine.tickSeconds(10)
        #expect(engine.kind == .rest)

        engine.tickSeconds(5)
        #expect(engine.round == 2)
        #expect(engine.kind == .work)

        engine.tickSeconds(15)
        #expect(engine.currentStep?.blockIndex == 2)
        #expect(engine.kind == .cooldown)

        engine.tickSeconds(3)
        #expect(engine.isComplete)
    }

    @Test func currentIndexMatchesRowUp2FlatPhaseIndex() {
        var engine = makeIntervalEngine(work: 5, rest: 5, repeats: 2)
        #expect(engine.currentIndex == 0)
        engine.tickSeconds(5)
        #expect(engine.currentIndex == 1)
        engine.tickSeconds(5)
        #expect(engine.currentIndex == 2)
        engine.tickSeconds(5)
        #expect(engine.currentIndex == 3)
    }

    @Test func nextStepLooksAhead() {
        var engine = makeIntervalEngine(work: 5, rest: 3, repeats: 2)
        #expect(engine.nextStep?.kind == .rest)
        engine.tickSeconds(13)
        #expect(engine.currentIndex == 3)
        #expect(engine.nextStep == nil)
    }

    // MARK: - Ported: skip

    @Test func skipDuringWorkGoesToRest() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 3)
        engine.advance(by: 5)
        let events = engine.skip()
        #expect(engine.kind == .rest)
        #expect(engine.round == 1)
        #expect(engine.stepRemaining == 60)
        #expect(events == [.stepStarted(index: 1, reason: .skipped)])
        #expect(engine.records.last?.endReason == .skipped)
        #expect(engine.records.last?.duration == 5)
    }

    @Test func skipDuringRestGoesToNextWork() {
        var engine = makeIntervalEngine(work: 120, rest: 60, repeats: 3)
        engine.tickSeconds(120)
        engine.skip()
        #expect(engine.kind == .work)
        #expect(engine.round == 2)
        #expect(engine.stepRemaining == 120)
    }

    @Test func skipFinalStepCompletes() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 1)
        engine.tickSeconds(10)
        #expect(engine.skip().completed == .finished)
        #expect(engine.isComplete)
    }

    @Test func skipAdvancesToNextBlock() {
        var engine = makeEngine([block(step(.warmup, .time(30))), block(work(10), rest(5), repeats: 2)])
        engine.advance(by: 5)
        engine.skip()
        #expect(engine.currentStep?.blockIndex == 1)
        #expect(engine.kind == .work)
    }

    @Test func skipMultipleStepsInSequence() {
        var engine = makeIntervalEngine(work: 60, rest: 30, repeats: 3)
        engine.advance(by: 1)
        var started: [Int] = []
        for _ in 0..<4 { started += engine.skip().startedIndices }
        #expect(started == [1, 2, 3, 4])
        #expect(engine.round == 3)
        #expect(engine.kind == .work)
    }

    @Test func skipAfterCompleteIsNoOp() {
        var engine = makeIntervalEngine(work: 5, rest: 5, repeats: 1)
        engine.tickSeconds(10)
        #expect(engine.skip().isEmpty)
        #expect(engine.next().isEmpty)
        #expect(engine.previous().isEmpty)
        #expect(engine.restartStep().isEmpty)
        #expect(engine.logRound().isEmpty)
    }

    // MARK: - previous / restart

    @Test func previousGoesBackOneStep() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 2)
        engine.tickSeconds(12)
        #expect(engine.kind == .rest)
        let events = engine.previous()
        #expect(events == [.stepStarted(index: 0, reason: .previous)])
        #expect(engine.kind == .work)
        #expect(engine.stepElapsed == 0)
        #expect(engine.stepRemaining == 10)
        #expect(engine.totalElapsed == 12)
        #expect(engine.records.last?.endReason == .previous)
    }

    @Test func previousOnFirstStepRestartsIt() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 2)
        engine.tickSeconds(4)
        engine.previous()
        #expect(engine.currentIndex == 0)
        #expect(engine.stepElapsed == 0)
    }

    @Test func restartStepResetsCurrentStep() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 2)
        engine.tickSeconds(13)
        let events = engine.restartStep()
        #expect(events == [.stepStarted(index: 1, reason: .restarted)])
        #expect(engine.stepElapsed == 0)
        #expect(engine.stepRemaining == 5)
    }

    // MARK: - reps / open

    @Test func repsStepWaitsForDone() {
        var engine = makeEngine([block(step(.work, .reps(15)), rest(10), skipLastRest: false)])
        let events = engine.tickSeconds(300)
        #expect(events.isEmpty)
        #expect(engine.kind == .work)
        #expect(engine.stepElapsed == 300)
        #expect(engine.stepRemaining == nil)
        #expect(engine.stepProgress == nil)

        #expect(engine.next() == [.stepStarted(index: 1, reason: .userAdvanced)])
        #expect(engine.records.last?.endReason == .userAdvanced)
        #expect(engine.records.last?.duration == 300)
    }

    @Test func openStepNextCompletes() {
        var engine = makeEngine([block(step(.work, .open))])
        engine.tickSeconds(42)
        #expect(engine.next() == [.completed(reason: .finished)])
        #expect(engine.totalElapsed == 42)
    }

    @Test func logRoundCounts() {
        var engine = makeEngine([block(work(600))])
        #expect(engine.logRound() == [.roundLogged(count: 1)])
        #expect(engine.logRound() == [.roundLogged(count: 2)])
        #expect(engine.loggedRounds == 2)
    }

    // MARK: - Pause / resume / clock

    @Test func tickAtUsesWallClockDeltas() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(30), rest(10), repeats: 2)]))
        engine.start(at: t0)
        engine.tick(at: t0.addingTimeInterval(12.5))
        #expect(engine.stepElapsed == 12.5)
        engine.tick(at: t0.addingTimeInterval(35))
        #expect(engine.kind == .rest)
        #expect(engine.stepElapsed == 5)
    }

    @Test func firstTickAfterStartCounts() {
        var engine = makeIntervalEngine(work: 30, rest: 10, repeats: 1)
        engine.tick(at: Date.testEpoch.addingTimeInterval(3))
        #expect(engine.totalElapsed == 3)
    }

    @Test func firstTickAfterResumeCounts() {
        let t0 = Date.testEpoch
        var engine = makeIntervalEngine(work: 30, rest: 10, repeats: 1)
        engine.pause(at: t0.addingTimeInterval(2))
        engine.resume(at: t0.addingTimeInterval(50))
        engine.tick(at: t0.addingTimeInterval(53))
        #expect(engine.totalElapsed == 5)
    }

    @Test func pauseExcludesPausedTime() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(30))]))
        engine.start(at: t0)
        #expect(engine.pause(at: t0.addingTimeInterval(10)) == [.paused])
        #expect(engine.isPaused)
        #expect(engine.tick(at: t0.addingTimeInterval(100)).isEmpty)
        #expect(engine.advance(by: 50).isEmpty)
        #expect(engine.resume(at: t0.addingTimeInterval(200)) == [.resumed])
        engine.tick(at: t0.addingTimeInterval(205))
        #expect(engine.totalElapsed == 15)
        #expect(engine.stepRemaining == 15)
    }

    @Test func pauseAcrossBoundaryReportsTransitionsFirst() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(5), rest(5), repeats: 2)]))
        engine.start(at: t0)
        let events = engine.pause(at: t0.addingTimeInterval(6))
        #expect(events.startedIndices == [1])
        #expect(events.last == .paused)
    }

    @Test func pauseThatCompletesDoesNotPause() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(5))]))
        engine.start(at: t0)
        let events = engine.pause(at: t0.addingTimeInterval(9))
        #expect(events.completed == .finished)
        #expect(!events.contains(.paused))
        #expect(engine.isComplete)
    }

    @Test func pauseResumeGuards() {
        var engine = makeIntervalEngine(work: 5, rest: 5, repeats: 1)
        #expect(engine.resume(at: .testEpoch).isEmpty)
        #expect(engine.pause() == [.paused])
        #expect(engine.pause().isEmpty)
        #expect(engine.resume(at: .testEpoch) == [.resumed])
    }

    @Test func skipWhilePausedStaysPaused() {
        var engine = makeIntervalEngine(work: 30, rest: 10, repeats: 2)
        engine.pause()
        engine.skip()
        #expect(engine.isPaused)
        #expect(engine.kind == .rest)
    }

    @Test func finishEndsEarlyAndRecordsPartialStep() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(30), rest(10), repeats: 3)]))
        engine.start(at: t0)
        let events = engine.finish(at: t0.addingTimeInterval(45))
        #expect(events.startedIndices == [1, 2])
        #expect(events.completed == .stopped)
        #expect(engine.completionReason == .stopped)
        #expect(engine.records.map(\.duration) == [30, 10, 5])
        #expect(engine.finish().isEmpty)
    }

    @Test func finishAfterNaturalEndReturnsCompletionOnly() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(5))]))
        engine.start(at: t0)
        #expect(engine.isRunning)
        let events = engine.finish(at: t0.addingTimeInterval(10))
        #expect(events.completed == .finished)
        #expect(engine.completionReason == .finished)
        #expect(engine.records.count == 1)
        #expect(!engine.isWaitingForHeartRate)
    }

    @Test func finishWhilePausedIgnoresClock() {
        var engine = makeIntervalEngine(work: 30, rest: 10, repeats: 1)
        engine.advance(by: 3)
        engine.pause()
        #expect(engine.finish(at: Date()).completed == .stopped)
        #expect(engine.totalElapsed == 3)
    }

    @Test func finishBeforeStartIsNoOp() {
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(30))]))
        #expect(engine.finish().isEmpty)
        #expect(engine.status == .ready)
    }

    @Test func emptyTimelineCompletesOnStart() {
        var engine = IntervalEngine(timeline: Timeline(steps: []))
        #expect(engine.start(at: .testEpoch) == [.completed(reason: .finished)])
        #expect(engine.currentStep == nil)
        #expect(engine.nextStep == nil)
        #expect(engine.stepProgress == nil)
        #expect(engine.stepRemaining == nil)
    }

    @Test func zeroLengthStepsAreSkippedThrough() {
        var engine = makeEngine([block(work(0), work(5), work(0))])
        let events = engine.advance(by: 1)
        #expect(events.startedIndices == [1])
        engine.advance(by: 10)
        #expect(engine.isComplete)
    }

    @Test func zeroLengthLoopDoesNotSpin() {
        var engine = makeEngine([block(work(0), rest(0), loops: true)], end: .target(.distance(meters: 1000)))
        let events = engine.advance(by: 1)
        #expect(events.completed == .finished)
    }

    // MARK: - Cues

    @Test func countdownCuesBeforeStepEnds() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 1)
        let events = engine.tickSeconds(10)
        let cues = events.compactMap { if case .countdown(let i, let n) = $0 { [i, n] } else { nil } }
        #expect(cues == [[0, 3], [0, 2], [0, 1]])
        // The "1" cue comes before the transition.
        #expect(events.firstIndex(of: .countdown(index: 0, secondsRemaining: 1))! < events.firstIndex(of: .stepStarted(index: 1, reason: .timeElapsed))!)
    }

    @Test func countdownCuesInOneLargeTick() {
        var engine = makeIntervalEngine(work: 10, rest: 5, repeats: 1)
        let events = engine.advance(by: 11)
        let cues = events.filter { if case .countdown = $0 { true } else { false } }
        #expect(cues.count == 3)
    }

    @Test func shortStepsOnlyGetCuesThatFit() {
        var engine = makeEngine([block(work(2), rest(5))])
        let events = engine.tickSeconds(2)
        #expect(events.contains(.countdown(index: 0, secondsRemaining: 1)))
        #expect(!events.contains(.countdown(index: 0, secondsRemaining: 2)))
    }

    @Test func halfwayCueOnlyForMinuteOrLonger() {
        var engine = makeEngine([block(work(60), work(59))])
        let first = engine.tickSeconds(60)
        #expect(first.filter { $0 == .halfway(index: 0) }.count == 1)
        let second = engine.tickSeconds(59)
        #expect(!second.contains(.halfway(index: 1)))
    }

    /// G1 regression: floating-point drift used to land a tick just under a mark (within ε),
    /// firing the cue, and the next tick fired it again.
    @Test(arguments: [1.0 / 60.0, 1.0 / 30.0, 0.05, 0.1, 0.3, 0.7, 1.0])
    func cuesFireOncePerMarkUnderFractionalTicks(dt: Double) {
        var engine = makeEngine([block(work(60), rest(40), repeats: 3)])
        var events: [EngineEvent] = []
        var n = 0
        while !engine.isComplete && n < 200_000 { events += engine.advance(by: dt); n += 1 }
        var counts: [String: Int] = [:]
        for e in events {
            switch e {
            case .countdown(let i, let s): counts["c\(i)-\(s)", default: 0] += 1
            case .halfway(let i): counts["h\(i)", default: 0] += 1
            default: break
            }
        }
        #expect(counts.filter { $0.value > 1 }.isEmpty, "dt=\(dt)")
        #expect(counts.count == 5 * 3 + 3)   // 5 steps × 3-2-1, 3 work steps ≥ 60 s get halfway
    }

    @Test func backwardsClockIsIgnored() {
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
        var engine = IntervalEngine(timeline: TimelineCompiler.compile([block(work(60))]))
        engine.start(at: t0)
        engine.tick(at: t0.addingTimeInterval(10))
        #expect(engine.tick(at: t0.addingTimeInterval(4)).isEmpty)
        engine.tick(at: t0.addingTimeInterval(12))
        #expect(engine.totalElapsed == 12)
    }

    @Test func untimedStepsGetNoCues() {
        var engine = makeEngine([block(step(.work, .open))])
        let events = engine.tickSeconds(120)
        #expect(events.isEmpty)
    }

    // MARK: - Records

    @Test func recordsCaptureEveryStep() {
        var engine = makeEngine([
            block(step(.warmup, .time(5))),
            block(work(10), rest(5), repeats: 2),
        ])
        engine.tickSeconds(30)
        #expect(engine.isComplete)
        #expect(engine.records.map(\.kind) == [.warmup, .work, .rest, .work])
        #expect(engine.records.map(\.startOffset) == [0, 5, 15, 20])
        #expect(engine.records.map(\.duration) == [5, 10, 5, 10])
        #expect(engine.records.map(\.round) == [1, 1, 1, 2])
        #expect(engine.records.allSatisfy { $0.endReason == .timeElapsed && $0.loopIteration == 1 })
    }

    @Test func stepProgressForTimedStep() {
        var engine = makeIntervalEngine(work: 40, rest: 10, repeats: 1)
        engine.tickSeconds(10)
        #expect(engine.stepProgress == 0.25)
        #expect(engine.stepLimit == 40)
    }

    @Test func engineRoundTripsThroughJSON() throws {
        var engine = makeIntervalEngine(work: 40, rest: 10, repeats: 2)
        engine.tickSeconds(45)
        engine.updateHeartRate(130)
        let data = try JSONEncoder().encode(engine)
        var restored = try JSONDecoder().decode(IntervalEngine.self, from: data)
        #expect(restored == engine)
        restored.tickSeconds(5)
        engine.tickSeconds(5)
        #expect(restored == engine)
    }

    @Test func initFromProgram() {
        var engine = IntervalEngine(program: Presets.tabata())
        engine.start(at: .testEpoch)
        engine.advance(by: 10 + 8 * 30 - 10)
        #expect(engine.isComplete)
    }
}
