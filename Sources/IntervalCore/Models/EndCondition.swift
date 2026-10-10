import Foundation

/// How a single step ends. Replaces RowUp2's `PhaseTrigger`, `IntervalEndCondition`,
/// and `TargetMetric` with one type (discovery F1/F7).
public enum EndCondition: Codable, Hashable, Sendable {
    case time(TimeInterval)
    /// Distance covered during the step, fed in via `IntervalEngine.updateMetrics`.
    case distance(meters: Double)
    /// Active calories burned during the step.
    case calories(Double)
    /// User taps "Done" after `n` reps. The engine does not count reps.
    case reps(Int)
    /// User taps "Next".
    case open
    /// Ends when HR drops to `bpm` or below. `maxWait <= 0` means wait forever.
    case heartRateBelow(bpm: Int, maxWait: TimeInterval)
    /// Ends when HR rises to `bpm` or above. `maxWait <= 0` means wait forever.
    case heartRateAbove(bpm: Int, maxWait: TimeInterval)

    /// Exact duration when the step ends on time alone.
    public var fixedDuration: TimeInterval? {
        if case .time(let seconds) = self { return seconds }
        return nil
    }

    public var isTimed: Bool { fixedDuration != nil }

    /// True when the step only ends by a user tap.
    public var requiresUserAction: Bool {
        switch self {
        case .reps, .open: true
        default: false
        }
    }

    public var isHeartRate: Bool {
        switch self {
        case .heartRateBelow, .heartRateAbove: true
        default: false
        }
    }

    public var isMetric: Bool {
        switch self {
        case .distance, .calories: true
        default: false
        }
    }

    /// Fallback time for HR steps, if any.
    public var heartRateMaxWait: TimeInterval? {
        switch self {
        case .heartRateBelow(_, let wait), .heartRateAbove(_, let wait):
            wait > 0 ? wait : nil
        default:
            nil
        }
    }

    /// Short label for chips and auto names: "1:00", "500m", "15 kcal", "10 reps", "Open", "HR ≤ 120".
    public var summary: String {
        switch self {
        case .time(let seconds):
            DurationFormatter.clock(seconds)
        case .distance(let meters):
            DurationFormatter.distance(meters)
        case .calories(let kcal):
            "\(Int(kcal.rounded())) kcal"
        case .reps(let n):
            n == 1 ? "1 rep" : "\(n) reps"
        case .open:
            "Open"
        case .heartRateBelow(let bpm, _):
            "HR ≤ \(bpm)"
        case .heartRateAbove(let bpm, _):
            "HR ≥ \(bpm)"
        }
    }
}
