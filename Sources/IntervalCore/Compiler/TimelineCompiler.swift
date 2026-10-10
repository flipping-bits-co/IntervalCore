import Foundation

/// Flattens blocks × repeats × steps into a linear `Timeline`.
public enum TimelineCompiler {

    public static func compile(_ blocks: [IntervalBlock], workoutEnd: WorkoutEnd = .allBlocks) -> Timeline {
        let loopBlocks = loopBlockRange(blocks, workoutEnd: workoutEnd)
        var steps: [TimelineStep] = []
        var loopStart: Int?
        var loopEnd: Int?

        for (blockIndex, block) in blocks.enumerated() {
            let inLoop = loopBlocks?.contains(blockIndex) ?? false
            if inLoop && loopStart == nil { loopStart = steps.count }

            let rounds = max(1, block.repeats)
            let trailingRestStart = trailingRestStart(of: block)
            for round in 1...rounds {
                for (stepIndex, step) in block.steps.enumerated() {
                    let isFinalRound = round == rounds
                    if isFinalRound, block.skipLastRest, !inLoop,
                       let trailingRestStart, stepIndex >= trailingRestStart {
                        continue
                    }
                    steps.append(TimelineStep(
                        index: steps.count,
                        blockIndex: blockIndex,
                        blockID: block.id,
                        stepID: step.id,
                        round: round,
                        totalRounds: rounds,
                        stepIndex: stepIndex,
                        kind: step.kind,
                        name: step.name,
                        end: step.end
                    ))
                }
            }

            if inLoop { loopEnd = steps.count }
        }

        var loopRange: Range<Int>?
        if let loopStart, let loopEnd, loopEnd > loopStart {
            loopRange = loopStart..<loopEnd
        }
        return Timeline(steps: steps, workoutEnd: workoutEnd, loopRange: loopRange)
    }

    /// Blocks from the first to the last loop block, inclusive. Non-loop blocks in
    /// between are part of the loop so the range stays contiguous.
    static func loopBlockRange(_ blocks: [IntervalBlock], workoutEnd: WorkoutEnd) -> ClosedRange<Int>? {
        guard workoutEnd.target != nil,
              let first = blocks.firstIndex(where: \.loopsUntilTarget),
              let last = blocks.lastIndex(where: \.loopsUntilTarget) else { return nil }
        return first...last
    }

    /// Index where the block's trailing run of rest steps begins. `nil` when there is
    /// no trailing rest, or when the block is all rest (dropping it would erase the block).
    static func trailingRestStart(of block: IntervalBlock) -> Int? {
        guard let lastNonRest = block.steps.lastIndex(where: { $0.kind != .rest }) else { return nil }
        let start = lastNonRest + 1
        return start < block.steps.count ? start : nil
    }
}
