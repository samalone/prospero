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
        let pc = PageContext(from: context)
        return PatternListPage(patterns: patterns, pageContext: pc).html
    }

    // New pattern form
    router.get("/patterns/new") { request, context -> HTML in
        let pc = PageContext(from: context)
        return PatternFormPage(pageContext: pc).html
    }

    let hueService = PatternHueService(db: db)

    // Create pattern (assigned to current user)
    router.post("/patterns") { request, context -> Response in
        let input = try await URLEncodedFormDecoder().decode(
            PatternInput.self, from: request, context: context
        )
        let pattern = input.toModel()
        pattern.userID = context.user.id
        try await pattern.save(on: db)
        try await hueService.recomputeHues(userID: context.user.id!)
        return .redirect(to: mountURL("/patterns"), type: .normal)
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
        let pc = PageContext(from: context)
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
        // Recompute in case isHueFixed status changed.
        try await hueService.recomputeHues(userID: context.user.id!)
        return .redirect(to: mountURL("/patterns"), type: .normal)
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
        try await hueService.recomputeHues(userID: context.user.id!)
        return .redirect(to: mountURL("/patterns"), type: .normal)
    }
}

// MARK: - Form Input

/// All optional numeric fields are decoded as String? because HTML forms
/// submit empty strings for blank inputs, and URLEncodedFormDecoder
/// can't parse "" as Double?.
struct PatternInput: Decodable {
    var name: String
    var location_name: String?
    var latitude: String
    var longitude: String
    var tide_station: String?
    var duration_hours: String
    var temperature_min: String?
    var temperature_max: String?
    var humidity_max: String?
    var precip_probability_max: String?
    var wind_speed_min: String?
    var wind_speed_max: String?
    var cloud_cover_max: String?
    var requires_daylight: String?
    var earliest_hour: String?
    var latest_hour: String?
    var tide_requirement: String?
    var tide_height_min: String?
    var hue: String?
    var is_hue_fixed: String?

    func toModel() -> ActivityPattern {
        ActivityPattern(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: Double(latitude) ?? 0,
            longitude: Double(longitude) ?? 0,
            locationName: location_name?.nilIfEmpty,
            tideStation: tide_station?.nilIfEmpty,
            durationHours: Double(duration_hours) ?? 4,
            temperatureMin: temperature_min?.toDouble,
            temperatureMax: temperature_max?.toDouble,
            humidityMax: humidity_max?.toDouble,
            precipProbabilityMax: precip_probability_max?.toDouble,
            windSpeedMin: wind_speed_min?.toDouble,
            windSpeedMax: wind_speed_max?.toDouble,
            cloudCoverMax: cloud_cover_max?.toDouble,
            requiresDaylight: requires_daylight == "true",
            earliestHour: earliest_hour?.toInt,
            latestHour: latest_hour?.toInt,
            tideRequirement: TideRequirement(rawValue: tide_requirement ?? "any") ?? .any,
            tideHeightMin: tide_height_min?.toDouble,
            hue: hue?.toDouble ?? 0,
            isHueFixed: is_hue_fixed == "true"
        )
    }

    func apply(to pattern: ActivityPattern) {
        pattern.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pattern.latitude = Double(latitude) ?? 0
        pattern.longitude = Double(longitude) ?? 0
        pattern.locationName = location_name?.nilIfEmpty
        pattern.tideStation = tide_station?.nilIfEmpty
        pattern.durationHours = Double(duration_hours) ?? 4
        pattern.temperatureMin = temperature_min?.toDouble
        pattern.temperatureMax = temperature_max?.toDouble
        pattern.humidityMax = humidity_max?.toDouble
        pattern.precipProbabilityMax = precip_probability_max?.toDouble
        pattern.windSpeedMin = wind_speed_min?.toDouble
        pattern.windSpeedMax = wind_speed_max?.toDouble
        pattern.cloudCoverMax = cloud_cover_max?.toDouble
        pattern.requiresDaylight = requires_daylight == "true"
        pattern.earliestHour = earliest_hour?.toInt
        pattern.latestHour = latest_hour?.toInt
        pattern.tideRequirement = TideRequirement(rawValue: tide_requirement ?? "any") ?? .any
        pattern.tideHeightMin = tide_height_min?.toDouble
        if let h = hue?.toDouble {
            pattern.hue = h
        }
        pattern.isHueFixed = is_hue_fixed == "true"
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Parse as Double, returning nil for empty or non-numeric strings.
    var toDouble: Double? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Double(trimmed)
    }

    /// Parse as Int, returning nil for empty or non-numeric strings.
    var toInt: Int? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }
}
