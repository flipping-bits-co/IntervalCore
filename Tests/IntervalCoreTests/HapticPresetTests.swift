import Foundation
import Testing
@testable import IntervalCore

struct HapticPresetTests {

    @Test func defaultsAndLabels() {
        #expect(HapticPreset.default == .strong)
        #expect(HapticPreset.allCases.map(\.label) == ["Subtle", "Standard", "Strong", "Max"])
        #expect(HapticPreset.max.id == "max")
        let haptics = WatchHaptics()
        #expect(haptics.preset == .strong && haptics.countdownTaps && haptics.halfwayTap)
        #expect(WatchSettings().haptics == haptics)
    }

    @Test func strengthMapsToPresetAndBack() {
        #expect(HapticPreset(strength: .light) == .subtle)
        #expect(HapticPreset(strength: .normal) == .standard)
        #expect(HapticPreset(strength: .strong) == .strong)
        #expect(HapticPreset.allCases.map(\.legacyStrength) == [.light, .normal, .strong, .strong])

        var settings = WatchSettings(hapticStrength: .light)
        #expect(settings.haptics == WatchHaptics(preset: .subtle))
        settings.hapticStrength = .normal
        #expect(settings.haptics.preset == .standard)
    }

    @Test func unknownPresetFallsBackToStrong() throws {
        let haptics = try JSONDecoder().decode(WatchHaptics.self, from: Data(#"{"preset":"earthquake","halfwayTap":false}"#.utf8))
        #expect(haptics == WatchHaptics(preset: .strong, halfwayTap: false))
    }

    @Test func missingHapticFieldsTakeDefaults() throws {
        let haptics = try JSONDecoder().decode(WatchHaptics.self, from: Data(#"{"countdownTaps":false}"#.utf8))
        #expect(haptics == WatchHaptics(countdownTaps: false))
    }

    @Test func roundTripKeepsPresetAndToggles() throws {
        let settings = WatchSettings(
            cues: CuePreferences(watchVoiceCues: true),
            haptics: WatchHaptics(preset: .max, countdownTaps: false, halfwayTap: false)
        )
        #expect(try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    /// An older phone sends only `hapticStrength`.
    @Test func legacyPayloadMapsStrengthToPreset() throws {
        for (raw, preset) in [("light", HapticPreset.subtle), ("normal", .standard), ("strong", .strong)] {
            let json = #"{"cues":{},"hapticStrength":"\#(raw)"}"#
            let settings = try JSONDecoder().decode(WatchSettings.self, from: Data(json.utf8))
            #expect(settings.haptics == WatchHaptics(preset: preset))
        }
    }

    @Test func hapticsWinOverLegacyStrength() throws {
        let json = #"{"haptics":{"preset":"max"},"hapticStrength":"light"}"#
        let settings = try JSONDecoder().decode(WatchSettings.self, from: Data(json.utf8))
        #expect(settings.haptics.preset == .max)
    }

    /// An older Watch reads only `hapticStrength`, so it's still written.
    @Test func encodingKeepsLegacyStrengthForOlderWatches() throws {
        let data = try JSONEncoder().encode(WatchSettings(haptics: WatchHaptics(preset: .standard)))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hapticStrength"] as? String == "normal")
        #expect((object["haptics"] as? [String: Any])?["preset"] as? String == "standard")
    }

    @Test func contextCarriesHaptics() throws {
        let settings = WatchSettings(haptics: WatchHaptics(preset: .subtle, countdownTaps: false))
        let context = try WCMessage.applicationContext(programs: [Presets.tabata()], settings: settings)
        #expect(WatchSettings(applicationContext: context) == settings)
    }
}

struct HapticCommandTests {

    @Test func testHapticRoundTrips() throws {
        for preset in HapticPreset.allCases {
            let message = WCMessage.command(.testHaptic(preset))
            let dictionary = try message.toDictionary()
            _ = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
            #expect(try WCMessage(dictionary: dictionary) == message)
        }
    }

    @Test func watchHapticsChangedRoundTrips() throws {
        let haptics = WatchHaptics(preset: .max, countdownTaps: false, halfwayTap: true)
        let message = WCMessage.command(.watchHapticsChanged(haptics, changedAt: .testEpoch))
        let decoded = try WCMessage(dictionary: message.toDictionary())
        #expect(decoded == message)
        guard case .command(.watchHapticsChanged(let received, let changedAt)) = decoded else {
            Issue.record("wrong case"); return
        }
        #expect(received == haptics)
        #expect(changedAt == .testEpoch)
    }
}

struct HapticsChangedAtTests {

    @Test func roundTripsAndDefaultsToNil() throws {
        #expect(WatchSettings().hapticsChangedAt == nil)
        let settings = WatchSettings(haptics: WatchHaptics(preset: .max), hapticsChangedAt: .testEpoch)
        #expect(try JSONDecoder().decode(WatchSettings.self, from: JSONEncoder().encode(settings)) == settings)
        let context = try WCMessage.applicationContext(programs: [], settings: settings)
        #expect(WatchSettings(applicationContext: context).hapticsChangedAt == .testEpoch)
        #expect(WatchSettings(hapticStrength: .light, hapticsChangedAt: .testEpoch).hapticsChangedAt == .testEpoch)
    }

    /// Omitted when nil, and absent in older payloads.
    @Test func additiveOnTheWire() throws {
        let data = try JSONEncoder().encode(WatchSettings())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["hapticsChangedAt"] == nil)
        let old = try JSONDecoder().decode(WatchSettings.self, from: Data(#"{"haptics":{"preset":"subtle"}}"#.utf8))
        #expect(old.hapticsChangedAt == nil)
        #expect(old.haptics.preset == .subtle)
    }
}

struct HapticOverrideTests {

    private func decode(_ json: String) throws -> WatchHaptics {
        try JSONDecoder().decode(WatchHaptics.self, from: Data(json.utf8))
    }

    private func object(_ haptics: WatchHaptics) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(haptics)) as? [String: Any])
    }

    @Test func labels() {
        #expect(HapticFeel.allCases.map(\.label) == [
            "Off", "Tick", "Tap", "Double tap", "Alert", "Double alert", "Buzz", "Long buzz", "Success",
        ])
        #expect(HapticCueEvent.allCases.map(\.label) == ["Work start", "Rest start", "Halfway", "3-2-1", "Finish"])
        #expect(HapticFeel.doubleTap.id == "doubleTap")
        #expect(HapticCueEvent.workStart.id == "workStart")
    }

    @Test func overridesRoundTripAsAStringKeyedDictionary() throws {
        let haptics = WatchHaptics(preset: .standard, overrides: [.workStart: .doubleAlert, .finish: .success, .halfway: .off])
        let json = try object(haptics)
        let overrides = try #require(json["overrides"] as? [String: String])
        #expect(overrides == ["workStart": "doubleAlert", "finish": "success", "halfway": "off"])
        #expect(json["halfwayTap"] as? Bool == false)
        #expect(json["countdownTaps"] as? Bool == true)
        #expect(try decode(String(decoding: JSONEncoder().encode(haptics), as: UTF8.self)) == haptics)
    }

    @Test func noOverridesOmitsTheKey() throws {
        #expect(try object(WatchHaptics())["overrides"] == nil)
        #expect(try decode(#"{"preset":"max"}"#).overrides.isEmpty)
    }

    /// Payloads from before overrides: a false toggle reads as `.off`.
    @Test func togglesMigrateToOff() throws {
        let old = try decode(#"{"preset":"strong","countdownTaps":false,"halfwayTap":false}"#)
        #expect(old.overrides == [.countdown: .off, .halfway: .off])
        #expect(!old.countdownTaps && !old.halfwayTap)
        #expect(try decode(#"{"countdownTaps":true,"halfwayTap":true}"#).overrides.isEmpty)
        // An explicit override wins over the toggle.
        let mixed = try decode(#"{"countdownTaps":false,"overrides":{"countdown":"tick"}}"#)
        #expect(mixed.overrides == [.countdown: .tick])
        #expect(mixed.countdownTaps)
    }

    @Test func unknownEventsAndFeelsAreDropped() throws {
        let haptics = try decode(#"{"overrides":{"workStart":"thunder","sparkle":"tap","restStart":"buzz"}}"#)
        #expect(haptics.overrides == [.restStart: .buzz])
        #expect(haptics.override(for: .workStart) == nil)
        // A malformed overrides value doesn't fail the whole settings sync.
        #expect(try decode(#"{"preset":"subtle","overrides":[1,2]}"#) == WatchHaptics(preset: .subtle))
    }

    @Test func togglesAreAViewOfOverrides() {
        var haptics = WatchHaptics(overrides: [.countdown: .tick])
        #expect(haptics.countdownTaps)
        haptics.countdownTaps = false
        #expect(haptics.override(for: .countdown) == .off)
        haptics.countdownTaps = true
        #expect(haptics.override(for: .countdown) == .tick)  // HC5: the feel comes back

        haptics.overrides[.halfway] = .alert
        haptics.halfwayTap = true  // already on: keeps the chosen feel
        #expect(haptics.override(for: .halfway) == .alert)
        #expect(WatchHaptics(countdownTaps: false, halfwayTap: false).overrides == [.countdown: .off, .halfway: .off])

        haptics.resetToPreset()
        #expect(haptics.overrides.isEmpty)
        #expect(HapticCueEvent.allCases.allSatisfy(haptics.isEnabled))
    }

    @Test func settingsCarryOverrides() throws {
        let settings = WatchSettings(haptics: WatchHaptics(preset: .max, overrides: [.restStart: .longBuzz]), hapticsChangedAt: .testEpoch)
        let context = try WCMessage.applicationContext(programs: [], settings: settings)
        #expect(WatchSettings(applicationContext: context) == settings)
    }

    @Test func testHapticCueRoundTrips() throws {
        let messages: [WCMessage] = [
            .command(.testHapticCue(.workStart, feel: .doubleAlert, preset: .strong)),
            .command(.testHapticCue(.halfway, feel: nil, preset: .subtle)),
            .command(.watchHapticsChanged(WatchHaptics(overrides: [.finish: .success]), changedAt: .testEpoch)),
        ]
        for message in messages {
            let dictionary = try message.toDictionary()
            _ = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
            #expect(try WCMessage(dictionary: dictionary) == message)
        }
    }
}

/// HC5: on/off is stored apart from the feel.
struct HapticSelectionTests {

    private func roundTrip(_ haptics: WatchHaptics) throws -> WatchHaptics {
        try JSONDecoder().decode(WatchHaptics.self, from: JSONEncoder().encode(haptics))
    }

    private func object(_ haptics: WatchHaptics) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(haptics)) as? [String: Any])
    }

    @Test func tickOffOnKeepsTick() throws {
        var haptics = WatchHaptics()
        haptics.select(.feel(.tick), for: .countdown)
        haptics.countdownTaps = false
        #expect(haptics.selection(for: .countdown) == .off)
        #expect(haptics.override(for: .countdown) == .off)
        #expect(haptics.rememberedFeel(for: .countdown) == .tick)

        // Survives sync while off.
        let synced = try roundTrip(haptics)
        #expect(synced == haptics)

        var back = synced
        back.countdownTaps = true
        #expect(back.selection(for: .countdown) == .feel(.tick))
        #expect(back.override(for: .countdown) == .tick)
    }

    @Test func listSelectionRules() {
        var haptics = WatchHaptics()
        #expect(haptics.selection(for: .workStart) == .default)
        #expect(haptics.override(for: .workStart) == nil)

        haptics.select(.feel(.doubleAlert), for: .workStart)
        #expect(haptics.selection(for: .workStart) == .feel(.doubleAlert))

        haptics.select(.off, for: .workStart)  // keeps the feel
        #expect(haptics.selection(for: .workStart) == .off)
        #expect(!haptics.isEnabled(.workStart))
        #expect(haptics.rememberedFeel(for: .workStart) == .doubleAlert)

        haptics.select(.feel(.buzz), for: .workStart)  // a feel turns it back on
        #expect(haptics.selection(for: .workStart) == .feel(.buzz))
        #expect(haptics.isEnabled(.workStart))

        haptics.select(.off, for: .workStart)
        haptics.select(.default, for: .workStart)  // Default clears the feel and turns it on
        #expect(haptics.selection(for: .workStart) == .default)
        #expect(haptics.rememberedFeel(for: .workStart) == nil)

        haptics.select(.feel(.off), for: .finish)  // same as Off
        #expect(haptics.selection(for: .finish) == .off)

        haptics.setEnabled(false, for: .restStart)
        #expect(haptics.selection(for: .restStart) == .off)
        #expect(haptics.rememberedFeel(for: .restStart) == nil)
    }

    @Test func options() {
        #expect(HapticSelection.options.first == .default)
        #expect(HapticSelection.options.last == .off)
        #expect(HapticSelection.options.count == HapticFeel.allCases.count + 1)
        #expect(HapticSelection.options.map(\.label).prefix(3) == ["Default", "Tick", "Tap"])
        #expect(Set(HapticSelection.options.map(\.id)).count == HapticSelection.options.count)
    }

    @Test func feelsNeverHoldOff() {
        let feels: [HapticCueEvent: HapticFeel] = [.workStart: .off, .finish: .success]
        let haptics = WatchHaptics(feels: feels)
        #expect(haptics.rememberedFeel(for: .workStart) == nil)
        #expect(haptics.rememberedFeel(for: .finish) == .success)
    }

    @Test func overridesSetterKeepsRememberedFeels() {
        var haptics = WatchHaptics(feels: [.halfway: .alert], disabled: [.halfway])
        haptics.overrides[.finish] = .success
        #expect(haptics.selection(for: .halfway) == .off)
        #expect(haptics.rememberedFeel(for: .halfway) == .alert)
        #expect(haptics.selection(for: .finish) == .feel(.success))
    }

    /// New → old: older builds read `overrides` and the toggles.
    @Test func encodesTheOldViewForOlderBuilds() throws {
        let haptics = WatchHaptics(feels: [.countdown: .tick, .workStart: .alert], disabled: [.countdown, .restStart])
        let json = try object(haptics)
        #expect(json["overrides"] as? [String: String] == ["countdown": "off", "restStart": "off", "workStart": "alert"])
        #expect(json["countdownTaps"] as? Bool == false)
        #expect(json["halfwayTap"] as? Bool == true)
        #expect(json["feels"] as? [String: String] == ["countdown": "tick", "workStart": "alert"])
        #expect(json["disabled"] as? [String] == ["countdown", "restStart"])
        #expect(try roundTrip(haptics) == haptics)

        let plain = try object(WatchHaptics())
        #expect(plain["feels"] == nil && plain["disabled"] == nil && plain["overrides"] == nil)
    }

    /// Old → new: `.off` in overrides means disabled with no remembered feel.
    @Test func decodesOldPayloads() throws {
        let json = #"{"preset":"max","overrides":{"countdown":"off","finish":"success"},"countdownTaps":false,"halfwayTap":false}"#
        let haptics = try JSONDecoder().decode(WatchHaptics.self, from: Data(json.utf8))
        #expect(haptics.preset == .max)
        #expect(haptics.disabled == [.countdown, .halfway])
        #expect(haptics.rememberedFeel(for: .countdown) == nil)
        #expect(haptics.selection(for: .finish) == .feel(.success))
    }

    /// New keys win over the old view, and unknown values are dropped.
    @Test func decodesNewPayloads() throws {
        let json = #"{"overrides":{"countdown":"off"},"countdownTaps":false,"feels":{"countdown":"tick","sparkle":"tap","finish":"off"},"disabled":["countdown","glitter"]}"#
        let haptics = try JSONDecoder().decode(WatchHaptics.self, from: Data(json.utf8))
        #expect(haptics.disabled == [.countdown])
        #expect(haptics.rememberedFeel(for: .countdown) == .tick)
        #expect(haptics.rememberedFeel(for: .finish) == nil)

        let onlyDisabled = try JSONDecoder().decode(WatchHaptics.self, from: Data(#"{"disabled":["halfway"]}"#.utf8))
        #expect(onlyDisabled == WatchHaptics(halfwayTap: false))
    }

    @Test func equalityIncludesRememberedFeel() {
        let a = WatchHaptics(feels: [.countdown: .tick], disabled: [.countdown])
        let b = WatchHaptics(feels: [:], disabled: [.countdown])
        #expect(a != b)
        #expect(a.overrides == b.overrides)
    }

    @Test func resetClearsBoth() {
        var haptics = WatchHaptics(feels: [.countdown: .tick], disabled: [.countdown, .finish])
        haptics.resetToPreset()
        #expect(haptics == WatchHaptics(preset: haptics.preset))
        #expect(HapticCueEvent.allCases.allSatisfy { haptics.selection(for: $0) == .default })
    }
}
