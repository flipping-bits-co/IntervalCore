import Foundation
import Testing
@testable import IntervalCore

struct PresetsTests {

    @Test func tabataShape() {
        let program = Presets.tabata()
        #expect(program.name == "Tabata")
        let timeline = program.compile()
        #expect(timeline.steps.first?.kind == .prepare)
        #expect(timeline.steps.first?.end == .time(10))
        let body = timeline.steps.dropFirst()
        #expect(body.count == 15)
        #expect(body.filter { $0.kind == .work }.allSatisfy { $0.end == .time(20) })
        #expect(body.filter { $0.kind == .rest }.allSatisfy { $0.end == .time(10) })
        #expect(program.estimatedDuration() == DurationEstimate(seconds: 240, isEstimate: false))
    }

    @Test func workRestCustom() {
        let program = Presets.workRest(work: 45, rest: 15, rounds: 10, prepare: 0)
        #expect(program.name.isEmpty)
        #expect(program.displayName == "10×0:45/0:15")
        #expect(program.blocks.count == 1)
        #expect(program.compile().count == 19)
    }

    @Test func workRestWithoutRest() {
        let program = Presets.workRest(work: 30, rest: 0, rounds: 3)
        #expect(program.blocks.last?.steps.count == 1)
    }

    @Test func emomShape() {
        let program = Presets.emom(minutes: 12, prepare: 0)
        #expect(program.name == "EMOM 12")
        let steps = program.compile().steps
        #expect(steps.count == 12)
        #expect(steps.allSatisfy { $0.end == .time(60) && $0.displayName == "Minute" })
        #expect(steps.last?.round == 12)
    }

    @Test func amrapShape() {
        let program = Presets.amrap(duration: 15 * 60)
        #expect(program.name == "AMRAP 15:00")
        #expect(program.compile().steps.last?.end == .time(900))
        #expect(program.workoutEnd == .allBlocks)
    }

    @Test func forTimeShape() {
        let capped = Presets.forTime(cap: 20 * 60)
        #expect(capped.workoutEnd == .target(.time(1200)))
        #expect(capped.compile().steps.last?.end == .open)
        #expect(Presets.forTime().workoutEnd == .allBlocks)
    }

    @Test func presetEnumBuildsEveryCase() {
        for preset in Preset.allCases {
            let program = preset.makeProgram(activity: .rowing)
            #expect(program.activity == .rowing)
            #expect(!program.compile().isEmpty)
            #expect(!preset.label.isEmpty)
            #expect(preset.id == preset.rawValue)
        }
        #expect(Preset.tabata.makeProgram().name == "Tabata")
    }

    @Test func presetsRunToCompletion() {
        for preset in Preset.allCases {
            var engine = IntervalEngine(program: preset.makeProgram())
            engine.start(at: .testEpoch)
            engine.advance(by: 3600)
            if !engine.isComplete { engine.next() }
            #expect(engine.isComplete, "\(preset)")
        }
    }

    // MARK: - Ladder

    @Test func ladderValuesUpAndDown() {
        #expect(LadderGenerator.values(start: 60, step: 60, peak: 180, descending: true) == [60, 120, 180, 120, 60])
        #expect(LadderGenerator.values(start: 60, step: 60, peak: 180, descending: false) == [60, 120, 180])
    }

    @Test func ladderAlwaysEndsClimbOnPeak() {
        #expect(LadderGenerator.values(start: 30, step: 45, peak: 100, descending: false) == [30, 75, 100])
    }

    @Test func ladderDegenerateInputs() {
        #expect(LadderGenerator.values(start: 60, step: 0, peak: 180, descending: true) == [60])
        #expect(LadderGenerator.values(start: 200, step: 10, peak: 100, descending: true) == [200])
        #expect(LadderGenerator.values(start: 1, step: 0.001, peak: 1000, descending: false).count == LadderGenerator.maxRungs)
    }

    @Test func ladderBlockWithRatioRest() {
        let block = LadderGenerator.makeBlock(start: 60, step: 60, peak: 120, descending: true, rest: .ratio(0.5))
        #expect(block.name == "Ladder")
        let timeline = TimelineCompiler.compile([block])
        // 60/30, 120/60, 60 (final rest dropped)
        #expect(timeline.steps.map(\.end) == [.time(60), .time(30), .time(120), .time(60), .time(60)])
    }

    @Test func ladderBlockFixedRestAndMetrics() {
        let distance = LadderGenerator.makeBlock(metric: .distance, start: 200, step: 200, peak: 400, descending: false, rest: .fixed(60))
        #expect(distance.steps.map(\.end) == [.distance(meters: 200), .time(60), .distance(meters: 400), .time(60)])

        let reps = LadderGenerator.makeBlock(metric: .reps, start: 5, step: 5, peak: 10, descending: false, rest: .ratio(1))
        #expect(reps.steps.map(\.end) == [.reps(5), .reps(10)])

        let cals = LadderGenerator.makeBlock(metric: .calories, start: 10, step: 10, peak: 10, descending: false)
        #expect(cals.steps.map(\.end) == [.calories(10)])
    }
}
