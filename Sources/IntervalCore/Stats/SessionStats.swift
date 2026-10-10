import Foundation

/// Totals for any group of steps: a single step, a round, a block, or a step kind.
public struct SegmentStats: Codable, Hashable, Sendable {
    public var duration: TimeInterval
    public var distance: Double
    public var calories: Double
    /// Mean of the HR samples that fall inside the group's steps.
    public var averageHeartRate: Int?
    /// Highest ~5 s bucket average, so single-reading spikes are smoothed.
    public var maxHeartRate: Int?
    public var stepCount: Int

    public init(
        duration: TimeInterval = 0,
        distance: Double = 0,
        calories: Double = 0,
        averageHeartRate: Int? = nil,
        maxHeartRate: Int? = nil,
        stepCount: Int = 0
    ) {
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.stepCount = stepCount
    }
}

/// One round of one block (one loop pass), for the summary's per-round splits.
public struct RoundStats: Codable, Hashable, Sendable {
    /// 1-based position in the order rounds were first run (use for "Round N" across loops).
    public var sequence: Int
    public var blockIndex: Int
    public var round: Int
    public var loopIteration: Int
    public var total: SegmentStats
    /// `.work` steps only; `nil` when the round had none.
    public var work: SegmentStats?
    /// `.rest` steps only; `nil` when the round had none.
    public var rest: SegmentStats?
}

/// One block across all its rounds and loop passes.
public struct BlockStats: Codable, Hashable, Sendable {
    public var blockIndex: Int
    public var total: SegmentStats
    public var rounds: [RoundStats]
}

public struct StepStats: Codable, Hashable, Sendable {
    public var record: StepRecord
    public var stats: SegmentStats
}

public struct KindStats: Codable, Hashable, Sendable {
    public var kind: StepKind
    public var stats: SegmentStats
}

/// Seconds in each HR zone for one step kind.
public struct ZoneTime: Codable, Hashable, Sendable {
    public var kind: StepKind
    /// Indexed by zone (`HeartRateZones.zone(for:)`).
    public var seconds: [TimeInterval]

    public var total: TimeInterval { seconds.reduce(0, +) }

    /// 0...1 share of this kind's HR time spent in `zone`.
    public func fraction(zone: Int) -> Double {
        let total = total
        guard total > 0, seconds.indices.contains(zone) else { return 0 }
        return seconds[zone] / total
    }
}

/// Breakdowns of a finished session. Pure: works the same from a `SessionResult`
/// (History) or straight from `engine.records` plus a `HeartRateDownsampler` (live summary).
public struct SessionStats: Hashable, Sendable {
    public var steps: [StepRecord]
    public var heartRate: [HeartRateSample]
    /// Longest stretch one HR sample may stand for. Larger gaps mean the sensor dropped
    /// out, and that time shouldn't land in any zone.
    public var maxSampleSpan: TimeInterval

    /// HR samples per step record (same positions as `steps`). Each sample belongs to
    /// exactly one record.
    private let samplesByStep: [[HeartRateSample]]

    public init(steps: [StepRecord], heartRate: [HeartRateSample] = [], maxSampleSpan: TimeInterval = 15) {
        self.steps = steps
        self.heartRate = heartRate.sorted { $0.offset < $1.offset }
        self.maxSampleSpan = maxSampleSpan
        var buckets = Array(repeating: [HeartRateSample](), count: steps.count)
        for sample in self.heartRate {
            if let position = Self.position(of: sample, in: steps) { buckets[position].append(sample) }
        }
        self.samplesByStep = buckets
    }

    public init(result: SessionResult, maxSampleSpan: TimeInterval = 15) {
        self.init(steps: result.steps, heartRate: result.heartRate, maxSampleSpan: maxSampleSpan)
    }

    // MARK: - Groupings

    public var total: SegmentStats { stats(for: Array(steps.indices)) }

    /// Each step record with its own stats, in run order.
    public var perStep: [StepStats] {
        steps.indices.map { StepStats(record: steps[$0], stats: stats(for: [$0])) }
    }

    /// Rounds in the order first run. Repeats of a step caused by `previous()` merge into
    /// the round they belong to.
    public var rounds: [RoundStats] {
        struct Key: Hashable { var block: Int, round: Int, loop: Int }
        let groups = orderedGroups { Key(block: $0.blockIndex, round: $0.round, loop: $0.loopIteration) }
        return groups.enumerated().map { offset, group in
            let work = group.positions.filter { steps[$0].kind == .work }
            let rest = group.positions.filter { steps[$0].kind == .rest }
            return RoundStats(
                sequence: offset + 1,
                blockIndex: group.key.block,
                round: group.key.round,
                loopIteration: group.key.loop,
                total: stats(for: group.positions),
                work: work.isEmpty ? nil : stats(for: work),
                rest: rest.isEmpty ? nil : stats(for: rest)
            )
        }
    }

    /// Blocks in the order first run, each with its rounds.
    public var blocks: [BlockStats] {
        let rounds = rounds
        return orderedGroups(by: \.blockIndex).map { group in
            BlockStats(
                blockIndex: group.key,
                total: stats(for: group.positions),
                rounds: rounds.filter { $0.blockIndex == group.key }
            )
        }
    }

    /// Totals per step kind, in `StepKind.allCases` order, for kinds that ran.
    public var byKind: [KindStats] {
        StepKind.allCases.compactMap { kind in
            let positions = steps.indices.filter { steps[$0].kind == kind }
            return positions.isEmpty ? nil : KindStats(kind: kind, stats: stats(for: positions))
        }
    }

    // MARK: - HR zones

    /// Time in each zone per step kind, for kinds with any HR time.
    ///
    /// Integrated per step window. The latest reading at or before the window start
    /// (from any step) carries in until the first reading inside the window, which also
    /// matches HR lag across a transition. Each reading then runs to the next one or to
    /// the window end. A reading never covers more than `maxSampleSpan` past its own
    /// offset, so sensor dropouts count nowhere. Time before the session's first reading
    /// is unknown and isn't credited.
    public func zoneBreakdown(_ zones: HeartRateZones) -> [ZoneTime] {
        let attributed = heartRate.filter { Self.position(of: $0, in: steps) != nil }
        var seconds: [StepKind: [TimeInterval]] = [:]

        for record in steps {
            let start = record.startOffset
            let end = start + record.duration
            var current = attributed.last { Double($0.offset) <= start }
            var cursor = start
            let inside = attributed.filter { Double($0.offset) > start && Double($0.offset) < end }

            for next in inside.map(Optional.some) + [nil] {
                let segmentEnd = next.map { Double($0.offset) } ?? end
                if let current, let zone = zones.zone(for: Double(current.bpm)) {
                    let span = min(segmentEnd, Double(current.offset) + maxSampleSpan) - cursor
                    if span > 0 {
                        seconds[record.kind, default: Array(repeating: 0, count: zones.zoneCount)][zone] += span
                    }
                }
                cursor = segmentEnd
                if let next { current = next }
            }
        }
        return StepKind.allCases.compactMap { kind in
            seconds[kind].map { ZoneTime(kind: kind, seconds: $0) }
        }
    }

    /// All kinds combined.
    public func totalZoneTime(_ zones: HeartRateZones) -> [TimeInterval] {
        zoneBreakdown(zones).reduce(into: Array(repeating: 0, count: zones.zoneCount)) { totals, time in
            for zone in totals.indices { totals[zone] += time.seconds[zone] }
        }
    }

    // MARK: - Internals

    func stats(for positions: [Int]) -> SegmentStats {
        let records = positions.map { steps[$0] }
        let bpms = positions.flatMap { samplesByStep[$0].map(\.bpm) }
        return SegmentStats(
            duration: records.reduce(0) { $0 + $1.duration },
            distance: records.reduce(0) { $0 + $1.distance },
            calories: records.reduce(0) { $0 + $1.calories },
            averageHeartRate: bpms.isEmpty ? nil : Int((Double(bpms.reduce(0, +)) / Double(bpms.count)).rounded()),
            maxHeartRate: bpms.max(),
            stepCount: records.count
        )
    }

    /// The record a sample was taken in: same timeline step, inside its time window
    /// (which separates loop passes and `previous()` repeats). On a shared edge the
    /// later record wins, since the sample's offset is where that record begins.
    static func position(of sample: HeartRateSample, in steps: [StepRecord]) -> Int? {
        // Offsets are whole seconds, so allow rounding at both edges.
        let t = Double(sample.offset)
        return steps.lastIndex { record in
            sample.stepIndex == record.timelineIndex
                && t >= record.startOffset.rounded(.down)
                && t <= (record.startOffset + record.duration).rounded(.up)
        }
    }

    private func orderedGroups<Key: Hashable>(by key: (StepRecord) -> Key) -> [(key: Key, positions: [Int])] {
        var groups: [(key: Key, positions: [Int])] = []
        var slot: [Key: Int] = [:]
        for position in steps.indices {
            let k = key(steps[position])
            if let existing = slot[k] {
                groups[existing].positions.append(position)
            } else {
                slot[k] = groups.count
                groups.append((k, [position]))
            }
        }
        return groups
    }
}
