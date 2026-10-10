import Foundation

/// Zone boundaries as fractions of max HR. Zone 0 is below the first bound; zone `n` is
/// at or above `lowerBounds[n - 1]`. Defaults match RowUp2's `HRZone` (Z0 < 50%, Z1 50–60%,
/// …, Z5 ≥ 90%). The apps own zone names and colours.
public struct HeartRateZones: Codable, Hashable, Sendable {
    public static let defaultLowerBounds: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]

    public var maxHeartRate: Double
    /// Ascending fractions of `maxHeartRate`.
    public var lowerBounds: [Double]

    public init(maxHeartRate: Double, lowerBounds: [Double] = defaultLowerBounds) {
        self.maxHeartRate = maxHeartRate
        self.lowerBounds = lowerBounds.sorted()
    }

    /// 220 − age, as in RowUp2 `HRZoneService.defaultMaxHR`.
    public init(age: Int, lowerBounds: [Double] = defaultLowerBounds) {
        self.init(maxHeartRate: Double(220 - age), lowerBounds: lowerBounds)
    }

    public var zoneCount: Int { lowerBounds.count + 1 }

    /// Zone index for a reading, or `nil` for missing data.
    public func zone(for bpm: Double) -> Int? {
        guard bpm > 0, maxHeartRate > 0 else { return nil }
        let ratio = bpm / maxHeartRate
        return lowerBounds.lastIndex { ratio >= $0 }.map { $0 + 1 } ?? 0
    }

    /// BPM range of a zone: lower bound inclusive, upper exclusive (`nil` = open-ended).
    /// Out-of-range zones clamp to the nearest valid zone.
    public func bpmRange(zone: Int) -> (lower: Double, upper: Double?) {
        let zone = min(max(zone, 0), lowerBounds.count)
        let lower = zone == 0 ? 0 : lowerBounds[zone - 1] * maxHeartRate
        let upper = zone < lowerBounds.count ? lowerBounds[zone] * maxHeartRate : nil
        return (lower, upper)
    }
}
