import Foundation

/// Which device ran the session.
public enum SessionSource: String, Codable, Hashable, Sendable {
    case phone
    case watch
}

/// Starts a session on the other device (phone → Watch start, or mirroring).
public struct SessionStart: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var program: ProgramSnapshot
    public var requestedAt: Date

    public init(sessionID: UUID = UUID(), program: ProgramSnapshot, requestedAt: Date) {
        self.sessionID = sessionID
        self.program = program
        self.requestedAt = requestedAt
    }

    /// The program's training-track tags (empty for ordinary programs).
    public var trackRefs: [TrackRef] { program.trackRefs ?? [] }
}

/// Remote-control actions, mirroring `IntervalEngine`'s user actions.
public enum SessionControl: String, Codable, Hashable, Sendable, CaseIterable {
    case pause
    case resume
    case next
    case skip
    case previous
    case restartStep
    case logRound
    case end
}

/// Commands between phone and Watch. Controls carry the session id so a late command
/// can't act on a newer session.
public enum SessionCommand: Codable, Hashable, Sendable {
    case start(SessionStart)
    case control(SessionControl, sessionID: UUID)
    /// Replaces the Watch's cached programs (pinned + recents).
    case syncPrograms([ProgramSnapshot])
    /// Phone → Watch: start or stop streaming HR (`WCMessage.heartRate`) for a
    /// phone-only session. RowUp2's `startHRStream` / `stopHRStream`.
    case heartRateStream(enabled: Bool)
    /// Phone → Watch: play this preset's work-start pattern now ("Test on Watch").
    /// `sendMessage` only; a test that arrives late is pointless, so it's never queued.
    case testHaptic(HapticPreset)
    /// Phone → Watch: play one event's haptic now (Customize → Test). `feel` is the override to
    /// try; `nil` plays `preset`'s own pattern for `event` ("Default"). `sendMessage` only, like
    /// `testHaptic`.
    case testHapticCue(HapticCueEvent, feel: HapticFeel?, preset: HapticPreset)
    /// Watch → phone: the user changed haptics on the Watch. The phone stores them (ignoring
    /// an update older than its own last change) and syncs them back in `WatchSettings` as usual.
    case watchHapticsChanged(WatchHaptics, changedAt: Date)
}

/// One live HR reading, Watch → phone, for phone-only sessions.
public struct HeartRateReading: Codable, Hashable, Sendable {
    public var bpm: Double
    public var timestamp: Date

    public init(bpm: Double, timestamp: Date) {
        self.bpm = bpm
        self.timestamp = timestamp
    }
}

/// Live state streamed from the device running the session (about 1 Hz via `sendMessage`).
public struct LiveSample: Codable, Hashable, Sendable {
    public var sessionID: UUID
    public var timestamp: Date
    public var status: IntervalEngine.Status
    public var stepIndex: Int
    public var loopIteration: Int
    public var stepElapsed: TimeInterval
    /// `nil` for steps that don't end on time.
    public var stepRemaining: TimeInterval?
    public var totalElapsed: TimeInterval
    public var heartRate: Double?
    public var totalDistance: Double
    public var totalCalories: Double
    public var loggedRounds: Int
    /// Time left in the whole workout, as the runner computed it, so the mirror shows the
    /// same figure. `nil` from builds before it existed.
    public var overallRemaining: DurationEstimate?

    public init(
        sessionID: UUID,
        timestamp: Date,
        status: IntervalEngine.Status,
        stepIndex: Int,
        loopIteration: Int,
        stepElapsed: TimeInterval,
        stepRemaining: TimeInterval?,
        totalElapsed: TimeInterval,
        heartRate: Double?,
        totalDistance: Double,
        totalCalories: Double,
        loggedRounds: Int,
        overallRemaining: DurationEstimate? = nil
    ) {
        self.sessionID = sessionID
        self.timestamp = timestamp
        self.status = status
        self.stepIndex = stepIndex
        self.loopIteration = loopIteration
        self.stepElapsed = stepElapsed
        self.stepRemaining = stepRemaining
        self.totalElapsed = totalElapsed
        self.heartRate = heartRate
        self.totalDistance = totalDistance
        self.totalCalories = totalCalories
        self.loggedRounds = loggedRounds
        self.overallRemaining = overallRemaining
    }

    /// Snapshot of an engine's current state. Pass the program's assumptions
    /// (`EstimateAssumptions(activity:)`) so `overallRemaining` uses the right paces.
    public init(sessionID: UUID, engine: IntervalEngine, timestamp: Date, assumptions: EstimateAssumptions = .init()) {
        self.init(
            sessionID: sessionID,
            timestamp: timestamp,
            status: engine.status,
            stepIndex: engine.currentIndex,
            loopIteration: engine.loopIteration,
            stepElapsed: engine.stepElapsed,
            stepRemaining: engine.stepRemaining,
            totalElapsed: engine.totalElapsed,
            heartRate: engine.heartRate,
            totalDistance: engine.totalDistance,
            totalCalories: engine.totalCalories,
            loggedRounds: engine.loggedRounds,
            overallRemaining: engine.remainingEstimate(assumptions: assumptions)
        )
    }
}

/// A finished session, sent to the phone via `transferFile` (`WCMessage.fileTransfer()`) for History.
public struct SessionResult: Codable, Hashable, Identifiable, Sendable {
    public var sessionID: UUID
    public var program: ProgramSnapshot
    public var source: SessionSource
    public var startDate: Date
    public var endDate: Date
    public var completionReason: CompletionReason
    /// Time excluding pauses (`IntervalEngine.totalElapsed`).
    public var activeDuration: TimeInterval
    public var totalDistance: Double
    public var totalCalories: Double
    public var loggedRounds: Int
    public var steps: [StepRecord]
    /// Downsampled HR on the same active-time axis as `steps`, for zones and charts.
    public var heartRate: [HeartRateSample]
    /// Set by the Watch once its `HKWorkoutBuilder` finished successfully, so the phone
    /// doesn't save the same workout to Health twice. Absent in older payloads → `false`.
    public var savedToHealth: Bool

    public var id: UUID { sessionID }

    public init(
        sessionID: UUID,
        program: ProgramSnapshot,
        source: SessionSource,
        startDate: Date,
        endDate: Date,
        completionReason: CompletionReason,
        activeDuration: TimeInterval,
        totalDistance: Double = 0,
        totalCalories: Double = 0,
        loggedRounds: Int = 0,
        steps: [StepRecord] = [],
        heartRate: [HeartRateSample] = [],
        savedToHealth: Bool = false
    ) {
        self.sessionID = sessionID
        self.program = program
        self.source = source
        self.startDate = startDate
        self.endDate = endDate
        self.completionReason = completionReason
        self.activeDuration = activeDuration
        self.totalDistance = totalDistance
        self.totalCalories = totalCalories
        self.loggedRounds = loggedRounds
        self.steps = steps
        self.heartRate = heartRate
        self.savedToHealth = savedToHealth
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        program = try c.decode(ProgramSnapshot.self, forKey: .program)
        source = try c.decode(SessionSource.self, forKey: .source)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        completionReason = try c.decode(CompletionReason.self, forKey: .completionReason)
        activeDuration = try c.decode(TimeInterval.self, forKey: .activeDuration)
        totalDistance = try c.decode(Double.self, forKey: .totalDistance)
        totalCalories = try c.decode(Double.self, forKey: .totalCalories)
        loggedRounds = try c.decode(Int.self, forKey: .loggedRounds)
        steps = try c.decode([StepRecord].self, forKey: .steps)
        heartRate = try c.decode([HeartRateSample].self, forKey: .heartRate)
        savedToHealth = try c.decodeIfPresent(Bool.self, forKey: .savedToHealth) ?? false
    }

    /// Builds the result from a finished (or stopped) engine.
    public init(
        sessionID: UUID,
        program: ProgramSnapshot,
        source: SessionSource,
        engine: IntervalEngine,
        startDate: Date,
        endDate: Date,
        heartRate: [HeartRateSample],
        savedToHealth: Bool = false
    ) {
        self.init(
            sessionID: sessionID,
            program: program,
            source: source,
            startDate: startDate,
            endDate: endDate,
            completionReason: engine.completionReason ?? .stopped,
            activeDuration: engine.totalElapsed,
            totalDistance: engine.totalDistance,
            totalCalories: engine.totalCalories,
            loggedRounds: engine.loggedRounds,
            steps: engine.records,
            heartRate: heartRate,
            savedToHealth: savedToHealth
        )
    }

    /// Training-track tags of the program that ran (empty for ordinary programs). They travel
    /// inside `program`, so results from older Watch builds simply have none.
    public var trackRefs: [TrackRef] { program.trackRefs ?? [] }

    public var averageHeartRate: Int? {
        guard !heartRate.isEmpty else { return nil }
        let sum = heartRate.reduce(0) { $0 + $1.bpm }
        return Int((Double(sum) / Double(heartRate.count)).rounded())
    }

    public var maxHeartRate: Int? { heartRate.map(\.bpm).max() }
    public var minHeartRate: Int? { heartRate.map(\.bpm).min() }
}
