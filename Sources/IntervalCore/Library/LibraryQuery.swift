import Foundation

/// What `LibraryQuery` needs from a saved program. The phone's SwiftData model can
/// conform directly, or map to `LibraryItem`.
public protocol LibraryRankable {
    var id: UUID { get }
    var structureHash: String { get }
    var lastUsedDate: Date? { get }
    var useCount: Int { get }
    var isPinned: Bool { get }
    var isBundled: Bool { get }
}

/// Plain value form of `LibraryRankable` (Watch cache, tests).
public struct LibraryItem: LibraryRankable, Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var structureHash: String
    public var lastUsedDate: Date?
    public var useCount: Int
    public var isPinned: Bool
    public var isBundled: Bool

    public init(
        id: UUID = UUID(),
        structureHash: String = "",
        lastUsedDate: Date? = nil,
        useCount: Int = 0,
        isPinned: Bool = false,
        isBundled: Bool = false
    ) {
        self.id = id
        self.structureHash = structureHash
        self.lastUsedDate = lastUsedDate
        self.useCount = useCount
        self.isPinned = isPinned
        self.isBundled = isBundled
    }
}

/// Library sections, in display order.
public struct LibrarySections<Item: LibraryRankable> {
    public var pinned: [Item]
    public var recents: [Item]
    /// Bundled programs, in catalog (input) order.
    public var templates: [Item]
    /// User programs that are neither pinned nor in recents, best first.
    public var others: [Item]
}

extension LibrarySections: Sendable where Item: Sendable {}

/// The one ranking helper for the Library (F10). It replaces RowUp2's copy-pasted
/// `recencyWeight`, whose unbounded `0.3 × useCount` term let an old, often-used
/// program outrank yesterday's.
///
/// score = 0.5^(age / halfLife) × (1 + ln(1 + useCount)). Recency decays smoothly, and
/// frequency helps with diminishing returns. Never-used items score 0.
public struct LibraryQuery: Hashable, Sendable {
    public static let defaultHalfLife: TimeInterval = 14 * 86_400
    public static let defaultRecentsLimit = 5

    public var now: Date
    public var halfLife: TimeInterval

    public init(now: Date, halfLife: TimeInterval = defaultHalfLife) {
        self.now = now
        self.halfLife = halfLife
    }

    public func score(_ item: some LibraryRankable) -> Double {
        guard let lastUsed = item.lastUsedDate else { return 0 }
        let age = max(0, now.timeIntervalSince(lastUsed))
        let recency = halfLife > 0 ? pow(0.5, age / halfLife) : 0
        let frequency = 1 + log(1 + Double(max(0, item.useCount)))
        return recency * frequency
    }

    /// Best first. Ties: most recently used, then input order (stable).
    public func ranked<Item: LibraryRankable>(_ items: [Item]) -> [Item] {
        items.enumerated()
            .map { (offset: $0.offset, item: $0.element, score: score($0.element)) }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                let aDate = a.item.lastUsedDate ?? .distantPast
                let bDate = b.item.lastUsedDate ?? .distantPast
                if aDate != bDate { return aDate > bDate }
                return a.offset < b.offset
            }
            .map(\.item)
    }

    /// Used, not pinned, one per `structureHash` (the best-ranked copy wins), best first.
    /// Pinned items have their own section. Empty hashes are never merged.
    public func recents<Item: LibraryRankable>(_ items: [Item], limit: Int = defaultRecentsLimit) -> [Item] {
        var seen = Set<String>()
        var result: [Item] = []
        for item in ranked(items.filter { $0.lastUsedDate != nil && !$0.isPinned }) {
            guard result.count < limit else { break }
            if !item.structureHash.isEmpty {
                guard seen.insert(item.structureHash).inserted else { continue }
            }
            result.append(item)
        }
        return result
    }

    /// Pinned items, best first.
    public func pinned<Item: LibraryRankable>(_ items: [Item]) -> [Item] {
        ranked(items.filter(\.isPinned))
    }

    /// Splits the library into its sections. Pinned, recents, and others never overlap.
    /// Templates is the full bundled catalog, so a pinned or recent template shows there too.
    public func sections<Item: LibraryRankable>(_ items: [Item], recentsLimit: Int = defaultRecentsLimit) -> LibrarySections<Item> {
        let pinned = pinned(items)
        let recents = recents(items, limit: recentsLimit)
        let shown = Set(pinned.map(\.id)).union(recents.map(\.id))
        return LibrarySections(
            pinned: pinned,
            recents: recents,
            templates: items.filter(\.isBundled),
            others: ranked(items.filter { !$0.isBundled && !shown.contains($0.id) })
        )
    }
}
