import Foundation
import Testing
@testable import IntervalCore

/// Ported from RowUp2 `HRTriggeredIntervalTests`. RowUp2's global ceiling/floor maps to
/// `.heartRateAbove` on work and `.heartRateBelow` on rest, with the old phase duration
/// as `maxWait`.
private func makeHREngine(
    workWait: TimeInterval = 120,
    restWait: TimeInterval = 60,
    repeats: Int = 3,
    ceiling: Int = 145,
    floor: Int = 120
) -> IntervalEngine {
    makeEngine([block(
        step(.work, .heartRateAbove(bpm: ceiling, maxWait: workWait)),
        step(.rest, .heartRateBelow(bpm: floor, maxWait: restWait)),
        repeats: repeats,
        skipLastRest: false
    )])
}

struct HeartRateTests {

    @Test func initialState() {
        let engine = makeHREngine()
        #expect(engine.isWaitingForHeartRate)
        #expect(engine.kind == .work)
        #expect(engine.heartRate == nil)
        #expect(engine.stepLimit == 120)
    }

    @Test func aboveCeilingEndsWork() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        #expect(engine.updateHeartRate(146) == [.stepStarted(index: 1, reason: .heartRateReached)])
        #expect(engine.kind == .rest)
        #expect(engine.records.last?.endReason == .heartRateReached)
    }

    @Test func atCeilingEndsWork() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        engine.updateHeartRate(145)
        #expect(engine.kind == .rest)
    }

    @Test func belowCeilingStaysInWork() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        #expect(engine.updateHeartRate(140).isEmpty)
        #expect(engine.kind == .work)
        #expect(engine.heartRate == 140)
    }

    @Test func belowFloorEndsRest() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        engine.updateHeartRate(150)
        engine.advance(by: 1)
        engine.updateHeartRate(119)
        #expect(engine.kind == .work)
        #expect(engine.round == 2)
    }

    @Test func atFloorEndsRest() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        engine.updateHeartRate(150)
        engine.advance(by: 1)
        engine.updateHeartRate(120)
        #expect(engine.kind == .work)
    }

    @Test func aboveFloorStaysInRest() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        engine.updateHeartRate(150)
        engine.advance(by: 1)
        engine.updateHeartRate(130)
        #expect(engine.kind == .rest)
    }

    @Test func ignoredAtZeroElapsed() {
        var engine = makeHREngine()
        #expect(engine.updateHeartRate(200).isEmpty)
        #expect(engine.kind == .work)
        #expect(engine.heartRate == 200)
    }

    @Test func ignoredOnTimedSteps() {
        var engine = makeEngine([
            block(step(.warmup, .time(30))),
            block(step(.work, .heartRateAbove(bpm: 145, maxWait: 60))),
        ])
        engine.advance(by: 1)
        engine.updateHeartRate(200)
        #expect(engine.kind == .warmup)
        #expect(!engine.isWaitingForHeartRate)
    }

    @Test func ignoredWhenPaused() {
        var engine = makeHREngine()
        engine.advance(by: 1)
        engine.pause()
        #expect(engine.updateHeartRate(200).isEmpty)
        #expect(engine.kind == .work)
    }

    @Test func maxWaitFallsBackToTime() {
        var engine = makeHREngine(workWait: 10)
        let events = engine.tickSeconds(10)
        #expect(engine.kind == .rest)
        #expect(events.startReasons == [.heartRateTimeout])
        #expect(engine.records.last?.endReason == .heartRateTimeout)
        // No 3-2-1 for HR steps: the end depends on HR, not the clock.
        #expect(!events.contains { if case .countdown = $0 { true } else { false } })
    }

    @Test func noMaxWaitWaitsForever() {
        var engine = makeEngine([block(step(.rest, .heartRateBelow(bpm: 100, maxWait: 0)), work(10))])
        engine.tickSeconds(3600)
        #expect(engine.kind == .rest)
        #expect(engine.stepRemaining == nil)
        #expect(engine.stepProgress == nil)
        engine.updateHeartRate(99)
        #expect(engine.kind == .work)
    }

    @Test func stepProgressTracksMaxWait() {
        var engine = makeHREngine(workWait: 40)
        engine.tickSeconds(10)
        #expect(engine.stepProgress == 0.25)
        #expect(engine.stepRemaining == 30)
    }

    @Test func fullRoundCycleViaHR() {
        var engine = makeHREngine(repeats: 2)
        var started: [Int] = []
        var completion: CompletionReason?
        for bpm in [150.0, 115, 150, 115] {
            engine.advance(by: 1)
            let events = engine.updateHeartRate(bpm)
            started += events.startedIndices
            completion = completion ?? events.completed
        }
        #expect(started == [1, 2, 3])
        #expect(completion == .finished)
        #expect(engine.isComplete)
    }

    @Test func afterCompleteIsNoOp() {
        var engine = makeHREngine(repeats: 1)
        engine.advance(by: 1)
        engine.updateHeartRate(150)
        engine.advance(by: 1)
        engine.updateHeartRate(100)
        #expect(engine.isComplete)
        #expect(engine.updateHeartRate(200).isEmpty)
    }

    @Test func roundIncrementsOnHRTransitions() {
        var engine = makeHREngine(repeats: 3)
        #expect(engine.round == 1)
        engine.advance(by: 1); engine.updateHeartRate(150)
        #expect(engine.round == 1)
        engine.advance(by: 1); engine.updateHeartRate(110)
        #expect(engine.round == 2)
        engine.advance(by: 1); engine.updateHeartRate(150)
        engine.advance(by: 1); engine.updateHeartRate(110)
        #expect(engine.round == 3)
    }
}
