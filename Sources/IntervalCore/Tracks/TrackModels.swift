import Foundation

/// A per-exercise training track (Phase 7): fixed levels of pre-written sessions, followed
/// at the user's own pace. Pure data: the phone's `TrackEnrollment` snapshots a definition,
/// so updating a bundled track never rewrites anyone's progress.
public struct TrackDefinition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var summary: String
    /// Saved Health activity, and whether the track can be chained (see `isChainable`).
    public var activity: Activity
    /// One level for Run/Walk and Plank; A/B/C for the rep tracks. Levels of one track have
    /// the same number of sessions, so a level change can keep the session index.
    public var levels: [TrackLevel]
    /// Max-reps test that picks the starting level. `nil` when there's only one level.
    public var assessment: TrackAssessment?
    public var cadence: TrackCadence
    /// Guidance only ("rest a day between sessions"); never blocks a start.
    public var minRestDays: Int
    /// Rest before this track when it's chained after another one, e.g. 3:00 before pull-ups.
    public var leadInRest: TimeInterval?
    /// Bumped when bundled content changes, so the phone can offer the newer version.
    public var version: Int

    public init(
        id: UUID,
        name: String,
        summary: String = "",
        activity: Activity,
        levels: [TrackLevel],
        assessment: TrackAssessment? = nil,
        cadence: TrackCadence = .selfPaced,
        minRestDays: Int = 1,
        leadInRest: TimeInterval? = nil,
        version: Int = 1
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.activity = activity
        self.levels = levels
        self.assessment = assessment
        self.cadence = cadence
        self.minRestDays = minRestDays
        self.leadInRest = leadInRest
        self.version = version
    }

    /// Strength-style tracks chain into one workout. Distance activities (Run/Walk) stay a
    /// separate workout, because one HKWorkout has one activity type (DECISIONS 2026-10-09).
    public var isChainable: Bool { !activity.supportsDistance }

    public func level(id: UUID) -> TrackLevel? {
        levels.first { $0.id == id }
    }

    /// The level with `id`, else the first one, so a stale level id never strands an enrolment.
    public func levelOrFirst(id: UUID?) -> TrackLevel? {
        id.flatMap(level(id:)) ?? levels.first
    }

    /// Session count, the same in every level.
    public var sessionCount: Int { levels.first?.sessions.count ?? 0 }
}

public struct TrackLevel: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// "A", "B", "C", or "All levels".
    public var name: String
    /// "0–5 push-ups", "Assisted & negatives".
    public var summary: String
    public var sessions: [TrackSession]

    public init(id: UUID, name: String, summary: String = "", sessions: [TrackSession]) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sessions = sessions
    }

    /// Index of the first session in `week` (1-based), for "jump to week". `nil` if no such week.
    public func firstSessionIndex(week: Int) -> Int? {
        sessions.firstIndex { $0.week == week }
    }

    public var weekCount: Int { sessions.map(\.week).max() ?? 0 }
}

public struct TrackSession: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// 1-based.
    public var week: Int
    /// 1-based day within the week.
    public var day: Int
    /// Coaching text shown before starting.
    public var note: String
    /// One program per session; chaining happens at Start (`TrackChainer`).
    public var program: ProgramSnapshot
    /// A max-reps re-test: its result can move the user to another level
    /// (`TrackAssessment.levelID(forMaxReps:)`), and it never auto-repeats.
    public var isRetest: Bool

    public init(id: UUID, week: Int, day: Int, note: String = "", program: ProgramSnapshot, isRetest: Bool = false) {
        self.id = id
        self.week = week
        self.day = day
        self.note = note
        self.program = program
        self.isRetest = isRetest
    }

    /// "Week 2 · Day 1".
    public var label: String { "Week \(week) · Day \(day)" }
    /// "W2 D1", for History and chained-block labels.
    public var shortLabel: String { "W\(week) D\(day)" }
}

/// The initial max-reps test. The app asks the question (or runs a set) and maps the answer
/// to a level.
public struct TrackAssessment: Codable, Hashable, Sendable {
    /// "How many push-ups can you do in one go, with good form?"
    public var question: String
    /// Lower bounds per level, ascending: a max of `minReps` or more qualifies for that level.
    public var bands: [Band]

    public struct Band: Codable, Hashable, Sendable {
        public var levelID: UUID
        public var minReps: Int

        public init(levelID: UUID, minReps: Int) {
            self.levelID = levelID
            self.minReps = minReps
        }
    }

    public init(question: String, bands: [Band]) {
        self.question = question
        self.bands = bands
    }

    /// The highest level whose band the max reaches; the lowest band below every threshold.
    public func levelID(forMaxReps reps: Int) -> UUID? {
        let sorted = bands.sorted { $0.minReps < $1.minReps }
        return sorted.last { reps >= $0.minReps }?.levelID ?? sorted.first?.levelID
    }
}

/// How often a track wants a session. Drives the "due" badge and reminders only: missed
/// days never block or shift a track (DECISIONS 2026-10-09).
public enum TrackCadence: Codable, Hashable, Sendable {
    case selfPaced
    case timesPerWeek(Int)
    case weekdays(Set<Weekday>)
}

/// `Calendar` weekday numbering: Sunday = 1 … Saturday = 7.
public enum Weekday: Int, Codable, Hashable, Sendable, CaseIterable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    public static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Tags the blocks of a run that belong to one enrolled track session. Block ids, not index
/// ranges, so "Edit before start" reorders and edits in the Builder keep outcomes right as
/// long as the Builder keeps block ids.
public struct TrackRef: Codable, Hashable, Sendable {
    /// The phone's `TrackEnrollment` id.
    public var enrollmentID: UUID
    /// `TrackSession.id` that ran. The phone applies an outcome only while the enrolment's
    /// next session is still this one, so a late Watch result can't advance twice.
    public var sessionID: UUID
    public var blockIDs: [UUID]
    /// "Push-ups · W2 D1", for the summary rows and History block labels.
    public var label: String
    public var isRetest: Bool

    public init(enrollmentID: UUID, sessionID: UUID, blockIDs: [UUID], label: String = "", isRetest: Bool = false) {
        self.enrollmentID = enrollmentID
        self.sessionID = sessionID
        self.blockIDs = blockIDs
        self.label = label
        self.isRetest = isRetest
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enrollmentID = try c.decode(UUID.self, forKey: .enrollmentID)
        sessionID = try c.decode(UUID.self, forKey: .sessionID)
        blockIDs = try c.decodeIfPresent([UUID].self, forKey: .blockIDs) ?? []
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        isRetest = try c.decodeIfPresent(Bool.self, forKey: .isRetest) ?? false
    }
}
