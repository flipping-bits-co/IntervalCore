import Foundation

/// Maps a finished run back to each tagged track: advance, repeat, or leave unchanged. Pure,
/// so the phone applies the same rules to phone and Watch results (DECISIONS 2026-10-09).
///
/// A track's session is **missed** when any of its work steps was skipped, never finished
/// (the workout ended first, or the user went back from it), or logged fewer reps than its
/// `.reps` target. A missed session repeats when auto-repeat is on; a session that never
/// started (the workout ended before its blocks) stays unchanged. Re-tests always advance:
/// their result moves the level instead (`maxRepsLogged`).
public enum TrackOutcome {

    public enum Decision: String, Codable, Hashable, Sendable {
        /// Move to the next session.
        case advance
        /// Missed with auto-repeat on: do the same session next time.
        case `repeat`
        /// The run never reached this track's blocks.
        case unchanged
    }

    public struct Result: Codable, Hashable, Sendable {
        public var ref: TrackRef
        public var decision: Decision
        /// Started and missed a target; always false for `.unchanged`.
        public var missed: Bool
        public var totalWorkSteps: Int
        public var completedWorkSteps: Int
        /// Work steps ended with Skip (including the step running when the workout was ended).
        public var skippedWorkSteps: Int
        /// Work steps never reached, or left with Back and not finished.
        public var unfinishedWorkSteps: Int
        /// `.reps` steps finished with fewer reps logged than the target.
        public var belowTargetWorkSteps: Int
        /// Sum of logged reps across the track's work steps.
        public var totalRepsLogged: Int
        /// Best single set, for re-tests (`TrackAssessment.levelID(forMaxReps:)`). `nil` if no
        /// step logged reps.
        public var maxRepsLogged: Int?

        /// The decision with the user's summary override applied: "Repeat next time" on or off.
        /// `.unchanged` stays unchanged.
        public func decision(repeatOverride: Bool?) -> Decision {
            guard decision != .unchanged, let repeatOverride else { return decision }
            return repeatOverride ? .repeat : .advance
        }
    }

    /// Outcomes for every tag on `result.program`.
    /// - Parameters:
    ///   - autoRepeat: the "Repeat a session when I miss a target" setting.
    ///   - autoRepeatOverrides: per-enrolment overrides of that setting, keyed by `enrollmentID`.
    public static func evaluate(
        _ result: SessionResult,
        autoRepeat: Bool,
        autoRepeatOverrides: [UUID: Bool] = [:]
    ) -> [Result] {
        evaluate(
            program: result.program,
            records: result.steps,
            refs: result.trackRefs,
            autoRepeat: autoRepeat,
            autoRepeatOverrides: autoRepeatOverrides
        )
    }

    /// The same for a live session (`engine.records`) or any program/records pair.
    public static func evaluate(
        program: ProgramSnapshot,
        records: [StepRecord],
        refs: [TrackRef],
        autoRepeat: Bool,
        autoRepeatOverrides: [UUID: Bool] = [:]
    ) -> [Result] {
        let timeline = program.compile()
        // The latest record per timeline step is how that step finally ended.
        var latest: [Int: StepRecord] = [:]
        for record in records { latest[record.timelineIndex] = record }

        return refs.map { ref in
            let blockIDs = Set(ref.blockIDs)
            let steps = timeline.steps.filter { blockIDs.contains($0.blockID) }
            let started = steps.contains { latest[$0.index] != nil }

            var result = Result(
                ref: ref, decision: .unchanged, missed: false,
                totalWorkSteps: 0, completedWorkSteps: 0, skippedWorkSteps: 0,
                unfinishedWorkSteps: 0, belowTargetWorkSteps: 0, totalRepsLogged: 0, maxRepsLogged: nil
            )
            for step in steps where step.kind == .work {
                result.totalWorkSteps += 1
                guard let record = latest[step.index] else {
                    result.unfinishedWorkSteps += 1
                    continue
                }
                if let reps = record.repsLogged {
                    result.totalRepsLogged += reps
                    result.maxRepsLogged = max(result.maxRepsLogged ?? reps, reps)
                }
                switch classify(record, end: step.end) {
                case .completed: result.completedWorkSteps += 1
                case .skipped: result.skippedWorkSteps += 1
                case .unfinished: result.unfinishedWorkSteps += 1
                case .belowTarget: result.belowTargetWorkSteps += 1
                }
            }
            guard started else { return result }
            result.missed = result.completedWorkSteps < result.totalWorkSteps
            let repeats = autoRepeatOverrides[ref.enrollmentID] ?? autoRepeat
            result.decision = result.missed && repeats && !ref.isRetest ? .repeat : .advance
            return result
        }
    }

    private enum StepOutcome { case completed, skipped, unfinished, belowTarget }

    private static func classify(_ record: StepRecord, end: EndCondition) -> StepOutcome {
        switch record.endReason {
        case .skipped:
            return .skipped
        case .previous, .restarted:
            return .unfinished
        case .start, .timeElapsed, .heartRateReached, .heartRateTimeout, .metricReached, .userAdvanced, .targetReached:
            // Done logs the target, so a record without a count (older builds) met it.
            if case .reps(let target) = end, let logged = record.repsLogged, logged < target {
                return .belowTarget
            }
            return .completed
        }
    }
}
