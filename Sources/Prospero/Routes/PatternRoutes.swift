import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import Plot

typealias AuthedContext = AuthenticatedContext<AppRequestContext>

func addPatternRoutes(
    to router: RouterGroup<AuthedContext>,
    db: Database,
    logger: Logging.Logger
) {
    // List current user's patterns
    router.get("/patterns") { request, context -> HTML in
        let userID = context.user.id!
        let patterns = try await ActivityPattern.query(on: db)
            .filter(\.$userID == userID)
            .sort(\.$name)
            .all()
        let pc = await PageContext.from(context, request: request, db: db)
        return PatternListPage(patterns: patterns, pageContext: pc).html
    }

    // New pattern form
    router.get("/patterns/new") { request, context -> HTML in
        let pc = await PageContext.from(context, request: request, db: db)
        return PatternFormPage(pageContext: pc).html
    }

    // Create pattern (assigned to current user)
    router.post("/patterns") { request, context -> Response in
        let input = try await URLEncodedFormDecoder().decode(
            PatternInput.self, from: request, context: context
        )
        let pattern = input.toModel()
        pattern.userID = context.user.id
        try await pattern.save(on: db)
        return .redirect(to: "/patterns", type: .normal)
    }

    // Edit pattern form (only if owned by current user)
    router.get("/patterns/:id/edit") { request, context -> HTML in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.query(on: db)
                .filter(\.$id == id)
                .filter(\.$userID == context.user.id!)
                .first()
        else {
            throw HTTPError(.notFound)
        }
        let pc = await PageContext.from(context, request: request, db: db)
        return PatternFormPage(pattern: pattern, pageContext: pc).html
    }

    // Update pattern
    router.post("/patterns/:id") { request, context -> Response in
        guard let id = context.parameters.get("id", as: UUID.self),
              let pattern = try await ActivityPattern.query(on: db)
                .filter(\.$id == id)
                .filter(\.$userID == context.user.id!)
                .first()
        else {
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
              let pattern = try await ActivityPattern.query(on: db)
                .filter(\.$id == id)
                .filter(\.$userID == context.user.id!)
                .first()
        else {
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
    var tide_height_min: Double?

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
            tideRequirement: TideRequirement(rawValue: tide_requirement ?? "any") ?? .any,
            tideHeightMin: tide_height_min
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
        pattern.tideHeightMin = tide_height_min
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
