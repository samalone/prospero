import FluentKit

struct CreateActivityPatterns: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .id()
            .field("name", .string, .required)
            .field("latitude", .double, .required)
            .field("longitude", .double, .required)
            .field("location_name", .string)
            .field("tide_station", .string)
            .field("duration_hours", .double, .required)
            .field("temperature_min", .double)
            .field("temperature_max", .double)
            .field("humidity_max", .double)
            .field("precip_probability_max", .double)
            .field("wind_speed_min", .double)
            .field("wind_speed_max", .double)
            .field("cloud_cover_max", .double)
            .field("requires_daylight", .bool, .required, .sql(.default(false)))
            .field("earliest_hour", .int)
            .field("latest_hour", .int)
            .field("tide_requirement", .string, .required, .sql(.default("any")))
            .field("hue", .double, .required, .sql(.default(0.0)))
            .field("is_hue_fixed", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns").delete()
    }
}
