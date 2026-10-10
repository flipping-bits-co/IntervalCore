import Foundation
import Testing
@testable import IntervalCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func roundTrip(_ message: WCMessage) throws -> WCMessage {
    let dictionary = try message.toDictionary()
    // WatchConnectivity only accepts property-list types.
    _ = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    return try WCMessage(dictionary: dictionary)
}

/// Runs `program` for its full length at 1 Hz with a synthetic HR feed, as the Watch would.
private func simulatedResult(_ program: ProgramSnapshot, seconds: Int) -> SessionResult {
    var engine = IntervalEngine(program: program)
    var hr = HeartRateDownsampler()
    engine.start(at: t0)
    for second in 1...seconds {
        engine.tick(at: t0.addingTimeInterval(Double(second)))
        guard !engine.isComplete else { break }
        let bpm = engine.currentStep?.kind == .work ? 150.0 + Double(second % 20) : 120.0 - Double(second % 15)
        engine.updateHeartRate(bpm)
        hr.add(bpm: bpm, offset: engine.totalElapsed, stepIndex: engine.currentIndex)
    }
    if !engine.isComplete { engine.finish(at: t0.addingTimeInterval(Double(seconds))) }
    return SessionResult(
        sessionID: UUID(),
        program: program,
        source: .watch,
        engine: engine,
        startDate: t0,
        endDate: t0.addingTimeInterval(engine.totalElapsed),
        heartRate: hr.finish()
    )
}

struct WCMessageTests {

    @Test func startCommandRoundTrips() throws {
        let start = SessionStart(program: Presets.tabata(activity: .cycling), requestedAt: t0)
        let message = WCMessage.command(.start(start))
        #expect(try roundTrip(message) == message)
        #expect(message.kind == .command)
    }

    @Test(arguments: SessionControl.allCases)
    func controlCommandsRoundTrip(control: SessionControl) throws {
        let message = WCMessage.command(.control(control, sessionID: UUID()))
        #expect(try roundTrip(message) == message)
    }

    @Test func syncProgramsRoundTrips() throws {
        var pinned = Presets.emom(minutes: 12)
        pinned.isPinned = true
        pinned.lastUsedDate = t0
        let loop = ProgramSnapshot(
            name: "",
            activity: .running,
            blocks: [
                IntervalBlock(steps: [IntervalStep(kind: .warmup, end: .time(600))]),
                IntervalBlock(steps: [
                    IntervalStep(kind: .work, end: .distance(meters: 400)),
                    IntervalStep(kind: .rest, end: .heartRateBelow(bpm: 120, maxWait: 120)),
                ], repeats: 2, loopsUntilTarget: true),
            ],
            workoutEnd: .target(.distance(meters: 5000))
        )
        let message = WCMessage.command(.syncPrograms([pinned, loop, Presets.forTime(cap: 900)]))
        #expect(try roundTrip(message) == message)
    }

    @Test func liveSampleRoundTrips() throws {
        var engine = IntervalEngine(program: Presets.forTime())
        engine.start(at: t0)
        engine.advance(by: 15)
        let untimed = LiveSample(sessionID: UUID(), engine: engine, timestamp: t0)
        #expect(untimed.stepRemaining == nil)
        #expect(untimed.heartRate == nil)
        #expect(try roundTrip(.liveSample(untimed)) == .liveSample(untimed))
        #expect(try roundTrip(.liveSample(untimed)).kind == .liveSample)
    }

    @Test func liveSampleMirrorsEngine() {
        var engine = IntervalEngine(program: Presets.tabata(prepare: 0))
        engine.start(at: t0)
        engine.advance(by: 47)
        engine.updateHeartRate(152)
        engine.updateMetrics(distance: 120, calories: 9)
        engine.logRound()
        let sample = LiveSample(sessionID: UUID(), engine: engine, timestamp: t0)
        #expect(sample.status == .running)
        #expect(sample.stepIndex == engine.currentIndex)
        #expect(sample.stepElapsed == 17)
        #expect(sample.stepRemaining == 3)
        #expect(sample.totalElapsed == 47)
        #expect(sample.heartRate == 152)
        #expect(sample.totalDistance == 120)
        #expect(sample.totalCalories == 9)
        #expect(sample.loggedRounds == 1)
        #expect(sample.loopIteration == 1)
    }

    @Test func liveSampleCarriesOverallRemaining() throws {
        var engine = IntervalEngine(program: Presets.tabata())
        engine.start(at: t0)
        engine.advance(by: 40)
        let sample = LiveSample(sessionID: UUID(), engine: engine, timestamp: t0)
        #expect(sample.overallRemaining == engine.remainingEstimate())
        #expect(sample.overallRemaining == DurationEstimate(seconds: 200, isEstimate: false))
        #expect(try roundTrip(.liveSample(sample)) == .liveSample(sample))

        var rowing = IntervalEngine(program: ProgramSnapshot(activity: .rowing, blocks: [
            IntervalBlock(steps: [IntervalStep(kind: .work, end: .distance(meters: 1000))]),
        ]))
        rowing.start(at: t0)
        let paced = LiveSample(sessionID: UUID(), engine: rowing, timestamp: t0, assumptions: EstimateAssumptions(activity: .rowing))
        #expect(paced.overallRemaining == DurationEstimate(seconds: 250, isEstimate: true))
    }

    /// Samples from Watch builds before `overallRemaining` must still decode.
    @Test func liveSampleWithoutOverallRemainingDecodes() throws {
        var engine = IntervalEngine(program: Presets.tabata())
        engine.start(at: t0)
        let sample = LiveSample(sessionID: UUID(), engine: engine, timestamp: t0)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? [String: Any])
        #expect(object.removeValue(forKey: "overallRemaining") != nil)
        let legacy = try JSONDecoder().decode(LiveSample.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(legacy.overallRemaining == nil)
        #expect(legacy.stepIndex == sample.stepIndex)
        #expect(legacy.totalElapsed == sample.totalElapsed)
    }

    @Test func sessionResultRoundTrips() throws {
        let result = simulatedResult(Presets.tabata(), seconds: 300)
        let message = WCMessage.sessionResult(result)
        #expect(try roundTrip(message) == message)
        #expect(message.kind == .sessionResult)
    }

    @Test func dictionaryShape() throws {
        let dictionary = try WCMessage.command(.control(.pause, sessionID: UUID())).toDictionary()
        #expect(dictionary[WCMessage.Key.type] as? String == "command")
        #expect(dictionary[WCMessage.Key.version] as? Int == WCMessage.schemaVersion)
        #expect(dictionary[WCMessage.Key.payload] is Data)
    }

    // MARK: - Rejections

    @Test func rejectsMalformedDictionaries() throws {
        let valid = try WCMessage.command(.control(.end, sessionID: UUID())).toDictionary()
        func attempt(_ edit: (inout [String: Any]) -> Void) -> WCMessage.DecodingError? {
            var d = valid
            edit(&d)
            do {
                _ = try WCMessage(dictionary: d)
                return nil
            } catch let error as WCMessage.DecodingError {
                return error
            } catch {
                return nil
            }
        }

        #expect(attempt { $0[WCMessage.Key.type] = nil } == .missingType)
        #expect(attempt { $0[WCMessage.Key.type] = "ergMetrics" } == .unknownType("ergMetrics"))
        #expect(attempt { $0[WCMessage.Key.version] = nil } == .missingVersion)
        #expect(attempt { $0[WCMessage.Key.version] = WCMessage.schemaVersion + 1 } == .unsupportedVersion(WCMessage.schemaVersion + 1))
        #expect(attempt { $0[WCMessage.Key.payload] = nil } == .missingPayload)
        #expect(attempt { $0[WCMessage.Key.payload] = Data("{}".utf8) }.map {
            if case .invalidPayload = $0 { true } else { false }
        } == true)
        // Wrong payload for the declared type.
        #expect(attempt {
            $0[WCMessage.Key.type] = WCMessage.Kind.liveSample.rawValue
        }.map { if case .invalidPayload = $0 { true } else { false } } == true)
        #expect(attempt { $0[WCMessage.Key.type] = WCMessage.Kind.sessionResult.rawValue } != nil)
    }

    @Test func newerVersionWinsOverUnknownType() throws {
        let future: [String: Any] = [
            WCMessage.Key.type: "workoutPlan",
            WCMessage.Key.version: WCMessage.schemaVersion + 1,
            WCMessage.Key.payload: Data(),
        ]
        #expect(throws: WCMessage.DecodingError.unsupportedVersion(WCMessage.schemaVersion + 1)) {
            try WCMessage(dictionary: future)
        }
    }

    @Test func acceptsOlderVersions() throws {
        var dictionary = try WCMessage.command(.control(.skip, sessionID: UUID())).toDictionary()
        dictionary[WCMessage.Key.version] = 0
        if case .command(.control(.skip, _)) = try WCMessage(dictionary: dictionary) {} else {
            Issue.record("expected skip command")
        }
    }

    // MARK: - HR stream (phone-only sessions)

    @Test func heartRateStreamCommandRoundTrips() throws {
        for enabled in [true, false] {
            let message = WCMessage.command(.heartRateStream(enabled: enabled))
            #expect(try roundTrip(message) == message)
        }
    }

    @Test func heartRateReadingRoundTrips() throws {
        let message = WCMessage.heartRate(HeartRateReading(bpm: 142.5, timestamp: t0))
        #expect(try roundTrip(message) == message)
        #expect(message.kind == .heartRate)
    }
}

struct SessionResultTests {

    @Test func buildsFromEngine() {
        let result = simulatedResult(Presets.tabata(), seconds: 1000)
        #expect(result.completionReason == .finished)
        #expect(result.activeDuration == 240)
        #expect(result.steps.count == 16)
        #expect(result.source == .watch)
        #expect(result.id == result.sessionID)
        #expect(result.endDate.timeIntervalSince(result.startDate) == 240)
    }

    @Test func savedToHealthRoundTrips() throws {
        var result = simulatedResult(Presets.tabata(), seconds: 300)
        #expect(result.savedToHealth == false)
        result.savedToHealth = true
        let (data, metadata) = try WCMessage.sessionResult(result).fileTransfer()
        guard case .sessionResult(let decoded) = try WCMessage(fileData: data, metadata: metadata) else {
            Issue.record("wrong kind"); return
        }
        #expect(decoded.savedToHealth)
        #expect(decoded == result)
    }

    /// Payloads from before `savedToHealth` existed must decode, as not saved.
    @Test func savedToHealthDefaultsToFalseWhenAbsent() throws {
        var result = simulatedResult(Presets.tabata(), seconds: 300)
        result.savedToHealth = true
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as? [String: Any])
        #expect(object.removeValue(forKey: "savedToHealth") != nil)
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SessionResult.self, from: legacy)
        #expect(decoded.savedToHealth == false)
        #expect(decoded.steps == result.steps)
        #expect(decoded.heartRate == result.heartRate)
    }

    @Test func savedToHealthFromEngineInit() {
        var engine = IntervalEngine(program: Presets.tabata())
        engine.start(at: t0)
        let result = SessionResult(sessionID: UUID(), program: Presets.tabata(), source: .watch, engine: engine,
                                   startDate: t0, endDate: t0, heartRate: [], savedToHealth: true)
        #expect(result.savedToHealth)
    }

    @Test func unfinishedEngineCountsAsStopped() {
        var engine = IntervalEngine(program: Presets.tabata())
        engine.start(at: t0)
        let result = SessionResult(sessionID: UUID(), program: Presets.tabata(), source: .phone, engine: engine, startDate: t0, endDate: t0, heartRate: [])
        #expect(result.completionReason == .stopped)
    }

    @Test func heartRateStats() {
        var result = SessionResult(sessionID: UUID(), program: ProgramSnapshot(), source: .phone, startDate: t0, endDate: t0, completionReason: .finished, activeDuration: 0)
        #expect(result.averageHeartRate == nil)
        #expect(result.maxHeartRate == nil)
        #expect(result.minHeartRate == nil)
        result.heartRate = [
            HeartRateSample(offset: 0, bpm: 100, stepIndex: 0),
            HeartRateSample(offset: 5, bpm: 151, stepIndex: 0),
            HeartRateSample(offset: 10, bpm: 160, stepIndex: 1),
        ]
        #expect(result.averageHeartRate == 137)
        #expect(result.maxHeartRate == 160)
        #expect(result.minHeartRate == 100)
    }

    @Test func heartRateSamplesJoinStepRecords() {
        let result = simulatedResult(Presets.workRest(work: 30, rest: 15, rounds: 4, prepare: 0), seconds: 600)
        for sample in result.heartRate {
            let record = result.steps.first { $0.timelineIndex == sample.stepIndex }
            #expect(record != nil)
            if let record {
                #expect(Double(sample.offset) >= record.startOffset)
                #expect(Double(sample.offset) <= record.startOffset + record.duration)
            }
        }
    }
}

struct HeartRateDownsamplerTests {

    @Test func averagesFiveSecondBuckets() {
        var hr = HeartRateDownsampler()
        for second in 0..<12 { hr.add(bpm: Double(100 + second), offset: Double(second), stepIndex: 0) }
        #expect(hr.finish() == [
            HeartRateSample(offset: 0, bpm: 102, stepIndex: 0),
            HeartRateSample(offset: 5, bpm: 107, stepIndex: 0),
            HeartRateSample(offset: 10, bpm: 111, stepIndex: 0),
        ])
    }

    @Test func stepChangeClosesBucket() {
        var hr = HeartRateDownsampler()
        hr.add(bpm: 140, offset: 0, stepIndex: 0)
        hr.add(bpm: 150, offset: 2, stepIndex: 0)
        hr.add(bpm: 120, offset: 3, stepIndex: 1)
        #expect(hr.finish() == [
            HeartRateSample(offset: 0, bpm: 145, stepIndex: 0),
            HeartRateSample(offset: 3, bpm: 120, stepIndex: 1),
        ])
    }

    @Test func ignoresInvalidReadings() {
        var hr = HeartRateDownsampler()
        hr.add(bpm: 0, offset: 0, stepIndex: 0)
        hr.add(bpm: .nan, offset: 1, stepIndex: 0)
        hr.add(bpm: -4, offset: 2, stepIndex: 0)
        #expect(hr.finish().isEmpty)
    }

    @Test func finishTwiceDoesNotDuplicate() {
        var hr = HeartRateDownsampler(interval: 10)
        hr.add(bpm: 130, offset: 0, stepIndex: 0)
        #expect(hr.finish().count == 1)
        #expect(hr.finish().count == 1)
        #expect(hr.samples.count == 1)
    }

    @Test func sampleUsesShortKeys() throws {
        let json = String(decoding: try JSONEncoder().encode(HeartRateSample(offset: 5, bpm: 140, stepIndex: 2)), as: UTF8.self)
        #expect(json.count <= 24)
        #expect(json.contains("\"t\":5"))
    }
}
