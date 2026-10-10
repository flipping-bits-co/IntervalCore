import Foundation

/// Builds "sets with rest" blocks for strength tracks, e.g. push-ups [10, 12, 8, 8, max 12]
/// with 60 s rest: one block, a work step per set and a rest step between sets.
public enum RepsSetBuilder {

    public enum SetTarget: Codable, Hashable, Sendable {
        /// Tap Done after `n` reps.
        case reps(Int)
        /// "As many as you can, at least `n`": a reps step, so logging fewer counts as a miss.
        case max(atLeast: Int)
        /// A timed hold, e.g. a plank.
        case hold(TimeInterval)
    }

    /// One block of sets. Step names are the exercise ("Push-ups"); a max set reads
    /// "Push-ups · max". `id` lets bundled tracks pin a stable block id for `TrackRef`s.
    public static func block(
        id: UUID = UUID(),
        exercise: String,
        sets: [SetTarget],
        rest: TimeInterval,
        stepIDs: (Int) -> UUID = { _ in UUID() }
    ) -> IntervalBlock {
        var steps: [IntervalStep] = []
        for (index, set) in sets.enumerated() {
            if index > 0, rest > 0 {
                steps.append(IntervalStep(id: stepIDs(steps.count), kind: .rest, end: .time(rest)))
            }
            steps.append(IntervalStep(id: stepIDs(steps.count), kind: .work, name: name(exercise, set), end: end(set)))
        }
        return IntervalBlock(id: id, name: exercise, steps: steps)
    }

    /// Several exercises in one block list, e.g. assisted then negative pull-ups. Rest also
    /// sits between groups. Each group becomes its own block.
    public static func blocks(
        groups: [(exercise: String, sets: [SetTarget])],
        rest: TimeInterval,
        blockID: (Int) -> UUID = { _ in UUID() },
        stepID: (Int, Int) -> UUID = { _, _ in UUID() }
    ) -> [IntervalBlock] {
        var blocks: [IntervalBlock] = []
        for (index, group) in groups.enumerated() {
            var block = block(id: blockID(index), exercise: group.exercise, sets: group.sets, rest: rest) { stepID(index, $0) }
            if index < groups.count - 1, rest > 0 {
                block.steps.append(IntervalStep(id: stepID(index, block.steps.count), kind: .rest, end: .time(rest)))
                block.skipLastRest = false
            }
            blocks.append(block)
        }
        return blocks
    }

    /// Step-name suffix that marks a max set ("Push-ups · max").
    public static let maxSuffix = " · max"

    /// Whether a step name marks a max set built here.
    public static func isMaxSet(_ stepName: String) -> Bool {
        stepName.hasSuffix(maxSuffix)
    }

    private static func name(_ exercise: String, _ set: SetTarget) -> String {
        if case .max = set { return exercise + maxSuffix }
        return exercise
    }

    private static func end(_ set: SetTarget) -> EndCondition {
        switch set {
        case .reps(let n), .max(let n): .reps(max(1, n))
        case .hold(let seconds): .time(seconds)
        }
    }
}
