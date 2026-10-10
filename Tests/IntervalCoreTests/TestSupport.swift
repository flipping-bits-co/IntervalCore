import Foundation
@testable import IntervalCore

func work(_ seconds: TimeInterval, _ name: String = "") -> IntervalStep {
    IntervalStep(kind: .work, name: name, end: .time(seconds))
}

func rest(_ seconds: TimeInterval) -> IntervalStep {
    IntervalStep(kind: .rest, end: .time(seconds))
}

func step(_ kind: StepKind, _ end: EndCondition) -> IntervalStep {
    IntervalStep(kind: kind, end: end)
}

func block(_ steps: IntervalStep..., repeats: Int = 1, skipLastRest: Bool = true, loops: Bool = false) -> IntervalBlock {
    IntervalBlock(steps: steps, repeats: repeats, skipLastRest: skipLastRest, loopsUntilTarget: loops)
}

/// Same shape as RowUp2's `makeIntervalManager(rowDuration:restDuration:repeats:)`. RowUp2
/// always runs the final rest, so `skipLastRest` is off.
func makeIntervalEngine(work w: TimeInterval, rest r: TimeInterval, repeats: Int) -> IntervalEngine {
    var engine = IntervalEngine(timeline: TimelineCompiler.compile([
        block(work(w), rest(r), repeats: repeats, skipLastRest: false),
    ]))
    engine.start(at: .testEpoch)
    return engine
}

func makeEngine(_ blocks: [IntervalBlock], end: WorkoutEnd = .allBlocks) -> IntervalEngine {
    var engine = IntervalEngine(timeline: TimelineCompiler.compile(blocks, workoutEnd: end))
    engine.start(at: .testEpoch)
    return engine
}

extension IntervalEngine {
    /// One-second ticks, collecting every event.
    @discardableResult
    mutating func tickSeconds(_ n: Int) -> [EngineEvent] {
        (0..<n).flatMap { _ in advance(by: 1) }
    }

    var kind: StepKind? { currentStep?.kind }
    var round: Int? { currentStep?.round }
}

extension Array where Element == EngineEvent {
    var startedIndices: [Int] {
        compactMap { if case .stepStarted(let i, _) = $0 { i } else { nil } }
    }

    var startReasons: [TransitionReason] {
        compactMap { if case .stepStarted(_, let r) = $0 { r } else { nil } }
    }

    var completed: CompletionReason? {
        for case .completed(let reason) in self { return reason }
        return nil
    }
}

extension Date {
    /// Fixed start time for tests that drive the engine with `advance(by:)`.
    static let testEpoch = Date(timeIntervalSinceReferenceDate: 0)
}
