import Foundation

/// Phone → Watch "Up next" (Phase 7): today's chained strength workout plus each active track's
/// next session, ready to start as they are. Every program carries its `trackRefs`, so the
/// Watch's `SessionResult` advances the right tracks when the phone applies `TrackOutcome`.
/// Travels in the same application context as programs and settings, under `contextKey`.
public struct WatchUpNext: Codable, Hashable, Sendable {

    public struct Item: Codable, Hashable, Identifiable, Sendable {
        public var enrollmentID: UUID
        public var trackName: String
        /// "W2 D1".
        public var sessionLabel: String
        /// A single-link `TrackChainer` chain, tagged.
        public var program: ProgramSnapshot
        public var isDue: Bool

        public var id: UUID { enrollmentID }
        /// Run / Walk shows as its own workout; strength items are already in `chained`.
        public var activity: Activity { program.activity }

        public init(enrollmentID: UUID, trackName: String, sessionLabel: String, program: ProgramSnapshot, isDue: Bool) {
            self.enrollmentID = enrollmentID
            self.trackName = trackName
            self.sessionLabel = sessionLabel
            self.program = program
            self.isDue = isDue
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enrollmentID = try c.decode(UUID.self, forKey: .enrollmentID)
            trackName = try c.decodeIfPresent(String.self, forKey: .trackName) ?? ""
            sessionLabel = try c.decodeIfPresent(String.self, forKey: .sessionLabel) ?? ""
            program = try c.decode(ProgramSnapshot.self, forKey: .program)
            isDue = try c.decodeIfPresent(Bool.self, forKey: .isDue) ?? false
        }
    }

    /// The ticked-by-default strength tracks chained into one program; `nil` when none are due.
    public var chained: ProgramSnapshot?
    /// One per active track, in Up next order.
    public var items: [Item]
    public var generatedAt: Date?

    public init(chained: ProgramSnapshot? = nil, items: [Item] = [], generatedAt: Date? = nil) {
        self.chained = chained
        self.items = items
        self.generatedAt = generatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        chained = try c.decodeIfPresent(ProgramSnapshot.self, forKey: .chained)
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
    }

    public var isEmpty: Bool { chained == nil && items.isEmpty }

    /// Application-context key, next to the `syncPrograms` envelope and `WatchSettings.contextKey`.
    public static let contextKey = "watchUpNext"

    /// Reads Up next from a received application context. Missing (older phone) or unreadable
    /// gives an empty Up next.
    public init(applicationContext: [String: Any]) {
        guard let data = applicationContext[Self.contextKey] as? Data,
              let decoded = try? JSONDecoder().decode(WatchUpNext.self, from: data) else {
            self.init()
            return
        }
        self = decoded
    }
}
