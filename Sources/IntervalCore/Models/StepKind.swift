import Foundation

/// What a step is for. Drives phase colour, icon, and haptic in the apps.
public enum StepKind: String, Codable, Hashable, Sendable, CaseIterable {
    case prepare
    case warmup
    case work
    case rest
    case cooldown

    public var label: String {
        switch self {
        case .prepare: "Get Ready"
        case .warmup: "Warm-up"
        case .work: "Work"
        case .rest: "Rest"
        case .cooldown: "Cool-down"
        }
    }

    /// SF Symbol name. A plain string so the package stays UI-free.
    public var iconName: String {
        switch self {
        case .prepare: "timer"
        case .warmup: "sun.max.fill"
        case .work: "flame.fill"
        case .rest: "pause.circle.fill"
        case .cooldown: "snowflake"
        }
    }
}
