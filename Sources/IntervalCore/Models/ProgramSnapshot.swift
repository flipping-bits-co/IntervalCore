import Foundation

/// Activity the workout is saved as. The apps map it to `HKWorkoutActivityType`.
public enum Activity: String, Codable, Hashable, Sendable, CaseIterable {
    case hiit
    case strength
    case running
    case walking
    case cycling
    case rowing
    case mobility
    case other

    public var label: String {
        switch self {
        case .hiit: "HIIT"
        case .strength: "Strength"
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Cycle"
        case .rowing: "Row"
        case .mobility: "Mobility"
        case .other: "Other"
        }
    }

    /// Whether HealthKit reports live distance for this activity, so `.distance`
    /// steps and targets make sense (design plan §6).
    public var supportsDistance: Bool {
        switch self {
        case .running, .walking, .cycling, .rowing: true
        default: false
        }
    }
}

/// Workout-level target used by loop-until-target programs and time caps.
public enum WorkoutTarget: Codable, Hashable, Sendable {
    case time(TimeInterval)
    case distance(meters: Double)
    case calories(Double)
}

/// How the whole workout ends.
public enum WorkoutEnd: Codable, Hashable, Sendable {
    /// Run every block once.
    case allBlocks
    /// Stop when the target is reached. Loop blocks repeat until then.
    case target(WorkoutTarget)

    public var target: WorkoutTarget? {
        if case .target(let t) = self { return t }
        return nil
    }
}

/// Plain, Codable copy of a program. Used for the Watch cache, WatchConnectivity,
/// and anywhere the apps need a program without SwiftData.
public struct ProgramSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var activity: Activity
    public var blocks: [IntervalBlock]
    public var workoutEnd: WorkoutEnd
    public var isPinned: Bool
    public var lastUsedDate: Date?
    /// Training-track tags when this program is (or contains) track sessions, set by
    /// `TrackChainer`. Rides along on `SessionStart` and comes back on `SessionResult`, so a
    /// run on either device advances the right tracks. `nil` for ordinary programs and in
    /// payloads from older builds.
    public var trackRefs: [TrackRef]?

    public init(
        id: UUID = UUID(),
        name: String = "",
        activity: Activity = .hiit,
        blocks: [IntervalBlock] = [],
        workoutEnd: WorkoutEnd = .allBlocks,
        isPinned: Bool = false,
        lastUsedDate: Date? = nil,
        trackRefs: [TrackRef]? = nil
    ) {
        self.id = id
        self.name = name
        self.activity = activity
        self.blocks = blocks
        self.workoutEnd = workoutEnd
        self.isPinned = isPinned
        self.lastUsedDate = lastUsedDate
        self.trackRefs = trackRefs
    }

    /// `name`, or the auto name when the user never set one.
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? ProgramNamer.displayName(for: blocks, workoutEnd: workoutEnd) : trimmed
    }

    public var structureHash: String {
        StructureHash.hash(blocks: blocks, workoutEnd: workoutEnd, activity: activity)
    }

    public func compile() -> Timeline {
        TimelineCompiler.compile(blocks, workoutEnd: workoutEnd)
    }

    public func estimatedDuration(assumptions: EstimateAssumptions? = nil) -> DurationEstimate {
        DurationEstimator.estimate(compile(), assumptions: assumptions ?? EstimateAssumptions(activity: activity))
    }
}
