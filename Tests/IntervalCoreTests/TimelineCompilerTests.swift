import Foundation
import Testing
@testable import IntervalCore

struct TimelineCompilerTests {

    @Test func expandsBlocksTimesRepeats() {
        let timeline = TimelineCompiler.compile([
            block(step(.warmup, .time(600))),
            block(work(60), rest(60), repeats: 8, skipLastRest: false),
            block(step(.cooldown, .time(300))),
        ])

        #expect(timeline.count == 1 + 16 + 1)
        #expect(timeline.steps.map(\.index) == Array(0..<18))
        #expect(timeline.steps.first?.kind == .warmup)
        #expect(timeline.steps.last?.kind == .cooldown)

        let intervals = timeline.steps.filter { $0.blockIndex == 1 }
        #expect(intervals.map(\.kind) == Array(repeating: [StepKind.work, .rest], count: 8).flatMap { $0 })
        #expect(intervals.map(\.round) == (1...8).flatMap { [$0, $0] })
        #expect(intervals.allSatisfy { $0.totalRounds == 8 })
        #expect(intervals.map(\.stepIndex) == Array(repeating: [0, 1], count: 8).flatMap { $0 })
    }

    @Test func skipLastRestDropsFinalRoundRest() {
        let timeline = TimelineCompiler.compile([block(work(20), rest(10), repeats: 8)])
        #expect(timeline.count == 15)
        #expect(timeline.steps.last?.kind == .work)
        #expect(timeline.steps.last?.round == 8)
    }

    @Test func skipLastRestDropsOnlyTrailingRests() {
        let timeline = TimelineCompiler.compile([
            block(work(30), rest(10), work(30), rest(15), rest(5), repeats: 2),
        ])
        // Round 1: all five. Round 2: the two trailing rests go.
        #expect(timeline.count == 5 + 3)
        #expect(timeline.steps.suffix(3).map(\.kind) == [.work, .rest, .work])
    }

    @Test func skipLastRestKeepsAllRestBlock() {
        let timeline = TimelineCompiler.compile([block(rest(90))])
        #expect(timeline.count == 1)
        #expect(timeline.steps[0].kind == .rest)
    }

    @Test func skipLastRestOffKeepsFinalRest() {
        let timeline = TimelineCompiler.compile([block(work(20), rest(10), repeats: 2, skipLastRest: false)])
        #expect(timeline.steps.map(\.kind) == [.work, .rest, .work, .rest])
    }

    @Test func zeroOrNegativeRepeatsCompileOnce() {
        #expect(TimelineCompiler.compile([block(work(10), repeats: 0)]).count == 1)
        #expect(TimelineCompiler.compile([block(work(10), repeats: -3)]).count == 1)
    }

    @Test func emptyBlocksContributeNothing() {
        let timeline = TimelineCompiler.compile([IntervalBlock(), block(work(10))])
        #expect(timeline.count == 1)
        #expect(timeline.steps[0].blockIndex == 1)
        #expect(TimelineCompiler.compile([]).isEmpty)
    }

    @Test func carriesIdentityAndNames() {
        let s = IntervalStep(kind: .work, name: "Push-ups", end: .reps(10))
        let b = IntervalBlock(steps: [s])
        let compiled = TimelineCompiler.compile([b]).steps[0]
        #expect(compiled.blockID == b.id)
        #expect(compiled.stepID == s.id)
        #expect(compiled.displayName == "Push-ups")
        #expect(compiled.end == .reps(10))
        #expect(compiled.id == 0)
    }

    @Test func displayNameFallsBackToKindLabel() {
        let compiled = TimelineCompiler.compile([block(step(.cooldown, .time(5)))]).steps[0]
        #expect(compiled.displayName == "Cool-down")
    }

    // MARK: - Loop ranges

    @Test func loopRangeOnlyWithTarget() {
        let blocks = [block(work(10), rest(5), loops: true)]
        #expect(TimelineCompiler.compile(blocks).loopRange == nil)
        #expect(TimelineCompiler.compile(blocks, workoutEnd: .target(.distance(meters: 5000))).loopRange == 0..<2)
    }

    @Test func loopRangeSpansFirstToLastLoopBlock() {
        let timeline = TimelineCompiler.compile([
            block(step(.warmup, .time(300))),
            block(work(60), rest(30), repeats: 2, loops: true),
            block(work(10)),
            block(work(20), rest(10), loops: true),
            block(step(.cooldown, .time(300))),
        ], workoutEnd: .target(.time(1800)))

        // warm-up(1) | loop: 4 + 1 + 2 | cool-down(1)
        #expect(timeline.loopRange == 1..<8)
        #expect(timeline.postLoopStart == 8)
    }

    @Test func loopBlocksKeepFinalRest() {
        let timeline = TimelineCompiler.compile(
            [block(work(60), rest(30), repeats: 2, loops: true)],
            workoutEnd: .target(.calories(100))
        )
        #expect(timeline.steps.map(\.kind) == [.work, .rest, .work, .rest])
        #expect(timeline.postLoopStart == nil)
    }

    @Test func emptyLoopBlocksGiveNoRange() {
        let timeline = TimelineCompiler.compile(
            [block(work(10)), IntervalBlock(loopsUntilTarget: true)],
            workoutEnd: .target(.time(60))
        )
        #expect(timeline.loopRange == nil)
    }

    @Test func timelineRoundTripsThroughJSON() throws {
        let timeline = TimelineCompiler.compile(
            [block(work(60), rest(30), repeats: 2, loops: true), block(step(.cooldown, .open))],
            workoutEnd: .target(.time(600))
        )
        let data = try JSONEncoder().encode(timeline)
        #expect(try JSONDecoder().decode(Timeline.self, from: data) == timeline)
    }
}
