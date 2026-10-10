import Foundation

/// Named Watch haptic presets. Each one is a pattern per event (type, repeats, spacing), and
/// the Watch owns that table because `WKHapticType` is watchOS-only. Replaces `HapticStrength`
/// for the Watch (watch-haptics plan §3); the phone's own "iPhone haptics" keep `HapticStrength`.
public enum HapticPreset: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case subtle
    case standard
    case strong
    case max

    /// Strong is the default: even the old Strong was too light on the wrist (v1.1 device re-test).
    public static let `default`: HapticPreset = .strong

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .subtle: "Subtle"
        case .standard: "Standard"
        case .strong: "Strong"
        case .max: "Max"
        }
    }

    /// The preset an older `HapticStrength` setting maps to.
    public init(strength: HapticStrength) {
        switch strength {
        case .light: self = .subtle
        case .normal: self = .standard
        case .strong: self = .strong
        }
    }

    /// The closest `HapticStrength`, written next to the preset so Watches from before presets
    /// still get a sensible setting.
    public var legacyStrength: HapticStrength {
        switch self {
        case .subtle: .light
        case .standard: .normal
        case .strong, .max: .strong
        }
    }

    /// Unknown values (from a newer app) fall back to the default instead of failing the sync.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HapticPreset(rawValue: raw) ?? .default
    }
}

/// A named Watch haptic the user can pick for one event (haptics-customize plan §3). The Watch
/// owns the pattern behind each feel. An unknown value from a newer build reads as "no override",
/// so the event follows the preset.
public enum HapticFeel: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case off
    case tick
    case tap
    case doubleTap
    case alert
    case doubleAlert
    case buzz
    case longBuzz
    case success

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .off: "Off"
        case .tick: "Tick"
        case .tap: "Tap"
        case .doubleTap: "Double tap"
        case .alert: "Alert"
        case .doubleAlert: "Double alert"
        case .buzz: "Buzz"
        case .longBuzz: "Long buzz"
        case .success: "Success"
        }
    }
}

/// The Watch haptic events a user can customize.
public enum HapticCueEvent: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case workStart
    case restStart
    case halfway
    case countdown
    case finish

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .workStart: "Work start"
        case .restStart: "Rest start"
        case .halfway: "Halfway"
        case .countdown: "3-2-1"
        case .finish: "Finish"
        }
    }
}

/// One row choice in a Customize list: follow the preset, a named feel, or off.
public enum HapticSelection: Codable, Hashable, Sendable, Identifiable {
    case `default`
    case feel(HapticFeel)
    case off

    /// The list in display order: Default, every feel, then Off.
    public static let options: [HapticSelection] =
        [.default] + HapticFeel.allCases.filter { $0 != .off }.map { .feel($0) } + [.off]

    public var id: String {
        switch self {
        case .default: "default"
        case .feel(let feel): feel.rawValue
        case .off: "off"
        }
    }

    public var label: String {
        switch self {
        case .default: "Default"
        case .feel(let feel): feel.label
        case .off: "Off"
        }
    }
}

/// The Watch's haptic settings: a preset, a remembered feel per event, and which events are off.
/// On/off is separate from the feel, so turning an event off and on again brings its feel back
/// (HC5). Set on either device; the phone syncs them in `WatchSettings`, the Watch sends its own
/// changes back with `SessionCommand.watchHapticsChanged`.
public struct WatchHaptics: Codable, Hashable, Sendable {
    public var preset: HapticPreset
    /// The user's feel per event, kept while the event is off. Never holds `.off`; an event
    /// without one follows the preset.
    public private(set) var feels: [HapticCueEvent: HapticFeel]
    /// Events that are silent.
    public var disabled: Set<HapticCueEvent>

    public init(preset: HapticPreset = .default, feels: [HapticCueEvent: HapticFeel], disabled: Set<HapticCueEvent> = []) {
        self.preset = preset
        self.feels = feels.filter { $0.value != .off }
        self.disabled = disabled
    }

    /// HC1-style initializer: `.off` in `overrides` (or a false toggle) disables that event.
    public init(
        preset: HapticPreset = .default,
        overrides: [HapticCueEvent: HapticFeel] = [:],
        countdownTaps: Bool = true,
        halfwayTap: Bool = true
    ) {
        self.init(preset: preset, feels: [:])
        self.overrides = overrides
        if !countdownTaps { disabled.insert(.countdown) }
        if !halfwayTap { disabled.insert(.halfway) }
    }

    // MARK: Resolver

    /// What the Watch plays for `event`: `.off` when disabled, else the feel, else `nil` for the
    /// preset's pattern.
    public func override(for event: HapticCueEvent) -> HapticFeel? {
        disabled.contains(event) ? .off : feels[event]
    }

    public func isEnabled(_ event: HapticCueEvent) -> Bool {
        !disabled.contains(event)
    }

    /// The resolver's view of every event (`.off` for disabled ones), as before HC5. Setting it
    /// maps `.off` to disabled (keeping the remembered feel), a feel to that feel and enabled,
    /// and a missing event to Default and enabled.
    public var overrides: [HapticCueEvent: HapticFeel] {
        get {
            var result = feels
            for event in disabled { result[event] = .off }
            return result
        }
        set {
            for event in HapticCueEvent.allCases {
                switch newValue[event] {
                case .off?: select(.off, for: event)
                case let feel?: select(.feel(feel), for: event)
                case nil: select(.default, for: event)
                }
            }
        }
    }

    // MARK: Customize list

    public func selection(for event: HapticCueEvent) -> HapticSelection {
        if disabled.contains(event) { return .off }
        return feels[event].map { .feel($0) } ?? .default
    }

    /// Off keeps the remembered feel; a feel sets it and turns the event on; Default clears the
    /// feel and turns the event on.
    public mutating func select(_ selection: HapticSelection, for event: HapticCueEvent) {
        switch selection {
        case .off, .feel(.off):
            disabled.insert(event)
        case .feel(let feel):
            feels[event] = feel
            disabled.remove(event)
        case .default:
            feels[event] = nil
            disabled.remove(event)
        }
    }

    /// The feel the event will use when on (kept while it's off), `nil` for Default.
    public func rememberedFeel(for event: HapticCueEvent) -> HapticFeel? {
        feels[event]
    }

    /// The 3-2-1 taps before a timed step ends: not disabled. Setting it only flips on/off.
    public var countdownTaps: Bool {
        get { isEnabled(.countdown) }
        set { setEnabled(newValue, for: .countdown) }
    }

    /// The tap at the halfway point of a timed step. Same rules as `countdownTaps`.
    public var halfwayTap: Bool {
        get { isEnabled(.halfway) }
        set { setEnabled(newValue, for: .halfway) }
    }

    public mutating func setEnabled(_ enabled: Bool, for event: HapticCueEvent) {
        if enabled { disabled.remove(event) } else { disabled.insert(event) }
    }

    /// "Reset to preset": every event on and following the preset.
    public mutating func resetToPreset() {
        feels = [:]
        disabled = []
    }

    // MARK: Coding

    private enum CodingKeys: String, CodingKey {
        case preset
        /// Pre-HC5 view: feels plus `.off` for disabled events. Still written for older builds.
        case overrides
        case countdownTaps
        case halfwayTap
        /// HC5: remembered feels (also for disabled events) and the disabled events.
        case feels
        case disabled
    }

    /// Payloads with `feels` or `disabled` (HC5) are read from those. Older ones are read from
    /// `overrides` (`.off` = disabled, no remembered feel), and a false toggle with nothing for
    /// its event reads as disabled. Unknown events or feels are dropped, so they follow the
    /// preset; malformed dictionaries read as empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        preset = try c.decodeIfPresent(HapticPreset.self, forKey: .preset) ?? .default
        feels = [:]
        disabled = []
        let newFeels = try? c.decodeIfPresent([String: String].self, forKey: .feels)
        let newDisabled = try? c.decodeIfPresent([String].self, forKey: .disabled)
        if newFeels != nil || newDisabled != nil {
            for (event, feel) in Self.parse(newFeels ?? [:]) where feel != .off {
                feels[event] = feel
            }
            disabled = Set((newDisabled ?? []).compactMap(HapticCueEvent.init(rawValue:)))
            return
        }
        let old = Self.parse((try? c.decodeIfPresent([String: String].self, forKey: .overrides)) ?? [:])
        for (event, feel) in old {
            if feel == .off { disabled.insert(event) } else { feels[event] = feel }
        }
        if try c.decodeIfPresent(Bool.self, forKey: .countdownTaps) == false, old[.countdown] == nil {
            disabled.insert(.countdown)
        }
        if try c.decodeIfPresent(Bool.self, forKey: .halfwayTap) == false, old[.halfway] == nil {
            disabled.insert(.halfway)
        }
    }

    /// Writes the old `overrides` view and toggles (false iff disabled) for builds before HC5,
    /// and `feels` / `disabled` when non-empty.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(preset, forKey: .preset)
        let overrides = overrides
        if !overrides.isEmpty { try c.encode(Self.raw(overrides), forKey: .overrides) }
        try c.encode(countdownTaps, forKey: .countdownTaps)
        try c.encode(halfwayTap, forKey: .halfwayTap)
        if !feels.isEmpty { try c.encode(Self.raw(feels), forKey: .feels) }
        if !disabled.isEmpty { try c.encode(disabled.map(\.rawValue).sorted(), forKey: .disabled) }
    }

    private static func parse(_ raw: [String: String]) -> [HapticCueEvent: HapticFeel] {
        var result: [HapticCueEvent: HapticFeel] = [:]
        for (key, value) in raw {
            guard let event = HapticCueEvent(rawValue: key), let feel = HapticFeel(rawValue: value) else { continue }
            result[event] = feel
        }
        return result
    }

    private static func raw(_ map: [HapticCueEvent: HapticFeel]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key.rawValue, $0.value.rawValue) })
    }
}
