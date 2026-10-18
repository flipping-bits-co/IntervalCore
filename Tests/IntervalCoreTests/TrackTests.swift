import Foundation
import Testing
@testable import IntervalCore

// MARK: - Helpers

private let pushEnrollment = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
private let sitEnrollment = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!
private let pullEnrollment = UUID(uuidString: "00000000-0000-4000-8000-0000000000A3")!

private func session(_ track: TrackDefinition, level: Int = 0, index: Int = 0) -> TrackSession {
    track.levels[level].sessions[index]
}

private func link(_ track: TrackDefinition, _ enrollment: UUID, level: Int = 0, index: Int = 0, restBefore: TimeInterval? = nil) -> TrackChainer.Link {
    TrackChainer.Link(
        enrollmentID: enrollment,
        trackName: track.name,
        session: session(track, level: level, index: index),
        leadInRest: track.leadInRest,
        restBefore: restBefore
    )
}

/// Runs a program to the end: timed steps run out, reps/open steps get Done with the count
/// `reps(step)` returns (`nil` = log the target). `skip` steps are skipped instead.
private func run(
    _ program: ProgramSnapshot,
    stopAt stopIndex: Int? = nil,
    skip: Set<Int> = [],
    reps: (TimelineStep) -> Int? = { _ in nil }
) -> IntervalEngine {
    var engine = IntervalEngine(program: program)
    engine.start(at: .testEpoch)
    while let step = engine.currentStep {
        if step.index == stopIndex {
            engine.finish()
            break
        }
        if skip.contains(step.index) {
            engine.skip()
        } else if let remaining = engine.stepRemaining {
            engine.advance(by: remaining)
        } else {
            engine.next(repsLogged: reps(step))
        }
    }
    return engine
}

private func workSteps(_ program: ProgramSnapshot, in ref: TrackRef) -> [TimelineStep] {
    program.compile().steps.filter { ref.blockIDs.contains($0.blockID) && $0.kind == .work }
}

// MARK: - Stable ids

struct StableUUIDTests {

    @Test func deterministicAndVersioned() {
        #expect(StableUUID.make("a") == StableUUID.make("a"))
        #expect(StableUUID.make("a") != StableUUID.make("b"))
        // Locked: changing these would orphan every enrolment.
        #expect(BundledTracks.ID.runWalk.uuidString == "F606C3C2-E861-840F-B7B7-B8121076089A")
        #expect(BundledTracks.ID.pushUps.uuidString == "7E0511A1-FA18-889D-A861-44E27D9405D0")
        let version = BundledTracks.ID.plank.uuidString.split(separator: "-")[2].first
        #expect(version == "8")
    }

    @Test func bundledIDsAreUnique() {
        var ids: [UUID] = []
        for track in BundledTracks.all {
            ids.append(track.id)
            for level in track.levels {
                ids.append(level.id)
                for session in level.sessions {
                    ids += [session.id, session.program.id]
                    for block in session.program.blocks {
                        ids.append(block.id)
                        ids += block.steps.map(\.id)
                    }
                }
            }
        }
        for program in TemplateCatalog.all {
            ids.append(program.id)
            ids += program.blocks.map(\.id)
        }
        #expect(Set(ids).count == ids.count)
    }

    @Test func catalogueIsTheSameEveryBuild() {
        // A rebuilt definition (as on another device) has identical ids and content.
        let rebuilt = BundledTracks.repTrack(
            key: "ember.track.pushups", id: BundledTracks.ID.pushUps, name: "Push-ups",
            summary: BundledTracks.pushUps.summary,
            question: BundledTracks.pushUps.assessment?.question ?? "",
            rest: 60, leadInRest: nil,
            levels: [
                .init(name: "A", summary: "0–5 push-ups", minReps: 0, groups: [("Push-ups", [2, 3, 2, 2, 3])], retestTarget: 6),
                .init(name: "B", summary: "6–10 push-ups", minReps: 6, groups: [("Push-ups", [6, 6, 4, 4, 5])], retestTarget: 11),
                .init(name: "C", summary: "11+ push-ups", minReps: 11, groups: [("Push-ups", [10, 12, 8, 8, 12])], retestTarget: 30),
            ]
        )
        #expect(rebuilt == BundledTracks.pushUps)
    }
}

// MARK: - Catalogue

struct BundledTracksTests {

    @Test func catalogue() {
        #expect(BundledTracks.all.map(\.name) == ["Run / Walk", "Push-ups", "Pull-ups", "Sit-ups", "Plank"])
        #expect(BundledTracks.definition(id: BundledTracks.ID.sitUps)?.name == "Sit-ups")
        #expect(BundledTracks.definition(id: UUID()) == nil)
        for track in BundledTracks.all {
            #expect(!track.levels.isEmpty)
            #expect(Set(track.levels.map(\.sessions.count)).count == 1, "levels of \(track.name) differ in length")
            for session in track.levels.flatMap(\.sessions) {
                #expect(!session.program.compile().isEmpty)
                #expect(session.program.activity == track.activity)
                #expect(!session.note.isEmpty)
            }
        }
    }

    @Test func runWalkIsCouchTo5K() {
        let track = BundledTracks.runWalk
        #expect(track.activity == .running)
        #expect(!track.isChainable)
        #expect(track.assessment == nil)
        #expect(track.sessionCount == 27)
        #expect(track.levels[0].weekCount == 9)
        let first = session(track).program.compile().steps
        #expect(first.first?.kind == .warmup)
        #expect(first.last?.kind == .cooldown)
        #expect(first.filter { $0.kind == .work }.count == 8)
        let last = session(track, index: 26)
        #expect(last.shortLabel == "W9 D3")
        #expect(last.program.compile().steps.filter { $0.kind == .work }.map(\.end) == [.time(1800)])
        #expect(track.levels[0].firstSessionIndex(week: 5) == 12)
        #expect(track.levels[0].firstSessionIndex(week: 10) == nil)
    }

    @Test func repTracksHaveLevelsAssessmentAndRetests() {
        for track in [BundledTracks.pushUps, BundledTracks.pullUps, BundledTracks.sitUps] {
            #expect(track.activity == .strength)
            #expect(track.isChainable)
            #expect(track.levels.map(\.name) == ["A", "B", "C"])
            #expect(track.sessionCount == 18)
            #expect(track.assessment?.bands.count == 3)
            let retests = track.levels[0].sessions.filter(\.isRetest).map(\.shortLabel)
            #expect(retests == ["W3 D3", "W6 D3"])
        }
    }

    @Test func pushUpSetsProgress() {
        let program = session(BundledTracks.pushUps).program
        let steps = program.compile().steps
        let work = steps.filter { $0.kind == .work }
        #expect(work.map(\.end) == [.reps(2), .reps(3), .reps(2), .reps(2), .reps(3)])
        #expect(work.last?.name == "Push-ups · max")
        #expect(steps.filter { $0.kind == .rest }.map(\.end) == Array(repeating: .time(60), count: 4))
        #expect(steps.last?.kind == .work)

        #expect(BundledTracks.reps(base: 2, week: 2, day: 2) == 3)
        #expect(BundledTracks.reps(base: 10, week: 6, day: 3) == 22)
        #expect(BundledTracks.reps(base: 0, week: 1, day: 1) == 1)
    }

    @Test func assessmentPicksLevel() throws {
        let track = BundledTracks.pushUps
        let assessment = try #require(track.assessment)
        let ids = track.levels.map(\.id)
        #expect(assessment.levelID(forMaxReps: 0) == ids[0])
        #expect(assessment.levelID(forMaxReps: 5) == ids[0])
        #expect(assessment.levelID(forMaxReps: 6) == ids[1])
        #expect(assessment.levelID(forMaxReps: 11) == ids[2])
        #expect(assessment.levelID(forMaxReps: 80) == ids[2])
        #expect(assessment.levelID(forMaxReps: -1) == ids[0])
        #expect(TrackAssessment(question: "", bands: []).levelID(forMaxReps: 3) == nil)
    }

    @Test func pullUpLevelAUsesAssistedAndNegatives() {
        let track = BundledTracks.pullUps
        #expect(track.leadInRest == 180)
        let program = session(track).program
        #expect(program.blocks.map(\.name) == ["Assisted pull-ups", "Negative pull-ups"])
        let steps = program.compile().steps
        // Rest between the two exercises survives skipLastRest.
        #expect(steps.filter { $0.kind == .work }.count == 6)
        #expect(steps.filter { $0.kind == .rest }.count == 5)
        #expect(steps.last?.name == "Negative pull-ups · max")
        #expect(session(track, level: 1).program.blocks.map(\.name) == ["Pull-ups"])
    }

    @Test func plankHoldsGrow() {
        let track = BundledTracks.plank
        #expect(track.assessment == nil)
        #expect(track.sessionCount == 12)
        #expect(track.minRestDays == 0)
        let holds = track.levels[0].sessions.compactMap { $0.program.compile().steps.first?.end }
        #expect(holds.count == 12)
        #expect(holds.first == .time(20))
        #expect(holds.last == .time(75))
    }
}

struct TemplateCatalogTests {

    @Test func templates() {
        #expect(TemplateCatalog.all.map(\.name) == ["30/30 Intervals", "4×4 Norwegian", "10-20-30", "Pyramid"])
        #expect(TemplateCatalog.thirtyThirty.id.uuidString == "6C1E0001-0000-4000-8000-000000000002")
        #expect(TemplateCatalog.norwegian4x4.estimatedDuration().seconds == 2400)  // 10:00 + 4 × 4:00 + 3 × 3:00 + 5:00
        #expect(TemplateCatalog.pyramid.estimatedDuration().seconds == 1330)  // 0:10 + 16:00 work + 6 × 1:00
        #expect(TemplateCatalog.tenTwentyThirty.estimatedDuration().seconds == 2040)  // 10:00 + 3 × 5:00 + 2 × 2:00 + 5:00
        #expect(TemplateCatalog.norwegian4x4.activity == .running)
    }

    @Test func debugUITestIsAWellKnownTestProgram() {
        let program = TemplateCatalog.debugUITest
        #expect(program.id == ProgramSnapshot.debugUITestProgramID)
        #expect(program.isTestProgram)
        #expect(!TemplateCatalog.all.contains { $0.id == program.id })

        let timeline = program.compile()
        #expect(timeline.steps.contains { $0.displayName == "Push-ups" })
        #expect(timeline.steps.filter { $0.displayName == "Push-ups" }.count == 3)
        #expect(timeline.steps.contains { $0.end.isHeartRate })
        #expect(timeline.steps.last?.end == .heartRateBelow(bpm: 120, maxWait: 40))

        let estimate = program.estimatedDuration()
        #expect(estimate.seconds >= 90 && estimate.seconds <= 150)
    }

    @Test func isTestProgramIsFalseForOrdinaryPrograms() {
        #expect(!Presets.tabata().isTestProgram)
        #expect(!TemplateCatalog.thirtyThirty.isTestProgram)
    }

    /// The id — the only thing the test-run check relies on — must survive the phone →
    /// Watch Codable trip with no new wire field.
    @Test func testProgramIdentitySurvivesRoundTrip() throws {
        let data = try JSONEncoder().encode(TemplateCatalog.debugUITest)
        let decoded = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
        #expect(decoded.isTestProgram)
        #expect(decoded.id == ProgramSnapshot.debugUITestProgramID)
    }
}

// MARK: - Chainer

struct TrackChainerTests {

    @Test func chainsWithARestBlockPerGap() {
        let links = [link(BundledTracks.pushUps, pushEnrollment), link(BundledTracks.pullUps, pullEnrollment)]
        let chain = TrackChainer.chain(links)
        let program = chain.program

        #expect(program.name == "Push-ups + Pull-ups")
        #expect(program.activity == .strength)
        #expect(program.trackRefs == chain.refs)
        #expect(program.blocks.count == 1 + 1 + 1 + 2)  // prepare, push, gap, assisted, negatives
        #expect(program.blocks[0].steps.first?.kind == .prepare)
        #expect(program.blocks[2].steps.map(\.end) == [.time(180)])
        #expect(program.blocks[2].steps.first?.kind == .rest)

        #expect(chain.gaps.count == 1)
        #expect(chain.gaps[0].seconds == 180)
        #expect(chain.gaps[0].source == .leadIn)
        #expect(chain.gaps[0].beforeEnrollmentID == pullEnrollment)
        #expect(chain.gaps[0].blockID == program.blocks[2].id)

        #expect(chain.refs.map(\.enrollmentID) == [pushEnrollment, pullEnrollment])
        #expect(chain.refs[0].blockIDs == session(BundledTracks.pushUps).program.blocks.map(\.id))
        #expect(chain.refs[1].blockIDs == session(BundledTracks.pullUps).program.blocks.map(\.id))
        #expect(chain.refs[0].label == "Push-ups · W1 D1")
        #expect(chain.refs[0].sessionID == session(BundledTracks.pushUps).id)
    }

    @Test func gapDefaults() {
        let push = link(BundledTracks.pushUps, pushEnrollment)
        let sit = link(BundledTracks.sitUps, sitEnrollment)
        func gap(_ link: TrackChainer.Link, _ lastUsed: TimeInterval?) -> String {
            let rest = TrackChainer.gapRest(before: link, lastUsed: lastUsed)
            return "\(Int(rest.seconds)) \(rest.source.rawValue)"
        }
        #expect(gap(sit, nil) == "120 fallback")
        #expect(gap(sit, 90) == "90 lastUsed")
        #expect(gap(link(BundledTracks.pullUps, pullEnrollment), 90) == "180 leadIn")
        #expect(gap(link(BundledTracks.pullUps, pullEnrollment, restBefore: 45), 90) == "45 userSet")

        let chain = TrackChainer.chain([push, sit], lastUsedGap: 75)
        #expect(chain.gaps.map(\.seconds) == [75])
    }

    @Test func zeroRestAddsNoBlock() {
        let chain = TrackChainer.chain(
            [link(BundledTracks.pushUps, pushEnrollment), link(BundledTracks.sitUps, sitEnrollment, restBefore: 0)],
            prepare: 0
        )
        #expect(chain.program.blocks.count == 2)
        #expect(chain.gaps.first?.blockID == nil)
        #expect(chain.gaps.first?.seconds == 0)
    }

    @Test func singleLinkIsTheSessionTagged() {
        let track = BundledTracks.runWalk
        let chain = TrackChainer.chain([link(track, pushEnrollment)], prepare: 0)
        #expect(chain.program.name == "Run / Walk · W1 D1")
        #expect(chain.program.activity == .running)
        #expect(chain.program.blocks == session(track).program.blocks)
        #expect(chain.gaps.isEmpty)
        #expect(chain.refs.count == 1)
    }

    @Test func deterministic() {
        let links = [link(BundledTracks.pushUps, pushEnrollment), link(BundledTracks.sitUps, sitEnrollment)]
        #expect(TrackChainer.chain(links) == TrackChainer.chain(links))
        #expect(TrackChainer.chain(links).program.id != TrackChainer.chain(Array(links.reversed())).program.id)
        #expect(TrackChainer.chain(links, name: "Today").program.name == "Today")
    }

    @Test func chainCodableRoundTrip() throws {
        let chain = TrackChainer.chain([link(BundledTracks.pushUps, pushEnrollment), link(BundledTracks.sitUps, sitEnrollment)])
        #expect(try JSONDecoder().decode(TrackChainer.Chain.self, from: JSONEncoder().encode(chain)) == chain)
    }
}

// MARK: - Outcome

struct TrackOutcomeTests {

    private let chain = TrackChainer.chain([
        link(BundledTracks.pushUps, pushEnrollment),
        link(BundledTracks.sitUps, sitEnrollment),
    ])

    private func evaluate(_ engine: IntervalEngine, autoRepeat: Bool = true, overrides: [UUID: Bool] = [:]) -> [TrackOutcome.Result] {
        TrackOutcome.evaluate(
            program: chain.program,
            records: engine.records,
            refs: chain.refs,
            autoRepeat: autoRepeat,
            autoRepeatOverrides: overrides
        )
    }

    @Test func allDoneAdvancesEveryTrack() {
        let outcomes = evaluate(run(chain.program))
        #expect(outcomes.map(\.decision) == [.advance, .advance])
        #expect(outcomes.allSatisfy { !$0.missed })
        #expect(outcomes[0].totalWorkSteps == 5)
        #expect(outcomes[0].completedWorkSteps == 5)
        #expect(outcomes[0].totalRepsLogged == 2 + 3 + 2 + 2 + 3)
        #expect(outcomes[0].maxRepsLogged == 3)
    }

    @Test func fewerRepsRepeatsOnlyThatTrack() {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        let engine = run(chain.program) { $0.index == pushWork[1].index ? 1 : nil }
        let outcomes = evaluate(engine)
        #expect(outcomes.map(\.decision) == [.repeat, .advance])
        #expect(outcomes[0].missed)
        #expect(outcomes[0].belowTargetWorkSteps == 1)
        #expect(outcomes[0].completedWorkSteps == 4)

        #expect(evaluate(engine, autoRepeat: false).map(\.decision) == [.advance, .advance])
        #expect(evaluate(engine, autoRepeat: false, overrides: [pushEnrollment: true]).map(\.decision) == [.repeat, .advance])
        #expect(evaluate(engine, autoRepeat: true, overrides: [pushEnrollment: false]).map(\.decision) == [.advance, .advance])
    }

    @Test func moreRepsThanTargetIsFine() {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        let engine = run(chain.program) { $0.index == pushWork.last?.index ? 9 : nil }
        let outcomes = evaluate(engine)
        #expect(outcomes[0].decision == .advance)
        #expect(outcomes[0].maxRepsLogged == 9)
    }

    @Test func skippedWorkStepIsAMiss() {
        let sitWork = workSteps(chain.program, in: chain.refs[1])
        let outcomes = evaluate(run(chain.program, skip: [sitWork[2].index]))
        #expect(outcomes.map(\.decision) == [.advance, .repeat])
        #expect(outcomes[1].skippedWorkSteps == 1)
    }

    @Test func skippedRestIsNotAMiss() {
        let steps = chain.program.compile().steps
        let pushRest = steps.first { chain.refs[0].blockIDs.contains($0.blockID) && $0.kind == .rest }
        let outcomes = evaluate(run(chain.program, skip: [pushRest?.index ?? -1]))
        #expect(outcomes.map(\.decision) == [.advance, .advance])
    }

    @Test func endingEarlyRepeatsTheCurrentTrackAndLeavesTheRest() {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        let outcomes = evaluate(run(chain.program, stopAt: pushWork[3].index))
        #expect(outcomes.map(\.decision) == [.repeat, .unchanged])
        #expect(outcomes[0].completedWorkSteps == 3)
        #expect(outcomes[0].skippedWorkSteps == 1)  // the set running when the workout ended
        #expect(outcomes[0].unfinishedWorkSteps == 1)
        #expect(!outcomes[1].missed)
        #expect(outcomes[1].completedWorkSteps == 0)
    }

    @Test func endingInTheGapAdvancesTheFinishedTrack() {
        let gapStep = chain.program.compile().steps.first { $0.blockID == chain.gaps[0].blockID }
        let outcomes = evaluate(run(chain.program, stopAt: gapStep?.index))
        #expect(outcomes.map(\.decision) == [.advance, .unchanged])
    }

    @Test func goingBackWithoutFinishingIsUnfinished() {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        var engine = IntervalEngine(program: chain.program)
        engine.start(at: .testEpoch)
        while engine.currentStep?.index != pushWork[1].index {
            if let remaining = engine.stepRemaining { engine.advance(by: remaining) } else { engine.next() }
        }
        engine.previous()  // back to the rest before set 2
        engine.finish()
        let outcomes = evaluate(engine)
        #expect(outcomes[0].unfinishedWorkSteps == 4)
        #expect(outcomes[0].decision == .repeat)
    }

    @Test func retestNeverRepeatsAndReportsMax() {
        let track = BundledTracks.pushUps
        let retestIndex = track.levels[0].sessions.firstIndex(where: \.isRetest) ?? 0
        let chain = TrackChainer.chain([link(track, pushEnrollment, index: retestIndex)])
        #expect(chain.refs[0].isRetest)
        let engine = run(chain.program) { _ in 4 }
        let outcome = TrackOutcome.evaluate(program: chain.program, records: engine.records, refs: chain.refs, autoRepeat: true)[0]
        #expect(outcome.missed)
        #expect(outcome.decision == .advance)
        #expect(outcome.maxRepsLogged == 4)
        #expect(track.assessment?.levelID(forMaxReps: outcome.maxRepsLogged ?? 0) == track.levels[0].id)
    }

    @Test func removedBlocksLeaveTheTrackUnchanged() {
        var program = chain.program
        program.blocks.removeAll { chain.refs[1].blockIDs.contains($0.id) }
        let engine = run(program)
        let outcomes = TrackOutcome.evaluate(program: program, records: engine.records, refs: chain.refs, autoRepeat: true)
        #expect(outcomes.map(\.decision) == [.advance, .unchanged])
        #expect(outcomes[1].totalWorkSteps == 0)
    }

    /// Builder edits ("Edit before start") that reorder blocks keep outcomes right.
    @Test func reorderedBlocksStillMap() {
        var program = chain.program
        program.blocks.reverse()
        let sitWork = workSteps(program, in: chain.refs[1])
        let engine = run(program) { $0.index == sitWork[0].index ? 0 : nil }
        let outcomes = TrackOutcome.evaluate(program: program, records: engine.records, refs: chain.refs, autoRepeat: true)
        #expect(outcomes.map(\.decision) == [.advance, .repeat])
    }

    @Test func overrideOnTheSummary() {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        let outcomes = evaluate(run(chain.program, stopAt: pushWork[0].index))
        #expect(outcomes[0].decision(repeatOverride: nil) == .repeat)
        #expect(outcomes[0].decision(repeatOverride: false) == .advance)
        #expect(outcomes[1].decision(repeatOverride: true) == .unchanged)
        let done = evaluate(run(chain.program))
        #expect(done[0].decision(repeatOverride: true) == .repeat)
    }

    /// A Watch-run chained workout comes back by file and still maps to its tracks.
    @Test func taggedResultRoundTripsFromTheWatch() throws {
        let pushWork = workSteps(chain.program, in: chain.refs[0])
        let engine = run(chain.program) { $0.index == pushWork[0].index ? 1 : nil }
        let result = SessionResult(
            sessionID: UUID(), program: chain.program, source: .watch, engine: engine,
            startDate: .testEpoch, endDate: .testEpoch.addingTimeInterval(engine.totalElapsed), heartRate: []
        )
        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        guard case .sessionResult(let received) = try WCMessage(fileData: data, metadata: metadata) else {
            Issue.record("not a result"); return
        }
        #expect(received.trackRefs == chain.refs)
        #expect(received.steps.map(\.repsLogged) == result.steps.map(\.repsLogged))
        #expect(TrackOutcome.evaluate(received, autoRepeat: true).map(\.decision) == [.repeat, .advance])
    }
}

// MARK: - Progress

struct TrackProgressTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!  // fixed zone so day maths is stable
        calendar.firstWeekday = 2  // weeks start Monday
        return calendar
    }()

    /// 2026-10-05 is a Monday.
    private func date(_ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!  // valid fixed date
    }

    private func progress(
        _ track: TrackDefinition = BundledTracks.pushUps,
        index: Int = 0,
        completions: [Date] = [],
        cadence: TrackCadence? = .selfPaced,
        now: Date
    ) -> TrackProgress {
        TrackProgress(
            definition: track, levelID: nil, nextSessionIndex: index,
            completions: completions, cadence: cadence, now: now, calendar: calendar
        )
    }

    @Test func nextSessionAndPercent() {
        let start = progress(now: date(5))
        #expect(start.level?.name == "A")
        #expect(start.nextSession?.shortLabel == "W1 D1")
        #expect(start.fractionComplete == 0)
        #expect(start.due == .due)

        let mid = progress(index: 9, now: date(5))
        #expect(mid.nextSession?.shortLabel == "W4 D1")
        #expect(mid.fractionComplete == 0.5)
        #expect(mid.completedSessions == 9)

        let done = progress(index: 40, now: date(5))
        #expect(done.isFinished)
        #expect(done.nextSessionIndex == 18)
        #expect(done.fractionComplete == 1)
        #expect(done.due == .finished)

        #expect(progress(index: -3, now: date(5)).nextSessionIndex == 0)
    }

    @Test func levelFallsBackToFirst() {
        let track = BundledTracks.sitUps
        let b = TrackProgress(definition: track, levelID: track.levels[1].id, nextSessionIndex: 0, now: date(5), calendar: calendar)
        #expect(b.level?.name == "B")
        let stale = TrackProgress(definition: track, levelID: UUID(), nextSessionIndex: 0, now: date(5), calendar: calendar)
        #expect(stale.level?.name == "A")
    }

    @Test func restDayHint() {
        // Done Monday evening; push-ups want a rest day, so Tuesday rests and Wednesday is due.
        let completions = [date(5, 19)]
        #expect(progress(completions: completions, now: date(6)).due == .resting(until: date(7, 0)))
        #expect(progress(completions: completions, now: date(7)).due == .due)
        #expect(!progress(completions: completions, now: date(6)).due.isDue)
        // Plank has no rest days.
        #expect(progress(BundledTracks.plank, completions: completions, now: date(6)).due == .due)
    }

    @Test func timesPerWeek() {
        let plank = BundledTracks.plank
        let three = [date(5), date(6), date(7)]
        #expect(progress(plank, completions: three, cadence: nil, now: date(8)).due == .weeklyGoalMet)
        #expect(progress(plank, completions: Array(three.prefix(2)), cadence: nil, now: date(8)).due == .due)
        // A new week (Monday the 12th) starts over.
        #expect(progress(plank, completions: three, cadence: nil, now: date(12)).due == .due)
    }

    @Test func weekdays() {
        let plank = BundledTracks.plank
        let cadence = TrackCadence.weekdays([.monday, .thursday])
        #expect(progress(plank, cadence: cadence, now: date(5)).due == .due)
        #expect(progress(plank, cadence: cadence, now: date(6)).due == .notScheduledToday(next: date(8, 0)))
        #expect(progress(plank, cadence: cadence, now: date(9)).due == .notScheduledToday(next: date(12, 0)))
        #expect(progress(plank, cadence: .weekdays([]), now: date(6)).due == .due)
        #expect(progress(plank, cadence: .timesPerWeek(0), now: date(6)).due == .due)
        #expect([Weekday.friday, .monday, .sunday].sorted() == [.sunday, .monday, .friday])
    }
}

// MARK: - Reps logging and back-compat

struct RepsLoggingTests {

    @Test func doneLogsTargetOrTheGivenCount() {
        var engine = makeEngine([block(step(.work, .reps(8)), step(.work, .reps(8)), step(.work, .open), step(.work, .open), work(10))])
        engine.next()
        engine.next(repsLogged: 5)
        engine.next()
        engine.next(repsLogged: -3)
        engine.skip()
        #expect(engine.records.map(\.repsLogged) == [8, 5, nil, 0, nil])
    }

    @Test func skippedRepsStepLogsNothing() {
        var engine = makeEngine([block(step(.work, .reps(8)), work(10))])
        engine.skip()
        #expect(engine.records.first?.repsLogged == nil)
    }

    @Test func stepRecordWireFormat() throws {
        let record = StepRecord(
            timelineIndex: 0, loopIteration: 1, kind: .work, blockIndex: 0, round: 1,
            startOffset: 0, duration: 12, endReason: .userAdvanced, distance: 0, calories: 0, repsLogged: 6
        )
        let data = try JSONEncoder().encode(record)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["n"] as? Int == 6)
        #expect(try JSONDecoder().decode(StepRecord.self, from: data) == record)

        var plain = record
        plain.repsLogged = nil
        let plainObject = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(plainObject["n"] == nil)
    }

    /// Records from builds before `repsLogged`.
    @Test func oldRecordDecodes() throws {
        let json = #"{"i":0,"k":"work","b":0,"r":1,"o":0,"d":12,"e":"userAdvanced"}"#
        let record = try JSONDecoder().decode(StepRecord.self, from: Data(json.utf8))
        #expect(record.repsLogged == nil)
    }
}

struct TrackRefCompatibilityTests {

    @Test func untaggedProgramsOmitTheKey() throws {
        let data = try JSONEncoder().encode(Presets.tabata())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["trackRefs"] == nil)
    }

    /// A program from an older build has no `trackRefs`.
    @Test func oldProgramDecodes() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Presets.emom())) as? [String: Any])
        object.removeValue(forKey: "trackRefs")
        let program = try JSONDecoder().decode(ProgramSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(program.trackRefs == nil)
        let start = SessionStart(program: program, requestedAt: .testEpoch)
        #expect(start.trackRefs.isEmpty)
    }

    @Test func startCarriesTags() throws {
        let chain = TrackChainer.chain([link(BundledTracks.pushUps, pushEnrollment)])
        let message = WCMessage.command(.start(SessionStart(program: chain.program, requestedAt: .testEpoch)))
        guard case .command(.start(let start)) = try WCMessage(dictionary: message.toDictionary()) else {
            Issue.record("not a start"); return
        }
        #expect(start.trackRefs == chain.refs)
    }

    @Test func minimalRefDecodes() throws {
        let json = #"{"enrollmentID":"00000000-0000-4000-8000-0000000000A1","sessionID":"00000000-0000-4000-8000-0000000000B1"}"#
        let ref = try JSONDecoder().decode(TrackRef.self, from: Data(json.utf8))
        #expect(ref.enrollmentID == pushEnrollment)
        #expect(ref.blockIDs.isEmpty)
        #expect(ref.label.isEmpty)
        #expect(!ref.isRetest)
    }

    @Test func definitionRoundTrips() throws {
        for track in BundledTracks.all {
            #expect(try JSONDecoder().decode(TrackDefinition.self, from: JSONEncoder().encode(track)) == track)
        }
        let cadences: [TrackCadence] = [.selfPaced, .timesPerWeek(3), .weekdays([.monday, .friday])]
        #expect(try JSONDecoder().decode([TrackCadence].self, from: JSONEncoder().encode(cadences)) == cadences)
    }
}
