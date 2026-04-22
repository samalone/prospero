import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// One hour of forecast data, conventionally representing the forward
/// interval `[tick, tick + 1h)`. Each field's type announces how the
/// value relates to time:
///
/// - `PointInTime<T>`: an instantaneous value observed at `tick`.
///   (Open-Meteo calls these "Instant" variables.)
/// - `PrecedingHour<T>`: an aggregate over `[endTime - 1h, endTime)`.
///   Each slot's preceding-hour values use `endTime == tick + 1h`, so
///   they describe the slot itself — values are shifted at ingestion
///   to line up with the slot they characterize, not the Open-Meteo
///   timestamp they were published under.
///
/// Tide fields are populated by `ForecastAssembler`. They're optional
/// because a pattern with no tide station has none.
struct ForecastSlot: Sendable {
    /// Start of the forward hour this slot represents. Equals the
    /// Open-Meteo timestamp of the instant-variable observations.
    let tick: Date

    let temperature: PointInTime<Double>    // Fahrenheit
    let humidity: PointInTime<Double>       // Percentage 0-100
    let windSpeed: PointInTime<Double>      // knots
    let cloudCover: PointInTime<Double>     // Percentage 0-100

    let precipProbability: PrecedingHour<Double>  // Percentage 0-100
    let windGusts: PrecedingHour<Double>          // knots

    var tideStatus: PointInTime<TideStatus>?
    var tideHeight: PointInTime<Double>?          // feet (MLLW datum)
}

/// Sunrise / sunset for a single local calendar day at the forecast
/// location. Provided by Open-Meteo's daily endpoint (real solar physics,
/// not a hand-rolled approximation).
struct SolarDay: Sendable {
    var dayStart: Date   // local midnight
    var sunrise: Date
    var sunset: Date
}

/// Bundle returned by the forecast fetch so callers can get both hourly
/// weather and daily solar times in a single call.
///
/// `timezone` is the IANA zone the forecast is anchored to (returned by
/// Open-Meteo when the request uses `timezone=auto`). Every `Date` in
/// `hourly` and `solar` is a correct absolute instant, but downstream
/// "hour of day", "same local day", and "daylight" logic must evaluate
/// against this zone — not `Calendar.current`, which silently picks up
/// the server's zone.
struct Forecast: Sendable {
    var hourly: [ForecastSlot]
    var solar: [SolarDay]
    var timezone: TimeZone
}

/// Client for the Open-Meteo Forecast API.
///
/// Cached entries expire at the next hour boundary plus a small skew
/// (Open-Meteo publishes new forecast data roughly once per hour; the
/// exact minute varies, so we give it five minutes of slack). This means
/// we never hit the upstream API more than once per hour per location —
/// even if many users ask at different minutes of the same hour — and
/// callers still get data no more than about an hour stale.
actor OpenMeteoClient {
    private struct CacheEntry {
        var data: Forecast
        var expiresAt: Date
    }

    private var cache: [String: CacheEntry] = [:]

    // Dedup concurrent cold-cache callers so N parallel patterns at the
    // same location collapse into one upstream request — CalendarRoutes
    // fetches per-pattern in a TaskGroup, so the check-then-fetch gap
    // would otherwise let several requests slip through.
    private var inflight: [String: Task<Forecast, Error>] = [:]

    private let publishSkew: TimeInterval = 5 * 60

    private static let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal
    }()

    /// Fetch hourly forecast + daily sunrise/sunset for the next 14 days.
    func fetchForecast(
        latitude: Double,
        longitude: Double
    ) async throws -> Forecast {
        let cacheKey = "\(latitude),\(longitude)"
        let now = Date()
        if let entry = cache[cacheKey], entry.expiresAt > now {
            return entry.data
        }
        if let existing = inflight[cacheKey] {
            return try await existing.value
        }

        let task = Task {
            try await fetchFromAPI(latitude: latitude, longitude: longitude)
        }
        inflight[cacheKey] = task
        defer { inflight[cacheKey] = nil }

        let forecast = try await task.value
        cache[cacheKey] = CacheEntry(
            data: forecast,
            expiresAt: nextExpiry(after: now)
        )
        return forecast
    }

    private func nextExpiry(after now: Date) -> Date {
        let cal = Self.utcCalendar
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        let topOfThisHour = cal.date(from: comps) ?? now
        return topOfThisHour.addingTimeInterval(3600 + publishSkew)
    }

    private func fetchFromAPI(
        latitude: Double,
        longitude: Double
    ) async throws -> Forecast {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,relative_humidity_2m,precipitation_probability,wind_speed_10m,wind_gusts_10m,cloud_cover"
            ),
            URLQueryItem(name: "daily", value: "sunrise,sunset"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "precipitation_unit", value: "inch"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "14"),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw OpenMeteoError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        return Forecast(
            hourly: buildHourly(from: decoded),
            solar: buildSolar(from: decoded),
            timezone: TimeZone(identifier: decoded.timezone) ?? .current
        )
    }

    // Open-Meteo's "auto" timezone returns times without a timezone
    // suffix but tagged with the resolved zone in `response.timezone`.
    // Try ISO8601 first, fall back to a naive parser anchored in the
    // reported zone.
    private static func parseTime(_ s: String, tz: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [
            .withFullDate, .withTime,
            .withDashSeparatorInDate, .withColonSeparatorInTime,
        ]
        if let d = iso.date(from: s) { return d }
        let fallback = DateFormatter()
        fallback.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fallback.timeZone = TimeZone(identifier: tz)
        return fallback.date(from: s)
    }

    private func buildHourly(from response: OpenMeteoResponse) -> [ForecastSlot] {
        let hourly = response.hourly
        let count = hourly.time.count
        guard count >= 2 else { return [] }

        // Parse timestamps up front so the per-slot loop can reference
        // neighbors by index without re-parsing.
        var ticks: [Date?] = []
        ticks.reserveCapacity(count)
        for t in hourly.time {
            ticks.append(Self.parseTime(t, tz: response.timezone))
        }

        // Each slot represents the forward hour [ticks[i], ticks[i+1]).
        // Instant variables come from the record at `i` (Open-Meteo's
        // convention: observed AT that instant). Preceding-hour
        // variables come from the record at `i+1` (Open-Meteo's
        // convention: that record's "preceding hour" is exactly our
        // slot's forward hour). The last record has no successor so
        // we emit count - 1 slots.
        var slots: [ForecastSlot] = []
        slots.reserveCapacity(count - 1)
        for i in 0..<(count - 1) {
            guard let tick = ticks[i], let nextTick = ticks[i + 1] else { continue }
            slots.append(ForecastSlot(
                tick: tick,
                temperature: PointInTime(time: tick, value: hourly.temperature_2m[i]),
                humidity: PointInTime(time: tick, value: hourly.relative_humidity_2m[i]),
                windSpeed: PointInTime(time: tick, value: hourly.wind_speed_10m[i]),
                cloudCover: PointInTime(time: tick, value: hourly.cloud_cover[i]),
                precipProbability: PrecedingHour(
                    endTime: nextTick, value: hourly.precipitation_probability[i + 1]
                ),
                windGusts: PrecedingHour(
                    endTime: nextTick, value: hourly.wind_gusts_10m[i + 1]
                )
            ))
        }
        return slots
    }

    private func buildSolar(from response: OpenMeteoResponse) -> [SolarDay] {
        guard let daily = response.daily else { return [] }
        // Open-Meteo's daily `time` is the local calendar date (midnight).
        let tz = TimeZone(identifier: response.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        var result: [SolarDay] = []
        result.reserveCapacity(daily.time.count)
        for i in 0..<daily.time.count {
            guard i < daily.sunrise.count, i < daily.sunset.count,
                  let dayDate = Self.parseTime(daily.time[i] + "T00:00", tz: response.timezone),
                  let sunrise = Self.parseTime(daily.sunrise[i], tz: response.timezone),
                  let sunset = Self.parseTime(daily.sunset[i], tz: response.timezone)
            else { continue }
            result.append(SolarDay(
                dayStart: calendar.startOfDay(for: dayDate),
                sunrise: sunrise,
                sunset: sunset
            ))
        }
        return result
    }
}

enum OpenMeteoError: Error {
    case httpError(Int)
}

// MARK: - API Response Types

private struct OpenMeteoResponse: Decodable {
    var timezone: String
    var hourly: HourlyData
    var daily: DailyData?

    struct HourlyData: Decodable {
        var time: [String]
        var temperature_2m: [Double]
        var relative_humidity_2m: [Double]
        var precipitation_probability: [Double]
        var wind_speed_10m: [Double]
        var wind_gusts_10m: [Double]
        var cloud_cover: [Double]
    }

    struct DailyData: Decodable {
        var time: [String]       // "YYYY-MM-DD"
        var sunrise: [String]    // "YYYY-MM-DDTHH:mm"
        var sunset: [String]
    }
}
