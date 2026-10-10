import Foundation
import Testing
@testable import IntervalCore

private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let day: TimeInterval = 86_400

private func item(
    daysAgo: Double?,
    uses: Int = 1,
    hash: String = UUID().uuidString,
    pinned: Bool = false,
    bundled: Bool = false
) -> LibraryItem {
    LibraryItem(
        structureHash: hash,
        lastUsedDate: daysAgo.map { now.addingTimeInterval(-$0 * day) },
        useCount: uses,
        isPinned: pinned,
        isBundled: bundled
    )
}

struct LibraryQueryTests {
    let query = LibraryQuery(now: now)

    // MARK: - Score

    @Test func neverUsedScoresZero() {
        #expect(query.score(item(daysAgo: nil, uses: 50)) == 0)
    }

    @Test func scoreHalvesEveryHalfLife() {
        let fresh = query.score(item(daysAgo: 0, uses: 3))
        let old = query.score(item(daysAgo: 14, uses: 3))
        #expect(abs(old - fresh / 2) < 1e-12)
        #expect(abs(fresh - (1 + log(4.0))) < 1e-12)
    }

    @Test func futureDatesCountAsNow() {
        // Clock skew from another device mustn't push a score above "used just now".
        #expect(query.score(item(daysAgo: -3)) == query.score(item(daysAgo: 0)))
    }

    @Test func zeroHalfLifeScoresZero() {
        #expect(LibraryQuery(now: now, halfLife: 0).score(item(daysAgo: 0)) == 0)
    }

    @Test func negativeUseCountTreatedAsZero() {
        #expect(query.score(item(daysAgo: 0, uses: -5)) == 1)
    }

    /// Regression for RowUp2's `0.7·recency + 0.3·useCount`, where 10 uses two months ago
    /// (score 3.0) beat a single use yesterday (≈ 0.98).
    @Test func yesterdayBeatsOftenUsedLongAgo() {
        let stale = item(daysAgo: 60, uses: 10)
        let yesterday = item(daysAgo: 1, uses: 1)
        #expect(query.ranked([stale, yesterday]).map(\.id) == [yesterday.id, stale.id])
    }

    @Test func frequencyBreaksSameDayTies() {
        let once = item(daysAgo: 2, uses: 1)
        let often = item(daysAgo: 2, uses: 12)
        #expect(query.ranked([once, often]).first?.id == often.id)
    }

    @Test func frequentStillBeatsSlightlyNewer() {
        // 20 uses three days ago vs a one-off today: habit wins over a small recency gap.
        let habit = item(daysAgo: 3, uses: 20)
        let oneOff = item(daysAgo: 0, uses: 1)
        #expect(query.ranked([oneOff, habit]).first?.id == habit.id)
    }

    // MARK: - Ordering

    @Test func tiesFallBackToRecencyThenInputOrder() {
        let a = item(daysAgo: nil, uses: 0)
        let b = item(daysAgo: nil, uses: 0)
        let c = item(daysAgo: nil, uses: 0)
        #expect(query.ranked([a, b, c]).map(\.id) == [a.id, b.id, c.id])

        // Equal scores (both decayed to 0 far in the past) but different dates.
        let ancient = LibraryItem(lastUsedDate: now.addingTimeInterval(-1e7 * day), useCount: 1)
        let lessAncient = LibraryItem(lastUsedDate: now.addingTimeInterval(-1e6 * day), useCount: 1)
        #expect(query.score(ancient) == query.score(lessAncient))
        #expect(query.ranked([ancient, lessAncient]).map(\.id) == [lessAncient.id, ancient.id])
    }

    // MARK: - Recents

    @Test func recentsExcludePinnedAndUnused() {
        let pinned = item(daysAgo: 0, pinned: true)
        let unused = item(daysAgo: nil)
        let used = item(daysAgo: 1)
        #expect(query.recents([pinned, unused, used]).map(\.id) == [used.id])
    }

    @Test func recentsDedupeByStructureHashKeepingBest() {
        let older = item(daysAgo: 10, uses: 1, hash: "tabata")
        let newer = item(daysAgo: 1, uses: 1, hash: "tabata")
        let other = item(daysAgo: 5, uses: 1, hash: "emom")
        #expect(query.recents([older, other, newer]).map(\.id) == [newer.id, other.id])
    }

    @Test func emptyHashesAreNotMerged() {
        let a = item(daysAgo: 1, hash: "")
        let b = item(daysAgo: 2, hash: "")
        #expect(query.recents([a, b]).count == 2)
    }

    @Test func recentsRespectLimit() {
        let items = (0..<10).map { item(daysAgo: Double($0)) }
        #expect(query.recents(items).map(\.id) == items.prefix(5).map(\.id))
        #expect(query.recents(items, limit: 2).count == 2)
        #expect(query.recents(items, limit: 0).isEmpty)
    }

    @Test func usedTemplatesAppearInRecents() {
        let template = item(daysAgo: 1, bundled: true)
        #expect(query.recents([template]).map(\.id) == [template.id])
    }

    // MARK: - Sections

    @Test func sectionsSplitTheLibrary() {
        let pinned = item(daysAgo: 30, uses: 4, pinned: true)
        let pinnedFresh = item(daysAgo: 0, uses: 4, pinned: true)
        let recent = item(daysAgo: 1)
        let neverUsed = item(daysAgo: nil, uses: 0)
        let template = item(daysAgo: nil, uses: 0, bundled: true)
        let usedTemplate = item(daysAgo: 2, bundled: true)
        let duplicate = item(daysAgo: 9, hash: recent.structureHash)

        let s = query.sections([pinned, recent, neverUsed, template, usedTemplate, pinnedFresh, duplicate])
        #expect(s.pinned.map(\.id) == [pinnedFresh.id, pinned.id])
        #expect(s.recents.map(\.id) == [recent.id, usedTemplate.id])
        #expect(s.templates.map(\.id) == [template.id, usedTemplate.id])
        // The deduped copy and the never-used program still have a home.
        #expect(s.others.map(\.id) == [duplicate.id, neverUsed.id])
    }

    @Test func pinnedRecentsAndOthersNeverOverlap() {
        let items = (0..<30).map { i in
            item(daysAgo: i % 4 == 0 ? nil : Double(i), uses: i % 5, hash: "h\(i % 7)", pinned: i % 6 == 0, bundled: i % 9 == 0)
        }
        let s = query.sections(items, recentsLimit: 8)
        let ids = (s.pinned + s.recents + s.others).map(\.id)
        #expect(Set(ids).count == ids.count)
        // Every user program lands somewhere.
        let userIds = Set(items.filter { !$0.isBundled }.map(\.id))
        #expect(userIds.isSubset(of: Set(ids)))
    }

    @Test func worksWithReferenceTypes() {
        final class Program: LibraryRankable {
            let id = UUID()
            var structureHash = "x"
            var lastUsedDate: Date? = now
            var useCount = 2
            var isPinned = false
            var isBundled = false
        }
        let p = Program()
        #expect(query.sections([p]).recents.first === p)
    }

    @Test func itemRoundTripsThroughJSON() throws {
        let original = item(daysAgo: 3, uses: 7, hash: "abc", pinned: true, bundled: true)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(LibraryItem.self, from: data) == original)
    }
}
