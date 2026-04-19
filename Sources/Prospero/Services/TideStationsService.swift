import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging

/// Slim representation of a NOAA CO-OPS tide prediction station.
///
/// Only the fields needed to render a pin on the map and populate the
/// tide-station form field. Pruning the wire payload ~10× (2 MB → 200 KB).
struct TideStationSummary: Sendable, Codable {
    var id: String
    var name: String
    var state: String?
    var lat: Double
    var lng: Double
}

/// Fetch + cache NOAA CO-OPS tide prediction stations.
///
/// Stations change rarely; we pull the full list once at startup, cache
/// it for 24 hours, and re-fetch lazily thereafter. The cached payload
/// is handed straight back on every request to `/patterns/tide-stations.json`.
actor TideStationsService {
    private let logger: Logger
    private let cacheTTL: TimeInterval = 60 * 60 * 24  // 24 hours

    private var cache: (stations: [TideStationSummary], fetchedAt: Date)?
    /// Pre-encoded JSON payload for cheap response serving.
    private var cachedJSON: Data?

    init(logger: Logger) {
        self.logger = logger
    }

    /// Return the cached stations, fetching if the cache is empty or stale.
    func stations() async throws -> [TideStationSummary] {
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return cache.stations
        }
        return try await refresh()
    }

    /// Return the cached stations as a preserialized JSON payload. Much
    /// cheaper than re-encoding on every request; the client-side Leaflet
    /// code fetches this once per page load.
    func stationsJSON() async throws -> Data {
        if let cachedJSON, let cache, Date().timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return cachedJSON
        }
        _ = try await refresh()
        return cachedJSON ?? Data("[]".utf8)
    }

    @discardableResult
    private func refresh() async throws -> [TideStationSummary] {
        let url = URL(string:
            "https://api.tidesandcurrents.noaa.gov/mdapi/prod/webapi/stations.json?type=tidepredictions&units=english"
        )!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Prospero/1.0 (+https://propercourse.app/prospero)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NSError(domain: "TideStationsService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "NOAA MDAPI returned non-200"
            ])
        }

        let decoded = try JSONDecoder().decode(MDAPIResponse.self, from: data)
        let pruned = decoded.stations.map { full in
            TideStationSummary(
                id: full.id,
                name: full.name,
                state: full.state,
                lat: full.lat,
                lng: full.lng
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        self.cachedJSON = try encoder.encode(pruned)
        self.cache = (stations: pruned, fetchedAt: Date())
        logger.info("Fetched \(pruned.count) NOAA tide stations")
        return pruned
    }
}

// MARK: - Wire format

/// The raw NOAA MDAPI response has many fields we don't need (product
/// lists, affiliations, disclaimers, …). We decode just what we want.
private struct MDAPIResponse: Decodable {
    var stations: [RawStation]
}

private struct RawStation: Decodable {
    var id: String
    var name: String
    var state: String?
    var lat: Double
    var lng: Double
}
