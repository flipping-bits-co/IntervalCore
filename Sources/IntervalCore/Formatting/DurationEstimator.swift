import Foundation

/// A total that may include guesses for steps that don't end on time (F8).
public struct DurationEstimate: Codable, Hashable, Sendable {
    public var seconds: TimeInterval
    /// True when any part came from an assumption rather than a fixed duration.
    public var isEstimate: Bool

    public init(seconds: TimeInterval, isEstimate: Bool) {
        self.seconds = seconds
        self.isEstimate = isEstimate
    }

    public static let zero = DurationEstimate(seconds: 0, isEstimate: false)

    public static func + (lhs: DurationEstimate, rhs: DurationEstimate) -> DurationEstimate {
        DurationEstimate(seconds: lhs.seconds + rhs.seconds, isEstimate: lhs.isEstimate || rhs.isEstimate)
    }
}

/// Guesses used to size steps that end on something other than time.
public struct EstimateAssumptions: Codable, Hashable, Sendable {
    public var secondsPerMeter: Double
    public var secondsPerCalorie: Double
    public var secondsPerRep: Double
    public var openStepSeconds: TimeInterval
    /// Used for HR steps with no `maxWait`.
    public var heartRateStepSeconds: TimeInterval

    public init(
        secondsPerMeter: Double = 0.36,
        secondsPerCalorie: Double = 6,
        secondsPerRep: Double = 3,
        openStepSeconds: TimeInterval = 60,
        heartRateStepSeconds: TimeInterval = 90
    ) {
        self.secondsPerMeter = secondsPerMeter
        self.secondsPerCalorie = secondsPerCalorie
        self.secondsPerRep = secondsPerRep
        self.openStepSeconds = openStepSeconds
        self.heartRateStepSeconds = heartRateStepSeconds
    }

    /// Conservative recreational paces per activity.
    public init(activity: Activity) {
        let pace: Double = switch activity {
        case .rowing: 0.25      // 2:05 / 500m
        case .cycling: 0.144    // 25 km/h
        case .walking: 0.75     // 4.8 km/h
        default: 0.36           // 6:00 / km run
        }
        self.init(secondsPerMeter: pace)
    }
}

public enum DurationEstimator {

    public static func estimate(_ end: EndCondition, assumptions: EstimateAssumptions = .init()) -> DurationEstimate {
        switch end {
        case .time(let seconds):
            DurationEstimate(seconds: max(0, seconds), isEstimate: false)
        case .distance(let meters):
            DurationEstimate(seconds: meters * assumptions.secondsPerMeter, isEstimate: true)
        case .calories(let kcal):
            DurationEstimate(seconds: kcal * assumptions.secondsPerCalorie, isEstimate: true)
        case .reps(let n):
            DurationEstimate(seconds: Double(n) * assumptions.secondsPerRep, isEstimate: true)
        case .open:
            DurationEstimate(seconds: assumptions.openStepSeconds, isEstimate: true)
        case .heartRateBelow(_, let wait), .heartRateAbove(_, let wait):
            DurationEstimate(seconds: wait > 0 ? wait : assumptions.heartRateStepSeconds, isEstimate: true)
        }
    }

    /// Sum of the given steps. Used for strip widths and per-block totals.
    public static func estimate(_ steps: some Sequence<TimelineStep>, assumptions: EstimateAssumptions = .init()) -> DurationEstimate {
        steps.reduce(.zero) { $0 + estimate($1.end, assumptions: assumptions) }
    }

    public static func estimate(_ block: IntervalBlock, assumptions: EstimateAssumptions = .init()) -> DurationEstimate {
        estimate(TimelineCompiler.compile([block]).steps, assumptions: assumptions)
    }

    /// Whole-workout total. Loop programs are sized by their target: a time target is
    /// exact (plus anything after the loop); distance and calorie targets are guesses.
    public static func estimate(_ timeline: Timeline, assumptions: EstimateAssumptions = .init()) -> DurationEstimate {
        let all = estimate(timeline.steps, assumptions: assumptions)
        guard let target = timeline.workoutEnd.target else { return all }

        guard let loopRange = timeline.loopRange else {
            // No loop: the target acts as a cap on a single pass.
            switch target {
            case .time(let cap):
                return cap < all.seconds ? DurationEstimate(seconds: cap, isEstimate: false) : all
            case .distance(let meters):
                return capped(all, by: DurationEstimate(seconds: meters * assumptions.secondsPerMeter, isEstimate: true))
            case .calories(let kcal):
                return capped(all, by: DurationEstimate(seconds: kcal * assumptions.secondsPerCalorie, isEstimate: true))
            }
        }

        let after = estimate(timeline.steps[loopRange.upperBound...], assumptions: assumptions)
        let untilTarget: DurationEstimate = switch target {
        case .time(let seconds):
            DurationEstimate(seconds: seconds, isEstimate: false)
        case .distance(let meters):
            DurationEstimate(seconds: meters * assumptions.secondsPerMeter, isEstimate: true)
        case .calories(let kcal):
            DurationEstimate(seconds: kcal * assumptions.secondsPerCalorie, isEstimate: true)
        }
        return untilTarget + after
    }

    private static func capped(_ total: DurationEstimate, by cap: DurationEstimate) -> DurationEstimate {
        cap.seconds < total.seconds ? cap : DurationEstimate(seconds: total.seconds, isEstimate: true)
    }
}

extension IntervalEngine {
    /// Time left in the whole workout, for the live "elapsed · ~remaining" line. Same rules as
    /// `DurationEstimator.estimate(_ timeline:)`: exact for time-only workouts and time targets,
    /// `isEstimate` once any part depends on a guess (metric, reps, open, HR steps).
    public func remainingEstimate(assumptions: EstimateAssumptions = .init()) -> DurationEstimate {
        guard let step = currentStep else { return .zero }

        let current: DurationEstimate = if let fixed = step.end.fixedDuration {
            DurationEstimate(seconds: max(0, fixed - stepElapsed), isEstimate: false)
        } else {
            DurationEstimate(
                seconds: max(0, DurationEstimator.estimate(step.end, assumptions: assumptions).seconds - stepElapsed),
                isEstimate: true
            )
        }
        let rest = DurationEstimator.estimate(timeline.steps[(currentIndex + 1)...], assumptions: assumptions)
        let natural = current + rest

        guard !targetReached, let target = timeline.workoutEnd.target else { return natural }
        let untilTarget: DurationEstimate = switch target {
        case .time(let seconds):
            DurationEstimate(seconds: max(0, seconds - totalElapsed), isEstimate: false)
        case .distance(let meters):
            DurationEstimate(seconds: max(0, meters - totalDistance) * assumptions.secondsPerMeter, isEstimate: true)
        case .calories(let kcal):
            DurationEstimate(seconds: max(0, kcal - totalCalories) * assumptions.secondsPerCalorie, isEstimate: true)
        }

        guard let loopRange = timeline.loopRange else {
            // No loop: the target caps a single pass.
            return untilTarget.seconds < natural.seconds
                ? untilTarget
                : DurationEstimate(seconds: natural.seconds, isEstimate: natural.isEstimate || untilTarget.isEstimate)
        }
        let afterLoop = DurationEstimator.estimate(timeline.steps[loopRange.upperBound...], assumptions: assumptions)
        return untilTarget + afterLoop
    }
}
