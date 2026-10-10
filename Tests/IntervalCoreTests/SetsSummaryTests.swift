import Foundation
import Testing
@testable import IntervalCore

struct SetsSummaryTests {

    private func program(_ sets: [RepsSetBuilder.SetTarget], exercise: String = "Push-ups") -> ProgramSnapshot {
        ProgramSnapshot(activity: .strength, blocks: [RepsSetBuilder.block(exercise: exercise, sets: sets, rest: 60)])
    }

    /// Timed steps run out; reps steps get Done with `reps[i]` (nil = target) or are skipped.
    private func records(_ program: ProgramSnapshot, reps: [Int?] = [], skip: Set<Int> = [], stopAfterSets: Int? = nil) -> [StepRecord] {
        var engine = IntervalEngine(program: program)
        engine.start(at: .testEpoch)
        var set = 0
        while let step = engine.currentStep {
            if step.kind == .work {
                if set == stopAfterSets { engine.finish(); break }
                defer { set += 1 }
                if skip.contains(set) { engine.skip(); continue }
                if engine.stepRemaining == nil {
                    engine.next(repsLogged: reps.indices.contains(set) ? reps[set] : nil)
                    continue
                }
            }
            if let remaining = engine.stepRemaining { engine.advance(by: remaining) } else { engine.next() }
        }
        return engine.records
    }

    @Test func plannedFormats() {
        #expect(SetsSummary.planned(program([.reps(3), .reps(4), .reps(5), .reps(6), .max(atLeast: 8)])) == "3-4-5-6-8+")
        #expect(SetsSummary.planned(program(Array(repeating: .reps(10), count: 5))) == "5×10")
        #expect(SetsSummary.planned(program([.reps(8), .reps(8), .hold(20)])) == "8-8-20s")
        #expect(SetsSummary.planned(program([.reps(5), .hold(20), .hold(20), .hold(15)])) == "5-20s-20s-15s")
        #expect(SetsSummary.planned(program([.reps(5), .hold(90)])) == "5-1:30")
        #expect(SetsSummary.planned(program([.max(atLeast: 6)])) == "6+")
        #expect(SetsSummary.planned(program([.reps(12)])) == "12")
        #expect(SetsSummary.planned(ProgramSnapshot(blocks: [block(step(.work, .reps(5)), step(.work, .open))])) == "5-max")
        #expect(SetsSummary.planned(ProgramSnapshot(blocks: [block(step(.work, .reps(5)), step(.work, .calories(10)))])) == "5-10 kcal")
    }

    @Test func noRepsStepsGiveNil() {
        #expect(SetsSummary.planned(BundledTracks.plank.levels[0].sessions[0].program) == nil)
        #expect(SetsSummary.planned(BundledTracks.runWalk.levels[0].sessions[0].program) == nil)
        #expect(SetsSummary.logged([], program: BundledTracks.plank.levels[0].sessions[0].program) == nil)
        #expect(SetsSummary.planned(ProgramSnapshot()) == nil)
    }

    @Test func bundledSession() {
        #expect(SetsSummary.planned(BundledTracks.pushUps.levels[0].sessions[0].program) == "2-3-2-2-3+")
    }

    @Test func perTrackInsideAChain() {
        let push = BundledTracks.pushUps, sit = BundledTracks.sitUps
        let chain = TrackChainer.chain([
            TrackChainer.Link(enrollmentID: UUID(), trackName: push.name, session: push.levels[0].sessions[0]),
            TrackChainer.Link(enrollmentID: UUID(), trackName: sit.name, session: sit.levels[0].sessions[0]),
        ])
        #expect(SetsSummary.planned(chain.program, blockIDs: Set(chain.refs[0].blockIDs)) == "2-3-2-2-3+")
        #expect(SetsSummary.planned(chain.program, blockIDs: Set(chain.refs[1].blockIDs)) == "5-6-5-5-6+")
        #expect(SetsSummary.planned(chain.program) == "2-3-2-2-3+-5-6-5-5-6+")

        let done = records(chain.program, reps: [nil, 1])
        #expect(SetsSummary.logged(done, program: chain.program, blockIDs: Set(chain.refs[0].blockIDs)) == "2-1-2-2-3")
        #expect(SetsSummary.logged(done, program: chain.program, blockIDs: Set(chain.refs[1].blockIDs)) == "5-6-5-5-6")
    }

    @Test func loggedFormats() {
        let varied = program([.reps(3), .reps(4), .reps(5), .max(atLeast: 8)])
        #expect(SetsSummary.logged(records(varied), program: varied) == "3-4-5-8")
        #expect(SetsSummary.logged(records(varied, reps: [nil, 2, nil, 11]), program: varied) == "3-2-5-11")
        #expect(SetsSummary.logged(records(varied, skip: [1]), program: varied) == "3-–-5-8")
        #expect(SetsSummary.logged(records(varied, stopAfterSets: 2), program: varied) == "3-4-–-–")
        #expect(SetsSummary.logged([], program: varied) == "–-–-–-–")

        let equal = program(Array(repeating: .reps(10), count: 3))
        #expect(SetsSummary.logged(records(equal), program: equal) == "3×10")

        let mixed = program([.reps(8), .reps(8), .hold(20)])
        #expect(SetsSummary.logged(records(mixed), program: mixed) == "8-8-20s")
        #expect(SetsSummary.logged(records(mixed, skip: [2]), program: mixed) == "8-8-–")
    }

    @Test func maxMarker() {
        #expect(RepsSetBuilder.isMaxSet("Push-ups · max"))
        #expect(!RepsSetBuilder.isMaxSet("Push-ups"))
    }
}
