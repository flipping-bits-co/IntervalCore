import Foundation
import Testing
@testable import IntervalCore

struct DurationFormatterTests {

    @Test func clock() {
        #expect(DurationFormatter.clock(0) == "0:00")
        #expect(DurationFormatter.clock(45) == "0:45")
        #expect(DurationFormatter.clock(59.9) == "0:59")
        #expect(DurationFormatter.clock(600) == "10:00")
        #expect(DurationFormatter.clock(3725) == "1:02:05")
        #expect(DurationFormatter.clock(-5) == "0:00")
    }

    @Test func countdownRoundsUp() {
        #expect(DurationFormatter.countdown(59.2) == "1:00")
        #expect(DurationFormatter.countdown(0.01) == "0:01")
        #expect(DurationFormatter.countdown(0) == "0:00")
    }

    @Test func short() {
        #expect(DurationFormatter.short(45) == "45s")
        #expect(DurationFormatter.short(60) == "1 min")
        #expect(DurationFormatter.short(1080) == "18 min")
        #expect(DurationFormatter.short(89) == "1 min")
        #expect(DurationFormatter.short(90) == "2 min")
        #expect(DurationFormatter.short(3600) == "1 h")
        #expect(DurationFormatter.short(3900) == "1 h 5 min")
    }

    @Test func estimatePrefix() {
        #expect(DurationFormatter.estimate(DurationEstimate(seconds: 1080, isEstimate: true)) == "~18 min")
        #expect(DurationFormatter.estimate(DurationEstimate(seconds: 1080, isEstimate: false)) == "18 min")
    }

    @Test func distance() {
        #expect(DurationFormatter.distance(400) == "400m")
        #expect(DurationFormatter.distance(1000) == "1 km")
        #expect(DurationFormatter.distance(1500) == "1.5 km")
        #expect(DurationFormatter.distance(10_000) == "10 km")
    }
}

struct EndConditionTests {

    @Test func helpers() {
        #expect(EndCondition.time(30).fixedDuration == 30)
        #expect(EndCondition.open.fixedDuration == nil)
        #expect(EndCondition.time(30).isTimed)
        #expect(EndCondition.reps(5).requiresUserAction)
        #expect(EndCondition.open.requiresUserAction)
        #expect(!EndCondition.time(5).requiresUserAction)
        #expect(EndCondition.heartRateAbove(bpm: 150, maxWait: 0).isHeartRate)
        #expect(EndCondition.heartRateAbove(bpm: 150, maxWait: 0).heartRateMaxWait == nil)
        #expect(EndCondition.heartRateBelow(bpm: 120, maxWait: 90).heartRateMaxWait == 90)
        #expect(EndCondition.time(5).heartRateMaxWait == nil)
        #expect(EndCondition.distance(meters: 1).isMetric)
        #expect(EndCondition.calories(1).isMetric)
        #expect(!EndCondition.open.isMetric)
    }

    @Test func summaries() {
        #expect(EndCondition.time(60).summary == "1:00")
        #expect(EndCondition.distance(meters: 500).summary == "500m")
        #expect(EndCondition.calories(15).summary == "15 kcal")
        #expect(EndCondition.reps(1).summary == "1 rep")
        #expect(EndCondition.reps(12).summary == "12 reps")
        #expect(EndCondition.open.summary == "Open")
        #expect(EndCondition.heartRateBelow(bpm: 120, maxWait: 0).summary == "HR ≤ 120")
        #expect(EndCondition.heartRateAbove(bpm: 160, maxWait: 0).summary == "HR ≥ 160")
    }

    @Test func kindsHaveLabelsAndIcons() {
        for kind in StepKind.allCases {
            #expect(!kind.label.isEmpty)
            #expect(!kind.iconName.isEmpty)
        }
        for activity in Activity.allCases {
            #expect(!activity.label.isEmpty)
        }
        #expect(Activity.running.supportsDistance)
        #expect(!Activity.hiit.supportsDistance)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let program = ProgramSnapshot(
            name: "Mixed",
            activity: .running,
            blocks: [
                IntervalBlock(name: "Main", steps: [
                    IntervalStep(kind: .work, name: "Hill", end: .distance(meters: 400)),
                    IntervalStep(kind: .rest, end: .heartRateBelow(bpm: 120, maxWait: 120)),
                    IntervalStep(kind: .work, end: .heartRateAbove(bpm: 170, maxWait: 0)),
                    IntervalStep(kind: .work, end: .reps(10)),
                    IntervalStep(kind: .work, end: .calories(20)),
                    IntervalStep(kind: .cooldown, end: .open),
                ], repeats: 3, skipLastRest: false, loopsUntilTarget: true),
            ],
            workoutEnd: .target(.distance(meters: 5000)),
            isPinned: true,
            lastUsedDate: Date(timeIntervalSinceReferenceDate: 12345)
        )
        let data = try JSONEncoder().encode(program)
        #expect(try JSONDecoder().decode(ProgramSnapshot.self, from: data) == program)
    }

    @Test func stepDisplayName() {
        #expect(IntervalStep(kind: .rest, name: "  ").displayName == "Rest")
        #expect(IntervalStep(kind: .work, name: "Burpees").displayName == "Burpees")
    }
}

struct ProgramNamerTests {

    @Test func designPlanExample() {
        let blocks = [
            block(step(.warmup, .time(600))),
            block(work(60), rest(60), repeats: 8),
            block(step(.cooldown, .time(300))),
        ]
        #expect(ProgramNamer.displayName(for: blocks) == "Warm-up + 8×1:00/1:00 + Cool-down")
    }

    @Test func prepareBlocksAreLeftOut() {
        #expect(Presets.workRest(work: 20, rest: 10, rounds: 8).displayName == "8×0:20/0:10")
    }

    @Test func singleStepUsesLabelAndSummary() {
        #expect(ProgramNamer.displayName(for: [block(work(1200))]) == "Work 20:00")
        #expect(ProgramNamer.displayName(for: [block(work(1200, "Run"))]) == "Run 20:00")
    }

    @Test func blockNameWins() {
        var b = block(work(60), rest(60), repeats: 4)
        b.name = "Hills"
        #expect(ProgramNamer.displayName(for: [b]) == "Hills")
    }

    @Test func multiStepSingleRound() {
        #expect(ProgramNamer.displayName(for: [block(work(30), step(.work, .reps(10)), rest(15))]) == "0:30/10 reps/0:15")
    }

    @Test func targetSuffix() {
        let blocks = [block(work(60), rest(30), loops: true)]
        #expect(ProgramNamer.displayName(for: blocks, workoutEnd: .target(.distance(meters: 5000))) == "1:00/0:30 until 5 km")
        #expect(ProgramNamer.displayName(for: blocks, workoutEnd: .target(.time(1200))) == "1:00/0:30 until 20:00")
        #expect(ProgramNamer.displayName(for: blocks, workoutEnd: .target(.calories(300))) == "1:00/0:30 until 300 kcal")
    }

    @Test func emptyFallsBack() {
        #expect(ProgramNamer.displayName(for: []) == "Workout")
        #expect(ProgramNamer.displayName(for: [block(step(.prepare, .time(10)))]) == "Workout")
    }

    @Test func snapshotUsesCustomNameFirst() {
        #expect(ProgramSnapshot(name: " Leg Day ", blocks: [block(work(60))]).displayName == " Leg Day ".trimmingCharacters(in: .whitespaces))
        #expect(ProgramSnapshot(blocks: [block(work(60))]).displayName == "Work 1:00")
    }
}

struct StructureHashTests {

    private func program(_ blocks: [IntervalBlock], activity: Activity = .hiit, end: WorkoutEnd = .allBlocks) -> ProgramSnapshot {
        ProgramSnapshot(activity: activity, blocks: blocks, workoutEnd: end)
    }

    @Test func ignoresIdsAndNames() {
        var a = program([block(work(60), rest(30), repeats: 8)])
        var b = program([block(work(60), rest(30), repeats: 8)])
        a.name = "Mine"
        b.blocks[0].name = "Intervals"
        #expect(a.structureHash == b.structureHash)
        #expect(a.structureHash.count == 16)
    }

    @Test func stableAcrossRuns() {
        // Fixed value: changing the hash would orphan every saved Recent.
        #expect(Presets.tabata().structureHash == Presets.tabata().structureHash)
        let canonical = StructureHash.canonical(blocks: [block(work(60))], workoutEnd: .allBlocks, activity: .hiit)
        #expect(canonical == "a:hiit|e:all|b:1,true,false[work,t60,]")
        #expect(program([block(work(60))]).structureHash == "919d7f2dbebc7eed")
    }

    @Test func treatsIntegralDoublesTheSame() {
        #expect(program([block(work(60))]).structureHash == program([block(work(60.0))]).structureHash)
        #expect(program([block(work(60))]).structureHash != program([block(work(60.5))]).structureHash)
    }

    @Test func sensitiveToStructure() {
        let base = program([block(work(60), rest(30), repeats: 8)])
        let variants = [
            program([block(work(60), rest(30), repeats: 7)]),
            program([block(work(61), rest(30), repeats: 8)]),
            program([block(work(60), rest(30), repeats: 8, skipLastRest: false)]),
            program([block(work(60), rest(30), repeats: 8, loops: true)]),
            program([block(work(60, "Burpees"), rest(30), repeats: 8)]),
            program([block(work(60), rest(30), repeats: 8)], activity: .rowing),
            program([block(work(60), rest(30), repeats: 8)], end: .target(.time(600))),
            program([block(rest(30), work(60), repeats: 8)]),
        ]
        for variant in variants {
            #expect(variant.structureHash != base.structureHash)
        }
    }

    @Test func coversEveryEndCondition() {
        let ends: [EndCondition] = [
            .time(1), .distance(meters: 1), .calories(1), .reps(1), .open,
            .heartRateBelow(bpm: 1, maxWait: 1), .heartRateAbove(bpm: 1, maxWait: 1),
        ]
        let targets: [WorkoutEnd] = [.allBlocks, .target(.time(1)), .target(.distance(meters: 1)), .target(.calories(1))]
        var hashes = Set<String>()
        for end in ends { hashes.insert(program([block(step(.work, end))]).structureHash) }
        for target in targets { hashes.insert(program([block(work(5))], end: target).structureHash) }
        #expect(hashes.count == ends.count + targets.count)
    }
}

struct DurationEstimatorTests {

    @Test func perCondition() {
        let a = EstimateAssumptions()
        #expect(DurationEstimator.estimate(.time(90), assumptions: a) == DurationEstimate(seconds: 90, isEstimate: false))
        #expect(DurationEstimator.estimate(.distance(meters: 1000), assumptions: a) == DurationEstimate(seconds: 360, isEstimate: true))
        #expect(DurationEstimator.estimate(.calories(10), assumptions: a) == DurationEstimate(seconds: 60, isEstimate: true))
        #expect(DurationEstimator.estimate(.reps(10), assumptions: a) == DurationEstimate(seconds: 30, isEstimate: true))
        #expect(DurationEstimator.estimate(.open, assumptions: a) == DurationEstimate(seconds: 60, isEstimate: true))
        #expect(DurationEstimator.estimate(.heartRateBelow(bpm: 120, maxWait: 120), assumptions: a) == DurationEstimate(seconds: 120, isEstimate: true))
        #expect(DurationEstimator.estimate(.heartRateAbove(bpm: 160, maxWait: 0), assumptions: a) == DurationEstimate(seconds: 90, isEstimate: true))
    }

    @Test func activityPaces() {
        #expect(EstimateAssumptions(activity: .rowing).secondsPerMeter == 0.25)
        #expect(EstimateAssumptions(activity: .cycling).secondsPerMeter == 0.144)
        #expect(EstimateAssumptions(activity: .walking).secondsPerMeter == 0.75)
        #expect(EstimateAssumptions(activity: .hiit).secondsPerMeter == 0.36)
    }

    @Test func allTimedIsExact() {
        let timeline = TimelineCompiler.compile([
            block(step(.warmup, .time(600))),
            block(work(60), rest(60), repeats: 8),
            block(step(.cooldown, .time(300))),
        ])
        #expect(DurationEstimator.estimate(timeline) == DurationEstimate(seconds: 600 + 15 * 60 + 300, isEstimate: false))
    }

    /// F8: one metric step makes the whole total an estimate.
    @Test func metricStepMarksTotalAsEstimate() {
        let program = ProgramSnapshot(activity: .running, blocks: [
            block(step(.warmup, .time(600))),
            block(step(.work, .distance(meters: 400)), rest(90), repeats: 6),
        ])
        let estimate = program.estimatedDuration()
        #expect(estimate.isEstimate)
        #expect(estimate.seconds == 600 + 6 * 144 + 5 * 90)
        #expect(DurationFormatter.estimate(estimate).hasPrefix("~"))
    }

    @Test func loopWithTimeTargetIsExact() {
        let timeline = TimelineCompiler.compile([
            block(step(.warmup, .time(300))),
            block(work(60), rest(30), loops: true),
            block(step(.cooldown, .time(300))),
        ], workoutEnd: .target(.time(1200)))
        #expect(DurationEstimator.estimate(timeline) == DurationEstimate(seconds: 1500, isEstimate: false))
    }

    @Test func loopWithMetricTargetIsEstimate() {
        let distance = TimelineCompiler.compile([block(work(60), rest(30), loops: true)], workoutEnd: .target(.distance(meters: 5000)))
        #expect(DurationEstimator.estimate(distance, assumptions: EstimateAssumptions(activity: .rowing)) == DurationEstimate(seconds: 1250, isEstimate: true))
        let calories = TimelineCompiler.compile([block(work(60), rest(30), loops: true)], workoutEnd: .target(.calories(100)))
        #expect(DurationEstimator.estimate(calories) == DurationEstimate(seconds: 600, isEstimate: true))
    }

    @Test func targetWithoutLoopActsAsCap() {
        let blocks = [block(work(600))]
        let capped = TimelineCompiler.compile(blocks, workoutEnd: .target(.time(300)))
        #expect(DurationEstimator.estimate(capped) == DurationEstimate(seconds: 300, isEstimate: false))
        let loose = TimelineCompiler.compile(blocks, workoutEnd: .target(.time(900)))
        #expect(DurationEstimator.estimate(loose) == DurationEstimate(seconds: 600, isEstimate: false))

        let shortRun = TimelineCompiler.compile(blocks, workoutEnd: .target(.distance(meters: 1000)))
        #expect(DurationEstimator.estimate(shortRun) == DurationEstimate(seconds: 360, isEstimate: true))
        let longRun = TimelineCompiler.compile(blocks, workoutEnd: .target(.calories(1000)))
        #expect(DurationEstimator.estimate(longRun) == DurationEstimate(seconds: 600, isEstimate: true))
    }

    @Test func forTimeEstimate() {
        #expect(Presets.forTime(cap: 1200, prepare: 0).estimatedDuration() == DurationEstimate(seconds: 60, isEstimate: true))
        #expect(Presets.forTime(prepare: 0).estimatedDuration(assumptions: EstimateAssumptions(openStepSeconds: 900)).seconds == 900)
    }
}
