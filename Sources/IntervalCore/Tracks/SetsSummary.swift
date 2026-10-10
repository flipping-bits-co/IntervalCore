import Foundation

/// The short reps label shared by the phone and Watch: "3-4-5-6-8+", "5×10", "8-8-20s".
/// Built from a session's work steps, so it reads the same for a single track session and,
/// with `blockIDs`, for one track inside a chained program.
public enum SetsSummary {

    /// Shown for a work step that was skipped or never reached.
    public static let missing = "–"

    /// The planned sets, e.g. "3-4-5-6-8+" (a max set shows as "n+"), or "5×10" when every set is
    /// the same. Holds read "20s", or "1:30" from a minute up. `nil` when the work steps have no
    /// reps step (Run / Walk, Plank), so callers show the duration instead.
    public static func planned(_ program: ProgramSnapshot, blockIDs: Set<UUID>? = nil) -> String? {
        let steps = workSteps(program, blockIDs: blockIDs)
        guard steps.contains(where: isReps) else { return nil }
        return join(steps.map(plannedToken))
    }

    /// What was done, in the same format: logged reps (the target when none was logged), the
    /// planned length for a finished hold, and "–" for a skipped or unreached step. `nil` when
    /// `planned` is.
    public static func logged(_ records: [StepRecord], program: ProgramSnapshot, blockIDs: Set<UUID>? = nil) -> String? {
        let steps = workSteps(program, blockIDs: blockIDs)
        guard steps.contains(where: isReps) else { return nil }
        var latest: [Int: StepRecord] = [:]
        for record in records { latest[record.timelineIndex] = record }
        return join(steps.map { step in
            guard let record = latest[step.index], isFinished(record) else { return missing }
            if case .reps(let target) = step.end { return String(record.repsLogged ?? target) }
            return plannedToken(step)
        })
    }

    // MARK: - Internals

    private static func workSteps(_ program: ProgramSnapshot, blockIDs: Set<UUID>?) -> [TimelineStep] {
        program.compile().steps.filter { step in
            step.kind == .work && (blockIDs?.contains(step.blockID) ?? true)
        }
    }

    private static func isReps(_ step: TimelineStep) -> Bool {
        if case .reps = step.end { return true }
        return false
    }

    private static func plannedToken(_ step: TimelineStep) -> String {
        switch step.end {
        case .reps(let n):
            return RepsSetBuilder.isMaxSet(step.name) ? "\(n)+" : String(n)
        case .time(let seconds):
            return seconds < 60 ? "\(Int(seconds.rounded()))s" : DurationFormatter.clock(seconds)
        case .open:
            return "max"
        default:
            return step.end.summary
        }
    }

    private static func isFinished(_ record: StepRecord) -> Bool {
        switch record.endReason {
        case .skipped, .previous, .restarted: false
        default: true
        }
    }

    /// "5×10" when there are several identical sets, else the sets joined with "-".
    private static func join(_ tokens: [String]) -> String {
        if tokens.count > 1, let first = tokens.first, first != missing, tokens.allSatisfy({ $0 == first }) {
            return "\(tokens.count)×\(first)"
        }
        return tokens.joined(separator: "-")
    }
}
