import FluentKit

struct AddTideHeightMin: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .field("tide_height_min", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("activity_patterns")
            .deleteField("tide_height_min")
            .update()
    }
}
