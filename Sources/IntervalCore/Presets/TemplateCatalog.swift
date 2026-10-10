import Foundation

/// Extra bundled templates (Phase 7 plan §1): single workouts with no progression. Ids
/// continue the app's `BundledTemplates` series, and `thirtyThirty` keeps the id the app
/// already seeds, so moving the app to this catalogue doesn't duplicate it.
public enum TemplateCatalog {

    public static let all: [ProgramSnapshot] = [thirtyThirty, norwegian4x4, tenTwentyThirty, pyramid]

    /// 10 × (0:30 work / 0:30 rest), as the app's existing "30/30 Intervals".
    public static let thirtyThirty: ProgramSnapshot = {
        var program = Presets.workRest(work: 30, rest: 30, rounds: 10)
        program.name = "30/30 Intervals"
        return program.withStableIDs("ember.template.3030", id: "6C1E0001-0000-4000-8000-000000000002")
    }()

    /// Warm-up 10:00, 4 × (4:00 hard / 3:00 easy), cool-down 5:00.
    public static let norwegian4x4: ProgramSnapshot = ProgramSnapshot(
        name: "4×4 Norwegian",
        activity: .running,
        blocks: [
            IntervalBlock(steps: [IntervalStep(kind: .warmup, end: .time(600))]),
            IntervalBlock(
                steps: [
                    IntervalStep(kind: .work, name: "Hard", end: .time(240)),
                    IntervalStep(kind: .rest, name: "Easy", end: .time(180)),
                ],
                repeats: 4
            ),
            IntervalBlock(steps: [IntervalStep(kind: .cooldown, end: .time(300))]),
        ]
    ).withStableIDs("ember.template.norwegian4x4", id: "6C1E0001-0000-4000-8000-000000000005")

    /// Warm-up 10:00, then 3 sets of 5 × (0:30 easy / 0:20 moderate / 0:10 sprint) with 2:00
    /// between sets, cool-down 5:00.
    public static let tenTwentyThirty: ProgramSnapshot = {
        let set = IntervalBlock(
            steps: [
                IntervalStep(kind: .rest, name: "Easy", end: .time(30)),
                IntervalStep(kind: .work, name: "Moderate", end: .time(20)),
                IntervalStep(kind: .work, name: "Sprint", end: .time(10)),
            ],
            repeats: 5
        )
        let recover = IntervalBlock(steps: [IntervalStep(kind: .rest, name: "Recover", end: .time(120))])
        return ProgramSnapshot(
            name: "10-20-30",
            activity: .running,
            blocks: [IntervalBlock(steps: [IntervalStep(kind: .warmup, end: .time(600))])]
                + [set, recover, set, recover, set]
                + [IntervalBlock(steps: [IntervalStep(kind: .cooldown, end: .time(300))])]
        ).withStableIDs("ember.template.102030", id: "6C1E0001-0000-4000-8000-000000000006")
    }()

    /// 1-2-3-4-3-2-1 minutes of work with 1:00 rest between.
    public static let pyramid: ProgramSnapshot = {
        var steps: [IntervalStep] = []
        for (index, minutes) in [1, 2, 3, 4, 3, 2, 1].enumerated() {
            if index > 0 { steps.append(IntervalStep(kind: .rest, end: .time(60))) }
            steps.append(IntervalStep(kind: .work, end: .time(TimeInterval(minutes * 60))))
        }
        return ProgramSnapshot(
            name: "Pyramid",
            activity: .hiit,
            blocks: Presets.prepareBlocks(Presets.defaultPrepare) + [IntervalBlock(steps: steps)]
        ).withStableIDs("ember.template.pyramid", id: "6C1E0001-0000-4000-8000-000000000007")
    }()
}

extension ProgramSnapshot {
    /// Stable block and step ids from `key`, and the given literal program id.
    func withStableIDs(_ key: String, id: String) -> ProgramSnapshot {
        var copy = withStableIDs(key)
        // Literal, well-formed UUID strings above; `TemplateCatalogTests` decodes every one.
        copy.id = UUID(uuidString: id)!
        return copy
    }
}
