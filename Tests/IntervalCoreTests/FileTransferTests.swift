import Foundation
import Testing
@testable import IntervalCore

/// Runs `program` at 1 Hz for up to `seconds` with HR every second through the downsampler.
private func longResult(_ program: ProgramSnapshot, seconds: Int) -> SessionResult {
    let t0 = Date.testEpoch
    var engine = IntervalEngine(program: program)
    var sampler = HeartRateDownsampler()
    engine.start(at: t0)
    sampler.add(bpm: 100, offset: 0, stepIndex: 0)
    for second in 1...seconds {
        engine.tick(at: t0.addingTimeInterval(Double(second)))
        guard !engine.isComplete else { break }
        let bpm = engine.currentStep?.kind == .work ? 155.0 + Double(second % 25) : 125.0 - Double(second % 10)
        sampler.add(bpm: bpm, offset: engine.totalElapsed, stepIndex: engine.currentIndex)
    }
    if !engine.isComplete { engine.finish(at: t0.addingTimeInterval(Double(seconds))) }
    return SessionResult(
        sessionID: UUID(), program: program, source: .watch, engine: engine,
        startDate: t0, endDate: t0.addingTimeInterval(engine.totalElapsed), heartRate: sampler.finish()
    )
}

/// `SessionResult` travels Watch → phone via `transferFile` (no size cap, full 5 s HR).
struct FileTransferTests {

    @Test func resultMetadataIsPlistSafe() throws {
        let result = longResult(Presets.tabata(), seconds: 600)
        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        _ = try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
        #expect(metadata[WCMessage.Key.type] as? String == "sessionResult")
        #expect(metadata[WCMessage.Key.version] as? Int == WCMessage.schemaVersion)
        #expect(WCMessage.sessionID(fromMetadata: metadata) == result.sessionID)
        #expect(metadata[WCMessage.Key.payload] == nil)
        #expect(try WCMessage(fileData: data, metadata: metadata) == .sessionResult(result))
    }

    /// Worst case: 4 h of 20/10 (959 step records, ~2880 HR samples at 5 s), well past
    /// what `transferUserInfo` could take. Must round-trip losslessly and stay sane.
    @Test func fourHourWorstCaseRoundTripsUnderOneMegabyte() throws {
        let result = longResult(Presets.workRest(work: 20, rest: 10, rounds: 480, prepare: 0), seconds: 14_400)
        #expect(result.steps.count >= 959)
        #expect(result.heartRate.count >= 2870)

        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        #expect(data.count < 1_000_000, "\(data.count) bytes")
        #expect(try WCMessage(fileData: data, metadata: metadata) == .sessionResult(result))
    }

    @Test func roundTripsThroughAFile() throws {
        let result = longResult(Presets.workRest(work: 240, rest: 60, rounds: 24, prepare: 0), seconds: 7200)
        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(try WCMessage(fileURL: url, metadata: metadata) == .sessionResult(result))
    }

    @Test func otherMessagesCanUseFilesToo() throws {
        let message = WCMessage.command(.syncPrograms([Presets.tabata(), Presets.emom()]))
        let (data, metadata) = try message.fileTransfer()
        #expect(WCMessage.sessionID(fromMetadata: metadata) == nil)
        #expect(try WCMessage(fileData: data, metadata: metadata) == message)
    }

    @Test func fileErrorsMatchEnvelopeErrors() throws {
        let (data, metadata) = try WCMessage.sessionResult(longResult(Presets.tabata(), seconds: 60)).fileTransfer()

        #expect(throws: WCMessage.DecodingError.missingVersion) { try WCMessage(fileData: data, metadata: nil) }

        var newer = metadata
        newer[WCMessage.Key.version] = WCMessage.schemaVersion + 1
        #expect(throws: WCMessage.DecodingError.unsupportedVersion(WCMessage.schemaVersion + 1)) {
            try WCMessage(fileData: data, metadata: newer)
        }

        var unknown = metadata
        unknown[WCMessage.Key.type] = "ergMetrics"
        #expect(throws: WCMessage.DecodingError.unknownType("ergMetrics")) { try WCMessage(fileData: data, metadata: unknown) }

        #expect(throws: (any Error).self) { try WCMessage(fileData: Data("nope".utf8), metadata: metadata) }
        #expect(throws: (any Error).self) {
            try WCMessage(fileURL: URL(filePath: "/nonexistent/\(UUID().uuidString)"), metadata: metadata)
        }
        #expect(WCMessage.sessionID(fromMetadata: [WCMessage.Key.sessionID: "not-a-uuid"]) == nil)
    }

    @Test func everyKindRoundTripsAsFile() throws {
        let messages: [WCMessage] = [
            .command(.start(SessionStart(program: Presets.tabata(), requestedAt: .testEpoch))),
            .command(.control(.pause, sessionID: UUID())),
            .command(.syncPrograms([Presets.emom()])),
            .command(.heartRateStream(enabled: true)),
            .liveSample(LiveSample(sessionID: UUID(), engine: IntervalEngine(program: Presets.tabata()), timestamp: .testEpoch)),
            .sessionResult(longResult(Presets.tabata(), seconds: 300)),
            .heartRate(HeartRateReading(bpm: 150, timestamp: .testEpoch)),
        ]
        #expect(Set(messages.map(\.kind)) == Set(WCMessage.Kind.allCases))
        for message in messages {
            let (data, metadata) = try message.fileTransfer()
            #expect(try WCMessage(fileData: data, metadata: metadata) == message)
        }
    }

    @Test(arguments: [Data(), Data("{not json".utf8), Data("[1,2,3]".utf8)])
    func emptyOrCorruptFilesFailWithInvalidPayload(data: Data) throws {
        let (_, metadata) = try WCMessage.sessionResult(longResult(Presets.tabata(), seconds: 60)).fileTransfer()
        do {
            _ = try WCMessage(fileData: data, metadata: metadata)
            Issue.record("expected a decoding error")
        } catch let error as WCMessage.DecodingError {
            guard case .invalidPayload = error else { Issue.record("got \(error)"); return }
        }
    }

    @Test func fullResultSurvivesLosslessly() throws {
        let result = longResult(Presets.workRest(work: 30, rest: 15, rounds: 160, prepare: 0), seconds: 7200)
        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        guard case .sessionResult(let decoded) = try WCMessage(fileData: data, metadata: metadata) else {
            Issue.record("wrong kind"); return
        }
        // No re-bucketing: the ~5 s series arrives sample for sample.
        #expect(decoded.heartRate == result.heartRate)
        #expect(decoded.heartRate.count >= 1430)
    }

    // MARK: - Compact StepRecord wire format

    /// Payloads written before defaults were omitted carry every key; they must still decode.
    @Test func stepRecordDecodesFullKeyPayloads() throws {
        let json = #"{"i":2,"l":1,"k":"work","b":0,"r":2,"o":30,"d":20,"e":"timeElapsed","m":0,"c":0}"#
        let decoded = try JSONDecoder().decode(StepRecord.self, from: Data(json.utf8))
        #expect(decoded == StepRecord(timelineIndex: 2, loopIteration: 1, kind: .work, blockIndex: 0, round: 2,
                                      startOffset: 30, duration: 20, endReason: .timeElapsed, distance: 0, calories: 0))
    }


    @Test func stepRecordOmitsDefaults() throws {
        let plain = StepRecord(timelineIndex: 3, loopIteration: 1, kind: .rest, blockIndex: 1, round: 2,
                               startOffset: 19.999999999999996, duration: 10, endReason: .timeElapsed, distance: 0, calories: 0)
        let json = String(decoding: try JSONEncoder().encode(plain), as: UTF8.self)
        #expect(!json.contains("\"l\""))
        #expect(!json.contains("\"e\""))
        #expect(!json.contains("\"m\""))
        #expect(!json.contains("\"c\""))
        #expect(json.contains("\"o\":20"))
        let decoded = try JSONDecoder().decode(StepRecord.self, from: Data(json.utf8))
        #expect(decoded.startOffset == 20)
        #expect(decoded.loopIteration == 1)
        #expect(decoded.endReason == .timeElapsed)
    }

    @Test func stepRecordKeepsNonDefaults() throws {
        let full = StepRecord(timelineIndex: 3, loopIteration: 4, kind: .work, blockIndex: 1, round: 2,
                              startOffset: 120.5, duration: 33.25, endReason: .metricReached, distance: 400, calories: 12)
        #expect(try JSONDecoder().decode(StepRecord.self, from: JSONEncoder().encode(full)) == full)
    }
}
