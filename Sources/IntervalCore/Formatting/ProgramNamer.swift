import Foundation

/// Auto display names such as "Warm-up + 8×1:00/1:00 + Cool-down".
public enum ProgramNamer {

    public static func displayName(for blocks: [IntervalBlock], workoutEnd: WorkoutEnd = .allBlocks) -> String {
        let parts = blocks.compactMap(blockName)
        var name = parts.isEmpty ? "Workout" : parts.joined(separator: " + ")
        if case .target(let target) = workoutEnd {
            name += " until " + targetSummary(target)
        }
        return name
    }

    /// `nil` for blocks that don't belong in a name (empty, or only "Get Ready").
    public static func blockName(_ block: IntervalBlock) -> String? {
        let steps = block.steps.filter { $0.kind != .prepare }
        guard !steps.isEmpty else { return nil }

        let custom = block.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }

        let rounds = max(1, block.repeats)
        if steps.count == 1, rounds == 1 {
            let step = steps[0]
            switch step.kind {
            case .warmup, .cooldown: return step.displayName
            default: return "\(step.displayName) \(step.end.summary)"
            }
        }

        let body = steps.map(\.end.summary).joined(separator: "/")
        return rounds > 1 ? "\(rounds)×\(body)" : body
    }

    public static func targetSummary(_ target: WorkoutTarget) -> String {
        switch target {
        case .time(let seconds): DurationFormatter.clock(seconds)
        case .distance(let meters): DurationFormatter.distance(meters)
        case .calories(let kcal): "\(Int(kcal.rounded())) kcal"
        }
    }
}
