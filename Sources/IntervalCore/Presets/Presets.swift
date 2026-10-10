import Foundation

/// Quick timers. Each is just a program built from blocks (design plan §3).
public enum Preset: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case workRest
    case tabata
    case emom
    case amrap
    case forTime

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .workRest: "Work/Rest"
        case .tabata: "Tabata"
        case .emom: "EMOM"
        case .amrap: "AMRAP"
        case .forTime: "For Time"
        }
    }

    /// The preset with its default settings.
    public func makeProgram(activity: Activity = .hiit) -> ProgramSnapshot {
        switch self {
        case .workRest: Presets.workRest(activity: activity)
        case .tabata: Presets.tabata(activity: activity)
        case .emom: Presets.emom(activity: activity)
        case .amrap: Presets.amrap(activity: activity)
        case .forTime: Presets.forTime(activity: activity)
        }
    }
}

public enum Presets {

    public static let defaultPrepare: TimeInterval = 10

    /// `[work W, rest R] × N`. Unnamed so the auto name ("8×0:30/0:30") describes it.
    public static func workRest(
        work: TimeInterval = 30,
        rest: TimeInterval = 30,
        rounds: Int = 8,
        prepare: TimeInterval = defaultPrepare,
        activity: Activity = .hiit
    ) -> ProgramSnapshot {
        var steps = [IntervalStep(kind: .work, end: .time(work))]
        if rest > 0 { steps.append(IntervalStep(kind: .rest, end: .time(rest))) }
        return ProgramSnapshot(
            activity: activity,
            blocks: prepareBlocks(prepare) + [IntervalBlock(steps: steps, repeats: rounds)]
        )
    }

    /// 20 s work / 10 s rest × 8.
    public static func tabata(prepare: TimeInterval = defaultPrepare, activity: Activity = .hiit) -> ProgramSnapshot {
        var program = workRest(work: 20, rest: 10, rounds: 8, prepare: prepare, activity: activity)
        program.name = "Tabata"
        return program
    }

    /// One 60 s "Minute" step per round; the user's rest is whatever is left of it.
    public static func emom(
        minutes: Int = 10,
        prepare: TimeInterval = defaultPrepare,
        activity: Activity = .hiit
    ) -> ProgramSnapshot {
        let block = IntervalBlock(
            steps: [IntervalStep(kind: .work, name: "Minute", end: .time(60))],
            repeats: minutes
        )
        return ProgramSnapshot(name: "EMOM \(minutes)", activity: activity, blocks: prepareBlocks(prepare) + [block])
    }

    /// One long work step; rounds are counted with `IntervalEngine.logRound()`.
    public static func amrap(
        duration: TimeInterval = 20 * 60,
        prepare: TimeInterval = defaultPrepare,
        activity: Activity = .hiit
    ) -> ProgramSnapshot {
        let block = IntervalBlock(steps: [IntervalStep(kind: .work, name: "AMRAP", end: .time(duration))])
        return ProgramSnapshot(
            name: "AMRAP \(DurationFormatter.clock(duration))",
            activity: activity,
            blocks: prepareBlocks(prepare) + [block]
        )
    }

    /// One open step the user ends with "Next", with an optional time cap.
    public static func forTime(
        cap: TimeInterval? = nil,
        prepare: TimeInterval = defaultPrepare,
        activity: Activity = .hiit
    ) -> ProgramSnapshot {
        let block = IntervalBlock(steps: [IntervalStep(kind: .work, name: "For Time", end: .open)])
        let end: WorkoutEnd = cap.map { .target(.time($0)) } ?? .allBlocks
        return ProgramSnapshot(name: "For Time", activity: activity, blocks: prepareBlocks(prepare) + [block], workoutEnd: end)
    }

    static func prepareBlocks(_ prepare: TimeInterval) -> [IntervalBlock] {
        guard prepare > 0 else { return [] }
        return [IntervalBlock(steps: [IntervalStep(kind: .prepare, end: .time(prepare))])]
    }
}
