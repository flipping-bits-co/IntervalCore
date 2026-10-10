import Foundation

/// One entry in the flat, compiled timeline. The timeline strip, "next up", the
/// progress ring, and the Watch all read this same structure.
public struct TimelineStep: Codable, Hashable, Identifiable, Sendable {
    /// Position in `Timeline.steps`.
    public var index: Int
    public var blockIndex: Int
    public var blockID: UUID
    public var stepID: UUID
    /// 1-based round within the block.
    public var round: Int
    /// The block's `repeats`.
    public var totalRounds: Int
    /// Position of the step inside its block.
    public var stepIndex: Int
    public var kind: StepKind
    public var name: String
    public var end: EndCondition

    public var id: Int { index }

    public init(
        index: Int,
        blockIndex: Int,
        blockID: UUID,
        stepID: UUID,
        round: Int,
        totalRounds: Int,
        stepIndex: Int,
        kind: StepKind,
        name: String,
        end: EndCondition
    ) {
        self.index = index
        self.blockIndex = blockIndex
        self.blockID = blockID
        self.stepID = stepID
        self.round = round
        self.totalRounds = totalRounds
        self.stepIndex = stepIndex
        self.kind = kind
        self.name = name
        self.end = end
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.label : trimmed
    }
}

/// Output of `TimelineCompiler`: the flat step list plus how the workout ends.
public struct Timeline: Codable, Hashable, Sendable {
    public var steps: [TimelineStep]
    public var workoutEnd: WorkoutEnd
    /// Steps repeated until the workout target is reached. Only set when
    /// `workoutEnd` is a target and at least one block loops.
    public var loopRange: Range<Int>?

    public init(steps: [TimelineStep], workoutEnd: WorkoutEnd = .allBlocks, loopRange: Range<Int>? = nil) {
        self.steps = steps
        self.workoutEnd = workoutEnd
        self.loopRange = loopRange
    }

    public var isEmpty: Bool { steps.isEmpty }
    public var count: Int { steps.count }

    /// Index of the first step after the loop, e.g. a cool-down. `nil` when nothing follows.
    public var postLoopStart: Int? {
        guard let loopRange, loopRange.upperBound < steps.count else { return nil }
        return loopRange.upperBound
    }
}
