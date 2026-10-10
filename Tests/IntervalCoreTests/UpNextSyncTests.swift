import Foundation
import Testing
@testable import IntervalCore

struct UpNextSyncTests {
    private let push = UUID(uuidString: "00000000-0000-4000-8000-0000000000C1")!
    private let run = UUID(uuidString: "00000000-0000-4000-8000-0000000000C2")!

    private func link(_ track: TrackDefinition, _ enrollment: UUID) -> TrackChainer.Link {
        TrackChainer.Link(enrollmentID: enrollment, trackName: track.name, session: track.levels[0].sessions[0], leadInRest: track.leadInRest)
    }

    private var upNext: WatchUpNext {
        let pushLink = link(BundledTracks.pushUps, push)
        let runLink = link(BundledTracks.runWalk, run)
        return WatchUpNext(
            chained: TrackChainer.chain([pushLink]).program,
            items: [
                .init(enrollmentID: push, trackName: "Push-ups", sessionLabel: "W1 D1",
                      program: TrackChainer.chain([pushLink]).program, isDue: true),
                .init(enrollmentID: run, trackName: "Run / Walk", sessionLabel: "W1 D1",
                      program: TrackChainer.chain([runLink]).program, isDue: false),
            ],
            generatedAt: .testEpoch
        )
    }

    @Test func contextCarriesUpNextNextToProgramsAndSettings() throws {
        let programs = [Presets.tabata()]
        let settings = WatchSettings(haptics: WatchHaptics(preset: .max))
        let context = try WCMessage.applicationContext(programs: programs, settings: settings, upNext: upNext)
        _ = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)

        #expect(try WCMessage(dictionary: context) == .command(.syncPrograms(programs)))
        #expect(WatchSettings(applicationContext: context) == settings)
        let received = WatchUpNext(applicationContext: context)
        #expect(received == upNext)
        #expect(received.items.map(\.activity) == [.strength, .running])
        #expect(received.items.map(\.id) == [push, run])
        #expect(received.chained?.trackRefs?.first?.enrollmentID == push)
        #expect(received.items[1].program.trackRefs?.first?.enrollmentID == run)
    }

    @Test func missingOrUnreadableIsEmpty() throws {
        let legacy = try WCMessage.applicationContext(programs: [], settings: WatchSettings())
        #expect(legacy[WatchUpNext.contextKey] == nil)
        #expect(WatchUpNext(applicationContext: legacy).isEmpty)

        var context = legacy
        context[WatchUpNext.contextKey] = Data("garbage".utf8)
        #expect(WatchUpNext(applicationContext: context) == WatchUpNext())
        context[WatchUpNext.contextKey] = "not data"
        #expect(WatchUpNext(applicationContext: context).isEmpty)
    }

    @Test func partialPayloadsDecode() throws {
        let empty = try JSONDecoder().decode(WatchUpNext.self, from: Data("{}".utf8))
        #expect(empty.isEmpty)
        #expect(empty.generatedAt == nil)

        // A newer phone may add fields; an item missing optional ones still decodes.
        let program = String(decoding: try JSONEncoder().encode(Presets.tabata()), as: UTF8.self)
        let json = #"{"items":[{"enrollmentID":"00000000-0000-4000-8000-0000000000C1","program":\#(program),"badge":"new"}],"theme":1}"#
        let decoded = try JSONDecoder().decode(WatchUpNext.self, from: Data(json.utf8))
        #expect(decoded.items.count == 1)
        #expect(decoded.items[0].trackName.isEmpty)
        #expect(!decoded.items[0].isDue)
        #expect(!decoded.isEmpty)
    }
}
