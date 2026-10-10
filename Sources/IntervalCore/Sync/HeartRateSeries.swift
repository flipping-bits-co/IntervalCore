import Foundation

/// One downsampled HR point. Short coding keys and whole numbers keep long
/// `SessionResult` files small (a 60-minute series is about 20 KB of JSON).
public struct HeartRateSample: Codable, Hashable, Sendable {
    /// Active seconds since the session started: the same axis as `StepRecord.startOffset`.
    public var offset: Int
    public var bpm: Int
    /// `TimelineStep.index` the sample was taken in.
    public var stepIndex: Int

    public init(offset: Int, bpm: Int, stepIndex: Int) {
        self.offset = offset
        self.bpm = bpm
        self.stepIndex = stepIndex
    }

    private enum CodingKeys: String, CodingKey {
        case offset = "t"
        case bpm = "b"
        case stepIndex = "s"
    }
}

/// Averages raw HR readings into buckets of `interval` seconds. A bucket also closes when
/// the step changes, so no sample mixes two steps (needed for per-step-kind HR zones).
public struct HeartRateDownsampler: Codable, Hashable, Sendable {
    public static let defaultInterval: TimeInterval = 5

    public var interval: TimeInterval
    public private(set) var samples: [HeartRateSample] = []

    private var bucketStart: TimeInterval?
    private var bucketStep: Int = 0
    private var bucketSum: Double = 0
    private var bucketCount: Int = 0

    public init(interval: TimeInterval = defaultInterval) {
        self.interval = interval
    }

    /// `offset` is active time (`IntervalEngine.totalElapsed`) when the reading arrived.
    public mutating func add(bpm: Double, offset: TimeInterval, stepIndex: Int) {
        guard bpm > 0, bpm.isFinite else { return }
        if let start = bucketStart, stepIndex != bucketStep || offset - start >= interval {
            flush()
        }
        if bucketStart == nil {
            bucketStart = offset
            bucketStep = stepIndex
        }
        bucketSum += bpm
        bucketCount += 1
    }

    /// Closes the open bucket and returns every sample.
    public mutating func finish() -> [HeartRateSample] {
        flush()
        return samples
    }

    private mutating func flush() {
        guard let start = bucketStart, bucketCount > 0 else { return }
        samples.append(HeartRateSample(
            offset: Int(start.rounded()),
            bpm: Int((bucketSum / Double(bucketCount)).rounded()),
            stepIndex: bucketStep
        ))
        bucketStart = nil
        bucketSum = 0
        bucketCount = 0
    }
}
