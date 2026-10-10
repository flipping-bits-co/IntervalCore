import Foundation
import Testing
@testable import IntervalCore

/// Loop-until-target (RowUp2 `loopOnTarget` + `TargetManager`) and metric-ended steps.
struct LoopAndTargetTests {

    // MARK: - Ported loop behaviour

    @Test func loopsBackToFirstLoopBlock() {
        var engine = makeEngine([
            block(step(.warmup, .time(5))),
            block(work(10), rest(5), loops: true),
            block(step(.cooldown, .time(3)), loops: true),
        ], end: .target(.distance(meters: 5000)))

        engine.tickSeconds(5 + 15)
        #expect(engine.kind == .cooldown)
        let events = engine.tickSeconds(3)

        #expect(!engine.isComplete)
        #expect(engine.currentIndex == 1)
        #expect(engine.kind == .work)
        #expect(engine.stepRemaining == 10)
        #expect(engine.loopIteration == 2)
        #expect(events.contains(.loopStarted(iteration: 2)))
    }

    @Test func noLoopBlocksCompletesAtEnd() {
        var engine = makeEngine([
            block(step(.warmup, .time(5))),
            block(work(10), rest(5)),
        ], end: .target(.distance(meters: 5000)))
        engine.tickSeconds(20)
        #expect(engine.isComplete)
        #expect(engine.completionReason == .finished)
    }

    @Test func loopIgnoredWithoutTarget() {
        var engine = makeEngine([block(work(10), rest(5), skipLastRest: false, loops: true)])
        engine.tickSeconds(15)
        #expect(engine.isComplete)
        #expect(!engine.isLooping)
    }

    @Test func keepsLoopingUntilTarget() {
        var engine = makeEngine(
            [block(work(5), rest(2), loops: true)],
            end: .target(.calories(100))
        )
        engine.tickSeconds(21)
        #expect(!engine.isComplete)
        #expect(engine.loopIteration == 4)
        #expect(engine.isLooping)
        #expect(engine.nextStep?.kind == .rest)
    }

    @Test func nextStepWrapsWhileLooping() {
        var engine = makeEngine([block(work(5), rest(2), loops: true)], end: .target(.calories(100)))
        engine.tickSeconds(5)
        #expect(engine.kind == .rest)
        #expect(engine.nextStep?.index == 0)
    }

    @Test func allBlocksLoopingWrapToIndexZero() {
        var engine = makeEngine([
            block(work(5), rest(5), loops: true),
            block(work(5), rest(5), loops: true),
        ], end: .target(.distance(meters: 1000)))
        engine.tickSeconds(20)
        #expect(engine.currentIndex == 0)
        #expect(!engine.isComplete)
    }

    @Test func recordsCarryLoopIteration() {
        var engine = makeEngine([block(work(5), rest(5), loops: true)], end: .target(.time(25)))
        engine.tickSeconds(25)
        #expect(engine.records.map(\.loopIteration) == [1, 1, 2, 2, 3])
    }

    // MARK: - Target reached

    @Test func distanceTargetEndsImmediatelyWithoutPostLoop() {
        var engine = makeEngine(
            [block(step(.warmup, .time(5))), block(work(60), rest(30), loops: true)],
            end: .target(.distance(meters: 2000))
        )
        engine.tickSeconds(5 + 90 + 20)
        #expect(engine.updateMetrics(distance: 1999).isEmpty)
        #expect(engine.targetProgress == 0.9995)
        let events = engine.updateMetrics(distance: 2000)
        #expect(events == [.targetReached, .completed(reason: .targetReached)])
        #expect(engine.completionReason == .targetReached)
        #expect(engine.records.last?.endReason == .targetReached)
        #expect(engine.targetProgress == 1)
    }

    @Test func targetJumpsToCooldownAfterLoop() {
        var engine = makeEngine([
            block(step(.warmup, .time(5))),
            block(work(60), rest(30), loops: true),
            block(step(.cooldown, .time(120))),
        ], end: .target(.calories(50)))

        engine.tickSeconds(5 + 30)
        let events = engine.updateMetrics(calories: 50)
        #expect(events == [.targetReached, .stepStarted(index: 3, reason: .targetReached)])
        #expect(engine.kind == .cooldown)
        #expect(!engine.isLooping)

        engine.tickSeconds(120)
        #expect(engine.isComplete)
        #expect(engine.completionReason == .finished)
    }

    @Test func targetDuringWarmupSkipsLoopEntirely() {
        var engine = makeEngine([
            block(step(.warmup, .time(60))),
            block(work(60), rest(30), loops: true),
            block(step(.cooldown, .time(60))),
        ], end: .target(.distance(meters: 100)))
        engine.tickSeconds(10)
        engine.updateMetrics(distance: 150)
        #expect(engine.kind == .cooldown)
    }

    @Test func targetDuringCooldownChangesNothing() {
        var engine = makeEngine([
            block(work(10), loops: true),
            block(step(.cooldown, .time(60))),
        ], end: .target(.distance(meters: 100)))
        engine.updateMetrics(distance: 100)
        #expect(engine.kind == .cooldown)
        engine.tickSeconds(5)
        #expect(engine.updateMetrics(distance: 500).isEmpty)
        #expect(engine.kind == .cooldown)
    }

    @Test func timeTargetCapsMidStep() {
        var engine = makeEngine([block(work(60), rest(30), loops: true)], end: .target(.time(100)))
        let events = engine.advance(by: 500)
        #expect(events.contains(.targetReached))
        #expect(events.completed == .targetReached)
        #expect(engine.totalElapsed == 100)
        #expect(engine.records.last?.duration == 10)
    }

    @Test func timeTargetHandsLeftoverToCooldown() {
        var engine = makeEngine([
            block(work(60), rest(30), loops: true),
            block(step(.cooldown, .time(60))),
        ], end: .target(.time(100)))
        engine.advance(by: 110)
        #expect(engine.kind == .cooldown)
        #expect(engine.stepElapsed == 10)
        #expect(engine.totalElapsed == 110)
    }

    @Test func forTimeCapEndsOpenStep() {
        var engine = IntervalEngine(program: Presets.forTime(cap: 600, prepare: 0))
        engine.start(at: .testEpoch)
        #expect(engine.targetProgress == 0)
        engine.tickSeconds(300)
        #expect(engine.targetProgress == 0.5)
        engine.tickSeconds(300)
        #expect(engine.completionReason == .targetReached)
    }

    @Test func forTimeFinishedBeforeCap() {
        var engine = IntervalEngine(program: Presets.forTime(cap: 600, prepare: 0))
        engine.start(at: .testEpoch)
        engine.tickSeconds(250)
        #expect(engine.next().completed == .finished)
    }

    @Test func calorieTargetProgress() {
        var engine = makeEngine([block(work(60), loops: true)], end: .target(.calories(200)))
        engine.updateMetrics(calories: 50)
        #expect(engine.targetProgress == 0.25)
    }

    @Test func noTargetHasNoProgress() {
        let engine = makeIntervalEngine(work: 10, rest: 5, repeats: 1)
        #expect(engine.targetProgress == nil)
    }

    // MARK: - previous across loop

    @Test func previousWrapsBackIntoPriorIteration() {
        var engine = makeEngine([block(work(5), rest(2), loops: true)], end: .target(.calories(100)))
        engine.tickSeconds(7)
        #expect(engine.loopIteration == 2)
        #expect(engine.currentIndex == 0)
        engine.previous()
        #expect(engine.loopIteration == 1)
        #expect(engine.currentIndex == 1)
    }

    // MARK: - Metric-ended steps

    @Test func distanceStepUsesStepDelta() {
        var engine = makeEngine([block(step(.work, .distance(meters: 500)), rest(60), repeats: 2)])
        engine.updateMetrics(distance: 300)
        #expect(engine.stepProgress == 0.6)
        let events = engine.updateMetrics(distance: 520)
        #expect(events == [.stepStarted(index: 1, reason: .metricReached)])
        #expect(engine.records.last?.distance == 520)

        engine.tickSeconds(60)
        #expect(engine.kind == .work)
        #expect(engine.stepDistance == 0)
        engine.updateMetrics(distance: 900)
        #expect(engine.kind == .work)
        engine.updateMetrics(distance: 1020)
        #expect(engine.isComplete)
    }

    @Test func calorieStepEnds() {
        var engine = makeEngine([block(step(.work, .calories(15)), rest(30), skipLastRest: false)])
        engine.updateMetrics(calories: 5)
        #expect(abs((engine.stepProgress ?? 0) - 1.0 / 3) < 1e-9)
        engine.updateMetrics(calories: 15)
        #expect(engine.kind == .rest)
        #expect(engine.records.last?.calories == 15)
    }

    @Test func metricStepCountsUpTime() {
        var engine = makeEngine([block(step(.work, .distance(meters: 500)))])
        engine.tickSeconds(95)
        #expect(engine.stepElapsed == 95)
        #expect(engine.stepRemaining == nil)
    }

    @Test func metricsStoredButIgnoredWhilePaused() {
        var engine = makeEngine([block(step(.work, .distance(meters: 500)), rest(10), skipLastRest: false)])
        engine.pause()
        #expect(engine.updateMetrics(distance: 600).isEmpty)
        #expect(engine.totalDistance == 600)
        #expect(engine.kind == .work)
    }

    @Test func zeroTargetStepEndsOnFirstUpdate() {
        var engine = makeEngine([block(step(.work, .distance(meters: 0)), rest(10), skipLastRest: false)])
        #expect(engine.stepProgress == 1)
        engine.updateMetrics(distance: 0)
        #expect(engine.kind == .rest)
    }
}
