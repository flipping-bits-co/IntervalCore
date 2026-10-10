import Foundation

/// Why the engine moved to a step, or ended.
public enum TransitionReason: String, Codable, Hashable, Sendable {
    case start
    case timeElapsed
    case heartRateReached
    /// An HR step hit its `maxWait` fallback.
    case heartRateTimeout
    /// A distance or calorie step reached its goal.
    case metricReached
    /// "Done" / "Next" on reps and open steps.
    case userAdvanced
    case skipped
    case previous
    case restarted
    /// The workout target was reached; jumped past the loop.
    case targetReached
}

public enum CompletionReason: String, Codable, Hashable, Sendable {
    /// Ran off the end of the timeline.
    case finished
    case targetReached
    /// User ended early via `finish(at:)`.
    case stopped
}

/// Things the apps turn into haptics, audio cues, and UI updates. Returned in order
/// from every mutating engine call.
public enum EngineEvent: Codable, Hashable, Sendable {
    case stepStarted(index: Int, reason: TransitionReason)
    /// 3-2-1 before a timed step ends. Only for steps longer than `secondsRemaining`.
    case countdown(index: Int, secondsRemaining: Int)
    /// Halfway through a timed step of 60 s or more.
    case halfway(index: Int)
    /// The loop range started again. `iteration` is 1-based (first repeat = 2).
    case loopStarted(iteration: Int)
    case targetReached
    /// AMRAP-style round tap.
    case roundLogged(count: Int)
    case paused
    case resumed
    case completed(reason: CompletionReason)
}

/// What happened in one step, for summaries, splits, and `SessionResult`.
public struct StepRecord: Codable, Hashable, Sendable {
    public var timelineIndex: Int
    public var loopIteration: Int
    public var kind: StepKind
    public var blockIndex: Int
    public var round: Int
    /// Active workout time when the step started.
    public var startOffset: TimeInterval
    public var duration: TimeInterval
    public var endReason: TransitionReason
    public var distance: Double
    public var calories: Double
    /// Reps the user logged when ending the step with Done: the target for a `.reps` step
    /// unless they logged fewer (or more). `nil` for other steps, skips, and older builds.
    public var repsLogged: Int?

    public init(
        timelineIndex: Int,
        loopIteration: Int,
        kind: StepKind,
        blockIndex: Int,
        round: Int,
        startOffset: TimeInterval,
        duration: TimeInterval,
        endReason: TransitionReason,
        distance: Double,
        calories: Double,
        repsLogged: Int? = nil
    ) {
        self.timelineIndex = timelineIndex
        self.loopIteration = loopIteration
        self.kind = kind
        self.blockIndex = blockIndex
        self.round = round
        self.startOffset = startOffset
        self.duration = duration
        self.endReason = endReason
        self.distance = distance
        self.calories = calories
        self.repsLogged = repsLogged
    }

    /// Short keys, default values omitted, and times rounded to the millisecond, so long
    /// sessions' `SessionResult` files stay small. Wire format only; the Swift API is
    /// unaffected. Decoded times match the originals to within 0.5 ms, not bit for bit.
    private enum CodingKeys: String, CodingKey {
        case timelineIndex = "i"
        case loopIteration = "l"
        case kind = "k"
        case blockIndex = "b"
        case round = "r"
        case startOffset = "o"
        case duration = "d"
        case endReason = "e"
        case distance = "m"
        case calories = "c"
        case repsLogged = "n"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        timelineIndex = try c.decode(Int.self, forKey: .timelineIndex)
        loopIteration = try c.decodeIfPresent(Int.self, forKey: .loopIteration) ?? 1
        kind = try c.decode(StepKind.self, forKey: .kind)
        blockIndex = try c.decode(Int.self, forKey: .blockIndex)
        round = try c.decode(Int.self, forKey: .round)
        startOffset = try c.decode(TimeInterval.self, forKey: .startOffset)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        endReason = try c.decodeIfPresent(TransitionReason.self, forKey: .endReason) ?? .timeElapsed
        distance = try c.decodeIfPresent(Double.self, forKey: .distance) ?? 0
        calories = try c.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        repsLogged = try c.decodeIfPresent(Int.self, forKey: .repsLogged)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(timelineIndex, forKey: .timelineIndex)
        if loopIteration != 1 { try c.encode(loopIteration, forKey: .loopIteration) }
        try c.encode(kind, forKey: .kind)
        try c.encode(blockIndex, forKey: .blockIndex)
        try c.encode(round, forKey: .round)
        try c.encode(Self.millis(startOffset), forKey: .startOffset)
        try c.encode(Self.millis(duration), forKey: .duration)
        if endReason != .timeElapsed { try c.encode(endReason, forKey: .endReason) }
        if distance != 0 { try c.encode(distance, forKey: .distance) }
        if calories != 0 { try c.encode(calories, forKey: .calories) }
        try c.encodeIfPresent(repsLogged, forKey: .repsLogged)
    }

    /// Drops float drift (19.999999999999996 → 20) so JSON stays short.
    private static func millis(_ value: TimeInterval) -> TimeInterval {
        (value * 1000).rounded() / 1000
    }
}
