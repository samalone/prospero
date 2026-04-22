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
}
