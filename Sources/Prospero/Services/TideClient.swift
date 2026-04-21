import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Tide status for a given point in time.
enum TideStatus: String, Sendable, Codable {
    case rising
    case high
    case falling
    case low
    case unknown
}

/// A high or low tide prediction from NOAA CO-OPS.
struct TidePrediction: Sendable {
    var time: Date
    var height: Double  // feet (MLLW datum)
    var type: TideType

    enum TideType: String, Sendable, Codable {
        case high = "H"
        case low = "L"
    }
}

/// Client for the NOAA CO-OPS Tides & Currents API.
///
/// Fetches high/low tide predictions for a given station and classifies
/// tide status (rising/falling/high/low) for each hour in a forecast window.
/// A point on the 6-minute tide prediction curve from NOAA.
struct TideCurvePoint: Sendable {
    var time: Date
    var height: Double  // feet (MLLW datum)
}

/// Client for NOAA CO-OPS harmonic tide predictions.
///
/// Harmonic predictions are deterministic output from fixed tide
/// constants — the only reason to refetch is that the rolling 14-day
/// window has advanced. A 6-hour TTL keeps the request volume low while
/// guaranteeing the trailing edge of the window is always at least a
/// week ahead of "now."
actor TideClient {
    private struct HiLoEntry {
        var predictions: [TidePrediction]
        var expiresAt: Date
    }
    private struct CurveEntry {
        var points: [TideCurvePoint]
        var expiresAt: Date
    }

    private var hiloCache: [String: HiLoEntry] = [:]
    private var curveCache: [String: CurveEntry] = [:]
    private let cacheTTL: TimeInterval = 6 * 60 * 60 // 6 hours

    /// Fetch high/low tide predictions for the next 14 days.
    func fetchPredictions(station: String) async throws -> [TidePrediction] {
        let now = Date()
        if let entry = hiloCache[station], entry.expiresAt > now {
            return entry.predictions
        }

        let predictions = try await fetchHiLoFromAPI(station: station)
        hiloCache[station] = HiLoEntry(
            predictions: predictions,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        return predictions
    }

    /// Fetch the full 6-minute tide prediction curve for the next 14 days.
    /// This uses NOAA's harmonic model output — the same data used to draw
    /// tide graphs in eyc-weather.
    func fetchTideCurve(station: String) async throws -> [TideCurvePoint] {
        let now = Date()
        if let entry = curveCache[station], entry.expiresAt > now {
            return entry.points
        }

        let points = try await fetchCurveFromAPI(station: station)
        curveCache[station] = CurveEntry(
            points: points,
            expiresAt: now.addingTimeInterval(cacheTTL)
        )
        return points
    }

    /// Look up the tide height at a given date from the 6-minute curve.
    /// Finds the nearest point within 6 minutes.
    static func tideHeight(at date: Date, curve: [TideCurvePoint]) -> Double? {
        // Binary search for the closest point.
        var lo = 0
        var hi = curve.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if curve[mid].time < date {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        // lo is now the first point >= date. Check it and the one before.
        let candidates = [lo - 1, lo].filter { $0 >= 0 && $0 < curve.count }
        guard let closest = candidates.min(by: {
            abs(curve[$0].time.timeIntervalSince(date)) < abs(curve[$1].time.timeIntervalSince(date))
        }) else {
            return nil
        }
        // Only return if within 6 minutes.
        if abs(curve[closest].time.timeIntervalSince(date)) <= 6 * 60 {
            return curve[closest].height
        }
        return nil
    }

    /// Classify the tide status for a given date based on high/low predictions.
    ///
    /// Uses the trmnl-tides algorithm: if within 30 minutes of a high/low,
    /// report that status; otherwise report rising (next is high) or
    /// falling (next is low).
    static func tideStatus(at date: Date, predictions: [TidePrediction]) -> TideStatus {
        // Find the next prediction after this date.
        guard let nextIndex = predictions.firstIndex(where: { $0.time > date }) else {
            return .unknown
        }

        let next = predictions[nextIndex]
        let interval = next.time.timeIntervalSince(date)

        // Within 30 minutes of the next extreme → call it that status.
        if interval < 30 * 60 {
            return next.type == .high ? .high : .low
        }

        // Also check if we're within 30 minutes past the previous extreme.
        if nextIndex > 0 {
            let prev = predictions[nextIndex - 1]
            let sincePrev = date.timeIntervalSince(prev.time)
            if sincePrev < 30 * 60 {
                return prev.type == .high ? .high : .low
            }
        }

        // Otherwise, rising toward high or falling toward low.
        return next.type == .high ? .rising : .falling
    }

    // MARK: - API

    private func fetchHiLoFromAPI(station: String) async throws -> [TidePrediction] {
        // Validate station ID is numeric.
        guard station.allSatisfy(\.isNumber) else {
            throw TideClientError.invalidStation
        }

        let now = Date()
        let endDate = now.addingTimeInterval(14 * 24 * 60 * 60)

        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "station", value: station),
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "application", value: "Prospero"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "interval", value: "hilo"),
            URLQueryItem(name: "begin_date", value: Self.formatQueryDate(now)),
            URLQueryItem(name: "end_date", value: Self.formatQueryDate(endDate)),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw TideClientError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(HighLowResponse.self, from: data)
        return decoded.predictions.compactMap { pred in
            guard let date = Self.responseFormatter.date(from: pred.t),
                  let height = Double(pred.v),
                  let type = TidePrediction.TideType(rawValue: pred.type) else {
                return nil
            }
            return TidePrediction(time: date, height: height, type: type)
        }
    }

    private func fetchCurveFromAPI(station: String) async throws -> [TideCurvePoint] {
        guard station.allSatisfy(\.isNumber) else {
            throw TideClientError.invalidStation
        }

        let now = Date()
        let endDate = now.addingTimeInterval(14 * 24 * 60 * 60)

        // Fetch the full 6-minute prediction curve (no interval=hilo).
        var components = URLComponents(string: "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter")!
        components.queryItems = [
            URLQueryItem(name: "station", value: station),
            URLQueryItem(name: "product", value: "predictions"),
            URLQueryItem(name: "datum", value: "MLLW"),
            URLQueryItem(name: "time_zone", value: "gmt"),
            URLQueryItem(name: "units", value: "english"),
            URLQueryItem(name: "application", value: "Prospero"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "begin_date", value: Self.formatQueryDate(now)),
            URLQueryItem(name: "end_date", value: Self.formatQueryDate(endDate)),
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)

        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            throw TideClientError.httpError(httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(CurveResponse.self, from: data)
        return decoded.predictions.compactMap { pred in
            guard let date = Self.responseFormatter.date(from: pred.t),
                  let height = Double(pred.v) else {
                return nil
            }
            return TideCurvePoint(time: date, height: height)
        }
    }

    // MARK: - Date Formatting

    /// CO-OPS query parameter format: "yyyyMMdd HH:mm" in GMT, with space as +.
    private static let queryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func formatQueryDate(_ date: Date) -> String {
        queryFormatter.string(from: date)
    }

    /// CO-OPS response format: "yyyy-MM-dd HH:mm" in GMT.
    private static let responseFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
}

enum TideClientError: Error {
    case invalidStation
    case httpError(Int)
}

// MARK: - API Response Types

private struct HighLowResponse: Decodable {
    var predictions: [Prediction]

    struct Prediction: Decodable {
        var t: String   // "2026-04-16 12:34"
        var v: String   // "4.569"
        var type: String // "H" or "L"
    }
}

private struct CurveResponse: Decodable {
    var predictions: [Prediction]

    struct Prediction: Decodable {
        var t: String   // "2026-04-16 12:34"
        var v: String   // "4.569"
    }
}
