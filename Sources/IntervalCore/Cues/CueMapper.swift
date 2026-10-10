import Foundation

/// One thing the user hears. Phone and Watch both play these (DECISIONS.md, Audio cues).
public enum Cue: Codable, Hashable, Sendable {
    /// Spoken at each transition: the step name, or its kind ("Work", "Rest").
    case phase(String)
    /// Beep 3, 2, 1 seconds before a timed step ends; 1 is higher-pitched.
    case countdown(Int)
    /// Spoken halfway through steps of 60 s or more (the engine only emits it for those).
    case halfway
    case completed

    public var spokenText: String? {
        switch self {
        case .phase(let text): text
        case .halfway: "Halfway"
        case .completed: "Workout complete"
        case .countdown: nil
        }
    }

    public var isSpoken: Bool { spokenText != nil }
}

/// Engine events → cues. Pure and shared, so phone and Watch follow one rule set and
/// the mapping is tested without playing sound. Moved from the iPhone's `AudioCueMapper`.
public enum CueMapper {

    public static func cues(for events: [EngineEvent], timeline: Timeline, preferences: CuePreferences) -> [Cue] {
        guard preferences.enabled else { return [] }
        // One tick can cross several boundaries (after a lock or a skip burst). Only the
        // step that is now running is announced, so cues don't queue up stale names.
        let lastStart = events.lastIndex { if case .stepStarted = $0 { true } else { false } }

        var cues: [Cue] = []
        for (offset, event) in events.enumerated() {
            switch event {
            case .stepStarted(let index, _) where offset == lastStart && preferences.voice:
                if timeline.steps.indices.contains(index) { cues.append(.phase(phrase(for: timeline.steps[index]))) }
            case .countdown(_, let seconds) where preferences.countdownBeeps:
                cues.append(.countdown(seconds))
            case .halfway where preferences.voice && preferences.halfway:
                cues.append(.halfway)
            case .completed(let reason) where preferences.voice && reason != .stopped:
                cues.append(.completed)
            default:
                break
            }
        }
        return cues
    }

    /// "Squats", or the kind label for unnamed steps ("Work", "Get Ready").
    public static func phrase(for step: TimelineStep) -> String {
        step.displayName
    }
}
