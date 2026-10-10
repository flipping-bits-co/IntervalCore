import Foundation

/// Stable fingerprint of a program's structure, used to dedupe Recents.
///
/// Ignores ids, the program name, and block names, so re-running the same workout
/// maps to the same recent. Includes step names and activity, because "8×1:00 row"
/// and "8×1:00 run" are different workouts to the user. FNV-1a over a canonical
/// string rather than `Hasher`, which is seeded per process and would differ between
/// launches and between phone and Watch.
public enum StructureHash {

    public static func hash(blocks: [IntervalBlock], workoutEnd: WorkoutEnd, activity: Activity) -> String {
        var fnv: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in canonical(blocks: blocks, workoutEnd: workoutEnd, activity: activity).utf8 {
            fnv ^= UInt64(byte)
            fnv = fnv &* 0x0000_0100_0000_01b3
        }
        return String(fnv, radix: 16).leftPadded(to: 16)
    }

    static func canonical(blocks: [IntervalBlock], workoutEnd: WorkoutEnd, activity: Activity) -> String {
        var parts = ["a:\(activity.rawValue)", "e:\(endKey(workoutEnd))"]
        for block in blocks {
            let steps = block.steps.map { step in
                let name = step.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return "\(step.kind.rawValue),\(endKey(step.end)),\(name)"
            }
            parts.append("b:\(max(1, block.repeats)),\(block.skipLastRest),\(block.loopsUntilTarget)[\(steps.joined(separator: ";"))]")
        }
        return parts.joined(separator: "|")
    }

    private static func endKey(_ end: EndCondition) -> String {
        switch end {
        case .time(let s): "t\(num(s))"
        case .distance(let m): "d\(num(m))"
        case .calories(let c): "c\(num(c))"
        case .reps(let n): "r\(n)"
        case .open: "o"
        case .heartRateBelow(let bpm, let wait): "hb\(bpm),\(num(wait))"
        case .heartRateAbove(let bpm, let wait): "ha\(bpm),\(num(wait))"
        }
    }

    private static func endKey(_ end: WorkoutEnd) -> String {
        switch end {
        case .allBlocks: "all"
        case .target(.time(let s)): "tt\(num(s))"
        case .target(.distance(let m)): "td\(num(m))"
        case .target(.calories(let c)): "tc\(num(c))"
        }
    }

    /// Integers print without ".0" so 60 and 60.0 hash the same.
    private static func num(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        count >= length ? self : String(repeating: "0", count: length - count) + self
    }
}
