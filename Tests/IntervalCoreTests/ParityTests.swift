import Foundation
import Testing
@testable import IntervalCore

/// Parity: RowUp2 `WorkoutSegment` fixtures run through RowUp2's `IntervalManager`
/// (copied verbatim into Fixtures/) and through `TimelineCompiler` + `IntervalEngine`
/// must produce the same step sequence with the same durations.

// MARK: - Adapter (RowUp2 segment → IntervalBlock)

/// How a RowUp2 config maps onto the new model. RowUp2 always runs the final rest, so
/// `skipLastRest` is off. In HR mode, RowUp2's global ceiling/floor become HR end
/// conditions on interval steps, with the old phase durations as the `maxWait` fallback.
private func blocks(from segments: [LegacyWorkoutSegment], hr: (ceiling: Int, floor: Int)? = nil) -> [IntervalBlock] {
    segments.map { seg in
        let rowKind: StepKind = switch seg.type {
        case .warmup: .warmup
        case .interval: .work
        case .cooldown: .cooldown
        }
        let rowEnd: EndCondition
        switch seg.rowTrigger {
        case .time:
            if let hr, seg.type == .interval {
                rowEnd = .heartRateAbove(bpm: hr.ceiling, maxWait: seg.rowDuration)
            } else {
                rowEnd = .time(seg.rowDuration)
            }
        case .distance:
            rowEnd = .distance(meters: seg.rowTargetValue)
        case .strokes:
            Issue.record("strokes have no equivalent in IntervalCore")
            rowEnd = .open
        }
        var steps = [IntervalStep(kind: rowKind, end: rowEnd)]
        if seg.type == .interval && seg.restDuration > 0 {
            let restEnd: EndCondition = hr.map { .heartRateBelow(bpm: $0.floor, maxWait: seg.restDuration) }
                ?? .time(seg.restDuration)
            steps.append(IntervalStep(kind: .rest, end: restEnd))
        }
        return IntervalBlock(steps: steps, repeats: seg.repeats, skipLastRest: false, loopsUntilTarget: seg.loopOnTarget)
    }
}

// MARK: - Runner

private struct Position: Hashable, CustomStringConvertible {
    var block: Int
    var round: Int
    var kind: StepKind
    var description: String { "b\(block) r\(round) \(kind.rawValue)" }
}

private struct Run: Equatable {
    /// Consecutive (position, seconds spent there).
    var segments: [Pair] = []
    var completed = false

    struct Pair: Equatable, CustomStringConvertible {
        var position: Position
        var seconds: Int
        var description: String { "\(position)=\(seconds)s" }
    }

    mutating func record(_ position: Position) {
        if segments.last?.position == position {
            segments[segments.count - 1].seconds += 1
        } else {
            segments.append(Pair(position: position, seconds: 1))
        }
    }
}

/// Per-second inputs fed to both engines after each tick.
private struct Script {
    var metersPerSecond: Double = 0
    var heartRate: (Int) -> Double? = { _ in nil }
}

private func legacyPosition(_ mgr: LegacyIntervalManager) -> Position {
    let seg = mgr.segments[mgr.currentSegmentIndex]
    let kind: StepKind = switch (mgr.currentPhase, seg.type) {
    case (.rest, _): .rest
    case (.row, .warmup): .warmup
    case (.row, .interval): .work
    case (.row, .cooldown): .cooldown
    }
    return Position(block: mgr.currentSegmentIndex, round: mgr.currentRepeat, kind: kind)
}

private func runLegacy(_ mgr: LegacyIntervalManager, script: Script, seconds: Int) -> Run {
    var run = Run()
    for second in 0..<seconds {
        guard !mgr.isComplete else { break }
        run.record(legacyPosition(mgr))
        mgr.tick(delta: 1)
        mgr.updateMetrics(strokes: 0, distance: script.metersPerSecond * Double(second + 1))
        if let bpm = script.heartRate(second) { mgr.updateHeartRate(bpm) }
    }
    run.completed = mgr.isComplete
    return run
}

private func runEngine(_ engine: inout IntervalEngine, script: Script, seconds: Int) -> Run {
    var run = Run()
    for second in 0..<seconds {
        guard let step = engine.currentStep else { break }
        run.record(Position(block: step.blockIndex, round: step.round, kind: step.kind))
        engine.advance(by: 1)
        engine.updateMetrics(distance: script.metersPerSecond * Double(second + 1))
        if let bpm = script.heartRate(second) { engine.updateHeartRate(bpm) }
    }
    run.completed = engine.isComplete
    return run
}

private func assertParity(
    _ segments: [LegacyWorkoutSegment],
    loopUntilTarget: Bool = false,
    hr: (ceiling: Int, floor: Int)? = nil,
    script: Script = Script(),
    seconds: Int = 4 * 3600
) {
    let legacy = LegacyIntervalManager(
        segments: segments,
        hasTargetEndCondition: loopUntilTarget,
        useHRTrigger: hr != nil,
        hrCeiling: hr?.ceiling ?? 145,
        hrFloor: hr?.floor ?? 120
    )
    // The target is never reached in these runs; it only switches looping on.
    let end: WorkoutEnd = loopUntilTarget ? .target(.distance(meters: .greatestFiniteMagnitude)) : .allBlocks
    var engine = IntervalEngine(timeline: TimelineCompiler.compile(blocks(from: segments, hr: hr), workoutEnd: end))
    engine.start(at: .testEpoch)

    let expected = runLegacy(legacy, script: script, seconds: seconds)
    let actual = runEngine(&engine, script: script, seconds: seconds)
    #expect(actual.segments == expected.segments)
    #expect(actual.completed == expected.completed)
    #expect(!expected.segments.isEmpty)
}

// MARK: - Fixtures

struct ParityTests {

    @Test func singleIntervalSegment() {
        assertParity([LegacyWorkoutSegment(type: .interval, rowDuration: 120, restDuration: 60, repeats: 3)])
    }

    @Test func intervalWithoutRest() {
        assertParity([LegacyWorkoutSegment(type: .interval, rowDuration: 45, restDuration: 0, repeats: 5)])
    }

    @Test func warmupIntervalsCooldown() {
        assertParity([
            LegacyWorkoutSegment(type: .warmup, rowDuration: 600),
            LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 60, repeats: 8),
            LegacyWorkoutSegment(type: .cooldown, rowDuration: 300),
        ])
    }

    @Test func pyramidOfSegments() {
        assertParity([
            LegacyWorkoutSegment(type: .warmup, rowDuration: 300),
            LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 30, repeats: 1),
            LegacyWorkoutSegment(type: .interval, rowDuration: 120, restDuration: 60, repeats: 1),
            LegacyWorkoutSegment(type: .interval, rowDuration: 180, restDuration: 90, repeats: 1),
            LegacyWorkoutSegment(type: .interval, rowDuration: 120, restDuration: 60, repeats: 1),
            LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 30, repeats: 1),
            LegacyWorkoutSegment(type: .cooldown, rowDuration: 300),
        ])
    }

    @Test func norwegian4x4() {
        assertParity([
            LegacyWorkoutSegment(type: .warmup, rowDuration: 600),
            LegacyWorkoutSegment(type: .interval, rowDuration: 240, restDuration: 180, repeats: 4),
            LegacyWorkoutSegment(type: .cooldown, rowDuration: 300),
        ])
    }

    @Test func distanceTriggeredIntervals() {
        assertParity(
            [
                LegacyWorkoutSegment(type: .warmup, rowDuration: 300),
                LegacyWorkoutSegment(type: .interval, rowTrigger: .distance, rowDuration: 0, rowTargetValue: 500, restDuration: 90, repeats: 4),
                LegacyWorkoutSegment(type: .cooldown, rowDuration: 180),
            ],
            script: Script(metersPerSecond: 4)
        )
    }

    @Test func distanceTriggeredWarmup() {
        assertParity(
            [
                LegacyWorkoutSegment(type: .warmup, rowTrigger: .distance, rowDuration: 0, rowTargetValue: 1000),
                LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 30, repeats: 2),
            ],
            script: Script(metersPerSecond: 3.5)
        )
    }

    @Test func loopOnTargetTrailingSegments() {
        assertParity(
            [
                LegacyWorkoutSegment(type: .warmup, rowDuration: 120, loopOnTarget: false),
                LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 30, repeats: 2, loopOnTarget: true),
                LegacyWorkoutSegment(type: .interval, rowDuration: 30, restDuration: 15, repeats: 1, loopOnTarget: true),
            ],
            loopUntilTarget: true,
            seconds: 1500
        )
    }

    @Test func loopOnTargetAllSegments() {
        assertParity(
            [
                LegacyWorkoutSegment(type: .interval, rowDuration: 5, restDuration: 5, repeats: 1, loopOnTarget: true),
                LegacyWorkoutSegment(type: .interval, rowDuration: 7, restDuration: 3, repeats: 2, loopOnTarget: true),
            ],
            loopUntilTarget: true,
            seconds: 400
        )
    }

    @Test func heartRateTriggeredIntervals() {
        // HR climbs during work and falls during rest; some phases hit the
        // threshold, others fall back to maxWait.
        let pattern: [Double] = [100, 110, 125, 140, 150, 160, 150, 135, 125, 118, 110, 105]
        assertParity(
            [
                LegacyWorkoutSegment(type: .warmup, rowDuration: 20),
                LegacyWorkoutSegment(type: .interval, rowDuration: 40, restDuration: 25, repeats: 4),
                LegacyWorkoutSegment(type: .cooldown, rowDuration: 15),
            ],
            hr: (ceiling: 145, floor: 120),
            script: Script(heartRate: { pattern[($0 / 3) % pattern.count] })
        )
    }

    @Test func heartRateNeverReachedFallsBackToTime() {
        assertParity(
            [LegacyWorkoutSegment(type: .interval, rowDuration: 30, restDuration: 20, repeats: 3)],
            hr: (ceiling: 180, floor: 60),
            script: Script(heartRate: { _ in 130 })
        )
    }

    // MARK: - Durations

    @Test func timeSegmentDurationsMatchLegacyTotals() {
        let fixtures = [
            LegacyWorkoutSegment(type: .warmup, rowDuration: 600),
            LegacyWorkoutSegment(type: .interval, rowDuration: 60, restDuration: 60, repeats: 8),
            LegacyWorkoutSegment(type: .interval, rowDuration: 240, restDuration: 180, repeats: 4),
            LegacyWorkoutSegment(type: .interval, rowDuration: 45, restDuration: 0, repeats: 5),
            LegacyWorkoutSegment(type: .cooldown, rowDuration: 300),
        ]
        for (seg, block) in zip(fixtures, blocks(from: fixtures)) {
            let estimate = DurationEstimator.estimate(block)
            #expect(estimate.seconds == seg.totalDuration)
            #expect(!estimate.isEstimate)
        }
    }

    /// F8: RowUp2 counted only rest for distance-ended rows; the new total includes an
    /// estimate for the row and says so.
    @Test func metricSegmentDurationIsEstimatedNotUndercounted() {
        let seg = LegacyWorkoutSegment(type: .interval, rowTrigger: .distance, rowDuration: 0, rowTargetValue: 500, restDuration: 90, repeats: 4)
        let estimate = DurationEstimator.estimate(blocks(from: [seg])[0], assumptions: EstimateAssumptions(activity: .rowing))
        #expect(seg.totalDuration == 360)
        #expect(estimate.isEstimate)
        let expected: TimeInterval = 4 * (500 * 0.25 + 90)
        #expect(estimate.seconds == expected)
    }

    @Test func legacyFormatDurationMatchesClock() {
        for seconds in [0.0, 5, 45, 60, 61, 90, 599, 600, 3599] {
            #expect(DurationFormatter.clock(seconds) == LegacyWorkoutSegment.formatDuration(seconds))
        }
    }
}
