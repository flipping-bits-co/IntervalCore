import Foundation
import Testing
@testable import IntervalCore

private func record(
    _ index: Int,
    kind: StepKind,
    block: Int = 0,
    round: Int = 1,
    loop: Int = 1,
    start: TimeInterval,
    duration: TimeInterval,
    distance: Double = 0,
    calories: Double = 0
) -> StepRecord {
    StepRecord(
        timelineIndex: index, loopIteration: loop, kind: kind, blockIndex: block, round: round,
        startOffset: start, duration: duration, endReason: .timeElapsed, distance: distance, calories: calories
    )
}

private func hr(_ offset: Int, _ bpm: Int, step: Int) -> HeartRateSample {
    HeartRateSample(offset: offset, bpm: bpm, stepIndex: step)
}

/// The design plan's 3-block workout: warm-up, 3 × (work/rest), cool-down, run to completion.
private func threeBlockStats() -> SessionStats {
    let program = ProgramSnapshot(blocks: [
        IntervalBlock(steps: [IntervalStep(kind: .warmup, end: .time(60))]),
        IntervalBlock(steps: [IntervalStep(kind: .work, end: .time(30)), IntervalStep(kind: .rest, end: .time(15))], repeats: 3),
        IntervalBlock(steps: [IntervalStep(kind: .cooldown, end: .time(40))]),
    ])
    let t0 = Date(timeIntervalSinceReferenceDate: 0)
    var engine = IntervalEngine(program: program)
    var sampler = HeartRateDownsampler()
    engine.start(at: t0)
    sampler.add(bpm: 110, offset: 0, stepIndex: 0)
    var second = 0
    while !engine.isComplete {
        second += 1
        engine.tick(at: t0.addingTimeInterval(Double(second)))
        guard let step = engine.currentStep else { break }
        let bpm: Double = switch step.kind {
        case .warmup: 110
        case .work: 160
        case .rest: 130
        default: 100
        }
        sampler.add(bpm: bpm, offset: engine.totalElapsed, stepIndex: engine.currentIndex)
        engine.updateMetrics(distance: Double(second) * 3, calories: Double(second) / 6)
    }
    return SessionStats(steps: engine.records, heartRate: sampler.finish())
}

struct SessionStatsTests {

    // MARK: - Blocks and rounds

    @Test func threeBlockBreakdown() {
        let stats = threeBlockStats()
        #expect(stats.blocks.map(\.blockIndex) == [0, 1, 2])
        let expectedDurations: [TimeInterval] = [60, 120, 40]  // 3 × 30 work + 2 × 15 rest
        #expect(stats.blocks.map(\.total.duration) == expectedDurations)
        #expect(stats.blocks.map(\.total.stepCount) == [1, 5, 1])
        #expect(stats.blocks[1].rounds.count == 3)
        #expect(stats.total.duration == 220)
        // 18 work samples at 160, 6 rest samples at 130 → 152.5.
        #expect(stats.blocks.map(\.total.averageHeartRate) == [110, 153, 100])
        #expect(stats.blocks[1].total.maxHeartRate == 160)
        #expect(abs(stats.blocks.reduce(0) { $0 + $1.total.distance } - stats.total.distance) < 1e-9)
    }

    @Test func roundSplits() {
        let rounds = threeBlockStats().rounds
        #expect(rounds.map(\.sequence) == [1, 2, 3, 4, 5])
        let intervals = rounds.filter { $0.blockIndex == 1 }
        #expect(intervals.map(\.round) == [1, 2, 3])
        #expect(intervals.map { $0.work?.duration } == [30, 30, 30])
        #expect(intervals.map { $0.rest?.duration } == [15, 15, nil])  // skipLastRest
        #expect(intervals.allSatisfy { $0.work?.averageHeartRate == 160 })
        #expect(intervals.first?.rest?.averageHeartRate == 130)
        #expect(rounds.first?.work == nil)
    }

    @Test func distanceAndCaloriesAggregate() {
        let stats = SessionStats(steps: [
            record(0, kind: .work, start: 0, duration: 120, distance: 400, calories: 20),
            record(1, kind: .rest, start: 120, duration: 60, distance: 50, calories: 4),
            record(2, kind: .work, round: 2, start: 180, duration: 115, distance: 400, calories: 21),
        ])
        #expect(stats.total.distance == 850)
        #expect(stats.total.calories == 45)
        #expect(stats.rounds.map { $0.work?.distance } == [400, 400])
        #expect(stats.byKind.map(\.kind) == [.work, .rest])
        #expect(stats.byKind.first?.stats.duration == 235)
        #expect(stats.total.averageHeartRate == nil)
        #expect(stats.total.maxHeartRate == nil)
    }

    @Test func previousRepeatsMergeIntoTheirRound() {
        // Round 1 work, rest, then previous() back into rest, then round 2 work.
        let stats = SessionStats(steps: [
            record(0, kind: .work, start: 0, duration: 30),
            record(1, kind: .rest, start: 30, duration: 4),
            record(0, kind: .work, start: 34, duration: 30),
            record(1, kind: .rest, start: 64, duration: 15),
            record(2, kind: .work, round: 2, start: 79, duration: 30),
        ])
        #expect(stats.rounds.count == 2)
        #expect(stats.rounds[0].work?.duration == 60)
        #expect(stats.rounds[0].rest?.duration == 19)
        #expect(stats.rounds[0].total.stepCount == 4)
    }

    @Test func loopPassesAreSeparateRounds() {
        let stats = SessionStats(steps: [
            record(0, kind: .work, loop: 1, start: 0, duration: 60),
            record(1, kind: .rest, loop: 1, start: 60, duration: 30),
            record(0, kind: .work, loop: 2, start: 90, duration: 60),
            record(1, kind: .rest, loop: 2, start: 150, duration: 30),
            record(0, kind: .work, loop: 3, start: 180, duration: 20),
        ], heartRate: [hr(10, 150, step: 0), hr(100, 170, step: 0), hr(190, 180, step: 0)])
        #expect(stats.rounds.map(\.loopIteration) == [1, 2, 3])
        #expect(stats.rounds.map(\.sequence) == [1, 2, 3])
        #expect(stats.rounds.map { $0.work?.averageHeartRate } == [150, 170, 180])
        #expect(stats.blocks.count == 1)
        #expect(stats.blocks[0].rounds.count == 3)
    }

    @Test func perStepStats() {
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 10), record(1, kind: .rest, start: 10, duration: 10)],
            heartRate: [hr(0, 140, step: 0), hr(5, 150, step: 0), hr(10, 120, step: 1)]
        )
        #expect(stats.perStep.map(\.stats.averageHeartRate) == [145, 120])
        #expect(stats.perStep.map(\.record.kind) == [.work, .rest])
    }

    @Test func emptySession() {
        let stats = SessionStats(steps: [])
        #expect(stats.total == SegmentStats())
        #expect(stats.rounds.isEmpty)
        #expect(stats.blocks.isEmpty)
        #expect(stats.byKind.isEmpty)
        #expect(stats.zoneBreakdown(HeartRateZones(maxHeartRate: 190)).isEmpty)
    }

    @Test func fromResult() {
        let result = SessionResult(
            sessionID: UUID(), program: ProgramSnapshot(), source: .phone,
            startDate: .testEpoch, endDate: .testEpoch, completionReason: .finished, activeDuration: 10,
            steps: [record(0, kind: .work, start: 0, duration: 10)],
            heartRate: [hr(0, 150, step: 0)]
        )
        #expect(SessionStats(result: result).total.averageHeartRate == 150)
    }

    // MARK: - Sample assignment

    @Test func sampleOnRestartEdgeGoesToLaterRecord() {
        // restartStep() at t = 20: two records of step 0 share the edge.
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 20), record(0, kind: .work, start: 20, duration: 30)],
            heartRate: [hr(20, 170, step: 0)]
        )
        #expect(stats.perStep.map(\.stats.averageHeartRate) == [nil, 170])
    }

    @Test func samplesOutsideAnyRecordAreIgnored() {
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 10)],
            heartRate: [hr(50, 150, step: 0), hr(5, 140, step: 3)]
        )
        #expect(stats.total.averageHeartRate == nil)
        #expect(stats.zoneBreakdown(HeartRateZones(maxHeartRate: 200)).isEmpty)
    }

    @Test func unsortedSamplesAreSorted() {
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 10)],
            heartRate: [hr(5, 150, step: 0), hr(0, 140, step: 0)]
        )
        #expect(stats.heartRate.map(\.offset) == [0, 5])
    }

    // MARK: - Zones

    @Test func zoneBoundariesMatchRowUp2() {
        let zones = HeartRateZones(maxHeartRate: 200)
        #expect(zones.zoneCount == 6)
        #expect(zones.zone(for: 99) == 0)
        #expect(zones.zone(for: 100) == 1)
        #expect(zones.zone(for: 119) == 1)
        #expect(zones.zone(for: 120) == 2)
        #expect(zones.zone(for: 140) == 3)
        #expect(zones.zone(for: 160) == 4)
        #expect(zones.zone(for: 180) == 5)
        #expect(zones.zone(for: 230) == 5)
        #expect(zones.zone(for: 0) == nil)
        #expect(HeartRateZones(maxHeartRate: 0).zone(for: 120) == nil)
    }

    @Test func zoneHelpers() {
        let zones = HeartRateZones(age: 40)
        #expect(zones.maxHeartRate == 180)
        #expect(zones.bpmRange(zone: 0) == (0, 90))
        #expect(abs(zones.bpmRange(zone: 3).lower - 126) < 1e-9)
        #expect(abs((zones.bpmRange(zone: 3).upper ?? 0) - 144) < 1e-9)
        #expect(zones.bpmRange(zone: 5).upper == nil)

        let custom = HeartRateZones(maxHeartRate: 200, lowerBounds: [0.85, 0.6])
        #expect(custom.lowerBounds == [0.6, 0.85])
        #expect(custom.zone(for: 150) == 1)
        #expect(custom.zone(for: 175) == 2)
    }

    @Test func zoneTimePerKind() {
        let zones = HeartRateZones(maxHeartRate: 200)
        let stats = SessionStats(
            steps: [
                record(0, kind: .work, start: 0, duration: 20),
                record(1, kind: .rest, start: 20, duration: 12),
            ],
            heartRate: [
                hr(0, 150, step: 0),   // Z3 for 5 s
                hr(5, 165, step: 0),   // Z4 for 5 s
                hr(10, 185, step: 0),  // Z5 for 10 s (no sample until the rest starts at 20)
                hr(20, 150, step: 1),  // Z3 for 12 s, to the end of rest
            ]
        )
        let breakdown = stats.zoneBreakdown(zones)
        #expect(breakdown.map(\.kind) == [.work, .rest])
        #expect(breakdown[0].seconds == [0, 0, 0, 5, 5, 10])
        #expect(breakdown[1].seconds == [0, 0, 0, 12, 0, 0])
        #expect(breakdown[0].total == 20)
        #expect(breakdown[0].fraction(zone: 5) == 0.5)
        #expect(breakdown[0].fraction(zone: 9) == 0)
        #expect(stats.totalZoneTime(zones) == [0, 0, 0, 17, 5, 10])
    }

    @Test func sensorGapsAreNotCredited() {
        let zones = HeartRateZones(maxHeartRate: 200)
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 300)],
            heartRate: [hr(0, 150, step: 0), hr(200, 150, step: 0)]
        )
        // Each sample covers at most 15 s; the 200 s dropout counts nowhere.
        #expect(stats.totalZoneTime(zones)[3] == 30)
        #expect(SessionStats(steps: stats.steps, heartRate: stats.heartRate, maxSampleSpan: 1000).totalZoneTime(zones)[3] == 300)
    }

    @Test func sampleAtStepEndAddsNoZoneTime() {
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 10)],
            heartRate: [hr(10, 150, step: 0)]
        )
        // Counted in the step's HR average, but it covers no time.
        #expect(stats.total.averageHeartRate == 150)
        #expect(stats.zoneBreakdown(HeartRateZones(maxHeartRate: 200)).isEmpty)
    }

    /// Interim-review regression: with a real Watch feed (one reading every few seconds at an
    /// arbitrary phase), the head of each step before its first reading used to count in no
    /// zone. Rest lost up to half its time.
    @Test(arguments: [(period: 5.0, phase: 0.4), (period: 5.0, phase: 1.7), (period: 5.0, phase: 2.3), (period: 5.0, phase: 4.9), (period: 1.0, phase: 0.5)])
    func zoneTimeCoversRealisticFeed(period: Double, phase: Double) {
        let t0 = Date.testEpoch
        var engine = IntervalEngine(program: Presets.tabata(prepare: 0))
        var sampler = HeartRateDownsampler()
        engine.start(at: t0)
        var nextReading = phase
        var tick = 0
        while !engine.isComplete {
            tick += 1
            engine.tick(at: t0.addingTimeInterval(Double(tick) * 0.1))
            if engine.totalElapsed >= nextReading - 1e-9, !engine.isComplete {
                let bpm: Double = engine.currentStep?.kind == .work ? 170 : 125
                sampler.add(bpm: bpm, offset: engine.totalElapsed, stepIndex: engine.currentIndex)
                nextReading += period
            }
        }
        let stats = SessionStats(steps: engine.records, heartRate: sampler.finish())
        let zones = HeartRateZones(maxHeartRate: 190)
        let total = stats.totalZoneTime(zones).reduce(0, +)
        #expect(stats.total.duration == 230)
        #expect(total >= stats.total.duration - phase.rounded(.up) - 1, "zone total \(total)")
        // ≥ 95% of the time HR was actually known (from the first reading on).
        #expect(total >= 0.95 * (stats.total.duration - phase), "zone total \(total)")
        let rest = stats.zoneBreakdown(zones).first { $0.kind == .rest }?.total ?? 0
        #expect(rest >= 70 - 2, "rest zone time \(rest)")
    }

    @Test func carryInStopsAtMaxSampleSpan() {
        let zones = HeartRateZones(maxHeartRate: 200)
        let stats = SessionStats(
            steps: [record(0, kind: .work, start: 0, duration: 10), record(1, kind: .rest, start: 10, duration: 30)],
            heartRate: [hr(8, 170, step: 0)]
        )
        // The work reading covers 8...10 in work, then carries 13 s into rest (8 + 15 = 23).
        let breakdown = stats.zoneBreakdown(zones)
        #expect(breakdown.first { $0.kind == .work }?.total == 2)
        #expect(breakdown.first { $0.kind == .rest }?.seconds[4] == 13)
    }

    @Test func bpmRangeClampsZone() {
        let zones = HeartRateZones(maxHeartRate: 200)
        #expect(zones.bpmRange(zone: -1) == zones.bpmRange(zone: 0))
        #expect(zones.bpmRange(zone: 99) == zones.bpmRange(zone: 5))
    }

    @Test func emptyZoneTimeFractionIsZero() {
        #expect(ZoneTime(kind: .work, seconds: [0, 0]).fraction(zone: 0) == 0)
    }

    @Test func threeBlockZonesCoverAllHRTime() {
        let stats = threeBlockStats()
        let zones = HeartRateZones(maxHeartRate: 190)
        let breakdown = stats.zoneBreakdown(zones)
        #expect(breakdown.map(\.kind) == [.warmup, .work, .rest, .cooldown])
        // 160 / 190 = 84% → Z4 for all 90 s of work.
        #expect(breakdown.first { $0.kind == .work }?.seconds[4] == 90)
        let total = stats.totalZoneTime(zones).reduce(0, +)
        #expect(total == stats.total.duration)
    }

    @Test func statsTypesRoundTripJSON() throws {
        let stats = threeBlockStats()
        let blocks = stats.blocks
        #expect(try JSONDecoder().decode([BlockStats].self, from: JSONEncoder().encode(blocks)) == blocks)
        let zones = stats.zoneBreakdown(HeartRateZones(maxHeartRate: 190))
        #expect(try JSONDecoder().decode([ZoneTime].self, from: JSONEncoder().encode(zones)) == zones)
        let kinds = stats.byKind
        #expect(try JSONDecoder().decode([KindStats].self, from: JSONEncoder().encode(kinds)) == kinds)
        let steps = stats.perStep
        #expect(try JSONDecoder().decode([StepStats].self, from: JSONEncoder().encode(steps)) == steps)
        let z = HeartRateZones(maxHeartRate: 180)
        #expect(try JSONDecoder().decode(HeartRateZones.self, from: JSONEncoder().encode(z)) == z)
    }
}
