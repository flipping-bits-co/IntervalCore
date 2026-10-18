import Foundation

/// The user's audio cue settings. Missing keys decode to their defaults, so the phone
/// and Watch can add fields without breaking each other.
public struct CuePreferences: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var voice: Bool
    public var countdownBeeps: Bool
    public var halfway: Bool
    /// The Watch speaks its own cues during Watch sessions. Off by default: the Watch is
    /// haptics-only unless the user turns this on (v1 device feedback, item 1).
    public var watchVoiceCues: Bool
    /// Length of the pre-start "3-2-1" countdown, in seconds. Clamped to `0...15`; beeps
    /// (gated by `countdownBeeps`) still fire only on the last `beepSeconds(forCountdown:)`
    /// of it, so a longer countdown is a visible count with beeps only near the end.
    /// Additive: older payloads decode to the default, 3 (push-up-feedback-debug-workout.md §2).
    public var startCountdownSeconds: Int
    /// Length of the "beep beep beep" countdown at the *end* of every step, before the
    /// next rep/rest starts. Separate from `startCountdownSeconds` (the pre-start countdown).
    /// Clamped to `0...15` (picker offers Off/3/5/10/15); `0` means no step-end countdown at
    /// all. Drives `IntervalEngine`'s
    /// `.countdown` events (via its `countdownSeconds` init parameter), which in turn drive
    /// both the beeps (`CueMapper`, gated by `countdownBeeps`) and the apps' countdown haptics.
    /// Additive: older payloads decode to the default, 3.
    public var stepCountdownSeconds: Int

    public init(
        enabled: Bool = true,
        voice: Bool = true,
        countdownBeeps: Bool = true,
        halfway: Bool = true,
        watchVoiceCues: Bool = false,
        startCountdownSeconds: Int = 3,
        stepCountdownSeconds: Int = 3
    ) {
        self.enabled = enabled
        self.voice = voice
        self.countdownBeeps = countdownBeeps
        self.halfway = halfway
        self.watchVoiceCues = watchVoiceCues
        self.startCountdownSeconds = Self.clampedStartCountdown(startCountdownSeconds)
        self.stepCountdownSeconds = Self.clampedStepCountdown(stepCountdownSeconds)
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = CuePreferences()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        voice = try c.decodeIfPresent(Bool.self, forKey: .voice) ?? defaults.voice
        countdownBeeps = try c.decodeIfPresent(Bool.self, forKey: .countdownBeeps) ?? defaults.countdownBeeps
        halfway = try c.decodeIfPresent(Bool.self, forKey: .halfway) ?? defaults.halfway
        watchVoiceCues = try c.decodeIfPresent(Bool.self, forKey: .watchVoiceCues) ?? defaults.watchVoiceCues
        let decodedStartCountdown = try c.decodeIfPresent(Int.self, forKey: .startCountdownSeconds)
            ?? defaults.startCountdownSeconds
        startCountdownSeconds = Self.clampedStartCountdown(decodedStartCountdown)
        let decodedStepCountdown = try c.decodeIfPresent(Int.self, forKey: .stepCountdownSeconds)
            ?? defaults.stepCountdownSeconds
        stepCountdownSeconds = Self.clampedStepCountdown(decodedStepCountdown)
    }

    /// Clamps to `0...15`, so a corrupt or out-of-range synced value can't produce a
    /// negative or absurdly long pre-start countdown.
    public static func clampedStartCountdown(_ seconds: Int) -> Int {
        min(max(seconds, 0), 15)
    }

    /// Clamps to `0...15` (the picker offers Off/3/5/10/15), so a corrupt or out-of-range
    /// synced value can't produce a negative or absurdly long step-end countdown.
    public static func clampedStepCountdown(_ seconds: Int) -> Int {
        min(max(seconds, 0), 15)
    }

    /// How many of the final seconds of a pre-start countdown of length `seconds` get a
    /// beep: the last 3, or fewer when the countdown itself is shorter than that. Pure and
    /// shared so the phone and Watch agree on when beeps fire regardless of where the
    /// pre-start countdown loop itself lives (app-side today).
    public static func beepSeconds(forCountdown seconds: Int) -> Int {
        min(clampedStartCountdown(seconds), 3)
    }
}

/// How hard transition haptics hit. The apps map it to their haptic APIs.
public enum HapticStrength: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case light
    case normal
    case strong

    /// Strong is the default: mid-workout taps were too easy to miss (v1 device feedback, item 2).
    public static let `default`: HapticStrength = .strong

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .light: "Light"
        case .normal: "Normal"
        case .strong: "Strong"
        }
    }

    /// Unknown values (from a newer app) fall back to the default instead of failing the sync.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HapticStrength(rawValue: raw) ?? .default
    }
}

/// Settings the phone syncs to the Watch alongside its programs.
public struct WatchSettings: Codable, Hashable, Sendable {
    public var cues: CuePreferences
    public var haptics: WatchHaptics
    /// When `haptics` last changed on the phone (its own edit, or a Watch change it accepted).
    /// The Watch treats incoming settings with a time >= its pending local change as
    /// authoritative. `nil` from older phones.
    public var hapticsChangedAt: Date?
    /// Show the Quick Timers page on the Watch home (library-dashboard-split.md). Off by default:
    /// it distracts from the plan.
    public var showsQuickTimers: Bool
    /// Show the DEBUG-only "🧪 UI Test" workout. The flag ships in Release but has nothing to
    /// show there.
    public var showsTestWorkout: Bool

    public init(
        cues: CuePreferences = CuePreferences(),
        haptics: WatchHaptics = WatchHaptics(),
        hapticsChangedAt: Date? = nil,
        showsQuickTimers: Bool = false,
        showsTestWorkout: Bool = true
    ) {
        self.cues = cues
        self.haptics = haptics
        self.hapticsChangedAt = hapticsChangedAt
        self.showsQuickTimers = showsQuickTimers
        self.showsTestWorkout = showsTestWorkout
    }

    /// Pre-preset initializer: the strength maps to its preset, toggles stay on.
    public init(cues: CuePreferences = CuePreferences(), hapticStrength: HapticStrength, hapticsChangedAt: Date? = nil) {
        self.init(cues: cues, haptics: WatchHaptics(preset: HapticPreset(strength: hapticStrength)), hapticsChangedAt: hapticsChangedAt)
    }

    /// Pre-preset view of `haptics.preset`. Setting it picks the matching preset.
    public var hapticStrength: HapticStrength {
        get { haptics.preset.legacyStrength }
        set { haptics.preset = HapticPreset(strength: newValue) }
    }

    private enum CodingKeys: String, CodingKey {
        case cues
        case haptics
        case hapticStrength
        case hapticsChangedAt
        case showsQuickTimers
        case showsTestWorkout
    }

    /// `haptics` wins when present; an older phone's payload with only `hapticStrength` maps to
    /// its preset (light → subtle, normal → standard, strong → strong).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cues = try c.decodeIfPresent(CuePreferences.self, forKey: .cues) ?? CuePreferences()
        if let haptics = try c.decodeIfPresent(WatchHaptics.self, forKey: .haptics) {
            self.haptics = haptics
        } else if let strength = try c.decodeIfPresent(HapticStrength.self, forKey: .hapticStrength) {
            haptics = WatchHaptics(preset: HapticPreset(strength: strength))
        } else {
            haptics = WatchHaptics()
        }
        hapticsChangedAt = try c.decodeIfPresent(Date.self, forKey: .hapticsChangedAt)
        showsQuickTimers = try c.decodeIfPresent(Bool.self, forKey: .showsQuickTimers) ?? false
        showsTestWorkout = try c.decodeIfPresent(Bool.self, forKey: .showsTestWorkout) ?? true
    }

    /// Also writes `hapticStrength`, so a Watch from before presets keeps a matching strength.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cues, forKey: .cues)
        try c.encode(haptics, forKey: .haptics)
        try c.encode(hapticStrength, forKey: .hapticStrength)
        try c.encodeIfPresent(hapticsChangedAt, forKey: .hapticsChangedAt)
        try c.encode(showsQuickTimers, forKey: .showsQuickTimers)
        try c.encode(showsTestWorkout, forKey: .showsTestWorkout)
    }

    /// Application-context key holding the encoded settings, next to the `syncPrograms` envelope.
    public static let contextKey = "watchSettings"

    /// Reads settings from a received application context. Missing (older phone) or unreadable
    /// settings give the defaults: Watch voice cues off, Strong preset, both haptic toggles on.
    public init(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchSettings.self, from: data) else {
            self.init()
            return
        }
        self = decoded
    }
}

extension WCMessage {
    /// The phone → Watch application context: the `syncPrograms` envelope plus `WatchSettings`
    /// under `WatchSettings.contextKey` and, when given, `WatchUpNext` under `WatchUpNext.contextKey`.
    /// One dictionary, because each `updateApplicationContext` replaces the last. The Watch decodes
    /// programs with `WCMessage(dictionary:)` as before (extra keys are ignored), settings with
    /// `WatchSettings(applicationContext:)`, and Up next with `WatchUpNext(applicationContext:)`.
    public static func applicationContext(
        programs: [ProgramSnapshot],
        settings: WatchSettings,
        upNext: WatchUpNext? = nil
    ) throws -> [String: Any] {
        var context = try WCMessage.command(.syncPrograms(programs)).toDictionary()
        context[WatchSettings.contextKey] = try JSONEncoder().encode(settings)
        if let upNext {
            context[WatchUpNext.contextKey] = try JSONEncoder().encode(upNext)
        }
        return context
    }
}
