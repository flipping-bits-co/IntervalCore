import Foundation

/// Expands a ladder (start, step, peak, optionally back down) into one concrete block.
public enum LadderGenerator {

    public enum Metric: String, Codable, Hashable, Sendable, CaseIterable {
        case time
        case distance
        case calories
        case reps

        func end(_ value: Double) -> EndCondition {
            switch self {
            case .time: .time(value)
            case .distance: .distance(meters: value)
            case .calories: .calories(value)
            case .reps: .reps(Int(value.rounded()))
            }
        }
    }

    public enum Rest: Codable, Hashable, Sendable {
        case none
        case fixed(TimeInterval)
        /// Rest = work × ratio. Only meaningful for `.time` ladders; other metrics fall back to no rest.
        case ratio(Double)
    }

    /// Guards against a tiny step producing thousands of rungs.
    public static let maxRungs = 50

    /// The rung values, e.g. start 60, step 60, peak 180, down → [60, 120, 180, 120, 60].
    /// Always ends the climb on `peak`, even when the step doesn't land on it.
    public static func values(start: Double, step: Double, peak: Double, descending: Bool) -> [Double] {
        guard step > 0, start < peak else { return [start] }
        var up: [Double] = []
        var value = start
        while value < peak, up.count < maxRungs - 1 {
            up.append(value)
            value += step
        }
        up.append(peak)
        guard descending else { return up }
        return up + up.dropLast().reversed()
    }

    public static func makeBlock(
        metric: Metric = .time,
        start: Double,
        step: Double,
        peak: Double,
        descending: Bool = true,
        rest: Rest = .none,
        kind: StepKind = .work,
        name: String = "Ladder"
    ) -> IntervalBlock {
        var steps: [IntervalStep] = []
        for value in values(start: start, step: step, peak: peak, descending: descending) {
            steps.append(IntervalStep(kind: kind, end: metric.end(value)))
            let restSeconds: TimeInterval = switch rest {
            case .none: 0
            case .fixed(let seconds): seconds
            case .ratio(let ratio): metric == .time ? value * ratio : 0
            }
            if restSeconds > 0 { steps.append(IntervalStep(kind: .rest, end: .time(restSeconds))) }
        }
        return IntervalBlock(name: name, steps: steps, repeats: 1, skipLastRest: true)
    }
}
