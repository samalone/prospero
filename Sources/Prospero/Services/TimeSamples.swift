import Foundation

/// Forecast data arrives with distinct time conventions and it's
/// alarmingly easy to treat them uniformly — which silently misaligns
/// values against query windows. These wrapper types make the convention
/// part of the type so a `PrecedingHour<Double>` can never be passed
/// where a `PointInTime<Double>` is expected, and vice versa.
///
/// Conventions as documented by Open-Meteo:
/// - Instant (PointInTime):  temperature, humidity, wind_speed, cloud_cover, is_day
/// - Preceding hour:          precipitation_probability, wind_gusts, precipitation
///
/// These are hour-resolution variants; if we later consume 15-minute
/// data we'd add `PrecedingQuarterHour<T>` etc. A `FollowingHour`
/// variant would also slot in easily but none of our current sources
/// produce values in that convention, so it's deliberately absent.
///
/// On `@inlinable`: this is a single-module executable target and all
/// callers compile with whole-module optimization, so the Swift
/// compiler already inlines these tiny accessors freely. `@inlinable`
/// only matters for library targets where call sites live in another
/// module — adding it here would be ceremony with no measurable effect.

/// A value observed at a specific instant.
struct PointInTime<T: Sendable>: Sendable {
    let time: Date
    let value: T
}

/// A value that aggregates the interval `[endTime - 3600, endTime)`.
/// The sample for `14:00` describes what happened between 13:00 and 14:00.
struct PrecedingHour<T: Sendable>: Sendable {
    let endTime: Date
    let value: T

    var interval: DateInterval {
        DateInterval(start: endTime.addingTimeInterval(-3600), end: endTime)
    }
}

// MARK: - Window queries

extension Array {
    /// Instant samples whose `time` is inside the closed interval
    /// `[window.start, window.end]`. Endpoints are included so that a
    /// 2-hour window starting at 13:00 picks up the 13:00, 14:00, and
    /// 15:00 instants — both boundary ticks plus the interior one. This
    /// is the "fully covered" semantics: a predicate that holds at every
    /// hour tick bracketing the window is treated as holding throughout.
    func bracketing<T>(_ window: DateInterval) -> [PointInTime<T>]
        where Element == PointInTime<T>
    {
        filter { window.start <= $0.time && $0.time <= window.end }
    }

    /// Preceding-hour samples whose covered interval is fully inside
    /// the window. For a window `[13:00, 15:00)`, these are the samples
    /// at `14:00` (covers 13–14) and `15:00` (covers 14–15).
    func covering<T>(_ window: DateInterval) -> [PrecedingHour<T>]
        where Element == PrecedingHour<T>
    {
        filter { sample in
            let iv = sample.interval
            return window.start <= iv.start && iv.end <= window.end
        }
    }
}

// MARK: - Numeric aggregates

extension Array where Element == PointInTime<Double> {
    /// Min/max of the bracketing samples (endpoints included).
    /// Returns nil if no samples bracket the window.
    func extremes(in window: DateInterval) -> (min: Double, max: Double)? {
        let values = bracketing(window).map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return (lo, hi)
    }
}

extension Array where Element == PrecedingHour<Double> {
    func extremes(covering window: DateInterval) -> (min: Double, max: Double)? {
        let values = covering(window).map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return (lo, hi)
    }
}
