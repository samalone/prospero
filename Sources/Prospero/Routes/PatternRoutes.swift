import FluentKit
import Foundation
import Hummingbird
import Plot

func addPatternRoutes(
    to router: Router<BasicRequestContext>,
    db: Database,
    logger: Logging.Logger
) {
    // List all patterns
    router.get("/") { _, _ -> Response in
        .redirect(to: "/patterns")
    }

    router.get("/patterns") { _, _ -> HTML in
        let patterns = try await ActivityPattern.query(on: db)
            .sort(\.$name)
            .all()
        return PatternListPage(patterns: patterns).html
    }

    // New pattern form
    router.get("/patterns/new") { _, _ -> HTML in
        PatternFormPage().html
    }

    // Create pattern
    router.post("/patterns") { request, context -> Response in
        let input = try await URLEncodedFormDecoder().decode(
            PatternInput.self, from: request, context: context
        )
        let pattern = input.toModel()
        try await pattern.save(on: db)
        return .redirect(to: "/patterns", type: .normal)
    }

    // Edit pattern form
    router.get("/patterns/:id/edit") { _, context -> HTML in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.find(id, on: db) else {
            throw HTTPError(.notFound)
        }
        return PatternFormPage(pattern: pattern).html
    }

    // Update pattern
    router.post("/patterns/:id") { request, context -> Response in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.find(id, on: db) else {
            throw HTTPError(.notFound)
        }

        let input = try await URLEncodedFormDecoder().decode(
            PatternInput.self, from: request, context: context
        )
        input.apply(to: pattern)
        try await pattern.save(on: db)
        return .redirect(to: "/patterns", type: .normal)
    }

    // Delete pattern
    router.post("/patterns/:id/delete") { _, context -> Response in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.find(id, on: db) else {
            throw HTTPError(.notFound)
        }
        try await pattern.delete(on: db)
        return .redirect(to: "/patterns", type: .normal)
    }
}

// MARK: - Form Input

struct PatternInput: Decodable {
    var name: String
    var location_name: String?
    var latitude: Double
    var longitude: Double
    var tide_station: String?
    var duration_hours: Double
    var temperature_min: Double?
    var temperature_max: Double?
    var humidity_max: Double?
    var precip_probability_max: Double?
    var wind_speed_min: Double?
    var wind_speed_max: Double?
    var cloud_cover_max: Double?
    var requires_daylight: String?
    var earliest_hour: Int?
    var latest_hour: Int?
    var tide_requirement: String?

    func toModel() -> ActivityPattern {
        ActivityPattern(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: latitude,
            longitude: longitude,
            locationName: location_name?.nilIfEmpty,
            tideStation: tide_station?.nilIfEmpty,
            durationHours: duration_hours,
            temperatureMin: temperature_min,
            temperatureMax: temperature_max,
            humidityMax: humidity_max,
            precipProbabilityMax: precip_probability_max,
            windSpeedMin: wind_speed_min,
            windSpeedMax: wind_speed_max,
            cloudCoverMax: cloud_cover_max,
            requiresDaylight: requires_daylight == "true",
            earliestHour: earliest_hour,
            latestHour: latest_hour,
            tideRequirement: TideRequirement(rawValue: tide_requirement ?? "any") ?? .any
        )
    }

    func apply(to pattern: ActivityPattern) {
        pattern.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pattern.latitude = latitude
        pattern.longitude = longitude
        pattern.locationName = location_name?.nilIfEmpty
        pattern.tideStation = tide_station?.nilIfEmpty
        pattern.durationHours = duration_hours
        pattern.temperatureMin = temperature_min
        pattern.temperatureMax = temperature_max
        pattern.humidityMax = humidity_max
        pattern.precipProbabilityMax = precip_probability_max
        pattern.windSpeedMin = wind_speed_min
        pattern.windSpeedMax = wind_speed_max
        pattern.cloudCoverMax = cloud_cover_max
        pattern.requiresDaylight = requires_daylight == "true"
        pattern.earliestHour = earliest_hour
        pattern.latestHour = latest_hour
        pattern.tideRequirement = TideRequirement(rawValue: tide_requirement ?? "any") ?? .any
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
