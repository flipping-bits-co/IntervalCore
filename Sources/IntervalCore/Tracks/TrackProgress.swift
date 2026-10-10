import Foundation

/// Where an enrolment stands: the next session, % complete, and whether it's due today.
/// "Due" is a hint for Up next's pre-ticks and reminders; nothing here ever blocks a start.
public struct TrackProgress: Codable, Hashable, Sendable {

    public enum Due: Codable, Hashable, Sendable {
        /// Pre-tick it in Up next.
        case due
        /// Inside the track's rest-day guidance; due again from `until` (start of that day).
        case resting(until: Date)
        /// `.timesPerWeek(n)` already met this week.
        case weeklyGoalMet
        /// `.weekdays` cadence and today isn't one; `next` is the next scheduled day's start.
        case notScheduledToday(next: Date?)
        /// Every session is done.
        case finished

        public var isDue: Bool { self == .due }
    }

    public var level: TrackLevel?
    /// Clamped to `0...totalSessions`.
    public var nextSessionIndex: Int
    public var nextSession: TrackSession?
    public var totalSessions: Int
    public var due: Due

    /// Sessions done (the index of the next one).
    public var completedSessions: Int { nextSessionIndex }
    public var isFinished: Bool { nextSession == nil }
    /// 0…1.
    public var fractionComplete: Double {
        totalSessions > 0 ? Double(nextSessionIndex) / Double(totalSessions) : 0
    }

    /// - Parameters:
    ///   - levelID: the enrolment's level; an unknown id falls back to the first level.
    ///   - nextSessionIndex: the enrolment's index into the level's sessions.
    ///   - completions: when this track's sessions were done (advanced or repeated).
    ///   - cadence: the enrolment's override, else the definition's.
    public init(
        definition: TrackDefinition,
        levelID: UUID?,
        nextSessionIndex: Int,
        completions: [Date] = [],
        cadence: TrackCadence? = nil,
        now: Date,
        calendar: Calendar = .current
    ) {
        let level = definition.levelOrFirst(id: levelID)
        let sessions = level?.sessions ?? []
        let index = min(max(0, nextSessionIndex), sessions.count)
        self.level = level
        self.nextSessionIndex = index
        self.nextSession = sessions.indices.contains(index) ? sessions[index] : nil
        self.totalSessions = sessions.count
        self.due = nextSession == nil ? .finished : Self.due(
            cadence: cadence ?? definition.cadence,
            minRestDays: definition.minRestDays,
            completions: completions,
            now: now,
            calendar: calendar
        )
    }

    static func due(
        cadence: TrackCadence,
        minRestDays: Int,
        completions: [Date],
        now: Date,
        calendar: Calendar
    ) -> Due {
        let today = calendar.startOfDay(for: now)
        if minRestDays > 0, let last = completions.filter({ $0 <= now }).max(),
           let until = calendar.date(byAdding: .day, value: minRestDays + 1, to: calendar.startOfDay(for: last)),
           today < until {
            return .resting(until: until)
        }
        switch cadence {
        case .selfPaced:
            return .due
        case .timesPerWeek(let target):
            guard target > 0, let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return .due }
            let thisWeek = completions.filter { week.contains($0) && $0 <= now }.count
            return thisWeek >= target ? .weeklyGoalMet : .due
        case .weekdays(let days):
            guard !days.isEmpty else { return .due }
            let weekday = calendar.component(.weekday, from: now)
            if days.contains(where: { $0.rawValue == weekday }) { return .due }
            let next = (1...7).lazy
                .compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
                .first { date in days.contains { $0.rawValue == calendar.component(.weekday, from: date) } }
            return .notScheduledToday(next: next)
        }
    }
}
