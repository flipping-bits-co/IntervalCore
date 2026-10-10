import Foundation

/// Chains the ticked tracks' next sessions into one ordinary program (Phase 7, direction D):
/// their blocks in order with a real rest block per gap, tagged with a `TrackRef` per track.
/// The engine, live screens, Watch, Health and History run it like any other program.
public enum TrackChainer {

    /// Gap rest when neither the next track nor the caller has a length.
    public static let fallbackGap: TimeInterval = 120

    /// One track session to chain.
    public struct Link: Codable, Hashable, Sendable {
        public var enrollmentID: UUID
        public var trackName: String
        public var session: TrackSession
        /// The track's lead-in rest (enrolment override, else `TrackDefinition.leadInRest`).
        public var leadInRest: TimeInterval?
        /// The user's own rest for the gap before this link (edited in Up next). Wins over
        /// everything else; 0 means no rest block.
        public var restBefore: TimeInterval?

        public init(
            enrollmentID: UUID,
            trackName: String,
            session: TrackSession,
            leadInRest: TimeInterval? = nil,
            restBefore: TimeInterval? = nil
        ) {
            self.enrollmentID = enrollmentID
            self.trackName = trackName
            self.session = session
            self.leadInRest = leadInRest
            self.restBefore = restBefore
        }

        /// "Push-ups · W2 D1".
        public var label: String { "\(trackName) · \(session.shortLabel)" }
    }

    /// Where a gap's length came from, so Up next can show "Rest 3:00 (lead-in)" if it wants.
    public enum GapSource: String, Codable, Hashable, Sendable {
        case userSet
        case leadIn
        case lastUsed
        case fallback
    }

    /// The rest between two chained tracks.
    public struct Gap: Codable, Hashable, Sendable {
        /// The link the rest comes before.
        public var beforeEnrollmentID: UUID
        public var seconds: TimeInterval
        public var source: GapSource
        /// The rest block's id; `nil` when `seconds` is 0 and no block was added.
        public var blockID: UUID?
    }

    public struct Chain: Codable, Hashable, Sendable {
        /// Ready to run; `program.trackRefs` holds `refs`.
        public var program: ProgramSnapshot
        public var refs: [TrackRef]
        /// One per gap, in order (`links.count - 1` of them).
        public var gaps: [Gap]
    }

    /// Default rest before `link`: the user's own value, else the track's lead-in rest, else the
    /// length last used for a gap (`lastUsed`), else `fallbackGap`.
    public static func gapRest(before link: Link, lastUsed: TimeInterval?) -> (seconds: TimeInterval, source: GapSource) {
        if let rest = link.restBefore { return (max(0, rest), .userSet) }
        if let rest = link.leadInRest { return (max(0, rest), .leadIn) }
        if let rest = lastUsed { return (max(0, rest), .lastUsed) }
        return (fallbackGap, .fallback)
    }

    /// Builds the chained program. A single link gives that session's program, tagged (use it
    /// for Run/Walk too, so its result advances the track). Pass only chainable tracks
    /// (`TrackDefinition.isChainable`) when there's more than one link.
    ///
    /// - Parameters:
    ///   - lastUsedGap: the caller's remembered gap length, used where no lead-in is set.
    ///   - prepare: a leading Get Ready block, like the presets (0 for none).
    ///   - name: program name; defaults to "Push-ups · W2 D1" or "Push-ups + Pull-ups".
    public static func chain(
        _ links: [Link],
        lastUsedGap: TimeInterval? = nil,
        prepare: TimeInterval = Presets.defaultPrepare,
        name: String? = nil
    ) -> Chain {
        let chainKey = links.map { "\($0.enrollmentID.uuidString)/\($0.session.id.uuidString)" }.joined(separator: "+")
        var blocks: [IntervalBlock] = []
        var refs: [TrackRef] = []
        var gaps: [Gap] = []

        if prepare > 0 {
            blocks.append(IntervalBlock(
                id: StableUUID.make("chain/\(chainKey)/prepare"),
                steps: [IntervalStep(id: StableUUID.make("chain/\(chainKey)/prepare/step"), kind: .prepare, end: .time(prepare))]
            ))
        }

        for (index, link) in links.enumerated() {
            if index > 0 {
                let rest = gapRest(before: link, lastUsed: lastUsedGap)
                var blockID: UUID?
                if rest.seconds > 0 {
                    let key = "chain/\(chainKey)/gap/\(index)"
                    let id = StableUUID.make(key)
                    blocks.append(IntervalBlock(
                        id: id,
                        name: "Rest · next: \(link.trackName)",
                        steps: [IntervalStep(id: StableUUID.make(key + "/step"), kind: .rest, end: .time(rest.seconds))]
                    ))
                    blockID = id
                }
                gaps.append(Gap(beforeEnrollmentID: link.enrollmentID, seconds: rest.seconds, source: rest.source, blockID: blockID))
            }
            let sessionBlocks = link.session.program.blocks
            blocks += sessionBlocks
            refs.append(TrackRef(
                enrollmentID: link.enrollmentID,
                sessionID: link.session.id,
                blockIDs: sessionBlocks.map(\.id),
                label: link.label,
                isRetest: link.session.isRetest
            ))
        }

        let activities = Set(links.map(\.session.program.activity))
        let program = ProgramSnapshot(
            id: StableUUID.make("chain/\(chainKey)"),
            name: name ?? defaultName(links),
            activity: activities.count == 1 ? activities.first ?? .strength : .strength,
            blocks: blocks,
            trackRefs: refs
        )
        return Chain(program: program, refs: refs, gaps: gaps)
    }

    private static func defaultName(_ links: [Link]) -> String {
        if links.count == 1, let link = links.first { return link.label }
        return links.map(\.trackName).joined(separator: " + ")
    }
}
