import Foundation

/// Locale-independent duration and distance strings shared by both apps.
public enum DurationFormatter {

    /// "0:45", "1:00", "12:30", "1:05:00". Truncates fractions (elapsed-style).
    /// Kept from RowUp2 `WorkoutSegment.formatDuration`, plus hours.
    public static func clock(_ seconds: TimeInterval) -> String {
        format(Int(max(0, seconds).rounded(.down)))
    }

    /// Countdown display: rounds up, so 59.2 s left shows "1:00" and the
    /// display reaches "0:00" exactly when the step ends.
    public static func countdown(_ seconds: TimeInterval) -> String {
        format(Int(max(0, seconds).rounded(.up)))
    }

    /// "45s", "1 min", "18 min", "1 h 5 min". For totals and list rows.
    public static func short(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        if total < 60 { return "\(total)s" }
        let minutes = (total + 30) / 60
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m) min"
    }

    /// "18 min" or "~18 min" when the total includes guesses (F8).
    public static func estimate(_ estimate: DurationEstimate) -> String {
        (estimate.isEstimate ? "~" : "") + short(estimate.seconds)
    }

    /// "400m", "1.5 km", "10 km".
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded()))m" }
        let km = meters / 1000
        let rounded = (km * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) km" : String(format: "%.1f km", rounded)
    }

    private static func format(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
