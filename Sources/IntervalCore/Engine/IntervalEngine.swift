import Foundation

/// Walks a compiled `Timeline`. Adapted from RowUp2 `IntervalManager`, but a value
/// type with no clock of its own: callers feed time (`tick(at:)` or `advance(by:)`),
/// heart rate, and metrics in, and get `EngineEvent`s back. That keeps it
/// deterministic under test and lets the apps hold it inside an `@Observable` model.
public struct IntervalEngine: Codable, Hashable, Sendable {

    public enum Status: String, Codable, Hashable, Sendable {
        case ready
        case running
        case paused
        case completed
    }

    /// Steps shorter than this are treated as ended. Absorbs floating-point drift
    /// from many fractional ticks.
    static let epsilon: TimeInterval = 1e-9
    static let countdownSeconds = [3, 2, 1]
    static let halfwayMinimum: TimeInterval = 60

    public let timeline: Timeline
    public private(set) var status: Status = .ready
    public private(set) var currentIndex: Int = 0
    /// 1-based pass through the loop range.
    public private(set) var loopIteration: Int = 1
    public private(set) var stepElapsed: TimeInterval = 0
    /// Active time, excluding pauses.
    public private(set) var totalElapsed: TimeInterval = 0
    public private(set) var heartRate: Double?
    /// Cumulative workout totals, as last reported by `updateMetrics`.
    public private(set) var totalDistance: Double = 0
    public private(set) var totalCalories: Double = 0
    public private(set) var loggedRounds: Int = 0
    public private(set) var targetReached: Bool = false
    public private(set) var completionReason: CompletionReason?
    public private(set) var records: [StepRecord] = []

    private var stepStartDistance: Double = 0
    private var stepStartCalories: Double = 0
    private var stepStartOffset: TimeInterval = 0
    /// Clock reading of the last `start`/`tick`/`resume`. Only meaningful once started.
    private var lastTick: Date = .distantPast

    public init(timeline: Timeline) {
        self.timeline = timeline
    }

    public init(program: ProgramSnapshot) {
        self.init(timeline: program.compile())
    }

    // MARK: - Derived state

    public var isRunning: Bool { status == .running }
    public var isPaused: Bool { status == .paused }
    public var isComplete: Bool { status == .completed }

    public var currentStep: TimelineStep? {
        guard status != .completed, timeline.steps.indices.contains(currentIndex) else { return nil }
        return timeline.steps[currentIndex]
    }

    /// The step that follows, wrapping to the loop start while looping.
    public var nextStep: TimelineStep? {
        guard status != .completed, let next = nextIndex(after: currentIndex) else { return nil }
        return timeline.steps[next]
    }

    /// Time limit of the current step: its duration, or the HR `maxWait` fallback.
    public var stepLimit: TimeInterval? {
        guard let end = currentStep?.end else { return nil }
        return end.fixedDuration ?? end.heartRateMaxWait
    }

    public var stepRemaining: TimeInterval? {
        stepLimit.map { max(0, $0 - stepElapsed) }
    }

    public var stepDistance: Double { totalDistance - stepStartDistance }
    public var stepCalories: Double { totalCalories - stepStartCalories }

    /// 0...1 for the progress ring. `nil` for reps and open steps, and HR steps with no fallback.
    public var stepProgress: Double? {
        guard let end = currentStep?.end else { return nil }
        switch end {
        case .distance(let meters):
            return Self.fraction(stepDistance, of: meters)
        case .calories(let kcal):
            return Self.fraction(stepCalories, of: kcal)
        default:
            return stepLimit.map { Self.fraction(stepElapsed, of: $0) }
        }
    }

    public var isWaitingForHeartRate: Bool { currentStep?.end.isHeartRate ?? false }

    /// 0...1 progress toward the workout target, if there is one.
    public var targetProgress: Double? {
        guard let target = timeline.workoutEnd.target else { return nil }
        if targetReached { return 1 }
        switch target {
        case .time(let seconds): return Self.fraction(totalElapsed, of: seconds)
        case .distance(let meters): return Self.fraction(totalDistance, of: meters)
        case .calories(let kcal): return Self.fraction(totalCalories, of: kcal)
        }
    }

    /// Whether finishing the loop range sends the engine back to its start.
    public var isLooping: Bool { timeline.loopRange != nil && !targetReached }

    // MARK: - Lifecycle

    /// `now` is required so the first tick interval is never lost. Tests driving the
    /// engine with `advance(by:)` can pass any fixed date.
    @discardableResult
    public mutating func start(at now: Date) -> [EngineEvent] {
        guard status == .ready else { return [] }
        lastTick = now
        guard !timeline.isEmpty else {
            var events: [EngineEvent] = []
            complete(.finished, &events)
            return events
        }
        status = .running
        var events: [EngineEvent] = []
        enter(0, reason: .start, &events)
        return events
    }

    /// Advances by the time since the last `tick`/`start`/`resume`. Apps feed monotonic
    /// time. If a timestamp still goes backwards, that tick counts as zero elapsed and
    /// the clock stays put, so the gap is never counted twice.
    @discardableResult
    public mutating func tick(at now: Date) -> [EngineEvent] {
        guard status == .running, now > lastTick else { return [] }
        let last = lastTick
        lastTick = now
        return advance(by: now.timeIntervalSince(last))
    }

    @discardableResult
    public mutating func pause(at now: Date? = nil) -> [EngineEvent] {
        guard status == .running else { return [] }
        var events = now.map { tick(at: $0) } ?? []
        guard status == .running else { return events }
        status = .paused
        events.append(.paused)
        return events
    }

    @discardableResult
    public mutating func resume(at now: Date) -> [EngineEvent] {
        guard status == .paused else { return [] }
        status = .running
        lastTick = now
        return [.resumed]
    }

    /// Ends the workout early. Records the partial step.
    @discardableResult
    public mutating func finish(at now: Date? = nil) -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        var events: [EngineEvent] = []
        if status == .running, let now { events += tick(at: now) }
        guard status != .completed else { return events }
        recordCurrent(reason: .skipped)
        complete(.stopped, &events)
        return events
    }

    // MARK: - Inputs

    /// Moves time forward. Crosses as many step boundaries as `delta` covers
    /// (ported from `IntervalManager.tick`). Ignored unless running.
    @discardableResult
    public mutating func advance(by delta: TimeInterval) -> [EngineEvent] {
        guard status == .running, delta > 0 else { return [] }
        var events: [EngineEvent] = []
        var left = delta
        // Zero-length steps consume no time; stop a loop made only of them from spinning.
        var transitionsWithoutTime = 0
        let spinLimit = timeline.count * 2 + 2

        while status == .running {
            var slice = left
            if let remaining = stepRemaining { slice = min(slice, remaining) }
            if let targetLeft = timeTargetRemaining { slice = min(slice, targetLeft) }

            emitCues(from: stepElapsed, to: stepElapsed + slice, &events)
            stepElapsed += slice
            totalElapsed += slice
            left -= slice

            if slice > Self.epsilon {
                transitionsWithoutTime = 0
            } else {
                transitionsWithoutTime += 1
                if transitionsWithoutTime > spinLimit {
                    recordCurrent(reason: .timeElapsed)
                    complete(.finished, &events)
                    break
                }
            }

            if let targetLeft = timeTargetRemaining, targetLeft <= Self.epsilon {
                reachTarget(&events)
                continue
            }
            if let remaining = stepRemaining, remaining <= Self.epsilon, let end = currentStep?.end {
                advanceStep(reason: end.isHeartRate ? .heartRateTimeout : .timeElapsed, &events)
                continue
            }
            if left <= Self.epsilon { break }
        }
        return events
    }

    /// Latest heart rate. Ends an HR step once its threshold is met, after at least
    /// some time in the step (same guard as RowUp2).
    @discardableResult
    public mutating func updateHeartRate(_ bpm: Double) -> [EngineEvent] {
        heartRate = bpm
        guard status == .running, stepElapsed > 0, let end = currentStep?.end else { return [] }
        let reached: Bool
        switch end {
        case .heartRateBelow(let threshold, _): reached = bpm <= Double(threshold)
        case .heartRateAbove(let threshold, _): reached = bpm >= Double(threshold)
        default: reached = false
        }
        guard reached else { return [] }
        var events: [EngineEvent] = []
        advanceStep(reason: .heartRateReached, &events)
        return events
    }

    /// Cumulative workout totals since start. `nil` leaves a value unchanged.
    @discardableResult
    public mutating func updateMetrics(distance: Double? = nil, calories: Double? = nil) -> [EngineEvent] {
        if let distance { totalDistance = distance }
        if let calories { totalCalories = calories }
        guard status == .running else { return [] }
        var events: [EngineEvent] = []

        if !targetReached, let target = timeline.workoutEnd.target {
            switch target {
            case .distance(let meters) where totalDistance >= meters: reachTarget(&events)
            case .calories(let kcal) where totalCalories >= kcal: reachTarget(&events)
            default: break
            }
        }
        guard status == .running, let end = currentStep?.end else { return events }
        switch end {
        case .distance(let meters) where stepDistance >= meters:
            advanceStep(reason: .metricReached, &events)
        case .calories(let kcal) where stepCalories >= kcal:
            advanceStep(reason: .metricReached, &events)
        default:
            break
        }
        return events
    }

    // MARK: - User actions

    /// "Done" / "Next": ends the current step as completed by the user. On a `.reps(n)` step
    /// the record logs `repsLogged`, or `n` when the user didn't change the count. Other steps
    /// log `repsLogged` only when one is passed (e.g. a max-reps test on an open step).
    @discardableResult
    public mutating func next(repsLogged: Int? = nil) -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        var events: [EngineEvent] = []
        var reps = repsLogged.map { max(0, $0) }
        if reps == nil, case .reps(let target)? = currentStep?.end { reps = target }
        advanceStep(reason: .userAdvanced, repsLogged: reps, &events)
        return events
    }

    /// Skips the current step.
    @discardableResult
    public mutating func skip() -> [EngineEvent] {
        moveForward(reason: .skipped)
    }

    /// Goes back to the start of the previous step (wrapping back through the loop).
    /// On the first step, restarts it.
    @discardableResult
    public mutating func previous() -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        recordCurrent(reason: .previous)
        var target = max(0, currentIndex - 1)
        if let loopRange = timeline.loopRange, currentIndex == loopRange.lowerBound, loopIteration > 1 {
            loopIteration -= 1
            target = loopRange.upperBound - 1
        }
        var events: [EngineEvent] = []
        enter(target, reason: .previous, &events)
        return events
    }

    @discardableResult
    public mutating func restartStep() -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        recordCurrent(reason: .restarted)
        var events: [EngineEvent] = []
        enter(currentIndex, reason: .restarted, &events)
        return events
    }

    /// AMRAP round counter.
    @discardableResult
    public mutating func logRound() -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        loggedRounds += 1
        return [.roundLogged(count: loggedRounds)]
    }

    // MARK: - Internals

    private var timeTargetRemaining: TimeInterval? {
        guard !targetReached, case .target(.time(let seconds)) = timeline.workoutEnd else { return nil }
        return max(0, seconds - totalElapsed)
    }

    private func nextIndex(after index: Int) -> Int? {
        let next = index + 1
        if let loopRange = timeline.loopRange, next == loopRange.upperBound, !targetReached {
            return loopRange.lowerBound
        }
        return next < timeline.count ? next : nil
    }

    private mutating func moveForward(reason: TransitionReason) -> [EngineEvent] {
        guard status == .running || status == .paused else { return [] }
        var events: [EngineEvent] = []
        advanceStep(reason: reason, &events)
        return events
    }

    private mutating func advanceStep(reason: TransitionReason, repsLogged: Int? = nil, _ events: inout [EngineEvent]) {
        recordCurrent(reason: reason, repsLogged: repsLogged)
        let next = currentIndex + 1
        if let loopRange = timeline.loopRange, next == loopRange.upperBound, !targetReached {
            loopIteration += 1
            events.append(.loopStarted(iteration: loopIteration))
            enter(loopRange.lowerBound, reason: reason, &events)
        } else if next < timeline.count {
            enter(next, reason: reason, &events)
        } else {
            complete(.finished, &events)
        }
    }

    /// Target reached: jump to whatever follows the loop (e.g. cool-down), or end.
    /// Already past the loop means the target changes nothing.
    private mutating func reachTarget(_ events: inout [EngineEvent]) {
        guard !targetReached else { return }
        targetReached = true
        events.append(.targetReached)
        if let postLoop = timeline.postLoopStart {
            guard currentIndex < postLoop else { return }
            recordCurrent(reason: .targetReached)
            enter(postLoop, reason: .targetReached, &events)
        } else {
            recordCurrent(reason: .targetReached)
            complete(.targetReached, &events)
        }
    }

    private mutating func enter(_ index: Int, reason: TransitionReason, _ events: inout [EngineEvent]) {
        currentIndex = index
        stepElapsed = 0
        stepStartOffset = totalElapsed
        stepStartDistance = totalDistance
        stepStartCalories = totalCalories
        events.append(.stepStarted(index: index, reason: reason))
    }

    private mutating func recordCurrent(reason: TransitionReason, repsLogged: Int? = nil) {
        guard let step = currentStep else { return }
        records.append(StepRecord(
            timelineIndex: step.index,
            loopIteration: loopIteration,
            kind: step.kind,
            blockIndex: step.blockIndex,
            round: step.round,
            startOffset: stepStartOffset,
            duration: stepElapsed,
            endReason: reason,
            distance: stepDistance,
            calories: stepCalories,
            repsLogged: repsLogged
        ))
    }

    private mutating func complete(_ reason: CompletionReason, _ events: inout [EngineEvent]) {
        status = .completed
        completionReason = reason
        events.append(.completed(reason: reason))
    }

    private func emitCues(from before: TimeInterval, to after: TimeInterval, _ events: inout [EngineEvent]) {
        guard after > before, let step = currentStep, let duration = step.end.fixedDuration else { return }
        if duration >= Self.halfwayMinimum {
            let half = duration / 2
            if before < half - Self.epsilon, after >= half - Self.epsilon {
                events.append(.halfway(index: step.index))
            }
        }
        for n in Self.countdownSeconds where duration > Double(n) {
            let mark = duration - Double(n)
            if before < mark - Self.epsilon, after >= mark - Self.epsilon {
                events.append(.countdown(index: step.index, secondsRemaining: n))
            }
        }
    }

    private static func fraction(_ value: Double, of total: Double) -> Double {
        guard total > 0 else { return 1 }
        return min(max(value / total, 0), 1)
    }
}
