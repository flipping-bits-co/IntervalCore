import Foundation

/// The launch track catalogue (Phase 7 plan §6): Run / Walk, Push-ups, Pull-ups, Sit-ups,
/// Plank. Built in code with `StableUUID` ids for every track, level, session, block and step,
/// so ids never change between launches, devices, or app versions unless the content does.
public enum BundledTracks {

    /// Bump with any content change, together with the changed tracks' `version`.
    public static let version = 1

    public enum ID {
        public static let runWalk = StableUUID.make("ember.track.runwalk")
        public static let pushUps = StableUUID.make("ember.track.pushups")
        public static let pullUps = StableUUID.make("ember.track.pullups")
        public static let sitUps = StableUUID.make("ember.track.situps")
        public static let plank = StableUUID.make("ember.track.plank")
    }

    public static let all: [TrackDefinition] = [runWalk, pushUps, pullUps, sitUps, plank]

    public static func definition(id: UUID) -> TrackDefinition? {
        all.first { $0.id == id }
    }

    // MARK: - Run / Walk

    /// Couch-to-5K style: 9 weeks × 3 sessions, 5:00 brisk walk each side.
    public static let runWalk: TrackDefinition = {
        let key = "ember.track.runwalk"
        let weeks: [[[RunWalk]]] = [
            [[.repeating(8, [.run(60), .walk(90)])]],
            [[.repeating(6, [.run(90), .walk(120)])]],
            [[.repeating(2, [.run(90), .walk(90), .run(180), .walk(180)])]],
            [[.run(180), .walk(90), .run(300), .walk(150), .run(180), .walk(90), .run(300)]],
            [
                [.repeating(3, [.run(300), .walk(180)])],
                [.run(480), .walk(300), .run(480)],
                [.run(1200)],
            ],
            [
                [.run(300), .walk(180), .run(480), .walk(180), .run(300)],
                [.run(600), .walk(180), .run(600)],
                [.run(1500)],
            ],
            [[.run(1500)]],
            [[.run(1680)]],
            [[.run(1800)]],
        ]
        let levelKey = "\(key)/level/all"
        var sessions: [TrackSession] = []
        for (w, days) in weeks.enumerated() {
            for d in 0..<3 {
                let plan = days[min(d, days.count - 1)]
                let sessionKey = "\(levelKey)/w\(w + 1)d\(d + 1)"
                let program = ProgramSnapshot(
                    name: "Run / Walk · W\(w + 1) D\(d + 1)",
                    activity: .running,
                    blocks: [IntervalBlock(steps: [IntervalStep(kind: .warmup, name: "Brisk walk", end: .time(300))])]
                        + RunWalk.blocks(plan)
                        + [IntervalBlock(steps: [IntervalStep(kind: .cooldown, name: "Walk", end: .time(300))])]
                )
                sessions.append(TrackSession(
                    id: StableUUID.make(sessionKey),
                    week: w + 1,
                    day: d + 1,
                    note: RunWalk.note(plan),
                    program: program.withStableIDs(sessionKey)
                ))
            }
        }
        return TrackDefinition(
            id: ID.runWalk,
            name: "Run / Walk",
            summary: "From 1-minute runs to 30 minutes non-stop in 9 weeks, 3 runs a week.",
            activity: .running,
            levels: [TrackLevel(id: StableUUID.make(levelKey), name: "All levels", sessions: sessions)],
            cadence: .timesPerWeek(3),
            minRestDays: 1
        )
    }()

    // MARK: - Rep tracks

    public static let pushUps = repTrack(
        key: "ember.track.pushups",
        id: ID.pushUps,
        name: "Push-ups",
        summary: "5 sets a session over 6 weeks. A quick test picks your level.",
        question: "How many push-ups can you do in one go, with good form?",
        rest: 60,
        leadInRest: nil,
        levels: [
            RepLevel(name: "A", summary: "0–5 push-ups", minReps: 0, groups: [("Push-ups", [2, 3, 2, 2, 3])], retestTarget: 6),
            RepLevel(name: "B", summary: "6–10 push-ups", minReps: 6, groups: [("Push-ups", [6, 6, 4, 4, 5])], retestTarget: 11),
            RepLevel(name: "C", summary: "11+ push-ups", minReps: 11, groups: [("Push-ups", [10, 12, 8, 8, 12])], retestTarget: 30),
        ]
    )

    /// Level A builds strength with assisted and negative reps (owner request).
    public static let pullUps = repTrack(
        key: "ember.track.pullups",
        id: ID.pullUps,
        name: "Pull-ups",
        summary: "6 weeks of sets. Can't do one yet? Level A starts with assisted and negative reps.",
        question: "How many pull-ups can you do in one go, from a dead hang?",
        rest: 90,
        leadInRest: 180,
        levels: [
            RepLevel(
                name: "A",
                summary: "0–1 pull-ups · assisted & negatives",
                minReps: 0,
                groups: [("Assisted pull-ups", [3, 3, 3]), ("Negative pull-ups", [2, 2, 2])],
                retestTarget: 2,
                note: "Assisted: use a band or a chair. Negatives: jump to the top, lower for 5 seconds."
            ),
            RepLevel(name: "B", summary: "2–5 pull-ups", minReps: 2, groups: [("Pull-ups", [2, 2, 1, 1, 2])], retestTarget: 6),
            RepLevel(name: "C", summary: "6+ pull-ups", minReps: 6, groups: [("Pull-ups", [5, 5, 4, 4, 5])], retestTarget: 12),
        ]
    )

    public static let sitUps = repTrack(
        key: "ember.track.situps",
        id: ID.sitUps,
        name: "Sit-ups",
        summary: "5 sets a session over 6 weeks. A quick test picks your level.",
        question: "How many sit-ups can you do in one go?",
        rest: 60,
        leadInRest: nil,
        levels: [
            RepLevel(name: "A", summary: "0–15 sit-ups", minReps: 0, groups: [("Sit-ups", [5, 6, 5, 5, 6])], retestTarget: 16),
            RepLevel(name: "B", summary: "16–30 sit-ups", minReps: 16, groups: [("Sit-ups", [10, 12, 10, 10, 12])], retestTarget: 31),
            RepLevel(name: "C", summary: "31+ sit-ups", minReps: 31, groups: [("Sit-ups", [18, 20, 18, 18, 22])], retestTarget: 60),
        ]
    )

    // MARK: - Plank

    /// 4 weeks × 3 sessions of 3 holds, +5 s every session (0:20 → 1:15).
    public static let plank: TrackDefinition = {
        let key = "ember.track.plank"
        let levelKey = "\(key)/level/all"
        var sessions: [TrackSession] = []
        for index in 0..<12 {
            let week = index / 3 + 1, day = index % 3 + 1
            let hold = TimeInterval(20 + 5 * index)
            let sessionKey = "\(levelKey)/w\(week)d\(day)"
            let program = ProgramSnapshot(
                name: "Plank · W\(week) D\(day)",
                activity: .strength,
                blocks: [RepsSetBuilder.block(exercise: "Plank", sets: Array(repeating: .hold(hold), count: 3), rest: 60)]
            )
            sessions.append(TrackSession(
                id: StableUUID.make(sessionKey),
                week: week,
                day: day,
                note: "3 holds of \(DurationFormatter.clock(hold)), 1:00 rest. Straight line from head to heels.",
                program: program.withStableIDs(sessionKey)
            ))
        }
        return TrackDefinition(
            id: ID.plank,
            name: "Plank",
            summary: "Timed holds that grow 5 seconds every session, over 4 weeks.",
            activity: .strength,
            levels: [TrackLevel(id: StableUUID.make(levelKey), name: "All levels", sessions: sessions)],
            cadence: .timesPerWeek(3),
            minRestDays: 0
        )
    }()

    // MARK: - Builders

    struct RepLevel {
        var name: String
        var summary: String
        var minReps: Int
        /// Week 1 Day 1 sets per exercise. The last set of the last group is a max set.
        var groups: [(exercise: String, sets: [Int])]
        /// The re-test's "at least" target: reaching it qualifies for the next level.
        var retestTarget: Int
        var note: String = ""
    }

    static let weeks = 6
    /// Week 3 Day 3 and Week 6 Day 3 are max-reps re-tests.
    static let retestWeeks: Set<Int> = [3, 6]

    /// Sets grow 20% a week and by one rep per day within a week.
    static func reps(base: Int, week: Int, day: Int) -> Int {
        max(1, Int((Double(base) * (1 + 0.2 * Double(week - 1))).rounded()) + day - 1)
    }

    static func repTrack(
        key: String,
        id: UUID,
        name: String,
        summary: String,
        question: String,
        rest: TimeInterval,
        leadInRest: TimeInterval?,
        levels specs: [RepLevel]
    ) -> TrackDefinition {
        var levels: [TrackLevel] = []
        var bands: [TrackAssessment.Band] = []
        let exercise = name
        for spec in specs {
            let levelKey = "\(key)/level/\(spec.name)"
            let levelID = StableUUID.make(levelKey)
            var sessions: [TrackSession] = []
            for week in 1...weeks {
                for day in 1...3 {
                    let sessionKey = "\(levelKey)/w\(week)d\(day)"
                    let isRetest = day == 3 && retestWeeks.contains(week)
                    let blocks: [IntervalBlock]
                    let note: String
                    if isRetest {
                        blocks = [RepsSetBuilder.block(exercise: exercise, sets: [.max(atLeast: spec.retestTarget)], rest: rest)]
                        note = "Re-test: warm up with a few easy reps, then one set of as many \(exercise.lowercased()) as you can. "
                            + "Reach \(spec.retestTarget) to move up a level."
                    } else {
                        let groups = spec.groups.enumerated().map { g, group in
                            let isLastGroup = g == spec.groups.count - 1
                            let sets: [RepsSetBuilder.SetTarget] = group.sets.enumerated().map { s, base in
                                let n = reps(base: base, week: week, day: day)
                                return isLastGroup && s == group.sets.count - 1 ? .max(atLeast: n) : .reps(n)
                            }
                            return (exercise: group.exercise, sets: sets)
                        }
                        blocks = RepsSetBuilder.blocks(groups: groups, rest: rest)
                        let setCount = spec.groups.reduce(0) { $0 + $1.sets.count }
                        let base = "\(setCount) sets, \(DurationFormatter.clock(rest)) rest. The last set is as many as you can."
                        note = spec.note.isEmpty ? base : "\(base) \(spec.note)"
                    }
                    let program = ProgramSnapshot(name: "\(name) · W\(week) D\(day)", activity: .strength, blocks: blocks)
                    sessions.append(TrackSession(
                        id: StableUUID.make(sessionKey),
                        week: week,
                        day: day,
                        note: note,
                        program: program.withStableIDs(sessionKey),
                        isRetest: isRetest
                    ))
                }
            }
            levels.append(TrackLevel(id: levelID, name: spec.name, summary: spec.summary, sessions: sessions))
            bands.append(TrackAssessment.Band(levelID: levelID, minReps: spec.minReps))
        }
        return TrackDefinition(
            id: id,
            name: name,
            summary: summary,
            activity: .strength,
            levels: levels,
            assessment: TrackAssessment(question: question, bands: bands),
            cadence: .timesPerWeek(3),
            minRestDays: 1,
            leadInRest: leadInRest
        )
    }
}

/// Run / Walk session shape.
enum RunWalk {
    case run(TimeInterval)
    case walk(TimeInterval)
    case repeating(Int, [RunWalk])

    var step: IntervalStep? {
        switch self {
        case .run(let s): IntervalStep(kind: .work, name: "Run", end: .time(s))
        case .walk(let s): IntervalStep(kind: .rest, name: "Walk", end: .time(s))
        case .repeating: nil
        }
    }

    /// Repeats become their own block; runs of plain segments share one.
    static func blocks(_ plan: [RunWalk]) -> [IntervalBlock] {
        var blocks: [IntervalBlock] = []
        var pending: [IntervalStep] = []
        for segment in plan {
            if case .repeating(let n, let inner) = segment {
                if !pending.isEmpty { blocks.append(IntervalBlock(steps: pending)); pending = [] }
                blocks.append(IntervalBlock(steps: inner.compactMap(\.step), repeats: n))
            } else if let step = segment.step {
                pending.append(step)
            }
        }
        if !pending.isEmpty { blocks.append(IntervalBlock(steps: pending)) }
        return blocks
    }

    /// "8 × run 1:00 / walk 1:30", or "Run 20:00".
    static func note(_ plan: [RunWalk]) -> String {
        plan.map(\.text).joined(separator: ", ")
    }

    private var text: String {
        switch self {
        case .run(let s): "run \(DurationFormatter.clock(s))"
        case .walk(let s): "walk \(DurationFormatter.clock(s))"
        case .repeating(let n, let inner): "\(n) × (" + inner.map(\.text).joined(separator: " / ") + ")"
        }
    }
}

extension ProgramSnapshot {
    /// Replaces the program, block and step ids with ones derived from `key`.
    func withStableIDs(_ key: String) -> ProgramSnapshot {
        var copy = self
        copy.id = StableUUID.make("\(key)/program")
        for b in copy.blocks.indices {
            copy.blocks[b].id = StableUUID.make("\(key)/b\(b)")
            for s in copy.blocks[b].steps.indices {
                copy.blocks[b].steps[s].id = StableUUID.make("\(key)/b\(b)/s\(s)")
            }
        }
        return copy
    }
}
