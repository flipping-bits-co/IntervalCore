import Foundation

/// One step inside a block: kind + optional name + how it ends.
public struct IntervalStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: StepKind
    /// Free text like "Push-ups". Empty means "use the kind label".
    public var name: String
    public var end: EndCondition

    public init(id: UUID = UUID(), kind: StepKind = .work, name: String = "", end: EndCondition = .time(60)) {
        self.id = id
        self.kind = kind
        self.name = name
        self.end = end
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.label : trimmed
    }
}

/// A group of steps run `repeats` times. Adapted from RowUp2 `WorkoutSegment`.
public struct IntervalBlock: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [IntervalStep]
    public var repeats: Int
    /// Drop trailing rest steps from the final round. Ignored for loop blocks, which
    /// need the rest between loop iterations.
    public var skipLastRest: Bool
    /// When the workout ends on a target, the contiguous range of loop blocks repeats
    /// until the target is reached (was `WorkoutSegment.loopOnTarget`).
    public var loopsUntilTarget: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        steps: [IntervalStep] = [],
        repeats: Int = 1,
        skipLastRest: Bool = true,
        loopsUntilTarget: Bool = false
    ) {
        self.id = id
        self.name = name
        self.steps = steps
        self.repeats = repeats
        self.skipLastRest = skipLastRest
        self.loopsUntilTarget = loopsUntilTarget
    }
}
