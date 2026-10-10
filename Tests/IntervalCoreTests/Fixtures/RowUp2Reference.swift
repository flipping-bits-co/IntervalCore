// Reference copy of RowUp2's interval engine, used only as a parity oracle.
// Copied from RowUp2 Shared/ (IntervalManager, WorkoutSegment, SegmentType,
// PhaseTrigger, IntervalPhase) with types prefixed `Legacy` and @Observable removed.
// Don't change behaviour here; it stands for what RowUp2 ships.
import Foundation


enum LegacySegmentType: String, Codable, Sendable {
    case warmup
    case interval
    case cooldown

    var label: String {
        switch self {
        case .warmup:   return "Warmup"
        case .interval: return "Interval"
        case .cooldown: return "Cooldown"
        }
    }

    var iconName: String {
        switch self {
        case .warmup:   return "sun.max.fill"
        case .interval: return "repeat"
        case .cooldown: return "snowflake"
        }
    }
}


enum LegacyPhaseTrigger: String, Codable, Sendable, CaseIterable {
    case time
    case distance
    case strokes

    var label: String {
        switch self {
        case .time: "Time"
        case .distance: "Distance"
        case .strokes: "Strokes"
        }
    }
}


enum LegacyIntervalPhase: String, Codable, Sendable {
    case row
    case rest
}


struct LegacyWorkoutSegment: Codable, Identifiable, Sendable {
    var id: UUID
    var type: LegacySegmentType
    var rowTrigger: LegacyPhaseTrigger
    var rowDuration: TimeInterval
    var rowTargetValue: Double
    var restDuration: TimeInterval
    var repeats: Int
    var loopOnTarget: Bool

    init(
        id: UUID = UUID(),
        type: LegacySegmentType,
        rowTrigger: LegacyPhaseTrigger = .time,
        rowDuration: TimeInterval,
        rowTargetValue: Double = 0,
        restDuration: TimeInterval = 0,
        repeats: Int = 1,
        loopOnTarget: Bool = false
    ) {
        self.id = id
        self.type = type
        self.rowTrigger = rowTrigger
        self.rowDuration = rowDuration
        self.rowTargetValue = rowTargetValue
        self.restDuration = restDuration
        self.repeats = repeats
        self.loopOnTarget = loopOnTarget
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(LegacySegmentType.self, forKey: .type)
        rowTrigger = try container.decodeIfPresent(LegacyPhaseTrigger.self, forKey: .rowTrigger) ?? .time
        rowDuration = try container.decode(TimeInterval.self, forKey: .rowDuration)
        rowTargetValue = try container.decodeIfPresent(Double.self, forKey: .rowTargetValue) ?? 0
        restDuration = try container.decode(TimeInterval.self, forKey: .restDuration)
        repeats = try container.decode(Int.self, forKey: .repeats)
        loopOnTarget = try container.decodeIfPresent(Bool.self, forKey: .loopOnTarget) ?? false
    }

    var isMetricTriggered: Bool {
        rowTrigger != .time
    }

    var totalDuration: TimeInterval {
        guard !isMetricTriggered else { return restDuration * Double(repeats) }
        return (rowDuration + restDuration) * Double(repeats)
    }

    var phasesPerRepeat: Int {
        type == .interval && restDuration > 0 ? 2 : 1
    }

    var flatPhaseCount: Int {
        repeats * phasesPerRepeat
    }

    var rowPhaseSummary: String {
        switch rowTrigger {
        case .time:
            return Self.formatDuration(rowDuration)
        case .distance:
            return "\(Int(rowTargetValue))m"
        case .strokes:
            return "\(Int(rowTargetValue)) str"
        }
    }

    var durationSummary: String {
        switch type {
        case .warmup, .cooldown:
            return rowPhaseSummary
        case .interval:
            return "\(rowPhaseSummary) / \(Self.formatDuration(restDuration))"
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let m = total / 60
        let s = total % 60
        return s == 0 ? "\(m):00" : "\(m):\(String(format: "%02d", s))"
    }
}


final class LegacyIntervalManager {
    var currentPhase: LegacyIntervalPhase = .row
    var currentSegmentIndex: Int = 0
    var currentRepeat: Int = 1
    private(set) var cumulativeRound: Int = 1
    var phaseElapsed: TimeInterval = 0
    var phaseRemaining: TimeInterval
    var isComplete: Bool = false

    let segments: [LegacyWorkoutSegment]
    let hasTargetEndCondition: Bool
    let isHRTriggered: Bool
    let hrCeiling: Int
    let hrFloor: Int
    var waitingForHR: Bool = false
    private var targetReached: Bool = false
    private var currentBPM: Double = 0
    private var latestStrokes: Int = 0
    private var latestDistance: Double = 0
    private(set) var phaseStartStrokes: Int = 0
    private(set) var phaseStartDistance: Double = 0
    var onTransition: ((LegacyIntervalPhase) -> Void)?

    // Backward-compatible accessors used by snapshot/metrics consumers
    var currentRound: Int { currentRepeat }
    var totalRounds: Int { currentSegment?.repeats ?? 1 }

    var currentSegment: LegacyWorkoutSegment? {
        guard currentSegmentIndex < segments.count else { return nil }
        return segments[currentSegmentIndex]
    }

    var currentPhaseTrigger: LegacyPhaseTrigger {
        guard currentPhase == .row else { return .time }
        return currentSegment?.rowTrigger ?? .time
    }

    var isMetricTriggered: Bool {
        currentPhaseTrigger != .time
    }

    var phaseTargetValue: Double {
        currentSegment?.rowTargetValue ?? 0
    }

    var phaseCurrentMetricValue: Double {
        switch currentPhaseTrigger {
        case .time: return phaseElapsed
        case .distance: return latestDistance - phaseStartDistance
        case .strokes: return Double(latestStrokes - phaseStartStrokes)
        }
    }

    // Flat index of the current phase across all expanded segment phases.
    var flatPhaseIndex: Int {
        var index = 0
        for i in 0..<currentSegmentIndex {
            index += segments[i].flatPhaseCount
        }
        guard let seg = currentSegment else { return index }
        index += (currentRepeat - 1) * seg.phasesPerRepeat
        if currentPhase == .rest { index += 1 }
        return index
    }

    var totalFlatPhases: Int {
        segments.reduce(0) { $0 + $1.flatPhaseCount }
    }

    init(
        segments: [LegacyWorkoutSegment],
        hasTargetEndCondition: Bool = false,
        useHRTrigger: Bool = false,
        hrCeiling: Int = 145,
        hrFloor: Int = 120
    ) {
        self.segments = segments
        self.hasTargetEndCondition = hasTargetEndCondition
        self.isHRTriggered = useHRTrigger
        self.hrCeiling = hrCeiling
        self.hrFloor = hrFloor
        self.phaseRemaining = segments.first?.rowDuration ?? 0
        self.cumulativeRound = segments.first?.type == .warmup ? 0 : 1
    }

    func completeByTarget() {
        targetReached = true
    }

    func updateHeartRate(_ bpm: Double) {
        guard isHRTriggered, !isComplete, phaseElapsed > 0 else { return }
        guard currentSegment?.type == .interval else { return }
        currentBPM = bpm

        switch currentPhase {
        case .row:
            if bpm >= Double(hrCeiling) { advancePhase() }
        case .rest:
            if bpm <= Double(hrFloor) { advancePhase() }
        }
    }

    func updateMetrics(strokes: Int, distance: Double) {
        latestStrokes = strokes
        latestDistance = distance
        guard !isComplete, currentPhase == .row, isMetricTriggered else { return }

        switch currentPhaseTrigger {
        case .distance:
            if (distance - phaseStartDistance) >= phaseTargetValue {
                advancePhase()
            }
        case .strokes:
            if (strokes - phaseStartStrokes) >= Int(phaseTargetValue) {
                advancePhase()
            }
        case .time:
            break
        }
    }

    func tick(delta: TimeInterval) {
        guard !isComplete else { return }

        if isMetricTriggered {
            phaseElapsed += delta
            return
        }

        if isHRTriggered {
            phaseElapsed += delta
            phaseRemaining -= delta
            if phaseRemaining <= 0 {
                phaseRemaining = 0
                waitingForHR = true
                advancePhase()
            }
            return
        }

        var remaining = delta
        while remaining > 0 && !isComplete {
            let timeInPhase = min(remaining, phaseRemaining)
            phaseElapsed += timeInPhase
            phaseRemaining -= timeInPhase
            remaining -= timeInPhase

            if phaseRemaining <= 0 {
                advancePhase()
            }
        }
    }

    func skipPhase() {
        guard !isComplete else { return }
        advancePhase()
    }

    func reset() {
        currentPhase = .row
        currentSegmentIndex = 0
        currentRepeat = 1
        cumulativeRound = segments.first?.type == .warmup ? 0 : 1
        phaseElapsed = 0
        phaseRemaining = segments.first?.rowDuration ?? 0
        isComplete = false
        waitingForHR = false
        targetReached = false
        currentBPM = 0
        latestStrokes = 0
        latestDistance = 0
        phaseStartStrokes = 0
        phaseStartDistance = 0
    }

    private func advancePhase() {
        waitingForHR = false

        if targetReached {
            isComplete = true
            return
        }

        guard let seg = currentSegment else {
            isComplete = true
            return
        }

        switch currentPhase {
        case .row:
            if seg.type == .interval && seg.restDuration > 0 {
                currentPhase = .rest
                phaseElapsed = 0
                phaseRemaining = seg.restDuration
                onTransition?(.rest)
            } else {
                advanceToNextRepeatOrSegment()
            }

        case .rest:
            advanceToNextRepeatOrSegment()
        }
    }

    private func advanceToNextRepeatOrSegment() {
        guard let seg = currentSegment else {
            isComplete = true
            return
        }

        if currentRepeat < seg.repeats {
            currentRepeat += 1
            if seg.type != .warmup { cumulativeRound += 1 }
            currentPhase = .row
            phaseElapsed = 0
            phaseRemaining = seg.rowDuration
            snapshotMetrics()
            onTransition?(.row)
        } else {
            advanceToNextSegment()
        }
    }

    private func advanceToNextSegment() {
        let nextIndex = currentSegmentIndex + 1
        if nextIndex < segments.count {
            currentSegmentIndex = nextIndex
            currentRepeat = 1
            if segments[nextIndex].type != .warmup { cumulativeRound += 1 }
            currentPhase = .row
            phaseElapsed = 0
            phaseRemaining = segments[nextIndex].rowDuration
            snapshotMetrics()
            onTransition?(.row)
        } else if hasTargetEndCondition,
                  let loopIndex = segments.firstIndex(where: { $0.loopOnTarget }) {
            currentSegmentIndex = loopIndex
            currentRepeat = 1
            cumulativeRound += 1
            currentPhase = .row
            phaseElapsed = 0
            phaseRemaining = segments[loopIndex].rowDuration
            snapshotMetrics()
            onTransition?(.row)
        } else {
            isComplete = true
            onTransition?(.row)
        }
    }

    private func snapshotMetrics() {
        phaseStartStrokes = latestStrokes
        phaseStartDistance = latestDistance
    }
}

