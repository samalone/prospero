import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Hourly weather conditions, enriched with tide status.
struct HourlyConditions: Sendable {
    var date: Date
    var temperature: Double       // Fahrenheit
    var humidity: Double          // Percentage 0-100
    var precipProbability: Double // Percentage 0-100
    var windSpeed: Double         // knots
    var windGusts: Double         // knots
    var cloudCover: Double        // Percentage 0-100
    var isDaylight: Bool
    var tideStatus: TideStatus = .unknown
    var tideHeight: Double?  // feet (MLLW datum), nil if no tide data
}

/// Client for the Open-Meteo Forecast API.
actor OpenMeteoClient {
    private var cache: (key: String, data: [HourlyConditions], fetchedAt: Date)?
    private let cacheTTL: TimeInterval = 30 * 60 // 30 minutes

    /// Fetch hourly forecast for the next 14 days.
    func fetchHourlyForecast(
        latitude: Double,
        longitude: Double
    ) async throws -> [HourlyConditions] {
        let cacheKey = "\(latitude),\(longitude)"
        if let cache, cache.key == cacheKey,
           Date().timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return cache.data
        }

        let conditions = try await fetchFromAPI(latitude: latitude, longitude: longitude)
        self.cache = (key: cacheKey, data: conditions, fetchedAt: Date())
        return conditions
    }

    private func fetchFromAPI(
        latitude: Double,
        longitude: Double
    ) async throws -> [HourlyConditions] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "hourly",
                value: "temperature_2m,relative_humidity_2m,precipitation_probability,wind_speed_10m,wind_gusts_10m,cloud_cover,is_day"
            ),
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
        return buildConditions(from: decoded)
    }

    private func buildConditions(from response: OpenMeteoResponse) -> [HourlyConditions] {
        let hourly = response.hourly
        let count = hourly.time.count

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

        // Open-Meteo returns times without timezone suffix for "auto" timezone.
        // Try both with and without timezone designator.
        let fallbackFormatter = DateFormatter()
        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        fallbackFormatter.timeZone = TimeZone(identifier: response.timezone)

        var conditions: [HourlyConditions] = []
        conditions.reserveCapacity(count)

        for i in 0..<count {
            let dateString = hourly.time[i]
            guard let date = formatter.date(from: dateString)
                    ?? fallbackFormatter.date(from: dateString) else {
                continue
            }

            conditions.append(HourlyConditions(
                date: date,
                temperature: hourly.temperature_2m[i],
                humidity: hourly.relative_humidity_2m[i],
                precipProbability: hourly.precipitation_probability[i],
                windSpeed: hourly.wind_speed_10m[i],
                windGusts: hourly.wind_gusts_10m[i],
                cloudCover: hourly.cloud_cover[i],
                isDaylight: hourly.is_day[i] == 1
            ))
        }

        return conditions
    }
}

enum OpenMeteoError: Error {
    case httpError(Int)
}

// MARK: - API Response Types

private struct OpenMeteoResponse: Decodable {
    var timezone: String
    var hourly: HourlyData

    struct HourlyData: Decodable {
        var time: [String]
        var temperature_2m: [Double]
        var relative_humidity_2m: [Double]
        var precipitation_probability: [Double]
        var wind_speed_10m: [Double]
        var wind_gusts_10m: [Double]
        var cloud_cover: [Double]
        var is_day: [Int]
    }
}
