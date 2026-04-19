import FluentKit
import Foundation

enum TideRequirement: String, Codable, CaseIterable, Sendable {
    case any
    case rising
    case falling
    case high
    case low
    case notLow
}

final class ActivityPattern: Model, @unchecked Sendable {
    static let schema = "activity_patterns"

    @ID(key: .id)
    var id: UUID?

    @OptionalField(key: "user_id")
    var userID: UUID?

    @Field(key: "name")
    var name: String

    @Field(key: "latitude")
    var latitude: Double

    @Field(key: "longitude")
    var longitude: Double

    @OptionalField(key: "location_name")
    var locationName: String?

    @OptionalField(key: "tide_station")
    var tideStation: String?

    @Field(key: "duration_hours")
    var durationHours: Double

    // Weather constraints (nil = unconstrained)

    @OptionalField(key: "temperature_min")
    var temperatureMin: Double?

    @OptionalField(key: "temperature_max")
    var temperatureMax: Double?

    @OptionalField(key: "humidity_max")
    var humidityMax: Double?

    @OptionalField(key: "precip_probability_max")
    var precipProbabilityMax: Double?

    @OptionalField(key: "precip_probability_min")
    var precipProbabilityMin: Double?

    @OptionalField(key: "wind_speed_min")
    var windSpeedMin: Double?

    @OptionalField(key: "wind_speed_max")
    var windSpeedMax: Double?

    @OptionalField(key: "cloud_cover_max")
    var cloudCoverMax: Double?

    // Scheduling constraints

    @Field(key: "requires_daylight")
    var requiresDaylight: Bool

    @OptionalField(key: "earliest_hour")
    var earliestHour: Int?

    @OptionalField(key: "latest_hour")
    var latestHour: Int?

    @Field(key: "tide_requirement")
    var tideRequirement: TideRequirement

    @OptionalField(key: "tide_height_min")
    var tideHeightMin: Double?

    @OptionalField(key: "tide_height_max")
    var tideHeightMax: Double?

    /// Hue angle (0..<360) for this pattern's color in UI elements.
    /// Auto-assigned to maximize visual distinction from other patterns
    /// unless the user has pinned it via `isHueFixed`.
    @Field(key: "hue")
    var hue: Double

    /// Whether the hue is pinned by the user. When false, the hue is
    /// recomputed when the set of patterns changes.
    @Field(key: "is_hue_fixed")
    var isHueFixed: Bool

    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?

    init() {}

    init(
        id: UUID? = nil,
        name: String,
        latitude: Double,
        longitude: Double,
        locationName: String? = nil,
        tideStation: String? = nil,
        durationHours: Double,
        temperatureMin: Double? = nil,
        temperatureMax: Double? = nil,
        humidityMax: Double? = nil,
        precipProbabilityMin: Double? = nil,
        precipProbabilityMax: Double? = nil,
        windSpeedMin: Double? = nil,
        windSpeedMax: Double? = nil,
        cloudCoverMax: Double? = nil,
        requiresDaylight: Bool = false,
        earliestHour: Int? = nil,
        latestHour: Int? = nil,
        tideRequirement: TideRequirement = .any,
        tideHeightMin: Double? = nil,
        tideHeightMax: Double? = nil,
        hue: Double = 0,
        isHueFixed: Bool = false
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.tideStation = tideStation
        self.durationHours = durationHours
        self.temperatureMin = temperatureMin
        self.temperatureMax = temperatureMax
        self.humidityMax = humidityMax
        self.precipProbabilityMin = precipProbabilityMin
        self.precipProbabilityMax = precipProbabilityMax
        self.windSpeedMin = windSpeedMin
        self.windSpeedMax = windSpeedMax
        self.cloudCoverMax = cloudCoverMax
        self.requiresDaylight = requiresDaylight
        self.earliestHour = earliestHour
        self.latestHour = latestHour
        self.tideRequirement = tideRequirement
        self.tideHeightMin = tideHeightMin
        self.tideHeightMax = tideHeightMax
        self.hue = hue
        self.isHueFixed = isHueFixed
    }
}
