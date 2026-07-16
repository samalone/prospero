import FluentKit

struct AddAirQuality: AsyncMigration {
    func prepare(on database: Database) async throws {
        // One ALTER TABLE per column: SQLite rejects multiple ADD COLUMN
        // clauses in a single statement, so a combined `.field(...).field(...)`
        // fails there. Matches AddTideHeightMin / AddTideHeightMax.
        try await database.schema("activity_patterns")
            .field("air_quality_min", .double)
            .update()
        try await database.schema("activity_patterns")
            .field("air_quality_max", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteField("air_quality_min")
            .update()
        try await database.schema("activity_patterns")
            .deleteField("air_quality_max")
            .update()
    }
}
